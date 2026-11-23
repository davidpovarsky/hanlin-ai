# SDK02: fifteen affected native cancellation controls on composed07431

This is a frozen preparation and review packet. No Apple run has been dispatched on this source. All 15 current cases and the dependent iOS build are NOT_RUN.

The actual preceding run45282347722 has four complete bridge PASS cases, one physical cancellation FAIL and a current iOS compile PASS. Its source is6b003092 and producer e7bf. Its original proof remains in the separate docs-only477a8725 packet. That physical cancellation failure is preserved; no assertion, fixture or five-second acknowledgement deadline is weakened here.

## Source composition and cancellation ownership

The isolated stop-continuation branch already contains the accepted07431 dependency, exact f0616 User-Agent-only metadata admission and three original-engine .stop fixtures. It now includes exact source cherry-picks of ab06 (native instructions and separate consumer/executor cancellation observation) and1b3 (per-stream abort propagation). The composed package source is2381719e4a6ed2a2c5520d017980123121fba058.

The engine patch adds a lock-protected read of the existing StreamStopper state and passes that read as CallSettings.abortSignal only for the resolved appleOnDevice descriptor. A fresh stopper is still allocated inside each returned AsyncThrowingStream. It is never stored on the engine or shared with another stream.

| Lifetime operation | Preserved behavior |
| --- | --- |
| Register before stop | Store the result stop callback while locked; subsequent stop takes and clears it exactly once. |
| Stop before registration | The monotonic flag is already true; registration invokes its callback after releasing the lock. |
| Read native abort signal | Read that same monotonic flag under the existing lock; no asynchronous lock operation or new state. |
| Consumer cancellation, normal finish or error | Existing onTermination cancels the engine task and calls stopper.stop. The callback is cleared before invocation. |
| Dynamic-tool continuation | Retain the same stopper for the same returned stream; registration after cancellation immediately stops a newly created result. |
| Another stream | Owns a separate stopper and settings copy, so the first stream cannot cancel it. |

Moving the already-stopped callback outside the lock avoids reentrancy into the new synchronous reader. It preserves the existing register/stop races. The producer API forwards CallSettings.abortSignal through V4 to V3; the bridge's existing abort task group cancels its pending native run when this signal becomes true. Actual executor acknowledgement is still an outstanding native acceptance requirement.

## Exact current execution:15 invocations,7 method groups

| Group | Invocations | Reason to execute |
| --- | ---: | --- |
| Original Core native normalized input | 2 | New native settings enter the original producer for both approval modes. |
| Original Core native numeric rejection | 8 | New native signal can affect termination and provider scheduling; all original providerCalls1/zero-approval/zero-effect assertions stay exact. |
| Engine-backed native bridge | 4 | Allow, deny, numeric sibling and cancellation now enter the bridge's pre-existing nonnil-abort task group. |
| Original native numeric .stop case | 1 | The new native setting reaches the changed continuation-label boundary on07431. |

The first three original Core methods and all bridge bodies remain byte-bound to their accepted source. Parameter invocations retain exact strings, Bool values and unique authenticated xcresult URLs. Every selector uses the authentic Swift signature, including literal parentheses and parameter labels.

The two macOS test processes are named NativeCoreTests (11) and NativeSDKTests (4). A real current HanlinAgentCore iOS Simulator SDK build is required after these cases. No simulator is launched. Original CoreTests, SDKTests, StopContinuationTests, baseline and producer suites are not invoked; their current process exits must remain explicitly null.

## Source-qualified reuse:21 product invocations

| Original evidence | Invocations | Qualification |
| --- | ---: | --- |
| c93 /45259715158 /e7 | Cloud Core2 | Same original nil-abort settings and exact cloud method assertions. The finite fixture never cancels its consumer. Registration precedes its sequential result iteration and every finish/error path, so the moved already-stopped branch is unreachable. |
| c93 /45259715158 /e7 | Schema13 + pure2 | Same schema/history implementations and independent helper bodies; no engine or native runtime-profile entry. |
| 2c41 /45273580428 /e7 | Authorization1 | Same early rejection guard and helper/immutable fixture; rejection occurs before native history/session/profile or engine entry. |
| 6b /45282347722 /e7 | doGenerate1 | Exact provider, bridge, helper and immutable executor fixture. Direct doGenerate aggregates its provider stream and never constructs the engine or producer StreamTextActor. |
| e1a /45273687114 /07431 | Cloud .stop2 | Already executed on07431; unchanged finite no-cancel fixture, nil-abort settings and assertions. The moved already-stopped callback branch is unreachable before registration. |

For cloud Core2, the complete e7→07431 production diff is bound to the one shouldStartAnotherStep method. The fixture emits .toolCalls for its tool step and .stop with no new calls for its final text. Both producer versions make the same continuation decisions for these inputs. It supplies no dynamicTools callback or provider-deferred tools, and its stop conditions are pure. No generalized callback-invocation-count guarantee is claimed for other hosts.

The original e7 baseline12 remains a HISTORICAL_REFERENCE_ONLY packet:10 expected native failures and2 cloud passes. Its exact manifest, original ordinary exit65 and every argument leaf remain authenticated. It is not relabeled as a07431 baseline, and the old strict e7 reuse helper is unchanged.

## Admission and original evidence

The new166-file frozen fixture binds original runs, artifacts, source maps, raw results, command/toolchain outputs, actual locks and exact source snapshots. Its manifest is676dbcdb376fa334925385bf6ce0b17e777cb2b24b74168a3edcd7d5a250c6c0. The complete current404-package-file map must equal the reviewed composed snapshot; each original comparison admits only the explicitly frozen deltas. Both actual producer checkouts must be clean at07431 with complete production-source hashes. Both actual package locks must match the accepted07431 raw locks before and after build; unrelated dependency changes block reuse.

All six Xcode-selection/Xcode/Swift/macOS SDK/iOS SDK/OS outputs must match every original reuse source. Source/workflow Git binding, original result identities, actual current command selectors/logs/exits and the exact15+21 disjoint partition are enforced. The new route explicitly rejects enabling any of the16 unrelated workflow flags.

The old e7 helpers, native32 parser and prior Delta source guard are unchanged. The old Delta guard deliberately rejects the changed source; it is not broadened to claim its earlier execution used this composition. The router adds only the explicit HanlinNativeToolCancellationRecheck selection to the existing07431 runner.

## Local validation and remaining proof

Four new Python report/admission controls passed in0.614 seconds. Their current outcomes are deliberately synthetic fixtures, with original reference packets retained verbatim. They check the15+21 partition and historical attribution, bind selectors to actual original method IDs, reject the old omitted-parentheses bug, reject source/toolchain/producer/lock changes and fake execution/reuse, and preserve the actual physical cancellation FAIL and a missing parameter invocation as failures. No unchanged control suite or Apple test was replayed.

The source patch has independent parent and peer lifetime/locking review. The final route/freeze still requires review before a single native dispatch. Current native execution and iOS build remain NOT_RUN. All four shipping gates remain closed; SystemLanguageModel execution remains NOT_RUN, separately from these public-framework deterministic-executor controls.
