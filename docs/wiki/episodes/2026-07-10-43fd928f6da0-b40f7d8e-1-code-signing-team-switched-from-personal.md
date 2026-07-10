---
type: episode-card
date: 2026-07-10
session: 43fd928f-6da0-404c-a38a-406d6cdfb05f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/43fd928f-6da0-404c-a38a-406d6cdfb05f.jsonl
salience: architecture
status: superseded
subjects:
  - code-signing
  - bundle-id
  - development-team
  - project-yml
supersedes:
  - 2026-07-10-43fd928f6da0-b40f7d8e-1-switch-ios-project-from-no-signing
related_claims: []
source_lines:
  []
captured_at: 2026-07-10T07:34:48Z
---

# Episode: Code signing team switched from personal free team to paid SANITY ISLAND LLC to preserve bundle ID

## Prior State

project.yml had CODE_SIGNING_ALLOWED: NO and no DEVELOPMENT_TEAM — simulator-only, no device signing. When signing was first enabled, it used the personal free team C99QRJCR43, which silently rewrote the bundle ID from com.workoutmd.prototype to md.workout.

## Trigger

User noticed the installed bundle ID was md.workout instead of the configured com.workoutmd.prototype and explicitly instructed: 'no, use my team account -- and my bundle id'.

## Decision

Switched DEVELOPMENT_TEAM to 456SHKPP26 (SANITY ISLAND LLC — paid account with real Distribution certs) and set CODE_SIGN_STYLE to Automatic with CODE_SIGNING_ALLOWED: YES in project.yml. This preserves the intended bundle ID com.workoutmd.prototype on device builds.

## Consequences

- project.yml now hardcodes DEVELOPMENT_TEAM: 456SHKPP26, making the paid team the default for all future device builds
- Bundle ID com.workoutmd.prototype is stable and no longer subject to free-team rewriting
- Entitlements are now scoped to 456SHKPP26.com.workoutmd.prototype, which matters if entitlements or capabilities are added later
- Simulator builds remain compatible since automatic signing does not interfere with simulator deployment

## Open Tail

- The signing identity display name still shows 'Pablo Fernandez (C99QRJCR43)' in build logs — cosmetic, but could cause confusion in future debugging

## Evidence

*(no verified line ranges)*

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-10-43fd928f6da0-b40f7d8e-1-code-signing-team-switched-from-personal.json`](transcripts/2026-07-10-43fd928f6da0-b40f7d8e-1-code-signing-team-switched-from-personal.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-10-43fd928f6da0-b40f7d8e-1-code-signing-team-switched-from-personal.json`](transcripts/raw/2026-07-10-43fd928f6da0-b40f7d8e-1-code-signing-team-switched-from-personal.json)
