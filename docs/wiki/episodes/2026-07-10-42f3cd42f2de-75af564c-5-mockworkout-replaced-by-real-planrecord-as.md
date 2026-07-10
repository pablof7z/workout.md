---
type: episode-card
date: 2026-07-10
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: reversal
status: active
subjects:
  - mockworkout-removal
  - plan-record
  - today-screen
  - source-of-truth
supersedes:
  - 2026-07-10-42f3cd42f2de-75af564c-1-real-persisted-plan-model-replaces-hardcoded
related_claims: []
source_lines:
  - 2338-2340
  - 2375-2378
  - 2419-2442
  - 2457-2460
  - 2506-2516
captured_at: 2026-07-10T07:42:20Z
---

# Episode: MockWorkout replaced by real PlanRecord as Today source-of-truth

## Prior State

Today screen was driven by a hardcoded MockWorkout. SyncManager rendered plan.md from MockWorkout for iCloud sync. MockHistory seeded fake SAMPLE workout rows for demo purposes.

## Trigger

Real plans PR (#10) merged, introducing PlanRecord model, PlanStore, PlanEditorView, WhatsNextView (plan repair), and coach-generated plans. Finishing pass (PR #11) deleted MockHistory and MockWorkout references.

## Decision

Today screen now builds from the ACTIVE PlanRecord (queried via @Predicate isActive==true), never a hardcoded workout. SyncManager's MockWorkout-based plan.md write was removed (proper plan-sync deferred). MockHistory seeding deleted; History shows ContentUnavailableView empty state.

## Consequences

- SyncManager required a fix: line 141 still referenced deleted MockWorkout — the broken plan.md write was removed rather than rewired (PlanStore has no ModelContext in SyncManager)
- Session Markdown sync still works unchanged, but committing plan edits to GitHub was left out (plan export via Markdown ShareLink available today)
- startSession now takes a PlanRecord? parameter; activePlan computed from activePlans query
- Schema includes both WorkoutRecord.self and PlanRecord.self with cloudKitDatabase: .none
- Plan repair flow ('What should I do next?') reachable from Today via WhatsNextView

## Open Tail

- Plan.md sync to GitHub/iCloud not yet wired (SyncManager lacks ModelContext for plan rendering)

## Evidence

- transcript lines 2338-2340
- transcript lines 2375-2378
- transcript lines 2419-2442
- transcript lines 2457-2460
- transcript lines 2506-2516

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-10-42f3cd42f2de-75af564c-5-mockworkout-replaced-by-real-planrecord-as.json`](transcripts/2026-07-10-42f3cd42f2de-75af564c-5-mockworkout-replaced-by-real-planrecord-as.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-5-mockworkout-replaced-by-real-planrecord-as.json`](transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-5-mockworkout-replaced-by-real-planrecord-as.json)
