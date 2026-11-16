# 58 — Location messages and profile card (12/11/2026)

Scope: response parsing and one new native intent built from existing requests. No
request parameters, signing, command IDs or cipher flow changed.

## Location messages

Evidence (installed `Zalo.app` `app.asar`, static JavaScript):
- `chat.location.new` maps to `MSG_LOCATION`.
- The `card--location` renderer reads `content.lat`, `content.lo` and `content.title`,
  and opens `https://maps.google.com/maps?q=<lat>,<lo>&z=14`.

Before this change the core kept only the title text, so a shared location showed as
an address bubble. `chat::location_point` now reads `{lat, lo, title}` (also inside a
JSON `params` string) and stores the point as `link_url`
`https://maps.google.com/maps?q=<lat>,<lo>&z=15` with `link_src = "Vị trí Zalo"`, which
persists through the existing SQLite `raw_json` metadata. The native DTO reports
`msg_type = "chat.location"`. The Swift UI draws the map locally with MapKit.
Messages stored before this change have no coordinates and remain text bubbles.

## Profile card (`get_profile`)

Reuses existing requests only:
- `Session::get_friend_social_profile_value` — the same `GET /api/social/friend/getprofiles`
  call as `get_friend_social_profile` (feed.rs), returning the raw object so fields such
  as `phoneNumber` can be read.
- Fallback for non-friends: `chat::get_mini_profiles` (display name, avatar).
- `chat::check_friendship_status` (`/api/friend/reqstatus`) for the friend bar.

The intent returns only display fields (name, avatar, cover, gender, `sdob`, status,
phone, friendship). Zalo may withhold full fields from non-friends; the UI says so.

## Not verified

No live location message or profile response was captured in this session. Parser
tests cover direct and nested coordinate shapes and invalid points.
