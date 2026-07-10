---
type: episode-card
date: 2026-07-10
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: product
status: active
subjects:
  - app-icon
  - onboarding
  - dev-scaffolding-removal
  - default-provider
  - no-key-coach-state
supersedes: []
related_claims: []
source_lines:
  - 2496-2518
captured_at: 2026-07-10T07:02:02Z
---

# Episode: Productization finishing pass: app icon, onboarding, dev-scaffolding removal, default provider and no-key coach state

## Prior State

App had no app icon (BLOCKER B1), fake sample history seeded from MockHistory (B3), visible dev scaffolding ('core vX' label + echo print, B4), no onboarding, default coach provider was .ollama (localhost — broken on first run), and no graceful unconfigured-coach state (M3).

## Trigger

Opus audit flagged B1, B3, B4, and M3 as shipping-blocking issues between 'impressive demo' and 'finished app.'

## Decision

Added real app icon (offline Python+Pillow, barbell mark, indigo→crimson gradient) with full asset catalog. Deleted MockHistory and its seeding call. Removed core vX label and echo onAppear print. Added 3-screen first-run onboarding (track → coach → own data) gated by hasOnboarded flag. Changed default provider from .ollama to .openRouter (anthropic-claude-3.5-sonnet) so it works out-of-box. Added calm unconfigured-coach state ('Tell me how it feels' → 'Set up your coach in Settings') instead of crashing or silently failing.

## Consequences

- App presents a real, branded home-screen icon and launch screen
- History shows a proper empty state instead of fake SAMPLE rows
- No dev scaffolding visible in shipped UI
- First-run users get guided through coach setup instead of hitting a broken localhost default
- Default provider is now OpenRouter (non-localhost), so the coach works without manual configuration of a local server

## Open Tail

*(none)*

## Evidence

- transcript lines 2496-2518

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-10-42f3cd42f2de-75af564c-7-productization-finishing-pass-app-icon-onboarding.json`](transcripts/2026-07-10-42f3cd42f2de-75af564c-7-productization-finishing-pass-app-icon-onboarding.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-7-productization-finishing-pass-app-icon-onboarding.json`](transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-7-productization-finishing-pass-app-icon-onboarding.json)
