# FoundationModels invocation bridge review — 2026-11-23

## Status and scope

**Original executor access is available. Lossless model-round ownership is the remaining unestablished contract.** This review does not justify changing `HanlinAppleOnDeviceProvider.supportsTools` to `true`. No production source, public API, tests, native runs or consumer locks changed.

Reviewed Hanlin source: `8538287fc7f17af6a5b2a0e7333ffed356b64a9a`. This is a bounded architecture review of two concrete handoffs, not a new engine implementation or a claim that all future public FoundationModels APIs are incapable of supporting one.

The installed interface receipt is from native run `45112778130`, Hanlin `e33247fb`, Xcode 27.2 (27B52), iOS Simulator SDK 27.2. The retained declaration excerpt is 60,798 bytes, SHA-256 `812d8f15063b0e8fa2573568ee84eee86344d17a3c81c2383a35dd26df27938c`. That receipt says **DECLARATIONS_READ**, **availability NOT_QUERIED**, **modelExecution NOT_RUN**. Its excerpts are not a complete copy of every public declaration.

Oracle receipt: `/mnt/development/projects/hanlin-sdk-artifacts-20261123/native-run-45112778130/hanlin-foundation-models-interface/receipt.json`; declarations alongside it. The existing SwiftAISDK review at producer `e7bf34111e603ca977becd007dd4e5bb109af857` is reused without replay: `/mnt/development/projects/evidence/hanlin-sdk-ui-20261123/AppleProvider/provider-executed-contract/review-receipt.json`.

## 1. An engine-injected executor can preserve the existing authority

The relevant source already provides the actual closures; recovering them from V3 call options is unnecessary:

| Existing source | Actual contract |
| --- | --- |
| `Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinAISDKModels.swift`, `HanlinAISDKToolDefinition` | Public main-actor async throwing executor, optional provenance executor, input schema and `requiresApproval`. |
| `Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinAISDKAgentEngine.swift`, `stream` and `makeTools` | The engine receives the definitions and the original approval callback before it converts them into SwiftAISDK tools. Its existing wrapper performs input correlation/provenance handling and projects the result envelope. |
| `Packages/HanlinAgentSDK/Sources/HanlinAgentCore/HanlinAgentSession.swift`, `makeDefinitions` | The executor captures the current run, original catalog and model. It validates input, persists a pending invocation before dispatch, calls the original dispatcher, then retains the correlated result receipt. |
| `Packages/HanlinAgentSDK/Sources/HanlinAgentCore/HanlinHostDispatcher.swift`, `dispatch`/`invalidate` | Invocation identity is scoped to session/run/provider-call ID. Reservation precedes the host call; cancellation and uncertain effects retain the original rules. The host retains permission, durable idempotency and native effect authority. |
| `AI_HLY/Downstream/ChatCore/HanlinAppToolConsent.swift` and `HanlinAppAgentSessionOwner.swift` | Original consent suspends with a deadline and cancellation handler. Revocation resolves pending consent, and the owner invalidates the same session. |

An explicitly bound native invocation context could therefore await the original definition executor. It must never call a second dispatcher or invoke a host action directly. For definitions requiring provider approval, it could await the existing engine approval callback; the app callback already validates the actual session and generation. Host-owned consent is a distinct check inside the original host path and must remain there.

The current host-generated definitions leave `requiresApproval` at its default `false`; they rely on the original Host authority. That is not a reason to remove approval for other public engine clients.

Apple's public [Tool.call contract](https://developer.apple.com/documentation/foundationmodels/tool/call(arguments:).md) is async throwing and permits concurrent invocations. A callback may therefore await original consent and execution, but this signature alone does not establish propagation of FoundationModels task cancellation to a pending tool. An explicit bound context would need its own revocation and owned-task cancellation, alongside the existing session invalidation. Late results must still fail the original session/run checks.

### Concrete change boundary if this route is developed

The binding protocol belongs in `HanlinChatCore`: `HanlinAgentCore` already depends on it, so a reverse dependency would be inappropriate. The existing engine would create a context for the actual stream/request, using the actual prepared aliases and original definitions. Shared input/result handling must be extracted from the existing wrapper, not copied into the Apple provider. Native JSON reconstructed from `GeneratedContent` must retain `.normalized` provenance, never claim the original raw-input proof.

For this explicit native binding only, SwiftAISDK-facing tools would have to be observation-only while the bound context owns approval/execution. The ordinary tools path remains unchanged. This is a design boundary, **not an implemented or accepted API**. It resolves closure ownership; it does not resolve the round boundary below.

## 2. The native internal loop is not the current Hanlin step contract

The current engine awaits `prepareStep(globalStep)` at `streamText.prepareStep` before every SwiftAISDK model request. This updates active aliases and loaded skill instructions, emits the original step event, and sets `HanlinAgentSession.step`. Stop conditions enforce an explicit `maxSteps`; dynamic catalog changes are checked at those same step boundaries. The session executor captures that step before dispatch.

A FoundationModels session can execute tools and generate subsequent model responses inside one `streamResponse` call. Simply injecting the executor would leave all those native rounds inside one outer SwiftAISDK step. It would not automatically rerun Hanlin's asynchronous preparation, reload the catalog, enforce the original model-step budget, or emit correct step identities.

Public iOS 27 [DynamicInstructions](https://developer.apple.com/documentation/foundationmodels/dynamicinstructions.md) reevaluate their synchronous body before model requests. The retained interface also exposes async `onPrompt`, `onToolCall` and `onToolOutput` profile callbacks. The reviewed [profile documentation](https://developer.apple.com/documentation/foundationmodels/composing-dynamic-sessions-with-instructions-and-profiles.md) does not establish an awaited **complete-round** hook that corresponds one-for-one to Hanlin's asynchronous `prepareStep`, including concurrent tool batches. Calling preparation for each individual tool output would change a model-step budget into a tool-count budget and could advance the step while sibling tools are still running.

The [onPrompt documentation](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/dynamicprofile/onprompt(perform:).md) describes a pre-generation callback; the inspected contracts do not specify its exact invocation count for internal tool-output continuations or its ordering relative to dynamic-instruction evaluation. That missing guarantee is material, not proof that the callback can never support the requirement. These dynamic-profile APIs are also iOS 27 additions, whereas the original native provider's text path uses iOS 26 APIs.

The [tool calling modes](https://developer.apple.com/documentation/foundationmodels/generationoptions/toolcallingmode-swift.struct.md) control whether tools may, must or may not be called. They do not define a one-native-round return mode. Treating native internal iterations as one Hanlin step, adding a separate loop, or silently dropping `prepareStep`/skill behavior would not preserve the existing SDK contract.

## 3. Capture the call, stop before execution, then use the unchanged executor?

This alternative has a useful goal: let Apple choose a tool, return a canonical V3 tool call with `.toolCalls` finish, then allow the unchanged SwiftAISDK step/approval/executor path to run it. The next request would use the original canonical history. No native tool should execute a host action in this variant.

The reviewed public interfaces do not yet establish a lossless handoff:

| Required property | Public evidence and remaining boundary |
| --- | --- |
| Exact native call identity | `Tool.call(arguments:)` has arguments, but no transcript call ID or batch token. The iOS 27 `onToolCall` callback receives one `Transcript.ToolCall`; associating separately concurrent callbacks by equal name/arguments is not a safe identity rule. |
| Complete concurrent batch | [Tool](https://developer.apple.com/documentation/foundationmodels/tool.md) permits concurrent calls. [Transcript.ToolCalls](https://developer.apple.com/documentation/foundationmodels/transcript/toolcalls.md) is a collection; the inspected public contract has no sealed/completed-batch marker. One callback throwing does not prove all model-chosen calls were captured. |
| Error versus successful model stop | [ToolCallError](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/toolcallerror.md) retains an underlying error, so a deliberately thrown error can be distinguished. It still represents a failed native response, not a documented successful tool-request handoff. |
| Transcript completeness after interruption | Apple's [preserveTranscript policy](https://developer.apple.com/documentation/foundationmodels/transcripterrorhandlingpolicy/preservetranscript.md) explicitly permits the final retained entry to be partially generated. Keeping the transcript does not complete an interrupted batch. `GeneratedContent.isComplete` describes a content value, not all members of a tool batch. |
| Exact arguments | [GeneratedContent](https://developer.apple.com/documentation/foundationmodels/generatedcontent.md) exposes structured content and a JSON representation. Reserializing that value is not the original raw-input byte proof. The existing numeric/input guard must remain active with normalized provenance. |
| Canonical result replay | [Transcript](https://developer.apple.com/documentation/foundationmodels/transcript.md), `ToolCall` and `ToolOutput` have public constructors. They permit constructing known entries; they do not recover omitted batch members. The current Apple adapter rejects tool history and requires a final prompt, so canonical tool-response continuation is not implemented. The reviewed [response API](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/respond(options:prompt:).md) does not document resuming an interrupted batch merely by adding an empty/repeated prompt. |
| Cancellation and late callbacks | A cancelled or malformed native response must remain an error with no host execution. A callback arriving after the bridge is revoked cannot be promoted to a successful tool batch. No reviewed contract supplies a complete-batch barrier on cancellation. |

Consequently, catching the first sentinel error, collecting whichever callbacks arrived and returning `.toolCalls` would manufacture success from an unproven partial batch. Waiting a fixed time for more callbacks or guessing correspondence from argument equality would not repair the contract.

The public iOS 27 `SystemLanguageModel.Executor`/generation channel was also checked as a possible lower boundary. The installed excerpt exposes a public channel initializer and async sequence, but its `Event` and action structs expose construction factories rather than a public discriminator/payload extraction API. The current [Event documentation](https://developer.apple.com/documentation/foundationmodels/languagemodelexecutorgenerationchannel/event.md) agrees. Reflection/private access cannot turn that into a supported V3 decoder.

## Remaining requirement and implementation status

A safe next implementation needs either:

- A documented native **single completed model round** handoff with complete call IDs/arguments, success/error/cancellation separation and canonical tool-result continuation; or
- A coherent existing-engine binding with a documented awaited native round boundary, preserving the original asynchronous preparation, dynamic tools/skills, explicit step budget and session/event identity.

This review establishes executor/approval access and the required change boundary. It does **not** establish either full orchestration contract. Native tools therefore remain explicitly unsupported in the current provider, with rejection before native tool execution; `supportsTools` and `supportsToolUse` remain false. Existing text-only behavior is unchanged. Eligible-device tool/consent/cancellation acceptance remains unperformed and must not be inferred from interface reads, other providers, simulator builds or this document.

## Source binding

At reviewed Hanlin commit `8538287fc7f17af6a5b2a0e7333ffed356b64a9a`:

| File | SHA-256 |
| --- | --- |
| `HanlinChatCore/HanlinAISDKAgentEngine.swift` | `aaf8ae687d478710c2b4388f19350164a606facd02b70375743c808629cbe524` |
| `HanlinChatCore/HanlinAISDKModels.swift` | `c8e0ecfdda95960195c3454f76d35fa5bd6c48c08781e920d39903157416eb92` |
| `HanlinAgentCore/HanlinAgentSession.swift` | `179e222f04e185d941c0f42416f6df6d391cf308bd79b63af341093c460d1e1b` |
| `HanlinAgentCore/HanlinHostDispatcher.swift` | `8c7289779a6cce63dd58bb43a3ba877abfba357680609dc38c2dbd8cd8b738a1` |
| `Downstream/ChatCore/HanlinAppAgentSessionOwner.swift` | `0c36a379b5f81cac0722871709153f00e7c71673ae66ef923def95f66fa44883` |

No production/test execution was performed for this review. Only read-only source/interface/documentation inspection and this documentation commit were performed.
