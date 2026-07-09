---
type: episode-card
date: 2026-07-09
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: product
status: active
subjects:
  - today-screen
  - interaction-model
  - set-runner
  - coach-cues
supersedes: []
related_claims: []
source_lines:
  - 417-419
  - 527-533
captured_at: 2026-07-09T19:29:45Z
---

# Episode: Today screen interaction model: list view → TikTok-style one-set-at-a-time runner

## Prior State

The spec and both prototypes defined the Today screen as a vertical list of all exercises with set rows — a 'fillable form' where the whole workout is visible and you tap individual sets to log. Coach appeared as inline nudges within the list.

## Trigger

User directive: 'the UI should be tik-tok like where I only see what set I need to do next and perhaps cues or something that can be attached by the coach for the exercise. I should be able to tap next or provide very easily feedback on how easy/hard it felt or write a note or whatever.' (lines 417-419)

## Decision

Replace the list-based Today screen with a full-screen, one-set-per-page runner. Each page shows only the current set to perform, with tap/swipe to advance. Coach cues attach per-exercise on the current page. Feedback (Easy/Moderate/Hard pills, quick Note, Skip) and a big Log & Next button are inline on each page.

## Consequences

- Core product loop changes from 'open → see all exercises → tap sets in a form' to 'open → see one set → log → advance to next set'
- The 'scoreboard' mental model from the spec (see everything at once) is replaced by a 'guided runner' model (one thing at a time)
- Coach cues become a first-class per-exercise attachment shown on-screen during the set, not an inline nudge after a missed rep
- Effort/feedback capture (Easy/Moderate/Hard) moves from a post-workout concern to a per-set inline action
- The spec's 'one screen you live in' is reinterpreted: still one screen, but now paginated by set rather than scrolled by exercise

## Open Tail

- How to navigate back to review or edit a previously logged set in the runner flow is unspecified
- How the progress bar / sets-logged indicator from the original design surfaces in a one-set-at-a-time view is unresolved
- Whether users can see upcoming sets (preview) or only the current one is not yet decided

## Evidence

- transcript lines 417-419
- transcript lines 527-533

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-09-42f3cd42f2de-75af564c-2-today-screen-interaction-model-list-view.json`](transcripts/2026-07-09-42f3cd42f2de-75af564c-2-today-screen-interaction-model-list-view.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-2-today-screen-interaction-model-list-view.json`](transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-2-today-screen-interaction-model-list-view.json)
