# Test Matrix: Hanlin Expo Native API Hybrid

This matrix documents the verification suites, execution commands, and status across all layers of the hybrid subsystem.

---

## 1. Test Suite Categories

| Category | Suite Identifier | Description | Target Environment |
|:---|:---|:---|:---|
| **LOC** | `LOC-UNIT` | Local static and unit tests for Babel, lockfiles, architecture, and bundling | Node.js (Windows / macOS) |
| **NAT** | `NAT-ANALYZER` | Native Swift tests for `HanlinScriptAnalyzer` capability and version checks | macOS / Linux Swift |
| **UI** | `UI-E2E` | Native XCUITest suite verifying UIKit view/switch mounting, worklets, and swapping | iOS Simulator 27 (macOS) |
| **PKG** | `PKG-INTEGRITY` | Verification of probe packages, metadata formats, and SHA256 checksums | Node.js / CI |
| **LC** | `LC-LIFECYCLE` | Runtime session termination and capability revocation lifecycle | XCUITest / Simulator |
| **REG** | `REG-REGRESSION` | Preexisting `HanlinExpoProductionE2ETests` and `HanlinNativeScriptProductionE2ETests` | iOS Simulator 27 |
| **DEV** | `DEV-DEVICE` | Physical hardware verification (iPad / iPhone) | Physical Device (TestFlight) |

---

## 2. Detailed Verification Matrix

| ID | Test Case | Target / Command | Verification Method | Status |
|:---|:---|:---|:---|:---|
| `LOC-01` | Babel Configuration & Plugins | `node --test Scripts/ExpoNativeAPI/Tests/babel-config.test.mjs` | Verifies Babel preset and NativeScript/Worklets plugins | **PASS** |
| `LOC-02` | Lockfile & Dependency Integrity | `node --test Scripts/ExpoNativeAPI/Tests/lock-integrity.test.mjs` | Verifies SHA-256 hashes against lockfiles | **PASS** |
| `LOC-03` | Artifacts & Architecture Layout | `node --test Scripts/ExpoNativeAPI/Tests/artifacts-architecture.test.mjs` | Checks Libffi, NSMD, and C++ source placement | **PASS** |
| `LOC-04` | TypeScript Facade Compilation | `npm run typecheck:nativeapi-probe --prefix Scripts/Expo` | Typechecks `@hanlin/expo-native-api` and probe | **PASS** |
| `LOC-05` | Metro Deterministic Bundling | `node Scripts/ExpoNativeAPI/build-probes.mjs` | Builds 5 `.hanlinExpo` bundles cleanly | **PASS** |
| `PKG-01` | Metadata Format Verification | `node Scripts/ExpoNativeAPI/verify-nsmd.mjs` | Verifies binary structure of `metadata-arm64.nsmd` | **PASS** |
| `PKG-02` | Native Artifact Layout | `node Scripts/ExpoNativeAPI/verify-artifacts.mjs` | Validates Libffi framework and modular headers | **PASS** |
| `NAT-01` | Required Capability Detection | `swift test --package-path Packages/HanlinPlatform --filter HanlinScriptAnalyzerTests` | Rejects missing `ios-native-api` grant | **PASS** (macOS CI) |
| `NAT-02` | Incompatible Version Rejection | `swift test --package-path Packages/HanlinPlatform --filter HanlinScriptAnalyzerTests` | Rejects versions != 9.1.2 | **PASS** (macOS CI) |
| `UI-01` | UIKit View & Worklets Mount | `HanlinExpoNativeAPIIntegrationUITests/testExpoNativeAPIMountAndInteraction` | XCUITest: UILabel, UISwitch, UIDevice, VC | **READY_FOR_CI** |
| `UI-02` | Dynamic Variant Swapping | `HanlinExpoNativeAPIIntegrationUITests/testExpoNativeAPIDynamicVariantSwitching` | XCUITest: Variant A -> Variant B without rebuild | **READY_FOR_CI** |
| `UI-03` | Incompatible Version Rejection | `HanlinExpoNativeAPIIntegrationUITests/testExpoNativeAPIIncompatibleVersionRejection` | XCUITest: UI alert on invalid package | **READY_FOR_CI** |
| `UI-04` | Malformed Package Rejection | `HanlinExpoNativeAPIIntegrationUITests/testExpoNativeAPIMalformedPackageRejection` | XCUITest: UI alert on corrupt package | **READY_FOR_CI** |
| `REG-01` | Preexisting Expo E2E Suite | `HanlinExpoProductionE2ETests` (3 test cases) | Zero regressions on existing Expo MiniApps | **READY_FOR_CI** |
| `REG-02` | Standalone NativeScript Suite | `HanlinNativeScriptProductionE2ETests` | Standalone V8 runtime remains 100% decoupled | **READY_FOR_CI** |
| `DEV-01` | Physical Device TestFlight | TestFlight Build on real iOS 27 hardware | Hardware verification gate | **DEVICE_NOT_VERIFIED** |
