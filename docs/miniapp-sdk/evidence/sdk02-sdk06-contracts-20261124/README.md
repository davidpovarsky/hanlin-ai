# SDK02 / SDK06 focused contract follow-up — 2026-11-24

## Executed and reusable evidence

Two existing original ScriptWidget manifest cases passed with the actual compiler 6.0.3 extracted from run 8's authenticated SDK: 2 passed, 0 failed/cancelled/skipped. The validator and schema were checked byte-for-byte against the exported SDK. The package version is @typescript/typescript6 6.0.2; the observed compiler version is 6.0.3. The old Oracle TypeScript cache was not substituted.

The negative case includes the original control_storage rule for a toggle with no storage permission. The positive original manifest remains accepted. Native source origin: ScriptMetadata.swift:413–414 at original ScriptWidget revision 4da256d58247bbafb9a5cd443a285250b97b3c4b. This is an existing manifest contract and introduces no approval or grant flow. See original-permission-contract.json, original-permission-contract.tap.txt and validation-plan.json. These two methods were not rerun during the later archive/plugin additions.

One new real missing-manifest archive case passed: 1 test in 1 suite, 0 failed/skipped/cancelled. The real two-entry Expo-shaped ZIP contains a bundle and package.json but no script.json. The actual ZIP directory parser and production ArchivePolicy reject it with isInstallable=false, manifestPath=nil, code ambiguousManifest, severity error, entry=nil, and the exact message "Archive does not contain script.json." See missing-manifest-result.json, missing-manifest/archive-import-policy.txt and the retained ZIP and metadata. ZIPFoundation extraction, native import and Apple execution are not claimed by this portable case.

The prior twelve archive cases were not rerun. archive-reuse.json retains the original six-input comparison at base 4ea and records the later additive harness delta separately. Five whole-file inputs remain identical. The harness now has an optional filter and one independent fixture/case; its original three generated Swift test methods remain byte-identical, as does the separate ArchivePolicy test file. Reuse is limited to the original ambiguity and retained-source assertions and is not represented as a new thirteen-case run.

## Current gap map

| Gap | Status | Actual route |
| --- | --- | --- |
| Ambiguous manifest | REUSED_VERIFIED_PASS | Existing exact portable ArchivePolicy receipt, with unchanged relevant production and test bodies. |
| Missing root script.json | EXECUTED_PASS | One new actual ZIP directory/parser plus ArchivePolicy case; only this method ran. |
| Incompatible known native plugins | NEEDS_APPLE_EXECUTION | Three existing modern Analyzer methods. |
| Unavailable native plugin name | NEEDS_APPLE_EXECUTION | New unavailableModernNativePluginsFailBeforeImport method checks both Expo and NativeScript against valid baselines. |
| Unsupported/invalid exposure | NEEDS_APPLE_EXECUTION | Existing expoMultiExposureMatrix and malformedPreparedEntrypointsFailWithStableDiagnostic. |
| Wrong Expo/NativeScript foreground main | NEEDS_APPLE_EXECUTION | Existing exact foreground-entry tests for both engines. |
| Original permission mismatch | EXECUTED_PASS | Two selected current-SDK ScriptWidget authoring cases; no OS permission/UI claim. |

## Test-only changes

The first commit changes three expected messages in HanlinScriptAnalyzerTests.swift. They bind Core and Expo UI installed-version text to the public generated HanlinMiniAppHostVersions authority (currently Core 9.1.4 and Expo UI 58.0.29). Fixtures retain the same older supported patches and unsupported future versions. All canInstall expectations, finding selection, equality/contains semantics and assertion counts remain unchanged. expected-version-bindings.json and .diff describe that checkpoint.

The descendant adds one Analyzer method with four staged fixtures: a valid empty-plugin baseline and otherwise identical unavailable-plugin declaration for each modern foreground engine. NativeScript runtime 9.1.1 and Expo UI 58.0.29 are read through the generated authority. Negative assertions require canInstall=false, unsupported state, error severity, the actual engine package.json sourcePath, and a message naming the required plugin/version. The current finding does not supply a stable diagnostic code, so none is invented. The existing helper stages real source files and decodes the manifest; it does not extract a ZIP.

The changed Analyzer source passed Swift syntax parsing only. It has not been Apple typechecked or executed. All pre-existing Analyzer source is byte-identical to the first commit after removing only the added method.

The portable harness adds one missing-manifest case and an optional filter without changing the default command flags or original fixture/test bodies. No runtime production code or workflow was edited. new-negative-cases.json and .diff bind the final source and recorded results.

## Exact Apple route for eight Analyzer methods

Use the existing validate-scripting-runtime.yml workflow directly at the integrated intended source, with runtime_job_foundation_only=false, force_clean_build=true and this test_filter:

    HanlinScriptAnalyzerTests/(expoMainMustMatchTheInspectedForegroundEntrypoint|nativeScriptPreparedEntrypointIsAlwaysTheCanonicalBundle|nativeScriptSwiftUIContract|nativeScriptCoreContract|expoSwiftUIContract|expoMultiExposureMatrix|malformedPreparedEntrypointsFailWithStableDiagnostic|unavailableModernNativePluginsFailBeforeImport)

Its actual command is swift test --package-path Packages/HanlinPlatform --filter "$TEST_FILTER". The package test target exists in both manifests but is absent from both shipping app schemes; adding its selectors to the main app gate does not make them run.

The workflow has no configured concurrency group or cancel-in-progress rule, so a direct dispatch does not share the standalone MiniApps group. It selects Xcode 27 on a Mac runner, resolves SwiftPM dependencies, and has a 20-minute timeout. Legacy inventory/bootstrap/runtime preparation is conditional on the exact legacy-suite filter and will not execute for this modern filter. The required compiler resources are already tracked.

The normal branch does not upload a dedicated result artifact. Preserve the completed raw job log and intended source SHA. Require all eight exact Swift Testing pass rows and total 8 with no failures/cancellations/skips; swift test exit 0 or the XCTest wrapper's zero-test line is insufficient. This proves pre-import Analyzer behavior against real staged files, not archive extraction or application UI.

Historical plugin pass rows in phase1-swift-test.log were not reused for the current version authority. No Apple execution, dispatch, CI query, source regeneration, Asana write, root modification or production change was performed in this lane.
