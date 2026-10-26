# Security and Isolation Model: Hanlin Expo Native API Hybrid

This document outlines the security architecture, capability model, and defense-in-depth isolation mechanisms for the Hanlin Expo Native API hybrid subsystem.

---

## 1. Capability Definition: `ios-native-api`

The `ios-native-api` capability (`HanlinCapabilityID.iosNativeAPI`) is a broad native execution capability.
Because NativeScript exposes Objective-C and C runtime symbols dynamically via libffi and JSI, code executing under this capability has direct access to public iOS SDK APIs (such as UIKit, Foundation, CoreGraphics, AVFoundation, and UIDevice).

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
   [Tier 2: Native Authorization Gate]
      ├── HanlinExpoSession initializes with isNativeAPIGranted flag
      ├── Sets thread-local / session-scoped HanlinExpoNativeAPIGate
      ├── Injected into NativeScriptNativeApiModule.mm:
      │     ├── install()
      │     ├── installWorkletRuntime()
      │     └── NativeScriptCreateUIKitHost()
      └── THROWS native runtime exception if JSI is invoked without active grant
             │
             ▼ (Runtime Execution)
   [Tier 3: Dynamic Lifecycle Revocation]
      ├── HanlinScriptingPlatform observes capability changes
      ├── Upon permission revocation, HanlinExpoSession.terminate() is called immediately
      ├── Hermes JS runtime is torn down
      └── All Fabric UIKit components and worklets are destroyed
```

---

## 3. Tier 1: Static Manifest & AST Analysis

Inside `Packages/HanlinPlatform/Sources/HanlinScriptCompiler/HanlinScriptAnalyzer.swift`:
1. **Dependency Analysis**: If `package.json` contains `@nativescript/react-native` or `react-native-worklets`, the package must declare `"ios-native-api"` in `script.json.capabilities`.
2. **Version Pinning**: Only authorized versions (`@nativescript/react-native@9.1.2` and `react-native-worklets@0.13.1`) are permitted. Incompatible major/minor versions are rejected at import inspection.
3. **AST Inspection**: Bundle code is inspected for unauthorized references or circumvention attempts.

---

## 4. Tier 2: Native C++ / ObjC++ Gate Enforcement

JavaScript-level permission checks are fundamentally insufficient because client code could attempt to resolve the TurboModule directly:
```typescript
TurboModuleRegistry.getEnforcing("NativeScriptNativeApi");
```

To prevent this, `HanlinExpoNativeAPIGate` is written in Objective-C++ and injected directly into `NativeScriptNativeApiModule.mm`:

```objc
if (!HanlinExpoNativeAPIGate.isNativeAPIAuthorizedForCurrentSession) {
  NSLog(@"[HanlinExpoNativeAPI] Unauthorized Native API invocation rejected by native gate.");
  return @NO;
}
```

This ensures that regardless of how the JSI or TurboModule is addressed from JavaScript, the native binary refuses to initialize bindings or invoke worklets without valid session authorization.

---

## 5. Tier 3: Dynamic Revocation & Session Isolation

When a user revokes the `ios-native-api` permission in Hanlin settings:
- `HanlinScriptingPlatform` receives the event immediately.
- The active `HanlinExpoSession` is dismissed.
- The Hermes runtime instance, JS context, and UI root view are deallocated.
- Native view references retained in the retainer map are released.

---

## 6. Audit & Risk Assessment

| Vector | Risk Level | Mitigation |
|:---|:---|:---|
| **Arbitrary Native Code Execution** | High | Gated by explicit user consent (`ios-native-api`) and native gate. |
| **Direct TurboModule Bypass** | Medium | Native C++ entrypoints check `HanlinExpoNativeAPIGate`. |
| **Cross-Session Memory Leakage** | Low | Full Hermes runtime destruction upon session termination. |
| **Private Apple API Usage** | None | Metadata contains only public SDK symbols; App Store validation rules apply. |
