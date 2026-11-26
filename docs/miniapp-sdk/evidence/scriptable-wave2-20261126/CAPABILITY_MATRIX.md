# Scriptable 1.8 / MiniApps two-wave capability audit

Source boundary: this lane began at c34dd6ae752b3ab3ebc001743fc62c72fc48a203; its committed changes through a78f50d7 plus the Developer Studio and drawing checkpoints are listed below. Root integration and the separately owned widget lane may contain newer receipts. This matrix does not supersede their exact-SHA test results.

Labels: CODE_PRESENT means inspected source; IMPLEMENTED means a new source change; EXECUTED means an actual run with the stated scope; NATIVE_PENDING / DEVICE_PENDING / OS_PENDING are remaining gates, not successes.

| Plan item | Actual source and ownership | Observed evidence / remaining gate |
| --- | --- | --- |
| 00 Baseline and upstream comparison | Original Expo/RN, NativeScript and shared ScriptWidget are active; frozen Scripting-JSC/ScriptUI are not reactivated. Installed SDK declarations were read by Mac ops; root additionally observed an available iOS 27.2 simulator runtime (24B8117) with xcrun at 2026-11-26 13:23:22 UTC. | CODE_PRESENT. Build toolchain: Xcode 27.0 (27A266a), iPhoneOS SDK 27.0. Available simulator runtime: iOS 27.2 (24B8117). Runtime availability is not an executed app/test result. Original PR19 owner keeps its own exact native gate. |
| 01 Long-running Shortcuts | Standalone MiniAppsShortcutIntent.swift uses LongRunningIntent, CancellableIntent, foreground modes, opt-in long execution, canonical queued actions, owned headless platform and real progress. | IMPLEMENTED at 7f2cddd3. Callback lifetime helper EXECUTED 3 portable tests. AppIntents compile/actual Shortcuts background, foreground, cancellation and timeout NATIVE_PENDING. Long execution defaults off. |
| 02 Interactive Toggle | Mac widget lane owns original Expo Toggle/SetValueIntent, prepared renderer desired value and ScriptWidget action integration. | Independently reviewed state generation/corruption/path protections and captured timeline proof. Use that lane's exact source/test receipt; not certified by this matrix. |
| 03 Extra-large portrait and all families | Mac widget lane owns eight-family Swift and canonical SDK mappings. Installed WidgetKit declares systemExtraLargePortrait at iOS 27.0. | Declaration verified, not device availability. App extension/native render and iPad family selection NATIVE_PENDING / DEVICE_PENDING. |
| 04 Transparency, tint and backgrounds | Original ScriptWidget image accent/background APIs already present; Mac lane adds actual WidgetKit container/background integration. | CODE_PRESENT / separate implementation. Home Screen, Lock Screen and tinted rendering require actual system-surface captures. |
| 05 Dictionary/List I/O | HanlinShortcutValueCodec + standalone text/JSON/IntentFile selection and canonical output. Existing Apple API does not expose arbitrary heterogeneous Dictionary as an IntentValue. | Codec EXECUTED 12 portable cases at a28e977d. Actual JSON IntentFile and Shortcuts Dictionary/List conversion NATIVE_PENDING. Do not claim a fabricated [String: Any] AppIntent parameter. |
| 06 Concurrency/lifecycle | Existing queue/store generation admission plus new exactly-once completion; owned per-invocation runtime; per-activity serialization and latest submitted revisions. Root preserved pre-existing teardown/invocation dictionaries when merging. | Completion 3 and per-activity queue 3 portable tests EXECUTED. Cross-runtime/extension same-installation and independent-installation native scenarios remain in root's gate. |
| 07 Live Activities and Dynamic Island | Original Expo LiveActivityFactory/ActivityKit sources and NS host service start/update/list/end exist. HanlinScriptWidgetDynamicIsland has all seven regions; original native region/function-component tests already exist. a78f50d7 fixes same-activity state lost updates and end races. | Queue 3 portable tests EXECUTED. Extended actualActivityKitStartsUpdatesAndEndsTheOriginalProgram adds concurrent updates/two activities/namespace/end rejection. Its Apple run, restored activities, all actual system regions and physical Island/iPad behavior remain NATIVE_PENDING / DEVICE_PENDING. APNs push requires actual configured/provisioned delivery. |
| 08 Buttons, refresh, Progress/Gauge/Chart | Original engine UI/component code already contains these surfaces. Mac lane owns the expanded original Expo eight-family component fixture and widget interaction routing. | CODE_PRESENT, with exact engine/module limits to be taken from native fixture results. Source spelling or rendered-node construction alone is not system interaction acceptance. |
| 09 Timelines and last successful render | eb8a5829 adds verified prepared-render records keyed by installation/generation/engine/family/settings/program SHA. Original Expo timeline/LKG belongs to Mac lane. | Prepared LKG 11 native regression cases written; NATIVE_PENDING. No stale disabled/expired/generation-mismatched render is an allowed fallback. Expo lane separately adds locked state, checksum/backup and captured ownership proof. |
| 10 Editor, folders, gallery, drawing | No actual FileWorkshop/editor found in inspected app/shared paths. New standalone Studio uses the existing compiler/SDK, file coordination, conflict/recovery, folder metadata and actual SDK examples. Original ScriptWidget already has center-default rotationEffect and bounded/downsampled image pipeline. | Studio editor 4 + workspace 4 portable tests EXECUTED; Apple UI/iCloud/example install-run NATIVE_PENDING. Original ScriptWidget numeric transform gaps are fixed; 9 native image cases are added. A fifth gallery project exercises original NativeScript UIKit center drawing. Fresh SDK/native/UI acceptance remains pending. No frozen Canvas/DrawContext API is claimed live. |
| 11 Shared strict SDK and consumers | SDK declarations are generated through original tooling; Shortcut progress host services were added canonically. Hanlin consumes shared authoring/types/agent surfaces, not a second MiniApps runtime. | Source and strict tests from root's regenerated combined facade are authoritative. This lane's editor query uses that same canonical resolver and original TypeScript compiler. |
| 12 Integration and release | Root owns exact integration SHA, native selection, original PR19 gate coordination, signed app/extension packaging and Asana milestone logs. | NATIVE_PENDING / DEVICE_PENDING / OS_PENDING until actual receipts. None of the portable tests is an app build, archive, IPA or TestFlight receipt. |

## Exact item 07 selectors

- AI_HLYTests/HanlinOriginalScriptWidgetLiveActivityTests/actualActivityKitStartsUpdatesAndEndsTheOriginalProgram
- AI_HLYTests/HanlinOriginalScriptWidgetLiveActivityTests/originalRegionsPersistOutsideActivityContentAndActionsProduceFreshSnapshots
- AI_HLYTests/HanlinNativePresentationTests/testOriginalDynamicIslandCapturesAllSevenNativeRegionsAndFunctionComponents
- Packages/HanlinPlatform/Tests/HanlinScriptExtensionsTests/HanlinLiveActivityOperationQueueTests (the portable helper already passed; package/native inclusion remains root's gate)

These selectors cover the assertions in their code, not an unqualified all-Live-Activities acceptance. Region-node decoding does not prove the OS displayed those regions on an actual Dynamic Island.

## Primary upstream comparison

The Scriptable release notes were consulted for scope, not copied as a new architecture contract:
https://apps.apple.com/bo/app/scriptable/id1405459188?platform=mac

Exact API references:
- https://scriptable.app/docs/reference/drawcontext/ — drawImageInRect optional clockwise degrees around the destination rectangle's center.
- https://scriptable.app/docs/reference/filemanager/ — Files tags inherit existing tag colors; the API cannot create new colored tags.
- https://github.com/microsoft/typescript/wiki/using-the-language-service-api — original compiler language-service completions/signature help.
- https://docs.expo.dev/versions/latest/sdk/imagemanipulator/ — original Expo SDK 58 image manipulation exists upstream; embedding is not inferred from that documentation alone.
- Installed AppIntents/WidgetKit proof: /mnt/development/projects/evidence/hanlin-two-wave-storage-20261126/installed-ios27-api-receipt.json.

iOS 27.0 compile/runtime evidence must be labeled 27.0. The parent native coordinator observed iOS 27.2 simulator runtime 24B8117 available at 2026-11-26 13:23:22 UTC. Criteria naming 27.2 now require execution on that runtime; they are not blocked by simulator availability. Installed build SDK remains 27.0. OS_PENDING in this matrix means the required runtime scenario has not executed, not that the simulator is unavailable.
