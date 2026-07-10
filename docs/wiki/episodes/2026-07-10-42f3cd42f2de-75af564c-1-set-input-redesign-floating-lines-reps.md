---
type: episode-card
date: 2026-07-10
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: product
status: active
subjects:
  - set-input-ui
  - runner-view
  - reps-weight-editing
supersedes:
  - 2026-07-10-42f3cd42f2de-75af564c-5-set-input-ui-redesign-tap-to
related_claims: []
source_lines:
  - 2751-2757
  - 2856-2860
  - 2906-2926
  - 3011-3019
  - 3036-3049
  - 3051-3075
captured_at: 2026-07-10T07:42:20Z
---

# Episode: Set-input redesign: floating-lines reps+weight in main content

## Prior State

Reps editing was in a bottom cluster; weight was not directly editable. The set target block was not in the primary content area under 'Set X of Y'.

## Trigger

User correction: 'not only reps need to be editable; weight also!' and 'change the placement of where you put the reps input part and put it in the main part, right under set x of y'. Later refined: reps and resistance on separate lines, −/+ always visible, no glass pill containers, floating as text, vertically centered.

## Decision

Adopted 'V7 floating-lines' design: reps and resistance appear as two always-visible floating text lines (− 10 reps + / − 135 lb +) centered under Set X of Y, no glass containers. Effort button became a small icon-only round button. Both reps and weight mutate the live WorkoutSession.

## Consequences

- Bodyweight moves hide the weight line automatically; timed sets keep the countdown timer
- Effort RPE dial is now accessed via a small icon-only button rather than a labeled button
- Skip button remains for now but is targeted for removal by the diagonal-swipe gesture concept
- Merged as PR #15, deployed to Pablo's iPhone 17 Pro Max
- Diagonal-swipe completion gesture (up+right=done, up+left=skip, straight up=peek) proposed as next evolution of this surface — mock approved, not yet implemented

## Open Tail

- Diagonal swipe gesture for set completion/peek/skip — interactive HTML mock approved for build, not yet wired into RunnerView
- kg unit option not yet wired

## Evidence

- transcript lines 2751-2757
- transcript lines 2856-2860
- transcript lines 2906-2926
- transcript lines 3011-3019
- transcript lines 3036-3049
- transcript lines 3051-3075

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-10-42f3cd42f2de-75af564c-1-set-input-redesign-floating-lines-reps.json`](transcripts/2026-07-10-42f3cd42f2de-75af564c-1-set-input-redesign-floating-lines-reps.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-1-set-input-redesign-floating-lines-reps.json`](transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-1-set-input-redesign-floating-lines-reps.json)
