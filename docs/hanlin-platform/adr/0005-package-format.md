# ADR 0005: Script package format and module loading

Status: accepted for format; bundler implementation deferred to Phase 6
Date: 2026-07-23

## Decision

Script applications use an explicit `.hanlinapp` package with versioned
`hanlin.json`, `package.json`, `tsconfig.json`, source, assets, locales,
migrations, and declared entry points. Installation is staged, validated,
atomic, hash-identified, rollback-capable, and policy-gated.

The runtime will execute a deterministic bundle or controlled module graph.
The final implementation choice requires a Phase 6 license, iOS, native
executable, size, startup, and ESM/CJS review. No bundler dependency is selected
in Phase 0.

## Consequences

Filename inference cannot create extension entry points. Lifecycle scripts and
native addons are denied by default. A package is never executed before
manifest, integrity, capability, dependency, and user approval gates pass.
