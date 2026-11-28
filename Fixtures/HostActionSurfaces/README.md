# Dedicated genuine system-surface proof packages

These two NEW source packages exercise the installed foreground Expo or NativeScript app through existing Host services. They do not modify any original acceptance fixture, replace a runtime, or claim that source compilation proves an OS surface worked. They require the consolidated Host-action source and its freshly produced SDK; SDK20 predates the Host-action declaration.

| Property | Expo | NativeScript |
| --- | --- | --- |
| Archive name | SurfaceExpo.hanlinExpo | SurfaceNativeScript.hanlinNativeScript |
| Display name / widget entity | Surface Expo | Surface NativeScript |
| Widget gallery configuration | Hanlin Script | Hanlin Script |
| Stable app ID | hanlin.surface.expo | hanlin.surface.nativescript |
| Foreground runtime | Original Expo / React Native / Hermes | Original NativeScript |
| Widget renderer | Original Expo native widget renderer | Original ScriptWidget |
| Live Activity renderer | Existing shared native-node ActivityKit renderer | Original ScriptWidget ActivityKit renderer |
| Declared action | surface.run | surface.run |
| App Intent target | surface-intent | surface-intent |
| Share target | surface-share | surface-share |
| Translation target | surface-translation | surface-translation |

## Build with the original CLI and the current SDK

Run from the repository root with the original Node and Python prerequisites. SDK must be the newly generated SDK directory, not a stale SDK20 path. The CLI creates a new archive and refuses to overwrite an existing archive.

    node Scripts/MiniApps/miniapp.mjs validate --sdk "$SDK" --project Fixtures/HostActionSurfaces/expo --report "$OUT/expo-validate.json"
    node Scripts/MiniApps/miniapp.mjs build --sdk "$SDK" --project Fixtures/HostActionSurfaces/expo --archive "$OUT/SurfaceExpo.hanlinExpo" --report "$OUT/expo-build.json"
    node Scripts/MiniApps/miniapp.mjs validate --sdk "$SDK" --project Fixtures/HostActionSurfaces/nativescript --report "$OUT/nativescript-validate.json"
    node Scripts/MiniApps/miniapp.mjs build --sdk "$SDK" --project Fixtures/HostActionSurfaces/nativescript --archive "$OUT/SurfaceNativeScript.hanlinNativeScript" --report "$OUT/nativescript-build.json"

The NS build uses the original TypeScript emitter and shared native runtime dependencies. The Expo build uses original Metro. Both retain the authored source and SDK-bound validation. The original compiler, not manual ZIP editing, stages the explicit widget resource at its native-discovery path.

## Normal app controls

Both apps show a single status line:

    App ID: <appID> | Challenge: <fresh value> | Counter: <number> | Request ID: <last actual invocation ID or JS-handler nonce>

Both expose Prepare challenge, Start Live Activity, End Live Activity, Run all five runtimes, and Read last result. Expo additionally exposes Publish widget, which calls the original typed prepared-widget publication API. NS exposes Widget setup: its actual widget is published by normal installation; the button gives gallery instructions and does not manufacture a publication receipt.

Start Live Activity displays the actual authorization result, returned Activity ID, or error. The widget and activity buttons are Run Expo Surface and Run NativeScript Surface. The shared prepared-program gallery configuration is Hanlin Script; its installed entity is Surface Expo or Surface NativeScript. The separate original ExpoWidgets createWidget configuration is not this fixture route. OS rendering and placement must be observed separately.

Actual installedPackageID/packageID/generation must be read from the current published catalog. The JavaScript app does not invent those native ownership fields. The public surface-intent action uses the existing discoverable Run Script Action / Await result route. Share and Translation are explicit prepared-native declarations, mirroring the existing production routes; no native VM runs inside those extensions.

## Durable real result contract

Prepare challenge creates a new private state challenge and resets its counter. Each handler invocation increments the actual stored counter, generates a fresh nonce, preserves its complete incoming payload/caller, and sequentially calls the existing typed executeRuntime facade for node, typeScript, localPython, javaScriptCore, and shell. Each program returns the current app/challenge/nonce/counter marker; the handler checks the real receipt identity, failure flags, exit code, and actual output before declaring completed.

The returned and persisted SurfaceResult contains schemaVersion, appID, action, challenge, nonce, requestID, requestIDOrigin, caller, request, requestedSurface, counter, startedAt, finishedAt, status, and receipts[]. Each receipt row holds kind, marker, and the COMPLETE actual RuntimeExecutionResult, including any output-file references. A failure keeps partial actual receipts and an error; it never fabricates remaining engines or a successful result.

Expo receives the actual Host invocation UUID in its existing action callback. NativeScript's original callback supplies caller and payload but no invocation UUID, so requestIDOrigin is javascript-handler and requestID is the fresh JS nonce. Correlate that result with the real canonical receipt UUID in the current app-group queue. requestedSurface is a payload label, not independent proof of an OS launch.

The private file is surface-proof.json in the canonical app state area. Expo uses the typed Host readFile/writeFile with area state. NS uses the existing registerWindowFactory context's own storage.state and the original NativeScript File API; its app shows the resolved path. A fresh Shortcut window receives the UI-prepared challenge in its actual JSON input and writes only its own state; it never reads a sibling window's file. The file contains schemaVersion, appID, challenge, counter, activityID, and lastResult. Expo console output also includes the actual result prefixed [HanlinSurfaceProof]. NativeScript retains the complete result in its state file without requiring a console global.

The UI's Run all five runtimes is a foreground diagnostic only. It cannot count as a Widget, Live Activity, Shortcuts, Share, or Translation attempt. Those results require genuine system interaction plus matching current native delivery/receipt evidence. Neither an unavailable system surface nor a failed action is silently promoted to PASS.

## Origin and compatibility boundaries

Expo's Live Activity is the existing shared native-node ActivityKit API, now using the source.liveActivity-aware Host intent. It does not prove the separate original ExpoWidgets callback route. NS uses the ScriptWidget widget/Live Activity origin binding. No fabricated widgetOrigin is attached to the generic native-node path.

The NS metadata-selector declaration is a typed reference to the existing public HanlinNativeServicesBridge.h session selectors. Execution still goes exclusively through @hanlin/host-services. Both packages declare the current original library versions; the original SDK/compiler controls the actual prepared dependency closure. No npm install, native compilation, or alternate runtime is implemented by these fixtures.

These files are new proof sources, not a build or execution result. Actual compiler reports, archives, system attempts, and receipts must be retained separately.

## Additional Run MiniApp Action OS route

The same installed action is exposed through the standalone **Run MiniApp Action** entity picker. Choose **Dictionary or List (JSON)** and pass the fresh challenge shown by **Prepare challenge**, for example:

    {"surface":"miniAppShortcut","challenge":"<the actual visible challenge>","typed":{"text":"שלום עולם","count":42,"enabled":true,"empty":null}}

The fixture still runs and checks all five original Host runtimes. On this new route it also reports real invocation-owned progress. NativeScript retains observations of its bound window ID, state path, execution mode and actual native attachment. The returned result includes a fresh summary; it remains the complete actual result and receipts.

The existing paired runner has an additional, separate scope:

    PAIRED_TEST_SCOPE=miniapp_shortcuts_os python3 Scripts/ProductSplit/run_paired_acceptance.py

Use the original runner's existing source-qualified build environment, SPLIT_EVIDENCE and SPLIT_DERIVED_DATA. This scope builds these sources with the **current shipping SDK and original CLI**, stages only input archives, and selects four additional methods in HanlinEntrypointSystemSurfaceUITests. They use the real Shortcuts gallery/entity picker, verify the new default and saved Open When Run off/on choices across both process restarts, and compare the built-in Get Text from Input → Show Result chain with the exact native result.

The original paired54 plans and the original ten system-surface methods are unchanged. The read-only observe_shortcut_surfaces.py helper supplies only the existing Shortcuts observation exchange. It resolves actual post-XCTest MCM containers, the primary enabled installation/current generation, committed snapshot, native queue/terminal receipt, and matching private five-runtime result. It writes only XCTest coordination responses and evidence, never production grants, commands, receipts or state.

Portable validation of the reader is:

    python3 -B -m unittest discover -s Scripts/ProductSplit/Tests -p test_shortcut_surface_observer.py -v

Those unit inputs are temporary local fixtures, not system acceptance evidence. The four new UI methods require their actual Mac/Simulator run; source preparation and reader tests do not qualify native snippets, long-running cancellation, Home Screen shortcuts, Hebrew system layout, other surfaces or locked physical-device acceptance.
