---
type: episode-card
date: 2026-07-09
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: reversal
status: superseded
subjects:
  - tracking-ui-paradigm
  - today-screen
  - runner-flow
supersedes:
  - 2026-07-09-42f3cd42f2de-75af564c-2-ui-paradigm-overhaul-card-list-today
related_claims: []
source_lines:
  - 411-421
  - 527-534
  - 543-553
  - 692-706
captured_at: 2026-07-09T19:52:06Z
---

# Episode: TikTok-style one-set-at-a-time runner replaces list-based Today screen

## Prior State

The product spec and initial high-level vision described the Today screen as a vertical list of exercises with set rows — a 'fillable form' / 'smart checklist' where the whole workout is visible at once and you tap to log each set in place.

## Trigger

User directive at line 417: 'the UI should be tik-tok like where I only see what set I need to do next and perhaps cues or something that can be attached by the coach for the exercise' plus 'I should be able to tap next or provide very easily feedback on how easy/hard it felt.'

## Decision

The core tracking interaction is now a full-screen vertical pager — one set per page, swipe or tap Log & Next to advance. The Today screen is reduced to a launch/start screen; the runner is the primary tracking surface. Coach cues attach per-exercise-page as a quiet glass pill. Effort feedback (Easy/Moderate/Hard), Note, and Skip are inline controls on each set page.

## Consequences

- Today screen is no longer the '90% of usage' surface described in the spec — the runner is.
- Circuits/supersets require an inline mini-map (A1 ▶ A2) to maintain spatial awareness in a one-set-at-a-time flow.
- The planned-vs-actual distinction shifts from ghosted-vs-solid rows in a list to a single hero target per page with post-completion effort logging.
- Session flow became Today → Runner (22 steps) → Done, a three-state navigation stack with no NavigationStack.
- The HTML prototype's card-based list UI is now historical; the reference implementation is native SwiftUI.

## Open Tail

- Rest timer not yet implemented as a real countdown in the runner.
- Effort/note feedback does not yet visibly persist per set across pages.
- Done summary screen built but not yet verified with screenshots.

## Evidence

- transcript lines 411-421
- transcript lines 527-534
- transcript lines 543-553
- transcript lines 692-706

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-09-42f3cd42f2de-75af564c-1-tiktok-style-one-set-at-a.json`](transcripts/2026-07-09-42f3cd42f2de-75af564c-1-tiktok-style-one-set-at-a.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-1-tiktok-style-one-set-at-a.json`](transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-1-tiktok-style-one-set-at-a.json)
