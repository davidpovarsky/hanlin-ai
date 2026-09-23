# Runtime, tooling, and diagnostics acceptance

The focused simulator acceptance is collected by:

```bash
python3 Scripts/Runtime/run_runtime_tooling_acceptance.py \
  --project AI_HLY.xcodeproj \
  --scheme AI_HLY \
  --configuration Release \
  --destination 'platform=iOS Simulator,id=<booted-simulator-udid>' \
  --derived-data build/DerivedData \
  --source-packages build/SourcePackages \
  --output-dir build/acceptance \
  --commit "$(git rev-parse HEAD)" \
  --branch "$(git branch --show-current)" \
  --xcode-version "$(xcodebuild -version | tr '\n' ' ')" \
  --simulator-device '<simulator model>' \
  --simulator-os '<simulator runtime>'
```

CI first performs one `build-for-testing`, then the collector runs independent
`test-without-building` groups. An ordinary test failure or test-process crash is
recorded and does not prevent later groups from running. The collector exits
nonzero only after all groups have been attempted.

Reports are written to:

- `build/acceptance/runtime-tooling-acceptance.json`
- `build/acceptance/runtime-tooling-acceptance.md`
- `build/acceptance/xcresults/`

The JSON report is the machine-readable authority. It records commit and branch,
Xcode and simulator metadata, timings, group status, individual case status,
expected rejections, crashes, errors, and artifact paths. Arguments, package
credentials, API keys, cookies, and response bodies are not copied into it.

## Pinned package fixtures

- npm CommonJS: `is-number@7.0.0`
- npm ESM: `yocto-queue@1.2.2`
- PyPI pure wheel with dependencies: `requests==2.34.2`
- PyPI native-extension rejection: `numpy==2.5.3`

The package group performs preview, install, list, probe, real runtime import and
use, persistence through a new manager/runtime instance, uninstall, and missing
or invalid package rejection. Registry failures remain failures and are labeled
as external infrastructure; they are never converted into passes.

## Acceptance groups

- canonical tool contracts and semantic diagnostics
- RuntimeCore and Unified Host Services routing
- npm and PyPI package lifecycles
- Files, SQLite, and live capability policy
- Swift, ScriptUI, NativeScript, and Expo mini-app bridges
- deterministic production Agent conversation loop
- real application launch and chat UI presentation

The deterministic provider is enabled only in the iOS Simulator process with
`HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE=1`. It is not reachable in a device or normal
production launch.

## Device-only follow-up

Simulator acceptance does not establish real-device behavior for HealthKit,
Contacts, camera, microphone, speech recognition, Face ID, memory/background
pressure, or signed NativeScript/Expo framework linkage. Run the adjacent
`ON_DEVICE_ACCEPTANCE.md` checklist on a signed iPad/iPhone build. NativeScript
also retains the documented upstream single-active-session limitation.
