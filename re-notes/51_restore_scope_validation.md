# Restore verification and conversation-loading correction

The real export was re-imported through the native UI. It read 110678 rows in
630 source conversations and inserted zero new messages, proving idempotency
against the already restored account store. Native store statistics were
110678 unique messages and 828 metadata rows including existing contacts.
No empty message thread IDs were found.

A separate private staging store imported the source again. An attached
read-only native store matched every source message ID and conversation ID;
text, timestamp and outgoing direction had zero differences. The staging
store was removed automatically. No message bodies or credentials were saved
in this evidence. Aggregates: output/restore-validation/verification.json.

UI inspection found load_messages hydrated the entire store into a one-thread
vector, then popped its last element, replacing the selected conversation with
an unrelated row. MessageStore::hydrate_loaded_threads now loads only the
supplied conversation set, preserving the requested identity and avoiding an
account-wide scan. A second old heuristic collapsed different message IDs with
matching text inside five seconds; hydration now reconciles by exact ID only.
Both cases have fixture-backed regressions in tests/native_history_scope.rs.

After the first fix, sampled personal and group conversations displayed old
history, with 860 and 1438 stored rows respectively. Media attachments remain
outside the restore scope. Some content references can still load from remote
URLs; that does not mean archive media files were copied locally.
