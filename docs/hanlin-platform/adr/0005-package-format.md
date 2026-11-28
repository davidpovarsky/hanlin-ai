# ADR 0005: Script package format and module loading

Status: superseded by the full Scripting execution authorization
Date: 2026-07-23

## Decision

Users import `.scripting` packages and `.zip` archives containing one
unambiguous Scripting project. Hanlin validates `script.json`, source, assets,
locales, and inferred or declared entry points, then converts the accepted
input into a versioned canonical Hanlin package and artifact manifest.
Installation is staged, validated, atomic, hash-identified, rollback-capable,
and policy-gated.

The runtime executes a deterministic closed module table produced by the
trusted TypeScript 7.0.2 compiler service. Imported code never runs in Node.
Only package-local TS/TSX/JS/JSON and explicitly registered virtual modules are
eligible for resolution.

## Consequences

Filename inference is validated against the supported Scripting conventions;
it cannot grant capabilities. Lifecycle scripts, arbitrary npm resolution, and
native addons are denied. A package is never executed before
manifest, integrity, capability, dependency, and user approval gates pass.
