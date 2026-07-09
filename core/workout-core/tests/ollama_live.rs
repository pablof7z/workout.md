//! Gated live integration test: exercises the full `CoachEngine::send_message`
//! streaming path — provider client construction, rig's Ollama completion
//! model, the multi-turn streaming loop, and every `CoachSink` callback —
//! against a real, locally reachable Ollama endpoint.
//!
//! Skips (rather than failing) when nothing answers at
//! `http://127.0.0.1:11434`, per the task's testing requirements: a live LLM
//! is optional and must never gate `cargo test`. See `src/coach/mod.rs` and
//! `src/coach/tools.rs` for the always-run unit tests that cover the same
//! code paths (history parsing, tool routing, error reporting) without a
//! live model.

use std::net::TcpStream;
use std::sync::mpsc;
use std::time::Duration;

use workout_core::coach::{CoachEngine, CoachHost, CoachSink, ProviderConfig};

const OLLAMA_HOST: &str = "127.0.0.1:11434";
// A model available on the author's local Ollama instance at development
// time. It happens to be cloud-proxied by Ollama itself, but that's an
// implementation detail of *that* model — the endpoint under test is the
// local Ollama HTTP API, which is exactly what `ProviderConfig::Ollama`
// talks to via rig's `ollama` provider. Swap this for any locally-served
// model name to exercise this test fully offline.
const TEST_MODEL: &str = "deepseek-v4-flash:cloud";

fn ollama_reachable() -> bool {
    let Ok(addr) = OLLAMA_HOST.parse() else {
        return false;
    };
    TcpStream::connect_timeout(&addr, Duration::from_millis(500)).is_ok()
}

enum Event {
    TextDelta,
    ToolCall(String, String),
    Completed(String),
    Error(String),
}

struct ChannelSink(mpsc::Sender<Event>);

impl CoachSink for ChannelSink {
    fn on_text_delta(&self, _delta: String) {
        let _ = self.0.send(Event::TextDelta);
    }
    fn on_tool_call(&self, name: String, args_json: String) {
        let _ = self.0.send(Event::ToolCall(name, args_json));
    }
    fn on_completed(&self, full_text: String) {
        let _ = self.0.send(Event::Completed(full_text));
    }
    fn on_error(&self, message: String) {
        let _ = self.0.send(Event::Error(message));
    }
}

struct UnusedHost;

impl CoachHost for UnusedHost {
    fn apply_tool(&self, name: String, args_json: String) -> String {
        panic!("this turn should not need a tool call, got {name} ({args_json})");
    }
}

#[test]
fn streams_a_real_completion_through_the_full_coach_engine_surface() {
    if !ollama_reachable() {
        eprintln!(
            "SKIPPED: no Ollama instance reachable at http://{OLLAMA_HOST} — this test only \
             runs when a local Ollama is available. The always-run unit tests in \
             src/coach/mod.rs and src/coach/tools.rs cover the same code paths without a live \
             model."
        );
        return;
    }

    let engine = CoachEngine::new();
    engine.configure_coach(
        ProviderConfig::Ollama {
            base_url: format!("http://{OLLAMA_HOST}"),
            api_key: None,
        },
        TEST_MODEL.to_string(),
    );

    let (tx, rx) = mpsc::channel();
    engine.send_message(
        "Reply with exactly the single word OK and nothing else.".to_string(),
        "Say the word.".to_string(),
        "[]".to_string(),
        Box::new(ChannelSink(tx)),
        Box::new(UnusedHost),
    );

    let mut saw_delta = false;
    let final_text = loop {
        match rx.recv_timeout(Duration::from_secs(45)) {
            Ok(Event::TextDelta) => saw_delta = true,
            Ok(Event::ToolCall(name, args)) => {
                panic!("unexpected tool call {name} ({args}) for a plain text turn")
            }
            Ok(Event::Completed(text)) => break text,
            Ok(Event::Error(message)) => panic!("coach turn reported an error: {message}"),
            Err(_) => panic!("timed out waiting for the coach turn to complete"),
        }
    };

    assert!(saw_delta, "expected at least one streamed text delta");
    assert!(
        !final_text.trim().is_empty(),
        "final response text should not be empty"
    );
}

/// Records every `apply_tool` invocation it receives via a channel, so the
/// test thread can assert on them without touching shared mutable state from
/// the engine's background runtime thread.
struct RecordingHost(mpsc::Sender<(String, String)>);

impl CoachHost for RecordingHost {
    fn apply_tool(&self, name: String, args_json: String) -> String {
        let _ = self.0.send((name.clone(), args_json));
        format!("{name} applied")
    }
}

#[test]
fn a_tool_call_is_routed_through_the_real_coach_host() {
    if !ollama_reachable() {
        eprintln!(
            "SKIPPED: no Ollama instance reachable at http://{OLLAMA_HOST} — see \
             `streams_a_real_completion_through_the_full_coach_engine_surface` for details."
        );
        return;
    }

    let engine = CoachEngine::new();
    engine.configure_coach(
        ProviderConfig::Ollama {
            base_url: format!("http://{OLLAMA_HOST}"),
            api_key: None,
        },
        TEST_MODEL.to_string(),
    );

    // Small cloud models don't reliably choose to call a tool on every
    // attempt for the same prompt — that's model instruction-following
    // variance, not a plumbing bug. Retry a few times before failing; this
    // test's job is to prove that *when* the model calls a tool, it's
    // correctly routed through the real `Tool` impl to `CoachHost`, not to
    // guarantee any particular model calls tools deterministically.
    let mut routed: Option<(String, String)> = None;
    for attempt in 1..=3 {
        let (sink_tx, sink_rx) = mpsc::channel();
        let (host_tx, host_rx) = mpsc::channel();
        engine.send_message(
            "You are a strength coach. The athlete just asked for a weight change. You MUST \
             call the adjust_set tool to apply it — never respond with prose instead."
                .to_string(),
            "Bump my Back Squat, set index 0, to 100kg.".to_string(),
            "[]".to_string(),
            Box::new(ChannelSink(sink_tx)),
            Box::new(RecordingHost(host_tx)),
        );

        let mut saw_tool_call = false;
        loop {
            match sink_rx.recv_timeout(Duration::from_secs(45)) {
                Ok(Event::TextDelta) => {}
                Ok(Event::ToolCall(name, _args)) => {
                    assert_eq!(name, "adjust_set");
                    saw_tool_call = true;
                }
                Ok(Event::Completed(_)) => break,
                Ok(Event::Error(message)) => panic!("coach turn reported an error: {message}"),
                Err(_) => panic!("timed out waiting for the coach turn to complete"),
            }
        }

        if saw_tool_call {
            routed = host_rx.recv_timeout(Duration::from_secs(1)).ok();
            break;
        }
        eprintln!("attempt {attempt}/3: model did not call adjust_set for this prompt, retrying");
    }

    let (routed_name, routed_args) = routed.expect(
        "expected the model to call adjust_set for a weight-change request within 3 attempts",
    );
    assert_eq!(routed_name, "adjust_set");
    let parsed: serde_json::Value =
        serde_json::from_str(&routed_args).expect("tool args should be valid JSON");
    // Only assert on the shape rig/our tool guarantees (both fields are
    // `required` in the tool's JSON schema — see `AdjustSetArgs`), not on
    // the model's exact wording or whether it included the optional
    // `new_weight`/`new_reps` fields this particular run. Model instruction
    // *fidelity* is not what this test is verifying — the always-run unit
    // tests in `src/coach/tools.rs` cover exact argument routing
    // deterministically via a fake host.
    assert!(
        parsed["exercise"].as_str().is_some_and(|s| !s.is_empty()),
        "expected a non-empty exercise name, got {parsed}"
    );
    assert!(
        parsed["set_index"].is_number(),
        "expected a numeric set_index, got {parsed}"
    );
}
