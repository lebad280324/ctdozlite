# ADR-0006: AppKit transcript and independent local history pages

- **Status:** accepted
- **Date:** 2026-11-11
- **Deciders:** user and implementation team

## Context

Switching threads recreated the SwiftUI lazy transcript. Local history intents
shared the serial network command loop, and loading older messages repeatedly
expanded whole snapshots. Thumbnail arrival also changed row heights.
The user approved a SwiftUI shell with an AppKit transcript and bounded local
pagination. Diagnostics are in `output/performance-diagnostics-20261111/`.

## Decision

Use an AppKit `NSTableView` for the transcript, with reusable `NSHostingView`
cells, cached measured heights, and message-ID-plus-offset scroll anchors.
Preserve the existing SwiftUI message content and inject its account environment
explicitly. Keep composer, sidebar, menus and settings in SwiftUI.

The viewport reports its proposed window size directly. Each cell keeps one
hosting controller, measures content with `sizeThatFits(in:)`, and disables
content-size constraints and inherited safe areas. This avoids feeding a row's
intrinsic size back into the table's manual geometry and repeatedly fitting the
entire hosting-view subtree during scrolling.

The conversation shell places the header, optional controls, transcript and
composer in disjoint layout regions. Neither the header nor the composer is an
overlay on the native scroll view. Sidebar width is bounded by the window's
available width, and viewport-height changes preserve the bottom or the current
reading anchor. Local SQLite history remains the first source of displayed
messages; background network refreshes do not supply the first local frame.

Route `load_message_page` through a bounded, independent worker read queue.
The reader owns its SQLite connection and receives a short, account-scoped
metadata lease; credentials never enter that lease. Results are correlated by
request ID and rejected after account changes. No Zalo request or signing flow
changes. Store schema remains version 2.

Use `(ts, msg_id)` cursor pages in either direction, 50 messages per UI request,
a 400-message UI window, and a 12-thread LRU cache. Restore the same message and
pixel offset after page insertion and height corrections. Live updates contain
changed IDs; explicit removals cannot be resurrected by an older page response.
Remote refreshes are coalesced independently of local reads. Images reserve a
stable frame, and inline text formatting is cached.

## Consequences

- Main-thread work is limited to UI layout and applying already-decoded rows;
  filesystem, SQLite and network work remain in Rust (INV-3).
- Stable cursor ties and strict message-ID reconciliation preserve INV-4.
- The reader's weak stdout ownership and closed-channel guard are necessary
  for EOF and shutdown to terminate without a busy loop.
- AppKit cell reuse must retain one hosting view and forward the SwiftUI
  environment. Scroll anchors, width changes and old-window live edits require
  regression coverage.
- Component benchmarks do not establish click-to-display latency or frame rate;
  packaged-app interaction remains part of manual verification.

## References

- [Telegram thread scroll state](https://github.com/telegramdesktop/tdesktop/blob/dev/Telegram/SourceFiles/history/history.h)
- [Signal Desktop timeline windows](https://github.com/signalapp/Signal-Desktop/blob/main/ts/components/conversation/Timeline.dom.tsx)
- [Signal scroll continuity](https://github.com/signalapp/Signal-iOS/blob/main/Signal/ConversationView/ConversationViewLayout.swift)
- [Apple: Use SwiftUI with AppKit](https://developer.apple.com/videos/play/wwdc2022/10075/)

## Alternatives considered

Keeping the lazy SwiftUI transcript has lower migration cost, but offers less
control over reusable cell lifetimes and exact scroll continuity. A custom
renderer would require rebuilding text selection, accessibility and menus.
