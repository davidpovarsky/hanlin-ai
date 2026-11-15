# HostIntegration proposal v0.1 — SDK-03 / SDK-05 / SDK-07

Status: DESIGN_PROPOSAL, not an exported or compiled API. Source baseline and lease are in `SDK_01_SOURCE_AUDIT.md`. The frozen Anytype SDK-06 host audit has been incorporated below; public signatures still require the implementation lease, consumer review and actual compilation before promotion.

Historical design record: the subsequent preview's exact declarations and navigation acknowledgement API are in `PUBLIC_API.md` and `Sources/HanlinHostContracts`; use those for consumer mapping. Complete native validation remains pending as detailed in `IMPLEMENTATION_HANDOFF.md`.

## Module and version boundary

Propose `Packages/HanlinAgentSDK` consuming existing local HanlinPlatform products. HanlinHostContracts imports Foundation + HanlinPlatformContracts only. HanlinAgentCore imports HostContracts + the existing HanlinChatCore. Persistence adapters import HostContracts, not app business models. UI owners define the eventual canonical UI product. None imports Anytype, Otzaria, Hanlin app, SwiftData models or ProductSplit foreground bridge.

Contract version uses existing `HanlinAPIVersion`; proposed initial negotiation 1.0 is distinct from proposed package pre-release 0.1.0. Reject unknown major before catalog/context access. Additive minor fields must have documented defaults; changed authority, identity or persistence semantics require an explicit version/migration. Replay formats have a separate version and reject unsupported versions without overwriting original data.

## Proposed typed ports

These are design signatures, deliberately not a second set of tool/permission DTOs:

```swift
public protocol HanlinHostIntegration: Sendable {
    var apiVersion: HanlinAPIVersion { get }
    func context(for session: HanlinHostSession) async throws -> HanlinHostContext
    func catalog(for context: HanlinHostContext) async throws -> HanlinToolCatalogSnapshot
    func execute(
        _ invocation: HanlinHostInvocation,
        progress: @escaping @Sendable (HanlinToolProgressEvent) async -> Void
    ) async throws -> HanlinHostExecutionResult
    func cancel(_ invocation: HanlinToolInvocationID) async
    func open(_ destination: HanlinHostDestination) async throws -> HanlinHostNavigationResult
}
```

Proposed `HanlinHostSession`: a host-issued session UUID, conversation UUID and explicit namespace. `HanlinHostContext`: host/app identity, account, workspace, Space, scene, object/selection opaque references, source revision, locale and host-issued context token. Absence is represented explicitly; it is not an empty string meaning global access. Raw host context contents are opt-in scoped data, not automatically copied into a prompt.

Proposed `HanlinHostInvocation` wraps an existing `HanlinToolInvocationRequest` with the host context token, run UUID, step index and provider call ID. Preserve the provider's opaque ID verbatim; do not assume every provider ID is a UUID or sanitize it into collisions. The host issues a canonical invocation ID and idempotency identity bound to this run/scope, never from model-supplied grants. Execution uses the existing logical tool/revision/arguments/origin/limits/grants/deadline fields.

Permission/confirmation/revocation ports use existing HanlinPermissionRequest/Decision/Revocation/EffectivePermission contracts. Their concrete service stays host-owned. The SDK may request a decision; it cannot mint a valid grant or equate a UI confirmation with system permission. At its final available dispatch boundary the host revalidates the current decision. Atomic revision checks are a separately declared host capability: a Swift-side generation/fingerprint check does not create a native transaction or compare-and-swap. An action requiring an unsupported atomic precondition is unavailable before dispatch; do not substitute a best-effort write.

Auxiliary injected ports: ConversationStore, MemoryStore, AttachmentStore, CredentialResolver, redacted DiagnosticsSink, SkillSource and MCPToolSource. Concrete protocols and signatures await the implementation lease and consumer agreement. They must all carry the namespace/session where relevant; no implicit global singleton/default host identity.

## Invocation behavior

1. Host authenticates the current account/Space/scene and issues the context snapshot/token.
2. Catalog is a scoped view of existing host authority. Reject duplicate aliases, ambiguous identities and invalid descriptors before converting to core tool definitions. Unavailable tools remain unavailable.
3. On model tool request, bound argument bytes and decode canonical JSON. The host validates the actual schema, supported dialect, descriptor/catalog revision and capability scope. A schema document's successful decode is not argument validation.
4. Host resolves confirmation/system permission as needed. No UI available means a structured denial or needs-interaction result, never allow by default.
5. Before dispatch, host revalidates context/source revision, grants/revocation, run cancellation, limits/deadline and supported idempotency guarantees. Unknown, stale or unauthorized requests fail closed. Conditional mutations require proven native atomic revision support; if absent, report unsupported before dispatch. Host coordinates cancellation only to the extent its operation supports it; cancellation after dispatch may leave a committed or uncertain effect, even if the caller receives CancellationError. See the execution-result envelope below.
6. Preserve canonical invocation ID in progress and result, reject mismatched results. Progress sequence is monotonic per invocation; late callbacks from cancelled/superseded runs do not affect a newer run. Large outputs use scoped result/attachment handles, not unbounded prompt strings.
7. Duplicate calls return the same authoritative outcome or explicit in-progress/conflict state without repeating effects. A retry with different arguments/scope under the same identity is a conflict. Idempotency survives process boundaries only if the host durably implements it; an in-memory set is not that guarantee. A host without durable native deduplication may reject repeat/uncertain writes rather than reissue them. Neither SDK nor model-provider retry logic may automatically redispatch a write after uncertain completion or an account/Space transition.
8. Navigation carries typed opaque host destinations with exact account/Space/scene/object provenance, revalidated by the host. No arbitrary model URL/deep link becomes authority. No companion install/background wake requirement.

Structured errors must distinguish unsupported contract/tool/schema, invalid arguments, stale context/revision, denied/revoked/needs interaction, cancellation, timeout, idempotency conflict, transport/provider failure, output budget and storage failure. Safe messages are host-redacted; raw credentials/context/model payloads never become default diagnostic strings.

## Anytype consumer evidence and write-result semantics

The controller supplied the Anytype Lead-reviewed frozen host audit at `C:/Users/DAVID/Code/Codex-Agent-HQ/docs/anytype/hanlin-sdk06-20261115/`. Both received hashes were independently verified here: `HOST_AUDIT.md` SHA256 `d14eabfe48088c43822432f858b2f5c5d35a5eabd6e1efa82bce64e2065b0713`; `source-map.json` SHA256 `69f6bc7ec08bb52d2083b5a657bb22485260e62cf461ca6b370c4e55eb32f744`. The map contains 57 exact source blobs at `389f12320d89975ebb58d2aaf13b051693194d59`. This is consumed source evidence from SDK-06, not direct host runtime/ACL validation by this writer. Upstream divergence, protected hunks and host writes remain the Anytype lead's responsibility.

Concrete mapping from that audit: reads through `ObjectLifecycleService.ObjectShow` or the authorized live editor; writes through ObjectActions/property/block/text services; selected block IDs from the owning editor publisher; navigation through scene-local `PageNavigation`/`EditorPageModuleOutput`; presentation through the native sheet composition seam. Do not use generic Torah provisioning/bootstrap storage, global active-Space state or the legacy singleton window as SDK scene authority. Factory registration alone does not mount UI. Target/dependency/UI callsite changes remain host-owned.

The audited native write APIs expose no expected-revision/CAS parameter. Native work may continue after the Swift waiter is cancelled. Consequently the contract adds capability metadata and effect certainty alongside, rather than replacing, canonical tool outcomes. The following are proposed typed DTO shapes for the same HostIntegration API, not implemented symbols or another adapter API:

```swift
public enum HanlinHostWriteGuarantee: String, Codable, Sendable {
    case readOnly
    case independentObjectCreation
    case atomicRevisionMutation
}

public enum HanlinHostEffectState: String, Codable, Sendable {
    case notDispatched
    case confirmedNoEffect
    case confirmedCommitted
    case uncertain
}

public struct HanlinHostExecutionResult: Sendable {
    public let result: HanlinToolInvocationResult
    public let effectState: HanlinHostEffectState
    public let context: HanlinHostContext
    public let reconciliationReference: String?
}
```

Capability annotations are attached to the existing logical tool identity and descriptor/catalog revision; they are not a separate tool registry. A conditional request carries a host-issued expected revision and is accepted only for an advertised atomicRevisionMutation action backed by a native guarantee. Local update epochs may protect presentation freshness but never satisfy that precondition. Anytype existing-object conditional edits therefore remain unsupported under the supplied evidence. Independent-object creation is only a possible narrower first-write action after host authorization, exact contract mapping and runtime proof; this proposal does not enable it.

`effectState` is orthogonal to user delivery/cancellation. `notDispatched` proves the host did not send the operation. `confirmedNoEffect` requires authoritative evidence, not an exception string. `confirmedCommitted` requires an authoritative result/readback or durable receipt. `uncertain` means dispatch occurred and no definitive effect result is available; never translate it into an ordinary retryable failure or confirmed rollback. Cancellation, timeout or loss of a Swift waiter alone is insufficient to establish no effect. Read-only actions do not assert a write effect.

After mutation dispatch, host cancellation/error handling returns or durably records this envelope where possible. A disappeared waiter/process leaves an unresolved invocation record for reconciliation, rather than permission to rerun it. The SDK must not discard post-dispatch uncertainty simply because the stream was cancelled. Provider-level generation retry does not repeat a host write: tool dispatch receipts and unresolved calls remain bound to the original namespace/invocation identity.

`context` binds receipt/outcome to the original authenticated account + Space + object + scene/presentation generation. A known created object ID is retained only in that original authorized context. After account/Space switch, suppress old delivery/navigation into the new presentation and invalidate the old session; do not retarget reconciliation or automatic retry to the new account/Space. A host may reconcile only after explicitly reacquiring authorization to that original context. UI can show a safe operation-status message without disclosing old content into the new scope.

The future standalone SDK handoff must freeze these public types, exact auth/context/revision/cancellation/effect semantics, package products/SHA and the canonical UI entry API together. HanlinChatUI's entry signature remains UI-owner input; no fake view or new renderer is created to satisfy the host dependency.

## Store and transcript boundary

Conversation namespace comprises host/app + account + workspace + Space; session/scene scopes must not accidentally merge parallel documents. Namespaces are equality-checked typed values; on-disk keys should be a canonical encoding/hash of the entire tuple, not string interpolation or a sanitized chat name. Store APIs must reject access using a different namespace even if conversation UUID is known.

Persist a versioned transcript envelope with conversation/run/step/event sequence, timestamp, provider/model reference, message/tool correlation, result references, cancellation/error outcomes and versioned presentation payload references. Do not persist `HanlinChatModelConfiguration`: it includes the API key. CredentialResolver returns transient host-designated secrets; it never exports Keychain groups, requires Hanlin installation or writes secrets to group defaults.

Default store should be private per application with host-selected protected directory and bounded atomic writes. Shared app/extension operation requires an explicit coordinated writer strategy; an actor alone does not synchronize multiple processes. AppGroup history sharing is optional and only for compatible signed identities with owner-approved policy. Do not assign Hanlin AppGroups to Anytype/Otzaria. No CloudKit requirement. Native host business documents remain behind native repositories.

Attachment handles are host-issued, opaque and bound to namespace/session/use constraints. Import checks content type/byte limits and URI/bookmark authority; resolving a model-provided path is forbidden. Memory is scoped data with explicit retention/deletion, not another global context source.

Migrations are versioned plan/dry-run, checkpoint/backup, atomic commit and verified rollback on synthetic copies first. Unknown/newer versions remain byte-preserved and return an error. Logout/account switching revokes session access and closes/cancels work; deletion policy is explicit, not an automatic destructive move. Signed file-protection/Keychain/AppGroup behavior requires separate native/device evidence.

## Skills/MCP and single engine

SkillSource supplies authorized skill metadata/resources/instructions with version/provenance; MCPToolSource supplies the host's authenticated scoped MCP catalog/dispatch. Existing host services keep connection state and credentials. Do not copy Hanlin's production catalog or MCP runtime into a second registry. Loaded/exposed tool sets are per-run and reset appropriately; a skill cannot grant a capability the host denied.

HanlinAgentCore coordinates DI and translates canonical host tools into existing HanlinAISDKToolDefinition closures, then calls HanlinAISDKAgentEngine. Its per-step callback supplies approved exposures and skill instructions. It adds correlation/persistence/projection around the stream; it does not implement another model/tool loop. App adoption must replace responsibilities in place through a narrow lease, with no claim of parity while both paths remain independently orchestrated.

## Otzaria fixture and ownership boundaries

SDK-07 is a synthetic fixture conforming to this generic host boundary, with fake document context, fake catalog and deterministic test side effects only. It belongs under approved SDK fixture/test paths. It must import no Otzaria module and call no production host API. No enumeration of existing actions or claims that descriptor counts are functioning tools.

Actual Otzaria adapter is BLOCKED_DEPENDENCY on its unified semantic-actions team's versioned port, authentication and revision policy. Actual host target wiring belongs to that project's owner. Anytype owns its own native read/write/storage/DI hooks under its upstream freeze; SDK-06 is not leased to this writer. SDK-04 remains Maya/Eitan's canonical Composer/A2UI/UI extraction. Runtime/metadata and shared Host ABI remain Noam-owned.

## Required evidence before contract promotion

Use a fake host to exercise actual SDK dispatch logic: scoped read, permitted mutation, confirm/deny/revoke, stale revision/scene/Space, unknown/duplicate catalog entries, schema mismatch, cancellation during permission and mutation, mismatched progress/result, duplicate/conflicting idempotency, bounded output and two isolated hosts. Add cases where conditional mutation is unsupported, cancellation occurs before dispatch, native creation completes after cancellation, completion is uncertain, reconciliation stays in the original context, account/Space changes suppress delivery, and provider retries cannot repeat writes. Storage cases include same conversation UUID in distinct namespaces, account switch, malformed/newer replay, interrupted writes and checkpoint rollback. These are planned cases, all NOT_RUN in this design tranche.
