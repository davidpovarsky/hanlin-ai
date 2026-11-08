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

- Audio implementation `978888a2933413b3f5d6ad2e3bbb2db03a432c52`; focused run [42511840857](https://github.com/davidpovarsky/hanlin-ai/actions/runs/42511840857) dispatched. Result pending, not a pass.
- Widget recovery test audit found `testPass7InterruptedRevisionWriteOverwrittenAndClean` did not create a corrupt file at all. It now seeds authentic candidate revision paths with both zero bytes and nonempty corrupt bytes and asserts exact restored bytes. Existing committed-revision integrity rejection remains required: candidate repair must not imply arbitrary reconstruction of lost committed user state.
- Widget validation: execute the changed test with the existing `widget-package` workflow filter; unaffected renderer/action tests retain their original historical provenance, without claiming execution on this SHA.
