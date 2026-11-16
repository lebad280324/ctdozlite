# 59 — Live reactions, pinned bar, group notices, conversation library (12/11/2026)

Scope: response parsing, a reaction-code mapping fix and one local-only intent. No request
parameters, signing, command IDs or cipher flow changed.

## Reactions

- `chat::reaction_code_and_type` maps the six Zalo types (`/-heart` 5, `/-strong` 3, `:>` 0,
  `:o` 32, `:-((` 2, `:-h` 20; codes already in this file and in `reactions::emoji_for_type`).
  The native picker sent `😡`, which fell through to the default and was **sent as a heart**;
  the core also rejected `😆` ("Biểu cảm chưa được hỗ trợ"). `😡`→`:-h` and `😂`→`:>` now map
  to the existing types; the native React command normalises them before validation.
- The parser for live reaction envelopes (`reactions::parse_reaction_events`: `reacts`,
  `reactGroups`, `chat.reaction` rows; covered by its own tests) existed but nothing called it,
  so other people's reactions never appeared until a history reload. The native WebSocket
  loop now decodes `data` like `merge_live_previews` and applies those events to loaded
  messages through `ChatMessage::apply_reaction`.
- Your own reaction is recorded as an event from your UIN instead of a bare emoji, so other
  reactors are kept.
- Per-reactor summaries persist in the message `raw_json` metadata as `reaction_summaries`
  (additive key; no schema change). The DTO adds `reaction_details` (emoji, count, reactor IDs).

## Group notices

Leave/join and pin/unpin notices arrive (and are restored from backups) as plain text rows,
sometimes with sender `0`. `native_core::is_group_notice` reports them as `msg_type =
"chat.system"` for presentation only. Wording without an actor is matched only as a suffix
("… đã rời khỏi nhóm") or the pin phrase ("… ghim 1 tin nhắn"); broader wording requires the
text to begin with the sender's own name. Stored rows and identity are unchanged.

## Pinned bar

Reuses `list_pinned_topics` (`/api/board/pin/list`, re-note 47/48). Requested on opening a
group and again when a new pin notice arrives. Not requested in demo mode.

## `thread_library`

Local-only intent: loads up to 20 000 newest stored messages of one conversation and
returns up to 300 photos, files and links each, classified by the same DTO rules. Works
offline and in demo mode. Fixes the details card showing only the loaded transcript page.

## Not verified

No live reaction push was captured in this session; the live path is covered by a unit test
built from the parser's documented envelope. Visual checks used demo snapshots only.
