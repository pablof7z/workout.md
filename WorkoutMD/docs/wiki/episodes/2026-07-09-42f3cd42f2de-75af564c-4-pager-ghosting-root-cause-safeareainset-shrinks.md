---
type: episode-card
date: 2026-07-09
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: root-cause
status: active
subjects:
  - pager-ghosting-bug
  - safeareainset
  - scrollview-paging
  - containerrelativeframe
supersedes:
  - 2026-07-09-42f3cd42f2de-75af564c-5-durable-root-cause-safeareainset-shrinks-paging
related_claims: []
source_lines:
  - 630-640
  - 642-661
  - 692-711
captured_at: 2026-07-09T20:35:26Z
---

# Episode: Pager ghosting root cause: safeAreaInset shrinks scroll container

## Prior State

Bottom controls were attached via .safeAreaInset(edge: .bottom), which was assumed to be a harmless overlay pattern that wouldn't affect scroll content sizing.

## Trigger

Screenshot revealed next page's content bleeding through behind the translucent bottom glass controls — a faint 'BENCH PRESS' overline ghosting on every page. Visual inspection confirmed the paging stride was shorter than the screen height.

## Decision

Root cause: .safeAreaInset shrinks the ScrollView's container, so .containerRelativeFrame(.vertical) sized each page to less than full screen height, making the paging stride smaller than the screen. Fix: ScrollView gets .ignoresSafeArea() so its container is full device height; each page uses .containerRelativeFrame([.horizontal, .vertical]); controls moved from .safeAreaInset to .overlay positioned into safe area via padding; backgrounds are opaque (Color.black base under gradient) with .clipped() on page ZStack.

## Consequences

- Durable lesson: never use .safeAreaInset on a paging ScrollView with .containerRelativeFrame — it silently breaks page sizing
- Controls now float as overlays, not insets — they visually blur the current page but don't resize it
- BackgroundView no longer self-ignores safe area (which caused page-to-page bleed); TodayView/DoneView add .ignoresSafeArea() at call site instead
- StepPageView takes topInset/bottomInset parameters to reserve space for floating controls so hero content never hides under them

## Open Tail

*(none)*

## Evidence

- transcript lines 630-640
- transcript lines 642-661
- transcript lines 692-711

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-09-42f3cd42f2de-75af564c-4-pager-ghosting-root-cause-safeareainset-shrinks.json`](transcripts/2026-07-09-42f3cd42f2de-75af564c-4-pager-ghosting-root-cause-safeareainset-shrinks.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-4-pager-ghosting-root-cause-safeareainset-shrinks.json`](transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-4-pager-ghosting-root-cause-safeareainset-shrinks.json)
