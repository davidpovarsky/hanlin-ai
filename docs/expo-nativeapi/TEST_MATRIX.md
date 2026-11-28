# Test Matrix: Hanlin Expo Native API Hybrid

This matrix documents the verification suites, execution commands, and status across all layers of the hybrid subsystem.

---

## 1. Test Suite Categories

| Category | Suite Identifier | Description | Target Environment |
|:---|:---|:---|:---|
| **LOC** | `LOC-UNIT` | Local static and unit tests for Babel, lockfiles, architecture, and bundling | Node.js (Windows / macOS) |
| **SYN** | `SYN-NATIVE` | Native C++ syntax regression, per-entrypoint authorization gates, and patch idempotence | Node.js / Xcode 27 |
| **NAT** | `NAT-ANALYZER` | Native Swift tests for `HanlinScriptAnalyzer` capability and version checks | macOS Swift 6 / Xcode 27 |
| **UI** | `UI-E2E` | Native XCUITest suite verifying UIKit view/switch mounting, worklets, and swapping | iOS Simulator 27 (macOS) |
| **PKG** | `PKG-INTEGRITY` | Verification of probe packages, metadata formats, and SHA256 checksums | Node.js / CI |
| **LC** | `LC-LIFECYCLE` | Runtime session termination, repeated 20-cycle lifecycle, and capability revocation | XCUITest / Simulator |
| **REG** | `REG-REGRESSION` | Preexisting `HanlinExpoProductionE2ETests` and `HanlinNativeScriptProductionE2ETests` | iOS Simulator 27 |
| **DEV** | `DEV-DEVICE` | Physical hardware verification (iPad / iPhone) | Physical Device (TestFlight) |

---

## 2. Detailed Verification Matrix

| ID | Test Case | Target / Command | Verification Method | Status |
|:---|:---|:---|:---|:---|
| `LOC-01` | Duplicate Binary Check | `node --test Scripts/ExpoNativeAPI/Tests/artifacts-architecture.test.mjs` | Verifies no duplicate React or Hermes binaries | **PASS** |
| `LOC-02` | Multi-Target & ARC Separation | `node --test Scripts/ExpoNativeAPI/Tests/artifacts-architecture.test.mjs` | Verifies Swift/Core/Worklets split, -fno-objc-arc vs -fobjc-arc | **PASS** |
| `LOC-03` | Target Resource Ownership | `node --test Scripts/ExpoNativeAPI/Tests/artifacts-architecture.test.mjs` | Verifies Resources/metadata ownership for Bundle.module | **PASS** |
| `LOC-04` | Libffi Slices Architecture | `node --test Scripts/ExpoNativeAPI/Tests/artifacts-architecture.test.mjs` | Verifies device arm64 and sim universal fat binary (`0xcafebabe`) | **PASS** |
| `LOC-05` | Dependency Provider Registration | `node --test Scripts/ExpoNativeAPI/Tests/artifacts-architecture.test.mjs` | Verifies NativeScript, Worklets, and Fabric component registration | **PASS** |
| `LOC-06` | Babel Plugin Order & Config | `node --test Scripts/ExpoNativeAPI/Tests/babel-config.test.mjs` | Verifies preset and NativeScript/Worklets plugin order (`strictGlobal: true`) | **PASS** |
| `LOC-07` | Probe Content & Capabilities | `node --test Scripts/ExpoNativeAPI/Tests/bundle-resolution.test.mjs` | Fail-closed validation of zip contents, bundle.js, _worklet, NativeScript | **PASS** |
| `LOC-08` | Lockfile & Checksum Integrity | `node --test Scripts/ExpoNativeAPI/Tests/lock-integrity.test.mjs` | Verifies authoritative digests against npm integrity | **PASS** |
| `SYN-01` | C++ Function Signature Syntax | `node --test Scripts/ExpoNativeAPI/Tests/syntax-and-patch.test.mjs` | Exactly one installWorkletRuntime signature, no duplicated parameters | **PASS** |
| `SYN-02` | All 4 Entrypoint Denial Gates | `node --test Scripts/ExpoNativeAPI/Tests/syntax-and-patch.test.mjs` | Verifies install, installWorkletRuntime, CreateUIKitHost, RunUIKitHostLifecycle gates | **PASS** |
| `IDM-01` | Patch Idempotence Re-execution | `node --test Scripts/ExpoNativeAPI/Tests/syntax-and-patch.test.mjs` | Proves double execution of prepare-ios-dependencies is byte-identical | **PASS** |
| `PKG-01` | NSMD Binary Magic Headers | `node Scripts/ExpoNativeAPI/verify-nsmd.mjs` | Verifies NSMD magic header and size > 1MB for all 3 slices | **PASS** |
| `NAT-01` | Required Capability Detection | `swift test --package-path Packages/HanlinPlatform --filter HanlinScriptAnalyzerTests` | Rejects missing `ios-native-api` grant | **PASS** |
| `NAT-02` | Incompatible Version Rejection | `swift test --package-path Packages/HanlinPlatform --filter HanlinScriptAnalyzerTests` | Rejects versions != 9.1.2 | **PASS** |
| `UI-01` | UIKit View & Worklets Mount | `HanlinExpoNativeAPIIntegrationUITests/testExpoNativeAPIMountAndInteraction` | XCUITest: UILabel, UISwitch, UIDevice, VC | **EXECUTED_CI** |
| `UI-02` | Dynamic Variant Swapping | `HanlinExpoNativeAPIIntegrationUITests/testExpoNativeAPIDynamicVariantSwitching` | XCUITest: Variant A -> Variant B without rebuild | **EXECUTED_CI** |
| `UI-03` | Incompatible Version Rejection | `HanlinExpoNativeAPIIntegrationUITests/testExpoNativeAPIIncompatibleVersionRejection` | XCUITest: UI alert on invalid package | **EXECUTED_CI** |
| `UI-04` | Malformed Package Rejection | `HanlinExpoNativeAPIIntegrationUITests/testExpoNativeAPIMalformedPackageRejection` | XCUITest: UI alert on corrupt package | **EXECUTED_CI** |
| `UI-05` | Denied Persisted Grant | `HanlinExpoNativeAPIIntegrationUITests/testExpoNativeAPIDeniedPersistedGrant` | XCUITest: Package without ios-native-api denied native access | **EXECUTED_CI** |
| `UI-06` | Synchronous Revoke While Mounted | `HanlinExpoNativeAPIIntegrationUITests/testExpoNativeAPIRevokeWhileMounted` | XCUITest: Dismiss/revoke terminates native session, clean relaunch | **EXECUTED_CI** |
| `UI-07` | Repeated 20-Cycle Lifecycle | `HanlinExpoNativeAPIIntegrationUITests/testExpoNativeAPIRepeatedLifecycle` | XCUITest: 20 launch/dismiss cycles with zero crashes or leaks | **EXECUTED_CI** |
| `REG-01` | Preexisting Expo E2E Suite | `HanlinExpoProductionE2ETests` (3 test cases) | Zero regressions on existing Expo MiniApps | **EXECUTED_CI** |
| `REG-02` | Standalone NativeScript Suite | `HanlinNativeScriptProductionE2ETests` | Standalone V8 runtime remains 100% decoupled | **REUSED_VERIFIED_PASS** |
| `DEV-01` | Physical Device TestFlight | TestFlight Build on real iOS 27 hardware | Hardware verification gate | **DEVICE_NOT_VERIFIED** |
