---
type: episode-card
date: 2026-07-10
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: reversal
status: superseded
subjects:
  - plan-model
  - mockworkout-removal
  - plan-repair
supersedes:
  - 2026-07-09-42f3cd42f2de-75af564c-3-circuit-superset-support-added-as-first
related_claims: []
source_lines:
  - 2317-2370
  - 2441-2446
captured_at: 2026-07-10T07:02:02Z
---

# Episode: Real persisted plan model replaces hardcoded MockWorkout demo

## Prior State

The entire app was a single hardcoded MockWorkout — Today, Runner, and sync all referenced a static workout. There was no plan library, no plan creation/editing, and no plan-repair/'what's next' surface outside a running session.

## Trigger

Opus audit flagged BLOCKER B2 ('entire app is a single hardcoded MockWorkout, no real plans, edit_plan no-ops') and MAJOR M5 ('no what's-next surface outside a running session').

## Decision

Introduced a full SwiftData plan hierarchy: PlanRecord → PlanBlockRecord → PlanExerciseRecord → PlanSetRecord (supporting straight/superset/circuit, per-set reps/weight/timed holds). MockWorkout deleted; a real DefaultPlanSeed seeds one non-mock default plan. WorkoutSession now takes activePlan/ModelContext. Added PlansListView, PlanEditorView, coach-generated plans (CoachController.generatePlan), and WhatsNextView for plan-repair. edit_plan now mutates the active PlanRecord via a deterministic PlanEditInterpreter (avoiding nested-LLM-call deadlock).

## Consequences

- Today screen now reads from the active PlanRecord instead of a static mock — the one-workout demo is dead
- Plan edits persist across launches and drive the runner exactly via PlanConversion
- Coach can generate plans from goals and repair forward after gaps, with a deterministic fallback when no coach is reachable
- SyncManager lost its MockWorkout reference and the plan.md sync write was removed (plan sync via ShareLink only for now)
- Coach memory gained optional planID scoping as part of the same workstream

## Open Tail

- Committing plan edits to GitHub/iCloud not yet wired (plan export via Markdown ShareLink only)

## Evidence

- transcript lines 2317-2370
- transcript lines 2441-2446

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-10-42f3cd42f2de-75af564c-1-real-persisted-plan-model-replaces-hardcoded.json`](transcripts/2026-07-10-42f3cd42f2de-75af564c-1-real-persisted-plan-model-replaces-hardcoded.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-1-real-persisted-plan-model-replaces-hardcoded.json`](transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-1-real-persisted-plan-model-replaces-hardcoded.json)
