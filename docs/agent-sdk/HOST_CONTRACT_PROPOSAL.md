# HostIntegration proposal v0.1 — SDK-03 / SDK-05 / SDK-07

Status: DESIGN_PROPOSAL, not an exported or compiled API. Source baseline and lease are in `SDK_01_SOURCE_AUDIT.md`. Anytype's SDK-06 consumer contract must be reconciled through its lead before freezing names or relying on signatures.

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
    ) async throws -> HanlinToolInvocationResult
    func cancel(_ invocation: HanlinToolInvocationID) async
    func open(_ destination: HanlinHostDestination, context: HanlinHostContext) async throws
}
```

Proposed `HanlinHostSession`: a host-issued session UUID, conversation UUID and explicit namespace. `HanlinHostContext`: host/app identity, account, workspace, Space, scene, object/selection opaque references, source revision, locale and host-issued context token. Absence is represented explicitly; it is not an empty string meaning global access. Raw host context contents are opt-in scoped data, not automatically copied into a prompt.

Proposed `HanlinHostInvocation` wraps an existing `HanlinToolInvocationRequest` with the host context token, run UUID, step index and provider call ID. Preserve the provider's opaque ID verbatim; do not assume every provider ID is a UUID or sanitize it into collisions. The host issues a canonical invocation ID and idempotency identity bound to this run/scope, never from model-supplied grants. Execution uses the existing logical tool/revision/arguments/origin/limits/grants/deadline fields.

Permission/confirmation/revocation ports use existing HanlinPermissionRequest/Decision/Revocation/EffectivePermission contracts. Their concrete service stays host-owned. The SDK may request a decision; it cannot mint a valid grant or equate a UI confirmation with system permission. Host mutation revalidates the current decision inside its transaction. An API design must not split authorize and mutate in a way that creates an unchecked time-of-check race.

Auxiliary injected ports: ConversationStore, MemoryStore, AttachmentStore, CredentialResolver, redacted DiagnosticsSink, SkillSource and MCPToolSource. Concrete protocols and signatures await the implementation lease and consumer agreement. They must all carry the namespace/session where relevant; no implicit global singleton/default host identity.

## Invocation behavior

1. Host authenticates the current account/Space/scene and issues the context snapshot/token.
2. Catalog is a scoped view of existing host authority. Reject duplicate aliases, ambiguous identities and invalid descriptors before converting to core tool definitions. Unavailable tools remain unavailable.
3. On model tool request, bound argument bytes and decode canonical JSON. The host validates the actual schema, supported dialect, descriptor/catalog revision and capability scope. A schema document's successful decode is not argument validation.
4. Host resolves confirmation/system permission as needed. No UI available means a structured denial or needs-interaction result, never allow by default.
5. At mutation, host atomically revalidates context/source revision, grants/revocation, run cancellation, limits/deadline and idempotency. Unknown, stale or unauthorized requests fail closed. Host coordinates cancellation with its actual cancellable operation; cancellation does not promise rollback of an already committed effect.
6. Preserve canonical invocation ID in progress and result, reject mismatched results. Progress sequence is monotonic per invocation; late callbacks from cancelled/superseded runs do not affect a newer run. Large outputs use scoped result/attachment handles, not unbounded prompt strings.
7. Duplicate idempotency calls return the same authoritative outcome or explicit in-progress/conflict state without repeating effects. A retry with different arguments/scope under the same identity is a conflict. Idempotency survives process boundaries only if the host durably implements it; an in-memory set is not that guarantee.
8. Navigation carries typed opaque host destinations with exact account/Space/scene/object provenance, revalidated by the host. No arbitrary model URL/deep link becomes authority. No companion install/background wake requirement.

Structured errors must distinguish unsupported contract/tool/schema, invalid arguments, stale context/revision, denied/revoked/needs interaction, cancellation, timeout, idempotency conflict, transport/provider failure, output budget and storage failure. Safe messages are host-redacted; raw credentials/context/model payloads never become default diagnostic strings.

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

Use a fake host to exercise actual SDK dispatch logic: scoped read, permitted mutation, confirm/deny/revoke, stale revision/scene/Space, unknown/duplicate catalog entries, schema mismatch, cancellation during permission and mutation, mismatched progress/result, duplicate/conflicting idempotency, bounded output and two isolated hosts. Storage cases include same conversation UUID in distinct namespaces, account switch, malformed/newer replay, interrupted writes and checkpoint rollback. These are planned cases, all NOT_RUN in this design tranche.
