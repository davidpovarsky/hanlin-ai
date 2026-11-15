# HanlinAgentSDK 0.1.0-preview.1 — first source contract

This preview is source delivery, not app/UI/device acceptance or a stable release. Consume the exact handoff Git SHA, never a moving branch. The package manifest is `Packages/HanlinAgentSDK/Package.swift`; platforms are iOS **27.0**, macOS **26**, Swift tools **6.2**, Swift language mode **6**. The local `../HanlinPlatform` dependency retains its real manifest and original public products. SwiftAISDK is pinned to `43ebcfaae67ca2c47ea1ce940d66b581e60ca7f6` in both graphs. See `IMPLEMENTATION_HANDOFF.md` for the frozen source/evidence and remaining gates.

## Public products and direction

| Product | Imports / responsibility |
| --- | --- |
| HanlinHostContracts | Foundation + existing HanlinPlatformContracts. Host context/session/catalog, canonical authority/result/navigation envelopes, conversation/memory/attachment/credential/capability/diagnostic ports. |
| HanlinAgentCore | HostContracts + existing HanlinChatCore/SwiftAISDK. HanlinAgentSession adapts DI/persistence to the existing engine. HanlinHostDispatcher gates scoped host requests. Thin Apple provider is here. |
| HanlinPersistenceAdapters | HostContracts. Private single-writer file store and ephemeral store. No SwiftData model, Keychain entitlement, AppGroup, CloudKit or host business repository. |
| HanlinFixtureHost | Headless synthetic example only; no production Otzaria/Anytype import or semantics. |

There is no HanlinChatUI product in this delivery. Canonical UI/Composer/A2UI extraction and the exact SwiftUI entry signature remain UI-owner work. Hosts must not invent a replacement renderer/view to treat this core preview as completed SDK-04. Hanlin AI app adoption also remains an exact app-owned integration seam; its old orchestration has not been silently replaced or claimed migrated.

## Exact host port

The authoritative declarations are `Sources/HanlinHostContracts/HanlinHostContext.swift` and `HanlinHostIntegration.swift`. Method names are:

```swift
public protocol HanlinHostIntegration: Sendable {
    var apiVersion: HanlinAPIVersion { get }
    func context(for session: HanlinHostSession) async throws -> HanlinHostContext
    func catalog(for context: HanlinHostContext) async throws -> HanlinHostCatalog
    func execute(
        _ invocation: HanlinHostInvocation,
        progress: @escaping @Sendable (HanlinToolProgressEvent) async -> Void
    ) async throws -> HanlinHostExecutionResult
    func cancel(_ invocation: HanlinToolInvocationID) async
    func open(_ destination: HanlinHostDestination) async throws -> HanlinHostNavigationResult
}
```

`context` is getContext; `catalog` is the scoped availableTools projection, not another production registry. Major version 1 is required before dispatch. HanlinHostCatalog wraps canonical descriptors/routes/revisions with the host's actual write guarantees. A model-visible tool name is never authority. Host execute must validate actual JSON Schema, live permissions/confirmation/revocation, account/Space/object/scene generation, source preconditions and actual native dispatch; those operations cannot be replaced by the SDK's preliminary context check.

`HanlinConversationNamespace` contains exact `app`, `account`, `workspace`, `space`. Each is nonempty and bounded to 128 UTF-8 bytes; decoding revalidates. No lowercase/sanitization or implicit missing-to-global access. `HanlinHostContext` adds scene UUID, presentation generation UUID, opaque object/selected-block references, optional source revision and locale. The host supplies the authenticated presentation lifetime; global DI/current Space or a cached account is insufficient. Invalidate on account/Space/document/scene/permission lifetime changes and create a new host session for the new presentation. Do not attach current mutable global context to an old request after an await.

`HanlinHostInvocation` carries canonical HanlinToolInvocationRequest plus session, run UUID, step index, exact opaque providerCallID, writeGuarantee and optional expectedRevision. SDK maps provider IDs to fresh canonical invocation UUID strings instead of lossy sanitization. It reserves a call before execute, rejects same-call changed arguments and never auto-reissues an unresolved call. Its in-memory reservations are NOT cross-process durable idempotency; the host must durably journal operations that can survive the session/process. When native durable deduplication is unavailable, reject uncertain retries instead of re-dispatching.

## Writes, cancellation and receipts

`HanlinHostWriteGuarantee`: readOnly, independentObjectCreation, atomicRevisionMutation. An expected revision cannot be applied to a non-atomic operation. Atomic mutations require an expected revision matching the scoped context and an actual native atomic guarantee in the host. A local epoch/fingerprint is not CAS. The supplied Anytype audit establishes no native CAS: existing-object conditional edits are therefore unsupported. A separate new-object creation is only a candidate when the actual host authorizes and proves it.

`HanlinHostExecutionResult` wraps canonical HanlinToolInvocationResult with original context, optional opaque reconciliation reference and effectState: notDispatched, confirmedNoEffect, confirmedCommitted or uncertain. Exceptions/cancellation after entering execute cannot prove a write did not commit: SDK conservatively retains an uncertain receipt for writes. A host that knows validation failed before native dispatch should return an explicit notDispatched outcome. This avoids unnecessary uncertainty without trusting an exception string as proof.

Receipts are recorded in the original dispatcher namespace before stale-result delivery is rejected. They do not authorize new data access or navigation after account/Space switch. No automatic write retry in a newly selected account/Space; reconcile only with reacquired authority for the original scope. Host cancellation is best effort and does not promise native rollback. The SDK's default transcript stores pending tool identity before dispatch, metadata-only result receipts after dispatch, and rejects a new run while unresolved tool calls remain. Host reconciliation may explicitly update that original record after authoritative readback; replaying stored events never executes tools.

The canonical model/provider stream remains the existing HanlinAISDKAgentEngine loop. Thin facade callbacks expose current authorized host result/progress data for canonical UI consumption; raw host payloads are not logged or automatically persisted. Default persistence strips tool arguments, business result contents and raw host error details. Rehydration of rich historical host output needs scoped host references and the canonical UI projection, not duplicated host storage.

## Navigation acknowledgement

HanlinHostDestination has request UUID, originating context, exact object and optional block reference. `open` returns queued(requestID, context) or presented(requestID, context, objectReference, blockReference). The latter can only be issued by the actual target scene/UI owner after mount, not when a route merely enters a queue. SDK validates IDs/context/target and rechecks the session lifetime. `presentationAcknowledged` is false for queued requests. No generic fixture receipt proves a real host UI appeared. No background app wake, cross-app companion or arbitrary model URL authority.

## Injected services and storage

Construct HanlinAgentSession with an existing engine, scoped identity, host and ConversationStore; optionally supply authorized HanlinHostCapabilitySource and metadata-only HanlinDiagnosticsSink. Host capability preparation yields approved aliases/skill IDs/instructions from its existing Skills/MCP services. SDK never imports/copies the Hanlin production singleton catalog, connections or credentials. The core's dynamic tool reload is reused when aliases change; a same-alias catalog revision change ends the run explicitly because the existing core compares tool names for reload. This preview does not silently ignore a changed descriptor.

CredentialResolver returns transient host-designated credentials for a secret-free HanlinModelReference and namespace. Build the existing model configuration in memory; never persist its Codable apiKey-bearing representation. AttachmentStore imports bytes through host authority and resolves only typed scoped handles, not model file paths/URIs. MemoryStore carries explicit namespaces and host retention policy. Their concrete host/Keychain/document adapters are host-owned; protocols are not evidence those adapters exist.

HanlinPrivateConversationStore takes a host-provided private file URL and byte cap. One actor instance owns the directory. It validates namespace/conversation/format and revision on load/save, atomically writes records, rejects symbolic-link paths, and uses complete file protection on iOS. The latter requires native/signed verification; Windows behavior is not entitlement/file-protection proof. It does not coordinate multiple processes or multiple instances against the same directory. Shared app/extension storage requires a separate host-coordinated implementation. SDK code sharing needs no AppGroup and never assigns Hanlin groups to other products.

Checkpoint/restore operates only on versioned SDK metadata, uses compare-and-replace and never rolls back native host writes. Unknown versions/malformed records fail rather than auto-migrate/delete data. No production migration was executed. HanlinInMemoryConversationStore is explicitly ephemeral, suitable for temporary chats and tests.

## Apple model preview and existing picker seam

HanlinAppleOnDeviceProvider exposes modelID, displayName, availability, supportsTools=false, transient configuration() and makeEngine(configuration:). Its availability reads SystemLanguageModel.default when FoundationModels exists, distinguishing eligible-ready/off/not-ready/ineligible; unsupported frameworks report frameworkUnavailable. Existing picker owners show exactly one manually selectable row only for available, retain model identity across refresh, and report selection loss without cloud fallback. That app hookup is not implemented by this core writer.

The injected LanguageModelV3 adapter uses native text transcripts with role boundaries, native streaming snapshots normalized to deltas and empty/unknown token usage rather than invented metrics. It explicitly rejects tools/tool history, multimodal content, reasoning and unsupported generation settings. Native tool-call integration is **not implemented**: nesting native Tool execution inside SwiftAISDK would risk duplicate effects, and no native exact-once proof exists in this delivery. The preview must not be advertised as full Apple agent parity. No network/API key/PCC provider is selected as a substitute.

Apple SDK compilation, real model generation, runtime availability changes, cancellation and eligible-iPad tests remain required. Source/documentation and Windows compilation cannot prove them. The lead approved and source now implements native-only non-text preflight immediately before core message conversion, so unsupported image URLs/data are rejected before SwiftAISDK's download path. Additive spy tests cover both actual non-text enum cases and all three roles, but remain NOT_RUN until the full core can be tested with Apple Foundation. No synthetic file/tool message cases were invented.

## Host ownership and acceptance

Anytype SDK-06 input is the frozen 57-blob source audit at 389f12320d89975ebb58d2aaf13b051693194d59; no host source was modified here. Anytype lead owns upstream reconciliation, native services, authenticated scope, dependency/minimum and actual UI callsites. Generic SDK reads must not enter Torah provisioning/bootstrap storage or Heart/CRDT directly.

Otzaria owns its in-process thin adapter, ActionCore/UIRegistry/SceneOrchestrator and scene/routing ports. Reported portable contract/code pins are mock/compile readiness, not approved semantic integration. SDK-07 here is exclusively the headless synthetic fixture. No Otzaria API enumeration/import/reader/search/backend mapping occurred. Real integration requires both this frozen typed SDK contract and the host's accepted versioned semantic and scene/routing ports. Native/real-data/UI/device acceptance remains separate for every host.
