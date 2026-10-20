# Hanlin AI — CI Caching, Build & Test Optimization Guide

This guide documents the permanent CI optimization architecture implemented in `.github/workflows/build-ios26-unsigned-ipa.yml` and supporting scripts in `Scripts/CI/`.

---

## 1. How the Multi-Tier Cache System Works

The Hanlin CI pipeline uses a multi-tier caching model where each tier is isolated, deterministic, and keyed strictly by its exact dependencies:

1. **Layer A — SPM Dependencies (`actions/cache@v6`)**:
   - **Key**: `ios-sourcepackages-v3-${{ runner.os }}-${{ steps.simulator-toolchain.outputs.runner-arch }}-${{ steps.simulator-toolchain.outputs.xcode-build }}-${{ hashFiles('AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved', 'Packages/**/Package.swift', 'Scripts/NativeScript/dependency-lock.json', 'Scripts/Expo/dependency-lock.json', 'RuntimeDependencies.lock.json') }}`
   - **Restore Keys**: `ios-sourcepackages-v3-${{ runner.os }}-${{ steps.simulator-toolchain.outputs.runner-arch }}-${{ steps.simulator-toolchain.outputs.xcode-build }}-`
   - **Contents**: `build/SourcePackages`
   - **Policy**: Resolves once. Cache is restored before Package resolution. When lockfiles haven't changed, resolution completes in seconds without network re-cloning.

2. **Layer B — Compiler & Clang Module Cache**:
   - **Contents**: `build/SimulatorDerivedData/ModuleCache.noindex`, `build/SimulatorDerivedData/SDKStatCaches.noindex`
   - **Policy**: Preserves precompiled clang and Swift modules across builds on matching compiler toolchains. Cached as part of DerivedData.

3. **Layer C — DerivedData Build Products (`actions/cache@v6`)**:
   - **Key**: `ios-derived-v7-${{ runner.os }}-${{ steps.simulator-toolchain.outputs.runner-arch }}-${{ steps.simulator-toolchain.outputs.xcode-build }}-iphonesimulator-${{ steps.simulator-toolchain.outputs.simulator-sdk }}-${{ env.CONFIGURATION }}-${{ hashFiles('AI_HLY.xcodeproj/project.pbxproj', 'Package.resolved', 'Config.xcconfig', 'Scripts/CI/stage_modular_headers.py') }}-${{ hashFiles('AI_HLY/**/*.swift') }}`
   - **Restore Keys**:
     - `ios-derived-v7-...-${{ hashFiles('AI_HLY.xcodeproj/project.pbxproj', ...) }}-` (Same toolchain and dependencies, prior Swift build products)
     - `ios-derived-v7-...-` (Same toolchain, compatible fallback)
   - **Contents**: `build/SimulatorDerivedData/Build`, `ModuleCache.noindex`, `SDKStatCaches.noindex`, `CacheMetadata/xcode-build-inputs.json`.
   - **Policy**:
     - If Swift sources and project settings did not change: **EXACT_HIT**. Build completes in seconds, cache save is skipped (`SAVE_SKIPPED`). Zero 1.33GB uploads!
     - If Swift sources changed: **COMPATIBLE_RESTORE**. Restores prior DerivedData, mtimes of unchanged files are restored via `xcode_cache_inputs.py`, Xcode builds *only* the modified files incrementally (~2-3 minutes instead of 18 minutes), and the newly updated DerivedData is saved under the new source hash (`SAVE_CREATED`).

4. **Layer D — Staged Modular Headers (`Scripts/CI/stage_modular_headers.py`)**:
   - Validates output completeness in DerivedData (`Build/Products/${cfg}-iphonesimulator/.../Headers`).
   - If headers are missing in DerivedData (even if a stamp file exists in SourcePackages), it forces re-staging to guarantee build integrity.
   - Computes deterministic input stamps (`.modular_headers_staged`) based on base sources, configurations, and generator scripts. Modifications made during staging do not invalidate the stamp on subsequent checks.
   - Executes `Scripts/Expo/patch-hash-combine.mjs` and verifies return codes.
   - Resigns XCFrameworks on macOS with fail-closed checks.
   - Measures and logs actual elapsed time using high-resolution performance counters.

5. **Layer E — Verified Test Evidence Ledger (`TestDependencyLedger`)**:
   - Unchanged tests with valid dependency hashes are reused as `REUSED_VERIFIED_PASS`.
   - Affected tests identified by `plan_affected_validation.py` are executed fresh via `-only-testing`.

---

## 2. Simulator Fixture Staging (`stage_simulator_fixtures.py`)

- **Strict Fail-Closed on Mandatory Steps**:
  - Simulator boot / bootstatus check must succeed; fails with `BOOT_FAILED` (exit code 1) on failure/timeout.
  - Target app installation must succeed; fails with `INSTALL_FAILED` (exit code 1) if simctl install fails.
  - Target app container resolution (`com.itorah.chavrusachat`) must succeed; fails with `CONTAINER_NOT_FOUND` (exit code 1) if container cannot be resolved.
  - Essential fixture staging must find and copy fixtures into `<app_container>/Documents`; fails with `FIXTURES_MISSING` (exit code 1) if 0 fixtures are staged.
- **Graceful Skip for Optional System Apps**:
  - `com.apple.DocumentsApp` container lookup is bounded by a strict 5-second timeout.
  - In headless CI runners, unbooted system app containers are unprovisioned at boot. If `DocumentsApp` lookup times out or returns non-zero, it is logged and safely skipped, returning `SUCCESS` (exit code 0) without hanging the runner.

---

## 3. Cache Save Policy — Skipping Redundant Saves

GitHub Actions caches are immutable: attempting to overwrite an existing key fails with a cache reservation conflict. Furthermore, re-compressing and uploading 1.3+ GB tarballs wastes several minutes of runner time and consumes cache quota.

**Rule**:
- Save steps are guarded with `if: steps.<step-id>-cache.outputs.cache-hit != 'true'`.
- On an **EXACT_HIT**, the existing cache is used as-is; cache save is skipped entirely (`SAVE_SKIPPED`).
- On a **COMPATIBLE_RESTORE** or **MISS**, build and test artifacts are generated, and the updated cache is saved under the new key (`SAVE_CREATED`).

---

## 4. How to Add a Test Without Breaking the Cache

1. Add your test method to the appropriate test target (e.g. `AI_HLYTests` or `AI_HLYUITests`).
2. If your test validates a specific runtime tool, provider, or subsystem:
   - Check `Scripts/CI/affected-validation-map.json`.
   - Ensure the source file mapping includes your test target if you want affected-path triggers to run your test automatically.
3. Do NOT modify `AI_HLY.xcodeproj/project.pbxproj` build settings or deployment targets unless required.
4. Adding test files within existing targets does not invalidate SPM or DerivedData dependencies unless project structure changes.

---

## 5. What to Do When Local Tests Pass But CI Fails

1. **Check the Performance & Diagnostic Summary**:
   - Look at the step summary in GitHub Actions generated by `generate_performance_report.py`.
   - Check `ci-performance-report.json` in the run artifacts.
2. **Inspect Simulator Logs & Failures**:
   - Download `AI_Hanlin-iOS26-simulator-smoke-logs`.
   - Extract `SimulatorBuildResult.xcresult` or view `xcodebuild-test.log`.
3. **Verify Simulator Container / Permission State**:
   - CI runs in an isolated runner with no interactive display or pre-existing system accounts.
   - CloudKit and biometric features run in fail-safe mock/offline mode (`.none`).
   - Simulator staging uses `Scripts/CI/stage_simulator_fixtures.py` with bounded 5s timeouts; check `08-nativescript-files-staging.log` if assets are missing.

---

## 6. Verifying Whether Results Were Reused or Executed

- In GitHub Actions job summaries and test reports:
  - `EXECUTED_PASS`: The test was freshly executed in the iOS Simulator during this run.
  - `REUSED_VERIFIED_PASS`: The test passed in a prior authenticated run, and all source files, dependencies, and fixtures in its dependency graph are 100% unchanged.
  - `FAILED`: The test executed and failed assertions.
  - `NOT_RUN` / `BLOCKED`: The test requires device hardware or external cloud credentials not present in the simulator runner.
- The `generate_performance_report.py` output details:
  - Cache Hit Status (`exact-hit`, `fallback-hit`, `miss`) for SPM and DerivedData.
  - Cache Save Status (`SAVE_SKIPPED` vs `SAVE_CREATED`).
  - Total elapsed seconds for each major phase.
  - Side-by-side Cold vs Warm comparison when baseline reports are supplied.

---

## 7. Cache Invalidation and Safe Bumping

To intentionally invalidate a cache tier across all branches:
1. Bump the version prefix in `.github/workflows/build-ios26-unsigned-ipa.yml`:
   - For SPM: `ios-sourcepackages-v3` -> `ios-sourcepackages-v4`
   - For DerivedData: `ios-derived-v7` -> `ios-derived-v8`
   - For Modular Headers: Stamp schema version prefix in `Scripts/CI/stage_modular_headers.py`.
2. Delete specific cache entries via the GitHub CLI if needed:
   ```bash
   gh cache list --repo davidpovarsky/hanlin-ai
   gh cache delete <cache-id> --repo davidpovarsky/hanlin-ai
   ```

---

## 8. Expected Phase Durations (Target vs Historical Baseline)

| CI Phase / Step | Historical Duration (`39253288354`) | Optimized Target Duration | Optimization Mechanism |
| :--- | :--- | :--- | :--- |
| **Validation Planner** | 13s | ~10–15s | In-memory dependency graph traversal |
| **SPM Resolution & Cache** | 2m 33s | ~15–30s (Exact Hit) | Stable lockfile key, skip save on hit |
| **Modular Header Staging** | 7m 30s | ~0.1s (Stamp Hit) | `.modular_headers_staged` input stamp + completeness check |
| **Build Simulator App** | 17m 48s | ~2–4m (Incremental) | v7 keying (selective save on Swift change, instant hit on no-op) |
| **Simulator Boot & Prep** | 1m 20s | ~20–30s | Direct headless boot |
| **Simulator Fixture Staging** | 7m 34s (Deadlock!) | ~2–5s | Bounded 5s timeout on optional `DocumentsApp` |
| **XCTest Execution** | 14m 10s | ~5–10m | Focused `-only-testing` slices |
| **Diagnostics & Upload** | 4m 12s | ~1m | Scoped log packaging |
| **Cache Save Step** | 1m 45s | 0s (Exact Hit) | `steps.simulator-deriveddata-cache.outputs.cache-hit != 'true'` |
| **TOTAL SIMULATOR JOB** | **63m 36s** | **~15–20m** | **~45 minutes saved per run** |
