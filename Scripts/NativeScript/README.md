# Hanlin NativeScript tooling

The original upstream resolver records the versions used by each host build in
`dependency-lock.json` and `package-lock.json`. Those files and
`get_miniapp_sdk(engine: "nativescript")` are the version authority for:

- `@nativescript/ios`, including the original macOS metadata generator;
- `@nativescript/core` and its native frameworks;
- `@nativescript/swift-ui` for the original `registerSwiftUI` / `UIDataDriver` path;
- `@nativescript/vite` for prepared fixture output.

Install with `npm ci --prefix Scripts/NativeScript`. Prepare the Core and SwiftUI test
roots with `node Scripts/NativeScript/prepare-fixture.mjs`. Prepared assets retain
their recorded source/version provenance; `node_modules` is not committed.

The existing metadata Host Services bridge has a typed `@hanlin/host-services`
facade. Inside a NativeScript session, import `createHostServices` and capture
that session once; `executeRuntime` returns the complete canonical runtime
receipt. `startRuntime` additionally returns its cooperative cancellation handle.
Use the five exact names `node`, `typeScript`, `localPython`, `javaScriptCore`,
`shell`. Shell source remains a complete approved command; separate argv is
rejected. This does not provide arbitrary OS subprocesses or another NS isolate.

Run `npm run check:host-services --prefix Scripts/NativeScript` after installation.
The pinned TypeScript5.9.3 compiler strictly checks the facade/example, requires
the four negative diagnostics TS2345/TS2353/TS2322/TS7006, and compares generated
JS/declarations byte for byte. After an intentional source change, regenerate
with `node Scripts/NativeScript/build-host-services.mjs --write`. Existing native
preparation runs the check and preserves the exact module while replacing the
shared runtime. Native metadata/VM and physical acceptance remain separate.

Before resolving Swift packages, run
`npm run prepare:ios-dependencies --prefix Scripts/NativeScript`. It derives the
complete XCFramework set and native API usage input from the pinned Core package,
checks the exact registry hashes in `dependency-lock.json`, confirms Core and
the iOS runtime match the resolved lock, and stages the
artifacts inside `HanlinNativeScriptRuntime`. `ios-spm` supplies the runtime;
Core supplies `TNSWidgets` and `NSCWinterTC`. SwiftPM links and embeds both
dynamic frameworks rather than copying unreferenced files into the app bundle.

`npm run preflight:ios-dependencies --prefix Scripts/NativeScript -- --app PATH`
validates the derived closure, real plugin JavaScript, prepared applications,
embedded frameworks, `TNSLabel`, the embedded SwiftUI provider symbol, and the
NativeScript metadata section before simulator launch.

The app target's `Generate NativeScript metadata` phase runs the original
generator with the actual generated Host/provider headers. It includes the
public umbrellas of Core's staged native frameworks and the available system
frameworks declared in Core's original `native-api-usage.json`. Required names
include `TNSLabel` and `NSCCrypto`: merely embedding their native binaries does
not expose them to JavaScript.

The phase declares its architecture-specific output before linking.
`hanlin-nsld.sh` delegates transparently to Xcode's real linker. The app embeds
the generated file in `__DATA,__TNSMetadata`, and the runtime selects that exact
host section through `Config.MetadataPtr`. The metadata inputs, header inventory
and compiler diagnostics remain available under
`build/acceptance/nativescript-metadata`; actual VM execution is verified separately.

The v1 native-plugin boundary is intentionally build-time. Installed packages
may use only exact native support already compiled into Hanlin; downloaded
Swift/Objective-C is never compiled or loaded as new executable code.
