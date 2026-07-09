---
type: episode-card
date: 2026-07-09
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: product
status: superseded
subjects:
  - circuits
  - supersets
  - block-model
  - mini-map
  - workout-structure
supersedes: []
related_claims: []
source_lines:
  - 411-421
  - 530-531
  - 536-553
captured_at: 2026-07-09T20:16:44Z
---

# Episode: Circuits and supersets elevated to first-class UI representation

## Prior State

The product spec mentioned strength/hypertrophy support but did not explicitly model circuits or supersets in the UI; the initial mental model showed only straight-set exercises (Bench Press 3×10).

## Trigger

User directive: 'I do circuits or supersets very often so make that representable on the UI.'

## Decision

Introduced a block-level data model (WorkoutBlock / BlockKind: straight-sets vs. superset vs. circuit) with rounds, a flatten() function that expands blocks into a flat step list with rest pages between rounds (pattern: A1,A2,rest,A1,A2), an inline horizontal mini-map showing movement positions (▶ A1 Incline DB Press · A2 Barbell Row), and per-block color hue shifts (chest=crimson, superset=purple).

## Consequences

- 22-step workout model with rest pages inserted between rounds but never after the final round
- Mini-map component (MiniMapRow) provides spatial context within superset/circuit blocks without leaving the one-set-per-page paradigm
- Top context strip shows block type and round info (SUPERSET A · ROUND 1 OF 3)
- Rest pages get their own full-screen treatment distinct from set pages

## Open Tail

- Circuit block (Face Pull / Cable Fly / Plank) was built but not yet screenshotted or verified at session end

## Evidence

- transcript lines 411-421
- transcript lines 530-531
- transcript lines 536-553

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-09-42f3cd42f2de-75af564c-4-circuits-and-supersets-elevated-to-first.json`](transcripts/2026-07-09-42f3cd42f2de-75af564c-4-circuits-and-supersets-elevated-to-first.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-4-circuits-and-supersets-elevated-to-first.json`](transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-4-circuits-and-supersets-elevated-to-first.json)
