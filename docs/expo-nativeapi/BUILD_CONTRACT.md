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
  2. Native authorization gate (`HanlinExpoNativeAPIGate` with per-runtime and per-session bindings).
  3. Dynamic lifecycle revocation (dismissing active session and invalidating JSI bindings synchronously before persistence).

---

## 2. Package & Multi-Target Graph

```
AI_HLY (Host Application)
  │
  ├── Packages/HanlinExpoRuntime (SwiftPM)
  │     └── Packages/HanlinExpoNativeAPI (SwiftPM Product)
  │           │
  │           ├── HanlinExpoNativeAPI (Swift Target)
  │           │     ├── HanlinExpoNativeAPIManager.swift
  │           │     └── Resources/metadata/*.nsmd (Target-owned resources via Bundle.module)
  │           │
  │           ├── HanlinExpoNativeAPICore (Clang/ObjC++ Target, MRC -fno-objc-arc)
  │           │     ├── nativescript/ios (NativeScript RN JSI & Fabric)
  │           │     ├── bridge (HanlinExpoNativeAPIGate, HanlinExpoDependencyProvider)
  │           │     ├── generated/NativeScriptNativeApiSpec (iOS-only Codegen)
  │           │     └── Libffi binary target (ios-arm64, ios-arm64_x86_64-simulator)
  │           │
  │           └── HanlinExpoWorklets (Clang/ObjC++ Target, ARC -fobjc-arc)
  │                 ├── Common/cpp & apple (RNWorklets C++/ObjC++ source)
  │                 └── generated/rnworklets (iOS-only Codegen)
  │
  └── Packages/HanlinPlatform (Contracts & Analyzer)
```

---

## 3. Toolchain & Compiler Requirements

| Component | Requirement | Authority / Notes |
|:---|:---|:---|
| **Xcode Version** | Xcode 27+ | Stable macOS runner (`xcode-27`) |
| **Swift Tools** | Swift 6.2 / Swift 6 mode | `swift-tools-version: 6.2`, `swiftLanguageModes: [.v6]` |
| **C++ Standard** | GNU++20 (`-std=gnu++20`) | Required by React Native 0.88 / Hermes JSI / Worklets |
| **ARC Policy** | Separated per target | `HanlinExpoNativeAPICore`: `-fno-objc-arc`; `HanlinExpoWorklets`: `-fobjc-arc` |
| **Header Search Paths** | Modular headers via `Artifacts/ReactModularHeaders` | Strict clang non-modular include flags |
| **Platform Target** | iOS 27.0 (`.iOS("27.0")`) | Target platform for Hanlin AI on iOS / iPadOS |

---

## 4. Binary Artifacts & Checksums

All binary dependencies and metadata files are pinned with sha256 checksums in `Scripts/Expo/dependency-lock.json` and `Scripts/ExpoNativeAPI/dependency-lock.json`:

| File | SHA256 Checksum | Purpose |
|:---|:---|:---|
| `@nativescript/react-native@9.1.2.tgz` | `906f2106215426e6211c27f37fe2e874b9d91d174efbabb1d8b512fcdb2d4798` | Authoritative upstream package |
| `react-native-worklets@0.13.1.tgz` | `9d7a0e35344d454a8c661e01b6846252f4b016ef813a178a84768aa1197c5f9c` | Worklets UI threading engine |
| `metadata.ios.arm64.nsmd` | `50aabcb10723560a74500001cc2d64a034c05a5c755de35127fcc7601a7909f3` | iOS device metadata |
| `metadata.ios-sim.arm64.nsmd` | `33296faebf7f32db36d70304aef5fe27dfc1a283df6487c53d8a0a5931e4e73c` | iPadOS simulator arm64 metadata |
| `metadata.ios-sim.x86_64.nsmd` | `c811940bcb2202189473f52a2ccc368b34f3124a7d7f677e6702af61b0112d66` | iPadOS simulator x86_64 metadata |
| `Libffi.xcframework/ios-arm64/libffi.a` | `!<arch>\n` archive (>50KB) | Device static FFI library |
| `Libffi.xcframework/ios-arm64_x86_64-simulator/libffi.a` | Universal Mach-O fat binary (`0xcafebabe`, 97760 bytes) | Simulator static FFI library |

---

## 5. Build Steps & CI Automation Sequence

1. **Vendor Dependency Download & Idempotent Patching**:
   ```bash
   node Scripts/ExpoNativeAPI/prepare-ios-dependencies.mjs
   ```
   Verifies tarball SHA256 against `dependency-lock.json`, extracts `libffi.a` slices, stages `.nsmd` into `Artifacts/metadata` and `Sources/HanlinExpoNativeAPI/Resources/metadata`, generates iOS-only Codegen, and applies strict idempotent patch to `NativeScriptNativeApiModule.mm`.

2. **Artifact & NSMD Verification**:
   ```bash
   node Scripts/ExpoNativeAPI/verify-artifacts.mjs
   node Scripts/ExpoNativeAPI/verify-nsmd.mjs
   ```
   Validates header layout, framework bundle architecture, slice presence, and metadata NSMD magic header.

3. **Preflight & Static Unit Tests**:
   ```bash
   node Scripts/ExpoNativeAPI/preflight.mjs
   node --test Scripts/ExpoNativeAPI/Tests/*.test.mjs
   ```
   Validates Babel plugin ordering, dependency lock, multi-target architecture, ARC separation, and entrypoint denial gates.

4. **Deterministic Probe Packaging**:
   ```bash
   node Scripts/ExpoNativeAPI/build-probes.mjs
   ```
   Produces deterministic `.hanlinExpo` bundles with static timestamps and sorted archive entries.
