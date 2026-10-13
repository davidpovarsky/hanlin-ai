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

- [ ] **Hanlin Pass 4: Real Runtime Truth, Evidence Integrity & Impact-Aware Acceptance**
  - **Status:** In Progress (Stages B, C, and D Implementation Completed; Awaiting Authorized CI Verification).
  - **Historical Runs:**
      - Run `38234823425`: Full CI failed (`workflowConclusion=failure`, `testProductionNativeScriptParityFullRuntime` failed).
      - Run `38317896632`: Focused CI succeeded (`workflowConclusion=success`, commit `31cba5e`), but parity test passed via synthetic fallbacks in `bundle.mjs`. Multi-runtime parity (Node/Python/Network/Inter-App) now has authentic proofs without fallbacks.
  - **Completed Workstreams:**
      1. [COMPLETED] NativeScript Parity Truth: Eliminated all synthetic JavaScript fallbacks (`Function(...)`, literal `"246"`, `"123"`, `"HTTPS 200"`, local inter-app JSON). Wrapped label updates on main thread. Added genuine Node (`process.versions.node`) and CPython (`sys.version_info`) runtime proofs. Fixed `HanlinNativeServicesBridge.m` session provider leak and converted sync loops to non-blocking `runMode:beforeDate:`. Guard unit tests pass cleanly.
      2. [COMPLETED] Evidence Integrity & Generator: Overhauled `Scripts/generate_acceptance_results.mjs` with strict CLI flag handling (rejects unsupported flags, supports `--verify-self-test` and `--self-test` alias). Decoupled untrusted declarative claims from raw evidence. Added dynamic Git provenance derivation. Implemented 18 adversarial verifier tests (`NEG-01`–`NEG-15`) and positive checks (`POS-01`–`POS-03`) passing deterministically in an isolated sandbox without mutating canonical results.
      3. [COMPLETED] Impact-Aware Validation Engine: Implemented `TestDependencyLedger` in `Scripts/CI/plan_affected_validation.py`. Narrowed `no_impact_patterns` in `Scripts/CI/affected-validation-map.json` by removing lockfiles, vendor dependencies, and runtime `.mjs` scripts. Unit test suite passes with 95 tests.
      4. [COMPLETED] Missing Engineering Scenarios Implementation: Implemented authentic tests for `ZIP-01`, `ZIP-02`, `ZIP-08`, `FS-01`, `SH-01`, `CMD-01`, and `PY-02` in `AI_HLYTests/MasterScenarioSemanticAcceptanceTests.swift`. Removed artificial 25MB local import cutoff in `SkillImporter.swift`.
      5. [COMPLETED] Versioned Execution Policy Addendum: Authored `docs/hanlin-platform/personal-runtime-completion/versioned-execution-policy-addendum-pass4.md` defining strict mathematical evidence reuse and transparent handling of `FINAL-07`.
  - **Open Gates:**
      - Targeted Xcode/macOS CI execution of NativeScript parity and newly added unit tests.
      - Physical device obligations (78 Layer D cases) remain device-pending (`NOT_RUN_DEVICE`).
      - External API credentials (10 cases) and unpinned Core AI dependency (2 cases) remain accurately blocked (`BLOCKED_EXTERNAL`, `BLOCKED_DEPENDENCY`, `BLOCKED_INPUT_MODEL_FIXTURE`).

## Planned / Todo

- [ ] (Future) Physical Apple hardware device test execution (Layer D) when hardware test bench is provisioned.
- [ ] (Future) Live external cloud model provider end-to-end integration when production credentials are configured.

## Done

- [x] Pass 3 Apple Verification & Final Evidence Completion
  - Implemented: 2026-10-07
  - Commit/Run: `0c0025b` / GitHub Actions run `37587829849`
  - Notes: Executed full downstream app and simulator suites on real macOS 27 / Xcode 27 / iOS Simulator 27 infrastructure. Eliminated all 368 `NOT_RUN_PLATFORM` scenarios. Built 116MB unsigned Release IPA (`f6fe11fbaae74702b3c8e63907d58fea6d851481a6f97a9a08e1a489755b3347`). Resolved CabLate MCP-04 with exit code 0. Generated verified acceptance matrix and requirement results (R01–R47).
