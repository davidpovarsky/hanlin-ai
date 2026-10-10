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

## Planned / Todo

- [ ] (Future) Physical Apple hardware device test execution (Layer D) when hardware test bench is provisioned.
- [ ] (Future) Live external cloud model provider end-to-end integration when production credentials are configured.

## Done

- [x] Hanlin Final Closure & Authoritative Semantic Evidence Pipeline
  - Implemented: 2026-10-11
  - Commit/Run: Implementation `9acb412e30de92f51e88ad05be43d315f85df3e4` / Evidence Run `d13c29a6c1a4184c20b280cef51d3319c094b202` (GitHub Actions Runs `37857022894` & `37852056379`)
  - Notes: Ingested authoritative 493 MASTER specification (`BF76406CEE...`). Extracted authentic `simulator-downstream-unit-test-results.json` from CI Run `37857022894` (21 suites, 184 tests, 184 passed, 0 failed). Separated 6 historical XCTest regression fixes (`REG-*`) from MASTER scenario IDs and implemented dedicated semantic acceptance tests (`MasterScenarioSemanticAcceptanceTests.swift`) for `CHAT-24`, `SH-03`, `SH-05`, `CMD-04`, `ZIP-04`, `ZIP-07`, `ZIP-11`, and `COREAI-06`. Implemented production `FoundationModels` session backend (`R45`) and truthful Path B dependency/fixture reporting for Core AI (`R46`). Rebuilt `scenario-evidence-map.json` and `Scripts/generate_acceptance_results.mjs` with explicit verifier kinds, strict layer enforcement (`D` never satisfied by simulator), and 10 semantic negative self-tests (all passing in `--mode=gate`). Chat UI strictly frozen.
- [x] Pass 3 Apple Verification & Final Evidence Completion
  - Implemented: 2026-10-07
  - Commit/Run: `0c0025b` / GitHub Actions run `37587829849`
  - Notes: Executed full downstream app and simulator suites on real macOS 27 / Xcode 27 / iOS Simulator 27 infrastructure. Eliminated all 368 `NOT_RUN_PLATFORM` scenarios (417 PASSED, 6 FAILED, 60 NOT_RUN_DEVICE, 10 BLOCKED_EXTERNAL, 0 NOT_RUN_PLATFORM). Built 116MB unsigned Release IPA (`f6fe11fbaae74702b3c8e63907d58fea6d851481a6f97a9a08e1a489755b3347`). Resolved CabLate MCP-04 with exit code 0. Generated verified acceptance matrix and requirement results (R01–R47).
