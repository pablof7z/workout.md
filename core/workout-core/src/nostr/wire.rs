//! NIP-29 wire shapes for the coach's tenex-edge fabric membership.
//!
//! Mirrors, for the subset Workout.md's coach needs, the ground truth in
//! `~/src/tenex-edge`:
//! - `src/fabric/nip29/wire.rs` — kinds, tag shapes, kind:0/kind:9 encoding.
//! - `src/fabric/subscriptions.rs` — the narrow per-channel subscribe filter.
//! - `src/fabric/nip29/lifecycle.rs` — group create / lock-closed / put-user.
//!
//! Pure plumbing: no network, no signing. Every function here builds an
//! unsigned [`EventBuilder`] or a read [`Filter`] — signing and transport
//! live in `super` (`NostrCoach`).

use nostr_sdk::prelude::*;

/// kind:0 — replaceable profile metadata.
pub const KIND_METADATA: u16 = 0;
/// kind:9 — the sole chat/context-exchange mechanism on the fabric.
pub const KIND_CHAT: u16 = 9;
/// kind:30315 — per-session live status/presence (subscribed, never published
/// by this crate today).
pub const KIND_STATUS: u16 = 30315;
/// kind:30555 — backend-signed agent capability roster (subscribed, never
/// published by this crate today).
pub const KIND_AGENT_ROSTER: u16 = 30555;
/// kind:30023 — long-form proposal notes (subscribed, never published by
/// this crate today).
pub const KIND_LONGFORM: u16 = 30023;

/// kind:9007 — NIP-29 create-group. The signer becomes the group's admin. A
/// fresh group is OPEN (anyone may write) until locked via
/// [`KIND_GROUP_EDIT_METADATA`].
pub const KIND_GROUP_CREATE: u16 = 9007;
/// kind:9000 — NIP-29 put-user: grants `p` membership (or, with an `admin`
/// role tag, admin rights) over the group named by `h`.
pub const KIND_GROUP_PUT_USER: u16 = 9000;
/// kind:9002 — NIP-29 edit-metadata: used here to lock a group `closed`
/// (only members may write) while keeping it `public` (anyone may read).
pub const KIND_GROUP_EDIT_METADATA: u16 = 9002;

/// The `host` tag value stamped on every kind:0 profile this crate
/// publishes, identifying Workout.md's coach as the profile's origin app —
/// mirrors tenex-edge's `["host", <host>]` profile tag.
pub const PROFILE_HOST: &str = "workout.md-ios";

pub(crate) fn kind(n: u16) -> Kind {
    Kind::from(n)
}

/// Builds a tag from string parts. Only fails on an empty part *list*, which
/// never happens here (every call site passes at least the tag name) — see
/// `Tag::parse`'s doc: "Return error if the tag is empty". Panicking on that
/// truly-unreachable case keeps every builder below infallible without
/// smuggling an FFI-unfriendly error type through this pure wire layer.
fn tag(parts: &[&str]) -> Tag {
    Tag::parse(parts.iter().copied()).expect("static/runtime tag literals are never an empty list")
}

fn h_tag(channel: &str) -> Tag {
    tag(&["h", channel])
}

/// kind:0 profile metadata: content `{"name": ..}` (+ optional `about`/
/// `picture`, tolerated extra fields) and a `["host", PROFILE_HOST]` tag.
pub fn profile_event(name: &str, about: Option<&str>, picture: Option<&str>) -> EventBuilder {
    let mut content = serde_json::json!({ "name": name });
    if let Some(about) = about {
        content["about"] = serde_json::Value::String(about.to_string());
    }
    if let Some(picture) = picture {
        content["picture"] = serde_json::Value::String(picture.to_string());
    }
    EventBuilder::new(kind(KIND_METADATA), content.to_string()).tags([tag(&["host", PROFILE_HOST])])
}

/// kind:9 chat message: `["h", channel]` (required) + optional `["e",
/// reply_to]` (threads as a reply) + optional `["p", mention_pubkey]`
/// (routes/mentions). `allow_self_tagging` matches tenex-edge's chat/lifecycle
/// builders — needed when a mention happens to equal the signer's own
/// pubkey (self-mention is otherwise scrubbed by the SDK).
pub fn chat_event(
    channel: &str,
    body: &str,
    reply_to: Option<&str>,
    mention_pubkey: Option<&str>,
) -> EventBuilder {
    let mut tags = vec![h_tag(channel)];
    if let Some(id) = reply_to.filter(|s| !s.is_empty()) {
        tags.push(tag(&["e", id]));
    }
    if let Some(pk) = mention_pubkey.filter(|s| !s.is_empty()) {
        tags.push(tag(&["p", pk]));
    }
    EventBuilder::new(kind(KIND_CHAT), body.to_string())
        .tags(tags)
        .allow_self_tagging()
}

/// kind:9007 create-group with a client-chosen id (`h` == channel slug). The
/// signer becomes the group admin. NOTE: a fresh group is OPEN until locked
/// via [`group_lock_closed_event`].
pub fn group_create_event(channel: &str) -> EventBuilder {
    EventBuilder::new(kind(KIND_GROUP_CREATE), "").tags([h_tag(channel)])
}

/// kind:9002 edit-metadata that locks the group `closed` (only members may
/// write) while keeping it `public` (anyone may read), named `name`.
pub fn group_lock_closed_event(channel: &str, name: &str) -> EventBuilder {
    EventBuilder::new(kind(KIND_GROUP_EDIT_METADATA), "").tags([
        h_tag(channel),
        tag(&["name", name]),
        tag(&["closed"]),
        tag(&["public"]),
    ])
}

/// kind:9000 put-user adding `pubkey` to the group as a plain member, so it
/// can publish kind:9 chat into the now-closed group.
pub fn group_put_user_event(channel: &str, pubkey: &str) -> EventBuilder {
    EventBuilder::new(kind(KIND_GROUP_PUT_USER), "")
        .tags([h_tag(channel), tag(&["p", pubkey])])
        .allow_self_tagging()
}

fn h_single() -> SingleLetterTag {
    SingleLetterTag::lowercase(Alphabet::H)
}

fn p_single() -> SingleLetterTag {
    SingleLetterTag::lowercase(Alphabet::P)
}

/// Subscribe filter: kinds `[9, 30315, 30555, 30023]` scoped to `#h =
/// channel`; when `only_mentions_of` is set, additionally narrows to `#p =
/// <pubkey>` so only messages routed to that identity are returned.
pub fn subscribe_filter(channel: &str, only_mentions_of: Option<&str>) -> Filter {
    let mut f = Filter::new()
        .kinds([
            kind(KIND_CHAT),
            kind(KIND_STATUS),
            kind(KIND_AGENT_ROSTER),
            kind(KIND_LONGFORM),
        ])
        .custom_tag(h_single(), channel);
    if let Some(pk) = only_mentions_of {
        f = f.custom_tag(p_single(), pk);
    }
    f
}

#[cfg(test)]
mod tests {
    use super::*;

    fn has_tag(ev: &Event, name: &str, value: &str) -> bool {
        ev.tags.iter().any(|t| {
            let s = t.as_slice();
            s.first().map(String::as_str) == Some(name) && s.get(1).map(String::as_str) == Some(value)
        })
    }

    fn has_bare_tag(ev: &Event, name: &str) -> bool {
        ev.tags
            .iter()
            .any(|t| t.as_slice().first().map(String::as_str) == Some(name))
    }

    #[test]
    fn profile_event_is_kind_0_with_name_and_host_tag() {
        let ev = profile_event("coach", None, None)
            .sign_with_keys(&Keys::generate())
            .unwrap();
        assert_eq!(ev.kind.as_u16(), KIND_METADATA);
        assert!(has_tag(&ev, "host", PROFILE_HOST));
        let content: serde_json::Value = serde_json::from_str(&ev.content).unwrap();
        assert_eq!(content["name"], "coach");
    }

    #[test]
    fn profile_event_tolerates_about_and_picture_extra_fields() {
        let ev = profile_event("coach", Some("your strength coach"), Some("https://example/pic.png"))
            .sign_with_keys(&Keys::generate())
            .unwrap();
        let content: serde_json::Value = serde_json::from_str(&ev.content).unwrap();
        assert_eq!(content["name"], "coach");
        assert_eq!(content["about"], "your strength coach");
        assert_eq!(content["picture"], "https://example/pic.png");
    }

    #[test]
    fn chat_event_is_kind_9_with_h_tag_only_by_default() {
        let ev = chat_event("room1", "hello fabric", None, None)
            .sign_with_keys(&Keys::generate())
            .unwrap();
        assert_eq!(ev.kind.as_u16(), KIND_CHAT);
        assert_eq!(ev.content, "hello fabric");
        assert!(has_tag(&ev, "h", "room1"));
        assert!(!has_bare_tag(&ev, "e"));
        assert!(!has_bare_tag(&ev, "p"));
    }

    #[test]
    fn chat_event_adds_e_tag_when_replying() {
        let ev = chat_event("room1", "reply body", Some("deadbeef"), None)
            .sign_with_keys(&Keys::generate())
            .unwrap();
        assert!(has_tag(&ev, "h", "room1"));
        assert!(has_tag(&ev, "e", "deadbeef"));
    }

    #[test]
    fn chat_event_adds_p_tag_when_mentioning() {
        let mention = Keys::generate().public_key().to_hex();
        let ev = chat_event("room1", "hey you", None, Some(&mention))
            .sign_with_keys(&Keys::generate())
            .unwrap();
        assert!(has_tag(&ev, "h", "room1"));
        assert!(has_tag(&ev, "p", &mention));
    }

    #[test]
    fn chat_event_adds_both_e_and_p_tags() {
        let mention = Keys::generate().public_key().to_hex();
        let ev = chat_event("room1", "reply+mention", Some("cafebabe"), Some(&mention))
            .sign_with_keys(&Keys::generate())
            .unwrap();
        assert!(has_tag(&ev, "h", "room1"));
        assert!(has_tag(&ev, "e", "cafebabe"));
        assert!(has_tag(&ev, "p", &mention));
    }

    #[test]
    fn group_create_event_is_kind_9007_with_h_tag() {
        let ev = group_create_event("myroom")
            .sign_with_keys(&Keys::generate())
            .unwrap();
        assert_eq!(ev.kind.as_u16(), KIND_GROUP_CREATE);
        assert!(has_tag(&ev, "h", "myroom"));
    }

    #[test]
    fn group_lock_closed_event_is_closed_and_public() {
        let ev = group_lock_closed_event("myroom", "My Room")
            .sign_with_keys(&Keys::generate())
            .unwrap();
        assert_eq!(ev.kind.as_u16(), KIND_GROUP_EDIT_METADATA);
        assert!(has_tag(&ev, "h", "myroom"));
        assert!(has_tag(&ev, "name", "My Room"));
        assert!(has_bare_tag(&ev, "closed"));
        assert!(has_bare_tag(&ev, "public"));
        assert!(!has_bare_tag(&ev, "private"));
    }

    #[test]
    fn group_put_user_event_is_kind_9000_with_h_and_p_tags() {
        let member = Keys::generate().public_key().to_hex();
        let ev = group_put_user_event("myroom", &member)
            .sign_with_keys(&Keys::generate())
            .unwrap();
        assert_eq!(ev.kind.as_u16(), KIND_GROUP_PUT_USER);
        assert!(has_tag(&ev, "h", "myroom"));
        assert!(has_tag(&ev, "p", &member));
    }

    #[test]
    fn subscribe_filter_has_h_tag_and_the_four_subscribed_kinds() {
        let f = subscribe_filter("myroom", None);
        let json = serde_json::to_string(&f).unwrap();
        assert!(json.contains("\"#h\""));
        assert!(json.contains("myroom"));
        assert!(json.contains('9'));
        assert!(json.contains("30315"));
        assert!(json.contains("30555"));
        assert!(json.contains("30023"));
        assert!(!json.contains("\"#p\""));
    }

    #[test]
    fn subscribe_filter_adds_p_tag_when_scoped_to_a_pubkey() {
        let f = subscribe_filter("myroom", Some("pk-a"));
        let json = serde_json::to_string(&f).unwrap();
        assert!(json.contains("\"#h\""));
        assert!(json.contains("\"#p\""));
        assert!(json.contains("pk-a"));
    }
}
