---
type: episode-card
date: 2026-07-09
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: architecture
status: active
subjects:
  - visual-design-doctrine
  - full-bleed
  - no-card-containers
  - liquid-glass
supersedes:
  - 2026-07-09-42f3cd42f2de-75af564c-2-full-bleed-design-doctrine-no-card
related_claims: []
source_lines:
  - 411-414
  - 527-533
  - 684-686
captured_at: 2026-07-09T20:35:26Z
---

# Episode: Full-bleed no-cards as visual design doctrine

## Prior State

The HTML prototype used card-container panels (standard web pattern) to group exercises and controls, which the user found visually inappropriate for iPhone.

## Trigger

User directive: 'don't use card containers -- those are for the web and look bad on iphone -- bleed-edge instead.'

## Decision

Card containers are banned from the native app. Backgrounds bleed edge-to-edge (ignoresSafeArea). Liquid Glass is reserved strictly for floating controls (top context strip, bottom control cluster) — never for content grouping. Page backgrounds are opaque per-block gradient hues.

## Consequences

- Glass material is a scarce resource used only for interactive chrome, not content containers
- Each exercise block gets a distinct full-bleed gradient hue (chest = crimson, superset = purple, circuit = another)
- Saved as a durable memory file (design-native-ios-no-cards.md) for future sessions
- Lists inside sheets (e.g., WorkoutListView) are the exception — native grouped List is acceptable in sheet context, not in the runner

## Open Tail

*(none)*

## Evidence

- transcript lines 411-414
- transcript lines 527-533
- transcript lines 684-686

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-09-42f3cd42f2de-75af564c-2-full-bleed-no-cards-as-visual.json`](transcripts/2026-07-09-42f3cd42f2de-75af564c-2-full-bleed-no-cards-as-visual.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-2-full-bleed-no-cards-as-visual.json`](transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-2-full-bleed-no-cards-as-visual.json)
