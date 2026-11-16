# Native transcript and local history performance

## Evidence and scope

The 2026-11-11 user recording shows an initial vertical white strip when changing
threads (around 10 seconds), clipped sticker content, and unstable message
geometry. This was a real rendering defect in the first AppKit prototype.
Component timings alone did not establish the quality of scrolling.

The original local query on 110,963 messages returned 200 rows in a median
0.380 ms. The network command queue and presentation work required separate
changes; the store's size alone did not explain the reported delay.

## Implementation

- The Rust input reader routes `load_message_page` to an independent bounded
  read queue, with an account lease and its own SQLite connection. Cursor order
  is `(ts, msg_id)` in either direction. Network refreshes retain the existing
  API parameters, signing, hosts and cookie attachment.
- The frontend uses 50-row pages, a 400-row display window and 12-thread cache.
  Live deltas reconcile by message ID, and explicit removal tombstones prevent
  an older read from resurrecting deleted content.
- AppKit owns row geometry. Every new page is measured before its table update;
  visible rows are not first displayed with an estimated height and then resized.
  One detached measurement controller and the per-width height cache are reused.
- Every cell receives its actual hosting-view frame during configuration and
  `setFrameSize`, before display. The table uses full-width geometry without
  the system's implicit row inset. Bubble, image and file-card widths follow
  the transcript's available width.
- A message-ID-plus-offset anchor is restored after insertions and width changes.
  Table updates disable implicit animation. Highlight and swipe changes only
  refresh visible rows and do not invalidate message heights.
- Offscreen animated stickers pause. Offscreen measurement does not request
  photos, and images already in a reused row remain available on reappearance.
- JSONL framing searches only newly appended bytes rather than rescanning the
  whole incomplete frame for every input chunk.

## Verification

Synthetic checks cover equal timestamp cursor ties, forward/backward paging,
account changes, obsolete page responses, process ownership and shutdown,
incremental edits to older visible rows, scroll anchors, immediate hosting-view
frames, and wrapping at wide/narrow transcript sizes. Responsive render fixtures
contain synthetic text only.

Measurements and test logs are in
`output/performance-diagnostics-20261111/`. IPC framing of a 512,029-byte synthetic
frame in 4,096-byte chunks improved from approximately 104 ms to 0.54 ms median.
An independent 50-message page from a synthetic 10,000-message store took about
1.2 ms median. These exclude click-to-display latency and GPU frame pacing.

Strict clippy still reports existing repository lints outside the new history
reader. No protocol, crypto, store schema, user session or history data was
intentionally changed by this work. Old app/worktree cleanup is recorded
separately and must not remove the active Zalolite source or the clean upstream
clone.
