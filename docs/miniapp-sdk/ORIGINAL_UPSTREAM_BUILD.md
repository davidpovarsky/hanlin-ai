# Original MiniApp inputs at host build time

The release and paired-app validation workflows resolve current original upstream inputs before installing packages, restoring input-sensitive caches, or compiling native targets. `Scripts/MiniApps/resolve-upstreams.mjs --apply` writes one exact graph for that build. Its report is `build/acceptance/miniapp-upstreams/resolution.json`; the workflows also retain the source diff and export the resulting native artifacts with their original input hashes.

## Expo and React Native

The resolver reads the original `expo` publication and its `bundledNativeModules.json`. React, React Native, Worklets, Expo UI and brownfield versions come from that SDK's supported ranges. The `expo-modules-core` and `expo-modules-jsi` relationship comes from their original dependency metadata. React Native supplies the actual Hermes version. This prevents choosing unrelated newest React/Worklets releases and calling the resulting combination an Expo SDK.

The resolver updates the original npm package locks, local Hanlin peer relationships, native artifact checksums and the Native API codegen/runtime closure together. The installed native packages and the authoring SDK must match those exact inputs. A successful resolution is recorded as `applied-awaiting-native-build`; it is not evidence of an Xcode compilation or a device run.

The public `HANLIN_EXPO_RUNTIME_VERSION` and `getInstalledBridgeMetadata().runtimeVersion` identify the installed original Expo UI runtime. The resolver updates the generator configuration and both canonical/installed TypeScript and Swift metadata files in the same transaction as that graph. The source audit rejects a stale or divergent mirror. `bridgeVersion` identifies the independent Hanlin bridge ABI, while the generator’s reviewed `expoUIVersion` coverage input records which original declaration set its optional Apple API inventory was reviewed against. A runtime update preserves that coverage record until its separate review is performed.

Some recent Expo publications contain original source without a precompiled native archive. `build-original-expo-source.mjs` generates an isolated producer project with the original Expo CLI, installs the original CocoaPods dependency graph, and builds Expo UI for device and simulator using its original podspec. This project is a build tool; it does not replace Hanlin's application projects or entitlements. The existing native preparer runs the original ExpoModulesJSI SwiftPM producer and records the actual source, compiler and graph identities. A missing current binary never falls back to a binary from an earlier SDK.

Original React Native declaration corrections are narrowly authenticated against both declaration and implementation hashes. The currently audited files are identical in RN 0.88.0 and 0.88.1. Changing a version while preserving those exact files is allowed; changing the audited files requires a real type-contract repair. Expo authoring checks the original declaration bodies as well as the source.

## NativeScript

The original Core, iOS runtime, SwiftUI integration, Vite tooling and native declaration packages are resolved from their publications. The exact `ios-spm` tag revision and all SwiftUI source/runtime hashes accompany the npm inputs. The NativeScript package's SwiftPM dependency and the unified root package manifest are regenerated from those same versions. The native metadata producer still uses the actual selected Apple SDK and compiled host boundary.

The SDK includes original Core global types and original iOS/Android declaration packages. It follows NativeScript’s consumer configuration: `strict: true` for user code and API usage, with `skipLibCheck: true` for the internals of the upstream declaration files. The exact policy is exposed in the SDK manifest. This is not reported as a clean validation of all upstream declaration bodies; a project can explicitly set `skipLibCheck: false` to request those diagnostics. Real UIKit globals and wrong native API properties are exercised in consumer checks. The shipped `@hanlin/host-services` package is copied from the same generated runtime resource package, including its actual declarations and JavaScript.

## ScriptWidget and original renderer sources

The original ScriptWidget renderer files and editor catalogs are resolved to one immutable upstream commit. Expo widget renderer inputs come from the exact npm publications selected for the build. Existing downstream adaptations are merged against the previous original source with a three-way merge. New ScriptWidget component files inside the original component directory are included. Conflicts retain a repair diff and fail the update before changing the host checkout.

The manifest distinguishes original source files from authored Hanlin host adapters that cite upstream contracts. In particular, `HanlinScriptWidgetRuntime.swift` and the combined `HanlinExpoWidgetNative.swift` are host integrations, not renamed copies of the complete upstream app runtime. Their current upstream contracts and changes are authenticated and recorded separately. Updating a contract reference is not presented as implementing every service from the original application. API declarations must continue to describe the real registered host globals until the corresponding original services are integrated and exercised.

The current ScriptWidget authoring package includes the actual native component catalog and the original runtime service closure installed by Hanlin. Service declarations are generated from the installed Swift JSExport protocols and registration bindings: 41 globals, 24 native objects and 118 exported methods in the recorded baseline. Original Calendar, Contacts, Health, Home and the other integrated providers retain their real native implementations. The source manifest distinguishes this closure from unrelated upstream app screens. Generated declarations and configured system entitlements describe the installed contract; they do not establish that a device-specific service or remote account has been exercised successfully.

## Reproducible outputs

The build contains the exact resolution receipt, original tarball integrities, immutable source revisions, native artifact digests, generated host version constants and package-lock digests. The native SDK exporter validates and packages the already-prepared original frameworks and host resources. Reusing those artifacts requires the same source inputs; it does not rebuild or claim additional runtime acceptance.

For a read-only resolution and merge preview:

```sh
node Scripts/MiniApps/resolve-upstreams.mjs --cache=/tmp/hanlin-miniapp-upstreams
```

For the original host build inputs:

```sh
node Scripts/MiniApps/resolve-upstreams.mjs --apply --cache=/tmp/hanlin-miniapp-upstreams
node Scripts/MiniApps/install-tooling.mjs --engine=nativescript --ignore-scripts
npm run prepare:ios-dependencies --prefix Scripts/NativeScript
node Scripts/MiniApps/install-tooling.mjs --engine=expo --ignore-scripts
node Scripts/Expo/prepare-ios-dependencies.mjs
bash Scripts/Runtime/prepare-runtime-host.sh
```

Run this preparation before opening the generated projects or invoking `xcodebuild`. Direct Xcode incremental builds and generic `apple-build` use the prepared dependency graph; they do not refresh upstream sources through a late target build phase. The automatic full-build entrypoints run resolution before native preparation: `testflight.yml`, both app-producing jobs in `build-ios26-unsigned-ipa.yml`, `validate-app-split.yml` (except signing-only inspection), `validate-expo-runtime-spike.yml`, and `validate-performance-regression.yml`.

`install-tooling.mjs` invokes the original `npm ci`. Its reusable receipt binds package/lock inputs, the installed transitive graph, retained original JavaScript/declaration bytes, and the current local Hanlin package sources. A missing declaration, changed transitive file or stale local copy requires preparation again even when the version number is unchanged. Authenticated upstream declaration corrections can reseal only their explicitly checked files. SDK staging verifies that same installation before exporting it.

The first command is the automatic release-build path. The checked-in exact graph remains a reproducible baseline for isolated tooling tests. Neither path expands the optional full Apple SDK generator, introduces a custom home entrypoint, or resumes the frozen legacy Scripting engine.
