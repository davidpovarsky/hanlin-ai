# ADR 0003: Script isolation

Status: accepted
Date: 2026-07-23

## Decision

Ordinary imported applications use a `sandboxedApplication` profile in
dedicated JavaScriptCore isolation. They receive no Node globals, direct
filesystem/network, native modules, process API, or raw native objects. Every
native effect crosses a bounded, versioned, capability-checked RPC boundary.

Existing MCP and explicitly trusted developer/build work may use
`trustedDeveloperNode`, with a visible warning that Node permissions are not a
malicious-code sandbox.

## Consequences

Compilation can use trusted embedded Node but application execution cannot.
Persistent JavaScriptCore sessions are separate from the current one-shot
evaluators. Hard interruption remains an SDK/device verification spike and is
not promised by this ADR.
