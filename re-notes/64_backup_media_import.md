# 64 — Importing photos, videos and files from a Zalo PC export (14/11/2026)

Scope: local, read-only use of the official export; no request, signing or protocol change.

## Evidence (real export on this machine, counts only)

Survey with `backup_check <export> <session> --inspect` (decrypts headers and the message
database, seeks over media bodies):

| Folder under `<uid>/ZaloDownloads/` | Entries | Size |
| --- | ---: | ---: |
| `resource/<conversation>/{picture,video,file}/` | 4,193 | 3.16 GB |
| `file/<32-hex>` | 446 | 946 MB |
| `database/` | 3 | 179 MB |

- Photos are JPEG XL: `<cliMsgId>_<conversation>_<sender>_<hash>.jxl`. The leading number is the
  client send time; e.g. `1790764513726` matched a photo message with server time
  `1790764514850` in the same conversation. The hash is not the MD5 of the photo URL.
- Documents: `resource/<conversation>/file/<cliMsgId>_<sender>_<conversation>`, no extension.
- `file/<32-hex>`: all 442 bodies have the same size as a `resource/` body — a second copy. Not
  copied (saves ~946 MB). Their name is neither the URL MD5 nor the message `checksum`.
- 357 message rows carry `localPath` (mostly videos), pointing at `resource/...`.

## Matching (dry run `--media-plan` on the same export)

1. `localPath` → exact file. 2. Photos, videos, documents → same conversation and kind, message
time within −5 s … +180 s of the file's client time, nearest wins, each message used once.
Result: 3,684 of 3,737 files linked; 53 left unlinked (no matching message: recalled or deleted).

## Implementation

`zalo_backup::media` copies `resource/` bodies into `<account>/media/` (atomic rename, size-checked
re-runs, paths validated against `..`/absolute components), restores document extensions from the
message's file name, and adds `local_path` to each message's `raw_json`. The model, store and DTO
carry `local_path`; the native UI prefers the local copy and falls back to Zalo's URL when the file
is missing. Import commands may now run up to 12 h (they previously hit the 120 s command limit).
Tests: `media_import_copies_resources_links_messages_and_skips_repeats`, matching and path tests.
