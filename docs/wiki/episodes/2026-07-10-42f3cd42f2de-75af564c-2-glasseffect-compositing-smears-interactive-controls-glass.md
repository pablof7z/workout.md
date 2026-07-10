---
type: episode-card
date: 2026-07-10
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: root-cause
status: active
subjects:
  - liquid-glass-rendering
  - slider-knob
  - glass-effect-bug
supersedes: []
related_claims: []
source_lines:
  - 3756-3779
  - 3804-3827
  - 3831-3859
captured_at: 2026-07-10T11:31:29Z
---

# Episode: GlassEffect compositing smears interactive controls — glass removed from slider

## Prior State

The slider track and knob were built using iOS 26 `GlassEffectContainer` / `.glassEffect(.regular, in: .capsule)` per the Liquid Glass design system skill. The knob itself was a plain `Circle()` with no glass effect, but sat inside a `GlassEffectContainer`.

## Trigger

User showed on-device screenshots of the knob rendering as a blurry, pixelated mush in both pending and done states. Root-cause diagnosis (confirmed by the agent's own code comments): `GlassEffectContainer`'s morph/blend pass blurs everything inside it, smearing the solid `Circle()` knob into a soft, low-contrast blob even though the knob declared no `.glassEffect` of its own.

## Decision

Rip all `.glassEffect` / `GlassEffectContainer` usage out of the slider component entirely. Draw the track as a plain translucent capsule and the knob as a solid opaque filled circle with a tight shadow. Glass effects are reserved for non-interactive chrome (cue pill, effort button, timer) only.

## Consequences

- Slider knob now renders crisp on-device in all states (pending, done, skipped) — verified via simulator screenshots before deployment
- Establishes a reusable doctrine: do not wrap interactive solid-fill controls in `GlassEffectContainer` — its compositing pass will smear them
- Only 7 `.glassEffect` calls remain in StepPageView, all on non-slider elements
- After this fix, the verification protocol changed: assistant now visually inspects simulator screenshots before deploying to device, rather than trusting build reports

## Open Tail

*(none)*

## Evidence

- transcript lines 3756-3779
- transcript lines 3804-3827
- transcript lines 3831-3859

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-10-42f3cd42f2de-75af564c-2-glasseffect-compositing-smears-interactive-controls-glass.json`](transcripts/2026-07-10-42f3cd42f2de-75af564c-2-glasseffect-compositing-smears-interactive-controls-glass.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-2-glasseffect-compositing-smears-interactive-controls-glass.json`](transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-2-glasseffect-compositing-smears-interactive-controls-glass.json)
