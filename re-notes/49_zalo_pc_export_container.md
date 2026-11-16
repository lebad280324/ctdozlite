# 49 — Zalo PC export container (`backup_zalo_*.zl.zip`)

Date: 2026-11-10. Scope: read-only import of the official Zalo PC "Xuất dữ liệu"
file into the local SQLite store. No request parameters, signing, frame IDs or
cipher flow of the chat protocol change.

## Evidence

Static JavaScript in the locally installed `Zalo.app/Contents/Resources/app.asar`
(183,869,581 bytes, dated 2026-10-30). No Zalo session, cookie or user database
was read. One real export on this machine was inspected only for size and byte
entropy: 4,153,812,496 bytes (a multiple of 16), entropy 7.997 bits/byte from the
first byte, no zip signatures. It is not a zip archive despite the extension.

- Byte 7193837, file-manager module (duplicated in three other bundles):
  - extensions `V1=".zip"`, `V2=".zl.zip"`; database files `V0=".zb"`, `V4=".zdb"`.
  - `getCipherKey(e) = sha256(e)`; `getCipher(e) = createCipheriv("aes-256-cbc",
    key, Buffer.from("zie" + e.slice(0, 13)))`; `getDecipherV2` mirrors it.
  - `getDecipherV1(e) = createDecipher("aes-256-cbc", key)`: Node derives key and
    IV with `EVP_BytesToKey` (MD5, one round, no salt) from the SHA-256 digest.
  - Export pipes `tar-fs` `pack(ZaloPC dir, {entries})` through the cipher into
    `<name>.ztemp`, then renames it to `backup_zalo_DD_MM_YYYY.zl.zip`.
  - Import reads `<importTemp>/<uid>/ZaloDownloads/database/<uid>_z<table>.<ext>`.
- Byte 55210826, data-access module: `loadMessagesForBackup` returns rows of
  `DB.Core.Message` by index `userId_sendDttm_msgId`; `loadConversationsForBackup`
  returns `DB.Core.Conversation` rows (`userId`, `firstSmsLocalId`,
  `lastSmsLocalId`, `respondedByMe`, `numMsg`) — counters only, no display names.
- Byte 55237767, export/import class: each row is written as
  `JSON.stringify(row) + "\n"`; `encrypt`/`decrypt` are identity for `.zdb`, and
  `decryptV2` only applies to legacy `.zb`. Import reads `userId`, `toUid`,
  `fromUid`, `msgId`, `cliMsgId`, `msgType`, `sendDttm`, `message`, `localPath`,
  `staredDttm`; a group conversation id starts with the group prefix.
- Byte 63142334: the value passed as `e` is `UIN: data.dkey` from
  `GET /api/login/getLoginInfo`, not the numeric user id.

## Implementation

`src/zalo_backup.rs` decrypts with the account `dkey`, validates the first tar
header checksum (a wrong account key fails here), and walks the tar stream.
File bodies outside `database/` are skipped by seeking: CBC resumes from the
preceding ciphertext block, so media volume does not affect time or memory.
`*_zmessage.zdb` rows are upserted in batches of 5,000 with `INSERT OR IGNORE`,
so a repeated or interrupted import does not duplicate messages.

`LoginInfo.dkey` is now kept from the existing `getLoginInfo` response. A session
saved by an older build lacks it; the native worker issues that same existing
request once before the first import and saves the key in `session.json`. The
key is secret and never crosses the UI bridge.

> Correction (2026-11-11): the assumption below that the session `dkey` opens a
> same-account PC export did not hold for the real export. See
> `re-notes/50_export_key_scope.md` for the key actually used and
> `re-notes/51_restore_scope_validation.md` for the verified real import.

## Verified and not verified

- Synthetic archives built in the tests cover V1 and V2 key derivation, pax-free
  ustar headers with a prefix field, seeking over a 300 KB body, malformed rows,
  wrong key, truncation, media-only exports and idempotent re-import.
- Not verified against a real export: no `dkey` was available to the assistant.
  Open points to confirm on the first real import: that `.zdb` `message` values
  are plain (text or attachment object) rather than locally XOR-encoded, the
  `msgType` representation, and that 1:1 conversation ids equal the live thread ids.
- Media files in the export are not copied or linked. Legacy `.zb` databases are
  detected and reported as unsupported.
