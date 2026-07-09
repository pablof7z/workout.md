---
type: episode-card
date: 2026-07-09
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: product
status: active
subjects:
  - runner-interaction-model
  - tiktok-pager
  - circuits-supersets
  - coach-cues
supersedes:
  - 2026-07-09-42f3cd42f2de-75af564c-3-runner-interaction-model-list-based-tracking
  - 2026-07-09-42f3cd42f2de-75af564c-4-circuits-and-supersets-elevated-to-first
  - 2026-07-09-42f3cd42f2de-75af564c-5-coach-reimagined-as-swipe-right-panel
related_claims: []
source_lines:
  - 414-421
  - 527-533
  - 543-553
  - 775-786
captured_at: 2026-07-09T20:35:26Z
---

# Episode: TikTok-style one-set-per-page runner with circuit/superset support

## Prior State

The original product spec and HTML prototype used a vertical list of today's exercises on a single scrolling 'Today' screen, showing all sets simultaneously with tap-to-log interactions.

## Trigger

User directive: 'the UI should be tik-tok like where I only see what set I need to do next and perhaps cues or something that can be attached by the coach for the exercise.' Also: 'I do circuits or supersets very often so make that representable on the UI.'

## Decision

Replaced the list-based Today screen with a TikTok-style vertical pager: one set per full-screen page, swipe/tap to advance. Circuits and supersets are first-class — a block model (WorkoutBlock/BlockKind) with rounds, rest pages between rounds, and an inline mini-map (A1 ▶ A2). Coach cues are attached per-exercise as a quiet glass pill on each page. Timed sets (e.g., Plank) get a live countdown ring with Start/pause/resume.

## Consequences

- WorkoutStep flatten() model expands blocks into 22 paginated steps with rest pages inserted between rounds (never after final round)
- Mini-map shows current movement in the superset/circuit with play.fill marker, others dimmed
- Top context strip shows exercise name + step count (e.g., 'Bench Press · 1/22')
- Tap top strip opens a full workout list sheet with jump-to-step navigation
- Timed sets show a 132pt circular progress ring with countdown, replacing the hero number

## Open Tail

- Effort dial may need to reset per set when paging (currently stays open)

## Evidence

- transcript lines 414-421
- transcript lines 527-533
- transcript lines 543-553
- transcript lines 775-786

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-09-42f3cd42f2de-75af564c-3-tiktok-style-one-set-per-page.json`](transcripts/2026-07-09-42f3cd42f2de-75af564c-3-tiktok-style-one-set-per-page.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-3-tiktok-style-one-set-per-page.json`](transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-3-tiktok-style-one-set-per-page.json)
