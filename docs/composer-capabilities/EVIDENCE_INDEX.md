# Composer capabilities: validation evidence

This evidence packet includes native preparation at `7b7f7e4460200d7e98162dd525d67f8ca1860911`, RuntimeHost preparation at `cd795e378afed5c7556a71e26e5247da9ff22869`, and two failed application builds at `20fb9f71146aec19acd3a7f9802a1fbe9fe7fe91`. It also records the focus-property correction integrated at `e5a3e6d9216a69552b2b25a096fd3f3fcf8e2876`, without a successful build after that correction. The isolated documentation branch is based on `189ca0d73a8f9b92451d343ca84b4b7074c57c6c`. Overall completion is **pending**. Original execution sources and results remain unchanged; this packaging work ran no compiler, tests, or simulator.

The [validation plan](VALIDATION_PLAN.json) records the remaining gates. The [machine index](EVIDENCE_INDEX.json) lists results and their receipt paths. [Packaging metadata](evidence/package-20261125.json) maps copied files to their original paths and checksums; [SHA256SUMS](evidence/SHA256SUMS-20261125) covers the packaged evidence.

The dedicated manifest regression, native artifact preparation, and completed RuntimeHost retry are recorded separately below. They reconcile their respective gates without relabeling the earlier SDK or Platform executions. The existing shared-test applicability assessment remains scoped through `37a788a4a`; this follow-up does not extend that claim to a new source revision.

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
| RuntimeHost final attempt 4 | `cd795e378afed5c7556a71e26e5247da9ff22869` | After original native resource generation: exit 0 in 96.647s, 177 passed, 0 failed, one unchanged opt-in skip; ZIP validation and JITless probe passed | [receipt](evidence/runtime-host-final-attempt4-cd795e378/runtime-host-final-attempt4.json), [complete compressed log](evidence/runtime-host-final-attempt4-cd795e378/runtime-host-final-attempt4.log.gz) |
| Original native preparation | `7b7f7e4460200d7e98162dd525d67f8ca1860911` | Original preparer exit 0; 15 frameworks and four support groups validated; consumer acceptance tests remain pending | [preparer receipt](evidence/native-preparation-7b7f7e446/expo-current-cached-preparation.json), [validation receipt](evidence/native-preparation-7b7f7e446/native-preparation-final.json) |
| Final manifest-contract regression | `7b7f7e4460200d7e98162dd525d67f8ca1860911` | One passed, zero failed/skipped; exit 0 in 0.618s at 2026-11-25 00:35:34.980179 UTC, including changed embedded-plugin identity and new source-authority rejection cases | [receipt](evidence/manifest-final-7b7f7e446/manifest-final-test.json), [complete compressed log](evidence/manifest-final-7b7f7e446/manifest-final-test.log.gz) |
| AI_HLY build-for-testing attempt 1 | `20fb9f71146aec19acd3a7f9802a1fbe9fe7fe91` | Exit 65 after 330.678s; copied SwiftShims PCM retained the producer ModuleCache path. No acceptance tests executed by this build command | [receipt](evidence/app-build-attempt1-20fb9f711/ai-hly-build-attempt1.json), [xcresult errors](evidence/app-build-attempt1-20fb9f711/ai-hly-build-attempt1-errors.json), [complete compressed log](evidence/app-build-attempt1-20fb9f711/ai-hly-build-attempt1.log.gz) |
| AI_HLY build-for-testing attempt 2 | `20fb9f71146aec19acd3a7f9802a1fbe9fe7fe91` | Exit 65 after 261.208s; two compiler errors reject the private stored `focused` property. No acceptance tests executed by this build command | [receipt](evidence/app-build-attempt2-20fb9f711/ai-hly-build-attempt2.json), [xcresult errors](evidence/app-build-attempt2-20fb9f711/ai-hly-build-attempt2-errors.json), [complete compressed log](evidence/app-build-attempt2-20fb9f711/ai-hly-build-attempt2.log.gz) |
| App preparation / A2UI | `f54aebbb35169ea63eca146a1ba3ef4e8bf4f84d` | Both original source generators passed their checks; original A2UI schema generator executed successfully | [receipt](evidence/mac-validation-20261125/app-preparation.json), [A2UI result](evidence/mac-validation-20261125/a2ui-schemas.json/result.json) |

### Platform coverage is aggregated

The Platform checkpoint covers **51 unique methods: 45 verified prior passes plus six methods actually executed in attempt 5**. There was no single 51-case test run. The six final methods include the three previously failed fixtures, two affected existing Expo plugin checks, and the new ExpoAsset version check. The 45 retained methods have original passing case identities and unchanged relevant assertions/dependencies documented in the [reuse assessment](evidence/platform-attempt5-f54aebbb3/reuse-assessment.json). The [full four-file Platform impact diff](evidence/platform-attempt4-6a3c194a1/composer-platform-attempt4-impact.diff) is retained.

The original reports and raw logs remain authoritative. Files named `.derived.junit.xml` are explicitly log-derived summaries. They are not relabeled as native XCTest or Swift Testing reports. Attempt 2 also includes the separately named original Swift Testing XML output discovered during packaging; its original receipt is unchanged.

### SDK execution and reuse boundary

The SDK receipt verifies all eleven actual method identities across token queries, UIKit drafts, custom-panel provider bindings, and numeric editing. Its raw `.xcresult` remains on the Mac at the location in the receipt; this repository contains the exported summary, case tree, bundle-file hashes and losslessly compressed build log.

The macro build failure was corrected by using the aggregate package test scheme and destination-only simulator selection. The passing compiler invocation built the macro for `arm64-apple-macos12.0` using the macOS SDK. No dependency pin update was used to obtain the pass.

The [checkpoint applicability record](evidence/applicability-37a788a4a.json) distinguishes unchanged SDK sources from the unrelated generic app-descriptor/action-ID changes in the shared contracts. It does not substitute these SDK tests for app integration, native editor, engine, or UI execution.

### Native artifact preparation and generation provenance

The original `Scripts/Expo/prepare-ios-dependencies.mjs` preparer completed with exit 0 at `7b7f7e446`. The final validation receipt records **15 frameworks and four support groups**. Its [complete raw log](evidence/native-preparation-7b7f7e446/expo-current-cached-preparation.log.gz) confirms that the exact original ExpoUI and ExpoAsset producer builds were reused and verified; ExpoModulesJSI was built from original source for device and simulator in 56 seconds. The original Widgets Metro bundle, NativeAPI code generation, metadata verification and artifact audit also passed.

The [preparation assessment](evidence/native-preparation-7b7f7e446/preparation-assessment.json) retains the earlier guarded attempts without interpreting them as acceptance-test results:

| Preparation attempt | Recorded outcome | Interpretation |
|---|---|---|
| Initial byte reuse | Original status `FAILED`; zero staged records | Export prerequisite missing: original Python host support was not yet prepared |
| Attempt 3 | Original status `FAILED`; ten records retained | Transfer stopped at the Libffi tracked-header preservation guard |
| Attempt 4 | Original status `FAILED`; fifteen records retained | Transfer stopped before replacing the generated Widget receipt |
| Attempt 5 | Frameworks verified; Widget refresh pending | Framework transfer and byte checks completed; the subsequent original preparer supplied the Widget refresh |
| Original preparer / final validation | Exit 0; 15 frameworks, four support groups | Artifact preparation passed; application and native-engine acceptance remain separate |

The [producer metadata receipt](evidence/native-preparation-7b7f7e446/native-producer-cache-metadata.json) records restoration of ten byte-identical producer manifests that the portable SDK export excludes. It preserves the original producer paths and hashes.

The [generation provenance](evidence/native-preparation-7b7f7e446/generation-provenance.json) verifies that commit `47643864a8ac380f3d2e3a962ae7a8b144517a16` changes **one generated Widget receipt file, exactly two fields**: `inputSHA256` and `packageLockSHA256`. Every other JSON field is unchanged. Its original Git patch is preserved with lossless compression. Inventory-freeze commit `20fb9f71146aec19acd3a7f9802a1fbe9fe7fe91` changes only three generated source-revision lines in the SDK inventory/reachability documentation.

### RuntimeHost artifact freshness

After native generation, the source inventory check passed, while the old RuntimeHost archive correctly rejected the stale staged SDK: `MiniApp SDK differs from current host source inputs`. Both [source-check logs](evidence/native-preparation-7b7f7e446/post-native-source-check-1.log.gz) and the [stale-archive diagnostic](evidence/native-preparation-7b7f7e446/post-native-source-check-2.log.gz) are preserved. This was an artifact freshness failure, with no application or UI test execution.

The original RuntimeHost packager then completed attempt 4 at `cd795e378` in 96.647 seconds. Its **177 passing Node tests, zero failures, one existing opt-in skip, packed ZIP validation and JITless archive probe** are preserved in the completed receipt and raw log. The transfer independently matched the actual 81,837,518-byte Mac archive to SHA-256:

`16006101892548001b64e4a8167e27e910f5e907a7af296ef8786d4850811120`

The uncompressed attempt-4 raw log SHA-256 is:

`0530855aa61515628b1caf7ce8a38a222e64fdb5e74a354c8cc04845c8e91996`

The one skipped case was `actual Node job crosses 300 seconds with no hidden deadline`, the existing opt-in long test. No new skip was introduced.

**Archive freshness passed at `cd795e378` after original native resource generation.** Earlier attempts 2 and 3 retain their actual 177-pass results, sources and archive hashes. The generated source-revision metadata was subsequently frozen in `20fb9f711`; no new test execution is attributed to that metadata-only commit.

### Application build attempt 1 and isolated cache repair

The first `AI_HLY` Debug `build-for-testing` attempt ran at `20fb9f711` from 2026-11-25 01:04:51.837629 UTC to 01:10:22.514325 UTC. It exited **65 after 330.678 seconds**. Both the original raw log and exported xcresult issue summaries report that the copied `SwiftShims` precompiled module contains the original producer's absolute ModuleCache path, followed by `Missing required module 'SwiftShims'`. The failed compiler target was `ChavrusaChatNotificationService`. This is a recorded compilation failure; the build-for-testing command did not execute acceptance tests.

The [build assessment](evidence/app-build-attempt1-20fb9f711/build-assessment.json) links the original [APFS cache-copy receipt](evidence/app-build-attempt1-20fb9f711/derived-cache-reuse.json), exact compiler diagnostics, and [repair receipt](evidence/app-build-attempt1-20fb9f711/app-build-attempt1-cache-repair.json). At 01:15:16.954023 UTC the root owner moved only this task's isolated `ModuleCache.noindex` aside for regeneration. The repair receipt records no source changes and no changes to another owner's cache. It does not claim a successful recompilation.

The [historical retry admission snapshot](evidence/app-build-attempt1-20fb9f711/app-build-admission.json), observed at 01:21:53.348228 UTC, records waiting under the superseded admission policy. The [policy-refresh receipt](evidence/app-build-attempt1-20fb9f711/app-build-capacity-policy-refresh.json) records stopping only the owned waiting Python process, with an empty child-process list and no compiler. The root owner refreshed admission to use the current measured memory/disk policy. **This waiting-runner cancellation is orchestration, not a build or test failure.** The [earlier admission race-resolution receipt](evidence/app-build-attempt1-20fb9f711/app-build-admission-race-resolution.json) separately preserves removal of a duplicate waiting process while the first compiler remained active.

The [actual attempt-2 process receipt](evidence/app-build-attempt1-20fb9f711/ai-hly-build-attempt2-process.json) records an `xcodebuild` start at **01:23:17.863531 UTC**, PID 15399, at the unchanged `20fb9f711` source with `-jobs 2`. At the evidence capture of 01:25:39.507812 UTC no completed attempt-2 receipt existed. A process start does not establish a successful build; all application/native/editor/UI gates remain pending.

The complete 13,619,832-byte attempt-1 raw log is losslessly compressed; its uncompressed SHA-256 is:

`8638ebde19ff53fbd8564aa1613d726a06bf4503f96a30f4ca09ea94924e61fe`

The original `.xcresult` remains at the Mac path recorded in the build receipt. A [seven-file bundle hash inventory](evidence/app-build-attempt1-20fb9f711/xcresult-sha256.json) and original exported issue summaries are preserved here. Packaging this evidence performed no native compilation, test or simulator operation, cache repair, or application-source mutation.

### Application build attempt 2 and integrated focus correction

Attempt 2 completed at **01:27:39.070284 UTC**, with **exit 65 after 261.208 seconds**, on the same `20fb9f711` source. The earlier admission/start snapshot above remains a historical record; the completed [attempt-2 receipt](evidence/app-build-attempt2-20fb9f711/ai-hly-build-attempt2.json) now supplies its result.

The raw log has exactly two compiler error lines, both at `HanlinCompactChatWorkspace.swift:613:21`: the overriding property must be accessible, and a stored property named `focused` cannot override the inherited property. The same diagnostics appear in the exported xcresult issues. No `SwiftShims` diagnostic appears in these raw error lines or issue summaries. The build therefore reached a separate source error after the cache correction; it did not complete successfully.

The [cache-retirement receipt](evidence/app-build-attempt2-20fb9f711/isolated-stale-module-cache-retirement.json) records removal of only the inactive, reproducible copied ModuleCache after the working cache was regenerated. It records no active open files in that detached copy. This maintenance action is preserved as orchestration, with no build or test pass inferred.

The [focus-fix provenance](evidence/app-build-attempt2-20fb9f711/focus-fix-provenance.json) records the ownership check and exact correction: original commit `8cf5b3e3023852ab41fec7d9db1592218c1bcfd1` was integrated as `e5a3e6d9216a69552b2b25a096fd3f3fcf8e2876`. Their source diffs are byte-identical. Only the private Anchor backing Bool and three uses change from `focused` to `searchIsFocused`; initializer/update labels and focus publication behavior remain unchanged. The [original patch and ownership rationale](evidence/app-build-attempt2-20fb9f711/focus-fix-8cf5b3e30.patch.gz) are preserved. **Compilation after this correction is not verified by this packet.**

The complete 4,608,783-byte raw attempt-2 log is losslessly compressed; its uncompressed SHA-256 is:

`49e8df8a70597ca6f0f36f5974976ac0f51420ed5771f763cf90f5ffbc14b933`

The original xcresult remains on the Mac; its [seven-file hash inventory](evidence/app-build-attempt2-20fb9f711/xcresult-sha256.json) is included. Subsequent SDK-pin integration, RuntimeHost preparation and application validation are outside this packet's recorded results.

## Required work still pending

| Gate | Exact pending scope |
|---|---|
| Application compilation | Two Debug `build-for-testing` schemes: `AI_HLY` and `HanlinMiniApps` |
| App selection / storage / policy integration | 13 methods: six composer integration, five MiniApp assistant-tool, one original Skill policy and one prepared Expo discovery method |
| Original native engines | Four `HanlinUnifiedHostServicesE2ETests` methods |
| Native UIKit editor regressions | Four selected `NativeComposerLineSizingTests` methods |
| iPhone UI | Three composer-capability UI methods plus the existing model-picker/draft regression |
| iPad UI | The same three composer-capability UI methods |

This packet records two failed `AI_HLY` builds, the isolated cache repair and retirement, and the integrated focus-property correction. It contains no successful application build or application/native/editor/UI test result. The pending gates above remain open.

The UI inventory is **seven executions across two devices**, comprising four distinct methods. The catalog/map fixture supplies UI metadata only; it does not provide a tool executor or a fabricated model response.

SDK passes, dependency artifact reuse, source-generator checks and the Node host tests do not establish successful application builds, native engine execution, UI gestures, full CI, or physical-device behavior.
