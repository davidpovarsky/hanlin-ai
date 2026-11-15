# Coherent SDK consumer recipe

Consume this branch as one monorepo/local-package source, not a root Git package:
`codex/hanlin-agent-sdk-wave1-20261115`. Public production package bytes are frozen at
`9a864b3c21eaad374c93730d7877addb6726e09d`; subsequent recovery changes only the failed
checkpoint fixture/harness plus an app-only optional-tool lifecycle correction and documentation.
The final delivery commit is recorded in the handoff/evidence, with separate exact tested SHAs.

Keep `Packages/HanlinAgentSDK` and its literal `../HanlinPlatform` sibling. Link the three SDK products
`HanlinHostContracts`, `HanlinAgentCore`, `HanlinPersistenceAdapters` into **AI_Hanlin only**.
MiniApps does not acquire an agent/model engine. No project.pbxproj edits were made in this lane.
Existing app code also retains its existing HanlinChatCore/PlatformContracts dependencies.

Platforms: iOS27/macOS26, Swift tools6.2/language6. Both package manifests and raw locks are EXACT
6e8dd11 integration inputs, pinning the unchanged producer `e7bf34111e603ca977becd007dd4e5bb109af857`:

| Input | SHA256 |
| --- | --- |
| SDK Package.swift | 8a0846341234f25127f1625547cf7c2a0ca23047e32f9ae2d7d9e1c91070029e |
| SDK Package.resolved | 0b190b1d589a67422f7c7847c3a9c70533d89dd82e4ee7589b73836d277ce2f6 |
| Platform Package.swift | 3f8cbcbad6b07b509a7976fe0577315481f25358ce34a01e505f2d1b04821066 |
| Platform Package.resolved | 7882ef847a4aaa1bfa2ee128122393cf718f393485d9658bb93f402f740f2c17 |

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
nil: **real production structured-model output is UNSUPPORTED/NOT_RUN**, not claimed from fixtures.
The rich custom-channel cases prove an injected provider path through the real core/Session/store.
Connecting an actual production response path requires an explicit adapter/negotiated backend channel
or a schema-backed presentation-output tool in the same canonical tool loop, plus provider-wire/model proof.

Public contracts and recovery acceptance rules:
`CONTRACTS_WAVE_RESTART_2026-11-15.md`, `VALIDATION_CONTRACT_V2.md`.
The real Hanlin conversation SwiftData/Keychain/attachment/memory adapters, installed Host effects,
signed protection/AppGroups and actual app/UI/device obligations remain open; catalog SwiftData tests
are not evidence for those unrelated data adapters. Anytype/Otzaria remain separate projects.
