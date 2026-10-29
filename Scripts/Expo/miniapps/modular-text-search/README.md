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

The modules in src/engines and src/logic are copied from the user's .scripting archive without functional API changes. App.tsx is an independent Expo UI port of the Scripting screen and components. The screen uses the preinstalled @hanlin/expo-ui native SwiftUI Host/List/Searchable/Popover/TextField bridge and React state.

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
