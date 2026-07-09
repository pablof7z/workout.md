---
type: episode-card
date: 2026-07-09
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: product
status: active
subjects:
  - circuit-superset
  - data-model
  - block-rounds
supersedes: []
related_claims: []
source_lines:
  - 415-416
  - 527-533
captured_at: 2026-07-09T19:29:45Z
---

# Episode: Circuit/superset support added as first-class data model

## Prior State

The spec and prototype modeled exercises as a flat sequential list — no concept of circuits, supersets, or grouped exercise blocks with rounds.

## Trigger

User directive: 'I do circuits or supersets very often so make that representable on the UI.' (line 415)

## Decision

Introduce a block model that groups exercises into circuits/supersets with rounds, and an inline movement mini-map (A1 ▶ A2 …) showing position within a circuit.

## Consequences

- Data model must support exercise grouping (blocks) with round counts, not just a flat exercise array
- TikTok-style runner must cycle through circuit exercises per round (A1, A2, A1, A2...) rather than linearly through all sets of one exercise before moving to the next
- Mini-map component is a new UI element showing current position within a superset/circuit
- Markdown storage format must represent circuit/superset structure — the spec's clean .md export needs a schema extension

## Open Tail

- Markdown representation format for circuits/supersets is not yet defined
- How plan-repair AI handles circuit structure when adjusting for deviations is unspecified
- Whether non-circuit workouts are treated as single-exercise blocks or a separate flat-list path is undecided

## Evidence

- transcript lines 415-416
- transcript lines 527-533

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-09-42f3cd42f2de-75af564c-3-circuit-superset-support-added-as-first.json`](transcripts/2026-07-09-42f3cd42f2de-75af564c-3-circuit-superset-support-added-as-first.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-3-circuit-superset-support-added-as-first.json`](transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-3-circuit-superset-support-added-as-first.json)
