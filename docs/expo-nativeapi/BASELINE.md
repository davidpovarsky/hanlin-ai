# Baseline Audit & Repository Metadata

**Date:** 2026-10-27  
**Working Branch:** `codex/expo-nativescript-jsi-hybrid-20261027`  
**Base Reference:** `origin/fix/classic-source-first-agent-acceptance-20261025`  
**Base Commit SHA:** `0c0e6ab61607f19aa52f01bad1d0d1e4f7dfcf78`  
**Verified TestFlight Provenance:**  
- Build: `84001`  
- GitHub Actions Run: `40331983790` (Job: `upload-chavrusachat-to-testflight / build-sign-and-upload`, Xcode 27, iOS 27)  
- Signed IPA Artifact: `ChavrusaChat-signed-ipa-84001` (`12657179262`)  
- TestFlight Status: Upload and visibility verified on 2026-10-26  

---

## 1. Frozen Chat UI Integrity

Per non-negotiable project safety rules, the following chat UI files are strictly frozen and will remain byte-for-byte untouched throughout this integration:

| Relative Path | SHA256 Hash |
|---|---|
| `AI_HLY/ChatView.swift` | `1571911d14f3decf24c757f8f233a5a655476f19e48830f2c36016719a18847c` |
| `AI_HLY/Views/Components/ChatViewBottom.swift` | `161862b7718d7e2b4678517a5d5f06400719df9862e87dd3b083ae2595874c28` |
| `AI_HLY/Views/Components/ChatViewComponents.swift` | `43ccf9e91e806ae253af554f55070b6256a5a2a10cd02a0974ffbfd37cc27baa` |
| `AI_HLY/Views/Components/ChatandFile.swift` | `007111fb74ca3d237b07bbd9dc3f66bb0a021cbf89aa5a23a1f0a0ac28c9e135` |

---

## 2. Key Baseline Configuration Hashes

The TestFlight source contains late XCFramework normalization and modular headers layout wiring. Baseline hashes:

| Relative Path | Baseline SHA256 Hash |
|---|---|
| `Packages/HanlinExpoRuntime/Package.swift` | `096243e4eae290e4b4c9d7c0fd122f77d96a8422ef3b5a9d5f8fb2c0d4bc856f` |
| `Scripts/Expo/prepare-ios-dependencies.mjs` | `f982fabeed3baa895132f2f0b3bb14109cc01a9f024287cd1e88a3c288bbae31` |
| `Scripts/Expo/package.json` | `7e24674c9b438ba7b4f63ea353271f82dc05dba992bcc3d57a086bd7e91487b4` |
| `Scripts/Expo/dependency-lock.json` | `36edf80a0b31be62b0bdc1702cceb68a8e1a6d9d3570a9aa35973a84793a0815` |
| `Packages/HanlinNativeScriptRuntime/Package.swift` | `56673333e192c974ddeac9bf6f5eeccc62102d26acc37d493e385ad854a4eb08` |
| `AI_HLY.xcodeproj/project.pbxproj` | `eb2d785ef87c54894674b0d97b2965a8097c67b35f571157c5a2cad63cae85a3` |

---

## 3. Preexisting Runtime Closures

### Preexisting Expo Runtime (`Packages/HanlinExpoRuntime`)
- Expo SDK: `58.0.0-preview.3`
- React Native: `0.88.0-rc.0`
- React: `19.2.3`
- Hermes VM: `260318099.0.2`
- Expo UI: `58.0.3`
- Expo Modules Core: `58.0.3`
- Expo Brownfield: `58.0.3`
- Precompiled binary targets: `React`, `ReactNativeHeaders`, `ReactNativeDependencies`, `hermesvm`, `ExpoModulesJSI`, `ExpoModulesCore`, `ExpoModulesWorklets`, `ExpoUI`, `ExpoBrownfield`

### Preexisting NativeScript Runtime (`Packages/HanlinNativeScriptRuntime`)
- Standalone NativeScript iOS SPM target: `NativeScript/ios-spm@9.1.0`
- `@nativescript/swift-ui`: `4.0.2`
- Engine: V8 / standalone NativeScript runtime
- Completely separate runtime execution island; must remain intact and independent.
