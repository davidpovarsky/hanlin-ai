# Current Type Disposition

Status: proposed disposition at audited HEAD
`a5cea34dc60038c860b4148ee934111f3fac59bd`. No deletion, migration, or source
change is authorized.

## 1. Categories

- **CANONICAL** — the responsibility belongs in `HanlinPlatformContracts` and
  the current type is the basis of the canonical type. Fields/encoding may still
  evolve as specified; this is not an API freeze.
- **RUNTIME_ONLY** — valid implementation, UI, SDK, store, or reference type
  that does not cross as canonical domain authority.
- **TEMPORARY_ADAPTER_BOUNDARY** — current live type must be translated during
  cutover and must not become a permanent second model.
- **REPLACE_AFTER_CUTOVER** — current responsibility is superseded by the
  canonical model; retain until consumers and behavior migrate.
- **DELETE_CANDIDATE** — no proven current consumer or redundant adapter role;
  deletion still requires the stated evidence and verification.
- **PERSISTED_LEGACY_BOUNDARY** — current type/encoding protects concrete
  persisted data and keeps a reader/migration responsibility.

Each named type below receives one category. Types are grouped only when they
share the same category, responsibility, and deletion condition. SwiftUI view
types with no contract, persistence, execution, or integration responsibility
are out of scope. The complete lexical declaration list remains in
`../contract-audit/CONTRACT_INVENTORY.md`; lexical occurrence counts are not used
as deletion proof.

## 2. HanlinPlatformContracts

| Current type(s) | Category | Decision and exact retirement condition |
| --- | --- | --- |
| `HanlinStringIdentifier`, `HanlinAppID`, `HanlinPackageID`, `HanlinModuleID`, `HanlinRouteID`, `HanlinActionID`, `HanlinToolID`, `HanlinCapabilityID`, `HanlinRequestID`, `HanlinMCPServerID`, `HanlinPublisherID`, `HanlinCallbackID`, `HanlinObjectHandleID` | CANONICAL | Keep the typed-ID responsibility and current grammar unless cross-language fixtures require a versioned refinement. Add missing specific IDs. No retirement planned. |
| `HanlinPermissionDecisionID` | CANONICAL | Keep and supplement with permission request, grant, revocation, and policy-evaluation IDs. |
| `HanlinSessionID` | REPLACE_AFTER_CUTOVER | Replace with distinct app/runtime session IDs. Delete only when wire/session records and every adapter use the specific types and no persisted/external payload uses the generic ID. |
| `HanlinMajorMinorVersion`, `HanlinAPIVersion`, `HanlinManifestVersion`, `HanlinWireProtocolVersion`, `HanlinPackageVersion`, `HanlinHostVersionRange`, `HanlinVersionSupport` | CANONICAL | Keep responsibility; evolve negotiation semantics and tests. No direct replacement planned. |
| `HanlinValue` | CANONICAL | Keep rich value responsibility; evolve exact numeric/data encoding in the next major format. Old fixture reader can be omitted only after rechecking that no external/persisted consumer exists. |
| `HanlinJSONSchema` | REPLACE_AFTER_CUTOVER | Split into `HanlinValueSchema` and lossless `HanlinJSONSchemaDocument`. Delete after all manifests/descriptors/adapters/fixtures migrate and any real old encoded manifests are migrated or explicitly reset. |
| `LocalizedValue`, `HanlinExecutionOrigin`, `HanlinRiskLevel`, `HanlinExecutionContext`, `HanlinDistributionMode` | CANONICAL | Retain portable semantics; additions are versioned. |
| `HanlinAppImplementation`, `HanlinIconDescriptor`, `HanlinAppearanceDescriptor`, `HanlinPreferredColorScheme`, `HanlinAppCategory`, `HanlinEntryPointKind`, `HanlinEntryPointDescriptor` | CANONICAL | Retain descriptor responsibility; implementation variants remain declarative, never executable. |
| `HanlinRouteDescriptor`, `HanlinActionDescriptor` | CANONICAL | Retain descriptors; add separate request/result types rather than overloading them. |
| `HanlinToolOwner` | REPLACE_AFTER_CUTOVER | Replace with provider-qualified logical owner/instance identity. Delete when every tool descriptor/catalog/invocation and manifest fixture uses the new owner identity. |
| `HanlinToolPresentationDescriptor`, `HanlinToolCompactStyle` | CANONICAL | Keep only portable hints; app-specific renderer/profile stays runtime-only. |
| `HanlinToolDescriptor` | CANONICAL | Evolve with logical identity, revision, lossless schema, availability, progress/cancellation. Current responsibility remains canonical. |
| `HanlinCapabilityDeclaration` | CANONICAL | Evolve scope schema/purpose; explicitly non-authorizing. |
| `HanlinDependencyDeclaration`, `HanlinExtensionDeclaration`, `HanlinAuthor`, `HanlinDistributionDeclaration`, `HanlinIntegrityAlgorithm`, `HanlinIntegrityDeclaration` | CANONICAL | Retain package/app declaration responsibilities. |
| `HanlinAppDescriptor` | CANONICAL | Evolve and split package-level distribution/integrity into `HanlinPackageDescriptor`; app portion remains canonical. Current shape is not frozen. |
| `HanlinManifestIssueCode`, `HanlinManifestIssue`, `HanlinManifestSchema`, `HanlinContractError` | CANONICAL | Retain contract validation role; update findings for split schemas/types. `HanlinContractError` stays local API error rather than cross-wire error. |
| `HanlinErrorCode`, `HanlinPlatformError` | CANONICAL | Evolve safe localization, retry/cause/correlation fields; remain stable wire/domain error. |
| `HanlinScriptMessageKind`, `HanlinScriptEnvelope` | TEMPORARY_ADAPTER_BOUNDARY | Generalize into typed negotiated `HanlinWireEnvelope`. Delete script-only envelope after every kind has a typed payload and version/order/cancel/limit cross-language tests pass; retain a decoder only if real persisted/external messages exist. |

## 3. NativeAppPlatform

| Current type(s) | Category | Decision and exact retirement condition |
| --- | --- | --- |
| `NativeAppManifest`, `NativeAppAppearance`, `NativeAppCategory`, `NativeAppEntryPointKind` | TEMPORARY_ADAPTER_BOUNDARY | Map live built-in metadata to validated canonical descriptors. Delete/replace after all built-ins have catalog/search/settings/localization/launch parity and canonical descriptors are authoritative. |
| `NativePresentationMode` | RUNTIME_ONLY | Host presentation implementation enum; may remain if still useful after canonical presentation intent mapping. |
| `NativeAppModule` | RUNTIME_ONLY | Permanent native executable/module binding: SwiftUI view construction, tools, cards, capabilities. It may evolve but is not a portable descriptor. |
| `NativeChatCardProvider` | DELETE_CANDIDATE | Delete only after semantic call-site review, compiler/Xcode verification, and product confirmation that no dynamic/protocol consumer or planned extension point uses `chatCards(context:)`. Lexical absence alone is insufficient. |
| `NativeAppRegistry` | TEMPORARY_ADAPTER_BOUNDARY | Keep as native executable registry while canonical catalog is shadowed. Replace cross-subsystem lookup after canonical catalog/module binding parity; exact type may remain provider-private only if it no longer owns canonical metadata. |
| `NativeAppLaunchRequest` | TEMPORARY_ADAPTER_BOUNDARY | Map canonical launch request/result to WindowGroup/in-app presentation. Delete after every launch path is canonical and Codable WindowGroup restoration/presentation parity is verified. |
| `NativeAppPresentationStyle` | RUNTIME_ONLY | Host mapping target for canonical presentation intent; keep if native host still needs it. |
| `NativeAppSession` | REPLACE_AFTER_CUTOVER | Transfer live ownership to host session controller with canonical snapshots/events. Delete after tracked task, close, UI observation, environment injection, and window dismissal tests pass. |
| `NativeAppContext`, `NativeOpenURLAction`, `NativeAppPlatformServices` | RUNTIME_ONLY | Native dependency/UI context; never crosses portable boundary. Keep composition role, but services must enforce canonical permissions. |
| `NativeAppRoute`, `NativeAppRoutePayload` | PERSISTED_LEGACY_BOUNDARY | Embedded in Codable native UI actions. Retain versioned reader/adapter until historical `NativeUIBlock` records migrate or retention expires; stop new writes before reader retirement. |
| `NativeAppRouter` | RUNTIME_ONLY | Host routing implementation; consume canonical requests eventually. |
| `NativeAppAction`, `NativeAppActionOrigin`, `NativeAppActionRisk`, `NativeAppActionKind`, `NativeAppActionResult` | PERSISTED_LEGACY_BOUNDARY | Action/route payloads persist through NativeUI. Stop legacy writes after canonical action cutover; retain reader/migration and delete only when historical data is covered. |
| `NativeAppActionBus` | TEMPORARY_ADAPTER_BOUNDARY | Host executor/facade. Replace input/result with canonical action/policy contracts; delete old facade only after no caller bypasses canonical enforcement. Concrete service execution may remain behind a new facade. |
| `NativeCapabilityID` | TEMPORARY_ADAPTER_BOUNDARY | Map closed native IDs to registered canonical capability IDs; delete after all built-in declarations/services use canonical IDs. |
| `NativeCapabilityRequest` | TEMPORARY_ADAPTER_BOUNDARY | Treat current value as declaration-shaped input, never a grant. Delete after all modules declare canonical capability scopes/purposes. |
| `NativeCapabilityStatus` | REPLACE_AFTER_CUTOVER | Replace with request/decision/grant/effective permission. Delete after no UI/service interprets `.available` as authorization and status UI uses canonical effective state. |
| `NativeCapabilityRegistry` | REPLACE_AFTER_CUTOVER | Replace with canonical definition registry/permission broker implementation. Delete after all privileged gateways enforce canonical policy and bypass tests pass. |
| `NativeAppNetworkBroker`, `NativeAppPasteboardBroker`, `NativeAppOpenURLBroker`, `NativeAppStorageBroker` | RUNTIME_ONLY | Host service implementations/facades. Retain but require canonical request/effective-permission enforcement; replace only unguarded APIs once no bypass exists. |
| `NativeAppJSON`, built-in clients/services/import/export/index types | RUNTIME_ONLY | Native implementation helpers and app domain behavior, not canonical platform contracts. |
| `NativeAppSefariaStore`, `NativeAppWikipediaStore`, `NativeAppTextStudioStore` | PERSISTED_LEGACY_BOUNDARY | Protect saved sources/articles, recents/preferences, draft/history. Retire only after transactional namespace/schema migration, verification, rollback window, and no legacy reads. |
| `NativeAppSefariaLanguage`, `NativeAppSefariaSearchResult`, `NativeAppSefariaNameResolution`, `NativeAppSefariaNameCompletion`, `NativeAppSefariaSource` | RUNTIME_ONLY | Built-in app domain types. Codable instances referenced by legacy store remain covered by the store's persisted boundary; they do not become platform canonical. |
| `NativeAppWikipediaLanguage`, `NativeAppWikipediaSearchResult`, `NativeAppWikipediaSummary` | RUNTIME_ONLY | Same: built-in domain types; preserve decoders while legacy saved data exists. |
| `NativeAppTextStudioTransform`, `NativeAppTextStudioWordFrequency`, `NativeAppTextStudioAnalysis`, `NativeAppTextStudioHistoryItem` | RUNTIME_ONLY | Same: built-in domain types; preserve history decoder while legacy store exists. |

## 4. NativeAgentExtensions and tool presentation

| Current type(s) | Category | Decision and exact retirement condition |
| --- | --- | --- |
| `NativeTool` | RUNTIME_ONLY | Native executable provider protocol with closure/actor/UI concerns. It may later accept canonical request/result but never becomes portable metadata. |
| `NativeToolExecutionContext` | RUNTIME_ONLY | Native execution dependency context; canonical caller/session/permission metadata is adapted into it during cutover. |
| `NativeToolSchema` | REPLACE_AFTER_CUTOVER | Untyped OpenAI schema builder. Delete after every native tool has a lossless canonical schema and provider projection; no authoritative `[String: Any]` schema remains. |
| `NativeToolResult` | TEMPORARY_ADAPTER_BOUNDARY | Map existing model/user/UI result into canonical result/content. Delete/replace after every native tool returns canonical outcome and presentation parity passes. |
| `NativeToolCatalogEntry` | REPLACE_AFTER_CUTOVER | Split portable descriptor from settings/UI metadata. Delete after canonical catalog plus provider-private settings/presentation model covers all consumers and preferences migrate. |
| `NativeAssistantToolGroup` | RUNTIME_ONLY | Settings/UI grouping projection; derive from canonical catalog but may remain UI-only. |
| `NativeToolCatalog` | TEMPORARY_ADAPTER_BOUNDARY | Live native executable/settings registry. Retain provider registry during cutover; remove canonical metadata/routing authority after composed catalog parity. Delete exact type only if a provider registry replacement owns all executable lookup/settings. |
| private `NativeToolEnabledStore` | PERSISTED_LEGACY_BOUNDARY | Preserve tool/group settings and prior name migration. Retire after provider-qualified key migration, rollback/support window, and zero old reads. |
| `NativeToolBridge`, `AssistantToolBridge`, `MCPToolBridge` | TEMPORARY_ADAPTER_BOUNDARY | Existing integration/routing bridge. Replace with captured canonical routing/execution. Delete after APIManager and every model request/call path use canonical router with parity. |
| `NativeToolJSON` | RUNTIME_ONLY | Provider parsing helper; remove only if no native implementation needs legacy JSON strings. |
| `NativeUIBlockType`, `NativeUIExpandedPresentation`, `NativeUIActionType`, `NativeUIAction`, `NativeUIListItem`, `NativeUIKeyValue`, `NativeUIBlock` | PERSISTED_LEGACY_BOUNDARY | Persisted chat presentation schema. Stop new legacy writes after canonical content/projection cutover; keep decoder/migration until supported history is migrated or retention approved. |
| `NativeUIPresentationMode`, `NativeUIExpandedPayload`, render/card/style SwiftUI types | RUNTIME_ONLY | UI projection/rendering only. May continue rendering legacy and canonical projections. |
| `ToolActivityPresentationKind`, `ToolActivityPresentationDescriptor`, `ToolResultRendererKind`, `ToolResultPresentationDescriptor`, `ToolResultDisplayPolicy`, `ToolResultPresentationRequest`, `ToolPresentationProfile` | PERSISTED_LEGACY_BOUNDARY | Profiles persist in AgentRun schema 4. Retain readers; future portable hints are separate. Delete old encoding only with activity migration/retention approval. |
| `ToolInvocationMetadata`, `ToolInvocationExtractionResult`, `ToolInvocationMetadataExtractor`, `ToolSchemaDecorator`, `ToolProgressSummary`, `ProgressSummarySanitizer` | RUNTIME_ONLY | Model/provider presentation metadata implementation. Canonical invocation arguments must exclude provider-control metadata through a documented projection; types may remain UI/model-loop helpers. |
| `ToolResultSuppressionReason`, `ToolResultPresentationDecision`, `ToolResultPresentationCoordinator` | PERSISTED_LEGACY_BOUNDARY | Decision fields persist in diagnostics/activity. Retain decoding while records live; current coordinator remains UI runtime-only in behavior. |
| `LegacyToolPresentationAdapter`, `ToolPresentationProfileRegistry` | TEMPORARY_ADAPTER_BOUNDARY | Remove after every live tool/provider supplies canonical presentation metadata and schema-4 legacy histories still render through a read-only decoder. |
| `NativeToolTraceLogger`, private `TraceRecord` | RUNTIME_ONLY | Diagnostic implementation/schema, not canonical audit. Rotate/reset rather than migrate; retain only per diagnostic policy. |

## 5. MCP

| Current type(s) | Category | Decision and exact retirement condition |
| --- | --- | --- |
| `MCPServerDescriptor`, `MCPEnvironmentVariable`, `MCPEntryPointOption`, `MCPServerRegistryDocument` | PERSISTED_LEGACY_BOUNDARY | Current schema-0/1 registry mixes installed/config/path/cache. Retain reader and rollback bytes until split-store migration verifies every server, secret reference, package path, setting, and support window. Stop old writes before deletion. |
| `MCPServerRegistryStore`, `MCPServerRegistryError` | TEMPORARY_ADAPTER_BOUNDARY | Store/repair implementation remains authoritative through migration. Retire old writer after canonical store commit; retire reader after zero legacy reads and rollback closure. |
| `MCPInstalledPackageManifest` | DELETE_CANDIDATE | Delete only after semantic call-site/format review plus compiler/Xcode verification confirms it is neither written nor reserved by installer/host, and canonical installed package record covers its intended fields. |
| `MCPServerConfiguration` | RUNTIME_ONLY | Resolved paths/environment/secret values are provider runtime configuration and never portable. |
| `MCPCompatibilityVerdict`, `MCPCompatibilityFinding`, nested `Severity`, `MCPModuleAccess`, `MCPModuleEdge`, `MCPCompatibilityReport` | RUNTIME_ONLY | MCP install/runtime diagnostics/cache. Recompute after canonical installed migration; do not make canonical authorization. |
| `MCPServerRuntimeState`, `MCPServerFailureKind`, `MCPServerFailure`, `MCPServerStatus`, `MCPNodeRuntimeState`, `MCPRuntimeSnapshot`, `MCPPersistentLoadState` | RUNTIME_ONLY | Provider/UI runtime snapshots. Adapt to canonical runtime state at cross-subsystem boundary; implementation remains. |
| `MCPError`, `MCPServerPathResolutionError` | RUNTIME_ONLY | Map to canonical stable errors at boundary; retain subsystem diagnostics. `MCPServerRegistryError` is classified with its temporary store boundary above. |
| `MCPFeatureConfiguration` | PERSISTED_LEGACY_BOUNDARY | Preserve enabled/debug config; migrate to versioned configuration. Old decoder retires after verified switch/rollback window. |
| `MCPFeatureConfigurationStore` | RUNTIME_ONLY | Store implementation; may be replaced by canonical configuration store but never a portable contract. |
| `MCPChatSelection` | PERSISTED_LEGACY_BOUNDARY | Preserve chat/server association. Retire after versioned mapping to provider-instance IDs and support/rollback window. |
| `MCPChatSelectionStore` | TEMPORARY_ADAPTER_BOUNDARY | Current actor/file writer. Stop old writes after migration; retain legacy reader through support window. Temporary in-memory selections remain runtime state. |
| `MCPSecretStore` | RUNTIME_ONLY | Credential implementation. Preserve Keychain values/references; may be unified behind canonical credential service without exposing secrets. |
| `MCPFileLayout`, `MCPResolvedServerPaths`, `MCPServerPathDiagnostics`, `MCPServerPathResolver` | RUNTIME_ONLY | Local path/repair implementation. Retain legacy path migration until registry split; never enter portable descriptors. |
| `MCPPackageSource`, `MCPPackageSpec`, `MCPPackageManifestPreview`, `MCPPackageInstallation`, `MCPPackageInstallService` | RUNTIME_ONLY | MCP installer inputs/transaction implementation. Future canonical install request/result adapts to them. |
| `MCPInstallPhase`, `MCPInstallState`, `MCPInstallTerminalError`, `MCPInstallProgress`, `MCPInstallProgressResponse` | TEMPORARY_ADAPTER_BOUNDARY | Map install lifecycle/progress/error to canonical operation contracts. Replace boundary types after installer directly publishes canonical state; UI may keep provider projections. |
| `MCPToolDescriptor` | TEMPORARY_ADAPTER_BOUNDARY | Preserve server/original/exposed name and raw schema while mapping to logical identity/lossless schema. Delete after canonical provider descriptors are authoritative and no cached/current consumer needs this shape. |
| `MCPToolCatalog` | RUNTIME_ONLY | Provider discovery registry actor; may remain behind canonical composed catalog. It must not own global identity/routing. |
| `MCPToolNameCodec` | TEMPORARY_ADAPTER_BOUNDARY | Preserve observable `mcp__` alias behavior during cutover. Retain as provider alias projector or delete only when a canonical deterministic implementation passes exact golden tests. |
| `MCPServerResolutionFailure`, `MCPToolResolutionResult` | TEMPORARY_ADAPTER_BOUNDARY | Map to canonical catalog findings/snapshot. Delete after resolution publishes canonical results directly. |
| `AssistantToolRequestScope` | REPLACE_AFTER_CUTOVER | Replace with immutable canonical routing table/request scope. Delete after all model requests capture exact logical routes and server-selection configuration has migrated. |
| `MCPToolCallOutput` | TEMPORARY_ADAPTER_BOUNDARY | Map MCP SDK content/`isError` to canonical outcome/content. Delete after MCP executor returns canonical result directly. |
| `MCPClientSession`, `EmbeddedNodeMCPTransport`, `MCPTransportTermination`, private transport state | RUNTIME_ONLY | MCP SDK/transport actors and state; never canonical. |
| `MCPRuntimeController`, `MCPRuntimeProvider`, `MCPServerRuntimeSlot`, `MCPActivationReason`, `MCPServerLifecycleOperationKind` | RUNTIME_ONLY | Live provider/runtime lifecycle implementation. Publish canonical snapshots/events but keep actor/task ownership provider-local. |
| `MCPRuntimeAcceptance`, acceptance result/host diagnostic/progress types, `MCPServerPathResolverAcceptance` | RUNTIME_ONLY | Verification/acceptance implementation, not product contract. |
| `MCPTraceLogger`, `MCPLogRedactor` | RUNTIME_ONLY | Diagnostic implementation; no migration, bounded retention. |
| `MCPEnvironmentDraft`, UI settings/view models | RUNTIME_ONLY | UI/editor projection; not canonical configuration authority. |

## 6. RuntimeCore

| Current type(s) | Category | Decision and exact retirement condition |
| --- | --- | --- |
| `RuntimeKind`, `RuntimeOperationalState`, `RuntimeSnapshot` | RUNTIME_ONLY | Runtime implementation/UI status. Adapt to canonical runtime session/snapshot; keep provider-local if useful. |
| `RuntimeExecutionLimits`, `RuntimeExecutionRequest`, `RuntimeExecutionResult` | TEMPORARY_ADAPTER_BOUNDARY | Current local execution boundary includes URL/env and implementation result. Map from canonical script/execution contracts; replace cross-subsystem use after lossless result/cancel/limit parity. Runtime-internal equivalents may remain. |
| `RuntimeJSONValue` | RUNTIME_ONLY | Keep only at RuntimeCore host boundary; never canonical because integer provenance/data are absent. Adapter deletion means no cross-subsystem consumer, not necessarily removing host decoding. |
| `RuntimeCoreError` | RUNTIME_ONLY | Provider error; map to canonical error without discarding subsystem category. |
| `RuntimeManifest` and nested `BundleRecord`, `RuntimeRecord`, `LinkDependencyRecord` | RUNTIME_ONLY | Runtime bundle/build installed-state manifest, not app/package canonical domain descriptor. |
| `AppRuntimeCore` | RUNTIME_ONLY | Execution composition actor. Permanent implementation role. |
| `RuntimeFileLayout`, nested `Client` | RUNTIME_ONLY | Local filesystem ownership/path safety. Never portable. |
| `RuntimePolicy` | RUNTIME_ONLY | Low-level environment/archive policy. It supplements rather than replaces canonical permission policy. |
| `RuntimeEnvironmentScope`, `RuntimeEnvironmentItem` | PERSISTED_LEGACY_BOUNDARY | Current JSON record and IDs protect configuration/secret references. Retire old encoding only after versioned migration and rollback window. |
| `RuntimeEnvironmentStore`, `RuntimeSecretStore` | RUNTIME_ONLY | Store/Keychain implementations. Preserve data; may sit behind canonical config/credential interfaces. |
| `LifecycleApprovalRecord` | PERSISTED_LEGACY_BOUNDARY | Exact package/version/integrity/script-hash security decision. Preserve for current behavior, never map to capability grant, retire only after separate lifecycle approval migration and rollback window. |
| `LifecycleExecutionBroker` | RUNTIME_ONLY | Runtime policy/execution actor. Future canonical policy approval request adapts to it; keep implementation role. |
| `RuntimeHostConnection`, private host-ready/response types, `NodeHostHealthFailure`, `NodeRuntimeService`, `NodeRuntimeBridge` | RUNTIME_ONLY | Embedded host/transport implementation. Never canonical. |
| `TypeScriptCompilationResult`, nested `Diagnostic`, `TypeScriptProjectCompilationResult`, `TypeScriptExecutionResult`, `TypeScriptRuntimeService` | RUNTIME_ONLY | Compiler/runtime implementation. Map to canonical script diagnostics/results only after compiler lane decision. |
| `JavaScriptCoreRuntimeService`, `PythonRuntimeService`, `PythonRuntimeBridge`, private bridge response, `ShellRuntimeService`, `ShellCommandCapability`, `ShellHealthCategory` | RUNTIME_ONLY | Execution provider implementations/status. |
| `NodePackageFinding`, `LifecycleExecutionPlan` and nested `Action`/`Rejection`, `NodePackageDetails`, `NodePackageInstallTransaction`, `NodePackageManager` | RUNTIME_ONLY | Node package/lifecycle implementation. Installed data handled by store policy, not canonical app descriptor unchanged. |
| `PythonPackageDependency`, `PythonPackageRecord` | PERSISTED_LEGACY_BOUNDARY | Python installed registry records. Preserve/reconcile and retire old encoding only after transactional migration/rollback. |
| `PythonPackagePreview`, `PythonPackageInstallProgress`, nested `Phase`, `PythonPackageManager` internal index types | RUNTIME_ONLY | Installer/runtime implementation; progress may be adapted to canonical operation events. |
| `ExecuteJavaScriptTool`, `ExecuteTypeScriptTool`, `ExecuteLocalPythonTool`, `ExecuteShellCommandTool`, `RuntimeToolSupport` | RUNTIME_ONLY | Native tool provider implementations. Their descriptors/invocations become canonical through native provider adapter; executors remain. |
| `RuntimeDiagnostics`, shell diagnostic/smoke/acceptance types, `RuntimeLifecycleBridge` | RUNTIME_ONLY | Diagnostics/verification/app lifecycle glue; not canonical event authority. |

## 7. AgentActivity, diagnostics, and app integration

| Current type(s) | Category | Decision and exact retirement condition |
| --- | --- | --- |
| `AgentRunMetadata`, `AgentItemMetadata`, `AgentProgressMessage`, `AgentToolCall`, `AgentToolExecution`, `AgentToolResult`, `AgentAnswerDisposition`, `AgentEvent`, `AgentSafeError` | RUNTIME_ONLY | Live model-loop/activity events and UI payloads. Adapt to canonical audit/invocation events; provider/UI runtime types may remain. `@unchecked Sendable` is not inherited by canonical contracts. |
| `AgentActivityStatus`, `AgentActivityKind`, `ProgressSummarySource`, `AgentActivitySource`, `AgentActivityStep`, `AgentRun` | PERSISTED_LEGACY_BOUNDARY | AgentRun schema 4 persists in ChatMessages. Stop old writer only after new versioned activity projection; retain reader/migration through history support window. |
| `AgentTranscriptItemKind`, `AgentTranscriptTextRole`, `AgentTranscriptCompletionVisibility`, `AgentTranscriptItem`, `AgentEvidenceKind`, `AgentEvidenceItem` | PERSISTED_LEGACY_BOUNDARY | Embedded in AgentRun schema 4. Same retirement condition. |
| `AgentEventAccumulator`, `AgentRunCoordinator`, transcript/evidence accumulators/composers/deduplicators/policies | RUNTIME_ONLY | UI/product projection logic. Consume canonical events later; do not promote to portable audit contract. |
| `LegacyAgentActivityAdapter`, `LegacyResourcesEvidenceAdapter` | TEMPORARY_ADAPTER_BOUNDARY | Retire only when every live legacy provider/resource path emits canonical events and schema-4 history continues through read-only decoding. |
| `ProviderEventAdapter`, `HanlinStreamEventAdapter`, `ProviderCapabilities` | RUNTIME_ONLY | Model-provider stream adapter implementation; may feed canonical activity/audit but remains provider-local. |
| `AgentDiagnosticsLevel`, `AgentDiagnosticsConfiguration` | PERSISTED_LEGACY_BOUNDARY | UserDefaults diagnostic configuration. Preserve key values; retire only after versioned config migration. |
| `AgentDiagnosticsSession`, `AgentDiagnosticsRound`, `AgentDiagnosticsModelRequest`, `AgentDiagnosticsModelResponse`, `AgentDiagnosticsToolCall`, `AgentEfficiencyReport`, `AgentTokenUsage`, `AgentPromptCompositionMetrics`, `TokenUsageSource` | RUNTIME_ONLY | Versionless/bounded diagnostic file content, not canonical audit. Reset/retain per diagnostics policy rather than migrate. |
| `AgentDiagnosticsRecorder`, `AgentDiagnosticsRedactor`, `AgentTokenEstimator` | RUNTIME_ONLY | Diagnostic implementation. |
| `APIManager`, `ChatView` | RUNTIME_ONLY | Upstream-derived orchestration/UI integration points, not contracts. Future edits must be narrow hooks; do not replace broad behavior during contract cutover. |

## 8. App persistence models

| Current type(s) | Category | Decision and exact retirement condition |
| --- | --- | --- |
| `ChatMessages`, `ChatRecords`, `CanvasData`, `Resource`, `PromptCard`, `Location`, `Coordinate`, `RouteInfo`, `AudioAsset`, `EventItem`, `HealthData`, `CodeBlock`, `KnowledgeCard` | PERSISTED_LEGACY_BOUNDARY | SwiftData/CloudKit user data and embedded values. Retain exact model/decoders until explicit SwiftData migration, CloudKit assessment, semantic fixture verification, rollback/export, and history retention approval. |
| `KnowledgeRecords`, `KnowledgeChunk`, `MemoryArchive`, `PromptRepo`, `TranslationDic`, `UserInfo` | PERSISTED_LEGACY_BOUNDARY | User data/configuration. Same transactional SwiftData migration criteria; vectors may rebuild only from preserved source under approved policy. |
| `APIKeys`, `SearchKeys`, `ToolKeys` | PERSISTED_LEGACY_BOUNDARY | Metadata plus secrets in SwiftData. Retain until Keychain copy/read-back/reference switch/rollback succeeds and old secret fields are cleared by approved migration. |
| `APIType`, `APIFrom` | RUNTIME_ONLY | App provider configuration enums; preserve mapping while APIKeys records exist, not canonical platform identity. |
| `AllModels` | PERSISTED_LEGACY_BOUNDARY | User/provider model configuration. Migrate only with explicit ID/default mapping and SwiftData rollback. |
| `AppDataManager` | RUNTIME_ONLY | SwiftData composition root. Persistence ownership remains app implementation. |

## 9. Authorized Scripting reference

Every symbol in:

- `Reference/ScriptingCompatibility/Original/Types/global.d.ts`;
- `node.d.ts`;
- `safari-ext.d.ts`;
- `scripting.d.ts`; and
- `web-fetch.d.ts`

is classified **RUNTIME_ONLY** in the sense of an external/reference provider
surface: it remains immutable compatibility reference material and is not a
Hanlin canonical contract or live implementation. This blanket classification
applies to all 2,419 inventoried declaration symbols, including `Script`,
`ScriptingApi`, rendering types, system-service types, stream/cancellation types,
and Node/web declarations. The files are not deletion candidates. A future
implemented subset maps through canonical contracts and keeps the original
reference unchanged.

Compiler profile/reference metadata and generated compatibility records are
also **RUNTIME_ONLY** reference/verification artifacts. They become build inputs
only after Scripting gates; they never become product authorization evidence.

## 10. Global deletion evidence

For every `REPLACE_AFTER_CUTOVER`, `TEMPORARY_ADAPTER_BOUNDARY`, or
`DELETE_CANDIDATE`, deletion requires all applicable criteria in
`CANONICAL_CONTRACT_MODEL.md`: migrated/rebuildable persistence, producer and
consumer cutover, behavior/error/cancellation/presentation parity, no privileged
bypass, closed rollback window, zero legacy reads for the approved window, owner
approval, and explicitly requested verification on the exact commit.

`NativeChatCardProvider` and `MCPInstalledPackageManifest` are the only current
qualified delete candidates from the audit. Their classification is based on
semantic responsibility and required verification, not token counts.
