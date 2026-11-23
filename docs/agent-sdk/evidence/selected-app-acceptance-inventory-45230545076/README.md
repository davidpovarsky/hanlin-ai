# Expected original app acceptance — source 7523f45

This is a read-only inventory and result-gate review for the already-dispatched [run 45230545076](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45230545076) at `7523f45cf8ea180a8e30f511ff0fbd3bb5ccae6d`. It does not execute tests, acquire another artifact, edit CI, or claim an application pass.

## Required identities and counts

The **32 requested selectors** comprise 27 unit scopes and five UI scopes. They expand to **310 distinct method definitions**: 299 unit and 11 UI. Expanding the eighteen literal argument arrays gives **342 authored invocations**: 331 unit and 11 UI. These are expected source counts, not an observed xcresult total. Swift Testing may report parameter containers and their runs separately; do not sum both as executions.

`expected-inventory.json` lists every selected method and source line, the exact SHA256 of each original test source, every parameter array with its cardinality, and all enclosing compile conditions. Methods are associated with their original suite declaration, including the two suites in A2UITests, the selected suites/methods in the shared organizer file, and the three localization suites compiled from the original SDK test file. Unselected methods in those files are excluded.

| Required area | Exact method or scope | Expected execution |
| --- | --- | --- |
| Real EventKit continuation | `HanlinAppAgentSessionOwnerTests/actualEventKitToolRecoversTheOriginalChatAndReadsTheFullDateWindow()` | One passing method in original app-hosted unit results; the staging receipt alone is not execution |
| AppIntents host localization | `HanlinApplicationSystemIntegrationTests/widgetIntentMetadataLoadsTheOriginalHostTranslations(language:)` | All three arguments: en, he, zh-Hans; both app and widget executable tables are asserted inside each invocation |
| Original SDK bundle localization | `HanlinLocalizationTests/originalTranslationTablesRemainAvailable(locale:)` | All three arguments: en, he, zh-Hans |
| Native settings propagation | `ModelPopoverZoomOrderTests/nativeGenerationConfigurationPreservesOriginalSettings()` | One passing exact selected method |
| Native unsupported top-P | `ModelPopoverZoomOrderTests/nativeGenerationRejectsUnsupportedTopPThroughOriginalEngine()` | One passing exact selected method; this rejects settings before availability/model generation, so it is not generation acceptance |
| Original NativeA2UI UI suite | `HanlinNativeA2UIChatUITests` | All seven original methods, including the mixed React/SwiftUI method |
| Original activity, Composer, citations | The four exact `AgentRuntimeConversationUITests` methods in the request | Four distinct passing methods, including separate English and Hebrew citation journeys |

The mixed method is `testOriginalMixedOpenUIReactAndNativeShareStateAndKeepDraft()`. Its original assertions require the real React WebView and native SwiftUI controls inside the same assistant message, native-to-React update to 7, React-to-native update to 9, unchanged request count while state stays local, exactly one subsequent action continuation, and preservation of the unsent Composer draft. Its success-path `record` call retains screenshot and accessibility attachments named `original-mixed-openui-react-native-state-and-action` and the corresponding `-AX` name in the original UI xcresult. This is original app/renderer integration with fixture HTTP; it is not a live network model test.

## Result gate finding

`Scripts/CI/verify_selected_tests.py` traverses actual xcresult Test Case nodes and rejects a requested suite with no executed child, an omitted exact method, or a skipped-only selector. The workflow separately preserves each xcodebuild exit code and fails the step when it is nonzero. Exported invalid/missing JSON does not silently pass the verifier.

However, a suite selector is satisfied by **one executed child**, and the verifier does not enumerate all suite members or all parameter arguments. Therefore a green run alone cannot establish the source coverage above. A failed or expected-failure node is accepted only as evidence that a selector executed; neither is a feature PASS for this acceptance. Require the original exported trees/logs to establish each required passing method, every argument invocation, and zero unresolved failed/skipped/missing required cases. Inspect full parameter-run identities or original Swift Testing argument records when a tree displays a single aggregate method. Counts or suite headings alone are insufficient.

The workflow remains unchanged while the run is active. This inventory allows an exact review of its original retained output without replaying tests.

## Exact retained result locations

The `AI_Hanlin-iOS26-simulator-smoke-logs` artifact retains both original result bundles and exports:

- Unit tree: `simulator-logs/08-downstream-unit-test-results.json`; raw log: `08-downstream-unit-tests.log`; bundle: `DownstreamTestsResult.xcresult`.
- UI tree: `simulator-logs/08-nativescript-production-ui-test-results.json`; raw log: `08-nativescript-production-ui-tests.log`; bundle: `NativeScriptProductionE2EResult.xcresult`.
- Unit source/product admission: `06-current-unit-xctestrun.json`, `06-generated-unit.xctestrun`, and `08-current-unit-xctestrun-admission.json`, all under `simulator-logs/`. Require the original source/run/attempt, Debug configuration, exact requested unit scopes, generated-manifest hash, original app/test bundle identities, and owned device binding. `ADMITTED_NOT_EXECUTED` explicitly does not claim a test pass.
- Calendar staging: `08-calendar-native-staging.json` binds installation and calendar/reminder grants to that original unit host and owned simulator. Require its PASS plus the actual EventKit method PASS.
- Actual runtime/device metadata: `verified-simulator-environment.json`, result bundle device records, and raw command destination. Preserve any UI runner clone identity separately rather than assuming its UDID matches the unit destination.

## Conditional scope

There are **no permitted platform-conditional omissions in this requested run**. It selects Debug on iOS Simulator with the app's existing A2UI define. Simulator-only EventKit acceptance is included; `HANLIN_A2UI_POC`, the Debug-only SDK close test, and Darwin/SwiftUI/UIKit localization cases are expected. The portable standalone-runner branches are not selected. If actual compile flags differ, treat the corresponding coverage as missing or blocked; do not lower the expected set.

The native settings methods explicitly call `Issue.record` when their original modules cannot be imported, rather than passing an empty alternate body. The live-provider `XCTSkipUnless` in the conversation UI source belongs to an **unselected** live-provider method; it does not excuse any of the four selected UI methods. Physical-device runs would have a different EventKit compile scope, but none is requested here.
