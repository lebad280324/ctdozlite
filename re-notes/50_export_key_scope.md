# Zalo PC export key scope correction

The earlier assumption in note 49 that the native session's current `dkey` must
open a same-account PC export is false for the real export tested locally.

Observed: the native dkey failed the tar checksum; the PC metadata record
`0_sync_cross_state_backup`, JSON `value.uin`, passed it. Its `value.userId`
exactly matched the authenticated account's public UID. The cryptographic
algorithm itself remains SHA-256 over the key string, AES-256-CBC and the
observed explicit V2 IV. No keys or message bodies are included in this note.

The reader now first validates the supplied session key, then reads only that
known account-matched metadata record from the PC Local Storage LevelDB. SST
blocks/raw Snappy and WAL records are parsed read-only with size/count bounds.
Unrelated storage fields and other accounts are never returned. Candidates must
pass the export's first tar-header checksum before a database can be opened.
The PC export key never replaces `LoginInfo.dkey` or crosses the UI bridge.

Manual verification on the user's selected archive used an isolated in-memory
SQLite store: 630 threads, 110678 imported/seen messages, zero skipped rows,
one message database, not cancelled. Source export and native history were not
modified. Media was skipped as designed. The old 'wrong account' error was
replaced with wording that also covers a different PC key or incomplete file.
