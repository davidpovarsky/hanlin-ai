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
- **Bash `set -u` Safe Array Expansion:** Expanding an empty array `"${arr[@]}"` under `set -u` aborts with `unbound variable`. Use `"${arr[@]+"${arr[@]}"}"` for portable, safe expansion.
- **NativeScript iOS Dynamic Bridge Dispatch Without Metadata Recompilation:** In embedded NativeScript runtimes where binary metadata generation is skipped during simulator builds, new Objective-C class methods are not dynamically added to the JavaScript class prototype. Routing Host Services invocations through the pre-bound `roundTripValue:key:` selector (`compat.roundTripValueKey(value, key)`) guarantees deterministic execution of JavaScript, Node, Python, HTTPS network requests, and inter-app messaging without requiring offline binary metadata updates.
- **NativeScript Objective-C Class vs Instance Bridging:** In NativeScript iOS runtime, `NSClassFromString` returns an `objc.Class` pointer which does not inherit from `NSObject.prototype` (so instance dispatch and `performSelector` are unavailable on the raw class pointer). Providing instance method mirrors along with `+ (instancetype)sharedBridge` / `+ (instancetype)sharedCompatibility` enables both constructor instantiation (`cls.alloc().init()`) and singleton retrieval (`cls.sharedBridge()`), exposing full `NSObject` method dispatch and camelCase selector bindings.

## In Progress / Active Blockers

## In Progress / Active Blockers

None currently blocking.

## Planned / Todo

- [ ] (Future) Physical Apple hardware device test execution (Layer D) when hardware test bench is provisioned.
- [ ] (Future) Live external cloud model provider end-to-end integration when production credentials are configured.

## Done

- [x] Hanlin Pass 4.1: NativeScript Production E2E Closure & Authentic Simulator Verification
  - Implemented: 2026-10-15
  - Commit/Run: `72d18d3` / `a510847` | GitHub Actions run `38639744717` (Exit Code 0, Green CI)
  - Notes:
    - Target E2E suite `AI_HLYUITests/HanlinNativeScriptProductionE2ETests/testProductionNativeScriptParityFullRuntime` passed cleanly (106.287s) on authentic iPad mini (A17 Pro) iOS 27 simulator (`NativeScriptProductionE2EResult.xcresult`).
    - Verified all 6 core runtime capabilities with dynamic challenge nonces: JavaScriptCore (JSC), Node.js (24.5.0), Python (CPython 3.12.6), HTTPS Networking, Storage Persistence, and Inter-App / Intra-App Action Communication.
    - Zero synthetic mocks or hardcoded strings; authentic host services dispatch via `NativeScriptHostServicesAdapter.swift` and `HanlinNativeServicesBridge.m`.
    - Invariant strictly maintained: 4 Chat UI files (`ChatView.swift`, `ChatBubbleView.swift`, `ChatViewBottom.swift`, `AI_HLY/ChatView.swift`) remain bit-for-bit identical to baseline `37ba73ba876fad72a3156052751c1b6a89bf825c` (`git diff --exit-code` = 0).
    - Acceptance metrics updated: 379 Scenarios PASSED (76.9%), 0 FAILED across 493 MASTER scenarios.

- [x] Pass 3 Apple Verification & Final Evidence Completion
  - Implemented: 2026-10-07
  - Commit/Run: `0c0025b` / GitHub Actions run `37587829849`
  - Notes: Executed full downstream app and simulator suites on real macOS 27 / Xcode 27 / iOS Simulator 27 infrastructure. Eliminated all 368 `NOT_RUN_PLATFORM` scenarios. Built 116MB unsigned Release IPA (`f6fe11fbaae74702b3c8e63907d58fea6d851481a6f97a9a08e1a489755b3347`). Resolved CabLate MCP-04 with exit code 0. Generated verified acceptance matrix and requirement results (R01–R47).
