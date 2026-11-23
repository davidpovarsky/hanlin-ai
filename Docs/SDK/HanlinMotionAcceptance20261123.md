# Motion acceptance and canonical SDK fixture — 2026-11-23

## Current acceptance remains open

The current canonical SDK run **45133334293 at6772dce6 executed B and C**: B failed its intermediate-reversal assertion; C passed its XCTest assertions. The original source/resource, resolved dependency and packaged-bundle accounting all completed before those cases. Native video shows visible warm animation, but the recorded rapid burst did not reverse at an intermediate height. No product timing or algorithm change is justified by the evidence. Clean landscape visual acceptance remains open because its original screenshot is clipped. A/D retain their historical wait failures and were not rerun. See [the current native receipt and reviewed frames](../../docs/agent-sdk/evidence/motion-native-45133334293/README.md).

The [Motion Asana task](https://app.asana.com/1/1219597879016953/project/1219603102275846/task/1220546846740594), comment `1220728546279038` at 2026-11-20 02:23 UTC, records an iPad A16 / iPadOS 27.2 run with product source **c456b7240d7b43f52de6b1090bfd82d41ec27eb7** and launcher **a8a9cbbfdbb711d301a04e7f2b93df0792349e27**.

| Case and exact selector suffix | Latest recorded run | Observed outcome and interpretation |
| --- | --- | --- |
| A — `testAAllFivePresetsTwentyCompleteCyclesEach` | [44648588449](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44648588449) | Collapse waiter failed after 190 of 200 toggle actions; subsequent state read was collapsed. No stuck animation is established. From the unchanged test ordering, action190 corresponds to the fifteenth cycle of the final, **No animations** preset; this is an inference from the original case source. |
| B — `testBRapidReversalPresetSwitchAndPersistence` | [45133334293](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45133334293) @6772dce6 | **FAILED**,40.123s. Two warm-up plus three burst actions delivered; burst gaps56.9/59.2ms, cached pre-action heights0/0/0. Original native frames show the footer still collapsed with counters3 and4, and moving after counter5. Later B assertions are NOT_RUN. |
| C — `testCReadableLongContentRTLTypeOrientationAndCompletion` | [45133334293](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45133334293) @6772dce6 | **EXECUTED_PASS**,33.586s, original XCTest long content/RTL/type/orientation/completion assertions. Portrait images reviewed. The landscape capture has a black/clipped region, so a clean landscape visual pass is not established. |
| D — `testDRapidInputDiagnosticOnly` | [44648453626](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44648453626) | Reset waiter failed; subsequent static and animated states both read collapsed. D only records native input diagnostics and never accepts A/B/C. |

The full selectors have prefix `ChatMotionProofUITests/MotionUITests/`. The source observations and exact task comments are retained in the [receipt](../../docs/agent-sdk/evidence/motion-acceptance-and-fixture-20261123.json). This audit reused existing reports and task comments and did not re-download large native artifacts.

## Historical evidence that must not be misreported

Run [44465711797](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44465711797), source8e2f8924, passed D’s XCTest: one test, zero failures,135.070s. Its workflow failed later at Python line18. Reading that exact pinned script resolves what line18 means: it requires recording exit_code0 and a video larger than1024bytes. It is a **recording-evidence gate**, not a disclosure geometry assertion. The retained excerpt does not distinguish which video predicate failed. Current source already includes the graceful recorder shutdown repair30637bf6; reimplementing that repair would duplicate existing work.

An older C pass in44358121911@a9085987 (39.352s) and A’s historical100 cycles in43771756937@58834d4c remain valid historical records within their original component scope. Neither is a current original-app or physical-device pass.

## Changes already present before this repair

Current fixture bodies and tests include **836a8a4a**. It keeps per-frame measurements away from the accessibility observation tree, bounds AX historical arrays while keeping the full on-disk timeline, and prewarms B using real native expand/collapse actions. B still requires an exact3-action burst, two gaps below0.5s, at least one action at intermediate rendered geometry, correct settling, nested expansion retention, native drag cancellation, persistence and Reduce Motion. No thresholds or gestures are weakened here. No verified native result for that later fixture existed at the initial audit. The current6772dce6 run now records actual B failure and C automated pass with those original assertions unchanged.

Historical C cannot stand in for the current production closure: c94e6fcf added disclosure disappearance revision invalidation;72bf6f2b restored original V17 letter shimmer and its1.95s relaxed period;20e6bd51 changed finite/full-natural-height geometry. The new scoped appearance/preset APIs8250e4ce preserve original defaults, but their SDK integration is also not proved by an older copied-source fixture.

## Definite fixture regressions from SDK extraction

The old preparer still required the deleted app paths `AI_HLY/Assets.xcassets/HLBluefont.colorset/Contents.json` and `AI_HLY/Resource/Localizable.xcstrings`. Its broad original-chat snippet boundary had also grown to capture the app-only consent adapter. Individually copied Motion sources now depend on canonical localization, typography and appearance modules that the disposable project did not link. All A/B/C/D cases were blocked before meaningful execution on that fixture; that is not an animation product failure.

The exact original `LoadingGradientText`, `ToggleButton` body and containing-scroll touch adapter are now canonical public ChatUI components. The original app consumes aliases; the [12-body preservation receipt](../../docs/agent-sdk/evidence/original-motion-controls-20261123.json) proves unchanged original bodies and input/touch restoration behavior. Their appearance and motion still flow through the existing HanlinActivityTitle/chatMotion implementation.

`prepare_motion_ui.py` now installs the actual selected **HanlinChatUI** profile at the exact checkout commit using the existing shared installer and generator. The fixture app imports that module and aliases its original toggle type. It stages only fixture app/test sources. No production source extraction, stand-in module, copied catalog or copied asset is produced.

The profile selects ChatUI, Localization, PresentationKit and RichUI source roots, with no native runtime binary target. The portable preparation exercised the actual installer and generated manifest at committed0a59a736:363 canonical source/resource files,24,800,545bytes. The fixture edits were intentionally uncommitted during this preparation, recorded explicitly; it is not a native test pass. The native accounting step rejects any harness that does not match the recorded commit.

The preparation receipt hashes every selected canonical source/resource file and all generator/manifest/pin inputs, including HanlinChatAppearance.swift. It retains the generated selected Package.swift, installer receipt and product lock. After the Apple build, the existing runner records actual resolved dependency checkout revisions and file bytes, the actual Package.resolved, and the packaged SDK resource bundles before executing the original tests. Its simulator selection, gestures, recording logic, result gates and diagnostic-only distinction are retained.

## Minimal next native work

The affected B/C scope has executed once on the corrected full source-bound fixture. B remains failed, and C’s automated pass is preserved for unchanged scope. The smallest remaining input comparison is the existing original **input-diagnostic** D case if scheduled; no new animation or timing implementation is proposed. A still requires its original **cycles** scope once the B result is resolved. Do not rerun C merely because B failed; its clean landscape capture is a separate unresolved visual obligation. A successful D remains DIAGNOSTIC_CAPTURED.

If a wait fails, retain the measured timeline, exact AX receipt and phase timestamps before diagnosing a product defect. Do not increase thresholds, remove the intermediate-geometry requirement, or modify the production animation to satisfy an observer that did not exercise the intended transition.

The component fixture remains distinct from original full-chat, streaming Markdown, paused-user scroll, compact multitasking and physical-device acceptance. Root’s original host/UI gates own those scopes. The initial source audit dispatched no CI. The later bounded native attempts below and the current45133334293 B/C run used the existing workflow; no animation algorithm or timing changes were made.

## Actual canonical native attempt: 45122303559

The focused `affected` dispatch at `65fdc2ed9cd1ed563b86d98cee2dab7f665f714c` ran on Xcode27.2 / Swift6.4.2. Its fresh simulator reached native boot readiness. The fixture and selected SDK profile matched the recorded source, with363 canonical source/resource files and manifest SHA256 `67bd5ca5a9e9c368886949f8fd178d11d502f858f5fe411b11540f8df238d2f4`.

Xcode stopped at `ComputeTargetDependencyGraph`: the existing EquatableMacros package was not enabled for this standalone headless command. Build exited65 before Swift compilation, resolved-input/bundle accounting and test execution. B/C are **NOT_RUN**; A/D were not dispatched. The artifact ZIP is15,318,937bytes and its API-verified SHA256 is `28e31d77849b03c564245f39017c1c4ec4c5d4c8c05d5cf9f1284fdd5b9984a6`.

The bounded repair reuses the original project's command-scoped `-skipMacroValidation` option in the two Motion xcodebuild commands. The original lock and native log identify Equatable1.4.1; the original pinned revision is `597c2bb34af0c51331eb3b5e705f942d8ee20daa`. Global preferences, product animation code, dependency declarations, UI cases and measurement semantics remain unchanged. A follow-up B/C execution is required before considering the original A cycles or diagnostic D.

See the [native receipt and actual build log](../../docs/agent-sdk/evidence/motion-native-45122303559/README.md). Native attempt: https://github.com/davidpovarsky/hanlin-ai/actions/runs/45122303559.

### Exact macro admission before compilation

The retry first performs normal Xcode package resolution, without macro admission. A new prebuild checkpoint reads the original selected SDK's app `Package.resolved`, validates its recorded hash, and compares the actual resolved Equatable identity/version/revision/location to that original pin. It reuses `Scripts/CI/ChatRegressionValidation/run_native.py::record_macro_configuration` for the existing reviewed exact checkout-HEAD policy. Any untracked or modified macro source is rejected before compilation.

Only after that checkpoint succeeds do build/test use the established command-scoped macro option. Both invocations disable automatic package re-resolution, and the postbuild source-accounting checkpoint rejects any resolved-lock byte change. The original admission helper and its precedent files are included in the fixture input hash inventory. No macro, plugin, fixture UI or native test was executed by the portable verification.

Six focused controls passed against the actual reviewed Equatable Git checkout and a synthetic test envelope: the exact input is admitted; unknown resolved revision, untracked macro source, changed original lock, uncommitted fixture and unreviewed checkout HEAD are rejected. See [the bounded control receipt](../../docs/agent-sdk/evidence/motion-macro-admission-controls-20261123.json). This adds input enforcement; it is not a dependency upgrade or a current Motion pass.

## Successful Apple compilation; post-build symlink accounting repair

The source-bound retry [45127145735](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45127145735) at `705f1bd8` passed its actual Xcode 27.2 test build and exact original macro admission. Post-build provenance stopped at the real `hanlin-streaming-markdown` directory symlink `.claude/skills`, before either original B/C case ran. This is a fixture accounting failure, not an observed animation failure.

The recorder now preserves tracked symbolic-link target bytes, Git mode and object identity without following destinations. Missing regular sources, modified links and type substitutions remain errors. The eight exact resolved trees contain three such links and no submodules. Six focused controls passed; original UI and test semantics are unchanged. No actual visual acceptance is claimed from this run. Full source, artifact digest, raw failure/build excerpts and limits are in [the native receipt](../../docs/agent-sdk/evidence/motion-native-45127145735/receipt.json).
