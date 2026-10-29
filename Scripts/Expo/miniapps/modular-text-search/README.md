# חיפוש טקסטים מודולרי — Hanlin Expo MiniApp

Portable recreation of the user-supplied חיפוש טקסטים מודולרי.scripting project for Hanlin's embedded Expo + SwiftUI runtime.

Host: Hanlin TestFlight 86201, commit 0504bd660e61a079d4488e10bce14f872fbcc431 (Expo UI bridge 3.0.0).
Installable file: dist/ModularTextSearch.hanlinExpo.

## Preserved features

- Native iOS SwiftUI search interface, Hebrew/English UI, quick queries.
- Original Sefaria API search logic, response normalization, grouped version results, full-text loading, and text-version rendering.
- Engine registry, modular source adapters, advanced six-tab options: engine/search/sort/filters/text/debug.
- All search and full-text options, including sheet/text types, sorting, filters, slop, and version selection.
- Next-page loading, Sefaria source links, error and progress states.

The modules in src/engines and src/logic are copied from the user's .scripting archive without functional API changes. App.tsx is an independent Expo UI port of the Scripting screen and components. The screen uses the preinstalled @hanlin/expo-ui native SwiftUI Host/List/Popover/TextField bridge and React state.

## Scope boundary

The original .scripting archive also includes Shortcut Snippet, App Intents, Share Sheet, and translation-provider entrypoints. A dynamically installed .hanlinExpo package cannot create new host-level iOS extensions or system actions, so only the foreground app was ported. The user-supplied .scripting archive retains those original files.

No new native binaries, Expo plugins, host entitlements, or TestFlight host changes are required.
Web API calls need network access to https://www.sefaria.org.
Physical-device behavior remains unverified until installation on the iPad.

## Rebuild (Windows)

Requires Scripts/Expo node_modules prepared using the repository's existing Expo install tooling.
In PowerShell, run from this folder: ./build.ps1

This script checks TypeScript, invokes the pinned local Metro/React Native CLI, and packs bundle.js, package.json, and script.json into dist/ModularTextSearch.hanlinExpo. It does not run Xcode, CI, simulator, or TestFlight.


## 1.0.1: TestFlight 86201 crash workaround

An iPad TestFlight crash during Sefaria search had signature SIGABRT on React's ObjCTurboModule::performVoidMethodInvocation background queue. That confirms an uncaught native exception in the RN TurboModule path, but the crash report does NOT identify the throwing module.

Version 1.0.1 no longer calls React Native fetch for Sefaria requests. Instead, the package uses the existing Hanlin Expo host-services bridge to run a restricted HTTPS request through the embedded Node runtime. Both runtime.node and network capabilities must be approved on install. All requests are scoped to https://www.sefaria.org, and failures become visible errors instead of being allowed to escape from the search function.

The automatically invoking next-page onAppear modifier was also removed to avoid a possible repeated-load/render feedback loop. Pagination now requires pressing the More Results button.

Verification performed: TypeScript 6 check passes; Metro creates a release iOS bundle; standalone Node transport integration test passes with a real Sefaria HTTP 200 POST request. Native iPad installation and absence of the original crash are NOT YET VERIFIED.

Run the transport check from the package directory: node tests/network-transport.test.cjs


## 1.0.2: No visible results fix + device diagnostics

The original quick-query buttons only changed the text and never invoked search. This update makes them actually submit a search. It also removes the native Searchable wrapper and adds a persistent, native SwiftUI TextField and explicit Search button. The submit code now merges the active advanced search options rather than discarding them.

Search status and errors are displayed directly beneath the query field. An optional Check connection button queries live host permissions for runtime.node/network and executes a small Node readiness probe; failures show diagnostic text rather than an apparently empty list.

Verification: the real Sefaria search integration test retrieves 10 hits and groups them into 2 source cards; Node transport test passes; UI wiring regression test passes; TypeScript 6 check passes; Metro builds a release iOS bundle.

No new iOS host or TestFlight release is needed, but these Windows-side checks cannot prove the SwiftUI screen and Node bridge function on the user's iPad. Please confirm on device; read visible diagnostics if it still fails.


## 1.0.3: Use iOS NSURLSession instead of embedded Node networking

TestFlight 86201 device feedback from 1.0.2 proved the cause of no results: the embedded Node 24.5.0 runtime produced a stream of unmanaged file-descriptor warnings and TypeError: fetch failed in Undici. The search options and Sefaria query itself were not the cause.

The Sefaria transport now uses the native Apple NSURLSession public Foundation APIs through the already-compiled NativeScript 9.1.2 JSI bridge. Its completion handler uses jsInvoker so NSURLSession's background-queue response is delivered to the React Native JS thread before resolving a search promise. No React Native fetch and no Node fetch are used. Both search POST and full-text GET use the same transport.

The package now declares ios-native-api and network capabilities. It does not request runtime.node; both of the new capabilities must be approved during installation or update. Native access is broad and restricted by the package code to HTTPS API endpoints on www.sefaria.org, with capability checks before each request.

The Check connection control now sends an actual one-hit search using NSURLSession, rather than only testing Node startup. Native transport errors are displayed in the miniapp UI.

Verification:
- Live Sefaria search of the Hebrew word for life returned ten hits through the NativeScript API mock's NSURLSession callback path.
- Disallowed URL hosts and revoked network permission are rejected by the native transport.
- Existing search UI wiring and visible-error tests passed.
- TypeScript 6 validation and Metro production iOS bundle compilation passed.

These Windows-side tests cannot test the JSI/Objective-C callback against the physical iPad's Apple runtime. Install the .hanlinExpo on Hanlin TestFlight 86201, grant ios-native-api and network, and use Check connection if necessary.


## 1.1.0: All-native SwiftUI interface

This update replaces the hand-built card / chip / HStack / VStack presentation with actual native SwiftUI primitives from the embedded Expo UI bridge:
- Real iOS Searchable attached to the native result List, using the keyboard Search action.
- System List and Section for grouped results, examples, search progress and messages.
- Tappable native NavigationLink rows, opening native NavigationDestination source detail screens.
- Native LabeledContent for result metadata; native DisclosureGroup for full-text versions.
- Native Form, Picker, Toggle and TextField for all advanced settings.
- Native Menu and Toolbar for access to options, language and connection diagnostics.
- Native ContentUnavailableView for initial empty state and Link for the Sefaria source.

No hand-built HStack/VStack cards, colors, rounded rectangles, or badges are present in the application UI. React manages state and data; Expo UI renders the visible native Apple components. The temporary React Native View root wrapper is removed.

The iOS NSURLSession/NativeScript transport from version 1.0.3 remains unchanged and is still used for both search and full-text requests. The required permissions remain ios-native-api and network.

Tests on Windows verify search submission wiring, native component usage, grouped result navigation, permission declarations, the unchanged transport, and a live Sefaria request through a test implementation of the URLSession callback. TypeScript 6 and Metro production bundling passed. Native presentation behavior requires confirmation on the iPad.

## v1.1.1: Native search event repair

The iPad reported that v1.1.0 rendered but both search and the connection check stopped responding. This release removes the nested Expo Toolbar/Menu wrapper around the Searchable component and restores the proven React Native View -> SwiftUI Host structure from v1.0.3. Native Button controls are direct List rows, not menu items. A native DisclosureGroup provides an alternative native TextField and Search Button if the platform Searchable keyboard event does not fire. Native Searchable, List, NavigationLink, Form, DisclosureGroup, and other native controls remain intact.

A visible status message is updated synchronously by the search and connection-test button handlers, distinguishing event propagation from network failures. Existing iOS NSURLSession transport and capabilities ios-native-api/network are unchanged.

GitHub Actions can build the installable package without a host TestFlight rebuild. This release still requires physical iPad confirmation; static tests cannot prove iOS event propagation.


## 1.1.2: Recover visible native List / search controls

The iPad screenshot showed the native title and Searchable field but no List contents; the 1.1.1 Searchable wrapper was hiding all actionable controls. The root List now attaches directly to NavigationStack with a native TextField, Button, Section and NavigationLink. All result rows and detail screens stay native SwiftUI. The problematic Searchable wrapper is intentionally disabled until its iOS host child-content rendering can be verified on a device; keeping it would leave the app unusable. The previously verified NativeScript/NSURLSession transport is unchanged.

The app displays 'Hanlin Expo 1.1.2' inside the root List as an on-device indicator. If that label is not visible, the native List or its host rendering is still broken and the issue requires host-level iOS simulator/device diagnostics.


## 1.2.0: Native Searchable restored with bridge fix (requires updated Host)

This package is for the Hanlin host containing commit 050bceb4358a6feb000b06de451318190ec0f910 or descendant. The SwiftUI Searchable field is again native and the native List is its direct React child, which is rendered by the revised Hanlin Expo bridge without a nested HanlinSlotView. The Sefaria NSURLSession transport is unchanged. DO NOT install on TestFlight Build 86201: the old host native bridge still loses the wrapped List. Host-level XCUITest remains required before a new signed TestFlight build is distributed.
