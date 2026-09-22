# Hanlin SwiftUI bridge generation

The generator parses `SwiftUICore.swiftinterface` and `SwiftUI.swiftinterface` with SwiftSyntax,
builds one canonical IR, compares it with the installed Expo UI declarations, and emits native
modifier registration, TypeScript declarations, version metadata, and coverage reports.

The checked-in production output is generated from the complete device interfaces exported from the
selected stable Xcode iPhoneOS SDK. Test fixtures remain under the generator test target only. The
generated inventory and coverage report record Xcode, SDK, target variant, selected source paths,
and SHA-256 hashes for both inputs. No generated timestamp is used.

`Scripts/Expo/inventory-expo-ui.mjs` derives Expo's view and modifier exports from the installed
58.0.3 declaration files through the TypeScript compiler API. Reviewed Expo capabilities are kept in
`expo-reviewed-capabilities.json`; symbol presence alone is not treated as Apple overload parity.
`rules.json` is the deliberate map for manual adapters, unsupported generic semantics, and
host-lifecycle-only APIs.

The tooling aliases `typescript` to `@typescript/typescript6` because TypeScript 7.0 does not expose
a programmatic compiler API. The semantic authoring check uses its `tsc6` executable before Metro.

## Flow and reproducibility

```text
Apple .swiftinterface files -> SwiftSyntax IR -> classification
  -> generated Expo Swift views/modifiers + generated TypeScript
  -> @hanlin/expo-ui -> Metro/Hermes -> dynamic .hanlinExpo MiniApp
```

Use `apple-sdk-interface SwiftUI SwiftUICore --sdk iphoneos` from the shared `apple-devtools`
repository to export the authoritative interfaces and machine-readable manifest. On Windows this
routes to the configured macOS/Xcode authority; the downloaded files belong in a local untracked
directory and must never be committed.

First refresh the installed Expo surface with `node Scripts/Expo/inventory-expo-ui.mjs`. Run
`hanlin-swiftui-bridge` with both full interfaces, `--sdk-manifest`,
`Tools/SwiftUIBridge/configuration.json`, an explicit SDK identity, and all three destinations:
`Generated/SwiftUIBridge`, the runtime's `Generated` directory, and
`Packages/HanlinExpoUI/src/generated`. Re-run the identical command with `--check`; it compares the
canonical report plus both runtime copies byte-for-byte. Inputs are hashed and outputs contain no
timestamps, so a second generation must be identical.

The bridge version is a host capability version. Regenerating for a new Xcode SDK, adding generated
native wrappers, or adding a manual adapter requires one new Hanlin host build. MiniApps that stay
within the bridge surface already installed in that host remain JavaScript-only and can be installed
or updated without recompiling the host.

Coverage is per signature as well as per symbol. A symbol is `partial` whenever only some overloads
map to a typed surface. New SDK declarations that are not mechanically safe remain
`needs-investigation`; every unresolved signature carries a machine-readable reason. Generic object
lifetimes are `unsupported`, scene APIs are `host-lifecycle-only`, and non-core framework inputs are
classified as `companion-framework` rather than silently treated as SwiftUI core.
