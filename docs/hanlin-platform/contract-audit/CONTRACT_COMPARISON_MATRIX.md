# Hanlin Contract Comparison Matrix

Audit snapshot: branch `codex/fix-mcp-reachable-compatibility`, HEAD `da0929110903c83e9314ccd29d14d6d8be987d1a`.

This matrix compares contracts by responsibility, not merely by similar names. It is a static audit: no compiler or runtime verification was performed.

## Evidence legend

- **C** — source-code evidence at the cited path and lines.
- **D** — repository documentation or ADR claim; not independently compiled by this audit.
- **H** — local Git-history evidence.
- **I** — inference from multiple items of static evidence.
- **R** — recommendation, not a description of current behavior.

## Audit totals

| Measure | Count | Meaning |
| --- | ---: | --- |
| Compared responsibility pairs/groups | 35 | Rows in the matrix below. |
| Exact duplicate canonical contracts | 0 | No two models are wire- and semantics-equivalent enough for direct substitution. |
| Near-duplicate responsibility groups | 18 | Rows marked **near duplicate**. |
| Missing canonical contract families | 14 | Listed after the matrix. |
| Static unused/dead candidates | 2 | Candidates only; neither is proven removable without a build/runtime check. |

## Comparison matrix

| # | Responsibility | Existing A | Existing B / platform candidate | Classification | Important semantic difference | Evidence |
| ---: | --- | --- | --- | --- | --- | --- |
| 1 | App/package manifest | `NativeAppManifest` | `HanlinAppDescriptor` | **Near duplicate** | Native manifest is a live built-in-app UI/runtime record with string IDs and no schema/API/package integrity metadata. Platform descriptor is a package-grade, versioned, localized, typed-ID contract with routes, actions, tools, capabilities, dependencies and integrity. | C: `AI_HLY/NativeAppPlatform/Core/NativeAppManifest.swift:3-53`; `Packages/HanlinPlatform/Sources/HanlinPlatformContracts/HanlinDescriptors.swift:567-870`. |
| 2 | Script manifest | Scripting `script.json` examples | `HanlinAppDescriptor` | **Near duplicate** | Reference examples describe entry, display metadata, intent input types and run contexts, but expose no declared schema version, typed package/app identity, capability list or integrity model. | C: `Reference/ScriptingCompatibility/Original/Examples/Map Snapshot/script.json:1-40`; `.../Transit Nearby/script.json:1-24`; platform lines above. |
| 3 | Executable app module | `NativeAppModule` | `HanlinAppImplementation` plus descriptor entries | Related, not duplicate | Native protocol returns `AnyView`, runtime tools and cards; it is executable behavior. Platform implementation enum is declarative (`native`, `script`, `hybrid`) and cannot execute or construct UI. | C: `AI_HLY/NativeAppPlatform/Core/NativeAppModule.swift:5-39`; `HanlinDescriptors.swift:533-565`. |
| 4 | App catalog/registry | `NativeAppRegistry` | No platform catalog contract | **Missing canonical contract** | The live singleton owns built-in module instances keyed by strings. The package defines descriptors but no catalog query, registration, conflict or lifecycle semantics. | C: `AI_HLY/NativeAppPlatform/Core/NativeAppRegistry.swift:4-64`; package source inventory. |
| 5 | Launch request | `NativeAppLaunchRequest` | No platform launch request | **Missing canonical contract** | Live request uses a fresh UUID, string app ID, presentation style and route. No stable request ID, package identity, caller, capability context or version negotiation contract exists. | C: `AI_HLY/NativeAppPlatform/Core/NativeAppPresentation.swift:9-26`; package source inventory. |
| 6 | App session | `NativeAppSession` | `HanlinSessionID` only | **Missing canonical contract** | Live session is a `@MainActor ObservableObject` with UI presentation and tracked unstructured tasks. Platform provides a typed ID but no session state, ownership, cancellation or persistence semantics. | C: `AI_HLY/NativeAppPlatform/Core/NativeAppSession.swift:5-53`; `Packages/HanlinPlatform/Sources/HanlinPlatformContracts/HanlinIdentifiers.swift:164-171`. |
| 7 | Route | `NativeAppRoute` | `HanlinRouteDescriptor` | **Near duplicate** | Native route is a concrete runtime navigation value with `[String:String]` payload and derived string ID; platform route is declarative metadata with typed ID and localized title. | C: `AI_HLY/NativeAppPlatform/Routing/NativeAppRoute.swift:3-78`; `HanlinDescriptors.swift:295-312`. |
| 8 | Action | `NativeAppAction` | `HanlinActionDescriptor` | **Near duplicate** | Native action is an invocation request with UUID, origin, risk and payload; platform action describes an action, input/output schemas and capabilities, but not an invocation. | C: `AI_HLY/NativeAppPlatform/Actions/NativeAppAction.swift:3-46`; `HanlinDescriptors.swift:314-337`. |
| 9 | Capability identity/declaration | `NativeCapabilityID` and request | `HanlinCapabilityID` and `HanlinCapabilityDeclaration` | **Near duplicate** | Native enum is closed and app-specific; its request ID is a composed string. Platform ID is extensible and typed, and its declaration records reason/constraints but no request state. | C: `AI_HLY/NativeAppPlatform/Capabilities/NativeCapabilityRequest.swift:3-76`; `HanlinIdentifiers.swift:146-153`; `HanlinDescriptors.swift:461-478`. |
| 10 | Permission request | `NativeCapabilityRequest` | No platform permission request | **Missing canonical contract** | Existing request has capability, reason and optional domain but no subject, requesting app/package version, scope, expiry, request ID or decision linkage. | C: native capability source above; package source inventory. |
| 11 | Permission decision/grant | `NativeCapabilityStatus` | `HanlinPermissionDecisionID` only | **Missing canonical contract** | Existing status is availability/not-requested/denied/unsupported, not an auditable grant/decision record. Platform supplies only a typed decision ID. | C: `NativeCapabilityRequest.swift:67-76`; `HanlinIdentifiers.swift:155-162`. |
| 12 | Capability broker/enforcement | `NativeCapabilityRegistry` | No platform broker/policy protocol | **Near duplicate** | Registry hard-codes a few statuses and does not persist, prompt, revoke or enforce. Service brokers retain it inconsistently and network execution does not check it. | C: `AI_HLY/NativeAppPlatform/Capabilities/NativeCapabilityRegistry.swift:3-27`; `.../Services/NativeAppNetworkBroker.swift:3-11`. |
| 13 | Platform services | `NativeAppPlatformServices` | No platform service interfaces | Related, implementation-only | Live struct is a `@MainActor` service bundle with concrete router/storage/network/action objects. There is no runtime-neutral, sendable service boundary in the package. | C: `AI_HLY/NativeAppPlatform/Services/NativeAppPlatformServices.swift:4-34`. |
| 14 | Tool descriptor vs executable tool | `NativeTool` | `HanlinToolDescriptor` | **Near duplicate** | Native protocol contains an executable closure and `[String:Any]` schema; platform descriptor is Codable/Sendable metadata with typed recursive schemas, capability and risk declarations, but no executor binding. | C: `AI_HLY/NativeAgentExtensions/ToolRuntime/NativeTool.swift:11-72`; `HanlinDescriptors.swift:427-459`. |
| 15 | Tool catalog entry | `NativeToolCatalogEntry` | `HanlinToolDescriptor` | **Near duplicate** | Catalog entry is UI/settings metadata and is not a portable descriptor. Platform descriptor owns identity, input/output schemas and capability/risk semantics. | C: `AI_HLY/NativeAgentExtensions/ToolCatalog/NativeToolCatalogEntry.swift:8-53`; platform lines above. |
| 16 | MCP tool descriptor | `MCPToolDescriptor` | `HanlinToolDescriptor` | **Near duplicate** | MCP descriptor identifies server and stores input schema as JSON `Data`; it lacks owner app/package, output schema, capability, risk and presentation semantics. | C: `AI_HLY/Downstream/MCP/ToolIntegration/MCPToolDescriptor.swift:3-25`; platform lines above. |
| 17 | Tool catalogs | `NativeToolCatalog` and `MCPToolCatalog` | No unified platform catalog | **Near duplicate** | Native catalog is `@MainActor`, settings-aware and executable; MCP catalog is an actor with live/last-known remote descriptors. `AssistantToolBridge` concatenates schemas at request time; it does not establish one canonical registry. | C: `AI_HLY/NativeAgentExtensions/ToolCatalog/NativeToolCatalog.swift:10-322`; `AI_HLY/Downstream/MCP/ToolIntegration/MCPToolCatalog.swift:3-50`; `.../AssistantToolBridge.swift:3-32`. |
| 18 | Tool invocation/result | `AgentToolCall`, `NativeToolResult`, MCP call result | No platform invocation/result | **Near duplicate** | Three runtime-specific representations carry different argument/result shapes and lifecycle detail. No stable request ID, typed value/schema validation, cancellation and error/result envelope spans them. | C: `AI_HLY/Downstream/AgentActivity/AgentEvent.swift:53-86`; `AI_HLY/NativeAgentExtensions/ToolRuntime/NativeToolResult.swift:8-26`; MCP client call path `AI_HLY/Downstream/MCP/Runtime/MCPClientSession.swift:80-113`. |
| 19 | Tool result presentation | `NativeUIBlock` | Tool presentation fields in `HanlinToolDescriptor` | **Near duplicate** | `NativeUIBlock` is a recursive, persisted UI payload with action IDs; platform presentation is descriptor metadata, not a portable result-rendering contract. | C: `AI_HLY/NativeAgentExtensions/UI/NativeUIBlock.swift:109-165`; `HanlinDescriptors.swift:427-459`. |
| 20 | General value | `RuntimeJSONValue` | `HanlinValue` | **Near duplicate** | Runtime value collapses integers into doubles and has no binary data case or explicit finite-number/canonical encoding rules. Platform value distinguishes integer/number/data and supplies deterministic canonical JSON. | C: `AI_HLY/Downstream/RuntimeCore/Core/RuntimeModels.swift:121-151`; `Packages/HanlinPlatform/Sources/HanlinPlatformContracts/HanlinValue.swift:3-115`. |
| 21 | Tool schema | `NativeToolSchema` | `HanlinJSONSchema` | **Near duplicate** | Native schema is an untyped `[String:Any]` builder for OpenAI-style JSON; platform schema is recursive Codable/Sendable validation data, but its tagged encoding is not itself standard JSON Schema wire format. | C: `NativeTool.swift:36-72`; `HanlinValue.swift:117-370`. |
| 22 | MCP schema | MCP SDK `Value` / encoded JSON `Data` | `HanlinJSONSchema` | **Near duplicate** | MCP preserves arbitrary schema JSON for transport. Platform schema has a narrower modeled vocabulary and requires an explicit lossless conversion policy before replacing MCP storage. | C: `MCPToolDescriptor.swift:3-25`; platform schema lines above. |
| 23 | Platform/runtime errors | `RuntimeCoreError` | `HanlinPlatformError` | **Near duplicate** | Runtime error is implementation-focused and localized; platform error is a stable coded payload with details. No formal mapping/versioning contract connects them. | C: `RuntimeModels.swift:153-189`; `Packages/HanlinPlatform/Sources/HanlinPlatformContracts/HanlinContractError.swift:40-75`. |
| 24 | Platform/MCP errors | `MCPError` | `HanlinPlatformError` | **Near duplicate** | MCP error is a Swift localized enum and not a Codable wire contract. Platform error can cross boundaries but lacks an approved MCP error mapping. | C: `AI_HLY/Downstream/MCP/Core/MCPError.swift:3-49`; platform error lines above. |
| 25 | Identity | String/UUID IDs across NativeApp/MCP/Runtime | `Hanlin*ID` wrappers | **Near duplicate** | Live systems use unrelated string and UUID identity domains. Platform wrappers prevent accidental cross-domain mixing, but no migration/adapter policy exists and the package is not linked to the app. | C: `HanlinIdentifiers.swift:92-216`; native/MCP/runtime models cited elsewhere. |
| 26 | Versioning | Native/MCP version strings and schema integers | `HanlinAPIVersion`, `HanlinManifestVersion`, `HanlinWireVersion`, `HanlinPackageVersion`, host range | **Near duplicate** | Existing versions are subsystem-local and partly free-form. Platform models formalize compatibility, but current stores and runtime do not negotiate them. | C: `Packages/HanlinPlatform/Sources/HanlinPlatformContracts/HanlinVersions.swift:79-424`; `MCPServerRegistryStore.swift:3-27`; native manifest source. |
| 27 | Installed package/server record | `MCPServerDescriptor` | No platform installed-package/provider record | **Near duplicate** | Descriptor mixes durable package identity, user enablement, compatibility, absolute install paths and cached runtime metadata. Platform has package/app IDs but no installed-instance record. | C: `AI_HLY/Downstream/MCP/Core/MCPServerDescriptor.swift:18-152`. |
| 28 | Script/runtime request | `RuntimeExecutionRequest` | `HanlinScriptEnvelope` | Related, not duplicate | Runtime request contains source, arguments, workspace URL, environment and limits. Envelope defines session/sequence/request/message framing but not execution semantics. | C: `RuntimeModels.swift:84-107`; `Packages/HanlinPlatform/Sources/HanlinPlatformContracts/HanlinWireProtocol.swift:23-95`. |
| 29 | Script/runtime result | `RuntimeExecutionResult` | No platform execution result | **Missing canonical contract** | Runtime result has stdout/stderr/exit code/duration/value. The platform envelope can carry payload but defines no typed result, stream, diagnostics or resource-accounting model. | C: `RuntimeModels.swift:109-119`; wire protocol above. |
| 30 | Activity/run | `AgentRun` | No platform run/activity contract | **Missing canonical contract** | `AgentRun` is a persisted UI/product transcript aggregate at schema version 4. No runtime-neutral tool/script activity and audit event contract exists. | C: `AI_HLY/Downstream/AgentActivity/AgentActivityModels.swift:185-264`. |
| 31 | Lifecycle/events | MCP/runtime state, `AgentEvent`, Scripting lifecycle callbacks | `HanlinScriptMessageKind` | **Near duplicate** | Existing lifecycle models describe different layers: process/server, agent UI activity and Script app callbacks. Platform message kinds frame transport but do not define a unified state machine. | C: `MCPServerRuntimeState.swift:3-36`; `AgentEvent.swift:111-132`; `Reference/ScriptingCompatibility/Original/Types/scripting.d.ts:11521-11635`; `HanlinWireProtocol.swift:3-21`. |
| 32 | Storage | Native UserDefaults brokers/stores and Scripting Storage/FileSystem | No platform storage service contract | **Missing canonical contract** | Current stores use product-specific key prefixes/JSON. Scripting declares a much broader API. There is no namespaced quota, durability, migration, transaction or capability contract. | C: `AI_HLY/NativeAppPlatform/Services/NativeAppStorageBroker.swift:3-36`; Scripting declarations/reference inventory. |
| 33 | Network | `NativeAppNetworkBroker`, runtime/MCP transports, Scripting fetch | No platform network service contract | **Missing canonical contract** | Current native broker directly uses `URLSession.shared` and does not enforce declared domains. Other subsystems own separate transport policy. | C: `NativeAppNetworkBroker.swift:3-11`; Scripting declarations/reference inventory. |
| 34 | Persistence schema/migration | MCP registry schema, AgentRun schema, ad-hoc stores | No common persistence contract | **Near duplicate** | Several stores version themselves, while others do not. There is no common record envelope, migration registry, recovery policy, ownership or compatibility promise. | C: `MCPServerRegistryStore.swift:3-185`; `AgentActivityModels.swift:185-264`; `MCPChatSelectionStore.swift:3-58`. |
| 35 | Scripting permissions and app contexts | `ScriptingApi`, `Script.env`, permission functions | Platform capability declarations only | **Missing canonical contract** | Reference surface names API permissions and many execution contexts; generated compatibility data marks all as unimplemented. Platform does not yet model context-specific grants or host-service availability. | C: `Reference/ScriptingCompatibility/Original/Types/scripting.d.ts:11339-11670`; `Reference/ScriptingCompatibility/Generated/compatibility-matrix.json`; platform capability source. |

## The 18 near-duplicate groups

Rows **1, 2, 7, 8, 9, 12, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 25, and 26** are counted as near duplicates. The remaining related models are either different layers, missing-platform counterparts, or persistence/lifecycle aggregations that should not be merged merely because fields overlap.

No exact duplicate was found. In particular, `RuntimeJSONValue` must not be type-aliased to `HanlinValue`, and MCP input schema JSON must not be decoded into `HanlinJSONSchema`, until lossless conversion behavior is specified and tested.

## Fourteen missing canonical contract families

1. App/package catalog and registration/query result.
2. Canonical launch request and launch rejection/result.
3. App session state/lifecycle/cancellation contract.
4. Runtime session/process identity and ownership contract.
5. Permission request with subject, scope and purpose.
6. Permission decision/grant with expiry and provenance.
7. Permission revocation and effective-grant query.
8. Policy decision/enforcement result.
9. Runtime-neutral platform service interfaces (storage, network, navigation, clipboard, files and events).
10. Installed package/provider instance record separated from runtime paths and user settings.
11. Unified tool invocation/result/progress/cancellation contract.
12. Script execution request/result/stream contract.
13. Common persistence envelope, schema ownership and migration/recovery contract.
14. Stable audit/activity event contract.

## Static unused/dead candidates

| Candidate | Evidence | Classification |
| --- | --- | --- |
| `NativeChatCardProvider` and the three `chatCards(context:)` producers | Definitions/producers occur in `NativeAppModule.swift:17-39` and the three built-in module/provider files; repository-wide Swift token search found no caller that reads the returned providers. | **Compiled, apparently unreachable contract path.** Confirm with Xcode index/build and product intent before removal. |
| `MCPInstalledPackageManifest` | Only declaration occurrence found at `AI_HLY/Downstream/MCP/Persistence/MCPInstalledPackageManifest.swift:3-12`. | **Compiled, no token consumer found.** It may be a reserved migration boundary; do not delete during platform convergence without owner decision. |

The lexical inventory contains many additional declarations with one token occurrence. They are not counted here because private/nested Swift declarations, protocol conformances, SwiftUI discovery and reflection-like framework behavior make occurrence count alone too weak to call them dead.

## Compatibility candidates that must remain temporarily

These are not canonical platform contracts, but deleting or rewriting them before an adapter and migration decision would risk user data or current behavior:

- `MCPServerRegistryDocument` / `MCPServerRegistryStore`: current schema-1 primary/backup persistence, legacy schema-0 decode and repair behavior protect existing MCP installations. Preserve until install ownership and migration policy are decided (`MCPServerRegistryStore.swift:3-185`).
- `NativeAppManifest`, `NativeAppModule`, `NativeAppRegistry`, `NativeAppLaunchRequest`, `NativeAppSession`, `NativeAppRoute` and `NativeAppAction`: they are the live built-in-app runtime/UI surface. Platform descriptors are package-only and cannot replace executable behavior.
- `NativeTool`, `NativeToolCatalog`, `NativeToolCatalogEntry`, `NativeToolResult` and `NativeUIBlock`: they power live assistant execution, settings and persisted UI rendering. A descriptor-only replacement would lose closures and presentation behavior.
- `MCPToolDescriptor`, `MCPToolCatalog` and `AssistantToolBridge`: they preserve remote-server identity, live tool-list changes and execution routing that `HanlinToolDescriptor` does not implement.
- `RuntimeJSONValue`, `RuntimeExecutionRequest` and `RuntimeExecutionResult`: these are active embedded-runtime implementation boundaries; conversion to platform value/wire types is neither proven lossless nor wired.
- `AgentRun`, `AgentToolCall`, `AgentEvent`, transcript/evidence and `ChatMessages` JSON fields: they preserve existing history and UI semantics. A common audit contract must be additive and versioned before migration.

## Conclusion

The duplication problem is primarily **semantic overlap without a shared boundary**, not byte-for-byte duplicate types. The safe convergence unit is an adapter-backed responsibility (identity, value, schema, tool invocation, permission, session), not a broad rename or direct model replacement.
