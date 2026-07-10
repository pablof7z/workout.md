---
type: episode-card
date: 2026-07-10
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: root-cause
status: active
subjects:
  - icloud-entitlement
  - swiftdata-cloudkit
  - cloudkit-database-none
supersedes: []
related_claims: []
source_lines:
  - 2285-2294
  - 2359-2370
captured_at: 2026-07-10T07:02:02Z
---

# Episode: iCloud entitlement triggers SwiftData CloudKit auto-detection crash

## Prior State

SwiftData ModelConfiguration defaults to cloudKitDatabase: .automatic. Without iCloud entitlements this is harmless, but adding an iCloud ubiquity container entitlement causes SwiftData to auto-detect CloudKit and crash at launch because the app's schema uses unique constraints and non-optional attributes that CloudKit rejects.

## Trigger

Runtime testing of the iCloud sync feature (PR #9) — app crashed at launch after adding the iCloud container entitlement to WorkoutMD.entitlements.

## Decision

Explicitly pass cloudKitDatabase: .none in ModelConfiguration in WorkoutMDApp.swift. This disables CloudKit auto-detection while keeping the iCloud Documents-based file sync (ICloudSync.swift) working independently.

## Consequences

- App launches cleanly with iCloud entitlements present
- iCloud Documents sync works via NSFileCoordinator/NSMetadataQuery without CloudKit schema constraints
- This is a durable invariant: any future schema change must keep cloudKitDatabase: .none unless migrating to a CloudKit-compatible schema
- Both the real-plans merge and iCloud merge confirmed cloudKitDatabase: .none present in the final schema

## Open Tail

*(none)*

## Evidence

- transcript lines 2285-2294
- transcript lines 2359-2370

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-10-42f3cd42f2de-75af564c-4-icloud-entitlement-triggers-swiftdata-cloudkit-auto.json`](transcripts/2026-07-10-42f3cd42f2de-75af564c-4-icloud-entitlement-triggers-swiftdata-cloudkit-auto.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-4-icloud-entitlement-triggers-swiftdata-cloudkit-auto.json`](transcripts/raw/2026-07-10-42f3cd42f2de-75af564c-4-icloud-entitlement-triggers-swiftdata-cloudkit-auto.json)
