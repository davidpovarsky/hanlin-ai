# Notification OS resource recovery — SDK19

This packet retains the actual uncharged v4 resource-preflight rejection and the subsequent removal of three task-owned, reproducible compiler/index caches. It records preparation for the original single notification OS case. The OS execution and delivery result belongs to its separate terminal packet.

The tested consumer source remains `d4a0b115b106d4250ea40ad66153d5156847a07c`; the SDK producer remains `a2c8a1b1be746461272ba77254603304567c309d`. The source, worker, UI test, original test/worker time limits and cumulative active-time accounting were not changed by this recovery.

## Actual rejection, with no active-time charge

At 2026-11-25 19:32:41.912811 UTC, sealer7 exited 1 because the observed free space was **5,106,081,792 bytes**, below an inherited **7,852,293,846-byte** bound for two earlier test groups. The seal command lasted 5.902149457993801 seconds, but no decision, native output directory or controller phase was created. The retained rejection is explicitly `SEAL_RESOURCE_REJECTED_UNCHARGED`.

The independent rejection observation at 19:33:58.417673 UTC reported 3,507,855,360 free bytes. These are separate global disk observations. The primary record remained SHA `73de5a617bfb057fe56e5767296ba847c1e56ff6756a647ff0569b06a815c255`, with active elapsed time 24,674.060430753034 seconds. The two earlier OS charges still total 366.5287689999968 seconds, leaving 533.4712310000032 seconds of the original separate 900-second allowance.

## Approved calculation for the one remaining case

The root-approved calculation retains the complete measured product/runner installation allowance and both 500 MB reserves. It uses one Host recreation, one worst historical result and one full worst historical diagnostic export for the one selected OS case.

| Component | Earlier two-group bound (bytes) | Single OS case (bytes) |
|---|---:|---:|
| Retained-device new allocation | 0 | 0 |
| Whole product/runner installation allowance | 2,505,814,016 | 2,505,814,016 |
| Host recreation | 713,731,370 | 356,865,685 |
| Worst historical result | 2,309,439,488 | 1,154,719,744 |
| Full worst historical diagnostic export | 1,323,308,972 | 661,654,486 |
| Temporary authoring workspaces | 500,000,000 | 500,000,000 |
| Concurrent activity and OS reserve | 500,000,000 | 500,000,000 |
| **Total** | **7,852,293,846** | **5,679,053,931** |

The retained actual v1 OS sample occupies 149,803,008 allocated bytes for its result and 149,975,040 allocated bytes for its exported diagnostics. The approved calculation continues to reserve the larger historical bounds above. The fresh free-space gate remains in place in both the sealer and controller.

## Actual owned-cache retirement

The native owner removed exactly these three directories under the task's existing DerivedData directory:

| Relative directory | Allocated bytes before removal |
|---|---:|
| `Build/Intermediates.noindex` | 2,760,409,088 |
| `ModuleCache.noindex` | 890,769,408 |
| `Index.noindex` | 202,231,808 |
| **Total measured allocation** | **3,853,410,304** |

The receipt records all three removals, no overlap with protected paths, and **816 unique protected hashes matching before and after**. Both the primary SHA and prepared source-diff SHA are unchanged. Build/Products, the existing xctestruns, SDK, original result bundles, diagnostic evidence and SourcePackages were outside the removed paths. The 87 compiler input-list copies (44 Mini and 43 AI) remain retained in the existing Oracle source-impact packet; this packet references that authority without duplicating those files.

During the cleanup observation, global free space changed from **7,489,654,784** to **11,292,880,896 bytes**. The difference is **3,803,226,112 bytes**. This global change includes concurrent system activity and is not attributed entirely to the cache removal.

## Separate import-only diagnostic

The optional raw import-verification record concerns the preceding v3 `SPLIT_EVIDENCE` module-import failure. On Oracle, the original helper reproduced the missing-variable error; the corrected helper loaded the unchanged original runner with an absent and a present variable and restored the original environment in both cases. Commands were disabled and bytecode writes were disabled. This verification executed zero native commands, product tests or builds and wrote no source.

## Contents and provenance

Four raw JSON records are copied byte-for-byte into `raw/`. `manifest.json` records the scope, calculation, original source identities and external evidence references. `receipt.json` binds every other file in this seven-file folder by size, SHA-256 and mode.

The assembler performed only Oracle evidence reads, hashing and copying. It did not execute the prepared sealer/controller, alter a checkout, run a test/build or perform another cleanup. Historical failed and uncharged attempts remain explicit in their raw records.
