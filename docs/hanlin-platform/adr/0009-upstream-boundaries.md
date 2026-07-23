# ADR 0009: Upstream boundaries

Status: accepted
Date: 2026-07-23

## Context

The README identifies CherryHQ/hanlin-ai as the source project, but this
checkout configures only the davidpovarsky origin. The branch contains extensive
downstream RuntimeCore, MCP, activity, native app, and native tool work.

## Decision

New platform logic is additive under `Packages/HanlinPlatform`,
`AI_HLY/Downstream/HanlinIntegration`,
`Reference/ScriptingCompatibility`, `Scripts/ScriptingReference`, and
`docs/hanlin-platform`. Existing upstream-derived files receive only narrow
bootstrap, route, package-reference, resource, entitlement, localization, or
adapter wiring.

## Consequences

No existing app file changes in Phase 0. The sole existing-file touchpoint is a
narrow `.gitignore` exception for the immutable, hash-verified imported
`tsconfig.json` files. Every unavoidable later touchpoint is documented by path
and reason. Upstream updates require substantive comparison; wholesale
ours/theirs conflict resolution is prohibited.
