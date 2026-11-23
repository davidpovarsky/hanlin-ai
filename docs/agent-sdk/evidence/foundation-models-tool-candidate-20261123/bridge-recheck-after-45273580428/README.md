# Native profile repair: five affected methods

## Original outcome and corrected source

The original [45273580428 run](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45273580428) executed all five selected Header methods at 2c41a1b7ed6b191be7529550ae1ca4501632ce8d. Authorization rejection and whole-batch numeric rejection passed. Allow and deny each failed only the two original system-instruction assertions. Cancellation failed its immediate consumer-error and executor-acknowledgement observations. Those complete cases remain **FAIL** in the original packet.

Source fix [ab06b412](https://github.com/davidpovarsky/hanlin-ai/commit/ab06b4129e23c8f9ce9c1a4229e72a3d99bbf5d4) removes only the redundant historyTransform and its stale comment. The original onPrompt validates the complete canonical prefix plus the framework-required empty trigger, removes that trigger before model invocation, and retains every original onToolCall guard. DynamicInstructions remains part of the native request. The missing instructions are observed; attributing their loss to the redundant transform is a source-based diagnosis, pending this execution. No private framework event order is claimed.

The cancellation fixture now explicitly checks the cancelled consumer Task after stream iteration. It separately waits, within five seconds, for the actual public executor to acknowledge cancellation. This does not claim a provider-thrown error: AsyncThrowingStream termination and executor acknowledgement are separate observations. All old assertions remain. Added assertions require zero text, zero accepted tool calls and exactly one final executor request.

The public contract references are Apple's [dynamic-session documentation](https://developer.apple.com/documentation/foundationmodels/composing-dynamic-sessions-with-instructions-and-profiles) and [Swift SE-0314](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0314-async-stream.md). Native execution remains necessary to accept the change.

## Affected execution

The existing exact-source Apple job receives the explicit selector HanlinNativeToolBridgeRecheck. Each singleton uses its authentic Swift Testing identity including literal parentheses.

| Current method | Why it executes |
| --- | --- |
| nativeFrameworkHandoffUsesCanonicalExecutorAndHistory() | Failed system instructions; both real requests use the changed profile. |
| nativeDenialReturnsThroughCanonicalHistory() | Failed system instructions; denial continuation uses the changed profile. |
| nativeNumericSiblingCannotPartiallyExecute() | Previously passed but enters the changed profile and the shared consumer helper. |
| nativeCancellationStopsAwaitingExecutor() | Failed observation; changed consumer cancellation control and profile path. |
| nativeGeneratePreservesToolCalls() | Previously passed direct doGenerate also enters the changed run/profile. |

A fresh iOS HanlinAgentCore build is required. The previous compile cannot satisfy the changed production bridge. No simulator launches, Core/baseline processes or other Swift suites are selected.

## Independently qualified reuse

The five current cases are disjoint from these 28 prior passes:

- Core12, Schema13 and two pure native schema/history methods: 27 passes from [45259715158](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45259715158), source c93b966e6c378f56b98d7805b5086a72d3061803.
- Authorization early rejection: one pass from 45273580428, source 2c41a1b7ed6b191be7529550ae1ca4501632ce8d.

The code verifies exactly 402 unchanged package files plus the two specifically reviewed source hashes against each original source closure. It also verifies the complete independent 238-file Platform closure, identical pure helper bodies and discovery wrappers, the byte-identical early settings guard before native history/session/profile setup, the Authorization helper and its immutable fixture tail. This is a dependency and call-path qualification; it is not a claim that all 404 files are unchanged.

The original baseline12 stays separate: ten expected native failures and two cloud passes from attempt2 of 45240721804. Its full overlay, raw lock, producer, exact leaf identities/statuses and toolchain guards remain unchanged. No baseline process runs; its current exit remains null. Core's current exit also remains null.

Each original reference is bound to its authenticated artifact and exact raw result leaves. Current actual locks must match before and after execution. Current native toolchain/OS fingerprints must match the accepted originals. Missing identities, changed inputs, ambiguous status, stale evidence, or an attempted current/reused attribution substitution blocks acceptance.

## Local controls and frozen inputs

The three new report-control methods passed. They are Python fixture controls, not Apple/native passes. They independently compare the emitted five selectors with the actual retained original nodeIdentifier values, reject the earlier Header5 scope and omitted parentheses, and reject changed independent dependencies, altered source snapshots, promoted original failures, omitted current tests, fabricated Core/baseline execution and an absent or falsely reused iOS build.

One existing source-control assertion specifically described the already accepted header-only revision. It is now bound to the authenticated 2c41 source snapshot and its original expected hash, instead of falsely requiring the later cancellation helper to remain unchanged. Only that affected control executed; unrelated historical controls were not rerun.

The plan receipt binds 15 code/proof inputs, the exact request and all 16 unrelated flags set false. The final plan commit must be the immutable dispatch source. A single finite watcher and one selective original-artifact acquisition own the run. Full original ZIPs remain preserved, without duplicate xcresult extraction.

## Limits

The current repair is **NOT_RUN** on Apple until the reviewed dispatch completes and its originals pass all gates. The central shipping native-tool capability remains disabled. Real SystemLanguageModel execution and model tool selection remain NOT_RUN on the observed ineligible hardware. The separately accepted producer07431 three-case delta retains its own source attribution and is not relabeled as this e7 run.
