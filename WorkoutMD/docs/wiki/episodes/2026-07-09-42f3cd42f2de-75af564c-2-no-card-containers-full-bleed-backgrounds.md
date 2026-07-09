---
type: episode-card
date: 2026-07-09
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: architecture
status: superseded
subjects:
  - visual-design-doctrine
  - liquid-glass-material
  - full-bleed-layout
supersedes: []
related_claims: []
source_lines:
  - 411-414
  - 528-530
  - 630-640
  - 644-660
  - 684-686
captured_at: 2026-07-09T19:52:06Z
---

# Episode: No card containers — full-bleed backgrounds with glass reserved for floating controls only

## Prior State

The HTML prototype used translucent card containers for each exercise — a web-style pattern where content sits in bordered, rounded panels with glass/blur treatment.

## Trigger

User directive at line 413: 'don't use card containers -- those are for the web and look bad on iphone -- bleed-edge instead.'

## Decision

Card containers are banned from the iOS app. Backgrounds are full-bleed edge-to-edge (gradients per movement/block, opaque base). Liquid Glass is reserved strictly for floating controls — the top context strip and bottom control cluster — never for content containers.

## Consequences

- BackgroundView must paint an opaque Color.black base under gradients to prevent sub-pixel bleed between pager pages.
- Floating controls must use .overlay positioned in the safe area, NOT .safeAreaInset — the latter shrinks the scroll container and breaks paging stride (durable root cause: safeAreaInset + containerRelativeFrame paging = ghosting of adjacent pages behind translucent glass).
- Each page uses .containerRelativeFrame([.horizontal, .vertical]) for full-height snaps with .clipped() to prevent spill.
- This doctrine was saved to project memory (design-native-ios-no-cards.md) as a durable rule for future sessions.
- Block hue shifts per section (chest = crimson, superset = purple) replace card boundaries as visual section separators.

## Open Tail

- Reps stepper is visually tight against effort pills — spacing needs tuning.
- Design rule is currently iOS-specific; no guidance yet for whether a future web/Android version would adopt a different material strategy.

## Evidence

- transcript lines 411-414
- transcript lines 528-530
- transcript lines 630-640
- transcript lines 644-660
- transcript lines 684-686

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-09-42f3cd42f2de-75af564c-2-no-card-containers-full-bleed-backgrounds.json`](transcripts/2026-07-09-42f3cd42f2de-75af564c-2-no-card-containers-full-bleed-backgrounds.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-2-no-card-containers-full-bleed-backgrounds.json`](transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-2-no-card-containers-full-bleed-backgrounds.json)
