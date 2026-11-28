# Upstream Provenance & Dependency Audit

**Author:** Noam (Engineering) & Yael (Research)  
**Execution Context:** NORMAL Mode (Direct Session)  
**Date:** 2026-10-27  

---

## 1. Primary Target Add-on Dependencies

### `@nativescript/react-native@9.1.2`
- **Source:** Authoritative published npm tarball
- **Tarball URL:** `https://registry.npmjs.org/@nativescript/react-native/-/react-native-9.1.2.tgz`
- **npm dist.integrity:** `sha512-sqgsqg++6etbihWzLeIeSi7OxlmAsEegxz4yHerqCbYBuxyrVnTrtK4vDNnTYbNM+q6u2b0hwDNhX0aOEKTeTw==`
- **SHA256:** `906f2106215426e6211c27f37fe2e874b9d91d174efbabb1d8b512fcdb2d4798`
- **License:** Apache-2.0
- **Codegen Configuration:**
  - Name: `NativeScriptNativeApiSpec` (Type: `all`)
  - Modules Provider: `NativeScriptNativeApi` -> `NativeScriptNativeApiModuleProvider`
  - Component Provider: `NativeScriptUIView` -> `NativeScriptUIViewComponentView`
- **Vendored Native Assets:**
  - `metadata/metadata.ios.arm64.nsmd`
  - `metadata/metadata.ios-sim.arm64.nsmd`
  - `metadata/metadata.ios-sim.x86_64.nsmd`
  - `ios/vendor/Libffi.xcframework` (arm64, simulator arm64+x86_64)

### `react-native-worklets@0.13.1`
- **Source:** Authoritative published npm tarball
- **Tarball URL:** `https://registry.npmjs.org/react-native-worklets/-/react-native-worklets-0.13.1.tgz`
- **npm dist.integrity:** `sha512-sX55Vx89/Y9uJmvAbAGoHXBZvCWXtYPGWPJ9Z9yl0h76mP9A10ULlSrixzGqBFLXeQMBpIpyJEhWpzXP7GG6YA==`
- **SHA256:** `9d7a0e35344d454a8c661e01b6846252f4b016ef813a178a84768aa1197c5f9c`
- **License:** MIT
- **Peer Compatibility Verification:**
  - Confirmed via `compatibility.json`:
    ```json
    "0.13.x": {
      "react-native": ["0.86", "0.87", "0.88"]
    }
    ```
  - Worklets 0.13.1 specifically targets stable React Native 0.88.

---

## 2. Coherent React Native 0.88 Stable Binary Closure

The host previously embedded `react-native@0.88.0-rc.0` precompiled binaries. Upgrading to the stable release requires ABI consistency across React, Hermes, and React Native dependencies.

### React Native Core (`com.facebook.react:react-native-artifacts:0.88.0`)
- **Maven Base:** `https://repo1.maven.org/maven2/com/facebook/react/react-native-artifacts/0.88.0/`
- `react-native-artifacts-0.88.0-reactnative-core-release.tar.gz`:
  - **SHA256:** `4f3d22afd5d74809178b737d3ed987cc747ea63336a758cdf20064c47ef67203`
  - Target: `Packages/HanlinExpoRuntime/Artifacts/React.xcframework`
- `react-native-artifacts-0.88.0-reactnative-dependencies-release.tar.gz`:
  - **SHA256:** `309b2fcea39fb4cdeb434144e735bc4065ac0dd8720e4f35ffee55fb3be54093`
  - Target: `Packages/HanlinExpoRuntime/Artifacts/ReactNativeDependencies.xcframework`
- `react-native-artifacts-0.88.0-reactnative-headers-release.tar.gz`:
  - **SHA256:** `7d896249102e6f10faa76218caf4bd2b8d739d1b6e3d032181ac498b34884165`
  - Target: `Packages/HanlinExpoRuntime/Artifacts/ReactNativeHeaders.xcframework`

### Hermes VM (`com.facebook.hermes:hermes-ios:260318099.0.4`)
- **Maven Base:** `https://repo1.maven.org/maven2/com/facebook/hermes/hermes-ios/260318099.0.4/`
- `hermes-ios-260318099.0.4-hermes-ios-release.tar.gz`:
  - **SHA256:** `b0db43628abc20b5eccb7ed1161801f418830f47b1ac1b5946cf532a886841f6`
  - Target: `Packages/HanlinExpoRuntime/Artifacts/hermesvm.xcframework`

### Expo SDK 58 Stable JS Packages
- `expo@58.0.0`:
  - **Tarball:** `https://registry.npmjs.org/expo/-/expo-58.0.0.tgz`
  - **dist.integrity:** `sha512-/KiC8tFY0hHl/mm49AFgNUFEQbnPthVh9o7EuDCSnTVpor8Cm/x1oqRyE97dxPT640lwuHO55xFO6OXopzjKXA==`
- `react@19.3.0`:
  - **Tarball:** `https://registry.npmjs.org/react/-/react-19.3.0.tgz`
  - **dist.integrity:** `sha512-E8LUcbtBWt20bbl2YoHfx4ZDBdxVTfOKtCZn9cDSJ4l6/nuoApcpIBcj47t2wZoVX8g2ZHuMHbiShgCR1T5Sog==`
- `react-native@0.88.0`:
  - **Tarball:** `https://registry.npmjs.org/react-native/-/react-native-0.88.0.tgz`
  - **dist.integrity:** `sha512-v/wee0nYWcammMYBnSat/e3WY/5iaf9YQOMcBrfKT/wPApPPlHp94hgZovBtwhMuthR01yc/8cGn0FpFTE/C4A==`
- `@expo/ui@58.0.3` / `expo-modules-core@58.0.3` / `expo-brownfield@58.0.3`:
  - Maintained from existing verified artifact closure.
