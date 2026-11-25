# Core48 retained-evidence reuse

**Conclusion:** the retained bounded core proof applies unchanged to target `6fbcf703dd9f40f5b1d42592d58a0a69573dcdfa`. This assessment did not execute tests. The historical Mac run at `04c1942bc88cd4de7deafda7dd342b9b6c401dcf` passed **4 original producer tests plus 44 Hanlin core tests**.

## Exact source closure

| Input group | Recorded and current paths | Result |
| --- | ---: | --- |
| PlatformContracts, including schema resource | 29 | All hashes equal; complete directory membership equal |
| ChatCore | 24 | All hashes equal; complete directory membership equal |
| ChatCoreTests, including unselected suites and helpers | 26 | All hashes equal; complete directory membership equal |
| Canonical HanlinPlatform Package.swift | 1 | Exact bytes equal |
| Original producer fixtures (two files, four executed tests) | 2 | Both hashes equal the execution receipt |
| Original core runner and graph generator | 2 | Exact bytes equal |

The 80-entry canonical inventory has no mismatch against either original or current source, and no omitted/new/removed directory members. The proof symlinks original package sources and creates a separate manifest retaining their original selected targets; it does not substitute production implementations.

## Dependencies and retained execution

The final proof Package.resolved exactly agrees with its receipt and with the corresponding pins in the current Xcode application lock:

| Dependency | Version / revision |
| --- | --- |
| swift-ai-sdk | abf0921c6e89e6521cc2b510ff11016b45a0ef08 |
| opentelemetry-swift-core | 2.6.0 / c6fcee77cfc21ba400366f12475217c7b6e1d605 |
| swift-argument-parser | 1.8.2 / 6a52f3251125d74daf04fcbd5e6f08a75d074382 |
| swift-atomics | 1.3.1 / 0442cb5a3f98ab802acb777929fdb446bda11a34 |

The compressed final log decompresses to SHA-256 `6bf42713f4fbc1fce3d9ac6dac10d094532c8c91f869558b5cd9504a734f40a9`, exactly matching the original receipt. The log contains 48 individual passed-test lines and process totals 4 and 44. The original environment identifies Apple Swift 6.4 (`swiftlang-6.4.0.34.1`, `clang-2100.3.34.1`), arm64 macOS 27, and Testing Library 2084.

Original producer files were independently read from local SDK commit `06cd98dc874a12e56ba8864a2baa20c22363d6c0`, tree `f094f58f7956903e740a5188cf1e9d43c126248e`. The retained publication receipt binds that same tree to published `abf0921c6e89e6521cc2b510ff11016b45a0ef08`. No remote fetch was performed. Earlier failed attempts and the earlier 95b pass remain historical records; the final-pin receipt is the execution evidence used here.

## Limits

- This is read-only reuse analysis, not a new test execution. The 48 passes occurred at original source 04c1942bc88cd4de7deafda7dd342b9b6c401dcf.
- The proof compiled the complete original ChatCore, PlatformContracts (including its schema resource), all ChatCoreTests source files and two original producer fixture files; the filter executed only the affected suites. It did not execute all tests present in those source files.
- The retained proof manifest intentionally omits unrelated iOS/UI targets and uses macOS 26 as its platform. It is not full application, complete HanlinPlatform package, iOS, simulator or UI proof.
- Dependencies are bound by the retained Package.resolved immutable revisions. The receipt does not retain per-file hashes or dirty-state inventories for all downloaded dependency checkouts, generated sources, build intermediates or transitive manifest evaluation inputs. No complete byte-for-byte transitive build attestation is claimed.
- Original Apple Swift and Testing Library version strings are retained; compiler executable, Xcode/SDK binary hashes, full environment and current Mac toolchain state are not part of this receipt and were not inspected in this assessment.
- Published SDK tree equivalence is supported by the retained fresh-GitHub publication receipt and the independently verified local tree and two fixture hashes. The published abf commit object is not present in the inspected local SDK repository; no new network fetch/verification was performed.
- The standalone Packages/HanlinPlatform/Package.resolved does not include OTel or Atomics. It was not the consumed proof lock. The dedicated proof lock and current Xcode application lock agree on all four proof dependencies.
- No live provider cache hit, billing savings, full application run at the target merge or unrelated merged behavior is inferred from this bounded core proof.

## Machine-readable evidence

`core48-reuse.json` records all 80 original/target/hash comparisons, complete membership comparisons, evidence file hashes, actual historical passed-test lines, exact four dependency pins, producer fixture provenance, earlier manifests/receipts and these limits. Repository sources and retained receipts were read from committed Git objects. Only this assigned external evidence directory was written.
