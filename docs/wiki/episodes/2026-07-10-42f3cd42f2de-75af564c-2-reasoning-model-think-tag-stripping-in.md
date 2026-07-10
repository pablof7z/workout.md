---
type: episode-card
date: 2026-07-10
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: root-cause
status: active
subjects:
  - coach-streaming
  - think-stripper
  - reasoning-models
supersedes:
  - 2026-07-10-42f3cd42f2de-75af564c-3-reasoning-model-think-tag-leak-root
related_claims: []
source_lines:
  - 2632-2636
  - 2797-2818
  - 2820-2832
captured_at: 2026-07-10T07:42:20Z
---

# Episode: Reasoning-model think-tag stripping in coach streaming

## Prior State

Coach streamed rig.rs StreamedAssistantContent::Text verbatim into the UI with no reasoning-tag awareness. Reasoning models (glm-5.2:cloud, deepseek-r1, qwq) leaked raw <think>/</think> (or orphan </think>) markers inline in coach replies.

## Trigger

Final Opus readiness gate (line 2633) found the leak: 'The live reply from glm-5.2:cloud rendered a raw </think> marker inline.' User's local models emit these tags, making it a visible defect for their setup.

## Decision

Implemented ThinkStripper.swift — a Foundation-only helper with strip(_:) (one-shot) and Buffer (streaming accumulator). CoachController's onTextDelta runs each delta through a per-turn Buffer; onCompleted runs the full text through strip(_:) before persisting. Handles tags split across delta boundaries with holdback, and the real bug's shape: a model that omits the opening <think> tag where the first orphan retroactively hides everything back to turn start.

## Consequences

- Models.swift changed from append-only appendStreamingDelta to replaceStreamingText since visible projection can shrink mid-stream
- 18 unit tests added (WorkoutMDTests target created) covering chunked blocks, split deltas, orphan tags, passthrough, edge cases
- Caught and fixed a regex bug: 'thinking?' only matches 'thinkin'+optional 'g' — corrected to 'think(?:ing)?'
- Shipped as PR #13, merged, and redeployed to Pablo's iPhone
- Default OpenRouter/Claude model doesn't emit these tags, so shipped default was already clean; fix only matters for local/reasoning models

## Open Tail

*(none)*

## Evidence

- transcript lines 2632-2636
- transcript lines 2797-2818
- transcript lines 2820-2832

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-10-42f3cd42f2de-75af564c-2-reasoning-model-think-tag-stripping-in.json`](transcripts/2026-07-10-42f3cd42f2de-75af564c-2-reasoning-model-think-tag-stripping-in.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-2-reasoning-model-think-tag-stripping-in.json`](transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-2-reasoning-model-think-tag-stripping-in.json)
