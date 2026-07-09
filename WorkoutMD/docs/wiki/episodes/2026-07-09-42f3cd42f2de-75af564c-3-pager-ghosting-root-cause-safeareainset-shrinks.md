---
type: episode-card
date: 2026-07-09
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
salience: root-cause
status: superseded
subjects:
  - pager-layout
  - safearea-inset
  - scroll-paging
  - floating-controls
supersedes: []
related_claims: []
source_lines:
  - 630-639
captured_at: 2026-07-09T19:44:55Z
---

# Episode: Pager ghosting root cause: safeAreaInset shrinks scroll container causing page-stride mismatch

## Prior State

Floating bottom controls were attached to the paging ScrollView via .safeAreaInset(edge: .bottom), which was assumed to coexist correctly with .scrollTargetBehavior(.paging) and .containerRelativeFrame.

## Trigger

Screenshot of the running simulator revealed the next page's content (faint 'BENCH PRESS' overline and exercise name) bleeding through behind the translucent bottom glass controls on every page.

## Decision

Diagnosed root cause: .safeAreaInset shrinks the scroll container, so each page sizes itself to the reduced height, making the paging stride less than the full screen — the top of the next step leaks behind the translucent glass. Fix adopted: full-screen .ignoresSafeArea() scroll container, each page sized to full container height via .containerRelativeFrame([.horizontal, .vertical]), controls moved to a floating overlay inside the safe area (no container resizing), opaque edge-to-edge page backgrounds, and bottom content padding so nothing hides under controls.

## Consequences

- Establishes a durable implementation pattern: floating controls over paging scroll views must be overlays, not safeAreaInset insets, to avoid stride mismatch
- Page backgrounds must be opaque to prevent translucency ghosting from adjacent pages
- Bottom content padding required so page content is not occluded by floating controls
- Fix was delegated to the Sonnet coder with a rebuild and re-verification cycle pending

## Open Tail

- Rebuild and screenshot verification not yet completed in this session
- Whether the same pattern applies to the top context strip (also floating glass) needs confirmation

## Evidence

- transcript lines 630-639

## Conversation

- Cleaned transcript (verbatim user words, abbreviated agent replies): [`transcripts/2026-07-09-42f3cd42f2de-75af564c-3-pager-ghosting-root-cause-safeareainset-shrinks.json`](transcripts/2026-07-09-42f3cd42f2de-75af564c-3-pager-ghosting-root-cause-safeareainset-shrinks.json)
- Raw transcript (verbatim user words, full agent replies): [`transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-3-pager-ghosting-root-cause-safeareainset-shrinks.json`](transcripts/raw/2026-07-09-42f3cd42f2de-75af564c-3-pager-ghosting-root-cause-safeareainset-shrinks.json)
