# Source-to-Test Matrix

**Author:** Roni (QA & Evidence)  
**Execution Context:** NORMAL Mode (Direct Session)  
**Date:** 2026-10-27  

---

| Source File / Artifact | Category | Rationale | Test ID | Verification Status |
|---|---|---|---|---|
| `Scripts/Expo/package.json` | Tooling | Pin stable RN 0.88, React 19.3, Expo 58, Worklets 0.13.1, NativeScript RN 9.1.2 | `LOC-06`, `LOC-08` | **PASS** (Local & CI) |
| `Scripts/Expo/dependency-lock.json` | Lockfile | Update stable RN 0.88 / Hermes 260318099.0.4 binary tarballs and hashes | `LOC-08` | **PASS** (Local & CI) |
| `Scripts/ExpoNativeAPI/dependency-lock.json` | Lockfile | Upstream NativeScript RN 9.1.2 & Worklets 0.13.1 exact provenance and integrity | `LOC-08` | **PASS** (Local & CI) |
| `Scripts/Expo/prepare-ios-dependencies.mjs` | Scripts | Strict cache validation preventing stale RC binaries masquerading as stable | `LOC-01`, `PKG-01` | **PASS** (Local & CI) |
| `Scripts/ExpoNativeAPI/prepare-ios-dependencies.mjs` | Scripts | Native API and Worklets artifact preparation, static slices, and strict patching | `LOC-01`, `LOC-02`, `LOC-03`, `LOC-04`, `SYN-01`, `SYN-02`, `IDM-01` | **PASS** (Local & CI) |
| `Scripts/ExpoNativeAPI/build-probes.mjs` | Scripts | Deterministic packaging of test `.hanlinExpo` bundles with static timestamps | `LOC-07`, `UI-01`, `UI-02` | **PASS** (Local & CI) |
| `Scripts/Expo/babel.config.cjs` | Bundler | Babel & Worklets plugin transform configuration (`strictGlobal: true`) | `LOC-06` | **PASS** (Local & CI) |
| `Packages/HanlinExpoNativeAPI/Package.swift` | SwiftPM | Multi-target architecture: Swift target, NativeScript MRC target, Worklets ARC target | `LOC-02`, `LOC-03`, `NAT-01` | **PASS** (SwiftPM Dump & CI) |
| `Packages/HanlinExpoNativeAPI/Sources/HanlinExpoNativeAPICore/` | Native | NativeScript JSI, Fabric component, and native authorization gate | `LOC-02`, `SYN-01`, `SYN-02`, `UI-01`, `UI-02` | **PASS** (Local syntax & CI) |
| `Packages/HanlinExpoNativeAPI/Sources/HanlinExpoWorklets/` | Native | RNWorklets 0.13.1 C++/ObjC++ source closure with ARC enabled | `LOC-02`, `LOC-05`, `UI-01` | **PASS** (Local & CI) |
| `Packages/HanlinExpoRuntime/Package.swift` | SwiftPM | Include `HanlinExpoNativeAPI` product, unified RN/Hermes binary linkage | `NAT-01`, `REG-01` | **PASS** (SwiftPM Dump & CI) |
| `Packages/HanlinExpoRuntime/Sources/.../HanlinExpoSession.swift` | Host | Inject RN dependency provider before JS eval, enforce session-scoped gate, bind runtime | `UI-01`, `UI-02`, `UI-05`, `UI-06` | **PASS** (Local & CI) |
| `Packages/HanlinPlatform/Sources/.../HanlinScriptAnalyzer.swift` | Importer | Accept `@nativescript/react-native@9.1.2`, require declared `ios-native-api` | `NAT-01`, `NAT-02`, `UI-03` | **PASS** (Local & CI) |
| `AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift` | Platform | Synchronous revocation before first await; dismiss active app on capability change | `UI-05`, `UI-06` | **PASS** (Local & CI) |
| `Packages/HanlinExpoNativeAPIJS/` (`@hanlin/expo-native-api`) | JS Facade | Thin TypeScript facade exporting NativeScript RN API contract `1.0.0` | `LOC-07` | **PASS** (Local & CI) |
| `Fixtures/ExpoNativeAPIProbe/` | Fixture | Combined SwiftUI + UIKit native controls, `defineUIKitView`, `RNHostView` | `LOC-07`, `UI-01` | **PASS** (Local & CI) |
| `AI_HLYUITests/HanlinExpoNativeAPIIntegrationUITests.swift` | E2E Tests | iOS 27 simulator integration tests: mount, switch, revoke, A/B swap, 20-cycle lifecycle | `UI-01`..`UI-07` | **EXECUTED_CI** |
| `Scripts/ExpoNativeAPI/Tests/*.test.mjs` | Static Tests | Static Babel plugin ordering, Worklets config, lock integrity, Libffi architecture | `LOC-01`..`LOC-08`, `SYN-01`, `SYN-02`, `IDM-01` | **PASS** (12/12 Clean TAP) |
