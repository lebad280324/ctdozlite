# 62 — Link previews were shown as broken photos (13/11/2026)

Symptom: a shared web link with a preview (title, description, picture) appeared in Zalolite as
an empty photo box with the description underneath, while Zalo shows a link card.

## Evidence

Stored row (values shortened): `link_url` = the shop page, `link_title` = the same URL,
`link_desc` = page description, `link_thumb` = `photo-stal-31.zdn.vn/...jpg`,
`link_src` = "Hình ảnh Zalo".

## Cause

`parse_chat_message` treated any message whose thumbnail is on Zalo's photo CDN as a photo.
Link previews always carry such a thumbnail, so the web page URL became the "photo" URL.

## Change

- Parser: a CDN thumbnail marks a photo only when `link_url` is not an ordinary web page.
  Real photos (`chat.photo`, or `link_url` on the photo CDN) are unchanged. Test:
  `link_preview_with_cdn_thumbnail_stays_a_link`.
- DTO: history already stored with the wrong label is shown as a link when `link_url` is a web
  page and the row has a description or a title equal to the URL.
- The DTO now carries `link_desc`; the native link card uses it as the heading when the title is
  only the address, and shows the picture from `link_thumb`.

No request parameters, signing or endpoints changed.
