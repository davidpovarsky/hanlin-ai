# W1-003 initial source tranche

[איתן | ARCH+DEV] [MAIN_SESSION] — source tranche ready for scoped review; whole-product acceptance remains open.

Primary `01a1dc79-6761-7463-a196-34771f7929bd`; branch `codex/hanlin-app-split-wave1-20261115`; frozen starting SHA `dd700c03e9fe9d22e95a031d4684275512ee6e6f`.

## Material deliverables

- `HanlinMiniAppsApp/`: independent `@main` source, native split-view library/search/detail/open/full-screen presentation, canonical catalog injection and explicit unconfigured-service errors. No fake catalog or success; no target assembled yet.
- `Packages/HanlinProductSplit/Sources/`: typed foreground envelope/codec/state machine, canonical request/result/launch adapters, exact origin and generation correlation, bounded URL/JSON validation, one-use returns, visible failure paths, versioned byte-preserving snapshot planner, interrupted copy/resume/rollback journal, and marked fixture-only disk adapter.
- `feature-delta-278.json` plus historical blob: all 278 original IDs retained with current baseline file:line/digest anchors, target/visibility/data/permission/accessibility/test/status/unresolved fields. Historical input digest matches `7252f34685839bd179314e8ce7b2266ea035eb73818ef378e9f28158709ce19e`.
- `legacy-ui-decisions.json`: all 26 canonical parent-task choices (14 KEEP, 11 RESTORE/TRIAL, 1 OPEN) mapped to original feature IDs and current split/Morph/A2UI constraints. Detailed original master-prompt attachment remains unavailable; no claim of detailed visual reconciliation/approval.
- `lane-source-snapshots.json`: bounded read-only current Runtime/A2UI/Composer HEADs, dirty paths and selected source hashes; no source copied or merged. `baseline-source-delta.tsv` records current baseline changes from the original 8f24983 source.
- `ARCHITECTURE_AND_INTEGRATION.md`: real API dependency map, foreground transport contract, data inventory, identity/entitlement risks, decision register and one controlled target/wiring/migration proposal.

## Verification actually executed

| Evidence | Result | Meaning |
| --- | --- | --- |
| `coverage-results.json` | EXECUTED_PASS, 278 IDs | Strict ID/row/provenance coverage; 269 feature rows NOT_RUN, 9 BLOCKED; no feature behavior PASS |
| `validator-results.json` | 9/9 EXECUTED_PASS | Reject missing/duplicate/unexpected IDs, unproven PASS, invalid owner/evidence, changed historical text/digest and missing fields |
| `portable-results.json` | 55/55 EXECUTED_PASS | Actual Windows Swift 6.3.3 leaf/adapters, actual canonical contract/catalog/request types, strict concurrency and warnings-as-errors; codec, identity, replay/return failures, package/generation checks, dry-run, version/conflicts, interrupted snapshot restore, tampered journals, rollback conflicts and marked disk fixture |
| `swiftc -frontend -parse HanlinMiniAppsApp/*.swift` (explicit three paths) | EXECUTED_PASS | Syntax only; no SwiftUI/UIKit module/SDK acceptance |
| `git diff --check` | EXECUTED_PASS before commit | Formatting check, not behavioral acceptance |

Final 55-case execution used a focused rebuild of changed owned Swift/test sources against unchanged real canonical DLLs already compiled in this session, then executed the test binary. The report records source and executable SHA256s. Earlier harness attempts failed on an unused SwiftPM `Bundle.module` helper, a missing `try` in a fixture descriptor, and CRLF translation of the fixture marker. Those were corrected; no failed attempt is represented as PASS. The fresh runner uses exact marker bytes, explicit failure reporting (no Swift crash dialog), platform library suffixes and invalidates stale evidence before a run. It is reproducible without a generated manifest, dependency installation or remote build.

## Remaining integration decisions and gates

1. **Target/package assembly is unleased.** No manifests/project/entitlements/signing modified. All source is isolated; two installable apps are not yet proved. Existing app-only host/package UI dependencies must be resolved through one deliberate extraction/composition, not source duplication.
2. **Authenticated transport and receiver durable idempotency are unimplemented.** The sender ledger is not cross-process exactly-once execution. A URL cannot establish caller identity. Mailbox origin/integrity, cold launch, atomic crash recovery and actual foreground open/return require integration and OS/device proof.
3. **Preserve the owner's personal-host policy.** Baseline adds `all` capabilities and host authorization returns `.allowed`; do not invent a new grant/sandbox engine. Connection must separately verify trusted origin/current installed package/generation and iOS system authority before treating a cross-process request as an in-process call. Noam API changes have not been made or assumed.
4. **Production migration is unimplemented and forbidden here.** The planner uses synthetic snapshots only. Disk tests write only fixed fixture slots under `Tests/ProductSplit/.build/fixture-store`; no production store/credential touched. SwiftData/CloudKit consistency, AppGroup/Keychain provisioning, bookmarks, locking, durable two-file transaction recovery and signed backup/restore remain open.
5. **J and H/I remain open.** MiniApps IA/visual acceptance, detailed legacy-prompt reconciliation, all 278 feature behaviors, full SwiftUI/SDK build, independent app install/missing companion, UI accessibility, signed physical device and release acceptance are NOT_RUN/BLOCKED as applicable. Runtime owns the remote native slot.

Next owner: Hanlin Lead + designated integrator, with Noam for existing Host API changes and Maya for Composer routing. Source tranche may enter focused QA; A/J/K/L are not completed wholesale. H `1219605235147314`, I `1219605282038820` stay open. Root performs one consolidated Asana checkpoint. No main merge, push/sync, CI, TestFlight, signing, new agents or Computer Use occurred.
