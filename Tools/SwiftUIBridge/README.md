# Hanlin SwiftUI bridge generation

The generator parses `SwiftUICore.swiftinterface` and `SwiftUI.swiftinterface` with SwiftSyntax,
builds one canonical IR, compares it with the installed Expo UI declarations, and emits native
modifier registration, TypeScript declarations, version metadata, and coverage reports.

The checked-in output is intentionally labeled `fixture-ios26` because this Windows checkout has no
Apple SDK. A release refresh must invoke the same command with the two interfaces from the selected
stable Xcode SDK and a concrete SDK identity. The generated report records SHA-256 hashes for both
inputs. No generated timestamp is used.

`Scripts/Expo/inventory-expo-ui.mjs` derives Expo's view and modifier exports from the installed
58.0.3 declaration files through the TypeScript compiler API. `rules.json` is the deliberate map for
manual adapters, unsupported generic semantics, and host-lifecycle-only APIs.

The tooling aliases `typescript` to `@typescript/typescript6` because TypeScript 7.0 does not expose
a programmatic compiler API. The semantic authoring check uses its `tsc6` executable before Metro.

## Flow and reproducibility

```text
Apple .swiftinterface files -> SwiftSyntax IR -> classification
  -> generated Expo Swift views/modifiers + generated TypeScript
  -> @hanlin/expo-ui -> Metro/Hermes -> dynamic .hanlinExpo MiniApp
```

First refresh the installed Expo surface with `node Scripts/Expo/inventory-expo-ui.mjs`. Run
`hanlin-swiftui-bridge` with both SDK interfaces, `Tools/SwiftUIBridge/configuration.json`, an explicit
SDK identity, and destinations for `Generated/SwiftUIBridge`, the runtime's `Generated` directory,
and `Packages/HanlinExpoUI/src/generated`. Re-run the same command with `--check` to compare every
artifact byte-for-byte. Inputs are hashed and outputs intentionally contain no timestamps.

`rules.json` is the only manual decision map. New SDK declarations that are not mechanically safe
remain `needs-investigation`; generic object lifetimes are `unsupported`; scene APIs are
`host-lifecycle-only`; and non-core framework inputs are classified as `companion-framework` rather
than silently treated as SwiftUI core.
