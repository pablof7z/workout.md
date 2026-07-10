---
type: episode-card
date: 2026-07-10
session: 576bd63b-163a-4e6a-8a3b-611cd421a386
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/576bd63b-163a-4e6a-8a3b-611cd421a386.jsonl
salience: root-cause
status: superseded
subjects:
  - runner-layout
  - safe-area-inset
  - overlay-geometry
supersedes: []
related_claims: []
source_lines:
  - 721-746
  - 1044-1044
  - 1052-1062
captured_at: 2026-07-10T06:54:04Z
---

# Episode: SwiftUI overlay safe-area double-counting root cause

## Prior State

StepPageView's topReserve was derived from a guessed constant (~50pt), and the floating top-context pill's overlay padding explicitly added safeTop on top of an ignoresSafeArea ScrollView — causing the safe-area inset to be double-counted, so the reserved clearance never actually cleared the pill.

## Trigger

User reported the runner screen was a 'total disaster' with broken alignment; on-device accessibility-frame measurements confirmed the 'Circuit · 14/22' pill overlapped the mini-map row by ~40pt.

## Decision

Created RunnerView.TopStripMetrics — a shared enum (topOffset=6, height=34, clearance=16, totalReserve=56) consumed by both RunnerView's pill overlay and StepPageView's topReserve — and removed the explicit safeTop addition from the overlay padding, since .overlay after .ignoresSafeArea implicitly re-adds the inset.

## Consequences

- Top pill now has a guaranteed 56pt clearance from page content, verified via accessibility frames on a dedicated simulator.
- The same double-counting pattern was found and fixed in the bottom controls overlay (safeBottom was also double-counted, producing excess whitespace).
- A memory file (swiftui-overlay-safearea-double-count.md) was written to prevent this SwiftUI quirk from recurring in future overlay work.

## Open Tail

- Other screens using .overlay after .ignoresSafeArea may still have the same latent double-count — a repo-wide audit was noted but not completed.

## Evidence

- transcript lines 721-746
- transcript lines 1044-1044
- transcript lines 1052-1062

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-10-576bd63b163a-031f8906-1-swiftui-overlay-safe-area-double-counting.json`](transcripts/2026-07-10-576bd63b163a-031f8906-1-swiftui-overlay-safe-area-double-counting.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-10-576bd63b163a-031f8906-1-swiftui-overlay-safe-area-double-counting.json`](transcripts/raw/2026-07-10-576bd63b163a-031f8906-1-swiftui-overlay-safe-area-double-counting.json)
