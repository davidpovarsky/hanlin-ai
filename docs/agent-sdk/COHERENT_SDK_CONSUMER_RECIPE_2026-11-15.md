# Coherent SDK consumer recipe

Current integration consumes the package source from the Apple-qualified association snapshot
`364f10a6dc55b9a28b67ab972843a2e1c44ef986`, handed off with evidence at
`7d2612d8bc21f424468b9774929eb71ca446e420`. Its raw Mac locks remain byte-identical to the
earlier schema handoff `62db3a1cff9884b363d4c457c3c3a88c803363b9`. This supersedes the older
frozen80 and schema-only package inputs; their historical evidence remains separate.
Use this monorepo's literal local packages, not its root as a Git package. Later app-owner,
Host-executor, history UI and Split changes are not included in this package-only update.

Keep `Packages/HanlinAgentSDK` and its literal `../HanlinPlatform` sibling. Link the three SDK products
`HanlinHostContracts`, `HanlinAgentCore`, `HanlinPersistenceAdapters` into **AI_Hanlin only**.
MiniApps does not acquire an agent/model engine. Integration already links these products and
links Core into the direct unit target; this package-only update makes no further project edit.
Existing app code retains its HanlinChatCore/PlatformContracts dependencies.

Platforms remain iOS27/macOS26. The SDK manifest uses tools6.2/language6; the exact new validation
dependency requires Swift6.4, qualified here with Apple Swift6.4.2/Xcode27.2. JSON/JSONSchema are
private AgentCore dependencies at `f2a0d12da7028edfbcb0cb307f19a921a3a12d03`. The producer remains
`e7bf34111e603ca977becd007dd4e5bb109af857`; neither Platform nor producer pins advance:

| Input | SHA256 |
| --- | --- |
| SDK Package.swift | 22f30a52c2b08e3a255c30c0887c35e8d2cdc1b0ca6b84648fbacd7f678b8d2c |
| SDK Package.resolved | f1d3bc296d9140741423eac850a1426eb8cf2e6a9aea9db21079746f7c573474 |
| Platform Package.swift | 3f8cbcbad6b07b509a7976fe0577315481f25358ce34a01e505f2d1b04821066 |
| Platform Package.resolved | 7882ef847a4aaa1bfa2ee128122393cf718f393485d9658bb93f402f740f2c17 |

## Qualified package schema/raw boundary

[Run43742612086](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43742612086) executed
18 Session,6 Context and9 schema/raw controls: **33 EXECUTED_PASS**, with actual iOS AgentCore
compilation PASS. This is the original run, not a new execution at the integration SHA.
Artifact14172853768 SHA-256 `23f962a56890524d03e6cde65eadf360428197c067aa0c7ed69c2cb86c98cd20`
was independently downloaded and all ZIP CRCs checked. All245 archived source hashes match both
their source tar and original Git; the two raw Mac locks match the handed-off package graph.
The actual33 unique xcresult case IDs, process exits, dependency source/revision and retained
Apache-2.0 license were checked. At integration checkpoint7cca3941, importing the15 changed
package paths matched that original closure; later association changes are accounted separately below. See
`evidence/host-schema-43742612086.json` and `HOST_SCHEMA_VALIDATOR_DECISION_2026-11-15.md`.

The existing manual SDK proof job accepts exact selector
`HanlinAgentCoreTests/HostSchemaValidationTests` to run that same affected package contract;
automatic triggers and other job routes are unchanged. No proof run was dispatched here.
This does not qualify the actual app Host, broad MCP, live provider, A2UI renderer, SwiftData,
XCUITest, device or release. The new optional model-response implementation below is documented
in `NATIVE_SCHEMA_MODEL_PATH_2026-11-15.md`; its older package fixtures remain separate evidence.

## Qualified ordered Host association

The Dispatcher reserves the actual result UUID before Host entry. An existing unresolved call
can then associate one bounded opaque reference through `Session.associateHostInvocation` and
the SAME ordered CAS persistence tail before external dispatch. Full original call/session/run/
step/result/argument identity is checked; a changed reference or fabricated reservation is rejected.
No second record writer or effect executor is introduced.

[Run43743854538](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43743854538) at exact364
executed **27 EXECUTED_PASS**:20 Session,6 Context and1 affected Dispatcher control; actual iOS
AgentCore compilation passed. Artifact14173940167 SHA-256
`04f671971b186a405d174e6864cd1c431911a4b65017ff58f9c5eb97ccb76f33` was independently downloaded
and all ZIP CRCs checked. All245 archived hashes match the source tar, original Git archive and
assembled package inputs, including unchanged actual raw Mac locks. All27 unique xcresult IDs
and both successful process exits were checked. See `evidence/host-association-43743854538.json`.

Manual selector `HanlinAgentCoreTests/HostAssociation` uses the same proof script with
`HANLIN_SDK_ASSOCIATION_ONLY=1`, excluding the8 unaffected pure schema cases. Those cases retain
their own earlier437426 execution; they did not execute in437438. No aggregate whole-suite pass
or new run on the integration SHA is asserted. All automatic triggers/peer job routes remain
unchanged. Later app composition, `isRunning`, exact fingerprint writer and Split return/UI
changes are not included in this snapshot and have separate outstanding proof obligations.

## Live model/Host binding

Use `HanlinAgentEvent.session` and `runID`, never a mutable currently selected host at callback time.
`onHostResult` receives `HanlinHostResultEvent`: stable dispatcher resultID and original
`call.session/runID/step/providerCallID/invocationID/logicalToolID`. Progress has the same call identity.
Complete account/Space/document/scene/generation binding lives in the canonical session context.
Persisted result identity is metadata; it never grants permission or automatically retries an effect.

Import `HanlinPlatformContracts` for the ONE `HanlinChatStructuredPart` value and `HanlinChatCore`
for its provider bridge extension. Version1 has UUID messageID/partID, message-wide sequence and
typed textDelta or complete a2uiMessage(protocolVersion,json:Data). A new text segment after a Surface
uses its own stable partID; subsequent deltas for an existing part update that part's original position.
The canonical stream validates message order/dedup and stable part kind/protocol version.

The app adapter consumes events outside View.body. For Surface content, register the existing
`HanlinA2UIResultStore.registerModelPart(runID:messageID:partID:sink:)` once, capture its returned
presentation generation and the original SDK context, and feed complete UTF-8 JSON to that key.
**A2UI receive ordinals are per registered part, starting at0.** The SDK sequence is message-wide;
derive the A2UI ordinal by counting that part's unique delivered frames in canonical order. Increment
after every correctly ordered receive, including renderer rejection, matching the existing store's rule.
Do not feed a message-wide sequence directly into A2UI's contiguous per-owner ordinal.
Invalid UTF-8 closes that part rather than inventing replacement protocol bytes.

Call `session.admitInteraction(origin)` only AFTER official A2UI admission. Model bytes alone grant
no action. Route renderer actions with original session/run/message/part provenance to
`continueInteraction`, through the optional host-owned `HanlinHostInteractionSource` admission.
That port validates action/schema/live policy and returns an authorized user-message projection;
business effects still execute through the existing canonical engine/tool authority. Each accepted
action starts a new turn and subsequent events retain interactionOrigin. Request IDs deduplicate actions.

Successful `onRunCompletion(.completed)` maps to A2UI `finishRun` (input EOF, controls remain live).
Cancelled/failed runs seal; `onSessionInvalidated` discards the chat projection. Surface deletion or
replacement calls `revokeInteraction`. No sheet disappearance is interpreted as host revocation.

## Canonical replay

Load the existing `HanlinConversationStore` with its original namespace/conversation. Call
`record.structuredEntries(runID:messageID:)`; entries retain global transcript order and exact typed
parts plus original context. This includes text/Surface interleaving and durable interrupted prefixes.
The read validates version/scope/order/conflicting replay; exact duplicate frames are suppressed.

Rebuild display through the same A2UI store/renderer outside View.body, using a read-only sink and
the deterministic per-part ordinals above. Seal historical projections; do NOT call admitInteraction
or deserialize live authority. A fresh invocation binds a new explicit host context. No second
transcript, message store or renderer is introduced. Format2 records preserve exact parts and result
correlation; format1 stays readable unchanged, with explicit checkpoint/compare-and-restore behavior.

## Apple row and app integration

See `APPLE_APP_MODEL_MAPPING_2026-11-15.md`. `HanlinAppleModelCatalogAdapter.catalogID` is the
canonical AllModels UUID. Startup registration appends one retained row without changing old positions
or saved useModel indices. The existing picker projects the original index only when runtime availability
is available. Default selection explicitly excludes that UUID. The app routes this row before network
API-key validation to the thin FoundationModels provider in the SAME engine, with no tool adapter/fetch.

The exact SDK-enabled picker consumer still requires combined app-target compilation and its actual
ModelPopoverZoomOrderTests/nativeVisibilityKeepsOriginalIndices case. Neither a canImport-false
build nor the catalog component harness proves that consumer. APIManager/startup whole-app compilation,
installed selection/send, XCUITest, eligible native generation and physical device acceptance remain OPEN.

## Production channel support is explicit

Provider adapters must advertise `structuredPartChannel: HanlinChatStructuredPart.channel` before
the canonical engine accepts the declared custom channel. `providerContent()` uses the existing
SwiftAISDK custom event, not prose/fenced JSON. Ordinary cloud/native descriptors currently advertise
nil. The current packages additionally implement the explicit opt-in MODEL Responses contract in
`NATIVE_SCHEMA_MODEL_PATH_2026-11-15.md`; ordinary prose does not acquire Surface authority.
Actual installed app/live-model output remains **NOT_RUN**. Injected/custom-channel and HTTP fixture
proofs do not substitute for the combined enabled application/provider/official-renderer path.

Public contracts and recovery acceptance rules:
`CONTRACTS_WAVE_RESTART_2026-11-15.md`, `VALIDATION_CONTRACT_V2.md`.
The real Hanlin conversation SwiftData/Keychain/attachment/memory adapters, installed Host effects,
signed protection/AppGroups and actual app/UI/device obligations remain open; catalog SwiftData tests
are not evidence for those unrelated data adapters. Anytype/Otzaria remain separate projects.

## Historical integration recovery: private-store ancestor traversal

The earlier integration checkpoint464efc64 took only `HanlinPrivateConversationStore.rejectSymbolicLinks` from
`8b6106ef247f12c8bc6abf1ceaed63d8373223e4`. Lexical ancestor paths now strictly shorten and have
a finite bound; malformed traversal fails closed. No later Host minor, Session, provider schema
or app-owner changes are included. The original checkpoint test and assertions are unchanged.

`StoreTests/versionOneCheckpointCanBeRestoredWithoutDestructiveMigration()` is
**REUSED_VERIFIED_PASS**, originally executed in
[run 43735446863](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43735446863).
Artifact `14170641291`, SHA-256
`cdcc7b0010f71fa6048afa6a0cd487bfd69f016a555776f89d829ff89a916794`, was independently downloaded.
Its source manifest authenticates 33 relevant source/test/manifest/lock files against the original
Git objects. After this backport, their bytes match the tested closure except two unused additions
in `HanlinHostContext.swift`: `hostManagedMutation` and its catalog minor-version guard. Neither
is called by the private-store/checkpoint path; all store protocols, records, errors, namespace,
PlatformContracts and test fixture code match. The original Mac log records save, checkpoint,
second save, restore, restored load and symbolic-link rejection, then a pass in 0.044 seconds.
Environment: Xcode 27.2/27B52, Apple Swift 6.4.2, arm64 macOS 27.0.1/26A434.

This evidence replaces the known checkpoint failure for this specific recovered implementation;
the historical failure remains historical. The test did not execute again on the integration SHA.
No whole-package, app, XCUITest or distribution acceptance is implied.
