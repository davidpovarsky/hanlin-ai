# `@hanlin/expo-ui`

Hanlin's stable TypeScript surface for dynamically installed Expo MiniApps. It re-exports the
installed `@expo/ui/swift-ui` surface and adds downstream native SwiftUI components and generated
modifiers. MiniApps contain TypeScript/JavaScript only; all native bridge code is precompiled into
the Hanlin host.

The checked-in inventory is generated from focused interfaces on Windows. Run the generator against
the installed stable Xcode SDK's `SwiftUICore.swiftinterface` and `SwiftUI.swiftinterface` before a
release host build to refresh complete measured coverage.
