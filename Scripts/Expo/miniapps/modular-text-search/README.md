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
