# Upstream Touchpoints & Integration Audit

This document records all modifications and integration points with upstream packages and host application code.

---

## 1. Upstream Package Ingest & Independent Derivative Context

Per `AGENTS.md`, Hanlin is an independently maintained derivative of CherryHQ/hanlin-ai. Upstream mergeability is not a primary architectural constraint; code maintainability and authoritative downstream architecture take precedence.

### `@nativescript/react-native@9.1.2`
- **Source**: Published npm package `@nativescript/react-native@9.1.2`
- **npm dist.integrity**: `sha512-sqgsqg++6etbihWzLeIeSi7OxlmAsEegxz4yHerqCbYBuxyrVnTrtK4vDNnTYbNM+q6u2b0hwDNhX0aOEKTeTw==`
- **Tarball SHA256**: `906f2106215426e6211c27f37fe2e874b9d91d174efbabb1d8b512fcdb2d4798`
- **Destination**: `Packages/HanlinExpoNativeAPI/Sources/HanlinExpoNativeAPICore/`
- **Modifications**:
  - Injected `HanlinExpoNativeAPIGate` checks inside `NativeScriptNativeApiModule.mm` at all four native entrypoints:
    - `install()` -> `isNativeAPIAuthorizedForRuntime`
    - `installWorkletRuntime()` -> `isNativeAPIAuthorizedForRuntime`
    - `NativeScriptCreateUIKitHost()` -> `isNativeAPIAuthorizedForCurrentSession`
    - `NativeScriptRunUIKitHostLifecycle()` -> `isNativeAPIAuthorizedForCurrentSession`
  - Injected `#import "HanlinExpoNativeAPIGate.h"` and `#import "HanlinExpoDependencyProvider.h"`.
  - Re-exported authoritative types and interfaces through `@hanlin/expo-native-api` (`Packages/HanlinExpoNativeAPIJS`).

### `react-native-worklets@0.13.1`
- **Source**: Published npm package `react-native-worklets@0.13.1`
- **npm dist.integrity**: `sha512-sX55Vx89/Y9uJmvAbAGoHXBZvCWXtYPGWPJ9Z9yl0h76mP9A10ULlSrixzGqBFLXeQMBpIpyJEhWpzXP7GG6YA==`
- **Tarball SHA256**: `9d7a0e35344d454a8c661e01b6846252f4b016ef813a178a84768aa1197c5f9c`
- **Destination**: `Packages/HanlinExpoNativeAPI/Sources/HanlinExpoWorklets/`
- **Modifications**: Multi-target Clang isolation with `-fobjc-arc` and C++20 standard; excludes out-of-platform Android/JNI sources.

---

## 2. Host Application Touchpoints

| File | Change Nature | Justification |
|:---|:---|:---|
| `Packages/HanlinExpoNativeAPI/Package.swift` | Multi-target architecture | Splits Swift orchestration (`HanlinExpoNativeAPI`), NativeScript MRC target (`HanlinExpoNativeAPICore`, `-fno-objc-arc`), and Worklets ARC target (`HanlinExpoWorklets`, `-fobjc-arc`). |
| `Packages/HanlinExpoRuntime/Package.swift` | Added dependency | Adds `HanlinExpoNativeAPI` product dependency to runtime package with header search paths. |
| `Packages/HanlinExpoRuntime/Sources/.../HanlinExpoSession.swift` | Lifecycle & Provider | Injects `HanlinExpoDependencyProvider`, Fabric component view provider, and binds runtime pointer to session ID. |
| `Packages/HanlinExpoRuntime/Sources/.../HanlinExpoBridgeMetadata.swift` | Version metadata | Adds `nativeApiVersion: "9.1.2"` and `workletsVersion: "0.13.1"`. |
| `Packages/HanlinPlatform/Sources/.../HanlinIdentifiers.swift` | Capability enum | Adds `HanlinCapabilityID.iosNativeAPI` (`"ios-native-api"`). |
| `Packages/HanlinPlatform/Sources/.../HanlinScriptAnalyzer.swift` | Manifest inspection | Validates `@nativescript/react-native@9.1.2` and requires `ios-native-api`. |
| `AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift` | Host orchestration | Synchronously calls `revokeActiveSession()` and `dismissActiveApplication()` before persistence on capability revocation. |
| `AI_HLY.xcodeproj/project.pbxproj` | Project reference | Adds `HanlinExpoNativeAPI` package reference, target dependency, and framework linking phase. |
| `.github/workflows/validate-expo-runtime-spike.yml` | CI test plan | Adds dependency preparation, verification, and UI integration test selectors. |

---

## 3. Frozen Chat UI Files Audit

The following 4 frozen chat UI files were strictly audited against baseline ancestor `0c0e6ab61607f19aa52f01bad1d0d1e4f7dfcf78`:

| File | Git Status | Modified? | SHA-256 Hash Matching Baseline |
|:---|:---|:---|:---|
| `AI_HLY/ChatView.swift` | Untouched | **NO** | `1571911d14f3decf24c757f8f233a5a655476f19e48830f2c36016719a18847c` |
| `AI_HLY/Views/Components/ChatViewBottom.swift` | Untouched | **NO** | `161862b7718d7e2b4678517a5d5f06400719df9862e87dd3b083ae2595874c28` |
| `AI_HLY/Views/Components/ChatViewComponents.swift` | Untouched | **NO** | `43ccf9e91e806ae253af554f55070b6256a5a2a10cd02a0974ffbfd37cc27baa` |
| `AI_HLY/Views/Components/ChatandFile.swift` | Untouched | **NO** | `007111fb74ca3d237b07bbd9dc3f66bb0a021cbf89aa5a23a1f0a0ac28c9e135` |

Git diff against baseline commit `0c0e6ab61607f19aa52f01bad1d0d1e4f7dfcf78` is 100% empty for all 4 files.
