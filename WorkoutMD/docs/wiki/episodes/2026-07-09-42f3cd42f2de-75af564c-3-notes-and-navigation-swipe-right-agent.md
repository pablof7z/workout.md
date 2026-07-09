---
type: episode-card
date: 2026-07-09
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: product
status: superseded
subjects:
  - notes-interaction
  - agent-in-session
  - swipe-navigation
  - log-and-next-removal
supersedes: []
related_claims: []
source_lines:
  - 741-745
captured_at: 2026-07-09T20:12:13Z
---

# Episode: Notes and navigation: swipe-right agent notes + swipe-down to advance (remove Log & Next)

## Prior State

Notes accessed via a button in the bottom control cluster. Advancing to the next set required tapping a 'Log & Next' button. AI interaction was strictly diff-based (inline nudges, proposed changes rendered as before/after) — the spec said 'no chatbot.'

## Trigger

User directive: 'instead of a notes button, let me swipe right on the screen to go to a notes screen -- just like on tiktok you can swipe right to go to someone's profile.' The notes should run the agent — e.g., user writes 'this hurt my back,' agent responds with weight reduction or program changes. Also: 'the log & next button we can remove since I would just swipe down to the next exercise when I'm done.'

## Decision

Notes become a swipe-right destination (horizontal swipe, TikTok-profile metaphor) instead of a button. Notes trigger an AI agent that interprets free-text feedback and can adjust the next set's weight, skip an exercise for sessions, or modify the program. The Log & Next button is removed — swipe down advances to the next set.

## Consequences

- Navigation model becomes purely gesture-based: swipe down = next set, swipe right = notes/agent screen
- Bottom control cluster loses both the Note button and the Log & Next button — only effort pills and reps stepper remain
- AI interaction model shifts: the spec's 'diff, not chatbot' posture is partially relaxed for the notes context, where the agent reads natural-language feedback and takes program-level actions
- The agent now has runtime authority to modify in-flight sessions (adjust next set weight) and future programming (skip exercise, ease back in two weeks) based on user notes — this exceeds the spec's original inline-nudge scope
- This has not yet been implemented — it was the last directive in the session

## Open Tail

- Swipe-right notes screen with agent integration is not yet built
- Log & Next button removal is not yet implemented
- Scope of agent autonomy over program changes (skip for weeks, weight reduction) needs boundary definition — spec flagged coach autonomy as an open question
- How agent responses are presented (conversational vs diff) in the notes context is unresolved

## Evidence

- transcript lines 741-745

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-09-42f3cd42f2de-75af564c-3-notes-and-navigation-swipe-right-agent.json`](transcripts/2026-07-09-42f3cd42f2de-75af564c-3-notes-and-navigation-swipe-right-agent.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-3-notes-and-navigation-swipe-right-agent.json`](transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-3-notes-and-navigation-swipe-right-agent.json)
