---
type: episode-card
date: 2026-07-10
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: product
status: active
subjects:
  - set-state-model
  - active-pointer-removal
  - runner-semantics
supersedes: []
related_claims: []
source_lines:
  - 3496-3520
  - 3525-3541
captured_at: 2026-07-10T11:31:29Z
---

# Episode: Per-set stateful model replaces active-pointer concept

## Prior State

The runner used a two-pointer model: `viewStepID` (scroll position / peek) and `activeStepID` (the set currently being logged). Navigating to a future set showed a 'Previewing — not logged' chip; only the active set could be done/skipped. Reps/weight were frozen once a set was committed.

## Trigger

User objected: 'why does it say previewing — not logged? if I skip to some workout in the future I need to always be able to do it/skip it.' User specified that any set should be re-stateable after the fact (skipped→done, done→skipped, back to pending) and reps/weight should remain editable even after marking done.

## Decision

Removed the active/view pointer split entirely. Every set is now independently stateful via a `SetState` enum (`.pending`/`.done`/`.skipped`) persisted per-set on `WorkoutSession.steps`. `WorkoutSession.setState(_:for:)` replaces `complete(active:)`/`skip(active:)`/`advanceActive()`. Navigation is free — `currentStepID` is only used for scroll position, not for locking interaction. Reps/weight rows are never frozen.

## Consequences

- No concept of a 'current set you're locked to' — users can navigate freely and act on any set, past or future
- Slider thumb is live and interactive on every page unconditionally, not just the active set
- Reps/weight remain editable after a set is marked done, so users can fix wrong values without losing committed state
- Removed DONE/SKIPPED text badges and exercise-name strikethrough — slider position is the sole status indicator
- Thumb-driven auto-advance/auto-finish was dropped (a separate Finish button handles session completion)

## Open Tail

- Slider rest positions, threshold, and haptics tuning still pending user feedback

## Evidence

- transcript lines 3496-3520
- transcript lines 3525-3541

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-10-42f3cd42f2de-75af564c-1-per-set-stateful-model-replaces-active.json`](transcripts/2026-07-10-42f3cd42f2de-75af564c-1-per-set-stateful-model-replaces-active.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-1-per-set-stateful-model-replaces-active.json`](transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-1-per-set-stateful-model-replaces-active.json)
