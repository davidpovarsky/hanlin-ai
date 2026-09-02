# NativeScript SwiftUI foreground integration

Hanlin's iOS 26 foreground runtime supports the official
`@nativescript/swift-ui` 4.0.2 JavaScript API with NativeScript Core/iOS 9.1.0.
Prepared applications use `registerSwiftUI`, `UIDataDriver`, and `SwiftUI`.
The host compiles the provider contract and supported providers with Swift 6;
the link-time NativeScript metadata pass exposes those provider classes to the
JavaScript runtime.

## Installed-package contract

A `.hanlinNativeScript` archive uses the existing safe ZIP import/store path.
Its prepared application's adjacent `package.json` may declare:

```json
{
  "hanlinNativeScript": {
    "runtimeVersion": "9.1.0",
    "plugins": {
      "@nativescript/swift-ui": "4.0.2"
    }
  }
}
```

Import Preview rejects unknown plugins, invalid contracts, and version
mismatches before installation. Legacy plugin-free NativeScript Core packages
remain valid. Scripting's unrelated bare-module and capability rules are not
relaxed.

The installed artifact is launched from the active generation under
Application Support. The host owns the app lifecycle and presents the
NativeScript controller as full-content child UI. Dismissal shuts down the
single active runtime before another installed package starts.

## Security and extensibility boundary

This is a preembedded-provider model. Package JavaScript and resources may be
installed dynamically, but native Swift/Objective-C is neither compiled nor
dynamically loaded. Supporting another native plugin or a custom provider
requires review, an exact dependency pin, host compilation, metadata/preflight
coverage, and a new Hanlin build.

Exact registry integrity, source hashes, and runtime provenance are recorded in
`Scripts/NativeScript/dependency-lock.json`. Apache-2.0 attribution is retained
beside `HanlinNativeScriptRuntime`.
