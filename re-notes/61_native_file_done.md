# 61 — Native file attachments failed with HTTP 405 (12/11/2026)

Symptom: sending a pasted document (or other non-image file) from the native app showed the
generic "Không thực hiện được thao tác" banner.

## Evidence

`native_errors.log` (sanitised failure log added in this change):
`send_attachment HTTP 405 Method Not Allowed from …/api/message/sharefile_full`.

## Cause

`chat::send_attachment` uploads files with `asyncfile/upload`, then waits for the
`act_type: "file_done"` control that carries the file URL before `asyncfile/msg` (PR #85).
The egui worker and `lp_control` poll feed those controls through
`chat::dispatch_file_done_controls`; the native core never did. With no feeder,
`FILE_DONE_LISTENER_ACTIVE` stayed false, the wait was skipped, and the fallback
`sharefile_full` endpoint (no longer accepting POST) returned 405.

A second issue would have hidden a fix made inside the command loop: the loop awaits each
command inline, so it does not read the WebSocket while `send_attachment` waits.

## Change

`native_core::websocket_feed` wraps `socket::spawn` in a task that dispatches `file_done`
controls as soon as they arrive (same node as the egui worker, plus the decoded form when
`data` is a JSON string), then forwards every event to the command loop unchanged. No request
parameters, signing or endpoints changed.

`record_failure` writes one line per failed command to `native_errors.log` in the data folder,
with query strings and long key-like tokens removed, capped at 400 characters and 256 KB.

## Not verified

A live file send after this change has not been observed yet.
