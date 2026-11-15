# Application Session and immutable row hook

This source connects `APIManager.processSDKAgentEngine` to **one** current
`HanlinAppAgentSessionOwner`. The owner retains the canonical Session/engine/Host and the adapter
of the existing SwiftData conversation row. A2UI owns ChatView/environment implementation;
Split owns actual target registration and the three SDK product links into AI_Hanlin only.
**Application Apple compilation and UI acceptance are NOT_RUN at this source handoff.**

## Concrete UI composition API

Keep one `HanlinAppAgentSessionOwner` for the original conversation in existing ChatView state.
Pass that same object to `APIManager(context: ..., agentSessionOwner: owner)` for subsequent
requests. Install a strongly retained A2UI consumer in `owner.presentation` **before** starting
the request. The property is weak; the consumer/view owns its lifetime.

`HanlinAppAgentPresentationConsumer` is the callable seam, extracted verbatim with the existing row/binding types into `AI_HLY/Downstream/ChatCore/HanlinAppAgentPresentationContracts.swift`. This file imports only actual SDK contracts and Foundation; it introduces no replacement DTO or SwiftData test stand-in. It receives installed Session,
original Host result/progress, canonical event plus immutable binding, completion, invalidation,
successful consumer drain, and read-only record replay. Completion hooks fan out existing
callbacks; no consumer overwrites an adapter's callback slot. Implement its
`validateCompleteParts` with
`try HanlinA2UICompleteBatchValidator.validate(parts)` (A2UI source `3637e8428fd7e37c8107d404efee23f040e1a854`, its corrected Apple proof
is independently pending). Validation is pure; actual receive admits the live surface once.

The already-created original assistant row must be passed explicitly to
`APIManager.sendStreamRequest(..., agentSDKRequest: .init(conversation: originalChatRecord,
conversationID: originalConversationUUID, sceneID: originalSceneUUID, rowID: originalAssistantRowUUID,
uiRunID: agentCoordinator.runID, temporary: originalTemporaryFlag, interaction: nil))`.
The existing row has to belong to that ModelContext; this source does not invent or save a new
conversation to satisfy identity. Non-SDK local/image routes retain their existing flow.

The A2UI consumer forwards `receive(event,binding:)` to its existing presentation adapter and
publishes the binding alongside its existing observable source/store. Match BOTH
`binding.reference.rowID` and `binding.reference.uiRunID`; use
`binding.canonicalRunID` and `binding.reference.messageID` for the canonical projection lookup.
`messageID` is the original application row UUID. Canonical runID comes from the **actual**
Session event. It is never fabricated from legacy `AgentRun.id`, prose, selected chat or part ID.
The original immutable `binding.session` is included.

The Session persists a bounded, version-prefixed reference via its existing
`presentationReference` transcript case before starting model delivery. It contains row/UI-run
UUIDs and original Session/context, while the transcript entry supplies actual canonical runID.
Replay validates namespace/conversation and restores historical original keys for display only.
No newly installed Session impersonates a historical one and no stored binding restores grants.
Mixed runs with identical text/part UUIDs must still match the entire original association.

After successful `for try await` drains, APIManager calls owner drain, which forwards the exact
completion runID. A `.finished` event does not return early or seal buffered output. Failure,
cancellation, selection/conversation/scene invalidation revoke authority immediately. UI lifecycle
calls `owner.cancel()` when its original context ceases to be current; transient sheet dismissal
does not mean surface deletion. Only explicit surface discard revokes that part's interaction.

For a form action, retain the original request and key; check the existing A2UI `isCurrent(key)`
before queueing. Start the existing application request/row flow with the SAME owner and new
row/UI-run identifiers, passing `interaction: originalRequest` and the original selected model.
The owner invokes **the same** Session's `continueInteraction`; original context/admission is
rechecked around its await. The host only converts user input into a new model turn; it does not
perform a business effect. A model/context change invalidates old controls instead of silently
substituting a model or reissuing authority.

## One storage and effect path

`ChatRecords.agentSDKRecordData` is an additive optional field in the existing conversation.
It holds the existing canonical `HanlinConversationRecord` (parts, receipts, references) once.
Existing ChatMessages text is its history/search/fallback projection; A2UI ordered presentation
replaces that visible body. No new database, transcript DTO, credential store or attachment store
is introduced. Legacy rows with nil canonical data remain unchanged. Temporary conversations use
the same adapter's transient record, retained across Session/model cancellation/replacement for
that original conversation owner. Saves compare revision, retain original bytes on error and
preserve non-SDK fields. Deleting a conversation invalidates its owner; stale rows fail authority
checks rather than recreate the conversation.

`HanlinAppHostIntegration` projects the existing `allToolDefinitions` and canonical authority.
It invokes the original closure once beneath the SDK dispatcher; NativeToolBridge/MCP/OS policy,
skill exposure, large result references, diagnostics and existing UI callbacks stay on that path.
Progress/outcome observers are transient, keyed by the original provider call and removed after
execution. They never execute a tool. Native `.succeeded` is authoritative general success,
not atomic CAS; unknown/failed/timed-out/cancelled mutation outcomes remain uncertain unless the
source explicitly rejected before effects. Late context/cancellation suppresses delivery without
rewriting a committed/uncertain receipt. Model failure feedback is transient sanctioned host
`userMessage`; persisted metadata receipts still redact business payload/error details.

The Host contract minor `1.1` adds `hostManagedMutation`. Catalog/dispatcher reject it under
minor `1.0`; serialization never downgrades it to independent creation/read-only. Conditional
revision input remains rejected before dispatch. This addition does not claim remote idempotency,
rollback or an OS permission the original executor does not have.

With structured presentation explicitly installed, the already-selected direct OpenAI
`gpt-6.1-terra` uses the actual Responses adapter and strict native schema request even when tools
are off. Other model selections keep their original route; no catalog default/model is replaced.
The existing app configuration/key resolver remains authoritative. No new named environment key
or repository secret is a product requirement.

## Evidence limits and next validation

Later exact source `8b6106ef`, run `43735446863`, has **45 newly executed passes**: all18 Session,
the Host minor control, the checkpoint recovery, and all25 Core (including five real Responses
adapter fixtures). iOS SDK compilation passed. Authenticated278 source hashes and all45 original
unique xcresult identities are retained in `evidence/contracts-43735446863.json`. This proves
the bounded checkpoint recovery including symbolic-link rejection. It does not compile app files.
The required catalog phase was **INFRA_ERROR / three NOT_RUN**: macOS Bash3.2 rejected an empty
archive array under nounset and an inadequate EXIT trap left the workflow green. The missing
actual results override its green status. The corrected helper requires real summary/xcresult/
iOS-build artifacts and the native-only recovery exercises the original shared-source branch.
Those45 package passes will not be reexecuted solely to repair this independent child phase.

SDK source `3885b01c`, run `43732861666`, executed **15 Session passes** and iOS SDK compilation.
Core test compilation failed on three new fixture source errors; **25 Core cases NOT_RUN** and
catalog phase NOT_RUN. The production Core compiled in that operation; this is not a Core test
pass. The fixture errors are corrected in this follow-on source, still awaiting Apple execution.

Checkpoint recovery `43730362902` at `80e755e1` was cancelled by the newer same-ref/same-group run.
Its actual log shows the Swift test started and hung at `CHECKPOINT_STAGE=save_v1`; no completed
case/xcresult pass exists. Prior invalidRecord failures remain real failures. Ancestor traversal
now uses a strictly shortening lexical path with a hard depth bound, retaining every symbolic-link
ancestor rejection. The unchanged checkpoint assertions/security case still require execution.

The next existing manual selector `HanlinAppHostComposition` selects all 18 affected Session
cases, one new Host minor-version control, the failed checkpoint recovery and all 25 missing Core
cases, followed by iOS SDK and catalog validation. It excludes five unchanged pure context/replay
cases and the in-memory namespace store case; those may be aggregated only after the versioned
closure/environment audit, never reported as reexecuted. The three catalog cases need actual
runtime availability evidence on the new runner. App SwiftData store/row collision/actual closure
execution, SDK-enabled full app/Composer, live model/rendered form, XCUITest/physical-device,
RTL/AX and release remain separate OPEN obligations.

## Conversation-open read-only restore

`HanlinAppAgentSessionOwner.restoreHistory(conversation: ChatRecords, conversationID: UUID,
sceneID: UUID, temporary: Bool, modelContext: ModelContext) async throws` loads through the
same store and private original-row decoder before any model request. Install the presentation
consumer first and call from a lifecycle task outside View.body, using the original conversation,
scene and ModelContext. It creates no engine/Host/Session, performs no admission or model request,
and forwards historical original Session/run/row bindings as read-only replay. The same-owner
temporary store is retained. Cancellation, revoke, a new stream/restore, wrong scope, replacement
or deletion suppress delivery; freshness and actual row existence are rechecked after the await.

Source syntax parsed on Windows. Actual SwiftData/App tests remain NOT_RUN pending the combined
enabled application graph. Package-only tests do not establish this app hook's compilation.
