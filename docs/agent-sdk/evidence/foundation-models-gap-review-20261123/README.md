# Native FoundationModels tool and continuation review

## Scope and disposition

Read-only review at Hanlin source `8429dbb6cb66e266504b8d055586829ba7aa61f7`, against the owner addendum and the 2026-11-23 SDK02 comments in task [1220542419128390](https://app.asana.com/0/0/1220542419128390). The source manifest binds every inspected production file. No production behavior changed, no model ran, and no Apple test was repeated for this review.

**Source review: PASS. Native tool adapter: BLOCKED / not implemented. Eligible-device model acceptance: NOT_RUN.** The current text-only provider is an explicit partial implementation. Preserving that limitation is honest compatibility behavior; it does not complete the required native tool integration. The existing engine, host permissions, identity, and numeric provenance contracts remain the required authority.

## The actual production route

The existing picker uses `HanlinAppleModelCatalogAdapter.catalogID`, projects the native row only when `HanlinAppleOnDeviceProvider.availability == .available`, and retains stable stored array indices. The model is registered once so saved identity remains stable when availability changes. `HanlinDefaultChatPolicy` applies actual native availability only to a new conversation's initial selection; it does not rewrite an existing selection.

`APIManager` constructs the native configuration and injects `HanlinAppleLanguageModel` through `HanlinAppleOnDeviceProvider.makeEngine` into the original `HanlinAISDKAgentEngine`. Native transport is not a network provider. The older `AppleFoundationModelsProvider` has no production callsite outside its own declaration file in the reviewed tree, so repairing that legacy type would not finish this route.

Four production boundaries currently enforce the partial support:

| Boundary | Current behavior | Necessary coordinated change |
| --- | --- | --- |
| Shared provider | `supportsTools = false`; rejects nonempty tool definitions and `.tool` history; only text assistant parts; requires a final user prompt | Project native tool calls into the existing provider event contract and reconstruct supported call/result history |
| Catalog adapter | Validates `supportsToolUse == false` | Advertise only a capability that the native adapter and runtime actually support |
| Original APIManager | Rejects a native selection when `toolAdapter != nil` | Route supported native calls through the same original tool adapter |
| Shared engine preflight | Requires every native message part to be `.text` before prompt conversion | Admit specifically supported call/result parts while retaining rejection of image/media content before downloads |

The original engine already maps definitions to its one tool executor, correlates approvals, checks accepted raw input against the parsed value, and emits tool results. A FoundationModels `Tool.call` implementation must not independently invoke the host dispatcher or duplicate those effects.

## Authenticated installed SDK evidence

The failed primary producer [45218713371](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45218713371), source `7f6a960eb341e3a6642db390d4b5de0b2e3448fc`, produced the declaration-only artifact [14839273585](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45218713371/artifacts/14839273585). The artifact was downloaded through authenticated GitHub API; ZIP CRCs and declared bytes were verified. Its failure does not invalidate the installed public interface as read-only API evidence, but does disqualify the producer for native asset publication.

- Xcode 27.2, build 27B52; iPhone Simulator SDK 27.2.
- Public arm64 simulator interface: 217372 bytes, SHA256 `7d29c5b8e1aa76f8b362f2b17f3b29e87418ff4f730822c3f725aa41989bed14`.
- ZIP: 7215 bytes, SHA256 `00dec5b2773b6e7c063c35e695b9c8063974a192eb1f3effdf6ba80d57f68e04`.
- Excerpt: SHA256 `812d8f15063b0e8fa2573568ee84eee86344d17a3c81c2383a35dd26df27938c`.
- Receipt explicitly says model execution `NOT_RUN`, availability `NOT_QUERIED`.

The installed SDK declares the system executor, generation request/channel, native tool-call lifecycle callback, mutable transcript, and history transform. Its qualified names use `FoundationModels::`, while the old capture also relied on dot-qualified extension needles. This omitted the exact `ToolCallingMode`, tool/transcript schema, and generated-content declarations needed to implement against that installed SDK. Capture-only commit `8373e095126f9815df131aa0bcd19c694c8e63ed` expands the existing bounded public-declaration capture. It does not execute a model, claim hardware eligibility, or require a separate native run.

## Public API findings and implementation boundary

Apple documents only `allowed`, `required`, and `disallowed` [tool calling modes](https://developer.apple.com/documentation/foundationmodels/generationoptions/toolcallingmode-swift.struct). Required mode continues native tool calling until a tool throws or a dynamic profile changes the mode. There is no documented manual-return-only mode in that enumeration.

Apple's [dynamic profile lifecycle documentation](https://developer.apple.com/documentation/foundationmodels/composing-dynamic-sessions-with-instructions-and-profiles) says the tool-call hook runs before the framework invokes the tool, and an error propagates to the response caller. Its [history transform](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/dynamicprofile/historytransform(_:)) supplies the model's history immediately before model invocation without rewriting the stored transcript. These are promising public seams for a single-generation adapter; they are not evidence that the proposed bridge already works.

The smallest credible implementation candidate is confined to the existing native provider and these existing admission boundaries:

1. Map supported canonical tool definitions into native parameter schemas without silently weakening constraints. Explicitly reject unsupported schemas and settings before model execution.
2. Use a native pre-execution hook to capture completed tool calls and end that generation before any native `Tool.call` performs a host effect. Preserve the transcript while handling only the adapter's exact internal handoff marker; propagate unrelated errors normally. Preserve native call IDs, names and complete argument values.
3. Emit the existing `LanguageModelV3` tool-call events and tool-calls finish reason. The original Hanlin loop then obtains approval, applies the host context/lease checks, and executes at most once through the existing executor.
4. Reconstruct assistant call and tool-result entries with matching IDs on the next canonical provider invocation. A tool-result-only continuation needs a proven public way to present exactly that history to the native model. A profile history transform may provide this seam, but acceptance must prove there is no added user instruction, repeated prior prompt, or lost role boundary in actual model input.
5. Keep cancellation scoped to the original turn, prevent late delivery after cancellation, and preserve original consent/receipt and next-turn behavior. Do not enable `supportsTools` until the connected route and runtime gates are proven.

A direct `SystemLanguageModel.Executor` shortcut remains unproven: the captured channel `Event` is opaque and its public declarations expose factories rather than a text/tool payload discriminator. The [generation channel documentation](https://developer.apple.com/documentation/foundationmodels/languagemodelexecutorgenerationchannel) describes sending provider output into the framework. Neither that description nor an `AsyncSequence` conformance proves a supported inverse decoder. Reflection or private API is not a substitute.

Native argument provenance is a separate hard boundary. Apple exposes [GeneratedContent](https://developer.apple.com/documentation/foundationmodels/generatedcontent) and its JSON representation; the [numeric kind](https://developer.apple.com/documentation/foundationmodels/generatedcontent/kind-swift.enum/array(_:)) is `number(Double)`. Re-serializing those values is not proof of the originally generated numeric spelling or precision. The current canonical numeric guard must keep rejecting unsupported/unverified numeric arguments; the adapter must not stamp such re-serialization as accepted original model JSON. A limited, explicitly documented string/bool/null schema subset can be considered only if all advertised constraints and host checks are preserved. General numeric tool parity would remain open.

## Required native eligibility and acceptance

Declaration capture and simulator compilation are compile/API evidence only. A real native acceptance gate must record actual `SystemLanguageModel.default.availability` and, on SDK27, the model's tool capability, OS/device identity, exact SDK source, and the original native selection. Unavailable or model-not-ready means BLOCKED, not PASS or fake availability override. The owner requires on-device execution; no network provider fallback or Private Cloud Compute can qualify it.

On eligible hardware, test the actual original engine/session/provider chain with a bounded non-destructive host tool and actual native model generation: text streaming and cancellation; one proposed tool call; zero host execution before approval; allowed execution exactly once; denied execution zero times; exact call/result identity; continuation into a final native response and a subsequent ordinary user turn; cancellation during the tool handoff with no late effect/delivery; multiple tool calls and unsupported schema/numeric rejection. Receipts must distinguish model availability, invocation, host execution, and final continuation. Existing deterministic guard tests may be reused only for unchanged source; they cannot stand in for native model execution.

The currently dispatched primary run predates the capture extension. It must not be cancelled or repeated solely to collect more declarations. Include the extension in the next necessary Apple run. Release preparation retains priority once a qualifying native producer succeeds.
