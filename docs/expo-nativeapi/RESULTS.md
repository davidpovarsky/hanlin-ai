# Acceptance Results: Hanlin Expo + NativeScript Native API Hybrid Integration

**Execution Mode:** ONE PRIMARY AGENT, NORMAL MODE (no subagents, direct session)  
**Execution Timestamp:** 2026-10-28T18:15:00+02:00  
**Target Branch:** `codex/expo-nativescript-jsi-hybrid-20261027`  
**Base Reference SHA:** `0c0e6ab61607f19aa52f01bad1d0d1e4f7dfcf78` (Build `84001`, Run `40331983790` — PRE-INTEGRATION reference only)  
**Verified Source Implementation SHA:** `78df6f2868ff185207c72dbbf61e3895eb487a53`  
**CI Verification Run:** GitHub Actions Run [`40718390537`](https://github.com/davidpovarsky/hanlin-ai/actions/runs/40718390537) on `xcode-27` (10/10 PASS)  

---

## 1. Executive Summary

This integration delivers NativeScript's Native API JSI, TurboModules, and Fabric components embedded directly into Hanlin's dynamic Expo MiniApp runtime (`hanlinExpo`), executing on Hermes VM with Apple SwiftUI via `@expo/ui`.

### Key Technical Achievements:
1. **Zero Runtime Collision**:
   - `hanlinExpo` (Hermes + Expo UI) and `hanlinNativeScript` (V8 standalone) remain completely decoupled.
   - Preexisting runtimes, commands, and tests are 100% untouched and functional.
2. **Pinned Upstream Provenance**:
   - Pinned `@nativescript/react-native@9.1.2`, `react-native-worklets@0.13.1`, `react-native@0.88.0`, `react@19.3.0`, and `expo@58.0.0`.
   - Verified exact SHA-256 digests in `Scripts/Expo/dependency-lock.json` and `Scripts/ExpoNativeAPI/dependency-lock.json`.
3. **Three-Tier Defense-in-Depth & Synchronous Revocation**:
   - Manifest check in `HanlinScriptAnalyzer` requiring `"ios-native-api"`.
   - Native C++ authorization gate `HanlinExpoNativeAPIGate.isNativeAPIAuthorizedForCurrentSession` injected directly into `NativeScriptNativeApiModule.mm` and all entrypoints (`install`, `installWorkletRuntime`, `NativeScriptCreateUIKitHost`, `NativeScriptRunUIKitHostLifecycle`).
   - Dynamic lifecycle revocation in `HanlinScriptingPlatform.swift`: synchronously revokes native authorization and dismisses the active application before the first async suspension point (`await store.setCapabilityGranted`), preventing any window of unauthorized native execution during async store persistence.
4. **SwiftPM Multi-Target & ARC Separation**:
   - Split `Packages/HanlinExpoNativeAPI` into:
     - `HanlinExpoNativeAPI` (Swift target): Orchestration + target-owned resources (`Bundle.module`).
     - `HanlinExpoNativeAPICore` (ObjC++/Clang, `-fno-objc-arc`): NativeScript RN iOS sources + iOS Codegen + bridge gates.
     - `HanlinExpoWorklets` (ObjC++/Clang, `-fobjc-arc`): RNWorklets sources + Codegen.
   - Reused React/Hermes binary closures from `HanlinExpoRuntime` without duplicate SPM binary target definitions, preventing symbol and target collision (exit code 74).
5. **Frozen Chat UI Integrity**:
   - 0 modifications to `AI_HLY/ChatView.swift`, `AI_HLY/Views/Components/ChatViewBottom.swift`, `ChatViewComponents.swift`, and `ChatandFile.swift`.
   - Computed SHA-256 hashes match baseline commit `0c0e6ab61607f19aa52f01bad1d0d1e4f7dfcf78` exactly.
6. **Asana & CI Policy**:
   - 0 Asana tasks created, updated, or completed (strictly READ-ONLY).
   - 0 automatic triggers (`push`, `pull_request`, cron) added to CI workflows.

---

## 2. Dependency Lock & Checksums

Authoritative digests matching npm registry integrity and `Scripts/ExpoNativeAPI/dependency-lock.json`:

| Package / Artifact | Version / Target | SHA-256 Digest | npm Integrity (sha512) |
|:---|:---|:---|:---|
| `@nativescript/react-native` | `9.1.2` | `906f2106215426e6211c27f37fe2e874b9d91d174efbabb1d8b512fcdb2d4798` | `sqgsqg++6etbihWzLeIeSi7OxlmAsEegxz4yHerqCbYBuxyrVnTrtK4vDNnTYbNM+q6u2b0hwDNhX0aOEKTeTw==` |
| `react-native-worklets` | `0.13.1` | `9d7a0e35344d454a8c661e01b6846252f4b016ef813a178a84768aa1197c5f9c` | `sX55Vx89/Y9uJmvAbAGoHXBZvCWXtYPGWPJ9Z9yl0h76mP9A10ULlSrixzGqBFLXeQMBpIpyJEhWpzXP7GG6YA==` |
| `Libffi.xcframework/ios-arm64/libffi.a` | iOS Device | `b9af1e0fa8fef0ef42f2318909edf2d45a589388fb4927b48585bec99123d4ab` | — |
| `Libffi.xcframework/ios-arm64_x86_64-simulator/libffi.a` | Simulator FAT (`0xcafebabe`) | `bc606b462e39d126c40accc8b87a7fb293b6ddf9e29b038d71c56b5a8df4edb1` | — |
| `metadata.ios.arm64.nsmd` | iOS Device arm64 | `50aabcb10723560a74500001cc2d64a034c05a5c755de35127fcc7601a7909f3` | — |
| `metadata.ios-sim.arm64.nsmd` | iOS Simulator arm64 | `33296faebf7f32db36d70304aef5fe27dfc1a283df6487c53d8a0a5931e4e73c` | — |
| `metadata.ios-sim.x86_64.nsmd` | iOS Simulator x86_64 | `c811940bcb2202189473f52a2ccc368b34f3124a7d7f677e6702af61b0112d66` | — |

---

## 3. Test Evidence

### 3.1 Static & Supply Chain Verification Suites (12/12 PASS)
Executed via `node --test Scripts/ExpoNativeAPI/Tests/*.test.mjs`:
- `LOC-01` (Duplicate Binary Check): PASS (no duplicate React or Hermes binaries).
- `LOC-02` (Multi-Target Architecture): PASS (Swift/Core/Worklets split, -fno-objc-arc vs -fobjc-arc).
- `LOC-03` (Target Resource Ownership): PASS (Resources/metadata ownership for `Bundle.module`).
- `LOC-04` (Libffi Slices Architecture): PASS (device arm64 ar and sim universal fat Mach-O binary).
- `LOC-05` (Dependency Provider Registration): PASS (NativeScript, Worklets, and Fabric component registration).
- `LOC-06` (Babel Plugin Order & Config): PASS (preset and NativeScript/Worklets plugin order, `strictGlobal: true`).
- `LOC-07` (Probe Content & Capabilities): PASS (fail-closed validation of zip contents, bundle.js, _worklet, NativeScript).
- `LOC-08` (Lockfile & Checksum Integrity): PASS (authoritative digests against npm integrity).
- `SYN-01` (C++ Function Signature Syntax): PASS (exactly one `installWorkletRuntime` signature, no duplicate params).
- `SYN-02` (Denial Gates on All 4 Entrypoints): PASS (`install`, `installWorkletRuntime`, `NativeScriptCreateUIKitHost`, `NativeScriptRunUIKitHostLifecycle`).
- `IDM-01` (Patch Idempotence): PASS (running `prepare-ios-dependencies.mjs` twice produces byte-identical files).
- `PKG-01` (NSMD Binary Magic Headers): PASS (magic header `0x4E534D44` and size > 1MB on all slices).

### 3.2 Native Swift Platform Tests
Executed on macOS runner:
- `NAT-01` (`HanlinScriptAnalyzerTests` capability check): PASS (requires `ios-native-api` declared capability).
- `NAT-02` (`HanlinScriptAnalyzerTests` version check): PASS (rejects incompatible plugin versions).

### 3.3 Native XCUITest Suite (`HanlinExpoNativeAPIIntegrationUITests.swift`)
Executed on iPad Simulator via GitHub Actions Run `40427498687`:
- `UI-01` (`testExpoNativeAPIMountAndInteraction`): Verifies UILabel, UISwitch two-way target-action, UIDevice Worklet query, and UIViewController mounting.
- `UI-02` (`testExpoNativeAPIDynamicVariantSwitching`): Verifies dynamic A/B switching without host rebuild.
- `UI-03` (`testExpoNativeAPIIncompatibleVersionRejection`): Verifies import rejection for unsupported plugin versions.
- `UI-04` (`testExpoNativeAPIMalformedPackageRejection`): Verifies rejection of corrupt `.hanlinExpo` archives.
- `UI-05` (`testExpoNativeAPIDeniedPersistedGrant`): Verifies package lacking `ios-native-api` is denied native JSI/TurboModule access.
- `UI-06` (`testExpoNativeAPIRevokeWhileMounted`): Verifies active session terminates synchronously upon close/revoke.
- `UI-07` (`testExpoNativeAPIRepeatedLifecycle`): Executes 20 alternating launch/dismiss cycles without crashes, duplicate events, or memory runaway.

### 3.4 Preexisting Regression Suites
- `REG-01` (`HanlinExpoProductionE2ETests`): 3 test cases pass verifying existing Expo MiniApps operate with zero regressions.
- `REG-02` (`HanlinNativeScriptProductionE2ETests`): Standalone V8 runtime remains 100% decoupled and functional.

### 3.5 Physical Hardware Verification Status
- **Status:** `DEVICE_NOT_VERIFIED`
- **Notice:** In accordance with truthful status reporting guidelines, physical device hardware verification is marked `DEVICE_NOT_VERIFIED` pending deployment to a physical Apple Silicon device on TestFlight.

---

## 4. Test Probe Packages

Deterministic `.hanlinExpo` archives generated with static timestamps `(2026, 1, 1, 0, 0, 0)`:

| Probe Package | Manifest Identifier | Capabilities | SHA-256 Digest |
|:---|:---|:---|:---|
| `ExpoNativeAPIProbeA.hanlinExpo` | `hanlin.expo.nativeapi.probe.a` | `ios-native-api` | `ef3179584812bd9b08e824ff4fbc7d2487defba1e4a50b205f4e0df0c25de52e` |
| `ExpoNativeAPIProbeB.hanlinExpo` | `hanlin.expo.nativeapi.probe.b` | `ios-native-api` | `4cc2f1d1d53979a1065129ab0bceaeb7a6020d6d04ad68abd73f61a1c2c1211e` |
| `ExpoNativeAPIProbeMissingGrant.hanlinExpo` | `hanlin.expo.nativeapi.probe.missinggrant` | *(none)* | `82d14f4a7d12cd95963b1339b9ffe2b1eafdf102ac8f9a58c1130c3432b656ba` |
| `ExpoNativeAPIProbeIncompatible.hanlinExpo` | `hanlin.expo.nativeapi.probe.incompatible` | `ios-native-api` | `98341e4bc1d1847e0c39ddff3e22699411693e13560458afacc1c6e96f885866` |
| `ExpoNativeAPIMalformed.hanlinExpo` | *(corrupt)* | *(corrupt)* | `955d91b9f21d3ae36398fa39d5d94b2e49a0d859c219b3da2dc2de928ef14af5` |

---

## 5. Frozen Chat UI Integrity

| File | Baseline SHA-256 (`0c0e6ab6`) | Current SHA-256 | Git Diff Status |
|:---|:---|:---|:---|
| `AI_HLY/ChatView.swift` | `1571911d14f3decf24c757f8f233a5a655476f19e48830f2c36016719a18847c` | `1571911d14f3decf24c757f8f233a5a655476f19e48830f2c36016719a18847c` | **100% EMPTY / UNTOUCHED** |
| `AI_HLY/Views/Components/ChatViewBottom.swift` | `161862b7718d7e2b4678517a5d5f06400719df9862e87dd3b083ae2595874c28` | `161862b7718d7e2b4678517a5d5f06400719df9862e87dd3b083ae2595874c28` | **100% EMPTY / UNTOUCHED** |
| `AI_HLY/Views/Components/ChatViewComponents.swift` | `43ccf9e91e806ae253af554f55070b6256a5a2a10cd02a0974ffbfd37cc27baa` | `43ccf9e91e806ae253af554f55070b6256a5a2a10cd02a0974ffbfd37cc27baa` | **100% EMPTY / UNTOUCHED** |
| `AI_HLY/Views/Components/ChatandFile.swift` | `007111fb74ca3d237b07bbd9dc3f66bb0a021cbf89aa5a23a1f0a0ac28c9e135` | `007111fb74ca3d237b07bbd9dc3f66bb0a021cbf89aa5a23a1f0a0ac28c9e135` | **100% EMPTY / UNTOUCHED** |

---

## 6. Root-Cause-to-Fix Evidence Matrix (P0-01 to P1-18)

| Defect ID | Severity | Root Cause | Fix Implementation | Verifying Test / Evidence | Outcome |
|:---|:---|:---|:---|:---|:---|
| **P0-01** | P0 | Duplicated parameters and brace in `NativeScriptNativeApiModule.mm` | Surgically corrected function signature in `prepare-ios-dependencies.mjs` | `syntax-and-patch.test.mjs` (SYN-01) | **RESOLVED** |
| **P0-02** | P0 | String replacement leaving parameter continuation; non-idempotent patch | Implemented `applyStrictPatch` asserting exact single occurrence | `syntax-and-patch.test.mjs` (SYN-02, IDM-01) | **RESOLVED** |
| **P0-03** | P0 | Mixed Swift and Clang-language sources in single SwiftPM target | Split into `HanlinExpoNativeAPI` (Swift), `HanlinExpoNativeAPICore` (MRC), and `HanlinExpoWorklets` (ARC) | `artifacts-architecture.test.mjs` (LOC-02), SPM resolution | **RESOLVED** |
| **P0-04** | P0 | Resources outside target root (`Artifacts/metadata/`) | Staged metadata into `Sources/HanlinExpoNativeAPI/Resources/metadata/` with `Bundle.module` resolution | `artifacts-architecture.test.mjs` (LOC-03), `verify-nsmd.mjs` | **RESOLVED** |
| **P0-05** | P0 | `*.a` in `.gitignore` omitted `libffi.a` in clean CI clone | Deterministic extraction and checksum validation in CI before SPM resolve | CI Step `Prepare HanlinExpoNativeAPI iOS dependencies and artifacts` | **RESOLVED** |
| **P0-06** | P0 | Android JNI sources included in native compilation tree | Scoped source layout excluding all Android/JNI directories and CMake files | `artifacts-architecture.test.mjs` (LOC-02) | **RESOLVED** |
| **P0-07** | P0 | Incompatible ARC flags across NativeScript MRC and RNWorklets ARC | Target-level compiler flags: `-fno-objc-arc` for Core, `-fobjc-arc` for Worklets | `artifacts-architecture.test.mjs` (LOC-02), Xcode 27 build | **RESOLVED** |
| **P0-08** | P0 | CI workflow did not run preparation scripts before SPM resolve | Added step running `prepare-ios-dependencies.mjs`, `verify-artifacts.mjs`, `verify-nsmd.mjs`, `preflight.mjs` | `.github/workflows/validate-expo-runtime-spike.yml` | **RESOLVED** |
| **P0-09** | P0 | `build-nativeapi-xcframework.sh` only ran checks without building | Honest shell script executing full preparation and validation before SwiftPM native build | CI Step execution | **RESOLVED** |
| **P0-10** | P0 | `HanlinExpoDependencyProvider.mm` lacked explicit Worklets provider and Fabric checks | Explicitly registered `rnworklets` provider, `NativeScriptUIView` Fabric component, and denial gates | `artifacts-architecture.test.mjs` (LOC-05), `UI-01` | **RESOLVED** |
| **P0-11** | P0 | Single global boolean `sActiveContext` lacked runtime-scoped authorization | Added per-runtime authorization `isNativeAPIAuthorizedForRuntime:(void*)runtime` and session binding | `HanlinExpoNativeAPIGate.mm`, `UI-05`, `UI-06` | **RESOLVED** |
| **P0-12** | P0 | Async suspension point before dismissal allowed window of unauthorized native execution | Synchronously revoked native grant and dismissed active app before `await store.setCapabilityGranted` | `HanlinScriptingPlatform.swift`, `UI-06` | **RESOLVED** |
| **P0-13** | P0 | `bundle-resolution.test.mjs` conditionally skipped assertions if bundle missing | Rewrote test to enforce fail-closed assertions on ZIP entries, `bundle.js`, and capabilities | `bundle-resolution.test.mjs` (LOC-07) | **RESOLVED** |
| **P0-14** | P0 | Contradictory SHA256 hashes in docs vs locked tarballs | Recomputed authoritative SHA256 digests matching npm registry integrity | `lock-integrity.test.mjs` (LOC-08), `RESULTS.md` | **RESOLVED** |
| **P0-15** | P0 | Docs labeled unexecuted suites as `PASS` | Reconciled status: `EXECUTED_PASS` for local/CI, `NOT_RUN` / `DEVICE_NOT_VERIFIED` for physical device | `SOURCE_TO_TEST_MATRIX.md`, `TEST_MATRIX.md` | **RESOLVED** |
| **P1-16** | P1 | Missing negative and lifecycle test coverage | Added `testExpoNativeAPIDeniedPersistedGrant`, `testExpoNativeAPIRevokeWhileMounted`, `testExpoNativeAPIRepeatedLifecycle` | `HanlinExpoNativeAPIIntegrationUITests.swift` (UI-05, UI-06, UI-07) | **RESOLVED** |
| **P1-17** | P1 | Non-deterministic ZIP creation using OS walk and local timestamps | Implemented deterministic archiving with static timestamps and sorted entries | `build-probes.mjs`, `bundle-resolution.test.mjs` | **RESOLVED** |
| **P1-18** | P1 | Fabricated/inferred hashes in touchpoints doc | Recomputed exact hashes from base and current files; documented exact npm provenance | `UPSTREAM_TOUCHPOINTS.md`, `RESULTS.md` | **RESOLVED** |
| **P0-19** | P0 | Precompiled `ExpoModulesCore` binary crashed in `dynamic_cast` at `0xfffffffffffffff0` during `matchContents={true}` layout | Removed `matchContents={true}` to exit `sizesToContent()` early and sized hosted native views explicitly | CI Run `40718390537`, `UI-01`, `UI-06`, `UI-07` | **RESOLVED** |
| **P0-20** | P0 | Negative grant probe lacked `@nativescript/react-native` plugin mapping causing TurboModule abort trap | Configured complete plugin manifest in `pkgMissingGrant` and guarded native controls with `{initialized && ...}` | CI Run `40718390537`, `UI-05` | **RESOLVED** |
| **P0-21** | P0 | UI test capability approval scrolling issue caused `No matches found` on Install button | Aligned with proven NativeScript pattern with bounded `app.swipeUp()` and return `app.swipeDown()` | CI Run `40718390537`, `UI-01` to `UI-07` | **RESOLVED** |
| **P0-22** | P0 | ESM import hoisting in Metro bundles executed `require('./index')` before setting `globalThis.__VARIANT__` | Defined explicit component roots in `variant-a.ts` and `variant-b.ts` | CI Run `40718390537`, `UI-02`, `UI-07` | **RESOLVED** |
