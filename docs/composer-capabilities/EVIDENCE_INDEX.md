# Composer capabilities: validation evidence

This is an evidence checkpoint through source `37a788a4a10a293653e307c05ba1a507d518d1f0`, assembled in an isolated documentation branch based on `189ca0d73a8f9b92451d343ca84b4b7074c57c6c`. Overall completion is **pending**. Each receipt retains its original execution source; assembling this packet did not run a compiler, tests, or a simulator.

The [validation plan](VALIDATION_PLAN.json) records the remaining gates. The [machine index](EVIDENCE_INDEX.json) lists results and their receipt paths. [Packaging metadata](evidence/package-20261125.json) maps copied files to their original paths and checksums; [SHA256SUMS](evidence/SHA256SUMS-20261125) covers the packaged evidence.

## Executed results

| Lane / attempt | Actual execution source | Actual result | Evidence |
|---|---|---|---|
| SDK iOS attempt 3 | `a3aae0b952b0518cb8c40ed4a511d4cffadab99f` | 11 passed, 0 failed, 0 skipped on iPhone 17 Pro Max / iOS 27.0 | [xcresult receipt](evidence/sdk-ios-a3aae0b95/receipt.json), [case tree](evidence/sdk-ios-a3aae0b95/tests.json) |
| Platform attempt 1 | `a27e1a36e1272e17413c283ad928916f0489c1b5` | 25 passed, 4 failed out of 29; retained as the original codec/path failure | [receipt](evidence/platform-attempt1-a27e1a36e/composer-platform-tests.json) |
| Platform attempt 2 | `a3aae0b952b0518cb8c40ed4a511d4cffadab99f` | 31 passed, 0 failed, 0 skipped | [receipt](evidence/mac-validation-20261125/composer-platform-attempt2-tests.json) |
| Platform attempt 3 | `0bf5a16789952cdd07a2a6431ae010211679466a` | 47 passed, 3 failed out of 50; the three fixtures omitted their schema dialect | [receipt](evidence/platform-attempt3-0bf5a1678/composer-platform-attempt3-tests.json) |
| Platform attempt 4 | `6a3c194a1951aa8394c76efcb6e100e76ade56c2` | Capacity-interrupted; **zero cases executed**, six not run | [corrected receipt](evidence/platform-attempt4-6a3c194a1/composer-platform-attempt4-tests.json), [original automation report](evidence/platform-attempt4-6a3c194a1/composer-platform-attempt4-original-execution-report.json) |
| Platform attempt 5 | `f54aebbb35169ea63eca146a1ba3ef4e8bf4f84d` | Six affected methods passed, 0 failed, 0 skipped | [receipt](evidence/platform-attempt5-f54aebbb3/composer-platform-attempt5-tests.json) |
| RuntimeHost final attempt 1 | `6a3c194a1951aa8394c76efcb6e100e76ade56c2` | Exit 1: the manifest audit lacked the integrated ExpoAsset plugin mapping | [receipt](evidence/mac-validation-20261125/runtime-host-final-attempt1.json) |
| RuntimeHost final attempt 2 | `f54aebbb35169ea63eca146a1ba3ef4e8bf4f84d` | Packager exit 0; 177 Node tests passed, 0 failed, one existing opt-in long test skipped; packed ZIP validation and JITless probe passed | [receipt](evidence/mac-validation-20261125/runtime-host-final-attempt2.json), [complete compressed log](evidence/mac-validation-20261125/runtime-host-final-attempt2.log.gz) |
| RuntimeHost final attempt 3 | `37a788a4a10a293653e307c05ba1a507d518d1f0` | After exact `@types/react@19.3.1` lock integration: exit 0, 177 passed, 0 failed, the same one existing opt-in skip; actual archive hash reverified | [receipt](evidence/runtime-host-final-attempt3-37a788a4a/runtime-host-final-attempt3.json), [complete compressed log](evidence/runtime-host-final-attempt3-37a788a4a/runtime-host-final-attempt3.log.gz) |
| App preparation / A2UI | `f54aebbb35169ea63eca146a1ba3ef4e8bf4f84d` | Both original source generators passed their checks; original A2UI schema generator executed successfully | [receipt](evidence/mac-validation-20261125/app-preparation.json), [A2UI result](evidence/mac-validation-20261125/a2ui-schemas.json/result.json) |

### Platform coverage is aggregated

The Platform checkpoint covers **51 unique methods: 45 verified prior passes plus six methods actually executed in attempt 5**. There was no single 51-case test run. The six final methods include the three previously failed fixtures, two affected existing Expo plugin checks, and the new ExpoAsset version check. The 45 retained methods have original passing case identities and unchanged relevant assertions/dependencies documented in the [reuse assessment](evidence/platform-attempt5-f54aebbb3/reuse-assessment.json). The [full four-file Platform impact diff](evidence/platform-attempt4-6a3c194a1/composer-platform-attempt4-impact.diff) is retained.

The original reports and raw logs remain authoritative. Files named `.derived.junit.xml` are explicitly log-derived summaries. They are not relabeled as native XCTest or Swift Testing reports. Attempt 2 also includes the separately named original Swift Testing XML output discovered during packaging; its original receipt is unchanged.

### SDK execution and reuse boundary

The SDK receipt verifies all eleven actual method identities across token queries, UIKit drafts, custom-panel provider bindings, and numeric editing. Its raw `.xcresult` remains on the Mac at the location in the receipt; this repository contains the exported summary, case tree, bundle-file hashes and losslessly compressed build log.

The macro build failure was corrected by using the aggregate package test scheme and destination-only simulator selection. The passing compiler invocation built the macro for `arm64-apple-macos12.0` using the macOS SDK. No dependency pin update was used to obtain the pass.

The [checkpoint applicability record](evidence/applicability-37a788a4a.json) distinguishes unchanged SDK sources from the unrelated generic app-descriptor/action-ID changes in the shared contracts. It does not substitute these SDK tests for app integration, native editor, engine, or UI execution.

### RuntimeHost artifact freshness

The latest successful RuntimeHost retry at `37a788a4a` produced an 81,837,535-byte archive with SHA-256:

`043f27b7c8b884c3095c97a99672d58bcf2ba7a1df5276ce8eaefa7eeae1e9d9`

Its uncompressed raw log SHA-256 is:

`c2657aebf954ae63ea467fa2fa696b409f304024d2bb6951c39315d0f44eac9f`

The one skipped case was `actual Node job crosses 300 seconds with no hidden deadline`, the existing opt-in long test. No new skip was introduced. Source `f54aebbb3` plus its four generated SDK documentation changes became checkpoint `189ca0d73`; the original execution source is still recorded as `f54aebbb3`.

**Archive freshness passed at `37a788a4a` after the exact `@types/react@19.3.1` lock and application-fixture integration.** Attempt 3 took 103.584 seconds. The transfer independently hashed the actual Mac archive and matched its 81,837,535 bytes and receipt digest. Attempt 2 remains recorded at `f54aebbb3`, with its own archive and raw-log hashes preserved. Native artifact provenance integration and all application/native/editor/UI gates remain pending with the root owner.

## Required work still pending

| Gate | Exact pending scope |
|---|---|
| Application compilation | Two Debug `build-for-testing` schemes: `AI_HLY` and `HanlinMiniApps` |
| App selection / storage / policy integration | 13 methods: six composer integration, five MiniApp assistant-tool, one original Skill policy and one prepared Expo discovery method |
| Original native engines | Four `HanlinUnifiedHostServicesE2ETests` methods |
| Native UIKit editor regressions | Four selected `NativeComposerLineSizingTests` methods |
| iPhone UI | Three composer-capability UI methods plus the existing model-picker/draft regression |
| iPad UI | The same three composer-capability UI methods |
| Native artifact integration | Complete root-owned artifact provenance integration and consumer application build validation |
| Separate manifest-contract audit test | Reconcile its historical source-specific receipt with final inputs; the current RuntimeHost inventory audit already passed |

The UI inventory is **seven executions across two devices**, comprising four distinct methods. The catalog/map fixture supplies UI metadata only; it does not provide a tool executor or a fabricated model response.

SDK passes, dependency artifact reuse, source-generator checks and the Node host tests do not establish successful application builds, native engine execution, UI gestures, full CI, or physical-device behavior.
