# Hanlin NativeScript tooling

The package lock pins the official npm distributions used by this integration:

- `@nativescript/ios` `9.1.0`, including the official macOS metadata generator;
- `@nativescript/core` `9.1.0`;
- `@nativescript/vite` `8.0.0` for deterministic prepared fixture output.

Install with `npm ci --prefix Scripts/NativeScript`. Prepare the two small test
roots with `node Scripts/NativeScript/prepare-fixture.mjs`. Generated output and
`node_modules` are intentionally not committed.

Before resolving Swift packages, run
`npm run prepare:ios-dependencies --prefix Scripts/NativeScript`. It derives the
complete XCFramework set and native API usage input from the pinned Core package,
checks that Core and the iOS runtime are both exactly 9.1.0, and stages the
artifacts inside `HanlinNativeScriptRuntime`. `ios-spm` supplies the runtime;
Core supplies `TNSWidgets` and `NSCWinterTC`. SwiftPM links and embeds both
dynamic frameworks rather than copying unreferenced files into the app bundle.

`npm run preflight:ios-dependencies --prefix Scripts/NativeScript -- --app PATH`
validates the derived closure, prepared JavaScript, embedded frameworks, and the
`TNSLabel` Objective-C class before simulator launch.

The app target's `Generate NativeScript metadata` phase runs the pinned
upstream generator and declares its architecture-specific output before
linking. `hanlin-nsld.sh` delegates the final link to Xcode's real linker. The
app embeds the generated file in `__DATA,__TNSMetadata`; NativeScript uses that
standard section when `Config.MetadataPtr` is not set.
