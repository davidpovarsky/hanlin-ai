# ADR 0012: deterministic multi-runtime Scripting

Status: accepted and partially implemented, 2026-08-24

## Decision

Runtime selection belongs to each entrypoint and is persisted as the typed
`HanlinRuntimeProfile`; engines are never tried as fallbacks. Original
Scripting TS/TSX/JS selects `scripting-jsc`, while original `index.py` selects
`hanlin-python` and requires an explicit trust review. Native Hanlin manifests
may select `hanlin-quickjs`, `hanlin-node`, or `hanlin-python`. Hybrid packages
communicate only through `HanlinValue` and the versioned typed wire.

`scripting-jsc` owns one persistent `JSVirtualMachine`/`JSContext` per package
session and is the compatibility engine. Public JavaScriptCore has no verified
hard memory, stack, or interruption controls; its contract says so and relies
on isolated contexts, bounded bridge messages, cooperative cancellation,
lifecycle disposal, and trust policy. `hanlin-quickjs` retains hard heap,
stack, interrupt, deadline, and output controls and has no ambient privileged
globals. NodeMobile and CPython are trusted-worker runtimes, never extension
runtimes or OS sandboxes. Shell remains an allowlisted capability service.

Legacy installed entrypoint descriptors without a profile decode as
`hanlin-quickjs`, preserving the historical engine. Newly analyzed original
packages persist the canonical JSC/Python choice. Runtime profile, engine
version, capabilities, compiler provenance, and integrity participate in
encoded descriptors and therefore in cache and authorization material.

## Compiler lanes

The [official TypeScript 7.0 announcement](https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/)
identifies 7.0.2 as a native command-line compiler and says a different
programmatic API is planned for 7.1. No
official iOS artifact or supported in-process NodeMobile integration is
published. TypeScript 7.0.2 therefore remains the authoritative host/CI
typecheck lane. The pinned TypeScript 6.0.3 JavaScript compiler in NodeMobile is
the on-device emitter/bundler lane; contracts record the two versions and their
separate hashes. Product text must not claim TypeScript 7 runs on iOS.

## Consequences

The compatibility fixture and assistant-tool route now execute with a
persistent JSC session. QuickJS remains separately testable as Hanlin Secure
JavaScript. Node/Python worker routing, production on-device project bundling,
and real-package acceptance remain gates until their end-to-end adapters and
Xcode evidence exist; no fallback masks those missing paths.
