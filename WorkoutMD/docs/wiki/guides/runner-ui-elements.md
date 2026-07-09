---
title: Runner UI Elements
slug: runner-ui-elements
topic: ios-prototype
summary: Coach cues are attached per exercise and displayed as a quiet glass quote pill on the set page.
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

# Runner UI Elements

## Coach Cues

Coach cues are attached per exercise and displayed as a quiet glass quote pill on the set page. <!-- [^42f3c-c8613] -->

All interactive controls in the runner have 44pt minimum tap targets. <!-- [^42f3c-57e9a] -->

## Set Page Feedback

The set page provides effortless feedback via Easy/Moderate/Hard effort pills, a quick note input, a skip action, and a primary Log & Next button. Haptics fire as .selection() on effort pill pick and .impact(.medium) on Log & Next. <!-- [^42f3c-3c62b] -->

## Done Screen

The Done screen is a terse completion screen with a .success haptic on appear and no gamification. <!-- [^42f3c-17c7b] -->
