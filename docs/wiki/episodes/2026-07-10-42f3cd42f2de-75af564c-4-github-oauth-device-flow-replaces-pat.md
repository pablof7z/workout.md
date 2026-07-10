---
type: episode-card
date: 2026-07-10
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: reversal
status: active
subjects:
  - github-auth
  - oauth-device-flow
  - sync
  - pat-demotion
supersedes: []
related_claims: []
source_lines:
  - 2886-2887
  - 2936-2940
  - 2953-2969
  - 3038-3045
captured_at: 2026-07-10T07:42:20Z
---

# Episode: GitHub OAuth device flow replaces PAT as primary auth

## Prior State

GitHub sync authentication required pasting a Personal Access Token (PAT) with repo scope. GitHubAuth had a TODO for real OAuth client id. Settings honestly said device-flow 'isn't wired up yet.'

## Trigger

User provided OAuth App Client ID (Ov23liOoVH2edVWyaqJr) and wanted proper 'Sign in with GitHub' without token pasting. User registered the OAuth App with device flow enabled.

## Decision

Wired GitHubAuth.deviceFlowClientID to the real Client ID. 'Sign in with GitHub' (device flow) is now the primary auth method in Settings → Sync, showing a user code + copy + 'Open GitHub' link + live polling. PAT entry was demoted under an 'Advanced' disclosure as a fallback.

## Consequences

- Verified live: curl to /login/device/code returned user_code B593-7E63; real flow from Settings UI produced user_code 6B6F-4973 with full copy/open/polling working
- Client ID is public (device-flow client IDs are designed to be shipped in-app), no client secret needed
- Callback URL field required by GitHub but unused by device flow — set to repo URL as placeholder
- Merged as part of PR #14, deployed to device

## Open Tail

*(none)*

## Evidence

- transcript lines 2886-2887
- transcript lines 2936-2940
- transcript lines 2953-2969
- transcript lines 3038-3045

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-10-42f3cd42f2de-75af564c-4-github-oauth-device-flow-replaces-pat.json`](transcripts/2026-07-10-42f3cd42f2de-75af564c-4-github-oauth-device-flow-replaces-pat.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-4-github-oauth-device-flow-replaces-pat.json`](transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-4-github-oauth-device-flow-replaces-pat.json)
