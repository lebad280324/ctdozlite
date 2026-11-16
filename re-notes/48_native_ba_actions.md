# 48 — Native BA workspace actions

Date: 2026-11-10. Scope: native Rust/SwiftUI UI intents. No live account or
outbound request was used for development tests. This note records static
request contracts, not evidence that each operation has passed against Zalo.

## Owning evidence

Read the static JavaScript shipped in the locally installed Zalo application,
extracted by the parent task under `/tmp/ctdo-ba-protocol/`. No session, cookies,
account databases or network capture was read.

- `compact-app-pc.cfeba43a9a8e4e40dda3.js`:
  - byte 14502807: higher-level `createGroupV2` maps selected users to UID strings,
    omits the current user, defaults `groupType` to null, and resolves
    `data.groupId` and `sucessMembers` from the response.
  - byte 15044028: request `createGroupV2` (12443), GET
    `/api/group/create/v2`, group service. Params: `clientId`, `gname`,
    `gdesc:null`, `members`, optional `memberTypes`, `nameChanged` (0/1),
    `createLink:1`, `clientLang`, `imei`, `groupType`. Optional JavaScript
    undefined fields are omitted; the native ordinary-group path does not
    invent a member-tracking enum.
  - byte 15059354: `getRequestedFriends` (12203), GET friend service
    `/api/friend/requested/list`, params `{imei}`. Response rows are projected
    onto safe identity/name/avatar fields; unknown nonempty shapes fail visibly.
  - byte 15064797: `inviteMemberV2` (12444), POST group service
    `/api/group/invite/v2`, params `{grid,members,memberTypes?,imei,clientLang}`.
  - byte 15069068: `getGroupInvitationList` (12170), GET group service
    `/api/group/inv-box/list`, default params
    `{mpage:1,page:0,invPerPage:10,mcount:10,lastGroupId:null,avatar_size:160,member_avatar_size:160}`.
    The module-level avatar constant `se` is 160.
    `joinGroupByInvitationBox` (12172), GET `/api/group/inv-box/join`,
    params `{grid,lang}`.
  - `getBlockFriends` (11429), GET friend service `/api/friend/blocklistv2`,
    default params `{page:1,count:50,avatar:75}`.
  - `setBlockFriend`, POST friend service `/api/friend/block` (11422) or
    `/api/friend/unblock` (11433), params `{fid,imei}`.

Alias functions follow `re-notes/36_mentions_alias.md` in the existing feature
checkout. GET alias service `/api/alias/update` takes `{friendId,alias,imei}`;
GET `/api/alias/remove` takes `{friendId}`.

Group members reuse the existing feature checkout's `get_group_members`:
`fetch_group_profiles` -> `memVerList` -> batches of existing
`chat::get_mini_profiles`, plus creator/admin roles. Pinned-topic listing reuses
its GET group_board `/api/board/pin/list` with `{groupId,boardVersion:0,imei}`.
The parent task centralizes the group_board host in `src/endpoints.rs`.

## Existing primitives reused without wire changes

`chat::set_unread_mark`, `set_hidden_conversation`, `delete_conversation`,
`get_friends`, `get_groups`, `get_mini_profiles`, `fetch_group_profiles`.
Server-side mutations only update local presentation after a checked zero
`error_code`. Empty/missing result codes do not count as success.

## Explicit local scope

Bookmarks, local message pins, priority/category organization, quick replies
and reminders persist in the active account's SQLite database. They are not
represented as server-wide flags. `scope: local` appears in relevant replies.
Server pin listing remains separate from local message pinning. No guessed
server pin-message creation flow, report reason enum or account security toggle
was added here.

Schema migration 2 adds only `native_local_preferences`; it leaves existing
message/history columns intact. Preference writes are bounded to 2 MiB and
parameterized. Databases declaring a newer schema version fail closed.

## Verification and remaining checks

- Synthetic/in-memory tests cover bookmark/pin separation, idempotency,
  unconfirmed destructive actions, exact group identity, duplicate quick-reply
  shortcuts, account-store isolation, preference limits and safe URL/DTO projection.
- Static payload tests lock the create-group request fields and member shape.
- Lists expose `partial:true` because only a bounded page is requested. This
  must not be presented as an exhaustive list or a reliable global count.
- Live verification still required: response shape of friend/group invitations,
  partial-success group membership outcomes, group creation and joining,
  server alias changes, block/unblock and hidden/unread/delete effects.
