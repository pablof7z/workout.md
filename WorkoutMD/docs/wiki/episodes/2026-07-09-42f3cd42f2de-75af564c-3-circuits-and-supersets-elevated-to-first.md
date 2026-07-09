---
type: episode-card
date: 2026-07-09
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: product
status: superseded
subjects:
  - circuit-superset-model
  - workout-block-structure
  - minimap-navigation
supersedes: []
related_claims: []
source_lines:
  - 415-416
  - 529-531
  - 543-545
  - 609-624
  - 697-702
captured_at: 2026-07-09T19:52:06Z
---

# Episode: Circuits and supersets elevated to first-class domain model

## Prior State

The product spec listed 'structure for non-lifting workouts' as an open question and did not explicitly model circuits or supersets. The initial high-level vision and HTML prototype treated exercises as a flat vertical list with no grouping or round-awareness.

## Trigger

User directive at line 415: 'I do circuits or supersets very often so make that representable on the UI.'

## Decision

Circuits and supersets are now a first-class construct in the domain model: WorkoutBlock with BlockKind (straight-sets vs superset/circuit), rounds, and an inline movement mini-map showing the current position in the circuit (▶ A1 Incline DB Press · A2 Barbell Row). Rest pages are inserted between rounds but never after the final round.

## Consequences

- Data model requires a flatten() function that expands blocks into a flat [WorkoutStep] array (22 steps for the mock session) with rest pages interleaved.
- The TikTok-style runner depends on this flat step list — blocks are a data abstraction, the UI consumes linear steps.
- Superset/circuit pages display 'SUPERSET A · ROUND 1 OF 3' overline and a horizontal-scrollable mini-map with the current movement marked by play.fill.
- Block-specific visual theming (mood-key → gradient/glow color per movement) gives each block a distinct hue without card boundaries.
- The A1,A2,rest,A1,A2,rest,A1,A2 pattern is codified as the rest-insertion rule.

## Open Tail

- Circuit block (Face Pull / Cable Fly / Plank) was built but not yet screenshotted or verified.
- No specification yet for how circuits interact with plan-repair or coach adjustments mid-circuit.
- Rest pages exist but have no functional countdown timer.

## Evidence

- transcript lines 415-416
- transcript lines 529-531
- transcript lines 543-545
- transcript lines 609-624
- transcript lines 697-702

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-09-42f3cd42f2de-75af564c-3-circuits-and-supersets-elevated-to-first.json`](transcripts/2026-07-09-42f3cd42f2de-75af564c-3-circuits-and-supersets-elevated-to-first.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-3-circuits-and-supersets-elevated-to-first.json`](transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-3-circuits-and-supersets-elevated-to-first.json)
