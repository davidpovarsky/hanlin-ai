# Security and Isolation Model: Hanlin Expo Native API Hybrid

This document outlines the security architecture, capability model, and defense-in-depth isolation mechanisms for the Hanlin Expo Native API hybrid subsystem.

---

## 1. Capability Definition: `ios-native-api`

The `ios-native-api` capability (`HanlinCapabilityID.iosNativeAPI`) is a broad native execution capability.
Because NativeScript exposes Objective-C and C runtime symbols dynamically via libffi and JSI, code executing under this capability has direct access to public iOS SDK APIs (such as UIKit, Foundation, CoreGraphics, AVFoundation, and UIDevice) within the application's process space.

Due to this power, access is strictly gated and governed by Hanlin's multi-layered permission system.

---

## 2. Multi-Layer Defense-in-Depth Architecture

```
[MiniApp Package (.hanlinExpo)]
             │
             ▼
   [Tier 1: Static Manifest Analyzer]
      ├── Inspects script.json and package.json
      ├── Detects imports of '@nativescript/react-native' or 'react-native-worklets'
      └── REJECTS package import if 'ios-native-api' is not explicitly declared
             │
             ▼ (User Grants Permission)
   [Tier 2: Native Runtime-Scoped Authorization Gate]
      ├── HanlinExpoSession initializes with host-derived sessionID and packageID
      ├── Binds specific jsi::Runtime* to sessionID upon host runtime initialization
      ├── Injected into all native entrypoints in NativeScriptNativeApiModule.mm:
      │     ├── install(runtime, ...) -> checks isNativeAPIAuthorizedForRuntime
      │     ├── installWorkletRuntime(runtime, ...) -> checks isNativeAPIAuthorizedForRuntime
      │     ├── NativeScriptCreateUIKitHost() -> checks isNativeAPIAuthorizedForCurrentSession
      │     └── NativeScriptRunUIKitHostLifecycle() -> checks isNativeAPIAuthorizedForCurrentSession
      └── Returns false / nil and logs [HANLIN_EXPO_NATIVEAPI_DENIAL] on denial
             │
             ▼ (Runtime Execution)
   [Tier 3: Dynamic Synchronous Revocation & Teardown]
      ├── HanlinScriptingPlatform.setCapabilityGranted revokes active session BEFORE first await
      ├── Calls HanlinExpoNativeAPIManager.revokeActiveSession() and dismissActiveApplication()
      ├── HanlinExpoNativeAPIClearWorkletRuntime() clears worklet handles
      ├── Active context and runtime mapping cleared immediately
      └── Hermes JS runtime and Fabric component views are deallocated
```

---

## 3. Tier 1: Static Manifest & AST Analysis

Inside `Packages/HanlinPlatform/Sources/HanlinScriptCompiler/HanlinScriptAnalyzer.swift`:
1. **Dependency Analysis**: If `package.json` contains `@nativescript/react-native` or `react-native-worklets`, the package must declare `"ios-native-api"` in `script.json.capabilities`.
2. **Version Pinning**: Only authorized versions (`@nativescript/react-native@9.1.2` and `react-native-worklets@0.13.1`) are permitted. Incompatible major/minor versions are rejected at import inspection.
3. **AST Inspection**: Bundle code is inspected for unauthorized references or circumvention attempts.

---

## 4. Tier 2: Per-Runtime Native C++ / ObjC++ Gate Enforcement

JavaScript-level permission checks are fundamentally insufficient because client code could attempt to resolve the TurboModule directly:
```typescript
TurboModuleRegistry.getEnforcing("NativeScriptNativeApi");
```

To prevent this, `HanlinExpoNativeAPIGate` is written in Objective-C++ and injected directly into `NativeScriptNativeApiModule.mm`:
- For JSI install functions:
  ```objective-c++
  if (![HanlinExpoNativeAPIGate isNativeAPIAuthorizedForRuntime:&runtime]) {
    NSLog(@"[HANLIN_EXPO_NATIVEAPI_DENIAL] NativeScriptNativeApiModule::install rejected: 'ios-native-api' capability is NOT granted.");
    return false;
  }
  ```
- For UIKit host functions:
  ```objective-c++
  if (![HanlinExpoNativeAPIGate isNativeAPIAuthorizedForCurrentSession]) {
    NSLog(@"[HANLIN_EXPO_NATIVEAPI_DENIAL] NativeScriptCreateUIKitHost rejected: 'ios-native-api' capability is NOT granted.");
    return nil;
  }
  ```

This ensures that regardless of how the JSI or TurboModule is addressed from JavaScript, the native binary refuses to initialize bindings or invoke worklets without valid session authorization.

---

## 5. Tier 3: Synchronous Revocation & Host Lifecycle

When a user revokes the `ios-native-api` permission in Hanlin settings:
- `HanlinScriptingPlatform.setCapabilityGranted` immediately calls `HanlinExpoNativeAPIManager.revokeActiveSession()` and `dismissActiveApplication()` **synchronously, before the first `await` suspension point**.
- `HanlinExpoNativeAPIClearWorkletRuntime()` invalidates Worklets runtime references.
- The active `HanlinExpoSession` is dismissed and shutdown.
- The Hermes runtime instance, JS context, and UI root view are deallocated.
- Subsequent calls to native entrypoints fail closed.

---

## 6. Honest Residual Trust Boundary

- **In-Process Public API Access**: A package granted `ios-native-api` executes in the same process space as the host application. While public SDK calls (UIKit, Foundation) are safe and standard, it does NOT provide an out-of-process operating system sandbox.
- **Private APIs**: Apple's App Store Review guidelines and static symbol analysis apply; the bundled metadata `.nsmd` contains exclusively public iOS SDK declarations.
- **Memory Safety**: Cross-session isolation is maintained by tearing down Hermes runtimes and clearing session state upon package dismiss or capability change.
