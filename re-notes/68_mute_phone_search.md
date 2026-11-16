# 68 — Unmute action, phone lookup noise, in-conversation search

## Unmute (error 114)
Evidence: Zalo PC `app.asar`, `setMuteConversation(e,t,n,a,i=-1)` posts
`{toid, duration, action:t, startTime (unix s), muteType: 1 user | 2 group, imei}` to
`/api/social/profile/setmute` (11288). Callers pass `SET_MUTE` / `UNSET_MUTE`; the module defines
`SET_MUTE = 1`, `UNSET_MUTE = 3`. The client sent `action = 2` to unmute; native_errors.log shows
`mute_thread server error 114` for each attempt. Now 1 / 3.

## Phone lookup from the search panel
Each pause while typing a number looked up the partial number (9–12 digits); Zalo rejected the
partial ones and each failure raised a banner while the final lookup succeeded. The panel now
looks up only a whole number (`0` + 9 digits or `84` + 9 digits) and shows failure in place.

## In-conversation search
Searching no longer filters the transcript. Matches in loaded messages are listed newest first;
the newest is scrolled to and flashed, Enter / ↑ step to older matches, Shift-Enter / ↓ to newer,
and matched text in native rows is marked yellow. Whole-history search stays under "Toàn bộ lịch sử…".
