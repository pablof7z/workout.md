---
type: episode-card
date: 2026-07-09
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: reversal
status: superseded
subjects:
  - today-screen
  - runner
  - interaction-model
  - circuits-supersets
  - coach-cues
supersedes:
  - 2026-07-09-42f3cd42f2de-75af564c-1-tiktok-style-one-set-at-a
  - 2026-07-09-42f3cd42f2de-75af564c-3-circuits-and-supersets-elevated-to-first
related_claims: []
source_lines:
  - 411-420
  - 527-533
  - 548-553
captured_at: 2026-07-09T20:12:13Z
---

# Episode: Today screen interaction model: list → TikTok-style one-set runner

## Prior State

Spec defined the Today screen as a vertical list of exercises with ghosted prescribed vs solid actual set rows, tap-to-log, with skip/substitute/add-set as inline chips. The whole session visible at once like a fillable form.

## Trigger

User directive: 'the UI should be tik-tok-like where I only see what set I need to do next and perhaps cues or something that can be attached by the coach for the exercise. I should be able to tap next or provide very easily feedback on how easy/hard it felt or write a note.' Also: circuits/supersets must be representable.

## Decision

Replaced the list-based Today screen with a full-screen vertical paging runner — one set per page, swipe/tap to advance. Each page shows hero target numbers, a mini-map for superset/circuit rounds (A1 ▶ A2), per-exercise coach cues in a glass pill, and Easy/Moderate/Hard effort pills. Circuits and supersets are first-class block types with rounds and rest pages.

## Consequences

- Circuits/supersets became first-class with block model (BlockKind: straight-sets vs superset vs circuit), inline mini-map, and rest pages between rounds (never after final round)
- Coach cues attached per exercise as a quiet glass quote pill — coach's presence is contextual, not conversational
- Effort feedback reduced to three-tap pills (Easy/Moderate/Hard) with haptic confirmation
- Reps stepper for adjusting actuals on the current page
- Session flow became Today → Runner (22 steps) → Done
- The list-based 'scoreboard' mental model from the spec is now historical for the in-workout screen

## Open Tail

- Time-based sets (Plank) need a live countdown timer — queued but not yet implemented
- Tap top strip to see full step list with jump-to — queued but not yet implemented

## Evidence

- transcript lines 411-420
- transcript lines 527-533
- transcript lines 548-553

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-09-42f3cd42f2de-75af564c-1-today-screen-interaction-model-list-tiktok.json`](transcripts/2026-07-09-42f3cd42f2de-75af564c-1-today-screen-interaction-model-list-tiktok.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-1-today-screen-interaction-model-list-tiktok.json`](transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-1-today-screen-interaction-model-list-tiktok.json)
