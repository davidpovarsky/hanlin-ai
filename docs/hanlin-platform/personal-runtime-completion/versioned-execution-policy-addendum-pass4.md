# Hanlin Execution Policy Addendum — Pass 4: Audited Evidence Reuse & Closure Aggregation

- **Addendum ID:** `EPA-2026-10-13-PASS4`
- **Specification Contract Version:** `2.2.0-pass4`
- **Authorizing Owner Directive:** Explicit owner directive authorizing impact-aware reuse of authentic, unaffected test results at final acceptance without repeating unimpacted hours of compilation.
- **Frozen Master Spec Hash:** Preserved verbatim from `authoritative-master-spec.md` (`specSha256`).

---

## 1. Scope & Objective

This addendum governs the mechanics of authentic test evidence reuse and aggregate final acceptance. It defines strict rules under which previously executed and verified passing test evidence may satisfy scenario obligations on descendant commits.

**Non-Negotiable Core Principle:** This policy governs the *evidence mechanics* of verification; it does **not** alter, relax, or waive any functional requirement, layer constraint, or coverage obligation defined in the authoritative MASTER specification.

---

## 2. Invariants for Evidence Reuse

A test obligation may be certified as `REUSED_VERIFIED_PASS` if and only if **all** of the following conditions are independently and mathematically proven:

1. **Authentic Historical Execution:**
   - The test executed in a verified, successful GitHub Actions run or authenticated local environment.
   - The origin workflow run ID and origin commit SHA are recorded and match authoritative GitHub metadata.
   - The test was directly executed and recorded as `Passed` in raw machine-readable artifacts (`xcresult`, TAP log, or structured test runner output). Name-only presence or declarative JSON status is not acceptable.

2. **Immutable Artifact Provenance & Digest:**
   - Raw artifact files (e.g. `simulator-downstream-unit-test-results.json`, test logs) are verified via SHA-256 checksums matching the immutable manifest.
   - Missing or tampered artifacts cause immediate failure (`NEG-08`).

3. **Complete Dependency Closure Verification:**
   - Every file modified in the Git commit range between `originSHA` and target `HEAD` is inspected (`git diff --name-only originSHA HEAD`).
   - If any global shared dependency (`Package.resolved`, `package-lock.json`, `AI_HLY.xcodeproj`, `AI_HLY.entitlements`, `Config.xcconfig`) was modified, reuse is **invalidated** (`NEG-07`).
   - If any source file, test file, bridge, or fixture within the test's dependency graph was modified, reuse is **invalidated** (`NEG-05`, `NEG-06`).
   - Only commits proven to touch exclusively non-impactful paths (such as documentation `*.md` or repo assets) permit reuse (`POS-02`).

4. **Newer Failure Precedence:**
   - If a descendant commit ran the test or related suite and produced a `Failed` result, the older passing evidence is superseded and **invalidated** (`NEG-04`, `NEG-14`). A new failure always outranks an older pass.

5. **No Synthetic or Fabricated Execution:**
   - Evidence produced via client-side fallbacks (e.g., `Function(...)` evaluation, hardcoded numeric/HTTP literals, or mock inter-app responses) is rejected as synthetic (`NEG-11`). True production host routing is mandatory.

---

## 3. Provenance Schema & Status Classes

Evidence reports must distinguish:

| Status Class | Definition |
|---|---|
| `EXECUTED_PASS` / `PASSED` | Test was executed on the current target implementation SHA and passed. |
| `REUSED_VERIFIED_PASS` | Authentic pass from a verified ancestor run reused under strict clean dependency closure. |
| `NOT_RUN` | Obligation has not yet executed or is awaiting execution. |
| `NOT_RUN_DEVICE` | Scenario proven on simulator/integration, awaiting physical Apple hardware (`LIM-04`). |
| `BLOCKED_EXTERNAL` | Requires live third-party cloud credentials or public internet in sandbox. |
| `BLOCKED_DEPENDENCY` | Required external Swift package dependency is unpinned. |
| `BLOCKED_INPUT_MODEL_FIXTURE` | Redistributable on-device model fixture is unbundled (`COREAI-06`). |
| `FAILED` | Test or build executed and produced a failure. |

---

## 4. Final Gate Reconciliation (`FINAL-01` through `FINAL-12`)

- **`FINAL-01` (HanlinPlatform swift-test):** Authentic Phase 1 execution preserved if package sources and toolchain are unchanged.
- **`FINAL-02` (RuntimeCore npm-test):** Genuine Node host TAP execution (`direct-blocked may import child_process without executing it` and ESM Hebrew execution) preserved as long as RuntimeCore sources and lockfiles are unchanged.
- **`FINAL-03` (iPadOS 27 build-for-testing):** Requires real `build-for-testing` evidence targeting iPadOS 27 simulator on final implementation commit. Stale iOS 26 archive cannot satisfy this gate (`NOT_RUN` pending operator CI run).
- **`FINAL-04` (App Unit/Integration):** Broken down into individual case ledger decisions rather than a single bulk pass. 235 tests verified clean and reusable; 25 tests in `MasterScenarioSemanticAcceptanceTests` affected and pending focused execution.
- **`FINAL-05` (Targeted UI 7 Families):** Requires complete inventory across all 7 UI families: Skills, runtime command/install, ScriptUI, NativeScript, Expo, Agent conversation, and rich chat. Legacy synthetic NativeScript evidence invalidated; all families marked `NOT_RUN` pending focused UI runs.
- **`FINAL-06` (Affected Validation Groups):** Requires successful manual GitHub Actions execution on target code with selected validation groups (`NOT_RUN` pending operator CI run).
- **`FINAL-07` (Full CI Validation):**
  - *Aggregated Verification Status:* Engineering coverage certified when all component obligations are proven either by fresh execution or audited `REUSED_VERIFIED_PASS`.
  - *Literal Single-Run Clause:* If governance strictly requires a single physical unbroken GitHub Actions run executing all 493 suites simultaneously on the exact target commit, the literal original `FINAL-07` clause remains `NOT_RUN` pending explicit owner dispatch.
- **`FINAL-08` (Physical Device Acceptance):** Truthfully classified as `NOT_RUN_DEVICE` awaiting physical Apple hardware (`LIM-04`).
- **`FINAL-09` (Live Provider Discovery & Tool Execution):** Dedicated semantic test `final09LiveToolDiscoveryAndExecution` in `MasterScenarioSemanticAcceptanceTests`.
- **`FINAL-10` (Cold State Restoration & Reset):** Dedicated semantic test `final10ColdRelaunchStateRestorationAndToolReset`.
- **`FINAL-11` (Cancellation & Immediate Clean Run):** Dedicated semantic test `final11CancellationAndImmediateNextRunCleanliness`.
- **`FINAL-12` (Invariant & Tool Cross-Join):** Dedicated semantic test `final12InvariantsAndToolsCrossJoinAudit`.

---

## 5. Pass 4.1 Remediation Specifications (`EPA-2026-10-13-PASS4.1`)

1. **Per-Case Reuse from Partially Failed Workflows:**
   - GitHub Actions run `38234823425` failed overall at workflow level, but contains valid, completed unit test execution steps.
   - Tests from this run may be reused **case by case** via `TestDependencyLedger` if and only if:
     - The case completed with status `Passed` in raw machine-readable `xcresulttool` index.
     - The case's entire transitive dependency closure (source, tests, fixtures, lockfiles, project settings) is demonstrably unmodified between `0095b6441e8968d4200e8cd8acf42f61b46b7c59` and target `HEAD`.
     - No newer failed execution exists at descendant commits.
   - Unknown suite mappings fail closed (`INVALIDATE`), never defaulting to blanket reuse.

2. **Authentic NativeScript Parity Proofs vs Synthetic Fallbacks:**
   - All synthetic fallback mechanisms (e.g. `Function(...)` evaluation returning fixed `"246"` or `"123"`) are strictly forbidden.
   - Proof of runtime parity requires a dynamic, unpredictable challenge nonce (`HANLIN_PARITY_CHALLENGE`) passed into the runtime and verified across JavaScriptCore, embedded Node.js, embedded Python, HostServices HTTPS, and inter-app mini-app routing.
   - NativeScript bridge providers are strictly bound to active sessions (`registerProvider:forSessionID:`); global fallbacks and placeholder replies (`reply(@"{}", nil)`) on active production paths are eliminated.
   - Bridge synchronous synchronization avoids deceptive "nonblocking" labels; nested run loop waiting is contained to safe, bounded execution without main-thread deadlocks.

3. **Streaming Skills Archive Import:**
   - Archives >25 MiB compressed on disk and >64 MiB expanded (`ZIP-08`) must be inspected and extracted using bounded 64KB streaming I/O (`FileHandle`), preventing full in-memory duplication and guaranteeing atomic cleanup on cancellation or failure.

4. **Pure Python Wheel Installation (`PY-02`):**
   - Fabricated `sys.modules` injection is strictly prohibited. `PY-02` must exercise the real `PythonPackageManager` installation pipeline with on-disk `.dist-info` verification, authentic pure-Python wheel extraction, and isolated interpreter import from the installed disk location.

5. **Report Provenance & Immutability:**
   - Acceptance reports must accurately report distinct `sourceImplementationSHA`, `testExecutionSHA`, `evidenceRunSHA`, and `reportSHA`.
   - Reused tests must not be falsely stamped as having executed on target HEAD.
   - Gate evaluation (`--mode=gate`) must fail closed (exit code 1) whenever mandatory obligations are not met, preventing false-green assertions.
