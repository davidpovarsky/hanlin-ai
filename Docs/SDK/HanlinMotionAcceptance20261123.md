# Motion acceptance and canonical SDK fixture — 2026-11-23

## Current acceptance remains open

The latest recorded failures do **not** establish a new unresolved animation implementation defect. They do establish incomplete acceptance: A and D failed observation/reset waits, and B did not demonstrate a reversal while the rendered height was intermediate. C passed on the historical source. A post-failure snapshot showing collapsed is insufficient to prove that collapse completed before the waiter deadline, so A/D are not silently converted to passes.

The [Motion Asana task](https://app.asana.com/1/1219597879016953/project/1219603102275846/task/1220546846740594), comment `1220728546279038` at 2026-11-20 02:23 UTC, records an iPad A16 / iPadOS 27.2 run with product source **c456b7240d7b43f52de6b1090bfd82d41ec27eb7** and launcher **a8a9cbbfdbb711d301a04e7f2b93df0792349e27**.

| Case and exact selector suffix | Latest recorded run | Observed outcome and interpretation |
| --- | --- | --- |
| A — `testAAllFivePresetsTwentyCompleteCyclesEach` | [44648588449](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44648588449) | Collapse waiter failed after 190 of 200 toggle actions; subsequent state read was collapsed. No stuck animation is established. From the unchanged test ordering, action190 corresponds to the fifteenth cycle of the final, **No animations** preset; this is an inference from the original case source. |
| B — `testBRapidReversalPresetSwitchAndPersistence` | [44648241434](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44648241434) | All three actions were delivered. The first gap was5.2ms; intermediate geometry was not measured. This supersedes the older one-of-three delivery failure but does not satisfy rapid reversal. The remainder of B cannot be treated as passed. |
| C — `testCReadableLongContentRTLTypeOrientationAndCompletion` | [44648241434](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44648241434) | Passed long content, RTL, large type, orientation and settling on the recorded historical source. |
| D — `testDRapidInputDiagnosticOnly` | [44648453626](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44648453626) | Reset waiter failed; subsequent static and animated states both read collapsed. D only records native input diagnostics and never accepts A/B/C. |

The full selectors have prefix `ChatMotionProofUITests/MotionUITests/`. The source observations and exact task comments are retained in the [receipt](../../docs/agent-sdk/evidence/motion-acceptance-and-fixture-20261123.json). This audit reused existing reports and task comments and did not re-download large native artifacts.

## Historical evidence that must not be misreported

Run [44465711797](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44465711797), source8e2f8924, passed D’s XCTest: one test, zero failures,135.070s. Its workflow failed later at Python line18. Reading that exact pinned script resolves what line18 means: it requires recording exit_code0 and a video larger than1024bytes. It is a **recording-evidence gate**, not a disclosure geometry assertion. The retained excerpt does not distinguish which video predicate failed. Current source already includes the graceful recorder shutdown repair30637bf6; reimplementing that repair would duplicate existing work.

An older C pass in44358121911@a9085987 (39.352s) and A’s historical100 cycles in43771756937@58834d4c remain valid historical records within their original component scope. Neither is a current original-app or physical-device pass.

## Changes already present before this repair

Current fixture bodies and tests include **836a8a4a**. It keeps per-frame measurements away from the accessibility observation tree, bounds AX historical arrays while keeping the full on-disk timeline, and prewarms B using real native expand/collapse actions. B still requires an exact3-action burst, two gaps below0.5s, at least one action at intermediate rendered geometry, correct settling, nested expansion retention, native drag cancellation, persistence and Reduce Motion. No thresholds or gestures are weakened here. No verified native result for that later fixture was found in the task or checked-in receipts.

Historical C cannot stand in for the current production closure: c94e6fcf added disclosure disappearance revision invalidation;72bf6f2b restored original V17 letter shimmer and its1.95s relaxed period;20e6bd51 changed finite/full-natural-height geometry. The new scoped appearance/preset APIs8250e4ce preserve original defaults, but their SDK integration is also not proved by an older copied-source fixture.

## Definite fixture regressions from SDK extraction

The old preparer still required the deleted app paths `AI_HLY/Assets.xcassets/HLBluefont.colorset/Contents.json` and `AI_HLY/Resource/Localizable.xcstrings`. Its broad original-chat snippet boundary had also grown to capture the app-only consent adapter. Individually copied Motion sources now depend on canonical localization, typography and appearance modules that the disposable project did not link. All A/B/C/D cases were blocked before meaningful execution on that fixture; that is not an animation product failure.

The exact original `LoadingGradientText`, `ToggleButton` body and containing-scroll touch adapter are now canonical public ChatUI components. The original app consumes aliases; the [12-body preservation receipt](../../docs/agent-sdk/evidence/original-motion-controls-20261123.json) proves unchanged original bodies and input/touch restoration behavior. Their appearance and motion still flow through the existing HanlinActivityTitle/chatMotion implementation.

`prepare_motion_ui.py` now installs the actual selected **HanlinChatUI** profile at the exact checkout commit using the existing shared installer and generator. The fixture app imports that module and aliases its original toggle type. It stages only fixture app/test sources. No production source extraction, stand-in module, copied catalog or copied asset is produced.

The profile selects ChatUI, Localization, PresentationKit and RichUI source roots, with no native runtime binary target. The portable preparation exercised the actual installer and generated manifest at committed0a59a736:363 canonical source/resource files,24,800,545bytes. The fixture edits were intentionally uncommitted during this preparation, recorded explicitly; it is not a native test pass. The native accounting step rejects any harness that does not match the recorded commit.

The preparation receipt hashes every selected canonical source/resource file and all generator/manifest/pin inputs, including HanlinChatAppearance.swift. It retains the generated selected Package.swift, installer receipt and product lock. After the Apple build, the existing runner records actual resolved dependency checkout revisions and file bytes, the actual Package.resolved, and the packaged SDK resource bundles before executing the original tests. Its simulator selection, gestures, recording logic, result gates and diagnostic-only distinction are retained.

## Minimal next native work

Use the existing root-owned native scheduling mechanism after the source/profile mapping is correct. Run scope **affected** first: unchanged B and C on the actual selected SDK. This checks the unaccepted native prewarm and the changed geometry/localization closure. Then run original scope **cycles** once for all five presets times twenty complete cycles; no current pass closes the latest A failure. Run **input-diagnostic** only if input delivery or reset observation still needs D’s comparison. A successful D remains DIAGNOSTIC_CAPTURED.

If a wait fails, retain the measured timeline, exact AX receipt and phase timestamps before diagnosing a product defect. Do not increase thresholds, remove the intermediate-geometry requirement, or modify the production animation to satisfy an observer that did not exercise the intended transition.

The component fixture remains distinct from original full-chat, streaming Markdown, paused-user scroll, compact multitasking and physical-device acceptance. Root’s original host/UI gates own those scopes. This lane dispatched no CI and made no animation algorithm or timing changes.

## Actual canonical native attempt: 45122303559

The focused `affected` dispatch at `65fdc2ed9cd1ed563b86d98cee2dab7f665f714c` ran on Xcode27.2 / Swift6.4.2. Its fresh simulator reached native boot readiness. The fixture and selected SDK profile matched the recorded source, with363 canonical source/resource files and manifest SHA256 `67bd5ca5a9e9c368886949f8fd178d11d502f858f5fe411b11540f8df238d2f4`.

Xcode stopped at `ComputeTargetDependencyGraph`: the existing EquatableMacros package was not enabled for this standalone headless command. Build exited65 before Swift compilation, resolved-input/bundle accounting and test execution. B/C are **NOT_RUN**; A/D were not dispatched. The artifact ZIP is15,318,937bytes and its API-verified SHA256 is `28e31d77849b03c564245f39017c1c4ec4c5d4c8c05d5cf9f1284fdd5b9984a6`.

The bounded repair reuses the original project's command-scoped `-skipMacroValidation` option in the two Motion xcodebuild commands. The original lock and native log identify Equatable1.4.1; the original pinned revision is `597c2bb34af0c51331eb3b5e705f942d8ee20daa`. Global preferences, product animation code, dependency declarations, UI cases and measurement semantics remain unchanged. A follow-up B/C execution is required before considering the original A cycles or diagnostic D.

See the [native receipt and actual build log](../../docs/agent-sdk/evidence/motion-native-45122303559/README.md). Native attempt: https://github.com/davidpovarsky/hanlin-ai/actions/runs/45122303559.
