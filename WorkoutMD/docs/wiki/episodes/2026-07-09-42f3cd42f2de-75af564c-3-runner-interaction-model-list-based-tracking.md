---
type: episode-card
date: 2026-07-09
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: product
status: superseded
subjects:
  - runner-interaction
  - tiktok-pager
  - swipe-navigation
  - coach-screen
  - implicit-logging
supersedes:
  - 2026-07-09-42f3cd42f2de-75af564c-1-today-screen-interaction-model-list-tiktok
  - 2026-07-09-42f3cd42f2de-75af564c-3-notes-and-navigation-swipe-right-agent
related_claims: []
source_lines:
  - 417-419
  - 741-746
  - 747-763
captured_at: 2026-07-09T20:16:44Z
---

# Episode: Runner interaction model: list-based tracking replaced by TikTok-style one-set pager with swipe-based coach panel

## Prior State

The product spec and initial design described a vertical list of today's exercises on a single scrolling screen, with explicit Log & Next and Note buttons to advance and annotate sets.

## Trigger

Two-stage user directives: (1) 'the UI should be tik-tok-like where I only see what set I need to do next and perhaps cues' and (2) 'instead of a notes button, let me swipe right on the screen to go to a notes screen… the log & next button we can remove since I would just swipe down to the next exercise when I'm done.'

## Decision

Replaced the list-based tracking screen with a full-screen vertical pager (one set per page, swipe down to advance). Advancing = implicit logging (no explicit Log & Next button). Swipe right opens a per-exercise Coach screen where the user writes free-text feedback and the coach responds with terse dry replies that actually mutate the upcoming plan (reduce weight, skip exercise, deload, add program notes). Removed Note button — notes live on the Coach screen. Coach is a scripted keyword-driven policy mock with a drop-in point for a real LLM.

## Consequences

- RunnerView uses ScrollView with .scrollTargetBehavior(.paging) and .containerRelativeFrame for full-screen page snaps
- Coach becomes a 'place' (side panel) rather than a button, aligning with the spec's 'AI as a diff, not a chatbot' principle
- Plan mutation is visible as applied-diff lines and upcoming sets in the runner reflect changes
- Effort pills (Easy/Moderate/Hard), reps stepper, and Skip remain as floating glass controls; Log & Next and Note buttons removed
- Scripted coach policy handles keyword-driven responses (back pain → reduce weight, skip for 2 weeks) as a mock that genuinely edits the step list

## Open Tail

- Coach screen with scripted policy not yet built at session end — was queued after polish batch
- Real LLM integration is a future drop-in point

## Evidence

- transcript lines 417-419
- transcript lines 741-746
- transcript lines 747-763

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-09-42f3cd42f2de-75af564c-3-runner-interaction-model-list-based-tracking.json`](transcripts/2026-07-09-42f3cd42f2de-75af564c-3-runner-interaction-model-list-based-tracking.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-3-runner-interaction-model-list-based-tracking.json`](transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-3-runner-interaction-model-list-based-tracking.json)
