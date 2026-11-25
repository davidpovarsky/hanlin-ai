# Composer capabilities: validation evidence

This packet includes successful original RuntimeHost preparation and qualified SwiftAI package resolution at `756d7f1517f64295d4ce8ff9ea01d88c1f5f1194`, followed by generated inventory freeze `91ac2c3868d9a056815bca56448e0cfcabd54eed`. Three application build attempts are preserved as actual failures, with their respective sources and diagnostics. The isolated documentation branch is based on `189ca0d73a8f9b92451d343ca84b4b7074c57c6c`. Overall completion is **pending**. This packaging work ran no compiler, tests, native preparer or simulator.

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
| RuntimeHost final attempt 5 | `756d7f1517f64295d4ce8ff9ea01d88c1f5f1194` | After qualified SwiftAI manifest integration: exit 0 in 466.034s, 177 passed, 0 failed, one unchanged opt-in skip; original ZIP/JITless checks passed | [receipt](evidence/runtime-host-final-attempt5-756d7f151/runtime-host-final-attempt5.json), [complete compressed log](evidence/runtime-host-final-attempt5-756d7f151/runtime-host-final-attempt5.log.gz) |
| Qualified SDK resolution | `756d7f1517f64295d4ce8ff9ea01d88c1f5f1194` | Original Xcode package resolution exit 0 in 264.447s; exact clean `3f38f130` SDK checkout and unchanged lock | [receipt](evidence/runtime-host-final-attempt5-756d7f151/qualified-sdk-resolution.json), [complete compressed log](evidence/runtime-host-final-attempt5-756d7f151/qualified-sdk-resolution.log.gz) |
| Final manifest-contract regression | `7b7f7e4460200d7e98162dd525d67f8ca1860911` | One passed, zero failed/skipped; exit 0 in 0.618s at 2026-11-25 00:35:34.980179 UTC, including changed embedded-plugin identity and new source-authority rejection cases | [receipt](evidence/manifest-final-7b7f7e446/manifest-final-test.json), [complete compressed log](evidence/manifest-final-7b7f7e446/manifest-final-test.log.gz) |
| AI_HLY build-for-testing attempt 1 | `20fb9f71146aec19acd3a7f9802a1fbe9fe7fe91` | Exit 65 after 330.678s; copied SwiftShims PCM retained the producer ModuleCache path. No acceptance tests executed by this build command | [receipt](evidence/app-build-attempt1-20fb9f711/ai-hly-build-attempt1.json), [xcresult errors](evidence/app-build-attempt1-20fb9f711/ai-hly-build-attempt1-errors.json), [complete compressed log](evidence/app-build-attempt1-20fb9f711/ai-hly-build-attempt1.log.gz) |
| AI_HLY build-for-testing attempt 2 | `20fb9f71146aec19acd3a7f9802a1fbe9fe7fe91` | Exit 65 after 261.208s; two compiler errors reject the private stored `focused` property. No acceptance tests executed by this build command | [receipt](evidence/app-build-attempt2-20fb9f711/ai-hly-build-attempt2.json), [xcresult errors](evidence/app-build-attempt2-20fb9f711/ai-hly-build-attempt2-errors.json), [complete compressed log](evidence/app-build-attempt2-20fb9f711/ai-hly-build-attempt2.log.gz) |
| AI_HLY build-for-testing attempt 3 | `91ac2c3868d9a056815bca56448e0cfcabd54eed` | Exit 65 after 134.632s; optional `Result` inference error in the NativeScript host-services adapter. No acceptance tests executed | [receipt](evidence/app-build-attempt3-91ac2c386/ai-hly-build-attempt3.json), [xcresult errors](evidence/app-build-attempt3-91ac2c386/ai-hly-build-attempt3-errors.json), [complete compressed log](evidence/app-build-attempt3-91ac2c386/ai-hly-build-attempt3.log.gz) |
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

### Qualified SDK resolution

The original Xcode `-resolvePackageDependencies` command completed with exit 0 in **264.447 seconds** at `756d7f151`. Its raw log records checkout of exactly `3f38f1302764635c9991d0d00fd7b12471a5373c` from the qualified SwiftAI repository. The receipt records a clean checkout and an unchanged before/after application lock SHA-256:

`4a55e370d71d69933efb0bc54a08973da962b4d7270da59791aa3b1ed58910bd`

The raw resolution-log SHA-256 is `40ad9a0514e4a17dafe9ac37264a707033c02cb7a3d3733ffcb33eeb5689e846`. This is successful package graph resolution; it is not an application build or test result.

The [checkpoint assessment](evidence/runtime-host-final-attempt5-756d7f151/checkpoint-assessment.json) verifies that generated commit `91ac2c3868d9a056815bca56448e0cfcabd54eed` changes exactly three source-revision lines in the existing SDK inventory/reachability files, from `cd795e378` to `756d7f151`. The [original Git patch](evidence/runtime-host-final-attempt5-756d7f151/sdk-inventory-freeze-91ac2c386.patch.gz) is retained. Earlier shared SDK/Platform execution and reuse evidence keep their existing assessed source boundaries; resolution alone does not extend that applicability.

### RuntimeHost artifact freshness

The qualified SwiftAI revision changes the Platform package manifest archived inside the SDK. The original RuntimeHost packager therefore completed attempt 5 at `756d7f151` in **466.034 seconds**, with **177 Node tests passed, zero failed, one unchanged opt-in skip, packed ZIP validation and the original JITless probe passed**. Native producers were not rerun.

The read-only transfer independently matched the actual **81,837,507-byte** Mac archive to SHA-256:

`120bc8a6396f4202284d8a4e61ca3d772d15d791f750b9824f6a57a735f1f70b`

The uncompressed attempt-5 raw log SHA-256 is:

`754ea129dbab59da74471bf0093977ba6c3c25a28b853dd7a6355a45fef98a09`

The skipped case remains `actual Node job crosses 300 seconds with no hidden deadline`, the existing opt-in long test. No new skip was introduced.

**Archive freshness passed at `756d7f151` after qualified SDK integration.** The generated source metadata was then frozen in `91ac2c386`; no test execution is attributed to that documentation-only commit. Earlier successful attempts 2, 3 and 4 retain their actual 177-pass results, original sources and archive hashes. The earlier missing-plugin audit failure and stale-SDK detection also remain preserved. The successful archive preparation does not establish a successful application build.

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

The original xcresult remains on the Mac; its [seven-file hash inventory](evidence/app-build-attempt2-20fb9f711/xcresult-sha256.json) is included. The later qualified SDK resolution and RuntimeHost attempt 5 are recorded above. The completed application attempt 3 is recorded below; it does not provide a successful build.

### Application build attempt 3

The third `AI_HLY` build-for-testing attempt ran at `91ac2c386` and completed at **01:48:50.353174 UTC**, with **exit 65 after 134.632 seconds**. Its receipt records an unchanged resolved lock and no tracked source changes.

The raw log and exported xcresult issues contain one compiler error at `NativeScriptHostServicesAdapter.swift:38:28`: an optional `Result<HanlinValue, any Error>?` must be unwrapped to the nonoptional `Result` type. The correction is with the assigned runtime-adapter owner. No correction or subsequent successful compilation is inferred from this packet.

The complete **1,376,602-byte** raw log is preserved with lossless compression. Its SHA-256 is:

`81679428a7a197b18ebf412364c63851ebcb8bb3a05d83363234a03dafdc09ff`

The original xcresult remains on the Mac, with its [seven-file hash inventory](evidence/app-build-attempt3-91ac2c386/xcresult-sha256.json) retained here. The command was build-for-testing and executed no application/native/editor/UI acceptance tests.

## Required work still pending

| Gate | Exact pending scope |
|---|---|
| Application compilation | Two Debug `build-for-testing` schemes: `AI_HLY` and `HanlinMiniApps` |
| App selection / storage / policy integration | 13 methods: six composer integration, five MiniApp assistant-tool, one original Skill policy and one prepared Expo discovery method |
| Original native engines | Four `HanlinUnifiedHostServicesE2ETests` methods |
| Native UIKit editor regressions | Four selected `NativeComposerLineSizingTests` methods |
| iPhone UI | Three composer-capability UI methods plus the existing model-picker/draft regression |
| iPad UI | The same three composer-capability UI methods |

This packet records three failed `AI_HLY` builds, successful qualified SDK resolution and original RuntimeHost preparation, and the integrated focus-property correction. It contains no successful application build or application/native/editor/UI test result. The pending gates above remain open.

The UI inventory is **seven executions across two devices**, comprising four distinct methods. The catalog/map fixture supplies UI metadata only; it does not provide a tool executor or a fabricated model response.

SDK passes, dependency artifact reuse, source-generator checks and the Node host tests do not establish successful application builds, native engine execution, UI gestures, full CI, or physical-device behavior.
