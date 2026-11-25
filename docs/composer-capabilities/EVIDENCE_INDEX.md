# Composer capabilities: validation evidence

The full `AI_HLY` Debug build-for-testing passed at `b739ada91aca115093e3511f9df58c15edcb5923`, with exit 0 after 1040.388 seconds. This packet preserves its original receipt, complete log, xcresult file hashes and generated NativeScript metadata evidence, alongside the prior library, preparation, Host and artifact proofs. The four earlier full application build failures remain preserved. Functional, native-engine, editor and UI tests have not been inferred from the successful build; the subsequent generated test-manifest guard requires an environment correction before those tests begin. The companion application build remains pending. The isolated documentation branch is based on `189ca0d73a8f9b92451d343ca84b4b7074c57c6c`. Overall completion is **pending**. This packaging work ran no compiler, tests, native preparer or simulator.

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
| RuntimeHost final attempt 6 | `801bb3f66cfe6d4d0ff9e49e0094ea2887525fbd` | After the NativeScript optional-result correction: exit 0 in 84.718s, 177 passed, 0 failed, one unchanged opt-in skip; original ZIP/JITless checks passed | [receipt](evidence/runtime-host-final-attempt6-801bb3f66/runtime-host-final-attempt6.json), [complete compressed log](evidence/runtime-host-final-attempt6-801bb3f66/runtime-host-final-attempt6.log.gz) |
| Final manifest-contract regression | `7b7f7e4460200d7e98162dd525d67f8ca1860911` | One passed, zero failed/skipped; exit 0 in 0.618s at 2026-11-25 00:35:34.980179 UTC, including changed embedded-plugin identity and new source-authority rejection cases | [receipt](evidence/manifest-final-7b7f7e446/manifest-final-test.json), [complete compressed log](evidence/manifest-final-7b7f7e446/manifest-final-test.log.gz) |
| AI_HLY build-for-testing attempt 1 | `20fb9f71146aec19acd3a7f9802a1fbe9fe7fe91` | Exit 65 after 330.678s; copied SwiftShims PCM retained the producer ModuleCache path. No acceptance tests executed by this build command | [receipt](evidence/app-build-attempt1-20fb9f711/ai-hly-build-attempt1.json), [xcresult errors](evidence/app-build-attempt1-20fb9f711/ai-hly-build-attempt1-errors.json), [complete compressed log](evidence/app-build-attempt1-20fb9f711/ai-hly-build-attempt1.log.gz) |
| AI_HLY build-for-testing attempt 2 | `20fb9f71146aec19acd3a7f9802a1fbe9fe7fe91` | Exit 65 after 261.208s; two compiler errors reject the private stored `focused` property. No acceptance tests executed by this build command | [receipt](evidence/app-build-attempt2-20fb9f711/ai-hly-build-attempt2.json), [xcresult errors](evidence/app-build-attempt2-20fb9f711/ai-hly-build-attempt2-errors.json), [complete compressed log](evidence/app-build-attempt2-20fb9f711/ai-hly-build-attempt2.log.gz) |
| AI_HLY build-for-testing attempt 3 | `91ac2c3868d9a056815bca56448e0cfcabd54eed` | Exit 65 after 134.632s; optional `Result` inference error in the NativeScript host-services adapter. No acceptance tests executed | [receipt](evidence/app-build-attempt3-91ac2c386/ai-hly-build-attempt3.json), [xcresult errors](evidence/app-build-attempt3-91ac2c386/ai-hly-build-attempt3-errors.json), [complete compressed log](evidence/app-build-attempt3-91ac2c386/ai-hly-build-attempt3.log.gz) |
| AI_HLY build-for-testing attempt 4 | `712fc49fe656e0b9a4c7e691752377b879fd6e24` | Exit 65 after 175.793s; actor-isolated tool-name access in the live executor factory. No acceptance tests executed | [receipt](evidence/app-build-attempt4-712fc49fe/ai-hly-build-attempt4.json), [log-derived diagnostic](evidence/app-build-attempt4-712fc49fe/derived-compiler-errors.json), [complete compressed log](evidence/app-build-attempt4-712fc49fe/ai-hly-build-attempt4.log.gz) |
| AI_HLY build-for-testing attempt 5 | `b739ada91aca115093e3511f9df58c15edcb5923` | **Exit 0 / TEST BUILD SUCCEEDED** in 1040.388s; lock unchanged and no tracked changes; acceptance tests not executed by the build | [receipt](evidence/app-build-attempt5-b739ada91/ai-hly-build-attempt5.json), [complete compressed log](evidence/app-build-attempt5-b739ada91/ai-hly-build-attempt5.log.gz), [assessment](evidence/app-build-attempt5-b739ada91/build-and-metadata-assessment.json) |
| HanlinApplication library build | `aea6d31e311a3f3096014ea2f1c39432371e3ecc` | Exit 0 in 571.716s; original library compilation only, with stable Host6 resource; no acceptance tests | [receipt](evidence/application-library-aea6d31e3/application-module-build-attempt1.json), [complete compressed log](evidence/application-library-aea6d31e3/application-module-build-attempt1.log.gz) |
| NativeScript metadata preparation | `aea6d31e311a3f3096014ea2f1c39432371e3ecc` | Original preparer exit 0 in 6.674s; installed wrapper hash matches exact owner source | [receipt](evidence/native-script-preparation-199da0f9e/native-script-metadata-preparation.json) |
| NativeScript initial preflight | `aea6d31e311a3f3096014ea2f1c39432371e3ecc` | Exit 1 in 0.307s; original SwiftUI fixture package.json absent | [receipt](evidence/native-script-preparation-199da0f9e/native-script-metadata-preflight.json), [raw log](evidence/native-script-preparation-199da0f9e/native-script-metadata-preflight.log.gz) |
| Original NativeScript fixture production | `199da0f9e61a0d99998bce906001e565f3138d1c` | Exit 0 in 24.598s after the fixture producer used the authoritative dependency lock | [receipt](evidence/native-script-preparation-199da0f9e/native-script-fixture-production.json) |
| NativeScript second preflight | `199da0f9e61a0d99998bce906001e565f3138d1c` | Exit 0 in 2.291s; package.json unchanged | [receipt](evidence/native-script-preparation-199da0f9e/native-script-metadata-preflight-attempt2.json) |
| RuntimeHost final attempt 7 | `bcd44d23a0d2fc2804fa34f3cc5407e51b0adc2f` | Exit 1 in 310.523s; 174 passed, three real readiness/child-timeout failures, one unchanged skip | [receipt](evidence/runtime-host-final-attempt7-bcd44d23a/runtime-host-final-attempt7.json), [failure assessment](evidence/runtime-host-final-attempt7-bcd44d23a/failure-assessment.json), [raw log](evidence/runtime-host-final-attempt7-bcd44d23a/runtime-host-final-attempt7.log.gz) |
| RuntimeHost final attempt 8 | `bcd44d23a0d2fc2804fa34f3cc5407e51b0adc2f` | Exit 0 in 125.160s at normal priority; 177 passed, zero failed, one unchanged skip; original packed ZIP/JITless checks passed | [receipt](evidence/runtime-host-final-attempt8-bcd44d23a/runtime-host-final-attempt8.json), [raw log](evidence/runtime-host-final-attempt8-bcd44d23a/runtime-host-final-attempt8.log.gz) |
| Native artifact export / verification | `b739ada91aca115093e3511f9df58c15edcb5923` | Both exit 0: 266.869s export and 9.269s verification; catalog has 15 frameworks and five support records | [receipt](evidence/integration-native-catalog-b739ada91/native-catalog-b739ada91-host8.json), [catalog](evidence/integration-native-catalog-b739ada91/native-artifacts.json) |
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

The NativeScript continuation correction at `801bb3f66` makes the existing lock closure's optional `Result` type explicit. That one-line source correction changes the original audited SDK source identity. The original RuntimeHost packager completed attempt 6 in **84.718 seconds**, with **177 Node tests passed, zero failed, one unchanged opt-in skip, original packed ZIP validation and the JITless probe passed**.

The read-only transfer independently matched the actual **81,837,524-byte** Mac archive to SHA-256:

`9d2390718e8cbd9161438392789a69a60bcfe537c8cd4ac5b8088323cb3339cc`

The uncompressed attempt-6 raw log SHA-256 is:

`84dad869cb29f0bd357f2f857d2cc1a0f7b68fb847ebe709890fa775006baae0`

The skipped case remains `actual Node job crosses 300 seconds with no hidden deadline`, the existing opt-in long test.

The [source/build assessment](evidence/runtime-host-final-attempt6-801bb3f66/source-and-build-assessment.json) verifies that generated freeze `712fc49fe` changes **eight lines across three documentation files**: three source-revision entries and five copies of the corrected adapter hash. The [original generated patch](evidence/runtime-host-final-attempt6-801bb3f66/sdk-inventory-freeze-712fc49fe.patch.gz) and [one-line source correction](evidence/runtime-host-final-attempt6-801bb3f66/nativescript-result-type-801bb3f66.patch.gz) are preserved.

**Host6 archive freshness passed at its actual source `801bb3f66`.** The later metadata/actor changes, fixture generation, Host7 failure and successful Host8 preparation are recorded separately below. Earlier passes, original sources, archive hashes and failures remain preserved. None establishes a successful full application build.

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

The [focus-fix provenance](evidence/app-build-attempt2-20fb9f711/focus-fix-provenance.json) records the ownership check and exact correction: original commit `8cf5b3e3023852ab41fec7d9db1592218c1bcfd1` was integrated as `e5a3e6d9216a69552b2b25a096fd3f3fcf8e2876`. Their source diffs are byte-identical. Only the private Anchor backing Bool and three uses change from `focused` to `searchIsFocused`; initializer/update labels and focus publication behavior remain unchanged. The [original patch and ownership rationale](evidence/app-build-attempt2-20fb9f711/focus-fix-8cf5b3e30.patch.gz) are preserved. At the attempt-2 checkpoint no successful recompilation was available. The later original library-only compilation is recorded below with its actual source and restricted scope.

The complete 4,608,783-byte raw attempt-2 log is losslessly compressed; its uncompressed SHA-256 is:

`49e8df8a70597ca6f0f36f5974976ac0f51420ed5771f763cf90f5ffbc14b933`

The original xcresult remains on the Mac; its [seven-file hash inventory](evidence/app-build-attempt2-20fb9f711/xcresult-sha256.json) is included. The later qualified SDK resolution and RuntimeHost attempt 5 are recorded above. The completed application attempt 3 is recorded below; it does not provide a successful build.

### Application build attempt 3

The third `AI_HLY` build-for-testing attempt ran at `91ac2c386` and completed at **01:48:50.353174 UTC**, with **exit 65 after 134.632 seconds**. Its receipt records an unchanged resolved lock and no tracked source changes.

The raw log and exported xcresult issues contain one compiler error at `NativeScriptHostServicesAdapter.swift:38:28`: an optional `Result<HanlinValue, any Error>?` must be unwrapped to the nonoptional `Result` type. The assigned owner corrected the optional return type in `801bb3f66`, whose original patch is preserved above. The next application attempt still failed on a separate actor-isolation error; no successful application compilation is inferred.

The complete **1,376,602-byte** raw log is preserved with lossless compression. Its SHA-256 is:

`81679428a7a197b18ebf412364c63851ebcb8bb3a05d83363234a03dafdc09ff`

The original xcresult remains on the Mac, with its [seven-file hash inventory](evidence/app-build-attempt3-91ac2c386/xcresult-sha256.json) retained here. The command was build-for-testing and executed no application/native/editor/UI acceptance tests.

### Application build attempt 4 and exact source intake

Attempt 4 ran at `712fc49fe` and completed at **02:03:01.307956 UTC**, with **exit 65 after 175.793 seconds**. The raw log contains one compiler error at `AssistantToolBridge.swift:83:62`: the MainActor-isolated `name` property cannot be read from the nonisolated live-factory context.

No separately exported xcresult issue file was present at capture. The included diagnostic is explicitly derived from the original raw log, not presented as an xcresult export. The completed xcresult remains on the Mac with its [seven-file hash inventory](evidence/app-build-attempt4-712fc49fe/xcresult-sha256.json) retained. The complete **489,706-byte** log has SHA-256:

`565d4477238385a062ad2ece425960abfa5e40b1edba10f0412dd2d30a3bbf87`

Original fix `4c18f43cabad800e6069d601b39ca534e720e8a0` adds exactly two `@MainActor` annotations to the live factories. Its integration as `aea6d31e311a3f3096014ea2f1c39432371e3ecc` has a byte-identical source diff. The [original fix and rationale](evidence/runtime-host-final-attempt6-801bb3f66/executor-mainactor-4c18f43ca.patch.gz) are preserved. The subsequent library-only compilation passed at the integrated `aea6d31e3` source; full application validation remains separate.

The original NativeScript owner change `4d8c0d0ac0e49e4a14dc64970b75bfca4e8b2aed` was taken through `d4258d2cc9bdce5fdcac846c9d4d86380e40793b` and integrated as `e08a77146a6bef97a0be8cd90dfdf1d30e2255ba`. All three diffs are byte-identical and affect exactly the original metadata wrapper and its README. The [owner patch](evidence/runtime-host-final-attempt6-801bb3f66/nativescript-owner-metadata-4d8c0d0ac.patch.gz) and comparison are preserved. This is source-intake evidence. The subsequent original NativeScript preparer, initial failed preflight, corrected fixture production, successful second preflight and Host8 archive preparation are preserved below as actual separate executions.

### Original application library compilation

The original `HanlinApplication` scheme completed `xcodebuild build` with **exit 0 in 571.716 seconds**, from **02:14:13.395232 to 02:23:45.110379 UTC** at `aea6d31e311a3f3096014ea2f1c39432371e3ecc`. Its raw log contains `BUILD SUCCEEDED`; the execution owner reported the original 519 Swift source files. The [exact receipt](evidence/application-library-aea6d31e3/application-module-build-attempt1.json) records no tracked changes.

This was a library compilation. It intentionally retained the prior Host6 archive, whose before/after SHA-256 was identical (`9d2390718e8cbd9161438392789a69a60bcfe537c8cd4ac5b8088323cb3339cc`). It did not execute tests or establish a successful `AI_HLY` or `HanlinMiniApps` build, current application resource binding, native-engine acceptance or UI behavior. The four completed full-app failures remain in this index.

The complete 8,526,296-byte raw log is losslessly compressed with SHA-256 `5f7a8d6b6714b532a0d4240dd58b92e7c34ec18d0c214ee9d77c56b7d24fd403`. The original xcresult remains on the Mac, with its [seven-file hash inventory](evidence/application-library-aea6d31e3/xcresult-sha256.json) preserved.

### NativeScript metadata preparation and fixture recovery

The original NativeScript preparer passed in **6.674 seconds** at `aea6d31e3`. Its installed wrapper SHA-256 `71bf1d521abff7cc29c1e8d397a9ef2a55b09f758afb36f0a148be12350b664f` matches the exact integrated owner source. The initial preflight then **failed** in 0.307 seconds because `Prepared/swiftui-fixture/nativescript/app/package.json` did not exist. This prerequisite failure remains preserved; it is not counted as a native-engine acceptance result.

The [exact fixture producer correction](evidence/native-script-preparation-199da0f9e/fixture-lock-authority-199da0f9e.patch.gz) in `199da0f9e61a0d99998bce906001e565f3138d1c` changes three lines in `prepare-fixture.mjs` to use the authoritative runtime/core lock versions. It retains the installed-version validation and original producer. The original fixture producer subsequently passed in **24.598 seconds**, and the second original preflight passed in **2.291 seconds**.

Both successful receipts record the same unchanged package.json SHA-256: `08fc03bfa87cd78f4f21f80e9324a4840061105f6e9ab081ed794c569ca7324b`. Generated commit `bcd44d23a0d2fc2804fa34f3cc5407e51b0adc2f` changes only the two original fixture bundle files; its [original patch](evidence/native-script-preparation-199da0f9e/generated-fixtures-bcd44d23a.patch.gz) is retained. The [combined source assessment](evidence/native-script-preparation-199da0f9e/preparation-and-library-assessment.json) preserves each execution source and the initial failure.

### Host7 failure, unchanged-source Host8 pass and final archive

Host7 ran the original packager at `bcd44d23a` with `nice -n 10` and completed with **174 passes, three actual failures, one unchanged skip**, exit 1 after 310.523 seconds. The three failures were execution-input readiness at 17.208 seconds, the Fetch child killed at its existing 15-second budget, and MCP host-fixture readiness at 18.564 seconds. The [failure assessment](evidence/runtime-host-final-attempt7-bcd44d23a/failure-assessment.json) retains their full case names and original timing details. The raw log SHA-256 is `e2553a7e5ebd8b0fd3f334cddaf79620d3c033eacbb9655a89e0c559462ce28e`.

Host8 used **the same source, tests, assertions and timing budgets**, with the original packager at normal priority. It completed at **02:37:47.226713 UTC**, exit 0 in **125.160 seconds**, with **177 passes, zero failures and the same existing opt-in skip**. Original packed ZIP validation and all eleven packed JITless contracts passed. The changed process priority and successful retry are recorded observations; they do not prove a sole cause for Host7's timing failures.

The read-only transfer independently matched the actual **81,837,544-byte** archive to SHA-256 `8b05742603572e8b3309a647fc04880fa59d891beb13f4623fbd79a0cb9c49a1`. The raw Host8 log SHA-256 is `0c87e20007d3a248b4ef781e1c3eb2ce6fb4fc9038a3a8774807e37ad752bd9f`. Repeated Host passes are not added together as unique test coverage.

Generated freeze `b739ada91aca115093e3511f9df58c15edcb5923` changes exactly **five provenance/hash lines in three SDK documentation files**, after Host8 at `bcd44d23a`. The [original generated patch](evidence/runtime-host-final-attempt8-bcd44d23a/sdk-inventory-freeze-b739ada91.patch.gz) and [original freeze receipt](evidence/runtime-host-final-attempt8-bcd44d23a/runtime-provenance-host8-commit.json) preserve this distinction. Archive freshness after the metadata, actor and fixture changes is now an executed pass; application acceptance remains pending.

### Prebuild source audit and verified native catalog

The [original read-only integration audit](evidence/integration-native-catalog-b739ada91/prebuild-integration-b739ada91.json) retains its actual remote fetch cutoff of **02:33:51.362865 UTC** and audited source `bcd44d23a`. It distinguishes subsequent generated-only `b739ada91` from the source actually audited. Completed relevant metadata and factory-isolation changes were already integrated; unrelated owner UI-helper changes do not affect the selected composer tests. The unresolved original owner's native acceptance boundary remains explicit.

The original native exporter and verifier executed at `b739ada91`, each with exit 0: **266.869 seconds** for export and **9.269 seconds** for verification. Their [receipt](evidence/integration-native-catalog-b739ada91/native-catalog-b739ada91-host8.json), [export log](evidence/integration-native-catalog-b739ada91/native-catalog-b739ada91-host8-export.log.gz), [verification log](evidence/integration-native-catalog-b739ada91/native-catalog-b739ada91-host8-verify.log.gz) and exact [native catalog](evidence/integration-native-catalog-b739ada91/native-artifacts.json) are preserved. The catalog declares 15 frameworks, five support records and no missing targets. It explicitly describes validation of existing native binaries and does not claim to build or test runtimes. Native binaries remain on the Mac.

The [qualified native comparison](evidence/integration-native-catalog-b739ada91/native-catalog-comparison-b739ada91.json) binds its owner baseline to the exact captured catalog at owner source `fda6948ca`, rather than relabeling an earlier mutable catalog. **All 16 native inputs match; 14 of 15 framework slice maps and 34 of 36 individual slices match the owner binaries.** ExpoModulesJSI is the documented original-producer rebuild completed at 00:46:04 UTC. Its raw producer log is already retained in this packet; the original producer built both slices in 56 seconds. This is not a claim that all fifteen frameworks reuse identical owner binaries.

Two additional framework ZIP differences concern only Header directory modes changing from 0700 to 0755. Byte equality after normalizing just those directory attributes was verified in memory; no Mac archive was modified. Four of five support archives match the owner catalog, with Host8's NodeHostSupport as the only support delta. All eight original catalog/receipt/inspection snapshots are retained with the comparison so its qualifications remain reproducible. The original native preparation receipt's then-stale RuntimeHost check is preserved; later Host8 proof is recorded separately.

### Verified Asana milestone

The authorized parent and M5 milestone descriptions were updated in a single successful **2-of-2** write at **02:31:11 UTC**. Both remained incomplete. The [write acknowledgement and read-back assessment](evidence/asana-milestone-20261125-023111.json) preserve the new summary and verification metadata without copying the prior task descriptions. M5 retained its prior rich/plain notes byte-for-byte; the parent retained all content with only six existing Asana URLs canonicalized to include `/f/`. One transient parent read-back failure was resolved by a bounded read-only retry, without a repeated write.

The first milestone reports the library-only pass, actual fixture/preflight recovery and open full-app/native/UI gates. A subsequent authorized combined milestone was written in one successful 2-of-2 batch at **02:52:54 UTC**, covering Host7/8 and the native catalog export/verify with qualified reuse. Its [acknowledgement and read-back](evidence/asana-milestone-20261125-025254.json) confirm that both tasks remain incomplete and all prior rich/plain descriptions are byte-identical. Asana normalized only the new heading markup. Both complete new summaries were verified, with no repeated write or read-back retry. Full application and native/editor/UI gates remain open.

### Full AI_HLY build-for-testing PASS

The original fifth `AI_HLY` Debug build-for-testing ran at `b739ada91aca115093e3511f9df58c15edcb5923`, from **02:40:52.964773 to 02:58:13.349471 UTC**, and completed with **exit 0 in 1040.388 seconds**. The original log contains `TEST BUILD SUCCEEDED`. The [receipt](evidence/app-build-attempt5-b739ada91/ai-hly-build-attempt5.json) records the task's iPhone simulator destination, isolated DerivedData, exact pinned package graph, an unchanged resolved lock and no tracked source changes.

This is an actual full `AI_HLY` application and test-product build. It is separate from the prior library-only pass. The build-for-testing command does not execute the functional, native-engine, editor or UI cases, and it does not complete the companion `HanlinMiniApps` build gate.

The complete **7,383,108-byte** raw build log is preserved with lossless compression. Its SHA-256 is `164cdd23b48d96255b7200b129b8b73a4e3ff001bf53c2ea7d4cda94846c0ecc`. The original xcresult remains on the Mac, with its [seven-file hash inventory](evidence/app-build-attempt5-b739ada91/xcresult-sha256.json) retained. The [build and metadata assessment](evidence/app-build-attempt5-b739ada91/build-and-metadata-assessment.json) binds these records to their actual source.

### NativeScript metadata generated during attempt 5

The original [visibility result](evidence/app-build-attempt5-b739ada91/metadata/visibility.json) records **all twelve required strings present** and **zero clang errors** for arm64 iOS Simulator metadata. It explicitly declares `HOST_BASELINE_ONLY` and a build-time completeness check. The required names include `TNSLabel`, `NSCCrypto`, the NativeScript services/session bridges, SwiftUI fixture/provider and WebKit classes/delegate.

The visibility file was modified at **02:49:35.178945 UTC**, within the recorded attempt-5 build interval. Its SHA-256 is `ee2499dca17090de31c058652ca6e22e6df9fb87b0ff7e73c8d7c65910a3ee01`. The actual metadata binary remained on the Mac and was read-only hashed as `5a3385b02b9f1c626301a326d32068aadc5d6ef6ceb4fa5bae486a978321fbba`. The original 2,207,738-byte [compiler stderr log](evidence/app-build-attempt5-b739ada91/metadata/metadata-generation-stderr-arm64.txt.gz), hash `9518b950dd8d66ddec4588cd2f52552330b306ad93de0578f135e1b493192220`, is preserved without loss.

The original headers and compressed framework/header inventories are retained with the [eight-file source hash manifest](evidence/app-build-attempt5-b739ada91/metadata/source-files-sha256.json). Each output hash declared in the visibility result matches the actual observed file. The [original compiler provenance](evidence/app-build-attempt5-b739ada91/metadata/provenance.json) identifies reused metadata-compiler source `5d4569c197810cdd4c1e02e7c16d42a01a77d5c0`; this is **the build tool's origin**, separately from application source `b739ada91`. Its original tool-only boundary has not been relabeled as an application or VM result.

Metadata completeness establishes the recorded build-time baseline. Actual NativeScript VM behavior and the selected engine tests remain pending.

### Generated test-manifest prerequisite

The original [built-products guard](evidence/app-build-attempt5-b739ada91/built-products-preflight-attempt1.json), checked at **03:00:05.269599 UTC**, confirms the successful build and identifies a separate prerequisite: the fresh `.xctestrun` manifest has no `HANLIN_UNIT_TEST_HOST` entry in either inspected environment map for either `AI_HLYTests` or `AI_HLYUITests`.

The manifest was generated at **02:58:11.389953 UTC**, with SHA-256 `b2cc79f4b3780daec837e119cc5e4a07d5ecccd618ab793b88bb0b80dbfa2062`. The original guard states that no application tests were launched. Source ownership and the correction were under investigation when this packet was captured. This is a blocked test prerequisite, **not a failed application build or an executed test failure**.

### Verified full-build Asana milestone

The parent and M5 descriptions were updated in one successful **2-of-2** batch at **02:59:20 UTC**. The [acknowledgement and read-back](evidence/asana-milestone-20261125-025920.json) confirm both tasks remain incomplete, the new summaries are exact, and all previous rich/plain content is byte-identical. The milestone records the full build PASS and twelve-string/zero-clang metadata boundary while keeping companion compilation and functional/native/editor/UI gates open. It preceded the separately retained 03:00 test-manifest guard.

## Required work still pending

| Gate | Exact pending scope |
|---|---|
| Companion application compilation | Remaining Debug `build-for-testing` scheme: `HanlinMiniApps`; `AI_HLY` passed in attempt 5 |
| Test launch prerequisite | Correct and verify the explicit test-host environment in the generated test manifest before actual test execution |
| App selection / storage / policy integration | 13 methods: six composer integration, five MiniApp assistant-tool, one original Skill policy and one prepared Expo discovery method |
| Original native engines | Four `HanlinUnifiedHostServicesE2ETests` methods |
| Native UIKit editor regressions | Four selected `NativeComposerLineSizingTests` methods |
| iPhone UI | Three composer-capability UI methods plus the existing model-picker/draft regression |
| iPad UI | The same three composer-capability UI methods |

This packet records the successful fifth full `AI_HLY` build, the four earlier failed attempts, the prior library-only pass, actual NativeScript preparation/fixture/preflight recovery, Host7 failure and Host8 pass, and native artifact export/verification. `HanlinMiniApps` compilation and application/native/editor/UI test results remain pending. The generated test-manifest environment guard is a recorded prerequisite issue; it does not reverse the actual build PASS.

The UI inventory is **seven executions across two devices**, comprising four distinct methods. The catalog/map fixture supplies UI metadata only; it does not provide a tool executor or a fabricated model response.

SDK passes, dependency artifact reuse, source-generator checks and the Node host tests do not establish successful application builds, native engine execution, UI gestures, full CI, or physical-device behavior.
