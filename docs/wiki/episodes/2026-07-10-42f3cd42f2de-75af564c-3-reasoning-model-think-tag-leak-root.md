---
type: episode-card
date: 2026-07-10
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: root-cause
status: superseded
subjects:
  - think-stripper
  - reasoning-tag-leak
  - coach-streaming
supersedes: []
related_claims: []
source_lines:
  - 2797-2818
captured_at: 2026-07-10T07:02:02Z
---

# Episode: Reasoning-model think-tag leak: root cause and streaming-safe ThinkStripper

## Prior State

rig.rs run_stream forwarded StreamedAssistantContent::Text verbatim into CoachSink with no reasoning-tag awareness. Reasoning models (deepseek-r1, glm, qwq) emit raw <think>/<thinking>…</think> tags inline, which leaked into the visible coach reply UI. No tag stripping existed anywhere in Swift or Rust.

## Trigger

Final Opus gate (line 2633) observed the exact bug: glm-5.2:cloud rendered a raw </think> marker inline in a coach reply. User's local models (glm/deepseek) all emit these tags.

## Decision

Created ThinkStripper.swift — a Foundation-only helper with strip() (one-shot) and Buffer (streaming accumulator). CoachStreamSink.onTextDelta now runs each delta through a per-turn ThinkStripper.Buffer; onCompleted runs the full text through strip() before persisting. Handles: well-formed blocks, unterminated in-progress blocks, tags split across delta boundaries (with holdback to prevent fragment flashing), and the exact bug shape (orphan with no opening tag that retroactively hides everything back to turn start). Replaced append-only appendStreamingDelta with replaceStreamingText since visible projection can shrink mid-stream.

## Consequences

- Reasoning-model tags no longer leak into coach replies on-screen or in persisted transcripts
- Streaming text projection can now shrink (not just grow), requiring replaceStreamingText instead of append
- 18 unit tests added in new WorkoutMDTests target (no Rust cross-compile needed)
- Caught and fixed a regex bug during development: 'thinking?' matched 'thinkin'+optional 'g', corrected to 'think(?:ing)?'
- Redeployed to user's iPhone

## Open Tail

*(none)*

## Evidence

- transcript lines 2797-2818

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-10-42f3cd42f2de-75af564c-3-reasoning-model-think-tag-leak-root.json`](transcripts/2026-07-10-42f3cd42f2de-75af564c-3-reasoning-model-think-tag-leak-root.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-3-reasoning-model-think-tag-leak-root.json`](transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-3-reasoning-model-think-tag-leak-root.json)
