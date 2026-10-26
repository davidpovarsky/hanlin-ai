# Build Contract: Hanlin Expo Native API Hybrid Architecture

This document defines the authoritative build contract for embedding NativeScript's Native API JSI, TurboModules, and Fabric components into the Hanlin Expo MiniApp runtime.

---

## 1. Architecture Overview

Hanlin Expo MiniApps run inside an isolated Hermes JavaScript runtime hosted within Apple SwiftUI.
The Native API Hybrid subsystem introduces direct C/Objective-C JSI access without modifying or replacing existing standalone runtimes:
- **Preexisting Runtimes Preserved**: `hanlinExpo` (Hermes + Expo UI) and `hanlinNativeScript` (V8 standalone) remain completely decoupled.
- **Embedded Hybrid Extension**: MiniApps with runtime `hanlinExpo` and capability `ios-native-api` gain access to `@nativescript/react-native@9.1.2` and `react-native-worklets@0.13.1`.
- **Three-Tier Isolation**:
  1. Static manifest inspection (`HanlinScriptAnalyzer`).
  2. Native authorization gate (`HanlinExpoNativeAPIGate`).
  3. Dynamic lifecycle revocation (dismissing active session and invalidating JSI bindings immediately upon capability loss).

---

## 2. Package & Dependency Graph

```
AI_HLY (Host Application)
  │
  ├── Packages/HanlinExpoRuntime (SwiftPM)
  │     └── Packages/HanlinExpoNativeAPI (SwiftPM)
  │           ├── Sources/HanlinExpoNativeAPI/bridge (HanlinExpoNativeAPIGate, HanlinExpoDependencyProvider)
  │           ├── Sources/HanlinExpoNativeAPI/native-api (C++ JSI & TurboModule bridge)
  │           ├── Sources/HanlinExpoNativeAPI/worklets (react-native-worklets 0.13.1)
  │           ├── Sources/HanlinExpoNativeAPI/fabric (NativeScriptUIViewComponentView)
  │           ├── Sources/HanlinExpoNativeAPI/codegen (Generated TurboModule & Fabric specs)
  │           ├── Frameworks/Libffi.xcframework (Prebuilt binary dependency)
  │           └── Resources/metadata/metadata-arm64.nsmd (Prebuilt binary iOS metadata)
  │
  └── Packages/HanlinPlatform (Contracts & Analyzer)
```

---

## 3. Toolchain & Compiler Requirements

| Component | Requirement | Authority / Notes |
|:---|:---|:---|
| **Xcode Version** | Xcode 27+ | Stable macOS runner (`xcode-27`) |
| **Swift Tools** | Swift 6.0+ | `swift-tools-version: 6.0` |
| **C++ Standard** | C++20 (`cxxLanguageStandard: .cxx20`) | Required by React Native 0.88 / Hermes JSI |
| **C Standard** | C17 (`cLanguageStandard: .c17`) | Required by libffi |
| **ObjC Interop** | Objective-C++ (`-ObjC++`, ARC enabled) | Required for Apple runtime interop |
| **Header Search Paths** | Modular headers via `Artifacts/ReactModularHeaders` | Strict clang non-modular include flags |

---

## 4. Binary Artifacts & Checksums

All binary dependencies and metadata files are pinned with sha256 checksums in `Scripts/Expo/dependency-lock.json` and `Scripts/ExpoNativeAPI/dependency-lock.json`:

| File | SHA256 Checksum | Purpose |
|:---|:---|:---|
| `Libffi.xcframework` | `330bf4370cfafbc12fcf5543cbe25c830eb8a37f59d5718a2eb36c1e5d713c77` | FFI dynamic function dispatch |
| `metadata-arm64.nsmd` | `b9f5afb7ce8547ca6ce2658fa1ef37e584f272a5a51c4a034988da1bcf12dc4c` | iOS SDK symbol and struct metadata |
| `@nativescript/react-native@9.1.2` | `04bf0745511dcbb8ec651f8931114b036d0ab1eb858cf0df8d519be9455351a6` | Authoritative upstream package |
| `react-native-worklets@0.13.1` | `d9feffb717b9b00e3952ba634f1ec52c93d25684fb6578a7b1b51e7a57a527fa` | Worklets UI threading engine |

---

## 5. Build Steps & Staging Automation

1. **Dependency Download & Verification**:
   ```bash
   node Scripts/ExpoNativeAPI/prepare-ios-dependencies.mjs
   ```
   Verifies tarball hashes against `dependency-lock.json`, stages C++ and ObjC++ files, generates and verifies `Libffi.xcframework`, and unpacks `metadata-arm64.nsmd`.

2. **Codegen Generation**:
   ```bash
   node Scripts/ExpoNativeAPI/generate-codegen.mjs
   ```
   Generates Fabric Component specs and TurboModule specs for React Native 0.88.

3. **Artifact Verification**:
   ```bash
   node Scripts/ExpoNativeAPI/verify-artifacts.mjs
   node Scripts/ExpoNativeAPI/verify-nsmd.mjs
   ```
   Validates header layout, framework bundle architecture, and metadata structure.

4. **Metro Probe Packaging**:
   ```bash
   node Scripts/ExpoNativeAPI/build-probes.mjs
   ```
   Produces deterministic `.hanlinExpo` bundles with Babel plugins applied.
