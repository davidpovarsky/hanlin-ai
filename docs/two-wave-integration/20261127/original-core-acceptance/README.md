# Verified original core acceptance — 2026-11-27

These are source-qualified technical results for the two-wave Hanlin/MiniApps candidate. They do not close app/system, physical-device, account-backed, signing or delivery gates.

| Original gate | Actual source | Actual result | Retained packet |
| --- | --- | --- | --- |
| Unfiltered macOS package | `1ee9c45796f41893c3b59745864de3412c17ddb4` | 603 starts, 603 terminal results, 603 PASS, zero failures/skips; 13 target summaries | `original-macos603.tar.gz` |
| Original Host/SDK producer, all 12 phases | `1ee9c45796f41893c3b59745864de3412c17ddb4` | 188/188 PASS, zero failures/cancellations/skips; actual long-job duration 305030.465584 ms | `original-host188.tar.gz` |
| Original selected native iOS package | `b723338e995b14dc31f96a90ad4c865e8a4b345a` | 58 definitions, 79 invocations, all PASS; 28 parameter invocations, no missing/extra/skipped results | `original-ios79.tar.gz` |
| Original complete CI discovery, infrastructure attempt | `1ee9c45796f41893c3b59745864de3412c17ddb4` | 477 discovered; 10 PermissionError errors, 2 original skips, zero assertion failures; FAILED | `original-ci477-infrastructure-failure.tar.gz` |
| Original complete CI discovery, repaired infrastructure | `1ee9c45796f41893c3b59745864de3412c17ddb4` | 477 discovered; 475 PASS, 2 original skips, zero failures/errors | `original-ci477-pass.tar.gz` |
| Original complete CI discovery with additive notification controls | `f43c3bb60f98e65b8061b08285612f7ceacc46bf` | 491 discovered; 489 PASS, 2 original skips, zero failures/errors | `original-ci491-pass.tar.gz` |

## Source and original-contract qualification

The macOS run was unfiltered and uninstrumented, from 12:29:37 to 12:32:21 UTC. The original HTTP method and its five-second per-execution budget were preserved. The causal Promise ownership repair passed both original lifetime controls and the complete original package. Parameter rows are not added to the 603 reported-test count. The normalized reconciliation excludes only framework run headers and the terminal reporting suffix for parameterized tests; it does not change native outcomes.

The Host run completed all 12 original phases from 12:39:09 to 12:45:20 UTC. All 32 original test files and their 99-file source/test closure remained unchanged. The prepared complete closure before and after tests is byte-identical. Root verified all 41 declared proof members and every one of the 392 recorded SDK input blobs against Git.

The resulting SDK input fingerprint is `0a9d3ca8f320af72485cab3d998be4861c1d858fe758c5f79e7b15d555937c50`; the manifest SHA-256 is `e7aa424015d509dc7d99b3158b85f6dbcbcc72fc17b3671d247382331e87e649`. The canonical Host ZIP is 81,901,035 bytes with SHA-256 `d83702acbcc7ce22f672a2c1952a6f3623606cda227fdc27172a03dc1caf5f42`. The ZIP remains with the original producer; this packet preserves its authenticated producer/verification evidence, not another binary copy.

Commit b723 seals exactly three producer-generated SDK documents. Product, package, test, fixture and producer trees remain unchanged from the executed 1ee9 source. The causal delta changes three of 392 inputs relative to the last accepted Host226 source; it changes four relative to diagnostic778 because the temporary Fetch instrumentation is restored to its original accepted bytes.

The native iOS build-for-testing passed from 12:56:46 to 12:59:11 UTC; test execution passed from 13:00:00 to 13:01:03 UTC. The actual owned device was an iPad Pro 13-inch (M5), iOS 27.2, on the iPhoneSimulator SDK platform. It was not an iPhone. The original baseline accounts for 57 definitions/78 invocations, plus one existing regression. Both original xcresult bundles and descriptor/source evidence are retained. Root independently verified all 275 declared members.

The first CI477 attempt failed because the exact ignored build parent was root-owned. The correction changed only that parent's owner to the established build user, retaining group, mode and child state. Original source, tests, command and environment were unchanged. The failed receipt and all raw output remain retained beside the successful rerun. Both successful CI runs preserve the original unstaged Expo-artifact and explicit real-network opt-in skips. Neither skip receives native acceptance credit.

The f43 notification changes touch test/runner/workflow/proof paths outside all 392 SDK inputs. They do not invalidate the source-qualified core results above. Notification OS acceptance and the other native app gates require their own actual executions.

## Lossless evidence retention

Each archive contains the exact original declared files and its original packet manifest, or the exact original CI output/controller files. Every member has an adjacent inventory recording its path, byte count and SHA-256. Archive header metadata is normalized for transport; original file bytes are unchanged. Every compressed archive was read back and all member byte counts/hashes were reconciled before publication.

The three independent root reviews are retained as separate JSON files. The preparation receipt records nine archives totaling 8,224,740 compressed bytes. It was written before Git publication, so its preparation status is historical. Raw Asana requirement snapshots and private consumer-owner operational audits are excluded from this public technical packet.

## Remaining boundaries

These core results do not establish original app54/extra26, original90, production25, notification/system/authoring OS acceptance, runtime-loaded image origin, ReleaseAI_HLY/Shell/MCP, consumer adoption, physical-device/account coverage or signed delivery. Those gates keep their original source, selectors, assertions, pins, time budgets and independent outcomes.
