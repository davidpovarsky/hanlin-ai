# SDK callback and structured-part contract

This revision supersedes the old two-argument `onHostResult` preview. Host API major 1,
iOS 27 / macOS 26, Swift 6. Canonical producer remains e7bf34111e603ca977becd007dd4e5bb109af857.
The four package manifest/lock inputs are imported byte-for-byte from authenticated
integration 6e8dd11dc5c6be78f04d787890b8e09b799631a3; no alternative core or dependency graph.

## Host result consumer

Import `HanlinAgentCore` and `HanlinHostContracts` from the existing nested package.
`session.onHostResult` receives one `HanlinHostResultEvent`:

- `call.session`: original session ID, conversation and complete host context, including generation.
- `call.runID`, `call.step`, `call.providerCallID`, canonical `call.invocationID` and `call.logicalToolID`.
- `resultID`: dispatcher-owned UUID assigned once at reservation, stable on duplicate receipt delivery.
- `result`: canonical host outcome and effect receipt, validated against the originating context and invocation.

`onHostProgress` receives `HanlinHostProgressEvent` with the same immutable `call` and canonical progress.
Step is captured before the first executor suspension. Callback data never reads a replacement active run.
`HanlinAgentEvent.session` provides the same binding for model stream events. An invalidated session is terminal;
late committed receipts remain in the original journal and do not deliver presentation callbacks.

The consumer creates its own presentation generation and binds it to these original values.
Run finish seals action authority; a historical receipt does not authorize an action. UI disappearance
is not host revocation. Queued navigation still does not mean an actual scene was mounted.
No second renderer, UI registry, model selection UI or permission authority is introduced.

## Model structured parts

Canonical public type: `HanlinChatCore.HanlinChatStructuredPart`, file
`Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinChatStructuredPart.swift`.
Version 1 carries stable `messageID`, `partID`, message-wide `sequence: UInt64`, and typed payload
`.textDelta(String)` or `.a2uiMessage(protocolVersion: String, json: Data)`.
The latter holds a complete official protocol message; admission/validation/rendering stay with A2UI.

An explicit model/provider adapter calls `part.providerContent()` and emits that value as the EXISTING
`LanguageModelV3StreamPart.custom`. Channel kind is `hanlin.chat.part.v1`; metadata is
`hanlin.part`, a Base64 string of the versioned Codable envelope. Exact integer sequences survive
the provider's Double-valued metadata representation. The canonical engine emits
`.structuredPart(part)` in source order on its SAME event stream. It never searches prose,
Markdown or fenced JSON for protocol content. Cloud adapters do not automatically gain this capability.
Unknown custom channels stay outside this channel; malformed declared channel data fails explicitly.

`HanlinChatStructuredPartSequence` validates strict per-message order. An exact duplicate is suppressed;
changed replay at the same sequence or unseen older sequence is rejected. Codable reconstruction
replays through the same validator, with no grants or execution closures. Create a new validator
for each originating run. Default SDK transcript storage still persists metadata/references only;
the authorized host must supply a content store before claiming durable structured-payload replay.

The app's existing APIManager switch currently refuses this new event explicitly. A2UI owns the
actual presentation bridge at that SDK adapter case; until it is connected, app inline rendering is OPEN.

## Affected validation plan

Changes: HostContracts event DTOs; dispatcher identity reservation; Session callbacks; canonical
ChatCore structured channel and finish criterion; existing SDK adapter switch. Transitive consumers:
all Session/Context/Store package tests and all canonical injected-provider/provider-factory/engine tests.
Execute these on actual Xcode plus iOS AgentCore compilation. The existing exact-source harness
is reused with contracts-only selection. New manual workflow has no automatic triggers.

Prior run43688388938 SDK10 cases are invalidated by changed contracts/session; run43686294717
Core20 cases are invalidated by changed core engine/models. Producer48 cases are unchanged inputs
and not rerun; original proof remains separately attributed, not claimed as newly executed or verified
reuse for a changed environment. UI/XCUITest/device/native FoundationModels execution are NOT_RUN
by this package-only validation. Earlier fixture proofs do not close those obligations.
