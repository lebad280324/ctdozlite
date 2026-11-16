# 65 — Rich attachment cards: contacts, calls, notices, official accounts

Evidence: `backup_check <export> <session> --shapes` (redacted survey added to
`src/zalo_backup.rs::survey_message_shapes`; strings cut to 10 characters, no values kept)
over a real Zalo PC export, 2026-11-16. Shapes are identical to the live `content` objects.

| `action` / marker | Shape | Shown as |
| :--- | :--- | :--- |
| `recommened.user` | `title` name, `thumb` avatar, `params` user ID, `description` JSON `{qrCodeUrl, phone, caption}` | Contact card (Kết bạn / Nhắn tin, QR). Phone is not shown. |
| `recommened.calltime` | `params` JSON `{calltype, duration, reason}`; `duration` seconds | Call card with duration; `calltype == 1` taken as video |
| `recommened.misscall` | same, `duration` 0 | Missed call card |
| `msginfo.actionlist` (msgType -1909) | `params.msg.vi` template `%1$s …`, names in `highLightsV2[].dpn` | Centered notice |
| `vote` (26) | `params.msg.vi`, `dName`, `question` | Centered notice with question |
| `params.customMsg.msg.vi` (msgType 52, zinstant) | Official-account template; body is a remote zinstant bundle | Its preview text (was "📢 Thông báo hệ thống Zalo") |
| content array (msgType 21, `chat.list`) | `[{title, description, href, thumb}]` | First article as link card (live parser previously produced empty text) |
| msgType -4 (export only) | `act` join/add/leave/remove, `eventInfo.updateMembers[].dName`, `eventInfo.source.dName` | Membership notice |

The parsed card is kept in `raw_json.card` so cached rows render the same after restart.
`calltype` meaning for video is inferred, not confirmed by a capture.
Profiles: `get_profile` now reports `is_official` when Zalo returns a non-empty `oaInfo` or an
`oa_status`; official accounts get no friend-request bar. Not yet confirmed on a live page profile,
so the UI also treats threads whose incoming links are `officialaccount.me` / `oa.zalo.me` as pages.

Block list (`/api/friend/blocklistv2`): the previous parser required id + name objects and raised
"Zalo trả về danh sách chưa được hỗ trợ". `blocked_rows` also accepts bare ID arrays and objects
keyed by user ID; the exact live shape is still unrecorded.
