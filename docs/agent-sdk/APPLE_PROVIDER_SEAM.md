# Apple on-device provider — narrow integration proposal

Status: DOCUMENTATION_RESEARCH / implementation and installed-SDK validation NOT_RUN.

Owner addendum scope is one manually selectable `Apple Intelligence — On-Device` row in the existing model list, available only when the device's default system model reports ready. It uses the same Chat/Agent/Composer/tool authority as other providers. No separate picker, routing manager, automatic cloud fallback, PCC, AppGroup, API key or companion app.

## Inspected existing path

- `AI_HLY/Model/AllModels.swift`: SwiftData model catalog entries with stable UUID, provider/name/display/visibility/capability fields.
- `AI_HLY/ChatView.swift:150–167`: `modelTemp` is populated from existing AllModels storage; current model selection is an array index.
- `AI_HLY/Downstream/ChatInput/HanlinModelPickerPopover.swift:14–61`: existing picker consumes `[AllModels]`, `selectedModelIndex` and callback. Visibility/search/grouping use existing entries and `isHidden`.
- `AI_HLY/Downstream/ChatInput/OrganizerDock/HanlinCompactChatWorkspace.swift` and session bridge consume that same model representation; they must not gain a competing catalog.
- `HanlinAISDKProviderFactory.swift`: currently selects four cloud families; shared provider resolution feeds HanlinAISDKAgentEngine/SwiftAISDK.
- `HanlinChatModelConfiguration.swift`: requires endpoint and key fields in the current data shape. Local selection must bypass remote credential requirements explicitly; empty/local metadata must never accidentally resolve as OpenAICompatible HTTP.

All app/picker/core source remains read-only until an exact owner lease. Maya owns picker integration; the core provider seam needs its own lease. No new implementation has been added here.

## System facts researched

Apple documents `SystemLanguageModel.default.availability` as the readiness check and distinct unavailable states, including unsupported device and model not ready. The code-along also shows Apple Intelligence disabled. `SystemLanguageModel` is documented as Observable, so the proposed UI seam should observe the current system instance and refresh at the existing scene/picker lifecycle boundary; no invented polling service is needed. Availability must also be rechecked immediately before generation. See [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel), [availability guidance](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models), and [Apple code-along](https://developer.apple.com/events/resources/code-along-205/).

`LanguageModelSession.ResponseStream` produces snapshots of partial content. An adapter to delta-based consumers must emit only the added suffix, detect inconsistent/non-prefix revisions explicitly, and never append every cumulative snapshot as new text. [ResponseStream documentation](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/responsestream).

Apple's `Tool` is Sendable, has runtime `parameters: GenerationSchema`, and accepts `ConvertibleFromGeneratedContent` arguments; tools may run concurrently. `GeneratedContent` exposes a JSON string and can be used as a dynamic argument representation. `GenerationSchema(root:dependencies:)` accepts dynamic schemas. These facts support investigating a thin provider adapter, but do not prove every JSON Schema dialect/keyword, tool policy or provider event can be preserved automatically. See [Tool](https://developer.apple.com/documentation/foundationmodels/tool), [GeneratedContent](https://developer.apple.com/documentation/foundationmodels/generatedcontent), and [GenerationSchema construction](https://developer.apple.com/documentation/foundationmodels/generationschema/init(root:dependencies:)).

The documented session is single-request-at-a-time. Context, supported languages, images, generation settings, guardrails and dynamic schema limits must be checked against the actual installed SDK/model variant. Current online docs include APIs newer than the deployment baseline; documentation availability is not an installed SDK compile. Do not promise reasoning, token accounting, image support, per-token tool arguments or arbitrary schema features until supported and verified. Any unsupported request returns a clear typed error without switching provider.

## Proposed small seams

1. Core exposes one stable local model identity and current availability/reason derived from SystemLanguageModel.default. Existing catalog/picker owners map it into the current list exactly once when available. Availability is runtime state, not a user preference to persist as permanently available.
2. Preserve model identity across list refresh, not just the old array index. If a selected Apple model becomes unavailable, remove it from available choices, preserve draft/history and show an explicit unavailable state for that selection. Sending must fail clearly until the user makes a valid manual choice; do not silently select a cloud entry at a shifted index.
3. Provider factory resolves this identity before any cloud URL/API-key path. The adapter conforms to the existing pinned provider interface and normalizes supported text/tool/error/cancel events into the existing stream. The existing agent loop remains the only orchestration owner.
4. Determine the correct native-tool/SwiftAISDK handoff using the pinned provider interfaces and installed FoundationModels SDK before implementation. Native sessions can execute tools internally; blindly nesting their tool execution inside SwiftAISDK could duplicate execution or bypass its step policy. Tool calls must reach the same HostIntegration executor exactly once, with explicit correlation and host authority. This is an implementation question, not a proven design outcome.
5. Duplicate/unsupported schemas and content fail before execution. Progress/results/cancellation use existing host contracts; no model output grants permission. Concurrent native tool callbacks require host-safe idempotency and transaction validation.

## Acceptance still required

- Eligible physical iOS 26+/27 iPad: current picker contains exactly one conditional row, manual selection, actual local generation, cancellation, streaming as supported and authorized host tool/result UI.
- Unavailable/off/downloading/ineligible states: row absent; other providers keep behavior and selection identity.
- Availability lost after selection: explicit error, preserved draft/history, no automatic cloud request.
- Native schema/content/settings errors, cancellation and correlation tests through the same engine/host boundary.
- App-independent import/run without Hanlin installed; Anytype real host and Otzaria future adapter accepted separately.

No tests, native compiler, simulator or device checks were run for these cases. Documentation is not native acceptance.
