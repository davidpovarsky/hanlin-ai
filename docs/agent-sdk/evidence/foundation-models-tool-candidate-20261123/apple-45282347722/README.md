# SDK02: original native bridge 4 PASS / 1 FAIL

Run [45282347722](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45282347722), attempt 1, executed the five selected original methods on source 6b0030926cd771f2dd9995fd01aecd1efe8bcf4e and producer e7bf34111e603ca977becd007dd4e5bb109af857. The result is **4 PASS / 1 FAIL / 0 NOT_RUN**, with normal Xcode test-failure exit 65. The current iOS HanlinAgentCore build is **EXECUTED PASS**, exit 0.

## Exact executed cases

| Original method | Actual result | What was observed |
| --- | --- | --- |
| nativeFrameworkHandoffUsesCanonicalExecutorAndHistory() | PASS | Two same-name calls retain distinct IDs; canonical approval/execution and correlated results continue through the original engine. The original system instruction and user history are preserved. |
| nativeDenialReturnsThroughCanonicalHistory() | PASS | Denial has no host effect; its correlated output and the original history resume into final text. |
| nativeNumericSiblingCannotPartiallyExecute() | PASS | The complete generated batch is rejected before approval, tool-call emission or any host effect. |
| nativeGeneratePreservesToolCalls() | PASS | The original provider's direct nonstreaming path preserves the handoff calls. |
| nativeCancellationStopsAwaitingExecutor() | FAIL | The real executor did not acknowledge cancellation within the existing five-second acknowledgement deadline. |

The sole recorded failing assertion is Expectation failed: await state.cancelled at source line 170; duration 5.0972583293914795 seconds. Consumer cancellation, zero host effects, zero approvals, zero text/tool-call events and final requestCount1 have no recorded failure. Those observations do not convert the complete case to PASS, and consumer termination is not physical executor acknowledgement.

Removing historyTransform in ab06b4129e23c8f9ce9c1a4229e72a3d99bbf5d4 is now verified by both complete continuation cases. The unchanged onPrompt guard still removes only the framework-required empty trigger before model input; the complete tests require the exact original user/system history. No private framework callback ordering is claimed.

## Cancellation source diagnosis

The original engine passes no CallSettings.abortSignal. The pinned producer's DefaultStreamTextResult.stop() schedules StreamTextActor.requestStop(). That actor marks external stop, cancels in-flight host tool work and emits an abort, but explicitly keeps streams open until the provider finishes. The native bridge's existing task-group abort watcher is entered only when options.abortSignal is nonnil. The waiting public executor therefore lacks the cooperative cancellation signal from this engine lifetime.

An engine-only repair is being reviewed: expose the existing per-stream StreamStopper flag through a lock-protected synchronous getter and supply it as the appleOnDevice-only abortSignal. No producer, fixture, assertion, deadline or public capability gate is changed by this evidence commit. The repair remains NOT_RUN and is not part of the source tested here. Producer-file hashes and exact original case diagnostics are in diagnosis.json.

## Reuse remains separate

The 27 unaffected product passes from 45259715158 and one Authorization rejection from 45273580428 were separately REUSED_VERIFIED under the frozen bridge source partition. The 12 baseline outcomes remain separately REUSED_VERIFIED: 10 expected native failures and two cloud passes. Current Core and baseline exits are null; neither process was invoked. These reused outcomes are not current executions.

The current iOS build really executed after these five cases, with the exact original HanlinAgentCore build command, both post-build raw locks and original command output hashes retained in terminal-audit.json. It is not reused from an earlier run. The composed producer 07431 proof remains separately attributed to the three original-engine .stop cases in run 45273687114; this packet uses e7bf throughout.

## Original evidence custody

Artifact 14870888736 was acquired exactly once: 116,456,490 bytes, SHA256 da3e823975fd37e07ba030f6da7e7f74321bc62bd189c6e73f7be8fe0d07ec31. API source/digest/size, complete member CRC/hash inventory, 404 package source hashes, 82 workflow/proof hashes, 17 command-output pairs and two actual raw locks were verified. The unchanged strict verifier reproduced the emitted summary exactly.

The selected original JSON, command logs, raw locks and source receipts are committed here. Frozen reference subdirectories remain in the owner Oracle worktree at build/sdk02-native-candidate-acceptance/bridge-recheck-1/original. The sole original ZIP is retained alongside it. A total of 131 small originals were extracted; 1,945 xcresult/archive members remain container-only, with their hashes preserved in archive-members.json.

All four shipping gates stay closed. These are actual FoundationModels framework controls using a deterministic public LanguageModelExecutor. SystemLanguageModel execution remains NOT_RUN, and the previously observed deviceNotEligible hardware restriction remains a separate blocker.
