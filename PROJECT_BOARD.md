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

## In Progress / Active Blockers

## In Progress / Active Blockers

- [ ] **Hanlin Pass 4.1: Fail-Closed Evidence Integrity, Real Runtime Proofs & Semantic MASTER Repair**
  - **Status:** Local Implementation & Tooling Verification Completed; Remote Apple CI Dispatch Pending Explicit Owner Command.
  - **Historical Runs & Baseline:**
      - Run `38234823425`: Failed overall; 235 unit tests verified clean and reusable via `TestDependencyLedger`; 25 tests in `MasterScenarioSemanticAcceptanceTests` affected and pending focused execution.
      - Run `38317896632`: Focused run with synthetic legacy NativeScript evidence; invalidated.
  - **Completed PASS 4.1 Workstreams:**
      1. [COMPLETED] NativeScript Bridge & Dynamic Parity Nonces: Eliminated all synthetic JS fallbacks and fixed literals (`"246"`, `"123"`, `"HTTPS 200"`). Implemented dynamic `HANLIN_PARITY_CHALLENGE` roundtrip verification across JSC, Node, Python, HostServices HTTPS, and MiniApp routing. In `HanlinNativeServicesBridge.m`, eliminated session provider fallback leak, cleared provider/bridges upon unregistration, eliminated placeholder `reply(@"{}", nil)` on production paths, and constrained synchronous execution to safe, bounded executors without main-thread deadlocks. Rebuilt `.hanlinNativeScript` archive byte-for-byte; verified with `test_nativescript_parity_fixture.py` (4/4 passed).
      2. [COMPLETED] Verifier & Acceptance Engine Hardening: Overhauled `Scripts/generate_acceptance_results.mjs`. Fixed `NEG-11` (synthetic fallback rejection with active injection) and `NEG-12` (isolated subprocess CLI test). All 18 adversarial self-tests and positive controls pass deterministically. Collision-safe `xcresult` indexing implemented. Integrated `verifyDependencyClosure` with `TestDependencyLedger` CLI.
      3. [COMPLETED] Dependency Ledger & Routing Engine: In `Scripts/CI/plan_affected_validation.py` and `affected-validation-map.json`, unknown suites fail closed (`INVALIDATE`). Narrowed `no_impact_patterns` (removed blanket `docs/**`); added consumed documents (`scenario-evidence-map.json`, `authoritative-master-spec.md`, contract audit schemas) to `ci_router`. Exposed `--evaluate-reuse` CLI. All 58 tests in `test_affected_validation.py` pass cleanly.
      4. [COMPLETED] Skills Streaming & Configurable PyPI: Implemented bounded 64KB streaming `FileHandle` SHA-256 and atomic staging in `SkillImporter.swift`. Added configurable `pypiBaseURL` in `PythonPackageManager.swift` for loopback test server support.
      5. [COMPLETED] Authentic Semantic Tests (`MasterScenarioSemanticAcceptanceTests.swift`): Implemented `fs01PythonNodeShellSharedWorkspace` (exact multi-engine workspace output + negative context isolation), `sh01DynamicCommandsReconciliationWithoutExact23`, `cmd01AwkExecutionWithPrintArgvSampleText`, `py02DistributionNameDiffersFromImportName` (authentic wheel installed with `.dist-info` and disk import), `zip01`, `zip02`, `zip08` (>25 MiB compressed on disk, >64 MiB expanded, end marker, cancellation), and dedicated methods for `final09`, `final10`, `final11`, `final12`.
      6. [COMPLETED] 493 MASTER Scenario Semantic Coverage Audit: Created `Scripts/Audit/audit_semantic_coverage.mjs`. Remapped `FINAL-01`–`FINAL-12`, `APPENG-03/04/05`, `SCRIPTARCH-04/05`. Replaced 29 `build_command` generic archive references with explicit repository audits and truthfully scoped pending obligations. Generated `semantic-coverage-audit.json` and `.md`.
      7. [COMPLETED] Execution Policy Addendum: Updated `docs/hanlin-platform/personal-runtime-completion/versioned-execution-policy-addendum-pass4.md` with PASS 4.1 specifications (`EPA-2026-10-13-PASS4.1`).
      8. [COMPLETED] Frozen Chat UI Invariant: Verified exact zero diff relative to `37ba73ba876fad72a3156052751c1b6a89bf825c` across all 4 chat files.
  - **Current Status Disposition (493 Scenarios):**
      - `REUSED_VERIFIED_PASS`: 377 (76.5%) — authentically proven unchanged passes from prior runs with verified clean closures.
      - `NOT_RUN / NEEDS_TEST`: 24 (4.9%) — pending operator-authorized focused Apple CI.
      - `NOT_RUN_DEVICE`: 78 (15.8%) — physical Apple hardware / Apple Intelligence obligations.
      - `BLOCKED_EXTERNAL`: 10 (2.0%) — live cloud provider credentials.
      - `BLOCKED_DEPENDENCY`: 2 (0.4%) — unpinned upstream dependency.
      - `BLOCKED_INPUT_MODEL_FIXTURE`: 2 (0.4%) — unbundled model weights.
      - `FAILED`: 0.
  - **Open Gates:**
      - Targeted Apple CI execution on target commit for affected groups (`nativescript_runtime`, `MasterScenarioSemanticAcceptanceTests`, missing `FINAL-05` UI families, and iPadOS 27 simulator `build-for-testing`). CI dispatch remains strictly pending explicit operator authorization.

## Planned / Todo

- [ ] (Future) Physical Apple hardware device test execution (Layer D) when hardware test bench is provisioned.
- [ ] (Future) Live external cloud model provider end-to-end integration when production credentials are configured.

## Done

- [x] Pass 3 Apple Verification & Final Evidence Completion
  - Implemented: 2026-10-07
  - Commit/Run: `0c0025b` / GitHub Actions run `37587829849`
  - Notes: Executed full downstream app and simulator suites on real macOS 27 / Xcode 27 / iOS Simulator 27 infrastructure. Eliminated all 368 `NOT_RUN_PLATFORM` scenarios. Built 116MB unsigned Release IPA (`f6fe11fbaae74702b3c8e63907d58fea6d851481a6f97a9a08e1a489755b3347`). Resolved CabLate MCP-04 with exit code 0. Generated verified acceptance matrix and requirement results (R01–R47).
