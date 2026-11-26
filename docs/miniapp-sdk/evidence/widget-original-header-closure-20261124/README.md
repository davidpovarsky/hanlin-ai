# Original Expo header import closure — MAIN15

Status: the original import failure is reproduced and corrected in a focused real compiler comparison. The production native project and its generator are corrected. Full configured Xcode 27.2 app/native acceptance remains pending.

## Actual failure and cause

MAIN15 (`45412939674`, source `e2227ccdfe0c3111d1c17ef2b4bb1653ac24bb9c`) failed the first MiniApps build with exit 65. The native widget extension could not resolve four original React headers while importing ExpoModulesCore. Those exact headers exist in the authenticated prepared header archive. The failing native command already had the original Clang search roots and definitions; adding those same widget roots again would not address the observed distinction.

The successful package consumers used explicit module loading. The native extension inherited `SWIFT_ENABLE_EXPLICIT_MODULES = NO` from Config.xcconfig. A real primary-Mac comparison used the same authenticated headers/interfaces, Swift 6, C++ interop, application-extension mode and consumer flags with two separately created empty module caches.

| Actual execution | Outcome | Boundary |
| --- | --- | --- |
| Implicit original import | Exit 1, 17.006 seconds; the same four missing headers | SDK 27.0 import typecheck |
| Explicit original import | Exit 0, 12.723 seconds; original private Swift interface freshly compiled | SDK 27.0 import typecheck |
| Existing consumer configuration case | 1 passed; actual project generation/idempotence and flag preservation | Python generator case with real Mac-evaluated manifests |

The generic original-interface SDK/compiler-version message follows the missing headers. The explicit run compiled that same interface, so this evidence does not establish a separate binary incompatibility.

## Production correction

`Scripts/SDK/update_project.py` now applies the original evaluated ExpoWidgets import flags and target-level explicit module loading after standalone extension cloning. The six demonstrated consumers are HanlinApp, HanlinMiniApps, AI_HLYTests, HanlinMiniAppsTests, HanlinScriptingWidgets and HanlinMiniAppsWidgets. The five direct-import targets and the hosted-test transitive edge are recorded in `consumer-import-sources.json`.

The generated project changes only 12 existing Debug/Release configuration objects. Both widget hosts retain their original Clang flag lists. The other four consumers gain those original flags while retaining inherited settings. All six keep objcxx mode and override implicit loading with YES. Unrelated targets, the global Config setting, original headers, upstream APIs, package manifests, signing and target memberships are unchanged.

The existing `test_real_widget_consumers_preserve_original_expo_cpp_import_contract` case now verifies all six native consumers, both configurations, original producer parity, preserved custom scalar flags, actual updater generation and repeated-generation stability. No new case or native selector is added.

## Evidence and reuse

`receipt.json` binds the authentic artifact/build log, three modified source hashes, input inventory, exact compiler commands, logs and independent review. `input-manifest.json.gz` retains the exact uncompressed input manifest whose SHA256 is recorded in the receipt. No original header implementation or interface was rewritten for the probe.

`mac-preflight.json` records the actual 15:18 UTC primary Mac observation: Xcode 27.0/27A266a, Swift 6.4.0.34.1, simulator SDK 27.0, no active build process and adequate capacity. This is a capability record for that time, not proof that configured 27.2 is available.

The three unchanged manifests were evaluated by the primary Mac through `xcrun swift package dump-package`. `run-focused-parity.py` uses those genuine results with only the task-root path relocated to the canonical Oracle checkout, allowing the existing full project producer to read its real source tree. No target/settings/assertion behavior was substituted.

Independent read-only review confirmed the exact three source hashes and 12-object semantic delta. Neither the compiler comparison nor the focused case was repeated by the reviewer.

After integration, only the existing reachability generator and its `--check` are required for these paths because the project file is a whole-file source anchor. The parent owns that regeneration and the next configured native gate. No app link, device behavior, OS widget rendering or any of the 52 acceptance cases is claimed here.
