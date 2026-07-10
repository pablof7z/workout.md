---
type: episode-card
date: 2026-07-10
session: 43fd928f-6da0-404c-a38a-406d6cdfb05f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/43fd928f-6da0-404c-a38a-406d6cdfb05f.jsonl
salience: architecture
status: superseded
subjects:
  - code-signing
  - provisioning
  - project-yml
  - ios-deployment
supersedes: []
related_claims: []
source_lines:
  - 103-107
  - 212-214
  - 257-259
  - 274-296
  - 339-347
  - 367-367
captured_at: 2026-07-10T06:52:42Z
---

# Episode: Switch iOS project from no-signing/simulator to paid-team code signing

## Prior State

project.yml had CODE_SIGNING_ALLOWED: NO, CODE_SIGNING_REQUIRED: NO, and no DEVELOPMENT_TEAM — the project was configured for simulator-only builds with no code signing or provisioning.

## Trigger

User requested deployment to a physical iPhone. After the first successful deploy, the bundle ID came out as `md.workout` instead of `com.workoutmd.prototype` because the personal free team (C99QRJCR43) silently rewrote it. User explicitly corrected: 'no, use my team account -- and my bundle id'.

## Decision

Enabled automatic code signing (CODE_SIGNING_ALLOWED: YES, CODE_SIGN_STYLE: Automatic) and switched DEVELOPMENT_TEAM from the free personal team C99QRJCR43 to the paid SANITY ISLAND LLC team 456SHKPP26, which has real Distribution certs and preserves the intended bundle ID `com.workoutmd.prototype`.

## Consequences

- Bundle ID on device is now correctly `com.workoutmd.prototype` instead of the free-team-rewritten `md.workout`.
- Entitlements are scoped to team 456SHKPP26 (application-identifier = 456SHKPP26.com.workoutmd.prototype).
- Provisioning profile is now required (PROVISIONING_PROFILE_REQUIRED = YES) and Xcode auto-generates it via -allowProvisioningUpdates.
- Interactive Apple ID sign-in (2FA) is a prerequisite for future fresh provisioning — the assistant cannot do this step autonomously.
- project.yml is durably updated so all future builds use the SANITY ISLAND LLC team.
- The xcodeproj is gitignored (regenerated from project.yml), so the signing config lives in project.yml as the source of truth.

## Open Tail

- If entitlements tied to a specific bundle ID are added later, the bundle ID must remain com.workoutmd.prototype to match the provisioning profile registered under team 456SHKPP26.

## Evidence

- transcript lines 103-107
- transcript lines 212-214
- transcript lines 257-259
- transcript lines 274-296
- transcript lines 339-347
- transcript lines 367-367

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-10-43fd928f6da0-b40f7d8e-1-switch-ios-project-from-no-signing.json`](transcripts/2026-07-10-43fd928f6da0-b40f7d8e-1-switch-ios-project-from-no-signing.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-10-43fd928f6da0-b40f7d8e-1-switch-ios-project-from-no-signing.json`](transcripts/raw/2026-07-10-43fd928f6da0-b40f7d8e-1-switch-ios-project-from-no-signing.json)
