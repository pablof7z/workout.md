---
title: Glass UI Design System
slug: glass-ui-design-system
topic: ui-components
summary: The app uses the liquid-glass-design skill's visual language — translucent blurred panels, specular top-edge highlights, a floating glass tab bar, and press-sca
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

# Glass UI Design System

## Material & Layout Language

The app uses the liquid-glass-design skill's visual language — translucent blurred panels, specular top-edge highlights, a floating glass tab bar, and press-scale interactions — for its material treatment. Full-bleed, edge-to-edge backgrounds are used with no card containers; glass effects are reserved strictly for floating controls (the top strip and bottom control cluster). Each runner page has an opaque, edge-to-edge background so no content from adjacent pages leaks through behind the translucent glass controls. <!-- [^42f3c-205e7] -->

## Accessibility

Hero numbers in the runner use @ScaledMetric so large custom sizes still respond to Dynamic Type. All interactive controls in the runner meet 44pt minimum tap targets and have accessibility labels and values set. <!-- [^42f3c-de043] -->

## Haptics

Haptics fire as .selection() on effort pick, .impact(.medium) on Log & Next, and .success() on workout completion. <!-- [^42f3c-d3db9] -->
