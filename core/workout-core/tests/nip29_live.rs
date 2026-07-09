//! Gated live integration test: exercises `NostrCoach` against the real
//! NIP-29 relay `wss://nip29.f7z.io` — generate an identity, publish a
//! kind:0 profile, create + lock a throwaway test group (kind:9007 then
//! kind:9002 closed+public, so this run's identity is its admin), publish a
//! kind:9 chat into it, and subscribe to confirm the relay actually
//! delivers it back.
//!
//! Skips (rather than failing) when the relay isn't reachable, per the
//! task's testing requirements: a live relay is optional and must never gate
//! `cargo test`. The always-run unit tests in `src/nostr/wire.rs` cover the
//! same event-shape code paths (correct kind/tags) without any network.
//!
//! Every group/channel id is a fresh random slug so repeated runs never
//! collide with a previous run's throwaway group.

use std::net::ToSocketAddrs;
use std::sync::mpsc;
use std::time::Duration;

use workout_core::nostr::{NostrCoach, NostrSink};

const RELAY: &str = "wss://nip29.f7z.io";
const RELAY_HOST_PORT: &str = "nip29.f7z.io:443";
const INDEXER: &str = "wss://purplepag.es";

/// Cheap reachability probe: a plain TCP connect to the relay's TLS port.
/// Skips the test rather than failing it when the author's network can't
/// reach the public relay (offline dev machine, CI with no egress, etc).
fn relay_reachable() -> bool {
    let Ok(mut addrs) = RELAY_HOST_PORT.to_socket_addrs() else {
        return false;
    };
    addrs.any(|addr| {
        std::net::TcpStream::connect_timeout(&addr, Duration::from_secs(3)).is_ok()
    })
}

fn random_slug(prefix: &str) -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    format!("{prefix}-{nanos:x}")
}

enum Inbound {
    Message { id: String, author: String, body: String },
    Error(String),
}

struct ChannelSink(mpsc::Sender<Inbound>);

impl NostrSink for ChannelSink {
    fn on_message(&self, id: String, author_pubkey: String, body: String, _created_at: u64) {
        let _ = self.0.send(Inbound::Message {
            id,
            author: author_pubkey,
            body,
        });
    }
    fn on_error(&self, message: String) {
        let _ = self.0.send(Inbound::Error(message));
    }
}

/// Full lifecycle against the live relay: identity -> kind:0 profile ->
/// create+lock a throwaway group -> kind:9 chat into it -> subscribe and
/// observe the relay deliver that same kind:9 back.
///
/// Reports (via `eprintln!`, captured by `cargo test -- --nocapture`) the
/// actual NIP-01 OK/AUTH behavior observed for each publish, per the task's
/// "report the actual relay OK/AUTH behavior you observed" requirement.
#[test]
fn joins_the_live_fabric_and_round_trips_a_kind_9_chat() {
    if !relay_reachable() {
        eprintln!(
            "SKIPPED: {RELAY} not reachable from this machine — this test only runs when the \
             live NIP-29 relay is reachable. The always-run unit tests in src/nostr/wire.rs cover \
             the same event-shape code paths without a live relay."
        );
        return;
    }

    let coach = NostrCoach::new();
    let npub = coach.generate_identity();
    eprintln!("generated identity: {npub}");

    let channel = random_slug("workout-md-smoke-test");
    coach.configure(
        vec![RELAY.to_string()],
        Some(INDEXER.to_string()),
        channel.clone(),
    );

    // kind:0 profile -> main relay + indexer.
    match coach.publish_profile("coach".to_string(), Some("Workout.md smoke test".to_string()), None) {
        Ok(id) => eprintln!("kind:0 profile published and OK'd by at least one relay: {id}"),
        Err(e) => panic!(
            "kind:0 profile publish was rejected/failed against {RELAY} + {INDEXER}: {e}. This \
             either means NIP-42 AUTH blocked an anonymous/first-time publish, or the relay \
             rejected the event outright — see the error text above for the exact reason."
        ),
    }

    // kind:9007 create + kind:9002 lock-closed+public -> this identity
    // becomes the throwaway group's sole admin.
    match coach.create_group(channel.clone(), channel.clone()) {
        Ok(id) => eprintln!("group {channel} created + locked closed+public: {id}"),
        Err(e) => panic!(
            "group create/lock against {RELAY} failed: {e}. If this is a NIP-42 AUTH rejection, \
             it means anonymous group creation is blocked on this relay — see the error text."
        ),
    }

    // kind:9 chat into the now-closed group we just admin'd.
    let body = format!("hello fabric from workout.md smoke test {channel}");
    let published_id = match coach.publish_message(body.clone(), None, None) {
        Ok(id) => {
            eprintln!("kind:9 chat published and OK'd by at least one relay: {id}");
            id
        }
        Err(e) => panic!(
            "kind:9 chat publish into our own just-created closed group failed: {e}. Since we're \
             the group's admin (and thus a member), this should never be a membership rejection \
             — see the error text for what the relay actually said."
        ),
    };

    // Subscribe and confirm the relay delivers that same kind:9 back.
    let (tx, rx) = mpsc::channel();
    coach.start_subscription(Box::new(ChannelSink(tx)));

    let deadline = std::time::Instant::now() + Duration::from_secs(20);
    let mut saw_own_message = false;
    while std::time::Instant::now() < deadline && !saw_own_message {
        match rx.recv_timeout(Duration::from_secs(5)) {
            Ok(Inbound::Message { id, author, body: recv_body }) => {
                eprintln!("subscription observed kind:9 id={id} author={author}");
                if id == published_id && recv_body == body {
                    saw_own_message = true;
                }
            }
            Ok(Inbound::Error(message)) => {
                eprintln!("subscription reported: {message}");
            }
            Err(_) => {} // keep polling until the deadline
        }
    }

    assert!(
        saw_own_message,
        "expected the live relay to deliver our own just-published kind:9 (id {published_id}) \
         back over the subscription within 20s — either the relay's NIP-42 AUTH gated the \
         subscription's REQ, or the #h filter/channel didn't match. See the eprintln! output \
         above (run with `cargo test -- --nocapture`) for what actually came back."
    );
}
