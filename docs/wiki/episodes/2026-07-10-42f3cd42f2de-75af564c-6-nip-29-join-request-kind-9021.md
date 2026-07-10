---
type: episode-card
date: 2026-07-10
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: product
status: superseded
subjects:
  - nip29
  - join-request
  - kind-9021
  - nostr-fabric
supersedes: []
related_claims: []
source_lines:
  - 2876-2884
captured_at: 2026-07-10T07:02:02Z
---

# Episode: NIP-29 join request (kind 9021) for requesting channel access when not a member

## Prior State

The tenex-edge nostr fabric supported kind:0/kind:9 identity and channel operations (create/lock/put-user) but had no mechanism to request joining a channel you're not yet a member of. The daemon doesn't self-serve membership.

## Trigger

User directive (line 2876): 'for the tenex-edge nip29 — when you are not member of a channel you can request to join via the nip29 event.'

## Decision

Implement NIP-29 join-request event (kind 9021) to request access to a channel. The standard 9021 join-request is the correct mechanism for the NIP-29 relay. Implementation launched as a parallel workstream (task #17).

## Consequences

- Users can request to join nostr channels they're not members of via the standard NIP-29 protocol
- Extends the fabric's channel interaction vocabulary beyond create/lock/publish to include membership requests

## Open Tail

- Implementation in progress via async agent; not yet merged

## Evidence

- transcript lines 2876-2884

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-10-42f3cd42f2de-75af564c-6-nip-29-join-request-kind-9021.json`](transcripts/2026-07-10-42f3cd42f2de-75af564c-6-nip-29-join-request-kind-9021.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-6-nip-29-join-request-kind-9021.json`](transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-6-nip-29-join-request-kind-9021.json)
