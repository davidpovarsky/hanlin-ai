# Approved Hanlin execution — 2026-11-08

Acting roles: [נועם | DEV] [MAIN_SESSION], [רוני | QA] [MAIN_SESSION].
Owner approved the ordered plan on 2026-11-08, including necessary infrastructure/dependency repairs. No subagents requested. No main merge or new distribution authorized.

Base: `507cd0409e722d933e7fd568a24b4221a7a5d346` (Pass 7).
Branch: `fix/hanlin-approved-plan-20261108`.

## Execution order

1. Reconcile Asana evidence without closing physical-device gates.
2. Repair and execute the complete audio lifecycle suite, including VR19–VR21; retain physical recording acceptance as OPEN.
3. Validate persistent widget data, revisions, migrations, and Default/A1/A2 selection without deleting user data.
4. Repair compact Tools/Skills/MCP/Runtime presentation and model picker expansion/zoom, then execute focused UI checks.
5. Complete runtime read/execute routing and capability policy; investigate embedded Node HTTPS/FD with device diagnostics.
6. Verify Expo, ScriptWidget, and legacy coexistence and actual OS actions.
7. Implement the approved shared chat surface/renderer/selection/saved/browser/activity work with original chat parity.
8. Connect Translation and Ask Hanlin Shortcuts to the shared execution core; verify actual file/tool/result flow.

## Audio validation manifest

- Obligations: all existing lifecycle cases plus actual file-backed buffer boundaries, oversize/format rejection, and repeated file-backed lifecycle cleanup.
- Affected: `VoiceInputView.swift`, `VoiceRecordingLifecycleTests.swift`; consumers include chat/model microphone presentation.
- Previous 17-test evidence: Pass 6, before `de069452`; invalidated for changed sink paths. VR19–VR21 had no authenticated execution.
- Discovered blockers: VR21 accessed private properties, asynchronous writes used fixed sleeps, and tests did not verify persisted frame data. Matching interleaved formats could enter a per-channel non-interleaved memcpy loop; sample rate was not checked.
- Execute: existing manual app workflow, exact selector `AI_HLYTests/VoiceRecordingLifecycleTests`, Debug arm64 iPad Simulator, stable installed Xcode. No Release IPA, TestFlight, runtime bundle or unrelated suites.
- Separate evidence: package CI `42059943062` passed 45 extension + 10 analyzer + 7 JS tests at `bda4478337d52665ab0bf1e274afde86b867167e`; it did not run audio tests. Signed build 89401 (`42098595922`) is distribution evidence only.
- Hardware obligations: Hebrew/English recording, file output, permission denial/revocation, interruptions, orange microphone indicator, and sustained recording remain NOT_RUN_DEVICE until actual signed iPad execution.

## Results

- Audio implementation `978888a2933413b3f5d6ad2e3bbb2db03a432c52`; focused run [42511840857](https://github.com/davidpovarsky/hanlin-ai/actions/runs/42511840857) SUCCESS: actual arm64 iPad Simulator app build and all 20 lifecycle tests, including VR19–VR21, passed (6.735s test execution; 33m46s simulator job including setup/build/artifacts). This predates the new owner screenshot and VR22 route fix; it cannot close that new physical symptom. Phase 1 artifact download emitted an expected-missing error despite being skipped; download steps are now conditioned on their planned producer.
- Widget recovery test audit found `testPass7InterruptedRevisionWriteOverwrittenAndClean` did not create a corrupt file at all. It now seeds authentic candidate revision paths with both zero bytes and nonempty corrupt bytes and asserts exact restored bytes. Existing committed-revision integrity rejection remains required: candidate repair must not imply arbitrary reconstruction of lost committed user state.
- Widget validation: execute the changed test with the existing `widget-package` workflow filter; unaffected renderer/action tests retain their original historical provenance, without claiming execution on this SHA.
- Widget candidate-recovery run [42512043667](https://github.com/davidpovarsky/hanlin-ai/actions/runs/42512043667), implementation `21738525e26128374a180b0ba7b1ae955f4ba9d3`: EXECUTED_PASS. One Swift test, both real corruption arguments (empty and nonempty bytes) passed; seven JS tests also executed and passed. This tests pre-existing candidate revisions, not recovery of an already-corrupted committed revision.

## Dock implementation and validation manifest

- Inline Tools drawer now owns an item-driven sheet with its own NavigationStack for the existing Skills, MCP and Runtime screens. Non-embedded navigation keeps the existing push route. Draft and installation registries remain owned by their existing components.
- Added actual full-destination UI tests at simulated compact/wide workspace widths, including dismissal and draft preservation. Simulated width does not substitute for iPhone or real iPad Split View acceptance.
- Model picker: fixed a stale animation completion altering a reopened presentation; corrected minimum-size clamping that exceeded small container bounds; made intrinsic popover sizing explicit and removed the second, outer zoom transition so only All Models navigation owns the matched zoom.
- Existing two-stage expand/navigation and Reduce Motion behavior remain. Added deterministic tests for stale/reopened presentations and narrow/short containers; strengthened UI search hit-testing, clipping and shrink assertions.
- Required validation: affected coordinator unit tests, management navigation compact/wide, All Models expand/back/reopen, plus subsequent physical animation review. No physical animation PASS is inferred from state tests.

## CI dependency synchronization

- Audited official GitHub Actions stable releases and major-version changelogs on 2026-11-08. Updated the eight existing workflows consistently: checkout 7.0.1, setup-node/setup-python 7.1.0, cache 6.1.0, upload-artifact 7.0.2, download-artifact 8.0.2. These use the current Node 24 action runtime, removing obsolete Node 20 action declarations. Embedded Node and compiler runtime versions remain independently pinned.
- No workflow triggers, permissions, runner labels, signing settings, cache keys or test selectors were broadened by the dependency updates. Artifact upload keeps its zipped default.
- Local CI regression run initially found a pre-existing assertion out of sync with Pass 6's required VoiceRecordingLifecycleTests mapping. The assertion now includes that required suite; validation coverage was retained.
- Exact-selector routing now accepts validated comma-separated unit/UI method paths in one build, retaining separate execution filters. Three new regressions cover mixed bundles, malformed members, duplicate selectors, and method boundaries. 107 local infrastructure tests passed; no full device build or distribution is selected.

## Owner evidence received during execution

Owner reported both microphone and Widgets FAILED on physical 89401, then supplied two crash logs and screenshots. Hardware: iPad15,3, iPadOS 27.2 (24B119), build 89401.

- Microphone screenshot: Hebrew localized `Audio route changed, recording stopped.` No audio crash is proven by that screenshot. The handler treated `.categoryChange` from its own `.record` activation as lost hardware. Fixed to keep recording while the current category is still `.record`, while retaining stop for actual input removal or a competing category. Notification selectors now enter nonisolated and explicitly hop to MainActor; VR22 covers own versus competing category.
- Widget screenshot: the system Edit Widget instance picker still throws `HanlinScriptExtensions.HanlinScriptExtensionStoreError - 4`. This is a current physical failure; candidate repair tests cannot close it. Exact store throw site still needs persisted diagnostic/committed-state analysis.
- Both supplied crash reports are EXC_BAD_ACCESS in Hermes, not AVAudioPCMBuffer crashes. One is on the React JS runtime scheduler (HiddenClass), the other enters Hermes from ExpoModulesJSI on a Swift concurrency thread. Root cause attribution to one exact operation is not proven by stacks alone.
- Source audit found React-hosted `AppContext.setRuntime` explicitly receiving nil scheduler/dispatch. Installed Expo 58.0.3 docs/source specify that this creates an inline scheduler. Hanlin now installs Expo's upstream weak React scheduler handle from RuntimeSchedulerBinding, retaining its teardown behavior. Missing binding fails bootstrap instead of allowing unsafe async inline JSI execution.
- Source audit also found `AppContext.destroy()` called from MainActor despite upstream destroy requiring JavaScriptActor. Removed that call; the original Expo main-runtime NativeState owns destroy during React teardown on the JS thread. Existing Probe, dynamic switching and lifecycle/uninstall tests must execute after these changes; physical Hermes acceptance remains OPEN.
- Owner could not find the old conditional Copy Diagnostic UI. No further owner diagnostic action is required. Package Information now has an always-available Widget status toolbar action for native widgets, showing and copying both consistency and exact store diagnostic, including when no error banner is present. Added a real UI assertion for its visibility/presentation. English/Hebrew/Chinese labels included.
- Consistency diagnostics previously reported success for a missing committed revision or malformed commit. The report now executes the actual validated store load and preserves failures and on-disk data; two parameterized negative cases cover that behavior.

## Next integrated validation scope

One Debug simulator build will execute: full affected audio lifecycle suite (including VR22), ModelPopoverZoomOrderTests; exact Skill read/execute routing and resource-reading contracts; compact/wide full management destinations and All Models; Expo Probe, dynamic package switching and lifecycle/uninstall; installed ScriptWidget Package Information/status UI. Native Expo scheduling and public bridge/generator changes invalidate prior foreground Expo lifecycle passes. The widget snapshot/diagnostic changes require fresh affected package tests; native raster/action semantics outside those changes remain separately sourced historical evidence. No Home Screen action, physical device, Node HTTPS or whole-project completion is inferred from this scoped validation.

- Integrated run `42515200204` was deliberately cancelled/superseded before a valid acceptance result: preparation deletes and regenerates the entire Native API Core target. Scheduler source/header must live in canonical `bridge-source`, be copied to generated `bridge`, and have the public header explicitly staged. Source placement and generation corrected before further validation; no PASS is claimed for the cancelled run.
- Widget store/diagnostic run `42515208307` remains separate and is not invalidated by the scheduler staging correction.
- Widget store/diagnostic run [42515208307](https://github.com/davidpovarsky/hanlin-ai/actions/runs/42515208307), implementation `4e5b32fcb23f68d967b8ce0ceb8ba0566a6c935f`: EXECUTED_PASS, 40 tests across the store and dual-engine integration suites (5.252s) plus seven JS tests. This includes missing-revision/malformed-commit negative diagnostics and real candidate corruption; it does not establish repair of the owner's committed store.
- Downloaded the existing signed 89401 artifact from run `42098595922`, without rebuilding or distributing it. The extracted ExpoModulesJSI binary UUID exactly matches both supplied reports. Its symbol table identifies the second report's frame 13 as `expo::RuntimeScheduler::scheduleTask`; frame 6 is Expo's `callFunction` error wrapper. Other Swift frames lack usable line symbols in that binary, and the archive contains no matching ExpoModulesJSI dSYM. This corroborates the scheduling path but does not prove the exact originating async operation or a physical fix.
- Integrated replacement run [42515491917](https://github.com/davidpovarsky/hanlin-ai/actions/runs/42515491917) targets `db68b47e`, including canonical scheduler staging. Compilation passed; final overall result is FAILED as detailed below. No compilation-only result is counted as test acceptance.
- Staging audit during that run found the ScriptUI/Expo consumer still used unbounded `subprocess.run` and returned success when required installation/container lookup failed. It now reuses NativeScript's existing `run_bounded`, limits app/Files container lookups to five seconds, preserves Files as optional, and fails required preparation with nonzero exit. The workflow's initial device enumeration/boot is bounded too. Local `unittest discover -s Scripts/CI/Tests -q`: all 155 tests passed (57.505s), including six ScriptUI staging cases. This infrastructure correction changes no app source or fixture bytes; it is not a new execution of Apple UI tests.

## Integrated validation outcome and focused follow-up

- Run `42515491917` at `db68b47ed7de9f24823c8fccc7cce20427d34cc0` FAILED overall (simulator job 32m47s). App compilation passed (3m34s); initial simulator/fixture preparation took 5m45s; selected test execution/setup took 17m54s. These phases are measured, not estimated cache savings.
- EXECUTED_PASS: all 21 audio lifecycle XCTest cases including VR22 (4.492s); five Swift Testing cases across the model coordinator and two Skill contract suites; compact and wide management navigation (117.518s/95.821s); Expo dynamic package switching, lifecycle/uninstall and SwiftUI Probe (161.102s/53.174s/108.405s). This is simulator evidence, not physical acceptance.
- FAILED: All Models disappeared during transition. Keep two-stage size expansion but use native NavigationStack push instead of the inner matched zoom. The UI test now stops after a failed destination assertion, preventing a secondary absent-frame query from crashing the test runner. Transition acceptance remains pending fresh UI execution.
- BLOCKED_TEST_SETUP: ScriptWidget Package Information/status did not execute its assertions. The stager copied generated ScriptUI archives and `*.hanlinExpo`, omitting the checked-in `Hanlin-ScriptWidget-Actions.scripting` archive. It now stages checked-in `.scripting` archives too, with byte-for-byte coverage for both ScriptWidget fixtures and the legacy widget fixture. All six affected local staging tests pass after this correction.
- The cold simulator boot log records 49 seconds of migration. Initial boot allowance is 90 seconds rather than 45, retaining a strict bound without rejecting that observed successful boot. Container probes remain five seconds.
- Follow-up scope: failed All Models and installed ScriptWidget status UI; Expo import/lifecycle cases whose initial document list changes with the corrected fixture staging. Reuse the prior audio/Skill/coordinator/compact/wide results only with unchanged relevant code and assertions; preserve their original run provenance. No full-suite retry or new distribution.
- Headphone status in the owner screenshot does not identify which audio route-change reason was delivered. The category-change fix is validated in simulation; it does not prove every possible hardware input/output transition is repaired. Apple distinguishes route inputs and outputs: [Responding to audio route changes](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes).
- Original All Models screen recording corroborates a visible zoom defect: the popover stretches into an oval and overlays old and new content. Its failure hierarchy contains neither popover nor All Models controls. The test-runner crash is separate from an app crash; XCTest queried a missing frame after the first assertion failed.
- Focused follow-up [42519441278](https://github.com/davidpovarsky/hanlin-ai/actions/runs/42519441278) at `f1fb4367d0a5d4fa21d7129694b3937982e2508b`: BLOCKED_TEST_SETUP / overall FAILED. Compilation passed; all five selected UI tests were NOT_RUN because `simctl install` exceeded the newly enforced 60-second limit. Boot succeeded and the actual ScriptWidget fixture digests were present. Both NativeScript and ScriptUI staging now share a 180-second install allowance; mandatory installation still fails closed, and container lookups retain their separate bounds. All 38 affected staging/cache automation tests passed (14.853s). No new app-source changes or repeated passing unit suites are required for this setup correction.

## Input/output route ownership follow-up

- The route audit also found `.oldDeviceUnavailable` stopped recording even when only an output changed, while `.newDeviceAvailable` and `.routeConfigurationChange` could keep an incompatible input running. Recording now captures its active microphone UIDs and PCM format, and preserves the tap only when that input, format, owned `.record` category and engine remain valid. No suitable input always stops cleanly. Cleanup deactivates only the owned `.record` category, preserving another owner's `.playAndRecord` as well as `.playback`.
- VR22 now explicitly models microphone identity and verifies competing play-and-record ownership without deactivating that session. New VR23 covers output-only changes, microphone replacement, format changes and no-suitable-input handling, including preservation of the recording URL/file. The earlier 21-test result is invalidated for these changed route/cleanup paths; a fresh full `VoiceRecordingLifecycleTests` run is required.
- Local Swift frontend parsing passed; it validates syntax only. Installed Xcode compilation/execution is required for the Apple-framework declarations and behavior.
- The in-flight five-UI follow-up `42521106207` targets `7f8d60a7`, before this audio-only change. Its selected paths do not open VoiceInputView or start SpeechRecognizer recording. The model/Expo/widget-status code, test assertions and fixtures remain unchanged by this audio follow-up; preserve the UI run's original SHA rather than claiming new execution on the audio commit.
