# Expo session isolation gate

The standalone Xcode test target compiles the production Objective-C++ gate, weak
runtime registry and Swift modifier ownership sources directly. It has no engine
binary dependencies. Twelve XCTest cases exercise A surviving B's open/close,
explicit runtime identity, identical host IDs in separate weak runtime namespaces,
UIKit root ownership, repeated/unknown shutdown, and first/last modifier owners.

The worklet values are test doubles. These focused Apple tests prove ownership and
cleanup behavior; they do not claim two actual Hermes/Expo UI applications have
been launched. The producer application native build covers the generated bridge,
NativeScriptUIView and actual runtime module.

The upstream NativeScript React Native 9.1.2 iOS sources are patched by
Scripts/ExpoNativeAPI/multiscene-patch.mjs, invoked by the established dependency
preparation pipeline. Canonical gate/header sources remain in bridge-source.
