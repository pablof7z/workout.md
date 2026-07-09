//! Coach engine — a rig.rs-backed LLM coaching turn loop exposed to the
//! native iOS shell through a UniFFI facade.
//!
//! Shape of the surface:
//! - [`ProviderConfig`] + [`CoachEngine::configure_coach`] select and
//!   authenticate a provider (OpenRouter or Ollama) and a model name.
//! - [`CoachEngine::send_message`] runs one streaming coach turn on a
//!   background tokio runtime owned by the engine. Every event (text delta,
//!   tool call, completion, error) is pushed to a Swift-implemented
//!   [`CoachSink`]; nothing is returned synchronously and nothing blocks the
//!   caller's thread.
//! - Tool calls the model makes (`adjust_set`, `skip_set`,
//!   `deload_exercise`, `add_note`, `edit_plan` — see [`tools`]) are routed
//!   through a Swift-implemented [`CoachHost`], because tool side effects
//!   live in the app's `WorkoutSession`, not in this crate. The multi-turn
//!   tool loop itself is rig's own (`Agent::stream_prompt(..).multi_turn(_)`)
//!   — this crate does not hand-roll a second copy of it.

mod tools;

use std::sync::{Arc, Mutex, Once};

use futures::StreamExt;
use rig::agent::MultiTurnStreamItem;
use rig::client::CompletionClient;
use rig::completion::{CompletionModel, GetTokenUsage};
use rig::message::Message as RigMessage;
use rig::providers::{ollama, openrouter};
use rig::streaming::{StreamedAssistantContent, StreamingPrompt};
use serde::Deserialize;

use tools::{AddNoteTool, AdjustSetTool, DeloadExerciseTool, EditPlanTool, SkipSetTool};

/// Default dry, terse coach voice (per the product spec: direct and sparse,
/// never motivational filler). Swift may override this per-call by passing a
/// different `system_prompt` to [`CoachEngine::send_message`].
pub const DEFAULT_COACH_SYSTEM_PROMPT: &str = "You are the athlete's strength coach. Be direct \
and terse — state what changed and why in as few words as possible. No hype, no emoji, no \
filler praise. When a change to a set or the plan is warranted, call the matching tool instead \
of describing the change in prose; use prose only for the reasoning the athlete needs to hear. \
Never invent data you were not given.";

/// Exposes [`DEFAULT_COACH_SYSTEM_PROMPT`] to Swift (UniFFI proc-macro export
/// does not carry plain `const` items across the FFI boundary).
#[uniffi::export]
pub fn default_coach_system_prompt() -> String {
    DEFAULT_COACH_SYSTEM_PROMPT.to_string()
}

/// Maximum number of tool round-trips the model may take in a single
/// `send_message` turn before the turn is forced to conclude. Keeps a
/// misbehaving model from looping forever against the host.
const MAX_TOOL_TURNS: usize = 6;

static INSTALL_RUSTLS_RING_PROVIDER: Once = Once::new();

/// Installs `ring` as the process-wide default rustls crypto provider.
///
/// This crate depends on reqwest's `rustls-no-provider` feature specifically
/// to avoid pulling in `aws-lc-rs` (see the `Cargo.toml` comment on the
/// `rig-core`/`reqwest`/`rustls` dependency block for why: `aws-lc-sys`'s
/// assembly does not link for the `aarch64-apple-ios` device target). That
/// feature choice means rustls has no default crypto provider installed
/// until something does so explicitly — this is that call. Idempotent and
/// cheap; safe to call from every `CoachEngine::new()`.
fn ensure_rustls_ring_provider() {
    INSTALL_RUSTLS_RING_PROVIDER.call_once(|| {
        // `install_default` only fails if a (different) provider was already
        // installed, which is harmless here — either way, some provider is
        // now installed.
        let _ = rustls::crypto::ring::default_provider().install_default();
    });
}

/// Provider selection + credentials for the coach engine.
///
/// Deliberately has no `#[derive(Debug)]` — see the hand-written [`fmt::Debug`]
/// impl below, which redacts API keys. Never log a `ProviderConfig` any other
/// way.
#[derive(uniffi::Enum, Clone)]
pub enum ProviderConfig {
    OpenRouter {
        api_key: String,
        base_url: Option<String>,
    },
    Ollama {
        base_url: String,
        api_key: Option<String>,
    },
}

impl std::fmt::Debug for ProviderConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ProviderConfig::OpenRouter { base_url, .. } => f
                .debug_struct("OpenRouter")
                .field("api_key", &"<redacted>")
                .field("base_url", base_url)
                .finish(),
            ProviderConfig::Ollama { base_url, api_key } => f
                .debug_struct("Ollama")
                .field("base_url", base_url)
                .field("api_key", &api_key.as_ref().map(|_| "<redacted>"))
                .finish(),
        }
    }
}

/// Streaming sink the Swift app implements to receive coach turn events.
/// Every method is called from the engine's background tokio runtime, never
/// from the thread that called `send_message`.
#[uniffi::export(callback_interface)]
pub trait CoachSink: Send + Sync {
    /// A chunk of assistant text as it streams in. Deltas within one turn
    /// concatenate to the final `on_completed` text.
    fn on_text_delta(&self, delta: String);
    /// The model invoked a tool. `args_json` is the raw JSON argument
    /// object. Fired for UI display; the tool call is executed against
    /// `CoachHost` independently of this notification.
    fn on_tool_call(&self, name: String, args_json: String);
    /// The turn finished normally. `full_text` is the concatenated assistant
    /// text of the final turn (a turn that ends purely on tool calls with no
    /// closing prose yields an empty string).
    fn on_completed(&self, full_text: String);
    /// The turn failed. `message` is safe to show to the user — it never
    /// contains API keys or other `ProviderConfig` contents.
    fn on_error(&self, message: String);
}

/// Tool-execution host the Swift app implements. Every coach tool call is
/// routed here because tool side effects belong to the app's
/// `WorkoutSession`, not to this crate; the returned string is fed back to
/// the model as the tool result.
#[uniffi::export(callback_interface)]
pub trait CoachHost: Send + Sync {
    fn apply_tool(&self, name: String, args_json: String) -> String;
}

#[derive(Default)]
struct EngineState {
    provider: Option<ProviderConfig>,
    model: String,
}

/// The coach engine. One instance owns a dedicated background tokio runtime
/// used for every `send_message` call, so streaming a coach turn never
/// blocks the Swift caller's thread (typically the main/UI thread).
#[derive(uniffi::Object)]
pub struct CoachEngine {
    state: Mutex<EngineState>,
    runtime: tokio::runtime::Runtime,
}

#[uniffi::export]
impl CoachEngine {
    #[uniffi::constructor]
    pub fn new() -> Self {
        ensure_rustls_ring_provider();
        Self {
            state: Mutex::new(EngineState::default()),
            runtime: tokio::runtime::Builder::new_multi_thread()
                .worker_threads(2)
                .thread_name("workout-core-coach")
                .enable_all()
                .build()
                .expect("failed to start coach engine tokio runtime"),
        }
    }

    /// Configure (or reconfigure) the provider and model used by future
    /// `send_message` calls. Safe to call again mid-lifetime (e.g. the user
    /// changes provider in Settings) — takes effect on the next turn.
    pub fn configure_coach(&self, provider: ProviderConfig, model: String) {
        let mut state = self.state.lock().expect("coach engine state poisoned");
        state.provider = Some(provider);
        state.model = model;
    }

    /// Stream one coach turn. Returns immediately; every event is delivered
    /// to `sink` from this engine's background runtime. Tool calls the model
    /// makes are routed through `host`.
    ///
    /// `history_json` is a JSON array of `{"role": "user"|"assistant", "content": "..."}`
    /// objects, oldest first. Pass `"[]"` for a fresh conversation.
    pub fn send_message(
        &self,
        system_prompt: String,
        user_message: String,
        history_json: String,
        sink: Box<dyn CoachSink>,
        host: Box<dyn CoachHost>,
    ) {
        // UniFFI callback interfaces cross the FFI boundary as `Box<dyn _>`,
        // but the turn loop below shares `host` across five tool instances
        // and both callbacks need to outlive this call (they're used from a
        // spawned task) — promote each to an `Arc` once, up front.
        let sink: Arc<dyn CoachSink> = Arc::from(sink);
        let host: Arc<dyn CoachHost> = Arc::from(host);

        let configured = {
            let state = self.state.lock().expect("coach engine state poisoned");
            state
                .provider
                .clone()
                .map(|provider| (provider, state.model.clone()))
        };

        let Some((provider, model)) = configured else {
            sink.on_error(
                "coach is not configured — call configure_coach before send_message".to_string(),
            );
            return;
        };

        self.runtime.spawn(async move {
            run_turn(
                provider,
                model,
                system_prompt,
                user_message,
                history_json,
                sink,
                host,
            )
            .await;
        });
    }
}

impl Default for CoachEngine {
    fn default() -> Self {
        Self::new()
    }
}

/// Parses `history_json` into rig chat messages. An empty/blank string is
/// treated as "no history" rather than an error, so callers can always pass
/// `"[]"` (or `""`) for a fresh conversation.
fn parse_history(history_json: &str) -> Result<Vec<RigMessage>, String> {
    #[derive(Deserialize)]
    struct HistoryEntry {
        role: String,
        content: String,
    }

    let trimmed = history_json.trim();
    if trimmed.is_empty() {
        return Ok(Vec::new());
    }

    let entries: Vec<HistoryEntry> =
        serde_json::from_str(trimmed).map_err(|e| format!("malformed history_json: {e}"))?;

    Ok(entries
        .into_iter()
        .map(|entry| match entry.role.as_str() {
            "assistant" => RigMessage::assistant(entry.content),
            _ => RigMessage::user(entry.content),
        })
        .collect())
}

/// Builds the provider client + agent (with the full coach tool set
/// attached) and runs the streaming turn loop, dispatching every event to
/// `sink`. Never panics on provider/network failure — reports it to
/// `sink.on_error` instead, since this runs detached on a background task.
async fn run_turn(
    provider: ProviderConfig,
    model: String,
    system_prompt: String,
    user_message: String,
    history_json: String,
    sink: Arc<dyn CoachSink>,
    host: Arc<dyn CoachHost>,
) {
    let history = match parse_history(&history_json) {
        Ok(history) => history,
        Err(err) => {
            sink.on_error(err);
            return;
        }
    };

    match provider {
        ProviderConfig::Ollama { base_url, api_key } => {
            let client = ollama::Client::builder()
                .api_key(api_key.unwrap_or_default())
                .base_url(base_url)
                .build();
            let client = match client {
                Ok(client) => client,
                Err(err) => {
                    sink.on_error(format!("failed to start Ollama client: {err}"));
                    return;
                }
            };
            let agent = client
                .agent(model)
                .preamble(&system_prompt)
                .tool(AdjustSetTool::new(host.clone()))
                .tool(SkipSetTool::new(host.clone()))
                .tool(DeloadExerciseTool::new(host.clone()))
                .tool(AddNoteTool::new(host.clone()))
                .tool(EditPlanTool::new(host))
                .build();
            run_stream(agent, user_message, history, sink).await;
        }
        ProviderConfig::OpenRouter { api_key, base_url } => {
            let mut builder = openrouter::Client::builder().api_key(api_key);
            if let Some(base_url) = base_url {
                builder = builder.base_url(base_url);
            }
            let client = match builder.build() {
                Ok(client) => client,
                Err(err) => {
                    sink.on_error(format!("failed to start OpenRouter client: {err}"));
                    return;
                }
            };
            let agent = client
                .agent(model)
                .preamble(&system_prompt)
                .tool(AdjustSetTool::new(host.clone()))
                .tool(SkipSetTool::new(host.clone()))
                .tool(DeloadExerciseTool::new(host.clone()))
                .tool(AddNoteTool::new(host.clone()))
                .tool(EditPlanTool::new(host))
                .build();
            run_stream(agent, user_message, history, sink).await;
        }
    }
}

/// Drives rig's own multi-turn streaming tool loop
/// (`Agent::stream_prompt(..).with_history(..).multi_turn(..)`) to
/// completion, translating each stream item into a [`CoachSink`] callback.
/// Generic over the provider's `CompletionModel` so both Ollama and
/// OpenRouter share this one loop.
async fn run_stream<M>(
    agent: rig::agent::Agent<M>,
    user_message: String,
    history: Vec<RigMessage>,
    sink: Arc<dyn CoachSink>,
) where
    M: CompletionModel + 'static,
    M::StreamingResponse: GetTokenUsage + Send + 'static,
{
    let mut stream = agent
        .stream_prompt(user_message)
        .with_history(history)
        .multi_turn(MAX_TOOL_TURNS)
        .await;

    let mut full_text = String::new();
    while let Some(item) = stream.next().await {
        match item {
            Ok(MultiTurnStreamItem::StreamAssistantItem(StreamedAssistantContent::Text(text))) => {
                full_text.push_str(&text.text);
                sink.on_text_delta(text.text);
            }
            Ok(MultiTurnStreamItem::StreamAssistantItem(StreamedAssistantContent::ToolCall {
                tool_call,
                ..
            })) => {
                sink.on_tool_call(
                    tool_call.function.name,
                    tool_call.function.arguments.to_string(),
                );
            }
            Ok(MultiTurnStreamItem::FinalResponse(response)) => {
                sink.on_completed(response.response().to_string());
                return;
            }
            Ok(_) => {}
            Err(err) => {
                sink.on_error(err.to_string());
                return;
            }
        }
    }

    // Defensive: the stream ended without an explicit `FinalResponse` item
    // (should not happen in practice). Surface whatever text we accumulated
    // rather than silently dropping the turn.
    sink.on_completed(full_text);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn provider_config_debug_never_contains_the_api_key() {
        let provider = ProviderConfig::OpenRouter {
            api_key: "sk-super-secret-value".to_string(),
            base_url: None,
        };
        let debug = format!("{provider:?}");
        assert!(!debug.contains("sk-super-secret-value"));
        assert!(debug.contains("redacted"));

        let provider = ProviderConfig::Ollama {
            base_url: "http://localhost:11434".to_string(),
            api_key: Some("ollama-secret".to_string()),
        };
        let debug = format!("{provider:?}");
        assert!(!debug.contains("ollama-secret"));
        assert!(debug.contains("redacted"));
    }

    #[test]
    fn parse_history_treats_blank_input_as_no_history() {
        assert_eq!(parse_history("").unwrap().len(), 0);
        assert_eq!(parse_history("   ").unwrap().len(), 0);
        assert_eq!(parse_history("[]").unwrap().len(), 0);
    }

    #[test]
    fn parse_history_maps_roles_and_preserves_order() {
        let history = parse_history(
            r#"[{"role":"user","content":"hi"},{"role":"assistant","content":"hello"}]"#,
        )
        .expect("valid history_json should parse");
        assert_eq!(history.len(), 2);
        assert!(matches!(history[0], RigMessage::User { .. }));
        assert!(matches!(history[1], RigMessage::Assistant { .. }));
    }

    #[test]
    fn parse_history_rejects_malformed_json() {
        let err = parse_history("not json").unwrap_err();
        assert!(err.contains("malformed history_json"));
    }

    #[test]
    fn parse_history_defaults_unknown_roles_to_user() {
        let history = parse_history(r#"[{"role":"system","content":"weird"}]"#)
            .expect("unknown roles should default rather than error");
        assert!(matches!(history[0], RigMessage::User { .. }));
    }

    #[test]
    fn default_system_prompt_matches_exported_constant() {
        assert_eq!(default_coach_system_prompt(), DEFAULT_COACH_SYSTEM_PROMPT);
    }

    /// `send_message` before `configure_coach` must report an error through
    /// the sink synchronously rather than panicking or silently no-op'ing —
    /// the Swift host still needs to see something happened.
    #[test]
    fn send_message_before_configure_reports_error_to_sink() {
        use std::sync::Mutex as StdMutex;

        struct UnusedHost;
        impl CoachHost for UnusedHost {
            fn apply_tool(&self, _name: String, _args_json: String) -> String {
                panic!("host should not be called when the engine is unconfigured");
            }
        }

        let engine = CoachEngine::new();
        let errors: Arc<StdMutex<Vec<String>>> = Arc::new(StdMutex::new(Vec::new()));

        struct ForwardingSink {
            errors: Arc<StdMutex<Vec<String>>>,
        }
        impl CoachSink for ForwardingSink {
            fn on_text_delta(&self, _delta: String) {}
            fn on_tool_call(&self, _name: String, _args_json: String) {}
            fn on_completed(&self, _full_text: String) {}
            fn on_error(&self, message: String) {
                self.errors.lock().unwrap().push(message);
            }
        }

        engine.send_message(
            "system".to_string(),
            "hello".to_string(),
            "[]".to_string(),
            Box::new(ForwardingSink {
                errors: errors.clone(),
            }),
            Box::new(UnusedHost),
        );

        let recorded = errors.lock().unwrap();
        assert_eq!(recorded.len(), 1);
        assert!(recorded[0].contains("not configured"));
    }
}
