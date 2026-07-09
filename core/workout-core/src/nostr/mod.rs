//! Nostr / NIP-29 module — lets the coach agent join the user's tenex-edge
//! fabric and exchange context with their other agents over kind:9 chat
//! messages.
//!
//! Ground truth mirrored from `~/src/tenex-edge` (see `wire.rs` for the
//! per-kind reasoning): `src/fabric/nip29/wire.rs` (kinds + tags),
//! `src/fabric/provider/chat.rs` (sign + publish a kind:9), `src/fabric/
//! subscriptions.rs` (the narrow per-channel filter), `src/fabric/nip29/
//! lifecycle.rs` (group create / lock-closed / put-user), and `src/
//! transport.rs` (NIP-42 automatic-authentication client setup, the indexer-
//! vs-main-relay publish split).
//!
//! Shape of the surface, mirroring [`crate::coach::CoachEngine`]'s pattern
//! (one instance owns a dedicated background tokio runtime; nothing blocks
//! the Swift caller's thread for the streaming subscription path):
//! - Identity: [`NostrCoach::generate_identity`] / [`NostrCoach::import_nsec`]
//!   / [`NostrCoach::current_npub`] hold a `Keys` in memory. Persisting the
//!   nsec (Keychain) is the Swift shell's job — [`NostrCoach::export_nsec`]
//!   just hands it back so Swift can store it.
//! - [`NostrCoach::configure`] selects the relay set, optional profile
//!   indexer, and NIP-29 channel used by every call below.
//! - [`NostrCoach::publish_profile`] / [`NostrCoach::publish_message`] /
//!   [`NostrCoach::create_group`] / [`NostrCoach::add_member`] each connect
//!   (or reuse a cached connection), sign with the configured identity, and
//!   publish over the engine's background runtime, blocking only the calling
//!   thread's dedicated call, never the caller's own thread — see the
//!   `runtime.block_on` note on `ensure_client` (below).
//! - [`NostrCoach::start_subscription`] subscribes kind:9 (+30315/30555/30023)
//!   for `#h = channel` and pushes every inbound kind:9 to a Swift-implemented
//!   [`NostrSink`], detached on the background runtime — mirrors
//!   `CoachEngine::send_message`'s fire-and-forget-with-callbacks shape.

pub mod wire;

use std::sync::Mutex;
use std::time::Duration;

use nostr_sdk::prelude::*;

pub use wire::PROFILE_HOST;

/// Bounded wait for the relay connection (+ NIP-42 AUTH handshake, which
/// `ClientOptions::automatic_authentication(true)` drives transparently) to
/// settle before a publish/subscribe is attempted. Mirrors tenex-edge's
/// `Transport::PUBLISH_CONNECT_WAIT`.
const CONNECT_WAIT: Duration = Duration::from_secs(8);

/// Error surface for every fallible [`NostrCoach`] operation. Every variant
/// carries only a `String` so this crosses the UniFFI boundary directly
/// (no `flat_error` indirection needed).
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum NostrError {
    /// `import_nsec` was given a string that isn't a valid hex or bech32
    /// (`nsec1...`) secp256k1 secret key.
    #[error("invalid nsec: {0}")]
    InvalidNsec(String),
    /// A publish/subscribe/group call was made before an identity
    /// (`generate_identity`/`import_nsec`) and/or `configure` had been set.
    #[error("nostr coach is not configured: {0}")]
    NotConfigured(String),
    /// The relay connection, publish, or fetch itself failed — includes the
    /// NIP-01 `OK,false,<reason>` case (e.g. a closed group rejecting a
    /// non-member's kind:9, or a relay's AUTH-required rejection).
    #[error("relay error: {0}")]
    Relay(String),
}

/// Streaming sink the Swift app implements to receive inbound fabric
/// messages. Every method is called from [`NostrCoach`]'s background tokio
/// runtime, never from the thread that called `start_subscription`.
#[uniffi::export(callback_interface)]
pub trait NostrSink: Send + Sync {
    /// A kind:9 chat message arrived for the configured channel (optionally
    /// further scoped to messages mentioning this identity's pubkey — see
    /// [`NostrCoach::start_subscription`]).
    fn on_message(&self, id: String, author_pubkey: String, body: String, created_at: u64);
    /// The subscription (or the connection it depends on) failed. Not fatal
    /// by itself — the underlying `nostr-sdk` relay pool keeps retrying the
    /// connection on its own; this is a best-effort surfacing of what went
    /// wrong for UI/logging purposes.
    fn on_error(&self, message: String);
}

#[derive(Default)]
struct NostrState {
    keys: Option<Keys>,
    relays: Vec<String>,
    indexer_relay: Option<String>,
    channel: String,
    /// Cached connection, invalidated (set back to `None`) whenever the
    /// identity or relay configuration changes, so the next network call
    /// reconnects under the new signer/relay set instead of silently
    /// continuing to use a stale one.
    client: Option<Client>,
}

/// A snapshot of [`NostrState`] taken under the lock, then used to drive an
/// async network operation *outside* the lock (a `std::sync::Mutex` must
/// never be held across an `.await`).
struct Snapshot {
    keys: Keys,
    relays: Vec<String>,
    indexer_relay: Option<String>,
    channel: String,
    client: Option<Client>,
}

/// The Nostr/NIP-29 fabric engine. One instance owns a dedicated background
/// tokio runtime, mirroring [`crate::coach::CoachEngine`], so a live
/// subscription's inbound-event loop never blocks the Swift caller's thread.
#[derive(uniffi::Object)]
pub struct NostrCoach {
    state: Mutex<NostrState>,
    runtime: tokio::runtime::Runtime,
}

#[uniffi::export]
impl NostrCoach {
    #[uniffi::constructor]
    pub fn new() -> Self {
        crate::coach::ensure_rustls_ring_provider();
        Self {
            state: Mutex::new(NostrState::default()),
            runtime: tokio::runtime::Builder::new_multi_thread()
                .worker_threads(2)
                .thread_name("workout-core-nostr")
                .enable_all()
                .build()
                .expect("failed to start nostr coach tokio runtime"),
        }
    }

    /// Generates a fresh secp256k1 identity, installs it as the signer for
    /// every subsequent call, and returns its `npub`. Invalidates any cached
    /// relay connection (the next network call reconnects, authenticating as
    /// the new identity). Persisting the corresponding nsec
    /// ([`NostrCoach::export_nsec`]) to the Keychain is the Swift shell's job.
    pub fn generate_identity(&self) -> String {
        let keys = Keys::generate();
        let npub = keys
            .public_key()
            .to_bech32()
            .unwrap_or_else(|_| keys.public_key().to_hex());
        let mut state = self.state.lock().expect("nostr coach state poisoned");
        state.keys = Some(keys);
        state.client = None;
        npub
    }

    /// Imports an existing identity from an `nsec1...` (bech32) or raw hex
    /// secret key string, installing it as the signer for every subsequent
    /// call. Invalidates any cached relay connection.
    pub fn import_nsec(&self, nsec: String) -> Result<(), NostrError> {
        let keys = Keys::parse(&nsec).map_err(|e| NostrError::InvalidNsec(e.to_string()))?;
        let mut state = self.state.lock().expect("nostr coach state poisoned");
        state.keys = Some(keys);
        state.client = None;
        Ok(())
    }

    /// Exports the current identity's `nsec1...` secret key, e.g. for the
    /// Swift Keychain layer to persist across launches. `None` until an
    /// identity has been generated or imported.
    pub fn export_nsec(&self) -> Option<String> {
        let state = self.state.lock().expect("nostr coach state poisoned");
        state
            .keys
            .as_ref()
            .and_then(|k| k.secret_key().to_bech32().ok())
    }

    /// The current identity's `npub`, or `None` if no identity is set yet.
    pub fn current_npub(&self) -> Option<String> {
        let state = self.state.lock().expect("nostr coach state poisoned");
        state.keys.as_ref().and_then(|k| k.public_key().to_bech32().ok())
    }

    /// Configure (or reconfigure) the relay set, optional profile indexer
    /// relay, and NIP-29 channel used by every publish/subscribe call below.
    /// Safe to call again mid-lifetime; invalidates any cached connection so
    /// the next network call reconnects under the new configuration.
    pub fn configure(&self, relays: Vec<String>, indexer_relay: Option<String>, channel: String) {
        let mut state = self.state.lock().expect("nostr coach state poisoned");
        state.relays = relays;
        state.indexer_relay = indexer_relay.filter(|s| !s.is_empty());
        state.channel = channel;
        state.client = None;
    }

    /// Publishes a kind:0 profile (`{"name": ..}`, optional `about`/
    /// `picture`) to both the main relay set and the configured profile
    /// indexer (if any) — per the protocol, the indexer relay accepts
    /// kind:0 but rejects NIP-29 kinds, so it is targeted only here, never
    /// for chat/group events. Returns the published event id (hex) once at
    /// least one relay has ack'd it (NIP-01 `OK,true`).
    pub fn publish_profile(
        &self,
        name: String,
        about: Option<String>,
        picture: Option<String>,
    ) -> Result<String, NostrError> {
        let snapshot = capture_snapshot(&self.state)?;
        self.runtime.block_on(async move {
            let (client, keys) = ensure_client(&self.state, snapshot).await?;
            let builder = wire::profile_event(&name, about.as_deref(), picture.as_deref());
            let signed = sign(builder, &keys).await?;
            let targets = publish_targets_with_indexer(&self.state);
            publish_checked(&client, &signed, &targets).await
        })
    }

    /// Publishes a kind:9 chat message (`["h", channel]`, optional `["e",
    /// reply_to]` / `["p", mention_pubkey]`) to the main relay set only.
    /// Returns the published event id (hex) once at least one relay has
    /// ack'd it.
    pub fn publish_message(
        &self,
        body: String,
        reply_to: Option<String>,
        mention_pubkey: Option<String>,
    ) -> Result<String, NostrError> {
        let snapshot = capture_snapshot(&self.state)?;
        let channel = snapshot.channel.clone();
        self.runtime.block_on(async move {
            let (client, keys) = ensure_client(&self.state, snapshot).await?;
            let builder = wire::chat_event(&channel, &body, reply_to.as_deref(), mention_pubkey.as_deref());
            let signed = sign(builder, &keys).await?;
            let targets = publish_targets_main_only(&self.state);
            publish_checked(&client, &signed, &targets).await
        })
    }

    /// Creates a throwaway NIP-29 group at the configured channel id
    /// (kind:9007) and immediately locks it `closed`+`public` (kind:9002),
    /// so the configured identity becomes its sole admin. Useful for tests
    /// and for a coach that wants to own a private channel of its own.
    /// Returns the lock-closed event's id (hex).
    pub fn create_group(&self, channel: String, name: String) -> Result<String, NostrError> {
        let snapshot = capture_snapshot(&self.state)?;
        self.runtime.block_on(async move {
            let (client, keys) = ensure_client(&self.state, snapshot).await?;
            let targets = publish_targets_main_only(&self.state);

            let create = sign(wire::group_create_event(&channel), &keys).await?;
            publish_checked(&client, &create, &targets).await?;

            let lock = sign(wire::group_lock_closed_event(&channel, &name), &keys).await?;
            publish_checked(&client, &lock, &targets).await
        })
    }

    /// Adds `pubkey` as a plain member of `channel` (kind:9000 put-user) —
    /// required before that identity may publish kind:9 into a `closed`
    /// group. Returns the published event id (hex).
    pub fn add_member(&self, channel: String, pubkey: String) -> Result<String, NostrError> {
        let snapshot = capture_snapshot(&self.state)?;
        self.runtime.block_on(async move {
            let (client, keys) = ensure_client(&self.state, snapshot).await?;
            let signed = sign(wire::group_put_user_event(&channel, &pubkey), &keys).await?;
            let targets = publish_targets_main_only(&self.state);
            publish_checked(&client, &signed, &targets).await
        })
    }

    /// Subscribes to kind:9 (+30315/30555/30023) for `#h = channel` and
    /// pushes every inbound kind:9 chat message to `sink`, detached on this
    /// engine's background runtime. Returns immediately; `sink.on_error` is
    /// called (synchronously, before returning) if the coach isn't
    /// configured yet, or (asynchronously, from the background runtime) if
    /// the subscribe call itself fails.
    pub fn start_subscription(&self, sink: Box<dyn NostrSink>) {
        let sink: std::sync::Arc<dyn NostrSink> = std::sync::Arc::from(sink);
        let snapshot = match capture_snapshot(&self.state) {
            Ok(s) => s,
            Err(e) => {
                sink.on_error(e.to_string());
                return;
            }
        };
        let channel = snapshot.channel.clone();

        self.runtime.spawn(async move {
            // `self` cannot be captured into a `'static` spawned task; the
            // caller (`self.runtime.spawn` below is called from a `&self`
            // method) instead passes everything the loop needs by value in
            // `snapshot`, and builds its own client rather than reaching
            // back into `self.state`.
            let client = match build_client(&snapshot).await {
                Ok(c) => c,
                Err(e) => {
                    sink.on_error(e.to_string());
                    return;
                }
            };

            // Subscribes to the whole channel's kind:9 (+30315/30555/30023)
            // traffic rather than narrowing to `#p = <own pubkey>` — a
            // freshly-joined coach wants full channel visibility. Scoping to
            // mentions-only is `wire::subscribe_filter`'s `only_mentions_of`
            // parameter, available to a future caller that wants it.
            let filter = wire::subscribe_filter(&channel, None);
            if let Err(e) = client.subscribe(filter, None).await {
                sink.on_error(format!("subscribe failed: {e}"));
                return;
            }

            let mut notifications = client.notifications();
            loop {
                match notifications.recv().await {
                    Ok(RelayPoolNotification::Event { event, .. }) => {
                        if event.kind.as_u16() == wire::KIND_CHAT {
                            sink.on_message(
                                event.id.to_hex(),
                                event.pubkey.to_hex(),
                                event.content.clone(),
                                event.created_at.as_secs(),
                            );
                        }
                    }
                    Ok(_) => {}
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(skipped)) => {
                        sink.on_error(format!(
                            "notification stream lagged, {skipped} messages dropped"
                        ));
                    }
                    Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                        sink.on_error("relay pool notification stream closed".to_string());
                        return;
                    }
                }
            }
        });
    }
}

impl Default for NostrCoach {
    fn default() -> Self {
        Self::new()
    }
}

/// Snapshots the current identity/relay/channel configuration, failing fast
/// (before touching the network) if either is unset.
///
/// A free function taking `&Mutex<NostrState>` rather than a `NostrCoach`
/// method: `#[uniffi::export]` processes every method in the `impl` block it
/// annotates, including private ones, and requires each of their
/// signatures' types to cross the FFI boundary — `Snapshot` (an internal,
/// non-UniFFI type holding a live `Client`) must never appear in that block.
fn capture_snapshot(state: &Mutex<NostrState>) -> Result<Snapshot, NostrError> {
    let state = state.lock().expect("nostr coach state poisoned");
    let keys = state.keys.clone().ok_or_else(|| {
        NostrError::NotConfigured("call generate_identity or import_nsec first".to_string())
    })?;
    if state.channel.is_empty() {
        return Err(NostrError::NotConfigured(
            "call configure with a non-empty channel first".to_string(),
        ));
    }
    Ok(Snapshot {
        keys,
        relays: state.relays.clone(),
        indexer_relay: state.indexer_relay.clone(),
        channel: state.channel.clone(),
        client: state.client.clone(),
    })
}

/// Sign `builder` with `keys` (async because [`Keys`] implements
/// [`NostrSigner`], whose signing methods are `async` — even though the
/// local-key case never actually awaits anything).
async fn sign(builder: EventBuilder, keys: &Keys) -> Result<Event, NostrError> {
    let unsigned = builder.build(keys.public_key());
    keys.sign_event(unsigned)
        .await
        .map_err(|e| NostrError::Relay(format!("signing failed: {e}")))
}

/// The main NIP-29 relay set — the broadcast target for chat/group events.
/// Never includes the profile indexer (see the module doc and
/// [`publish_targets_with_indexer`]).
fn publish_targets_main_only(state: &Mutex<NostrState>) -> Vec<String> {
    state.lock().expect("nostr coach state poisoned").relays.clone()
}

/// The main relay set PLUS the profile indexer, if configured — the kind:0
/// broadcast target. The indexer relay accepts kind:0 but rejects NIP-29
/// kinds, so only kind:0 publishes ever target it.
fn publish_targets_with_indexer(state: &Mutex<NostrState>) -> Vec<String> {
    let state = state.lock().expect("nostr coach state poisoned");
    let mut targets = state.relays.clone();
    if let Some(indexer) = &state.indexer_relay {
        if !targets.iter().any(|r| r == indexer) {
            targets.push(indexer.clone());
        }
    }
    targets
}

/// Builds a fresh, connected [`Client`] from a [`Snapshot`] — used both by
/// the cached-connection path ([`ensure_client`]) and by
/// [`NostrCoach::start_subscription`]'s detached task (which cannot borrow
/// back into `self.state` from a `'static` spawned future). Adds every main
/// relay plus the indexer relay (if any) with full READ+WRITE flags: WRITE
/// is required even for the indexer so the explicit kind:0 publish can reach
/// it (see `Transport::connect_with_indexer` in tenex-edge for the identical
/// reasoning), and READ is required on the main relays for subscriptions and
/// group-state lookups.
async fn build_client(snapshot: &Snapshot) -> Result<Client, NostrError> {
    let opts = ClientOptions::default().automatic_authentication(true);
    let client = Client::builder()
        .signer(snapshot.keys.clone())
        .opts(opts)
        .build();
    for relay in &snapshot.relays {
        client
            .add_relay(relay)
            .await
            .map_err(|e| NostrError::Relay(format!("adding relay {relay}: {e}")))?;
    }
    if let Some(indexer) = &snapshot.indexer_relay {
        client
            .add_relay(indexer)
            .await
            .map_err(|e| NostrError::Relay(format!("adding indexer relay {indexer}: {e}")))?;
    }
    client.connect().await;
    client.wait_for_connection(CONNECT_WAIT).await;
    Ok(client)
}

/// Returns a connected client for `snapshot`'s configuration, reusing the
/// cached one from `capture_snapshot` when present (same identity/relay
/// set — [`NostrCoach::generate_identity`]/[`NostrCoach::import_nsec`]/
/// [`NostrCoach::configure`] all clear the cache on change, so a cached
/// client here is always current), otherwise building and caching a new one.
///
/// Every `NostrCoach` public method that reaches the network calls this from
/// inside `self.runtime.block_on(..)` — the *engine's own* background
/// runtime thread, never the Swift caller's thread, so the caller only
/// blocks for the duration of that one call rather than the UI thread
/// blocking on network I/O. (A future refinement could make these
/// fire-and-forget with a sink, matching `start_subscription` and
/// `CoachEngine::send_message`; the Swift wiring step can decide which shape
/// fits the coach UI better.)
async fn ensure_client(
    state: &Mutex<NostrState>,
    snapshot: Snapshot,
) -> Result<(Client, Keys), NostrError> {
    if let Some(client) = snapshot.client {
        return Ok((client, snapshot.keys));
    }
    let client = build_client(&snapshot).await?;
    let mut locked = state.lock().expect("nostr coach state poisoned");
    // Only cache if the config hasn't changed underneath us (best-effort —
    // `generate_identity`/`import_nsec`/`configure` clear `client` on
    // change, so a stale write here just gets cleared again by the next
    // snapshot rather than silently reused).
    locked.client = Some(client.clone());
    Ok((client, snapshot.keys))
}

/// Publish an already-signed event to exactly `targets`, failing unless at
/// least one relay accepted it (NIP-01 `OK,true`) — mirrors tenex-edge's
/// `Transport::publish_event_checked`/`assert_relay_accepted`: `send_event`
/// resolves `Ok` even when every relay rejected the event (e.g. NIP-29
/// `blocked`/`auth-required`), so a bare `Ok` would mask a silently-dropped
/// publish. A "duplicate" rejection is treated as success — the relay
/// already has the event, so durability is satisfied.
async fn publish_checked(client: &Client, signed: &Event, targets: &[String]) -> Result<String, NostrError> {
    client.wait_for_connection(CONNECT_WAIT).await;
    let output = client
        .send_event_to(targets.iter().cloned(), signed)
        .await
        .map_err(|e| NostrError::Relay(format!("publishing event: {e}")))?;
    if !output.success.is_empty() {
        return Ok(output.val.to_hex());
    }
    if output
        .failed
        .values()
        .any(|reason| reason.to_ascii_lowercase().contains("duplicate"))
    {
        return Ok(output.val.to_hex());
    }
    let reasons: Vec<String> = output.failed.values().filter(|r| !r.is_empty()).cloned().collect();
    if reasons.is_empty() {
        return Err(NostrError::Relay(
            "no relay accepted the event (timeout or no OK received)".to_string(),
        ));
    }
    Err(NostrError::Relay(format!("relay rejected event: {}", reasons.join("; "))))
}
