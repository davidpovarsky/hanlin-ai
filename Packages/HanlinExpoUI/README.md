# `@hanlin/expo-ui`

Hanlin's stable TypeScript surface for dynamically installed Expo MiniApps. It re-exports the
installed `@expo/ui/swift-ui` surface and adds downstream native SwiftUI components and generated
modifiers. MiniApps contain TypeScript/JavaScript only; all native bridge code is precompiled into
the Hanlin host.

The checked-in inventory is generated from focused interfaces on Windows. Run the generator against
the installed stable Xcode SDK's `SwiftUICore.swiftinterface` and `SwiftUI.swiftinterface` before a
release host build to refresh complete measured coverage.

## Authoring contract

Import views from `@hanlin/expo-ui` and modifiers from `@hanlin/expo-ui/modifiers`. The package is a
superset: upstream Expo UI symbols are re-exported, mechanically bridgeable gaps are generated, and
semantic gaps use small Hanlin-native adapters. Controlled inputs consistently use `value`,
`defaultValue`, and `onValueChange` where applicable.

Expo's typed `environment` modifier is the supported environment channel for `colorScheme`,
`editMode`, `locale`, and `timeZone`; `dynamicTypeSize` and accessibility modifiers are also
re-exported. Arbitrary `EnvironmentObject` and `PreferenceKey` lifetimes are deliberately unsupported.
Scene ownership (`App`, `WindowGroup`, document/settings scenes) remains host-lifecycle-only for an
embedded MiniApp.

`hostServices` exposes the existing capability-gated Hanlin runtime and MiniApp file services to Expo
JavaScript. It does not create a second broker: calls are JSON/base64 transported into the same
`HanlinHostCallContext` and unified host-service brokers used by other runtimes.

Packages declare `hanlinExpo.bridgeVersion`; import analysis and runtime launch reject a package that
requires a newer bridge. `Scripts/Expo/build-probe.mjs` runs a TypeScript project semantic check before
Metro so native component props and generated declarations are checked before packaging.
