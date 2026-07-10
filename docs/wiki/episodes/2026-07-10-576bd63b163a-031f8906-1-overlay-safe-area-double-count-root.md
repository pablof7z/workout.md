---
type: episode-card
date: 2026-07-10
session: 576bd63b-163a-4e6a-8a3b-611cd421a386
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/576bd63b-163a-4e6a-8a3b-611cd421a386.jsonl
salience: root-cause
status: active
subjects:
  - runner-layout
  - swiftui-overlay-safearea
  - top-context-strip
supersedes:
  - 2026-07-10-576bd63b163a-031f8906-1-overlay-after-ignoressafearea-double-counts-safe
related_claims: []
source_lines:
  - 1-5
  - 721-746
  - 836-842
  - 1044-1044
  - 1056-1057
captured_at: 2026-07-10T07:19:03Z
---

# Episode: Overlay safe-area double-count root cause for top pill overlap

## Prior State

The floating top context strip pill (e.g. 'Circuit · 14/22') overlapped the mini-map row beneath it on circuit pages. StepPageView used a guessed constant (topInset + 50) for topReserve, and RunnerView added explicit safe-area padding on overlays of a view that already called .ignoresSafeArea().

## Trigger

User reported the screen as 'a total disaster' with broken alignment. Agent investigated via on-device accessibility frame measurements and found the pill overlapping content by ~40pt, then traced it to a SwiftUI quirk: .overlay(alignment:) after .ignoresSafeArea() still implicitly re-adds the safe-area inset, so the explicit padding was double-counting it.

## Decision

Replaced guessed constants with shared TopStripMetrics (topOffset=6, height=34, clearance=16, totalReserve=56) computed from the pill's actual rendered geometry. Removed the redundant explicit safe-area padding on overlays — the overlay already implicitly applies the inset. Documented the doctrine in a memory file (swiftui-overlay-safearea-double-count.md).

## Consequences

- 56pt clearance now correct, verified via accessibility frames showing no overlap between pill and mini-map row
- RunnerView is the only file in the app combining .overlay(alignment:) with .ignoresSafeArea(), so no other screens can have this bug
- A reusable memory note was written so future SwiftUI work in this repo avoids the same double-counting pattern
- The same double-count root cause was found and fixed on the bottom controls overlay (less visually obvious since it erred toward extra whitespace)

## Open Tail

*(none)*

## Evidence

- transcript lines 1-5
- transcript lines 721-746
- transcript lines 836-842
- transcript lines 1044-1044
- transcript lines 1056-1057

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-10-576bd63b163a-031f8906-1-overlay-safe-area-double-count-root.json`](transcripts/2026-07-10-576bd63b163a-031f8906-1-overlay-safe-area-double-count-root.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-10-576bd63b163a-031f8906-1-overlay-safe-area-double-count-root.json`](transcripts/raw/2026-07-10-576bd63b163a-031f8906-1-overlay-safe-area-double-count-root.json)
