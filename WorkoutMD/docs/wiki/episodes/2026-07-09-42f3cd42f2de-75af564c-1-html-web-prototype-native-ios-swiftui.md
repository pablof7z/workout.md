---
type: episode-card
date: 2026-07-09
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: reversal
status: active
subjects:
  - platform-choice
  - html-to-native
  - swiftui
supersedes: []
related_claims: []
source_lines:
  - 411-422
  - 449-453
  - 555-578
captured_at: 2026-07-09T20:35:26Z
---

# Episode: HTML web prototype → native iOS SwiftUI app

## Prior State

An HTML prototype (single-file index.html, CSS-emulated Liquid Glass) was built and opened in the browser as the first runnable representation of the product.

## Trigger

User rejected the web emulation: 'no, build it as an actual ios app -- I have xcode and everything!' — user wants a genuine native app, not a browser mockup.

## Decision

Pivot from HTML/CSS prototype to a real native SwiftUI app targeting iOS 26 SDK with real Liquid Glass APIs (.glassEffect, GlassEffectContainer, .buttonStyle(.glass)), built via xcodegen + xcodebuild, deployed to the iOS Simulator.

## Consequences

- Real Liquid Glass material APIs replace CSS backdrop-filter emulation
- Project scaffolded at WorkoutMD/ with project.yml (xcodegen), bundle id com.workoutmd.prototype, iOS 26 target, no signing (simulator-only)
- Build-deploy-verify loop now requires xcodegen generate → xcodebuild → simulator install/launch, adding toolchain overhead vs. opening a browser tab
- New Swift files must be picked up by re-running xcodegen generate before building (caused one compile failure mid-session)

## Open Tail

- App is mock-only (no real backend or LLM); coach is scripted keyword policy, not a live model

## Evidence

- transcript lines 411-422
- transcript lines 449-453
- transcript lines 555-578

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-09-42f3cd42f2de-75af564c-1-html-web-prototype-native-ios-swiftui.json`](transcripts/2026-07-09-42f3cd42f2de-75af564c-1-html-web-prototype-native-ios-swiftui.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-1-html-web-prototype-native-ios-swiftui.json`](transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-1-html-web-prototype-native-ios-swiftui.json)
