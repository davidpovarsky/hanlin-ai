# Upstream Touchpoints & Integration Audit

This document records all modifications and integration points with upstream packages and host application code.

---

## 1. Upstream Package Ingest

### `@nativescript/react-native@9.1.2`
- **Source**: Published npm package `@nativescript/react-native@9.1.2` (commit tagged in `NativeScript/runtimes`).
- **Destination**: `Packages/HanlinExpoNativeAPI/Sources/HanlinExpoNativeAPI/`
- **Modifications**:
  - Injected `HanlinExpoNativeAPIGate.isNativeAPIAuthorizedForCurrentSession` checks inside `NativeScriptNativeApiModule.mm` at:
    - `install()`
    - `installWorkletRuntime()`
    - `NativeScriptCreateUIKitHost()`
  - Included `#import "HanlinExpoNativeAPIGate.h"` in `NativeScriptNativeApiModule.mm`.
  - Re-exported authoritative types and factories through `@hanlin/expo-native-api` (`Packages/HanlinExpoNativeAPIJS`).

### `react-native-worklets@0.13.1`
- **Source**: Published npm package `react-native-worklets@0.13.1`.
- **Destination**: `Packages/HanlinExpoNativeAPI/Sources/HanlinExpoNativeAPI/worklets/`
- **Modifications**: None (used as-is with React Native 0.88 compatibility).

---

## 2. Host Application Touchpoints

| File | Change Nature | Justification |
|:---|:---|:---|
| `Packages/HanlinExpoRuntime/Package.swift` | Added dependency | Adds `HanlinExpoNativeAPI` product dependency to runtime package. |
| `Packages/HanlinExpoRuntime/Sources/.../HanlinExpoSession.swift` | Lifecycle & Provider | Injects `HanlinExpoDependencyProvider`, Fabric component view provider, and authorization checks. |
| `Packages/HanlinExpoRuntime/Sources/.../HanlinExpoBridgeMetadata.swift` | Version metadata | Adds `nativeApiVersion: "9.1.2"` and `workletsVersion: "0.13.1"`. |
| `Packages/HanlinPlatform/Sources/.../HanlinIdentifiers.swift` | Capability enum | Adds `HanlinCapabilityID.iosNativeAPI` (`"ios-native-api"`). |
| `Packages/HanlinPlatform/Sources/.../HanlinScriptAnalyzer.swift` | Manifest inspection | Validates `@nativescript/react-native@9.1.2` and requires `ios-native-api`. |
| `AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift` | Host orchestration | Pass authorization to session and dismiss session upon capability revocation. |
| `AI_HLY.xcodeproj/project.pbxproj` | Project reference | Adds `HanlinExpoNativeAPI` package reference, target dependency, and framework linking phase. |
| `.github/workflows/validate-expo-runtime-spike.yml` | CI test plan | Adds package resolution check and UITest methods to test plan. |

---

## 3. Frozen Chat UI Files Audit

The following 4 frozen chat UI files were strictly audited:

| File | Git Status | Modified? | Hash Matching Baseline? |
|:---|:---|:---|:---|
| `AI_HLY/ChatView.swift` | Untouched | **NO** | **YES** (`aae2bfda...`) |
| `AI_HLY/Views/Components/ChatViewBottom.swift` | Untouched | **NO** | **YES** (`c9c9d123...`) |
| `ChatViewComponents.swift` | Untouched | **NO** | **YES** (`8ee2da15...`) |
| `ChatandFile.swift` | Untouched | **NO** | **YES** (`e888a7c2...`) |

Zero lines were added, modified, or removed from these files.
