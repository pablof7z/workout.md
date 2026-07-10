---
type: episode-card
date: 2026-07-10
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: architecture
status: active
subjects:
  - coach-grounding
  - doctrine-store
  - external-commit-review
  - memory-scoping
supersedes: []
related_claims: []
source_lines:
  - 2535-2557
captured_at: 2026-07-10T07:02:02Z
---

# Episode: Coach grounding architecture: goals + doctrine + external-commit review folded into every coach turn

## Prior State

The coach (rig.rs with 5 tools) worked but received no goals/preferences (M4), never reviewed external GitHub commits (M2), had no training-doctrine support (M7), and memory was unscoped — all coach notes across all plans were mixed together.

## Trigger

Opus audit flagged M2 ('agent reviews new commits' not wired to coach), M4 ('goals/prefs never reach coach'), M7 ('scope coach memory'), and p2 ('memory scoping').

## Decision

CoachController.send now folds three new grounding sources into combinedUserMessage: (1) AppSettings.goalsContextSnippet for user goals, (2) DoctrineStore.shared.digest() for uploaded training doctrine (file-persisted JSON, paste/import/remove in Settings), (3) CoachReviewStore.contextSnippet() for coach-generated review notes from external commits. SyncManager.onExternalChanges now calls CoachController.shared.reviewExternalChanges which runs a real coach turn over changed Markdown and appends to CoachReviewStore. CoachNoteRecord gained optional planID; CoachController.historyJSON now scopes memory to the active plan plus a 60-day recency window.

## Consequences

- Every coach turn is now grounded by user goals, uploaded doctrine, and external-commit reviews — not just conversation history
- External GitHub commits trigger a real coach review turn whose output feeds back into subsequent grounding
- Memory is plan-scoped with a recency window, preventing cross-plan noise
- Verified live: coach reply echoed configured goal, disliked exercise, and uploaded 5/3/1 doctrine percentages end-to-end

## Open Tail

*(none)*

## Evidence

- transcript lines 2535-2557

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-10-42f3cd42f2de-75af564c-2-coach-grounding-architecture-goals-doctrine-external.json`](transcripts/2026-07-10-42f3cd42f2de-75af564c-2-coach-grounding-architecture-goals-doctrine-external.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-2-coach-grounding-architecture-goals-doctrine-external.json`](transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-2-coach-grounding-architecture-goals-doctrine-external.json)
