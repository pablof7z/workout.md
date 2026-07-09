---
type: episode-card
date: 2026-07-09
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: architecture
status: superseded
subjects:
  - design-doctrine
  - full-bleed
  - no-cards
  - liquid-glass-placement
supersedes:
  - 2026-07-09-42f3cd42f2de-75af564c-2-visual-doctrine-no-card-containers-full
related_claims: []
source_lines:
  - 411-421
  - 528-529
  - 536-553
  - 684-684
captured_at: 2026-07-09T20:16:44Z
---

# Episode: Full-bleed design doctrine: no card containers, glass only for floating controls

## Prior State

The initial product vision and HTML prototype used card-style containers for exercise entries, consistent with typical fitness-app UI patterns.

## Trigger

User directive: 'don't use card containers -- those are for the web and look bad on iphone -- bleed-edge instead.'

## Decision

Adopted a hard design rule: backgrounds fill the screen edge-to-edge (.ignoresSafeArea), no card containers anywhere in the runner. Liquid Glass is reserved strictly for floating controls (top context strip, bottom control cluster) that overlay the full-bleed background. Opaque base color (Color.black) under gradients prevents any transparency bleed.

## Consequences

- BackgroundView component paints opaque base + gradient, fills frame to infinity
- Glass effects appear only on floating overlays positioned via safe-area-aware padding, never on content containers
- Design rule persisted to project memory (design-native-ios-no-cards.md) for future sessions
- All subsequent UI additions (timer, list sheet, coach screen) must comply with the no-cards rule in the runner context

## Open Tail

- The WorkoutListView sheet uses native grouped List (acceptable in sheet context, not in runner) — the no-cards rule applies to the runner specifically

## Evidence

- transcript lines 411-421
- transcript lines 528-529
- transcript lines 536-553
- transcript lines 684-684

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-09-42f3cd42f2de-75af564c-2-full-bleed-design-doctrine-no-card.json`](transcripts/2026-07-09-42f3cd42f2de-75af564c-2-full-bleed-design-doctrine-no-card.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-2-full-bleed-design-doctrine-no-card.json`](transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-2-full-bleed-design-doctrine-no-card.json)
