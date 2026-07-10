---
type: noun-entry
slug: runnerview
name: "RunnerView"
origin: extracted
source_refs:
  - transcript:168-183
---

# RunnerView

The hero of the app: a full-screen vertical pager where each page is exactly one set (or a rest beat). Reads steps and current position from the shared WorkoutSession. The paging ScrollView spans the entire device height via ignoresSafeArea; floating glass controls are overlays, never safeAreaInset. Advancing between sets is a swipe down — no Log & Next button.
