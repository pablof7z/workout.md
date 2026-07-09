---
title: Code Signing and Provisioning
slug: code-signing-and-provisioning
topic: build-configuration
summary: Builds use automatic code signing that works for both simulator and device deployment
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-07-09
updated: 2026-07-09
verified: 2026-07-09
compiled-from: conversation
sources:
  - session:43fd928f-6da0-404c-a38a-406d6cdfb05f
---

# Code Signing and Provisioning

## Automatic Signing

Builds use automatic code signing that works for both simulator and device deployment. Device builds pass `-allowProvisioningUpdates` so Xcode can generate provisioning profiles automatically. The development team identifier is `C99QRJCR43` (Pablo Fernandez). <!-- [^43fd9-e83c9] -->

## Bundle Identifier

The bundle identifier declared in `project.yml` is `com.workoutmd.prototype`. When automatic signing on a free/personal team rewrites the bundle ID, the effective bundle identifier becomes `md.workout` instead of the declared `com.workoutmd.prototype`. <!-- [^43fd9-3cbd9] -->
