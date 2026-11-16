# ADR-0007: CoreText message rows in the native transcript

- **Status:** accepted
- **Date:** 2026-11-11
- **Scope:** Replaces the message-rendering part of ADR-0006; its worker, SQLite,
  pagination and scroll-anchor decisions remain in force.

## Context

The user uses a 120 Hz display, with approximately 8.33 ms between refreshes.
Viewport-first layout reduced work over the loaded history window, but fitting
SwiftUI message trees still exceeded that budget. The implementation started
by Claude Code was resumed after its usage limit. Evidence and remaining
limits are recorded in `re-notes/56_native_macos_120hz.md`.

## Decision

Use immutable `MessageRowLayout` objects and reusable AppKit cells for text,
quotes, link previews, reactions and photos. Cache attributed text and CoreText
typesetters; keep pixel geometry explicit. Limit each row's backing layer to
its drawn bounds and reuse the pixels when only its position changes.
Animated stickers and file cards retain the SwiftUI hosting fallback.

Maintain exact visible heights, bounded offscreen preparation and message-ID
scroll anchors. Lay rows out for the viewport width rather than an unsized
NSTableColumn. Bound photos by the actual bubble content width, including
space reserved for avatars and selection controls. Image arrival does not
change the reserved height. Photo transfer and decode remain asynchronous.

Keep the existing context-menu and swipe monitors. Native cells implement
drag selection and copy, quote jumps, photo opening and profile actions.
Static accessibility text remains exposed by each drawn message view.

The process installs the existing `CursorThrift` interposition of the public
`NSCursor.set` method to coalesce identical current-cursor updates for at most
one second. CPU sampling found repeated cursor-image registration expensive
with the user's pointer configuration. A different cursor always passes
through, and unexpected off-main calls use the original implementation.
This workaround requires manual cursor checks; it must not change system
pointer settings or be described as an AppKit guarantee.

## Consequences

- Native rows avoid SwiftUI fitting in the common rendering path. The shell,
  composer, stickers and file cards can still consume main-thread time.
- Native rendering owns geometry and interaction compatibility. Narrow photos,
  long text, date pills, redraw signatures and reading anchors need regression
  coverage. The optional positions in a redraw signature must remain constant
  when the corresponding element is absent.
- A display-link probe measures callback gaps and main-run-loop work, not
  independently observed compositor presentations. Occlusion, synthetic
  pre-decoded images and synchronous programmatic window resizing limit its
  conclusions. Unit tests or a successful build do not establish stable 120 FPS.
- No Zalo protocol or storage schema changes are involved.
