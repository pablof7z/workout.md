---
type: episode-card
date: 2026-07-09
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: product
status: superseded
subjects:
  - ui-paradigm
  - today-screen
  - circuit-superset-model
  - full-bleed-design
  - coach-cues
supersedes: []
related_claims: []
source_lines:
  - 411-421
  - 527-553
  - 609-624
captured_at: 2026-07-09T19:44:55Z
---

# Episode: UI paradigm overhaul: card-list Today screen → full-bleed TikTok-style set runner with circuit support

## Prior State

The product spec and the assistant's initial vision described the primary surface as a vertical list of exercise cards on a 'Today' screen, each showing all sets (ghosted prescribed vs. solid actual), with card-container UI patterns carried over from the web prototype.

## Trigger

User issued four simultaneous directives: (1) 'don't use card containers -- those are for the web and look bad on iphone -- bleed-edge instead', (2) 'the UI should be tik-tok-like where I only see what set I need to do next', (3) 'I do circuits or supersets very often so make that representable on the UI', (4) 'I should be able to tap next or provide very easily feedback on how easy/hard it felt or write a note'.

## Decision

Complete redesign of the primary interaction surface: a full-bleed vertical paging runner showing one set per full-screen page with swipe/tap to advance; circuits and supersets modeled as first-class BlockKind groups with a horizontal mini-map (A1 ▶ A2 …) for navigation context; coach cues attached per-exercise as quiet glass pills; per-set effort feedback (Easy/Moderate/Hard pills), quick Note and Skip, and a primary Log & Next button; glass material reserved strictly for floating controls — no card containers anywhere.

## Consequences

- Domain model gains WorkoutBlock/BlockKind (straight-sets vs superset/circuit) and a flatten() function that expands blocks into a flat [WorkoutStep] array with rest pages inserted between rounds
- Mini-map row provides circuit navigation context within the one-set-at-a-time paradigm
- Full-bleed gradient backgrounds keyed by movement (MoodKey → color), bleeding under Dynamic Island and floating chrome
- Glass is a floating-control-only material, not a content container — a durable design doctrine for the app
- The 'Today' screen becomes a start screen with a single glassProminent Start button; the runner is the main event
- Planned-vs-actual distinction shifts from visible-on-one-screen to sequential-reveal within the paging flow

## Open Tail

- How deviations (skips, subs, pain flags) surface in the one-set-at-a-time flow — partially mocked but not fully designed
- How the plan/calendar and coach-config surfaces translate to native iOS from the web prototype
- Markdown export and data-ownership promise not yet implemented in native app

## Evidence

- transcript lines 411-421
- transcript lines 527-553
- transcript lines 609-624

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-09-42f3cd42f2de-75af564c-2-ui-paradigm-overhaul-card-list-today.json`](transcripts/2026-07-09-42f3cd42f2de-75af564c-2-ui-paradigm-overhaul-card-list-today.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-2-ui-paradigm-overhaul-card-list-today.json`](transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-2-ui-paradigm-overhaul-card-list-today.json)
