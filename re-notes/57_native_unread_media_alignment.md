# Native media alignment, unread state and notifications

Date: 2026-11-11. Local implementation; no request parameters, signing or protocol IDs changed.

## Findings

- `MessageRowLayout` reserves a landscape rectangle. The native image renderer fitted portraits at its center, moving their visible edge away from the text column. Native photos now fit against the incoming left or outgoing right edge. The timestamp follows the visible image. SwiftUI photo rows use the fitted size; inline file cards no longer use negative horizontal padding.
- Native push/poll handling called the history-oriented `chat::merge_previews`, which inserted messages without updating unread state. The separate live merge now counts newly inserted incoming numeric message IDs, respects server read cursors, and ignores outgoing messages, duplicate deliveries and history loads. The shared history merge retains its existing behavior.
- `ThreadDto` omitted `marked_unread`. It now exports this flag, with backward-compatible Swift decoding and badges/filter/menu handling for a manual unread mark even when the count is zero.
- Notifications use count increases, suppress startup history, muted/hidden threads and the foreground conversation being read at the latest message. Foreground read receipts wait for loaded content. An empty initial thread snapshot is also remembered as the initial snapshot.
- On this Mac, Zalolite notification permission was denied while all in-app notification settings were enabled. Enabled system notification permission through System Settings and verified desktop banners, sound and badges are on.

## Verification

- 23 Swift tests passed: incoming notification eligibility, manual unread decoding, portrait/landscape edge geometry, native rows and transcript/viewport behavior.
- 23 Rust chat tests and 7 unread tests passed, including two new live-merge regression cases.
- Swift release and Rust release worker builds passed; the existing `dist/Zalolite.app` bundle was updated with both binaries while retaining its helper/resources. Code signing and bundle validation passed.
- No message was sent to another person for testing. A new real incoming-message banner has not been observed. The running account was not deliberately restarted; reopening is needed to load the new binaries. The final CUA attempt to inspect/reopen the running app timed out.
