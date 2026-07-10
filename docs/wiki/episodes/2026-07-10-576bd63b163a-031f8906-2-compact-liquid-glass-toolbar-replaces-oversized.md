---
type: episode-card
date: 2026-07-10
session: 576bd63b-163a-4e6a-8a3b-611cd421a386
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/576bd63b-163a-4e6a-8a3b-611cd421a386.jsonl
salience: product
status: active
subjects:
  - controls-view
  - effort-control
  - liquid-glass-toolbar
  - runner-layout
supersedes:
  - 2026-07-10-576bd63b163a-031f8906-2-effort-control-redesigned-from-oversized-bar
related_claims: []
source_lines:
  - 1-6
  - 646-654
  - 876-901
  - 944-955
  - 1058-1059
  - 1429-1435
captured_at: 2026-07-10T07:19:03Z
---

# Episode: Compact Liquid Glass toolbar replaces oversized effort bar

## Prior State

The 'Rate effort' control was a large, oversized bar at the bottom of the runner screen, sharing space with Skip as full-width elements. EffortControl owned its own expanded state internally.

## Trigger

User said: 'the rate effort being that big is horrible, skip, rate effort -- those should be small buttons in a liquidglass toolbar.' During implementation, a clipping bug was discovered: when the effort scale expanded next to Skip, the 'Set' commit button was clipped.

## Decision

Replaced with a compact two-button Liquid Glass toolbar: Rate effort and Skip/Finish as small auto-width pills (44pt tall, ~100pt and ~52pt wide respectively). Lifted EffortControl's expanded state to ControlsView via @Binding so the parent can hide Skip/Finish while the effort scale is expanded — the expanded scale needs the full row width and the two can't coexist.

## Consequences

- The 'Set' commit button no longer gets clipped during effort expansion
- EffortControl's expanded state is now parent-owned (ControlsView), creating a binding contract between the two components
- Verified via simulator that Skip correctly hides during expansion and reappears after commit
- Other full-width buttons in the app (TodayView, OnboardingView, DoneView, WhatsNextView) were audited and confirmed as correct single/sequential CTAs — not the same antipattern

## Open Tail

*(none)*

## Evidence

- transcript lines 1-6
- transcript lines 646-654
- transcript lines 876-901
- transcript lines 944-955
- transcript lines 1058-1059
- transcript lines 1429-1435

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-10-576bd63b163a-031f8906-2-compact-liquid-glass-toolbar-replaces-oversized.json`](transcripts/2026-07-10-576bd63b163a-031f8906-2-compact-liquid-glass-toolbar-replaces-oversized.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-10-576bd63b163a-031f8906-2-compact-liquid-glass-toolbar-replaces-oversized.json`](transcripts/raw/2026-07-10-576bd63b163a-031f8906-2-compact-liquid-glass-toolbar-replaces-oversized.json)
