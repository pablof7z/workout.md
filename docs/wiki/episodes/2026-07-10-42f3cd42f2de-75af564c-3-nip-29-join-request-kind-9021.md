---
type: episode-card
date: 2026-07-10
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: product
status: active
subjects:
  - nip-29
  - nostr
  - fabric-coach
  - channel-membership
supersedes:
  - 2026-07-10-42f3cd42f2de-75af564c-6-nip-29-join-request-kind-9021
related_claims: []
source_lines:
  - 2876-2881
  - 2953-2965
  - 3030-3046
captured_at: 2026-07-10T07:42:20Z
---

# Episode: NIP-29 join-request (kind 9021) for channel access

## Prior State

Tenex-edge NIP-29 fabric coach could publish kind:9 events to channels it was a member of, but had no mechanism to request joining a channel it was not yet a member of. The daemon doesn't self-serve membership.

## Trigger

User directive: 'for the tenex-edge nip29 -- when you are not member of a channel you can request to join via the nip29 event'

## Decision

Implemented NIP-29 join-request (kind 9021) and leave-request (kind 9022) events in core/workout-core/src/nostr/wire.rs, exposed via NostrCoach.request_to_join/leave and FabricController.requestToJoin(inviteCode:). Added 'Request to join' button in Settings fabric section.

## Consequences

- Verified live against wss://nip29.f7z.io — relay returns 'restricted: group is closed, you need an invite code' for closed groups and 'group doesn't exist' for missing ones
- Membership is admin-approved: once an admin adds the coach's npub or the relay accepts an invite code, it can post/read kind:9
- Protocol memory updated to reflect kind 9021 usage
- Merged as part of PR #14, deployed to device

## Open Tail

*(none)*

## Evidence

- transcript lines 2876-2881
- transcript lines 2953-2965
- transcript lines 3030-3046

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-10-42f3cd42f2de-75af564c-3-nip-29-join-request-kind-9021.json`](transcripts/2026-07-10-42f3cd42f2de-75af564c-3-nip-29-join-request-kind-9021.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-3-nip-29-join-request-kind-9021.json`](transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-3-nip-29-join-request-kind-9021.json)
