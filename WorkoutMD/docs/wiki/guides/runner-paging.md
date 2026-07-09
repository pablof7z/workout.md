---
title: Runner Paging and Layout
slug: runner-paging
topic: ios-prototype
summary: Each page in the runner is sized to the full screen height via `.containerRelativeFrame([.horizontal, .vertical])` so the paging stride equals the screen height
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-07-09
updated: 2026-07-09
verified: 2026-07-09
compiled-from: conversation
sources:
  - session:42f3cd42-f2de-49b4-abff-fc10d0bedf8f
---

# Runner Paging and Layout

## Page Sizing & Paging Stride

Each page in the runner is sized to the full screen height via `.containerRelativeFrame([.horizontal, .vertical])` so the paging stride equals the screen height and pages snap 1:1 with no seam. <!-- [^42f3c-42166] -->

Page backgrounds in the runner are opaque edge-to-edge (with an opaque `Color.black` base under the gradient) so no content bleeds through between pages. <!-- [^42f3c-9e7a7] -->

## Floating Controls

The top context strip and bottom control cluster float as overlays positioned inside the safe area rather than using `.safeAreaInset`, so they do not resize the scroll content. <!-- [^42f3c-3854e] -->

## Step Page Layout

The step page reserves top and bottom inset padding so the hero target and coach-cue pill never sit under the floating controls. <!-- [^42f3c-dad45] -->

## Hero Target Typography

Hero target numbers use `@ScaledMetric` so the large custom sizes still respond to Dynamic Type. <!-- [^42f3c-3a9a0] -->
