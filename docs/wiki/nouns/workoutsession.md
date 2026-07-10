---
type: noun-entry
slug: workoutsession
name: "WorkoutSession"
origin: extracted
source_refs:
  - transcript:853-853
---

# WorkoutSession

A shared @Observable (Observation framework) single source of truth owning mutable steps, currentStepID, per-set RPE, per-exercise transcripts, offerDeload, and deloaded state; all edit logic (adjustReps, skip, setEffort, sendCoachMessage, applyDeload, buildSummary) lives on it.
