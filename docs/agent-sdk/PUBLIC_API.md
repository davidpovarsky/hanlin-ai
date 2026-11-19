# HanlinAgentSDK 0.1.0-preview.1 — first source contract

> Historical 2026-11-15 source record. For current pins, implemented products, Host API 1.1, conversation format 2 and actual consumer/platform status, read [SDK-01 current audit (2026-11-19)](SDK_01_CURRENT_AUDIT_20261119.md). Historical pause/lease wording does not override the owner's current standing continuation authorization.

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

A host freshness call can suspend and later return a previously captured matching context. The dispatcher rechecks its own session revocation and task cancellation immediately after that await, before cached return, host navigation dispatch and post-effect result/navigation acknowledgement delivery. Checking the captured context alone is insufficient. Progress has the same post-await lifetime filtering. These checks preserve receipts for effects already dispatched and do not claim native rollback.

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

## Otzaria consumer representation review — 2026-11-15

Consumed the host-owned `HANLIN_CONTRACT_REVIEW_357D_20261115.md` and its eight-blob manifest from HQ `docs/otzaria/ui-routing`. All eight hashes were independently verified against the referenced 357d commit; `evidence/otzaria-consumer-review-input.json` records the receipt. This is a bounded review of the supplied contract feedback, not a production Otzaria API audit, accepted adapter or native test. The later 08b5 revocation correction remains subject to independent source re-review.

| Consumer requirement | Existing representation and limitation |
| --- | --- |
| Native String scene, UInt64 backend generation and RPC epoch | The host explicitly binds an SDK scene UUID to an actual native scene lifetime and separately issues a presentation-generation UUID. Preserve native scene identity/backend generation/RPC epoch/scene revision as distinct trusted host snapshots behind that binding. Never parse a native scene String as UUID, derive a UUID from a counter, narrow UInt64 to Int64, or accept authority epochs from model arguments. Invalidate the binding on relevant auth/profile/workspace/backend/scene/document/selection/permission changes. No new public contract type is needed for this host-owned lifetime mapping. |
| Complete normalized UI route, not just object/block | Use a host-issued opaque scoped reference in the destination's objectReference for an agreed non-content route handle. Its backing immutable native route includes presentation/tab/panel/focus/selection and exact scene/revision. Host checks the COMPLETE native UI receipt before emitting presented, retaining exact reference/request/context identity. SDK validates reference/context equality; it cannot inspect a route hidden behind the reference. No approved backing route port means unsupported, not an invented work/line or embedded private route payload. Queue remains queued; no success from backend completion alone. |
| Noncompleted semantic status/continuation | Canonical `HanlinToolOutcome.failed(HanlinPlatformError(code: .operationUnavailable, ... details: ...))` can carry a safe exact status and opaque continuation reference using existing HanlinValue. Keep it non-success; never encode pending/waiting/queued as completed text/metadata. The live onHostResult callback receives those structured details. Current model text projection is a generic error, and metadataReceipt deliberately strips error details. Therefore an exact historical status needs a top-level opaque reconciliationReference to the original authorized host receipt; inline historical/model-visible status is NOT promised by this preview. If no approved scoped receipt/continuation port exists, that continuation remains unsupported. A reference is not a grant, permission to retry or replay authority. |
| Effect certainty | Preserve notDispatched/confirmedNoEffect/confirmedCommitted/uncertain from actual evidence. Task cancellation/revoke/backend acceptance cannot prove native no-effect or rollback. Keep writes unavailable until their real guarantees are known; never retarget/retry an uncertain effect in another context. |
| Exact model argument numbers | **BLOCKED in the existing model-tool path; see below.** Direct canonical DTOs preserve Int64 vs finite Double, but the pinned SwiftAISDK conversion can erase that distinction/value before the host sees arguments. Host-side post-conversion validation alone cannot reconstruct lost information. |

Opaque route/status handles must be bounded, scoped to the original namespace/scene/generation/request, invalidated/revoked by the host and rejected after restart or loss of backing authority. They contain no private selection/query/note body and introduce no permanent shadow business-ID system. Actual host adapter/registry/cancellation-ID mapping and native readiness remain host-owned.

### Concrete numeric incompatibility and narrow proposal

Canonical `HanlinJSONValue` has integer(Int64) and number(Double). Its direct parser rejects plain integer overflow instead of falling back to Double, and canonicalJSONData preserves the integer/number category. Existing tagged Codable HanlinValue/HanlinJSONValue forms also preserve the category. Full UInt64 integer arguments and arbitrary exact decimal numbers are outside this public JSON value range; they must be rejected or represented only by an explicitly agreed versioned string/opaque-reference schema, never silently coerced.

However, **AISDKProvider.JSONValue** at exact revision `43ebcfaae67ca2c47ea1ce940d66b581e60ca7f6` has only number(Double). The existing HanlinAISDKAgentEngine.makeTools execute closure receives that value and calls jsonString(input), which uses JSONEncoder, before invoking the host executor. ToolCallOptions has toolCallId/messages/abortSignal/experimentalContext, no original argument JSON field. By this boundary the original numeric lexeme/type may already be lost. Re-parsing that normalized JSON in HanlinHostDispatcher does not recover it.

The isolated **actual pinned source** reproduction in `evidence/numeric-boundary-proof.swift`/`numeric-boundary-output.json` ran on Windows Swift6.3.3 and the actual canonical value module. It is not full engine/native/Otzaria execution. Observed: `1.0` and `1e0` become JSON `1` and arrive as integer(1); exact integer `9007199254740993` becomes `9007199254740992`; Int64.max becomes a rounded Double. Direct canonical parsing preserves those original supported values, and rejects UInt64.max outside Int64. This confirms a representational limitation before the host adapter, not an Otzaria validator defect.

Narrow requested seam, **not implemented or approved by this document**: preserve the original validated argument JSON/typed integer category at the point where the pinned SDK still owns raw toolCall.input, and carry it to the single existing core executor; alternatively, explicitly withhold/refuse affected numeric capabilities until such a path exists. This needs a reviewed core/pinned-SDK seam and real end-to-end regression cases, not a change to shared PlatformContracts or a second dispatcher/agent. Do not reconstruct integer intent from an already rounded Double, silently change host action schemas, or collect asynchronous stream deltas in a race-prone side cache as a substitute for an authoritative executor input.

No shared contracts, provider pin, core/host source, adapter or native API were changed during this consumer review. Exact numeric model-tool compatibility and any model/history projection needing inline continuation status remain unaccepted; native/full-graph/real host/UI/device gates remain open.


## Current producer/consumer and UI lifecycle packet

The later [combined packet](RAW_INPUT_AND_SESSION_HANDOFF.md) supersedes the
proposal-only status above. Producer commit `788a591aa0981443ec9a8e747393f07fcdcae4cf`
implements additive checked original input, including actual approval resume.
Its complete production module built on Windows and 45 selected real tests passed;
39 portable Hanlin cases passed. Actual Hanlin engine/session numeric execution
and Apple/device acceptance remain **BLOCKED / NOT_RUN**, not inferred from those
separate proofs. Tomer alone updates shipping dependency pins/locks after QA; the
new consumer source requires that producer while current manifests still pin43ebcf.

Stream cancellation/invalidate is terminal for a presentation Session. No reusable
cancel-current-turn seam is promised. A later send requires a new host-authorized
session identity/new Session; pending/uncertain effects still require original-host
reconciliation. Normal completed runs may reuse a still-valid session. See the
packet's exact lifecycle and reentrancy contract before implementing SDK04 UI.


## P1 consent-correlation source correction

The current [combined packet](RAW_INPUT_AND_SESSION_HANDOFF.md) now requires
producer `e7bf34111e603ca977becd007dd4e5bb109af857`. Multiple approval requests for
one call fail closed even when their distinct IDs have matching or conflicting
decisions. Other calls with one matching request retain eligibility. New actual
generateText/streamText resume regression bodies preserve static/dynamic and
accepted/repaired input, but are **NOT_RUN / not typechecked** under the resource
gate. Prior 45-producer/39-portable results remain historical old-closure evidence.
No consumer source or shipping dependency pin/lock changed for this correction;
Roni review and Tomer's real Mac proof/final dependency window remain required.
