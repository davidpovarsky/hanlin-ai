# Standalone target validation — 2026-11-15

Tasks: K `1219656771637321`, L `1219656771460030`; acceptance H/I remains open.
Branch: `codex/hanlin-app-split-wave1-20261115`, starting source `acbd95992b33216f95d5668daa98f00ed001a6df`.

Added a real `HanlinMiniApps` application target (`com.itorah.hanlinminiapps`) and its independent scheme/UI-test target. The existing AI target and bundle ID remain in place. The new target explicitly shares the existing package platform, native host sources, canonical registrations and runtime packages. It does not import AI's entry point, Chat UI, model records or provider adapter. The AI SwiftData/provider connection now lives in an AI-only extension and injects assistant operations into the existing platform. A single descriptor authorization implementation serves both hosts. Production split package membership excludes all three disk-fixture adapters.

The MiniApps composition uses the original restore/import/install/detail/launch implementations for Swift/ScriptUI/NativeScript/Expo. App Groups are source configuration only; real provisioning and OS sharing have not been verified. AI retains its current stores. No live store move, destructive migration or external distribution is performed.

## Impact and execution plan

New target membership, composition, shared platform initialization and authorization extraction invalidate any assumed application acceptance. No historical Parity or durability pass is reused as an installed-target pass. All 278 capability IDs and 26 UX decisions remain in their original inventory; this tranche does not turn their statuses into PASS.

Execute only the new standalone scheme's three XCUITests on a newly created disposable simulator: catalog to real compiled app; canonical private state across process relaunch; existing package-import screen. Check actual Xcode/SDK/runtime/device/architecture and source hashes on the Mac. Retain the exact command, raw xcodebuild log, xcresult, screenshots/accessibility attachments where created, and distinct early-infrastructure/build/test statuses. The repository's native dependency preparation is reused. Maestro/idb availability is recorded; XCUITest does not depend on them.

Local execution: `verify_targets.py` SOURCE_VALIDATED (56 existing shared source files); Python syntax and workflow YAML parsed; SwiftPM manifest dump succeeded; `git diff --check` passed. These checks are not Apple compilation or UI acceptance. The two newly authored descriptor-policy tests have not executed.

Remaining acceptance includes simultaneous independent AI+MiniApps installation, complete package lifecycle/runtime behaviors, validated cross-app transport/cold launch/exact chat return, real reversible migration and data retention, missing-app fallback, signed App Group/Keychain/CloudKit behavior, broad iPhone/iPad/RTL/accessibility coverage, physical device and explicitly requested TestFlight acceptance.

## First native invocation

Run [43723335133](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43723335133), source `4595df71b8164e4da92408d3abb3bd53d3d0f8ad`, ended in `INFRA_ERROR` after 3m26s. The Mac verified macOS 27.0.1/arm64, Xcode 27.2 (27B52), iOS simulator SDK 27.2 and available iOS 27.0 (24A434), with about 36 GiB free. `plutil` accepted the real project/entitlement documents; target source checks passed. The pinned metadata tool compiled. ios-simulator-skill scripts/idb/Maestro were not found on this runner; XCUITest was available. Native dependency preparation reached the missing RuntimeCore release lookup, then stopped. No app build or UI case started; no xcresult/simulator screenshot exists because the native test step was never reached.

Original evidence: artifact [14165182052](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43723335133/artifacts/14165182052), 6599 bytes, API SHA256 `06cec9afc3fedef43e8764ab85bd58b1d6fe3474ce48a2200a7078b0b674dcf5`. Original preflight/status files were downloaded; no full archive digest recomputation is claimed. The dependency source correction explicitly selects existing successful candidate `42926628418`, documented in `docs/runtime/CHAT_AND_AUTONOMY_IMPLEMENTATION_2026-11-10.md`; GitHub API authenticated unexpired artifact `13813704965`, outer SHA256 `f329036ba1ed870b9afb43ed164418f987505361d2a3276bfef1a89826cab850`. The existing consumer enforces the locked inner bundle checksum `196a35562a31229b1bcf05afbe49f76470ced90a7fbf0494ecebd5c06d07440f` and native source identity. No release publication is needed or performed.

Additional local execution: all 34 cases in `Scripts/CI/Tests/test_cache_and_ci_optimization.py` passed (4.787s; terminal evidence). This is CI automation regression evidence, not native/UI acceptance.
