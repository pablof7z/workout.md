---
type: episode-card
date: 2026-07-09
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: root-cause
status: superseded
subjects:
  - pager-layout
  - safeareainset
  - glass-bleed-through
  - container-relative-frame
supersedes:
  - 2026-07-09-42f3cd42f2de-75af564c-3-pager-ghosting-root-cause-safeareainset-shrinks
related_claims: []
source_lines:
  - 630-638
  - 647-656
captured_at: 2026-07-09T20:16:44Z
---

# Episode: Durable root cause: .safeAreaInset shrinks paging container causing content bleed-through behind translucent glass

## Prior State

Bottom controls were attached via .safeAreaInset(edge: .bottom), a standard SwiftUI pattern for docking controls above safe area. This was assumed safe for use with a paging ScrollView.

## Trigger

Screenshot verification revealed the next page's content ghosting behind the translucent glass bottom controls — a visible 'BENCH PRESS' overline leaking through from the subsequent page on every screen.

## Decision

Established that .safeAreaInset must not be used on a paging ScrollView when controls are translucent. Replaced with: full-screen ScrollView with .ignoresSafeArea(), each page sized via .containerRelativeFrame([.horizontal, .vertical]) to full container height, controls moved to floating .overlay positioned with safe-area-aware padding. Page backgrounds made fully opaque (Color.black base under gradient) and .clipped() to prevent any sub-pixel spill.

## Consequences

- Paging stride now equals full screen height — clean 1:1 full-screen snaps with no seam
- Glass controls blur only the current page, not the next page's content
- This pattern is the required approach for any future full-bleed pager with translucent floating controls in this project
- BackgroundView no longer self-ignores safe area (that was causing per-page bleed); .ignoresSafeArea moved to call site on full-screen screens

## Open Tail

*(none)*

## Evidence

- transcript lines 630-638
- transcript lines 647-656

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-09-42f3cd42f2de-75af564c-5-durable-root-cause-safeareainset-shrinks-paging.json`](transcripts/2026-07-09-42f3cd42f2de-75af564c-5-durable-root-cause-safeareainset-shrinks-paging.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-5-durable-root-cause-safeareainset-shrinks-paging.json`](transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-5-durable-root-cause-safeareainset-shrinks-paging.json)
