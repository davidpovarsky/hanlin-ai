# Source-to-Test Matrix

**Author:** Roni (QA & Evidence)  
**Execution Context:** NORMAL Mode (Direct Session)  
**Date:** 2026-10-27  

---

| Source File / Artifact | Category | Rationale | Test ID | Verification Status |
|---|---|---|---|---|
| `Scripts/Expo/package.json` | Tooling | Pin stable RN 0.88, React 19.3, Expo 58, Worklets 0.13.1, NativeScript RN 9.1.2 | `LOC-01`, `LOC-02` | **PASS** |
| `Scripts/Expo/dependency-lock.json` | Lockfile | Update stable RN 0.88 / Hermes 260318099.0.4 binary tarballs and hashes | `LOC-01`, `LOC-02` | **PASS** |
| `Scripts/ExpoNativeAPI/dependency-lock.json` | Lockfile | Upstream NativeScript RN 9.1.2 & Worklets 0.13.1 exact provenance and integrity | `LOC-01`, `LOC-02` | **PASS** |
| `Scripts/Expo/prepare-ios-dependencies.mjs` | Scripts | Strict cache validation preventing stale RC binaries masquerading as stable | `LOC-02`, `PKG-02` | **PASS** |
| `Scripts/ExpoNativeAPI/prepare-ios-dependencies.mjs` | Scripts | Native API and Worklets artifact preparation & verification | `LOC-03`, `PKG-01`, `PKG-02` | **PASS** |
| `Scripts/ExpoNativeAPI/build-probes.mjs` | Scripts | Deterministic packaging of test `.hanlinExpo` bundles without recompilation | `LOC-05`, `UI-01`, `UI-02` | **PASS** |
| `Scripts/Expo/babel.config.cjs` | Bundler | Babel & Worklets plugin transform configuration (`strictGlobal: true`) | `LOC-01`, `LOC-05` | **PASS** |
| `Packages/HanlinExpoNativeAPI/Package.swift` | SwiftPM | Link NativeScript JSI, Fabric component, and RNWorklets into host closure | `LOC-03`, `NAT-01` | **PASS** |
| `Packages/HanlinExpoNativeAPI/Sources/*` | Native | Native authorization gate, session context binding, lifecycle teardown | `LOC-03`, `UI-01`, `UI-02` | **PASS** |
| `Packages/HanlinExpoRuntime/Package.swift` | SwiftPM | Include `HanlinExpoNativeAPI` product, unified RN/Hermes binary linkage | `NAT-01`, `REG-01` | **PASS** |
| `Packages/HanlinExpoRuntime/Sources/.../HanlinExpoSession.swift` | Host | Inject RN dependency provider before JS eval, enforce session-scoped gate | `UI-01`, `UI-02`, `LC-01` | **PASS** |
| `Packages/HanlinPlatform/Sources/.../HanlinScriptAnalyzer.swift` | Importer | Accept `@nativescript/react-native@9.1.2`, require declared `ios-native-api` | `NAT-01`, `NAT-02`, `UI-03` | **PASS** |
| `AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift` | Platform | Check capability grant before native-enabled session launch; terminate on revoke | `UI-01`, `UI-03` | **PASS** |
| `Packages/HanlinExpoNativeAPIJS/` (`@hanlin/expo-native-api`) | JS Facade | Thin TypeScript facade exporting NativeScript RN API contract `1.0.0` | `LOC-04`, `LOC-05` | **PASS** |
| `Fixtures/ExpoNativeAPIProbe/` | Fixture | Combined SwiftUI + UIKit native controls, `defineUIKitView`, `RNHostView` | `LOC-04`, `LOC-05`, `UI-01` | **PASS** |
| `AI_HLYUITests/HanlinExpoNativeAPIIntegrationUITests.swift` | E2E Tests | iOS 27 simulator integration tests: mount, switch, revoke, A/B swap | `UI-01`, `UI-02`, `UI-03`, `UI-04` | **READY_FOR_CI** |
| `Scripts/ExpoNativeAPI/Tests/*.test.mjs` | Static Tests | Static Babel plugin ordering, Worklets config, lock integrity, no duplicate symbols | `LOC-01`, `LOC-02`, `LOC-03` | **PASS** |
