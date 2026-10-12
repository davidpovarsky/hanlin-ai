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

## In Progress / Active Blockers

- [ ] **Hanlin Final Semantic Closure & Evidence Rescue (Impact-Aware)**
  - **Status:** In Progress. Full CI run `38234823425` concluded in **FAILURE** (`full_workflow_conclusion=failure`, `ui_e2e_failed>=1`).
  - **Preserved Achievements:** Unit suite `DownstreamTestsResult.xcresult` has 260/260 passed (`unit_xcresult_failed=0`), Unsigned IPA build passed (`0a692362...`), Baseline/compiler validation passed, and Provider Conformance summary passed.
  - **Exact Failure:** Job `114762989410` failed at `Run simulator test suite` due to `AI_HLYUITests/HanlinNativeScriptProductionE2ETests.swift:45` `testProductionNativeScriptParityFullRuntime` (`JavaScript execution did not return expected deterministic output 42`).
  - **Downstream Impact:** Subsequent steps `Run full Runtime Tooling acceptance and collect every group` and `Launch full app and verify runtime acceptance` were skipped.
  - **Active Blockers:**
    1. NativeScript parity E2E failure diagnosis and real production fix.
    2. Permanent instruction updates in `AGENTS.md` and `PROJECT_AGENT_GUIDANCE.md` for impact-aware validation.
    3. Fine-grained exact-method test selection in CI planner and workflow to eliminate 3-hour diagnostic cycles.
    4. Authenticated test-evidence ledger and fail-closed generator verifiers (`repository_audit`, `build_command`, etc.).
    5. Re-audit of 493 MASTER scenario mappings for semantic truth (repairing FINAL-03..FINAL-07, ZIP-01/02/08, FS-01, CMD-01, PY-02, SH-01, COREAI-06).
    6. Verifiable coverage-complete aggregated final acceptance.

## Planned / Todo

- [ ] (Future) Physical Apple hardware device test execution (Layer D) when hardware test bench is provisioned.
- [ ] (Future) Live external cloud model provider end-to-end integration when production credentials are configured.

## Done

- [x] Pass 3 Apple Verification & Final Evidence Completion
  - Implemented: 2026-10-07
  - Commit/Run: `0c0025b` / GitHub Actions run `37587829849`
  - Notes: Executed full downstream app and simulator suites on real macOS 27 / Xcode 27 / iOS Simulator 27 infrastructure. Eliminated all 368 `NOT_RUN_PLATFORM` scenarios. Built 116MB unsigned Release IPA (`f6fe11fbaae74702b3c8e63907d58fea6d851481a6f97a9a08e1a489755b3347`). Resolved CabLate MCP-04 with exit code 0. Generated verified acceptance matrix and requirement results (R01–R47).
