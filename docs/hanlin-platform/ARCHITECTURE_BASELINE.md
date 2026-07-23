# Hanlin architecture baseline

Status: Phase 0 executable design baseline
Execution contract: `HANLIN_DUAL_PLATFORM_MASTER_EXECUTION_SPEC.md`, Revision
2.0, SHA-256
`5f294604af45cb2143314e0c26500856972be34544daf0691344c083e3af0b0a`

## Product boundary

Hanlin is one host platform with two first-class application surfaces:

1. compiled Swift/SwiftUI modules;
2. dynamically installed TypeScript/TSX packages.

Both surfaces must use one platform kernel for identity, manifests,
capabilities, permissions, storage, files, secrets, network, routing, actions,
tools, diagnostics, policy, and extension-safe shared state. Runtime engines
remain below that kernel and do not become general service locators.

## Verified current baseline

The current checkout has one iPhone/iPad application target,
`AI_Hanlin`, and one shared scheme, `AI_HLY`. Project settings select iOS 26.0,
Swift language mode 6.0, approachable concurrency, and device families 1 and 2.
The project contains an empty ExtensionKit embedding phase but no extension
target.

Current foundations:

- `AI_HLY/Downstream/RuntimeCore` owns Node, TypeScript, Python,
  JavaScriptCore, shell execution, package mechanics, lifecycle, and
  diagnostics. `AppRuntimeCore` is an actor and currently exposes a shared
  instance for engine coordination.
- `AI_HLY/NativeAppPlatform` owns the current native module, manifest,
  registry, session, Apps Hub, routing, basic services, and capability seed.
- `AI_HLY/NativeAgentExtensions` owns native tools and compact
  `NativeUIBlock` chat result presentation.
- `AI_HLY/Downstream/AgentActivity` owns provider-neutral activity, evidence,
  transcript, and result presentation.
- `AI_HLY/Downstream/MCP` owns MCP installation, compatibility, runtime,
  sessions, persistence, tools, and UI.
- `AI_HLY/AI_HLY.swift` prepares RuntimeCore and launches current mini apps
  through a separate `WindowGroup`.

Known boundaries that must be preserved:

- RuntimeCore remains an execution-engine layer.
- MCP remains the MCP protocol/provider implementation.
- `NativeUIBlock` remains compact tool-result UI, not ScriptUI.
- AgentActivity remains chat execution/evidence presentation.
- Existing native apps migrate through adapters before replacement.

## Target package boundaries

Phase 1 creates a local `Packages/HanlinPlatform` package with focused targets:

```text
HanlinPlatformContracts
    -> Foundation where needed

HanlinPlatformServices
    -> Contracts + public Apple frameworks

HanlinNativeSDK
    -> Contracts + service protocols

HanlinScriptContracts
    -> Contracts

HanlinScriptRuntime
    -> ScriptContracts + abstract engine/compiler protocols

HanlinScriptUI
    -> ScriptContracts + SwiftUI

HanlinAppCatalog
    -> Contracts + NativeSDK + ScriptContracts

HanlinTooling
    -> Contracts

AI_HLY/Downstream/HanlinIntegration
    -> app-specific adapters to existing systems
```

The package must not import AI_HLY model types. SwiftData, chat, RuntimeCore,
MCP, current native apps, and current tools connect through downstream
adapters.

## Runtime trust boundary

Two trust profiles are architectural:

- `sandboxedApplication`: dedicated JavaScriptCore isolation, no Node globals,
  filesystem, network, native modules, or process API; only capability-checked
  versioned RPC.
- `trustedDeveloperNode`: existing MCP, controlled build tooling, and
  explicitly trusted developer execution; visibly not a hostile-code sandbox.

Compilation is trusted host work and is distinct from application execution.

## Authorized Scripting baseline

Phase 0 imported the canonical root-level Scripting declarations,
documentation, examples, and compiler metadata into
`Reference/ScriptingCompatibility`.

- Baseline ID: `scripting-compat-2026-07-22-8d7d33d9369e`
- Aggregate SHA-256:
  `8d7d33d9369ee555d15adf10c867abbfb85834eced7e7596a627b70ff627ff36`
- Imported files: 999
- Original documentation: 942 files
- Original declarations: 5 files
- Indexed fixtures: 177

`Original/` is immutable. Generated indexes and Hanlin overlays are separate.
The original `scripting` declaration module remains the compile-time source of
truth. A separate `hanlin` module will contain Hanlin-owned extensions.
Declaration presence never implies runtime support.

## Persistence and versioning invariants

- Public identifiers and persisted contracts are strongly typed and versioned.
- Public wire boundaries use a Codable value model, never `[String: Any]`.
- Unknown optional fields are tolerated where safe; unsupported required
  capabilities and major versions fail explicitly.
- Every service operation declares capability, risk, origins, contexts,
  cancellation, interaction, entitlement, and redaction metadata.
- Package updates that expand capabilities invalidate affected grants.

## Distribution and extension constraints

Distribution mode is policy, not UI decoration. The default production policy
is conservative. Dynamic scripts cannot manufacture arbitrary compiled Swift
App Intent types. Extensions are separate constrained processes and must use an
extension-safe runtime and App Group artifacts added only in their gated phase.

## Verification status

This document is verified from repository files and the authorized local
source tree. No Apple documentation page was consulted in Phase 0. No Xcode
SDK/compiler build, GitHub Actions workflow, app launch, simulator test, or
device test was run. Apple API declarations and availability remain subject to
explicit later SDK verification.
