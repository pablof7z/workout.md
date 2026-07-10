---
type: episode-card
date: 2026-07-10
session: 43fd928f-6da0-404c-a38a-406d6cdfb05f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/43fd928f-6da0-404c-a38a-406d6cdfb05f.jsonl
salience: architecture
status: active
subjects:
  - code-signing
  - provisioning
  - bundle-id
  - project-config
supersedes:
  - 2026-07-10-43fd928f6da0-b40f7d8e-1-code-signing-team-switched-from-personal
related_claims: []
source_lines:
  - 103-105
  - 212-214
  - 257-259
  - 274-296
  - 336-347
  - 367-367
captured_at: 2026-07-10T07:46:09Z
---

# Episode: Code signing switched from disabled/simulator-only to paid team (SANITY ISLAND LLC) with enforced bundle ID

## Prior State

project.yml had CODE_SIGNING_ALLOWED: NO, CODE_SIGNING_REQUIRED: NO, and no DEVELOPMENT_TEAM — the project was configured for simulator-only builds with no code signing.

## Trigger

User requested deployment to a physical iPhone, which requires signing. The initial build under the personal free team (C99QRJCR43) silently rewrote the bundle ID from com.workoutmd.prototype to md.workout. User explicitly corrected: 'no, use my team account -- and my bundle id'.

## Decision

Switched project.yml to automatic code signing under the paid SANITY ISLAND LLC team (456SHKPP26) — CODE_SIGNING_ALLOWED: YES, CODE_SIGN_STYLE: Automatic, DEVELOPMENT_TEAM: 456SHKPP26 — preserving the correct bundle ID com.workoutmd.prototype instead of letting the free team override it.

## Consequences

- App now installs and launches on physical devices with the correct bundle ID com.workoutmd.prototype scoped to team 456SHKPP26
- Future entitlements or capabilities (push notifications, iCloud, etc.) can be tied to the correct, stable bundle ID
- Build requires -allowProvisioningUpdates flag for Xcode to auto-generate provisioning profiles
- The personal free team (C99QRJCR43) is no longer used for this project, eliminating silent bundle-ID rewriting

## Open Tail

- If App Store distribution is needed later, a Distribution signing identity and explicit provisioning profile may be required beyond the current Automatic Development signing

## Evidence

- transcript lines 103-105
- transcript lines 212-214
- transcript lines 257-259
- transcript lines 274-296
- transcript lines 336-347
- transcript lines 367-367

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-10-43fd928f6da0-b40f7d8e-1-code-signing-switched-from-disabled-simulator.json`](transcripts/2026-07-10-43fd928f6da0-b40f7d8e-1-code-signing-switched-from-disabled-simulator.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-10-43fd928f6da0-b40f7d8e-1-code-signing-switched-from-disabled-simulator.json`](transcripts/raw/2026-07-10-43fd928f6da0-b40f7d8e-1-code-signing-switched-from-disabled-simulator.json)
