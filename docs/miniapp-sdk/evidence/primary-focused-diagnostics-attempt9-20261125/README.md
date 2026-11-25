# Attempt 9: preserved focused runtime and Modular diagnostics

## Disposition

The actual six-case focused run executed all six selected tests: **3 passed, 3 failed, 0 skipped**. The isolated Modular diagnostic also failed at the native-list hittability assertion after successful strict package validation, installation, real native Expo rendering and live Sefaria search. **The original 25 + 27 = 52 acceptance cases remain NOT_RUN.**

This evidence-only commit retains both original packets independently, including their original receipts and timestamps. The earlier 01:42:20 UTC packet correctly says Modular was still running; the later 01:59:07 UTC packet preserves its terminal failure. No frozen receipt or phase history was rewritten.

Source: `1812bff50571c9907d15cd8b4bfbe4874be24756`; tree: `d06c5752c33c787df957a01d33461889cf5d7f4e`.

## Actual six-case results

| Original test | Actual result | Seconds |
|---|---|---:|
| testStandaloneExpoNativeAPIUsesActualUIKitAndWorklets | PASS | 50.314 |
| testStandaloneExpoRendersNativeControlsAndRunsReactEvents | PASS | 63.776 |
| testStandaloneExpoWidgetsUsesOriginalTimelinesAndLiveActivities | PASS | 73.521 |
| testStandaloneNativeScriptUsesRealRuntimesAndSurvivesRelaunch | FAIL | 54.074 |
| testStandaloneSDKOnlyExpoPackageImportsRendersAndHandlesEvents | FAIL | 47.353 |
| testStandaloneSDKOnlyNativeScriptPackageImportsRendersAndHandlesEvents | FAIL | 65.776 |

The retained test-case terminal lines and finalized FocusedOriginal summary establish these results. The controller's literal error, “Original runtime acceptance did not execute every selected case,” remains in the raw state without being silently repaired. It does not negate the executed cases recorded in the original test log. Xcode also reported a **600-second diagnostic collection timeout** during finalization; the original process sample is retained.

## NativeScript startup boundary

The JSC job completed successfully in 3 ms with the expected nonce and value 1932. The later Python job completed successfully in 183 ms. JSC completion to Python start was approximately 20.050 seconds, with no parity Node job in the retained observer journal. The actual loaded bridge binary contains the current CFRunLoop callback delivery, so an outdated linked bridge is not supported by the retained evidence.

The actual failure AX and the visually inspected PNG show the Apps catalog and parity card, without a presented runtime screen or runtime labels. The early test title predicate can match that card. Application markers show RUN_MAIN_BEGIN without a corresponding RUN_MAIN_OK before teardown.

The current SDK9 Node .ready marker was born at 01:27:59.751066 UTC, after the parity app was torn down. This is a filesystem observation, not a measurement of a particular Node preparation interval. Read-only source review identifies synchronous module-evaluation calls, main-queue UI updates and cold host preparation as relevant ordering boundaries; it does **not** prove that the JSC callback itself lost a result. The next authorized diagnostic keeps the parity fixture and its original independent runtime assertions unchanged and records cold/warm cache state.

## Modular search and detail boundary

The isolated variant changed only the install-preview existence wait from 30 to 240 seconds. The case allowance remained 420 seconds, with every other original assertion unchanged. Original strict Expo validation took **64,537 ms**, with **zero diagnostics**, skipLibCheck=false and dependency declarations checked. The install wait began at test t=34.23s and first observed the preview at t=103.24s. Installation, native rendering and the live Genesis 1:1 search result occurred before the later failure.

After the test tapped the result at t=131.14s, Open in Sefaria existed at t=133.33s. The test then queried the native collection at t=133.52–133.63s and immediately failed its existing hittability requirement at line 1177. The retained AX contains a native CollectionView and detail cells; that collection returned an AXVisiblePoint of (-1,-1), despite a 1032×1376 frame.

The actual Expo detail implementation is `Scripts/Expo/miniapps/modular-text-search/App.tsx`. Its List and source link are created from the selected search result without a detail HTTP request. Full text is fetched only after its later button action. An HTTP-readiness explanation for this particular failure is therefore unsupported. Remaining diagnosis must distinguish an unsettled or covered destination from a nonhittable container with interactive children. A bounded wait for the **same existing hittable native-list predicate**, followed by a pre-assertion screenshot/AX capture and unchanged content assertions, is an appropriate next diagnostic. No new success is claimed here.

The Modular test emitted its actual failure after 136.558 seconds. The controlled process later reached its 600-second limit without a cleanly finalized xcresult bundle. The file named ModularDiagnostic-summary.json is retained as its **literal xcresulttool exit-64 error**, not parsed or relabeled as a successful summary. The Modular attachment export also exited 64, so no detail screenshot is claimed.

## Source restoration and original acceptance

The original UI source was restored to SHA256 `732bc4e23f4f72d8978cdce54e99fe87a7cec9ac9070f0b479524b42fdd50695`. The original and diagnostic compiled test binaries have different retained hashes. The terminal state correctly requires rebuilding the original test binary after owned cleanup; restoring source alone does not satisfy that requirement. Owned simulator cleanup and all raw failures remain recorded.

The metadata baseline preserves the separate actual TNSLabel finding: the installed original TNSWidgets binary exports TNSLabel, while generated NativeScript metadata did not contain that name. Later source corrections and new runs are outside this frozen attempt9 checkpoint.

## Files and verification

- `raw/` holds all **29 original members plus both original receipts**. Four large text files use deterministic gzip. The PNG and all other members retain their exact raw bytes.
- `raw-bindings.json` maps every original path and identity to its stored path, including compressed and decompressed hashes.
- `assessment.json` records the actual case results, job timing, failure boundaries and restoration state.
- `source-review.json` binds the nine immutable production/test files used for the bounded ordering review.
- `verification.json` records every copied and decompressed identity check.
- `receipt.json` binds every evidence file in this directory except itself.

This work ran no compiler, test, native process or Mac query and changed no production source. It does not replace the already sealed SDK9 proof, the actual five-consumer resource binding, or any pending full acceptance/physical-device evidence.
