# 53 — Animated sticker sprites (11/11/2026)

Scope: presentation only. The request sent to Zalo is unchanged; the native worker
reads more fields from a response it already fetched.

## Evidence

- `https://api.zaloapp.com/api/emoticon/sticker/webpc?eid=<id>&size=130`, the URL the
  core used for every sticker, returned a static 130×130 PNG for the sampled IDs even
  with a browser `Accept: image/webp` header. It cannot animate.
- Installed `Zalo.app/Contents/Resources/app.asar` (static JavaScript only):
  - The sticker schema lists `stickerUrl`, `stickerSpriteUrl`, `stickerWebpUrl`
    (nullable), `totalFrames`, `duration`, `effectId`, `checksum`, `ext`.
  - The sticker renderer sets `backgroundImage` to the sprite, `backgroundSize` to
    `${n*totalFrames}px ${n}px` with `repeat-x`, and steps
    `backgroundPosition = -(frame*n)px 0` — a horizontal strip of square frames.
- The player calls `setInterval(next frame, t.duration || 250)`: `duration` is the
    interval per frame in milliseconds, not the total length.
- These rows come from the existing `sticker_detail` request in
  `chat::fetch_sticker_pack_items` (`GET {sticker}/api/message/sticker/category/sticker_detail`,
  params `{cid}`).

## Implementation

`chat::fetch_sticker_pack_art` repeats that same request (same host, params and
signing) and keeps `stickerSpriteUrl`, `totalFrames` and `duration` for rows with
more than one frame and an `https` sprite. Results are cached in
`stickers_cache/art_v1_<cid>.json`. The native `sticker_pack` result adds
`sprite_url`, `total_frames` and `duration_ms` per item; a failure leaves the static
items unchanged.

The Swift UI asks once per sticker category seen in the transcript and plays the
strip with a timeline, stepping one frame width per tick. Reduced Motion shows
the first frame. Sticker picker cells animate only while hovered.

## Not verified

No signed-in `sticker_detail` response was captured in this session; the field
names come from the shipped schema. A parser fixture covers the selection rules.
If live rows use other names, stickers stay static rather than failing.
