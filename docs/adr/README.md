# Architecture Decision Records

One file per decision: `NNNN-<kebab-name>.md`, numbered from `0001`, never renumbered.

## Template

```markdown
# ADR-0001: <Decision title>

- **Status:** proposed | accepted | superseded by ADR-NNNN | deprecated
- **Date:** YYYY-MM-DD
- **Deciders:** <names/roles>

## Context

Forces at play, constraints, evidence (capture note, upstream behaviour).

## Decision

What we will do, in one paragraph, present tense.

## Consequences

- Positive:
- Negative:
- Follow-ups:

## Alternatives Considered

| Option | Why rejected |
| :--- | :--- |
```

## Index

| ADR | Title | Status |
| :--- | :--- | :--- |
| [0004](0004-native-macos-frontend.md) | Native macOS frontend with a private Rust worker | accepted |
| [0006](0006-native-transcript-and-history-pages.md) | AppKit transcript and independent local history pages | accepted |
| [0007](0007-coretext-message-rows.md) | CoreText message rows in the native transcript | accepted |

Related domain language lives in [`/GLOSSARY.md`](../../GLOSSARY.md).
