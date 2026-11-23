# Original resource-copy scan PASS; localization gate FAIL

Run [45256955142](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45256955142), attempt 1, compiled source `0b40a021c6d28e4d1c47ed87060d063c8456ba9f` with producer `e7bf34111e603ca977becd007dd4e5bb109af857`. The producer run is **FAIL**. This packet preserves the actual native resource-scan result and the remaining localization gate. It does not qualify the later 07431 producer adoption.

| Scope | Actual result | Original evidence |
|---|---|---|
| Full arm64 app and test build | PASS, 20:23:39–20:34:06 UTC | Native job and authenticated original build-log digest |
| Current build-for-testing products | PASS, 20:34:06–20:34:08 UTC | SEALED descriptor, source/run binding, five product-file hashes |
| Runtime app signature | PASS | Original codesign output: valid on disk and designated requirement satisfied |
| Original AI_Hanlin copied-resource scanner | PASS | Two identical bundle inventories; all 37 copied-resource byte checks; zero errors |
| Canonical localization table selection | FAIL, 20:34:08–20:34:19 UTC | 177 missing-or-ambiguous table errors, catalog values 3683, packaged values 0 |
| Requested app acceptance | NOT_RUN | Simulator boot, test suite and runtime launch skipped; 32 scopes, 342 authored expected invocations remain unexecuted |
| Native18 publication | BLOCKED | Prepared artifact 14858299149 belongs to a failed producer; not acquired or published |

## Actual bundle ownership evidence

`original/07-simulator-sdk-bundle-resources.json` reports the app-root `HanlinSDK_AI_Hanlin.bundle` and the same-named copy under `Frameworks/HanlinApplication_3ED3A7D0B493F0DF_PackageProduct.framework`. Each has 49 complete inventory entries and 45 files. Both inventory SHA256 values equal `4f2efaf63079fa86b52ccbd718a52f551a892186f53e3ccb766e53c52427287f`. The unchanged canonical copied-resource checks also passed for all 37 resources. This is actual native execution of the reviewed duplicate-copy ownership fix.

The independent read-only source comparison in `copied-resource-source-binding.json` matches 35 resource records to the exact immutable source commit. The generated diagnostics record matches the retained same-run original receipt. The generated RuntimeHostResources ZIP is not inside the assigned smoke artifact: its same-run byte equality is reported by the original CI scanner, without an independent archive rehash claim here.

The separate localization scanner still assumed one shared localization bundle. Its original output records 177 instances of the same selection error across Localizable/RuntimeLocalizable and en/he/zh-Hans. Root's later scanner repair is outside this frozen run. No translation-runtime acceptance is inferred from catalog parsing or from a future source fix.

## Source and execution limits

The original current-products descriptor is hash-bound (`SEALED`), not a cryptographic signature. Its build-log, diagnostics, resolved-lock and xctestrun hashes were checked against the assigned original files. Actual binary bytes are absent from this smoke ZIP, so this review does not independently rehash the five binaries/plists listed by the CI guard. Xcode may reuse validated compiler products. The descriptor explicitly records a modified tracked runner workspace and its diff hash; no pristine or full-cold-build claim is made.

The smoke ZIP was acquired exactly once by this lane: artifact **14860023107**, **5,098,802 bytes**, SHA256 **f659bec8fe284616e3ee323d0f2a37e5bd1749440551fe70bc8fc128d12438db**. Its GitHub source/run metadata, complete ZIP digest, CRC and unique safe member paths were verified before extraction. The full original build result remains at the acquisition path in the receipt. The parent's 25,538,449-byte original job log was reused, not downloaded again. The narrow packet retains exact original JSON/log files and numbered raw-log excerpts.

No new tests, simulator run, watcher, app launch, Host pin change, prepared-native download or publication occurred during this evidence review. `performance-summary.json` has zero metrics and is not performance acceptance.
