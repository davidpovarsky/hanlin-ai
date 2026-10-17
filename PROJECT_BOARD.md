# Project Board

This is a living working-memory document for this repository.
It is intentionally lightweight. Humans and coding agents should update it when useful discoveries, ideas, plans, optimizations, problems, or follow-up work arise during normal development.
Do not turn this into a duplicate issue tracker or a dump of temporary thoughts.

## Inbox

Quick captures that still need classification.

## Ideas & Opportunities

Potential improvements, features, optimizations, or architectural ideas.

## Discoveries & Tips

- **CloudKit Container in CI:** On iOS Simulator running in CI without active iCloud entitlements/credentials, `cloudKitDatabase` must be initialized to `.none` to avoid blocking/deadlock during app/agent startup.
- **Node Worker ESM Resolution:** Node 22 exhibited a known worker loader internal assertion failure (`ERR_INTERNAL_ASSERTION: Unexpected module status 3`) on concurrent ESM worker resolution. Resolved cleanly in Node 24.5 (`@cablate/mcp-google-map` passes capability probing with exit code 0).
- **Simulator Concurrency Gates:** In XCTest suites driving async agent loops, unbounded polling loops can cause test runner timeouts. Use bounded timeouts with exponential backoff.
- **Authoritative Defect Identification:** The 6 test failures discovered in Pass 3 were previously mislabeled against scenario IDs SH-03, SH-05, CMD-04, ZIP-04, ZIP-07, ZIP-11. Their root causes were in `loadDescriptor` title propagation (`SkillStore.swift`), atomic rollback metadata preservation (`SkillStore.swift`), internal symlink policy acceptance (`HanlinArchivePolicy.swift`), dual-mode shell tool schema advertisement (`ExecuteShellCommandTool.swift`), obsolete path policy removal from smoke suite (`ShellRuntimeSmokeSuite.swift`), and raw command pipe execution / symlink reading (`HanlinUnifiedHostServicesAgentAcceptanceTests.swift`). All 6 have been fully fixed and verified.
- **Swift 6 Region Isolation on Completion Handlers:** When dispatching completion handlers from non-isolated methods to `DispatchQueue.main.async`, non-Sendable closures trigger `RegionIsolation::SendingRisksDataRace` unless aliased to `nonisolated(unsafe)` before any guard branch.
- **Clang Objective-C Class Scope Nesting:** Clang treats `@interface` / `@implementation` inside another class `@implementation` as an invalid nested class definition. The first `@end` terminates the outer implementation context, causing every subsequent method declaration to fail with `missing context for method declaration`. Moving helper classes (`HanlinSyncBox`) to top-level file scope before the parent `@implementation` ensures clean compilation across Apple and portable Clang toolchains.
- **Fail-Closed Session Bridge Isolation:** In multi-session native script bridge architectures, implicit fallbacks (`_sessionProviders.count == 1` or `_currentProvider`) can cause session crossover or silent fallback when an active session is cleared while another remains. Relying strictly on the active session bridge snapshot enforces strict session isolation with zero crossover leaks.
- **Bash `set -u` Safe Array Expansion:** Expanding an empty array `"${arr[@]}"` under `set -u` aborts with `unbound variable`. Use `"${arr[@]+"${arr[@]}"}"` for portable, safe expansion.
- **NativeScript iOS Dynamic Bridge Dispatch Without Metadata Recompilation:** In embedded NativeScript runtimes where binary metadata generation is skipped during simulator builds, new Objective-C class methods are not dynamically added to the JavaScript class prototype. Routing Host Services invocations through the pre-bound `roundTripValue:key:` selector (`compat.roundTripValueKey(value, key)`) guarantees deterministic execution of JavaScript, Node, Python, HTTPS network requests, and inter-app messaging without requiring offline binary metadata updates.
- **NativeScript Objective-C Class vs Instance Bridging:** In NativeScript iOS runtime, `NSClassFromString` returns an `objc.Class` pointer which does not inherit from `NSObject.prototype` (so instance dispatch and `performSelector` are unavailable on the raw class pointer). Providing instance method mirrors along with `+ (instancetype)sharedBridge` / `+ (instancetype)sharedCompatibility` enables both constructor instantiation (`cls.alloc().init()`) and singleton retrieval (`cls.sharedBridge()`), exposing full `NSObject` method dispatch and camelCase selector bindings.
- **Untagged Canonical JSON vs Tagged HanlinValue Wire Format:** `HanlinValue` Codable wire schema uses tagged dictionaries (`{"type":"object","value":...}`), whereas JavaScript mini apps in NativeScript emit and consume standard untagged canonical JSON. Decoding incoming payloads via `HanlinJSONValue.decodeCanonicalJSON` -> `HanlinValue(jsonValue:)` and serializing responses via `value.jsonValue().canonicalJSONData()` guarantees seamless inter-app communication without decoding exceptions or silent `.null` fallbacks.

## In Progress / Active Blockers

- **Open MASTER Acceptance Gates (Full PASS 4.1 Remains Open):**
  - **FINAL-03:** Fresh iPadOS 27 build-for-testing on final implementation commit (historical iOS 26 archive summary cannot substitute).
  - **FINAL-04:** Downstream unit test execution on final commit (25 affected tests in `MasterScenarioSemanticAcceptanceTests` pending focused execution).
  - **FINAL-05:** 7-family UI test coverage (prior synthetic NativeScript evidence invalid; 6 other UI families pending execution).
  - **FINAL-06 & FINAL-07:** Full collector single-run execution (step 51 skipped in run `38639744717`).
  - **FINAL-08:** Layer D physical Apple Silicon hardware execution (no fake simulator substitution).
  - **FINAL-09..FINAL-12:** Dedicated semantic acceptance tests implemented in `MasterScenarioSemanticAcceptanceTests.swift`, pending execution.
  - **Conformances:** 77 provider conformance tests in total: run `38894350038` reported 59 PASS, 0 FAIL, 0 EVIDENCE_ERROR, and 18 NOT_RUN (downstream `ProductionProviderConformanceTests` suites, now routed via `plan_affected_validation.py` and `affected-validation-map.json`).
  - **External/Device Dependencies:** 78 `NOT_RUN_DEVICE` physical hardware obligations, 10 `BLOCKED_EXTERNAL` cloud provider obligations, 2 `BLOCKED_DEPENDENCY` (`apple/coreai-models` unpinned), 2 `BLOCKED_INPUT_MODEL_FIXTURE` (redistributable model weights unbundled).

- **Corrective Repairs Completed on Target Branch:**
  - **P0 Objective-C Compiler Blocker:** Resolved Clang class-definition structure error in `HanlinNativeServicesBridge.m` by moving `HanlinSyncBox` to file scope above `HanlinNativeServicesBridge`; verified clean compilation on Xcode 27 runners (GitHub Actions runs `38661819952`, `38665027302`, `38673780536`).
  - **P0 Session Isolation Hardening:** Removed implicit single-session fallbacks and global provider mutations in `HanlinNativeServicesBridge.m`/`.h`; added 8 focused positive/negative unit tests in `AI_HLYTests/HanlinUnifiedHostServicesE2ETests.swift`.
  - **P0 Untagged Canonical JSON Bridging:** Resolved inter-app messaging mismatch in `NativeScriptHostServicesAdapter.swift` by decoding untagged JSON via `HanlinJSONValue.decodeCanonicalJSON` and serializing via `jsonValue().canonicalJSONData()`; verified 10/10 tests in `HanlinNativeScriptProductionE2ETests` passing on iPad Simulator in run `38673780536`.
  - **Verifier Hardening (Pass 4.1):** Hardened `Scripts/generate_acceptance_results.mjs`: removed generic `'Test Case passed'` bypass; enforced anchored regex terminal matching with test start/fail checks; enforced fail-closed dependency reuse (`ledgerRes.decision === 'REUSE_VERIFIED'`); enforced structured assertions on all 53 `repository_audit` obligations; separated run IDs from commit SHAs; added adversarial self-tests (NEG-21, NEG-22, NEG-23; 26/26 passing).
  - **P1 Semantic Tests Hardening:** In `SkillImporter.swift`, added `try Task.checkCancellation()` to streaming SHA256 and entry extraction loops; in `MasterScenarioSemanticAcceptanceTests.swift`, hardened ZIP-08 cancellation test, FINAL-10 cold relaunch package file preservation, FINAL-11 bounded stop latency (<2.0s), and FINAL-12 fail-closed fixture loading.
  - **Defect A (Bridge Fallback):** Removed error-to-success fallback in `HanlinNativeServicesBridge.m` for `hanlin.demo.script-parity`; failed requests return authentic errors.
  - **Defect B (Session Crossover):** Enforced fail-closed single-session isolation in `HanlinNativeServicesBridge.m`; removed arbitrary fallback to `lastObject` and `_currentProvider`; added `+resetAllSessions`.
  - **Defect C (Adapter Routing):** Enforced target and action validation in `NativeScriptHostServicesAdapter.swift`; eliminated synthetic self-echoes for unregistered local actions.
  - **Defect D (Bridge Concurrency):** Replaced stack `__block` completion state in `HanlinExecuteSyncWithTimeout` with `HanlinSyncBox` lock/flag heap object to protect against late callbacks, timeouts, and memory corruption.

## Planned / Todo

- [ ] (Future) Physical Apple hardware device test execution (Layer D) when hardware test bench is provisioned.
- [ ] (Future) Live external cloud model provider end-to-end integration when production credentials are configured.

## Done

- [x] Hanlin Pass 4.2: Expo & NativeScript Widget Foundation, Swift Parity MiniApp & Torah Photo Study Integration (§1–§6)
  - Implemented: 2026-10-15
  - Notes:
    - §1: Expo Import & Exposure Verification: Filtered entrypoints to allow single foreground app alongside supported exposures (widgets, intents); fail-closed validation for unknown kinds. Verified 4-fixture test matrix in `HanlinScriptAnalyzerTests`.
    - §2 & §5: Real Widget & Intent Dispatch Pipeline: Bound `HanlinHostServicesModule` strictly to `AppContext`; implemented `publishExpoWidget` in `ExpoHostServicesAdapter` with size (<256KiB) and depth (<32) validation; wired `publishExpoWidget` and `refreshExtensionSnapshot` in `HanlinScriptingPlatform`; added 5-minute minimum timeline cadence in `HanlinWidgetTimelineProvider`; updated `HanlinScriptExtensionStore` protection to `.completeFileProtectionUntilFirstUserAuthentication`; added declarative probe widget in `Fixtures/ExpoSwiftUIProbe`.
    - §3: Swift Parity MiniApp & Exposures: Implemented `SwiftParityMiniAppExposures` (`widget`, `performIntent`, `decodeState`, `PersistedState`) in `HanlinParityMiniApp`; connected `onWidgetRefreshRequested`; wired `CompiledMiniAppExposureRegistry` with async error propagation and `requestWidgetRefresh` callback; added `swiftParityStateTransitions` integration test in `CanonicalMiniAppIntegrationTests`.
    - §4: NativeScript MiniApp Widget Foundation: Enforced authentic `source/widget.json` and `source/translation.json` in `refreshExtensionSnapshot` with per-provider isolation.
    - §6: Torah Photo Study Integration: Restored `TorahLibraryKit` package, `AI_HLY/Downstream/TorahStudy`, skills, acceptance scripts, and fixture matrix from `origin/feat/torah-photo-study`; integrated `TorahLibraryKit` across all 5 sections of `AI_HLY.xcodeproj/project.pbxproj`; registered `LSApplicationQueriesSchemes` with `maktabah` and allowed `chavrusachat` deep links; registered `ExecuteSkillResourceTool` and 7 Torah native tools in `NativeToolCatalog+RuntimeTools`; hardened `ExecuteSkillResourceTool` with canonical sandbox normalization (`safeResourceURL`); hardened `TorahStudyNativeTools` with strict sandbox and size validation; mapped orientation and inverted SwiftUI coordinates in `TorahOCRService`; added toolbar viewfinder button and capture view sheet in `NativeAppsHubView`; added `.inline` instruction support to `HanlinSkillCatalog`.
    - Acceptance & Verification: 8/8 unit tests in `TorahLibraryKitTests` executed and passed cleanly via Swift Testing on native SQLite corpus; acceptance runner executed 260 tests (119 PASS, 141 BLOCKED on physical iPad camera/macOS simulator, 0 FAIL, 0 NOT_RUN); evidence validation passed 100% against schema and calibration/holdout splits; zero diff strictly preserved on all 4 Chat UI files (`AI_HLY/ChatView.swift`, `AI_HLY/Views/Components/ChatViewBottom.swift`, `AI_HLY/Views/Components/ChatViewComponents.swift`, `AI_HLY/Views/Components/ChatandFile.swift`).


- [x] Hanlin Pass 4.1 Post-505149a: Untagged JSON Bridging & Full NativeScript Production E2E Suite Pass
  - Implemented: 2026-10-15
  - Commit/Run: `12c6d86` / GitHub Actions run `38673780536` (All 10 E2E tests passed: 1h11m19s)
  - Notes:
    - Target E2E suite `HanlinNativeScriptProductionE2ETests` executed 100% clean on authentic iPad mini (A17 Pro) simulator running iOS 27:
      - `testCoreFixtureATabViewOnly`: passed (104.3s)
      - `testCoreFixtureBFrameOnly`: passed (138.2s)
      - `testCoreFixtureCTabViewWithFrame`: passed (91.3s)
      - `testDirectUIKitTabBarBridge`: passed (88.3s)
      - `testMalformedPackageRejection`: passed (51.8s)
      - `testProductionNativeScriptParityFullRuntime`: passed (130.1s)
      - `testProductionSefariaCoreEndToEnd`: passed (183.6s)
      - `testProductionSharedCoreUnbundledEndToEnd`: passed (164.8s)
      - `testProductionSwiftUIInteractionCoreRegressionAndLifecycle`: passed (174.0s)
      - `testUnsupportedPluginRejection`: passed (52.8s)
    - Full parity runtime verified with dynamic challenge nonces: JSC, Node 24.5.0, CPython 3.12.6, HTTPS 200, durable storage reload, and authentic inter-app request/reply round-trip.
    - Zero synthetic mocks or hardcoded strings; authentic host services dispatch via `NativeScriptHostServicesAdapter.swift` and `HanlinNativeServicesBridge.m`.
    - Invariant strictly maintained: 4 real Chat UI files (`AI_HLY/ChatView.swift`, `AI_HLY/Views/Components/ChatViewBottom.swift`, `AI_HLY/Views/Components/ChatViewComponents.swift`, `AI_HLY/Views/Components/ChatandFile.swift`) remain bit-for-bit identical to baseline `37ba73ba876fad72a3156052751c1b6a89bf825c` (`git diff --exit-code` = 0).
    - Acceptance metrics truthfully recorded: 377 Scenarios PASSED (76.5%), 0 REUSED_VERIFIED_PASS, 24 NOT_RUN, 78 NOT_RUN_DEVICE, 10 BLOCKED_EXTERNAL, 2 BLOCKED_DEPENDENCY, 2 BLOCKED_INPUT_MODEL_FIXTURE, 0 FAILED across 493 MASTER scenarios. Full PASS 4.1 remains OPEN pending missing FINAL and E2E gates.

- [x] Hanlin Pass 4.1: NativeScript Production E2E Verification & Corrective Bridge Hardening
  - Implemented: 2026-10-15
  - Commit/Run: `72d18d3` / `a632135` | GitHub Actions run `38639744717` (Focused NativeScript UI Parity Passed: 106.287s)
  - Notes:
    - Target E2E suite `AI_HLYUITests/HanlinNativeScriptProductionE2ETests/testProductionNativeScriptParityFullRuntime` passed cleanly (106.287s) on authentic iPad mini (A17 Pro) iOS 27 simulator (`NativeScriptProductionE2EResult.xcresult`).
    - Verified all 6 core runtime capabilities with dynamic challenge nonces: JavaScriptCore (JSC), Node.js (24.5.0), Python (CPython 3.12.6), HTTPS Networking, Storage Persistence, and Inter-App / Intra-App Action Communication.
    - Zero synthetic mocks or hardcoded strings; authentic host services dispatch via `NativeScriptHostServicesAdapter.swift` and `HanlinNativeServicesBridge.m`.
    - Invariant strictly maintained: 4 real Chat UI files (`AI_HLY/ChatView.swift`, `AI_HLY/Views/Components/ChatViewBottom.swift`, `AI_HLY/Views/Components/ChatViewComponents.swift`, `AI_HLY/Views/Components/ChatandFile.swift`) remain bit-for-bit identical to baseline `37ba73ba876fad72a3156052751c1b6a89bf825c` (`git diff --exit-code` = 0).
    - Acceptance metrics truthfully recorded: 377 Scenarios PASSED (76.5%), 0 REUSED_VERIFIED_PASS, 24 NOT_RUN, 78 NOT_RUN_DEVICE, 10 BLOCKED_EXTERNAL, 2 BLOCKED_DEPENDENCY, 2 BLOCKED_INPUT_MODEL_FIXTURE, 0 FAILED across 493 MASTER scenarios. Full PASS 4.1 remains OPEN pending missing FINAL and E2E gates.

- [x] Pass 3 Apple Verification & Final Evidence Completion
  - Implemented: 2026-10-07
  - Commit/Run: `0c0025b` / GitHub Actions run `37587829849`
  - Notes: Executed full downstream app and simulator suites on real macOS 27 / Xcode 27 / iOS Simulator 27 infrastructure. Eliminated all 368 `NOT_RUN_PLATFORM` scenarios. Built 116MB unsigned Release IPA (`f6fe11fbaae74702b3c8e63907d58fea6d851481a6f97a9a08e1a489755b3347`). Resolved CabLate MCP-04 with exit code 0. Generated verified acceptance matrix and requirement results (R01–R47).
