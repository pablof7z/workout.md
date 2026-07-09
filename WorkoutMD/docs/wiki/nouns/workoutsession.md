---
type: noun-entry
slug: workoutsession
name: "WorkoutSession"
origin: extracted
source_refs:
  - transcript:853-853
---

# WorkoutSession

An @Observable final class (Observation framework) serving as the single source of truth for a workout: mutable steps, currentStepID, per-set RPE, per-exercise transcripts, offerDeload, and deloaded state. It owns all edit logic (adjustReps, skip, setEffort, sendCoachMessage, applyDeload, buildSummary) so coach edits, effort dial, and stepper all mutate one shared model and changes propagate live to the runner's upcoming pages.
