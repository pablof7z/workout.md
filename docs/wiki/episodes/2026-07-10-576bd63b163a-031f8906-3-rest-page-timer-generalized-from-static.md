---
type: episode-card
date: 2026-07-10
session: 576bd63b-163a-4e6a-8a3b-611cd421a386
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/576bd63b-163a-4e6a-8a3b-611cd421a386.jsonl
salience: product
status: superseded
subjects:
  - rest-timer
  - countdown
  - step-page-view
supersedes:
  - 2026-07-10-576bd63b163a-031f8906-3-countdown-generalized-to-all-timed-pages
related_claims: []
source_lines:
  - 1-5
  - 810-823
  - 1052-1062
  - 1437-1522
captured_at: 2026-07-10T07:00:27Z
---

# Episode: Rest page timer generalized from static number to live countdown ring

## Prior State

The Rest page displayed a static, non-counting seconds number. Only the Plank (timed-set) hero had a live countdown. The user's directive was that 'anything that is time-based should have the countdown — not just this single plank thing.'

## Trigger

User directive: all time-based pages should have a countdown, not just the plank timed-set hero.

## Decision

The Rest page now renders a live, auto-starting countdown ring matching the Plank-style timed hero. Every timed page in the runner (both timed sets and rest beats) now behaves consistently with a live countdown.

## Consequences

- Rest timer auto-starts without requiring a 'Start' tap (verified: 20→18 seconds between consecutive screenshots).
- The timed-set hero countdown was already generic per-exercise, not Plank-specific — only Rest was the gap.
- All other `seconds`/timer references in the codebase (data model fields, plan editor inputs, static list-row labels in WorkoutListView) remain correctly static — the runner was the only place displaying a live countdown.

## Open Tail

- Straight-set blocks (e.g. Bench Press) currently have NO rest step inserted between sets at all — PlanConversion only inserts RestPageInfo for superset/circuit blocks. This is a feature gap, not a leftover bug, and was identified but not resolved in this session.

## Evidence

- transcript lines 1-5
- transcript lines 810-823
- transcript lines 1052-1062
- transcript lines 1437-1522

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-10-576bd63b163a-031f8906-3-rest-page-timer-generalized-from-static.json`](transcripts/2026-07-10-576bd63b163a-031f8906-3-rest-page-timer-generalized-from-static.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-10-576bd63b163a-031f8906-3-rest-page-timer-generalized-from-static.json`](transcripts/raw/2026-07-10-576bd63b163a-031f8906-3-rest-page-timer-generalized-from-static.json)
