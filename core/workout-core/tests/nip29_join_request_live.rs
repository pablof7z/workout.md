//! Gated live integration test for the NIP-29 join-request flow (kind:9021):
//! one identity creates + locks a throwaway private group (kind:9007 then
//! kind:9002 closed+public, exactly like `nip29_live.rs`'s admin setup), a
//! *second*, unrelated identity — never added as a member — then publishes
//! a join-request (`NostrCoach::request_to_join`) asking to join that
//! channel, and this test reports the relay's OK/response for that publish.
//!
//! This exercises the actual product scenario end to end: a coach identity
//! that is not (yet) a member of a NIP-29 channel asking to join one. It
//! does not assert the request was *approved* (that requires a human/admin
//! follow-up kind:9000, out of scope for an automated test) — only that the
//! join-request event itself is well-formed and the relay accepts/OKs it,
//! per NIP-01.
//!
//! Skips (rather than failing) when the relay isn't reachable, same as
//! `nip29_live.rs`, so a live relay is never required for `cargo test` to
//! pass. The always-run unit tests in `src/nostr/wire.rs` cover the
//! join/leave-request event shapes (correct kind/tags) without any network.

use std::net::ToSocketAddrs;
use std::time::Duration;

use workout_core::nostr::NostrCoach;

const RELAY: &str = "wss://nip29.f7z.io";
const RELAY_HOST_PORT: &str = "nip29.f7z.io:443";

/// Cheap reachability probe: a plain TCP connect to the relay's TLS port.
/// Skips the test rather than failing it when the author's network can't
/// reach the public relay (offline dev machine, CI with no egress, etc).
fn relay_reachable() -> bool {
    let Ok(mut addrs) = RELAY_HOST_PORT.to_socket_addrs() else {
        return false;
    };
    addrs.any(|addr| std::net::TcpStream::connect_timeout(&addr, Duration::from_secs(3)).is_ok())
}

fn random_slug(prefix: &str) -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    format!("{prefix}-{nanos:x}")
}

/// Admin identity creates + locks a throwaway closed+public group; a second,
/// unrelated identity (never added as a member) then sends a kind:9021
/// join-request for that same channel. Reports (via `eprintln!`, captured by
/// `cargo test -- --nocapture`) the actual NIP-01 OK/AUTH behavior observed
/// for the join-request publish, per the task's "report the relay's
/// OK/response" requirement.
///
/// Accepts either outcome as a pass: the relay OK'ing the join-request
/// outright, *or* a recognizable NIP-29 policy rejection (e.g. "restricted:
/// group is closed, you need an invite code" — this relay's actual observed
/// response for a closed group with no invite code configured, confirming
/// the event reached the relay and was correctly parsed/targeted). Only an
/// unrecognized failure (a connection error, or the relay rejecting the
/// event as malformed) fails the test.
#[test]
fn request_to_join_live_against_nip29_f7z_io() {
    if !relay_reachable() {
        eprintln!(
            "SKIPPED: {RELAY} not reachable from this machine — this test only runs when the \
             live NIP-29 relay is reachable. The always-run unit tests in src/nostr/wire.rs cover \
             the join/leave-request event shapes without a live relay."
        );
        return;
    }

    let channel = random_slug("workout-md-join-request-test");

    // Admin identity: creates + locks the throwaway group closed+public.
    let admin = NostrCoach::new();
    let admin_npub = admin.generate_identity();
    eprintln!("admin identity: {admin_npub}");
    admin.configure(vec![RELAY.to_string()], None, channel.clone());
    match admin.create_group(channel.clone(), channel.clone()) {
        Ok(id) => eprintln!("group {channel} created + locked closed+public: {id}"),
        Err(e) => panic!(
            "group create/lock against {RELAY} failed: {e}. If this is a NIP-42 AUTH rejection, \
             it means anonymous group creation is blocked on this relay — see the error text."
        ),
    }

    // Requesting identity: fresh, never added as a member, asks to join.
    let requester = NostrCoach::new();
    let requester_npub = requester.generate_identity();
    eprintln!("requesting identity: {requester_npub}");
    requester.configure(vec![RELAY.to_string()], None, channel.clone());

    match requester.request_to_join(channel.clone(), None) {
        Ok(id) => {
            eprintln!(
                "kind:9021 join-request for #{channel} published and OK'd by at least one relay: {id}"
            );
        }
        Err(e) => {
            let message = e.to_string();
            eprintln!("kind:9021 join-request for #{channel} was rejected by the relay: {message}");
            let lower = message.to_ascii_lowercase();
            assert!(
                lower.contains("restricted")
                    || lower.contains("invite")
                    || lower.contains("closed")
                    || lower.contains("auth"),
                "expected either relay acceptance or a recognizable NIP-29 policy rejection \
                 (restricted/invite/closed/auth-required), got an unrecognized failure: {message}"
            );
        }
    }
}
