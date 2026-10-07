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

## Planned / Todo

- [ ] Fix the 6 real iOS Simulator unit test failures discovered in Pass 3:
  - [ ] `SH-03`: Align iOS Simulator sandbox policy errno handling for `parent_traversal` and `absolute_path` in `HanlinUnifiedHostServicesAgentAcceptanceTests.swift`.
  - [ ] `SH-05`: Correct symlink rejection outcome expectations (`.invalidArguments` vs `.succeeded`/`.failed`) in `HanlinUnifiedHostServicesAgentAcceptanceTests.swift`.
  - [ ] `CMD-04`: Update advertised schema properties in `RuntimeToolContractTests.swift` (`program` vs `command`/`arguments`/`allow_network`).
  - [ ] `ZIP-04`: Fix `SkillStore` override precedence title assertion in `SkillStoreAndImportTests.swift`.
  - [ ] `ZIP-07`: Ensure atomic rollback retains initial record title on failed replacement in `SkillStoreAndImportTests.swift`.
  - [ ] `ZIP-11`: Align `HanlinArchivePolicy.inspectSkillArchive` security threat detection for symlink entries in `SkillStoreAndImportTests.swift`.

## Done

- [x] Pass 3 Apple Verification & Final Evidence Completion
  - Implemented: 2026-10-07
  - Commit/Run: `0c0025b` / GitHub Actions run `37587829849`
  - Notes: Executed full downstream app and simulator suites on real macOS 27 / Xcode 27 / iOS Simulator 27 infrastructure. Eliminated all 368 `NOT_RUN_PLATFORM` scenarios (417 PASSED, 6 FAILED, 60 NOT_RUN_DEVICE, 10 BLOCKED_EXTERNAL, 0 NOT_RUN_PLATFORM). Built 116MB unsigned Release IPA (`f6fe11fbaae74702b3c8e63907d58fea6d851481a6f97a9a08e1a489755b3347`). Resolved CabLate MCP-04 with exit code 0. Generated verified acceptance matrix and requirement results (R01–R47).
