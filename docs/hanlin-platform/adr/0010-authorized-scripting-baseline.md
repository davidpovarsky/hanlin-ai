# ADR 0010: Authorized Scripting baseline

Status: accepted
Date: 2026-07-23

## Decision

The user-authorized root-level Scripting declarations, compiler metadata,
documentation, and examples are copied byte-for-byte into one portable
repository baseline. Originals are immutable; generated indexes and Hanlin
overlays are separate.

Baseline:

- ID `scripting-compat-2026-07-22-8d7d33d9369e`;
- aggregate SHA-256
  `8d7d33d9369ee555d15adf10c867abbfb85834eced7e7596a627b70ff627ff36`;
- 999 imported files.

The explicit root-level mapping resolves a byte-identical backup subtree.
`node_modules`, `.bin`, executables, archives, caches, temporary/editor files,
and secrets are excluded.

Git attributes disable text normalization and whitespace-error rewriting only
for `Reference/ScriptingCompatibility/**`. This preserves the recorded bytes
across Windows staging and clean macOS checkout without changing line-ending
or whitespace checking policy for the rest of the upstream-derived repository.

## Packaging decision

`Reference/ScriptingCompatibility/Original` is the single manually immutable
copy. Phase 6 will generate SwiftPM resources deterministically from it rather
than create a second manually edited copy. Essential indexes may ship in the
main app; complete docs may be a deterministic optional local resource if size
requires it.

## Consequences

The absolute source path is provenance only. `scripting` type checking uses the
exact declarations. Hanlin additions use overlays or `hanlin`. Runtime support
is tracked independently. A source hash change produces a new baseline
identity and an explicit drift review.
