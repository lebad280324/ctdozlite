# 63 — Zalo nicknames, removing a reaction, several accounts (14/11/2026)

## Nicknames (`list_aliases`)

Evidence: installed Zalo PC bundle, `getAlias(page=1,count=20)` (cmd 12200):
`GET {alias}/api/alias/list?{common}&params=encodeAES({page,count,imei})`; `/api/alias/update`
and `/api/alias/remove` were already used by `update_alias`. The native worker pages with count 100
(at most 50 pages) through the standard path (`encoded_params`, alias endpoint, `maybe_decrypt`).
The response parser accepts `data.items` (or `aliases`/`list`/a bare array) with `userId` + `alias`;
the exact live shape has not been captured yet. Test: `alias_rows_keep_only_people_with_a_nickname`.
The UI shows the nickname in place of the Zalo name, as Zalo does.

## Removing a reaction

Evidence: Zalo PC's reaction bar defines removal as `{rType: -1, rIcon: ""}`.
`chat::reaction_code_and_type("")` returned the default `/-heart` (5), so a removal would have
sent a heart. It now returns `("", -1)`. Test: `empty_reaction_removes_instead_of_sending_a_heart`.

## Several accounts

No protocol change. The native app keeps each account's session file as
`accounts/<uin>.json` (0600, inside the data folder) next to its existing per-account history, and
switches by stopping the worker, swapping `session.json`, and starting it again — the same model as
`account_manager.rs` in the egui client. Only the active account is connected.
