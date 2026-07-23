# ADR 0011: TypeScript compiler versioning

Status: accepted for Phase 0; implementation gated to Phase 6
Date: 2026-07-23

## Context

The authorized Scripting workspace locks TypeScript 7.0.2. The existing Hanlin
runtime host locks TypeScript 6.0.3. The exact original `tsconfig.json` uses
strict CommonJS and classic JSX with `createElement` and `Fragment`.

## Decision

Hanlin records two explicit conformance lanes:

1. `scripting-original`: exact declarations and exact original tsconfig with
   TypeScript 7.0.2 for reference compatibility verification;
2. `hanlin-embedded`: the controlled iOS-capable compiler resource, currently
   6.0.3, with differences surfaced rather than hidden.

Phase 6 must determine whether the iOS compiler can move to the reference
version, whether both lanes remain necessary, and which language features each
accepts. It must use a full TypeScript program/incremental builder for projects.
One-shot `transpileModule` remains limited to developer snippets.

## Consequences

No source declaration is edited to accommodate compiler drift. Windows-native
compiler executables and local `node_modules` are never packaged. Diagnostics,
fixtures, autocomplete, hover, signature help, and source maps record compiler
lane and version.
