---
type: episode-card
date: 2026-07-10
session: 576bd63b-163a-4e6a-8a3b-611cd421a386
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/576bd63b-163a-4e6a-8a3b-611cd421a386.jsonl
salience: root-cause
status: superseded
subjects:
  - runner-layout
  - safe-area-insets
  - overlay-alignment
supersedes:
  - 2026-07-10-576bd63b163a-031f8906-1-swiftui-overlay-safe-area-double-counting
related_claims: []
source_lines:
  - 1-6
  - 721-746
  - 836-842
  - 1044-1044
  - 1052-1062
captured_at: 2026-07-10T07:00:27Z
---

# Episode: Overlay-after-ignoresSafeArea double-counts safe-area insets

## Prior State

StepPageView reserved top space for the floating context-strip pill using a hardcoded constant (`topInset + 50`). The floating pill overlay in RunnerView was positioned with explicit safeTop padding, assuming the overlay respected the ignoresSafeArea parent. This caused the pill to overlap content below it by ~40pt on circuit pages.

## Trigger

User flagged the runner screen as a 'total disaster' with broken alignment, specifically the top pill overlapping the mini-map row. On-device accessibility-frame measurements confirmed the pill at y=130 collided with the ROUND 1 OF 3 label beneath it.

## Decision

Introduced a shared `TopStripMetrics` enum in RunnerView (topOffset=6, height=34, clearance=16, totalReserve=56) so StepPageView derives topReserve from the pill's actual rendered geometry. Removed the redundant safeTop addition from the overlay padding — `.overlay(alignment:)` on a view with `.ignoresSafeArea()` implicitly re-adds the safe-area inset, so adding it explicitly double-counts. Applied the same fix to the bottom controls overlay.

## Consequences

- Top pill now has a guaranteed 56pt clearance from page content, verified via accessibility frames on the Plank/circuit page.
- A memory file (swiftui-overlay-safearea-double-count.md) was created documenting this SwiftUI quirk for future work.
- RunnerView is the only file in the app using this overlay+ignoresSafeArea pattern, so no other screens are affected.
- bottomReserve constant (168pt) was also corrected for the same double-counting on the bottom overlay.

## Open Tail

*(none)*

## Evidence

- transcript lines 1-6
- transcript lines 721-746
- transcript lines 836-842
- transcript lines 1044-1044
- transcript lines 1052-1062

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-10-576bd63b163a-031f8906-1-overlay-after-ignoressafearea-double-counts-safe.json`](transcripts/2026-07-10-576bd63b163a-031f8906-1-overlay-after-ignoressafearea-double-counts-safe.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-10-576bd63b163a-031f8906-1-overlay-after-ignoressafearea-double-counts-safe.json`](transcripts/raw/2026-07-10-576bd63b163a-031f8906-1-overlay-after-ignoressafearea-double-counts-safe.json)
