# ADR-0004: Native macOS frontend with a private Rust worker

- **Status:** accepted
- **Date:** 2026-11-10
- **Deciders:** user and implementation team

## Context

The user wants a SwiftUI/AppKit interface while retaining the existing Rust Zalo
protocol implementation. The current egui worker mixes UI contexts and decoded
textures with session, message and media operations. Existing egui edits are
uncommitted and must remain available. This decision changes the local UI/worker
boundary, not the Zalo wire protocol, cipher flow, service map or store schema.

## Decision

The macOS frontend is a separate Swift Package application. It owns one private
`ctdozlite-core` child process and exchanges versioned JSON Lines over anonymous
stdin/stdout pipes. The Rust worker calls the existing session, chat, socket,
media and store modules. Commands carry request IDs and receive terminal results;
independent events update public-safe session, thread and message snapshots.
No local HTTP listener, shell command interpolation or session credentials are
part of the bridge. Session and store ownership stay in Rust (INV-2, INV-3).

The frontend launches and reads the process off the main thread and delivers
events to its UI state on the main actor. The child receives an explicit private
data directory. Demo mode is synthetic and cannot touch the user's session or
send a Zalo request. The native bundle has a separate identifier and does not
replace the existing application. It does not use the legacy self-updater until
a native release asset contract is available (ADR-0002).

## Consequences

- Rust protocol behavior is reused rather than reimplemented in Swift.
- The UI can use native text input, menus, keyboard shortcuts and split views.
- IPC payloads and errors must remain bounded and contain no session keys.
- EOF, child termination and request timeouts must clear pending UI operations.
- Runtime UI independence precedes build dependency extraction: the shared Rust
  crate still compiles egui through legacy media/call adapters.
- The native capability list is explicit. Migrating a chat screen does not imply
  that every existing egui feature has been migrated or verified against Zalo.
- Packaging, shutdown and regression coverage are required alongside UI work.

## Alternatives considered

| Option | Reason not selected initially |
| --- | --- |
| Rewrite the Zalo client in Swift | Duplicates protocol work and increases compatibility risk. |
| Embed Rust with a C ABI immediately | Requires memory/callback ABI ownership and unsafe glue before UI behavior can be evaluated. |
| Local HTTP server | Adds port ownership and authentication concerns without helping this private desktop boundary. |
| Replace the installed app immediately | Risks losing access to existing uncommitted UI work and unported features. |
