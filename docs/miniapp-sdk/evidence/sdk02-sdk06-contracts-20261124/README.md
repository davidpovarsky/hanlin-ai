# SDK02 / SDK06 focused contract follow-up — 2026-11-24

## Executed and reusable evidence

Two existing original ScriptWidget manifest cases passed with the actual compiler6.0.3 extracted from run8's authenticated SDK: 2 passed, 0 failed/cancelled/skipped. The validator and schema were checked byte-for-byte against the exported SDK. The package version is @typescript/typescript6 6.0.2; the observed compiler version is 6.0.3. The old Oracle TypeScript cache was not substituted.

The negative case includes the original control_storage rule for a toggle with no storage permission. The positive original manifest remains accepted. Native source origin: ScriptMetadata.swift:413–414 at original ScriptWidget revision4da256d58247bbafb9a5cd443a285250b97b3c4b. This is an existing manifest contract and introduces no approval or grant flow.

See original-permission-contract.json, original-permission-contract.tap.txt and validation-plan.json.

The freshly recorded twelve archive cases were not rerun. archive-reuse.json verifies all six recorded input hashes and the original raw log against the current source, and reuses only the relevant ambiguity/retained-source assertions.

## Remaining gaps

| Gap | Status | Smallest actual route |
| --- | --- | --- |
| Ambiguous manifest | REUSED_VERIFIED_PASS | Existing exact portable ArchivePolicy receipt. |
| Missing root script.json | TEST_CASE_MISSING | One focused missing-manifest case using actual ArchivePolicy; existing malformed JSON and installed-artifact tests are different cases. |
| Incompatible known native plugins | NEEDS_APPLE_EXECUTION | Three existing modern Analyzer methods. |
| Uninstalled native plugin name | TEST_CASE_MISSING | Add one unavailable-plugin fixture to the existing modern Analyzer contract test; production already has an unsupported/default branch. |
| Unsupported/invalid exposure | NEEDS_APPLE_EXECUTION | Existing expoMultiExposureMatrix and malformedPreparedEntrypointsFailWithStableDiagnostic. |
| Wrong Expo/NativeScript foreground main | NEEDS_APPLE_EXECUTION | Existing exact foreground-entry tests for both engines. |
| Original permission mismatch | EXECUTED_PASS | Two selected current-SDK ScriptWidget authoring cases; no OS permission/UI claim. |

## Three expected-version corrections

Only three messages in HanlinScriptAnalyzerTests.swift change. They bind expected Core and ExpoUI installed-version text to the public generated HanlinMiniAppHostVersions authority (currently Core9.1.4 and ExpoUI58.0.29). The fixtures continue to exercise older supported patches and the same unsupported future versions. All canInstall expectations, finding selection, equality/contains semantics and assertion counts remain unchanged.

expected-version-bindings.json and expected-version-bindings.diff contain the exact changes. No runtime production code was edited.

## Exact Apple route for the seven existing analyzer cases

Use the existing validate-scripting-runtime.yml workflow directly at the integrated intended source, with runtime_job_foundation_only=false, force_clean_build=true and this test_filter:

    HanlinScriptAnalyzerTests/(expoMainMustMatchTheInspectedForegroundEntrypoint|nativeScriptPreparedEntrypointIsAlwaysTheCanonicalBundle|nativeScriptSwiftUIContract|nativeScriptCoreContract|expoSwiftUIContract|expoMultiExposureMatrix|malformedPreparedEntrypointsFailWithStableDiagnostic)

Its actual command is swift test --package-path Packages/HanlinPlatform --filter "$TEST_FILTER". The package test target exists in both manifests, but it is absent from both shipping app schemes; adding its selectors to the main app gate does not make them run.

The workflow has no configured concurrency group or cancel-in-progress rule, so a direct dispatch does not share the standalone MiniApps group. It selects Xcode27 on a Mac runner, resolves SwiftPM dependencies, and has a20-minute timeout. The legacy inventory/bootstrap/runtime preparation is conditional on the exact legacy-suite filter and will not execute for this modern filter. The required compiler resources are already tracked.

The normal branch does not upload a dedicated result artifact. Preserve the exact completed job log and intended source SHA. Require seven actual Swift Testing passes and no failures/cancellations/skips; swift test exit0 or the XCTest wrapper's zero-test line is insufficient. This proves pre-import analyzer behavior against real staged source files, not archive extraction or application UI.

Historical plugin pass rows were found in phase1-swift-test.log but were not reused for the current changed version authority. No Apple execution, dispatch, CI query, source regeneration, Asana write, root modification or production change was performed in this lane.
