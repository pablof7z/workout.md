---
type: episode-card
date: 2026-07-09
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: architecture
status: superseded
subjects:
  - visual-design
  - liquid-glass
  - full-bleed
  - no-cards
supersedes:
  - 2026-07-09-42f3cd42f2de-75af564c-2-no-card-containers-full-bleed-backgrounds
related_claims: []
source_lines:
  - 411-421
  - 528-529
  - 654-658
  - 684-688
captured_at: 2026-07-09T20:12:13Z
---

# Episode: Visual doctrine: no card containers — full-bleed with glass only on floating controls

## Prior State

HTML prototype used card-style containers for exercise cards — a web convention. Liquid Glass was applied broadly to surfaces.

## Trigger

User directive: 'don't use card containers -- those are for the web and look bad on iphone -- bleed-edge instead.'

## Decision

Banned card containers entirely. Backgrounds bleed edge-to-edge (ignoresSafeArea). Liquid Glass is reserved strictly for floating controls (top context strip, bottom control cluster) — never for content surfaces. Each page has an opaque base color under the gradient to prevent sub-pixel bleed.

## Consequences

- Glass effects appear only on the floating top strip and bottom control cluster, docked inside the safe area as overlays
- Background gradients fill the entire screen including under the Dynamic Island and home indicator
- Opaque Color.black base under gradients prevents transparency leaks during paging
- Design rule saved as durable project memory for future sessions
- A subsequent bug (next page ghosting behind translucent controls) was traced to safeAreaInset shrinking the scroll container; fix was to move controls to floating overlays, reinforcing the no-container doctrine

## Open Tail

- Control spacing still needs tightening — user reported controls too far from top and bottom of screen

## Evidence

- transcript lines 411-421
- transcript lines 528-529
- transcript lines 654-658
- transcript lines 684-688

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-09-42f3cd42f2de-75af564c-2-visual-doctrine-no-card-containers-full.json`](transcripts/2026-07-09-42f3cd42f2de-75af564c-2-visual-doctrine-no-card-containers-full.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-2-visual-doctrine-no-card-containers-full.json`](transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-2-visual-doctrine-no-card-containers-full.json)
