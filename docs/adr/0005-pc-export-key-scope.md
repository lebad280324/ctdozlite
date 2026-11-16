# ADR-0005: Validate account-scoped PC export keys before import

- Status: accepted
- Decision: Retain the existing export cipher. Validate the session key against
  the first tar header; if it fails, use only the same account's PC sync-state
  key from local metadata and validate it before any history write.
- Evidence: `re-notes/49_zalo_pc_export_container.md` and the real-file correction
  in `re-notes/50_export_key_scope.md`.
- Privacy: read-only bounded local metadata parsing, no key logging, no IPC key
  fields, no replacement of native session credentials, and no network fallback
  needed when a valid local PC key exists.
- Verification: synthetic decoder/account isolation tests and read-only manual
  import into an in-memory store. Source exports and active history are retained.
- Limits: an export from a different machine/older unavailable PC key cannot be
  recovered by guessing; the user must retain the matching original PC metadata.
