# 67 — Original profile photo; unread badge on the open conversation

## Full avatar
Evidence: Zalo PC `app.asar`, `static getFullAvatar(e)`:
GET `getProfileDomain() + "/api/social/profile/avatar?" + commonParams + "&params=" + AES({fid, imei})`
(action code 11860). Callers read `full_avatar` (fallback `bk_full_avatar`) and show it on avatar
click (`showImage(b, o.fullAvatar || o.avatar)`). Native command `full_avatar {user_id}` returns
`{user_id, url}`; the viewer opens the small photo at once and swaps to the original when it
arrives. Not yet confirmed against a live response; the response shape is as read from the bundle.

## Unread on the open conversation
A live message reaches the UI as `messages` before the `threads` snapshot that counts it unread,
so the "mark read while visible" check ran while the thread still looked read and was never
repeated. The UI now repeats the check on every `threads` snapshot; `mark_seen` publishes the
cleared badge before the slow full-store write.
