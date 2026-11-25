# NativeScript parity: actual attempt 11 PASS

The original parity selector **passed, with zero failures and zero skips**, on Git source `318b251b11a4816eb9cc3c1337c7bfe287f4a890`. The actual case lasted **96.358 seconds**; its native command finalized successfully at **2026-11-25 03:12:43.598356 UTC**. This is the corrected shipped fixture using the existing asynchronous completion APIs, the exact runtime-title identifier, and the published first-use Node wait inside the unchanged 420-second case allowance.

The executed case checked real JSC, Node 24.5.0 and CPython 3.14.6 outputs with its nonce, network response, inter-app echo, private storage, close/relaunch and persisted state. The finalized xcresult nodes and selected-test log confirm that the requested selector executed. All six retained runtime jobs (initial and relaunch JSC, Node and Python) completed with exit 0, no timeout/cancellation, and the same challenge nonce.

## Exact execution identity

| Input | SHA-256 |
| --- | --- |
| Shipped parity archive, 7,512 bytes | `2e48509336edba2b301490422102dbf25cb7f1b894430d52994febdc1c33c199` |
| Shipped/source bundle, 25,868 bytes | `5f21796994e3880ba5d5c9f0e6d23b3fa12a667ff6082183f604d214a61284b1` |
| Exact published UI test source | `995e98e35d5f4f464c3b83062b136b14f74c7445c040d2118baffd3bcaea9052` |
| Reused SDK10 Host archive | `86733eba5d80156edf52da87f0f371c208122d6e60f618f182990330514984c3` |

All six members of the shipped fixture archive match the exact Git source bytes. The original paired runner hash is unchanged. The source-advance receipt retains the actual prepared working-file state, so this checkpoint does not imply that generated prepared outputs were clean at the execution Git HEAD.

## Cold readiness and presentation

The actual active container was observed without the Host `.ready` file. That same container created it at **03:12:13.909465 UTC**, **28.297883 seconds after the first RUN_MAIN_BEGIN**. This is an observed interval, not an isolated unzip measurement. The first module/main evaluation returned in **55.337 ms** and relaunch returned in **89.125 ms**. Those evaluation times do not mean all asynchronous work had completed.

The reconciler independently viewed the verified-runtime and relaunch PNGs. The first shows all five runtime/network/inter-app rows verified; exact untruncated nonce values are in AX and jobs. The relaunch frame shows persisted state and several verified rows, with Node still Pending at that visual checkpoint. A completed second Node job is separately retained; no timing of the visual Node label update is inferred. The original case's actual assertions passed.

## Preservation and boundaries

The untouched handoff receipt `ce57c1eab185d65c2034faa9cb4a19bf6f9e3ff005c93e05c6539858c1492b8c` binds **59 members / 3,480,952 bytes**, all retained byte for byte. Its existing runtime-stream gzip round-trips losslessly to **681,146 bytes**, SHA-256 `cb8b9b93385f4f574f99e6b9af3ec25762f639bd2b235abfd321ec766a360da0`. All ten attachments listed in the exported attachment manifest are retained; the full xcresult bundle is not copied.

[reconciliation.json](reconciliation.json) contains exact source/fixture bindings, member checks, case result, runtime jobs, timing, attachment and scope details. [raw/receipt.json](raw/receipt.json) is the unmodified producer receipt. The observer records `sampleTaken=false`; cleanup records the owned simulator shut down and no owned runners.

The [attempt10 failure](../primary-parity-startup-diagnostic-attempt10-20261125/README.md) remains unchanged historical evidence. This pass applies to the corrected parity source. The [separate remaining-focused result](../primary-remaining-focused-diagnostics-attempt10-20261125/README.md) and Modular correction are outside this case. The original **25 + 27 acceptance run remains NOT_RUN**. No native query, build, test, generator or SDK repack was performed during this evidence reconciliation.
