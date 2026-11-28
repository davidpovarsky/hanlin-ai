# Hanlin Contract Decision Register

Snapshot: `codex/fix-mcp-reachable-compatibility` at `da0929110903c83e9314ccd29d14d6d8be987d1a`.

This register records decisions already evidenced by repository ADRs separately from recommendations produced by this audit. An **audit recommendation** is not authorization to implement Phase 2.

## Status vocabulary

- **Accepted in repository** — recorded by an existing ADR and reflected at least partly in source.
- **Audit recommendation** — recommended by this audit; owner approval is still required.
- **Open/blocking** — must be explicitly resolved before a safe convergence or migration phase.

## Decisions

| ID | Status | Decision | Reason and evidence | Consequence / next gate |
| --- | --- | --- | --- | --- |
| CAD-001 | Accepted in repository | Keep the platform kernel as a separate package with value contracts and no UI/runtime implementation dependency. | D: ADR 0001 selects a platform kernel; C: `Packages/HanlinPlatform/Package.swift` exposes only `HanlinPlatformContracts`. The app does not currently link it. | Preserve package independence. Linking/adapters are a future, separately approved change. |
| CAD-002 | Accepted in repository | Treat native and script apps as two implementations of one conceptual app surface, while preserving their distinct runtimes. | D: ADR 0002. C: `HanlinAppImplementation` models native/script/hybrid, but the live native runtime remains separate and Scripting remains reference-only. | Do not force executable `NativeAppModule` behavior into portable descriptors. Define launch/session/service contracts before integration. |
| CAD-003 | Audit recommendation | Adopt a three-layer architecture: canonical value contracts → subsystem adapters → existing runtime/UI implementations. | C/I: platform descriptors are clean but unlinked; live models carry closures, `AnyView`, `[String:Any]`, paths and actor isolation. Direct replacement would lose behavior and risk persistence. | Preferred architecture option. Requires owner approval before any adapter work. |
| CAD-004 | Audit recommendation | Make `Hanlin*ID` types canonical at new platform boundaries, while keeping legacy String/UUID identities inside adapters and persisted stores temporarily. | C: typed ID families in `HanlinIdentifiers.swift:92-216`; live NativeApp/MCP/session models use strings/UUIDs. | Specify normalization, collision and round-trip rules. No in-place persistence rewrite until migration/recovery policy is approved. |
| CAD-005 | Open/blocking | Choose a lossless conversion policy among `HanlinValue`, `RuntimeJSONValue`, Foundation JSON and MCP SDK `Value`; do not alias or replace them yet. | C: `HanlinValue` distinguishes integer/data and canonical encoding; `RuntimeJSONValue` does not; MCP schema/value can contain arbitrary JSON. | Decide numeric fidelity, binary representation, non-finite rejection, key ordering, size/depth limits and unknown-schema preservation; then test round trips. |
| CAD-006 | Audit recommendation | Define one logical tool namespace/catalog contract, but retain native and MCP executable registries behind adapters. | C: `NativeToolCatalog`, `MCPToolCatalog` and `AssistantToolBridge` are live and semantically different; `HanlinToolDescriptor` is metadata only. D: ADR 0008 calls for tool unification. | Preserve native-first resolution unless a versioned conflict policy replaces it. Add canonical invocation/result/progress/cancel contracts before catalog convergence. |
| CAD-007 | Open/blocking | Specify the permission model before exposing Scripting or third-party packages: request, decision/grant, effective scope, expiry, revocation, policy enforcement and audit. | C: native registry hard-codes status and network broker does not enforce it; platform has declarations and a decision ID only; Scripting reference names privileged APIs. | No third-party/script capability should be represented as implemented merely because it appears in declarations. |
| CAD-008 | Audit recommendation | Preserve current user-data formats as legacy compatibility boundaries until ownership and migrations are explicit. | C: MCP schema-1/legacy-schema-0 primary+backup repair; AgentRun schema 4 inside ChatMessages; multiple UserDefaults/Keychain/JSON stores. | Add adapters/readers first. Do not rewrite or delete registry, chat, tool UI, native-app or secret data during initial platform linkage. |
| CAD-009 | Audit recommendation | Split installed package identity/metadata from user configuration, resolved runtime configuration, runtime state and cached discovery. | C: `MCPServerDescriptor` currently mixes all four; `MCPServerConfiguration` is already a narrower execution boundary. | Design a portable installed-instance record without absolute paths, and derive runtime configuration locally. Preserve current registry through migration. |
| CAD-010 | Accepted in repository | Treat the authorized Scripting snapshot as a pinned compatibility reference, not a claim of runtime implementation. | D: ADR 0010 and ADR 0011; C: generated compatibility records are planned/false, reference compiler is 7.0.2 and embedded TypeScript is 6.0.3. | Every implemented API needs explicit mapping, availability and verification. Keep reference assets outside app target. |
| CAD-011 | Accepted in repository | Keep downstream features separated and minimize upstream-owned file changes. | D: ADR 0009 and root `AGENTS.md`; H: downstream features are mainly under `AI_HLY/Downstream`, `NativeAppPlatform`, `NativeAgentExtensions`, packages and docs. | Future integration should add narrow entry/import/registration bridges and document each unavoidable upstream-file edit. |
| CAD-012 | Open/blocking | Decide the verification and release gate for any future platform integration; this audit itself establishes no build result. | C: current app target is Swift 6/iOS 26; package is Swift tools 6.2. D: last documented full IPA closure belongs to commit `2c41b445…`, not current HEAD. | On explicit request only: run relevant package tests and Xcode workflow, capture Xcode/SDK/Swift mode, diagnostics, persistence fixtures and round-trip tests. |

## Architecture choice pending owner approval

The audit recommends **CAD-003 / Option B: canonical contracts plus adapters**, described in `CONTRACT_AUDIT_REPORT.md`. It best preserves upstream mergeability and user data while establishing a durable platform boundary. The following are deliberately not decided by this audit:

1. Whether `HanlinPlatformContracts` becomes an app dependency immediately or only after missing contract families are added.
2. Whether IDs are stored in a prefixed string form, structured objects, or both at different boundaries.
3. Whether `HanlinJSONSchema` remains a platform-native schema language or gains a lossless raw JSON Schema escape hatch.
4. Whether native and MCP tool names share one global namespace or remain provider-qualified.
5. Permission prompt UX, grant persistence, expiry defaults and revocation semantics.
6. Installed-package ownership, backup classification and uninstall recovery behavior.
7. Which Scripting execution contexts are in the first supported subset.
8. Whether current automatic/scheduled GitHub workflow triggers should be changed; the audit did not modify them.

## Required decisions before Phase 2

| Gate | Required owner answer | Blocks |
| --- | --- | --- |
| G1 | Approve Option B or select another architecture option. | Any app-package integration. |
| G2 | Approve identity and value/schema round-trip rules. | Adapters, wire messages, persistence references. |
| G3 | Approve tool conflict/routing and invocation lifecycle semantics. | Unified discovery/execution. |
| G4 | Approve permission/grant/policy model. | Script/third-party service exposure. |
| G5 | Classify every existing store as user data, install state, cache, secret or diagnostic; approve migrations and rollback. | Persistence changes. |
| G6 | Approve installed-package/session ownership and absolute-path boundaries. | Package installation/runtime sessions. |
| G7 | Explicitly request the desired Xcode/package verification workflow. | Claims of compilation or SDK acceptance. |

## Decision hygiene

Future updates should keep evidence and recommendations separate. If a recommendation is accepted, record it in a numbered ADR, identify affected persisted schemas and upstream files, and attach verification evidence to the exact commit that was built. A successful old workflow run must never be attributed to a newer HEAD.
