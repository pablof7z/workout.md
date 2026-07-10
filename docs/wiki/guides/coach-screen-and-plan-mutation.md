---
title: Coach Screen and Plan Mutation
slug: coach-screen-and-plan-mutation
topic: ui-screens
summary: Swipe right on the runner opens a per-exercise Coach screen — a TikTok-style side panel where the user writes how it felt in plain language and the coach replie
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-07-09
updated: 2026-07-10
verified: 2026-07-09
compiled-from: conversation
sources:
  - session:42f3cd42-f2de-49b4-abff-fc10d0bedf8f
  - session:576bd63b-163a-4e6a-8a3b-611cd421a386
---

# Coach Screen and Plan Mutation

## Coach Screen

Swipe right on the runner opens a per-exercise Coach screen — a TikTok-style side panel where the user writes how it felt in plain language and the coach replies tersely and mutates the upcoming plan. The Note button is removed; notes live inside the Coach screen. <!-- [^42f3c-f0631] -->

Coach replies are terse and dry per the spec's voice (e.g., 'Sharp or dull? Cut your next set to 50%.'). Applied mutations surface as diff lines (e.g., '↳ Next Bench Press: 135 → 70 lb') shown in green. <!-- [^42f3c-d5c59] -->

## Coach Cues

Coach cues are attached per exercise and displayed on the runner page as a quiet glass quote pill. <!-- [^42f3c-2bb33] -->

## PlanEditorView

The PlanEditorView hides the rest-between-rounds stepper for straight-set blocks. <!-- [^576bd-8da11] -->
