# Original NativeScript and AppIntents evidence: run 45238831508

**NativeScript host-baseline metadata: PASS. Original AppIntents compiler exports: PASS in the listed targets. Overall producer: FAIL. All 342 authored expected test invocations: NOT_RUN. Native publication: BLOCKED.**

The original [run 45238831508](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45238831508), attempt 1, used source `39a10b1cbf4645b629f556ea312e2576a4e566db`. Its native job `137917939932` failed during test compilation: the original `#require` expression around `HanlinConversationMutation.rename` needed an inner `try`. The shared build-for-testing invocation therefore did not finish. The subsequent current-product validation, simulator tests and runtime launch steps were skipped.

This evidence was acquired and reviewed without another build, simulator, test or native-asset download.

## Authentic acquisition

The single smoke acquisition is artifact `14851982748`, `AI_Hanlin-iOS26-simulator-smoke-logs`. The retained original ZIP is **3,623,566 bytes**, SHA256 **b182d1ebf821eaed35bc1f67365260080f2f11b5ead2873067f97d6926b61c6b**. The API source/run identity, nonexpired status, advertised size/digest, all 63 member CRCs, safe paths and non-symlink archive entries were checked. `acquisition.json` retains the original API record and per-member hashes. The ZIP was downloaded once.

The parent-owned original native job log was reused from Oracle; it was not downloaded again. It is 26,337,432 bytes, SHA256 `774daaa290455ac86b3f8a6f6faf4b8ec84f2063df894c291116a0c4a86cdab0`. The original run/jobs/artifact API records and compiler diagnostic are retained by the parent in commit [36d3c51b](https://github.com/davidpovarsky/hanlin-ai/commit/36d3c51bdba93ada2c2722ed0e9b99109d84a616), directory `docs/agent-sdk/evidence/application-require-compile-45238831508`. This packet binds its verbatim log excerpts to the same raw-log digest.

## NativeScript metadata repair

The original `build/acceptance/nativescript-metadata/iphonesimulator-arm64/visibility.json` reports **0 Clang errors** and all **10 required names present**:

- HanlinNativeServicesBridge and HanlinNativeServicesSessionBridge
- HanlinNativeScriptCompatibility
- UIView and NSObject
- NativeScriptEmbedder and SwiftUIProvider
- HanlinNativeScriptSwiftUIFixtureProvider
- WKNavigationDelegate and WKWebView

The original scope remains **HOST_BASELINE_ONLY**. This is declaration/metadata visibility, not execution of JavaScript, SwiftUI callbacks, native tools, a live model or an application session.

The actual original framework inventory contains **130 records: 107 SELECTED and 23 DEDUPLICATED_IDENTICAL, no conflict**. Every record's input-manifest digest was recomputed from its recorded header/modulemap hashes, and all 23 duplicate records were verified equal to their selected original owners. This authenticates the retained inventory; it does not rehash framework bytes absent from the artifact.

Both original libssh2 framework paths have the same four-entry header/modulemap manifest SHA256 `4a60070fc96708c9f46e143be087724ac1f0a8f0f2ebbea1b72f4c6ec9f1a84a`. The PackageFrameworks owner is selected once in view `0087/libssh2.framework`; the second built-products copy is an identical duplicate. Uppercase `React.framework` is selected in view 0060 with its identical duplicate removed. Lowercase `react.framework` remains a distinct original owner in view 0104. The complete 1,536,373-byte `FrameworkSearchView.inventory.json` is preserved inside the original ZIP.

The original visibility file's three artifact hashes match the actual extracted bytes:

| Original output | SHA256 |
|---|---|
| metadata-generation-stderr-arm64.txt | d471b20c127dbdd0ca63f5fc1dbdb6e8628a1b6b65536ab3f3683cb7bbca89a4 |
| umbrella-arm64.h | 5c1251646d4c8de07f3ff64f833033848fb9c11c5493b082076f9ab56419767a |
| metadata-arm64.bin | 0a914fed8d321c372585c8afb13663a06c6476c04d02823e0e88294b8296d1a7 |

The metadata binary is unchanged from the earlier failed duplicate-module run. That earlier run failed its real Clang guard; the current run removes the error while preserving the generated host-baseline metadata. No broader SDK metadata or runtime coverage is inferred.

## Original AppIntents compiler outputs

No `AppIntents only supports` diagnostic occurs in the original native log. Seven original processor blocks explicitly wrote `Metadata.appintents`:

| Project | Target/module |
|---|---|
| HanlinSDK | HanlinScriptExtensions |
| HanlinSDK | HanlinTranslationUI |
| HanlinSDK | HanlinScriptingWidgets |
| HanlinSDK | HanlinWidgetUI |
| AI_HLY | ChavrusaChatTranslationProvider |
| AI_HLY | HanlinScriptingWidgets / HanlinScriptingWidgetsHost |
| HanlinSDK | AI_Hanlin |

`appintents-extractors.json` retains their original command/output blocks and line references. All ten retained compiler metadata/file-list files match their original receipt's sizes and hashes. The four SDK `.swiftconstvalues` files match the previously authenticated run 452305 files exactly; the old explicit-bundle errors have not returned. This is compiler metadata evidence, not a claim that Siri invoked the actions or that all final app packaging completed.

## Application build boundary and tests

The original log contains main app link commands for `__preview.dylib` at 18:56:15Z, `AI_Hanlin.debug.dylib` at 18:56:41Z and `AI_Hanlin` at 18:56:43Z, plus 92 embedded-framework CodeSign commands. It contains **no final main-app CodeSign, Validate or Touch command**. These are progress milestones; they do not qualify a complete signed application or the prerequisite for paired MiniApps acceptance.

The unit descriptor receipt is only **PREPARED** and contains no prior descriptors. The original workflow explicitly skipped current-unit product validation, simulator test execution and runtime launch. There are no downstream/UI test-results exports in the smoke ZIP. All **32 selected scopes / 342 authored expected invocations remain NOT_RUN**. The exact original request is retained as `request.json`; expected counts are source inventory, not execution.

The prepared Native artifact `14850817502` is **INELIGIBLE** because its producer failed. It was neither acquired by this lane nor published.

## Necessary continuation

Parent fixed the single test expression in [36d3c51b](https://github.com/davidpovarsky/hanlin-ai/commit/36d3c51bdba93ada2c2722ed0e9b99109d84a616) and dispatched [45246711373](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45246711373) at that exact SHA. Its status at parent notification was in progress; parent is the sole watcher. This packet does not poll it or infer its result. The new run must prove the selected methods and arguments before acceptance or publication.
