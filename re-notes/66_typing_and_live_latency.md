# 66 — Typing indicator and live message latency (native)

## Typing
Evidence: Zalo PC `app.asar` control handler (bundle text near `"gtyping"==t.act`):
`actions[]` items with `act_type == "typing"` and `act` `typing` (1:1) or `gtyping` (group);
`data` is a string that Zalo PC wraps in braces before `JSON.parse` (`a&&(e="{"+t.data+"}")`),
then drops events whose `uid` is the own account. The group thread field is taken as `gid`
(fallback `grid`, `groupId`) — not confirmed by a capture. Delivered on WebSocket `cmd 602`.
Zalo sends no "stopped typing"; the native UI lets each mark lapse after 6 s, or clears it when
a message from that person arrives. Test: `native_core::tests::typing_controls_name_thread_and_person`.

## Latency
Before: each live chat push (`is_chat_ish`) awaited `persist()` — a full serialise + SQLite
write of every thread — before `publish()`, and the command loop handled nothing else meanwhile.
Now the push is published first and saved by a 2 s batch timer (and once more on shutdown).
The 5 s HTTP poll remains the fallback when a push is missed. Not measured on a live account.
