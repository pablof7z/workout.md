---
type: episode-card
date: 2026-07-09
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: product
status: superseded
subjects:
  - coach-interaction-model
  - swipe-right-coach
  - plan-mutation
  - shared-observable-session
  - remove-log-and-next
supersedes: []
related_claims: []
source_lines:
  - 741-745
  - 849-864
  - 900-913
captured_at: 2026-07-09T20:35:26Z
---

# Episode: Coach reimagined as swipe-right panel with live plan mutation

## Prior State

The coach was a button-triggered inline nudge ('Reduce Set 3 to 115?') with Accept/Ignore, plus a separate Note button on the bottom control cluster. Advancing required tapping a 'Log & Next' button. Notes were a simple text field.

## Trigger

User directive: 'instead of a notes button, let me swipe right on the screen to go to a notes screen -- just like on tiktok you can swipe right to go to someone's profile.' Furthermore: notes should run the agent — user writes 'this felt weird, hurt my back' and the coach replies, adjusts next set's weight, or decides to skip the exercise for weeks and modifies the program. Also: 'the log & next button we can remove since I would just swipe down to the next exercise when I'm done.'

## Decision

Coach becomes a place (swipe-right side panel), not a button. Note button and Log & Next are removed — advancing is implicit via swipe-down. The Coach screen is scoped to the current exercise, accepts plain-language input, replies in terse/dry voice per spec, and actually mutates the upcoming plan (reduce weight, skip, deload) with visible applied-diff lines. Architecture: shared @Observable WorkoutSession as single source of truth — coach, effort dial, and stepper all edit one model, changes propagate live to runner pages and list sheet.

## Consequences

- Log & Next button removed entirely; swipe-down = advancing + implicit logging
- Note button removed; notes live inside the Coach screen
- SessionView wraps a horizontal TabView(.page) with Coach (tag 0) at left and Runner (tag 1) at right, orthogonal to the runner's vertical paging
- Scripted keyword policy (pain/tired/easy/great/default) mutates WorkoutSession in place — e.g., 'hurt my back' → next Bench set 135→70 lb, confirmed live on runner
- Follow-up 'Deload 2 weeks' chip writes program-level notes
- Clean drop-in point for a real LLM model call later — the scripted policy is a placeholder
- EffortControl, CoachView, SessionView are new files requiring xcodegen re-generation

## Open Tail

- Coach is scripted mock, not a live LLM — real model integration is deferred
- Effort dial may need per-set reset on page advance

## Evidence

- transcript lines 741-745
- transcript lines 849-864
- transcript lines 900-913

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-09-42f3cd42f2de-75af564c-5-coach-reimagined-as-swipe-right-panel.json`](transcripts/2026-07-09-42f3cd42f2de-75af564c-5-coach-reimagined-as-swipe-right-panel.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-5-coach-reimagined-as-swipe-right-panel.json`](transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-5-coach-reimagined-as-swipe-right-panel.json)
