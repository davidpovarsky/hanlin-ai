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
