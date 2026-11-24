# SDK02: native cancellation 15 PASS, dependency lock qualification BLOCKED

Run [45292176348](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45292176348), attempt 1, executed the 15 authorized current invocations on source e325147a7ecf9f0c728ae524d116b7c6d78379b0 and producer 07431abccbfb151ca2dab67bca6cf86fcb2bd3b8. The original case results are **15 PASS / 0 FAIL / 0 NOT_RUN**, with both native test processes exiting 0. The overall workflow and its strict acceptance summary remain **BLOCKED** because the SDK package's dependency lock changed during Xcode resolution.

The current HanlinAgentCore iOS build actually executed, exited 0, and emitted the original BUILD SUCCEEDED marker. Its pinned-build qualification is **BLOCKED**, not an accepted pinned build: the original verifier correctly rejected the changed post-build lock. This packet preserves the original summary and every selected result without rewriting that distinction.

## Exact current execution

| Original case group | Invocations | Actual result | What was observed |
| --- | ---: | --- | --- |
| nativeInputStaysNormalized(_:) | 2 | PASS | Native normalized arguments retain non-original provenance with approval disabled and enabled. |
| nativeNumericInputCannotReachApprovalOrExecutor(_:_:) | 8 | PASS | Four exact numeric JSON inputs × two approval settings stop before approval/effect and retain providerCalls == 1. |
| nativeNumericStopToolCannotContinueOrReachHost() | 1 | PASS | A rejected native numeric call with finishReason .stop cannot reach host approval/effect or cause another provider request. |
| nativeFrameworkHandoffUsesCanonicalExecutorAndHistory() | 1 | PASS | Two same-name calls keep distinct IDs, use the canonical executor, and continue with correlated results and original system/user history. |
| nativeDenialReturnsThroughCanonicalHistory() | 1 | PASS | Denial has zero host effect and resumes through its correlated tool output. |
| nativeNumericSiblingCannotPartiallyExecute() | 1 | PASS | A numeric sibling rejects the complete batch before any approval, emitted call, or host effect. |
| nativeCancellationStopsAwaitingExecutor() | 1 | PASS | Consumer cancellation and real public executor acknowledgement are both observed; zero effects, approvals, text and tool calls, and final requestCount == 1 remain required. |

The cancellation method passed in 0.18376612663269043 seconds. Its assertions and existing five-second executor acknowledgement deadline are unchanged from the prior failing Bridge5 run. The engine-only StreamStopper/native CallSettings.abortSignal repair from 1b3c4cf0e27683b0af106a8e97b1c7c453062d08 is therefore exercised on the composed 07431 source. It uses the original per-stream cancellation state; the cloud settings path and canonical host-effect authority remain unchanged.

The exact 15 leaf identities, parameter values, unique bound URLs and results are in original/summary.json and the authenticated NativeCoreTests/NativeSDKTests JSON. The two original parameter detail exports come from the same Core xcresult. No old suite, baseline process or upstream producer suite was invoked.

## The actual lock change

| Package | Pre-command lock | Post-command lock | Change |
| --- | --- | --- | --- |
| HanlinPlatform | 8f67ee59e5ba54c1d9bdd312efff89ddc946e00443fef8faddfeb4e7eb5387c8 | Same bytes | None |
| HanlinAgentSDK | b771042794841f2e759cffc68181ca37214794b4fc9c02981a1c86176a9bde83 | ecddc1432961f62d5f8f883e2884fffb6dad193f41867324d9124223c0e44f72 | ZIPFoundation 0.9.19 → 0.9.21 and originHash |

ZIPFoundation changed from revision 02b6abe5f6eef7e3cbd5f247c5cc24e246efcfe0 to e7048f0569f0ba37df26f8357f560b9d25e9a284. SwiftAI 07431, ArgumentParser 1.8.2 and SwiftyJSON 5.0.1 remained exact. This is a real dependency resolution change, not a formatting discrepancy.

The original Core test command resolved ZIPFoundation 0.9.19. The SDK test command already resolved 0.9.21 before its four methods, and the later iOS command also resolved 0.9.21. All original logs and both pre/post raw locks are retained.

A complete parse of the original Xcode target graphs found 73 Core targets, 40 SDK targets and 30 iOS targets, with every declared node and dependency accounted for. The focused test/build closures contain 22, 32 and 30 targets respectively. ZIPFoundation is absent from all three focused closures and absent from the entire SDK and iOS build graphs. The broader Core graph includes it for unrelated ScriptCompiler products. The graph rows, exact closure roots, command output hashes and raw lock differences are in lock-drift-diagnosis.json.

The parent has authorized preparation of an exact ZIPFoundation 0.9.19 requirement and a narrowly guarded fresh iOS build, retaining these unaffected test results. No pin repair or follow-up execution is included in this evidence commit. Resolver-generated origin hashes must come from the actual resolver; no replacement hash has been invented. The original frozen acceptance guard remains unchanged.

## Source-qualified reuse and historical baseline

The original frozen reuse admission accepted 21 product passes separately: CloudCore2 + Schema13 + pure schema/history2 from 45259715158, Authorization rejection1 from 45273580428, direct doGenerate1 from 45282347722, and the two finite cloud .stop continuation cases from 45273687114. They were not executed again here.

The original e7 baseline retains 10 expected native failures and two cloud passes from run 45240721804 attempt 2. It is **HISTORICAL_REFERENCE_ONLY**. No current 07431 baseline equivalence is claimed, and all omitted current process exits are null.

## Evidence custody and limits

Artifact 14877495539 was acquired exactly once: 5,423,867 bytes, SHA256 69a9a0e2a9f7f6671715c09160198bb1c01b85b165d630ce9ced402d9a1ceb83. API run/source/digest/size, every ZIP member CRC/hash, 404 package source hashes, 176 workflow/proof hashes, all 22 command-output pairs and both actual raw locks were verified. The unchanged verifier exactly reproduced the emitted BLOCKED summary.

The sole original ZIP remains in the owner Oracle worktree at build/sdk02-native-cancellation-acceptance/attempt-1. All 232 selected small originals are retained there; 115 xcresult/archive members remain container-only. This committed packet includes the current original JSON/logs/locks plus the outer custody receipts. The 166 frozen reference files are already committed under Scripts/CI/Tests/Fixtures/native-cancellation-07431 and remain unchanged; their artifact copy stays in the retained original folder. Archive and committed-file hash inventories are included.

Both the sole watcher and sole collector have ended. No additional native run or artifact acquisition occurred. All four shipping gates remain closed. These are actual FoundationModels framework controls with a deterministic public LanguageModelExecutor, not execution by SystemLanguageModel. Real system-model generation remains NOT_RUN and requires eligible hardware.
