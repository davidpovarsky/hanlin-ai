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
