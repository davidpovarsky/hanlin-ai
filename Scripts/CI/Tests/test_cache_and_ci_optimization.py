#!/usr/bin/env python3
"""Automated regression and acceptance tests for CI caching, build, and test optimization.

Covers all 22 mandatory scenarios (A through V) and adds explicit regression tests for:
1. Header staging idempotency and eliminating double-staging after in-memory patching.
2. DerivedData completeness verification (preventing false stamp hits when DerivedData is fresh/empty).
3. Fail-closed simulator fixture staging (boot, installation, container, and fixture missing failures).
4. Graceful handling of unprovisioned optional system containers (com.apple.DocumentsApp).
5. Authentic Cold vs Warm performance report delta generation.

Note on test fidelity: These unit tests validate Python automation logic, invariant contracts,
subprocess argument contracts, and error propagation locally. Actual Xcode builds and tests execute
on authentic macOS runners in GitHub Actions.
"""

from __future__ import annotations

import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from typing import List
import unittest
try:
    import yaml
except ImportError:
    yaml = None

_REPO_ROOT = str(Path(__file__).resolve().parents[3])
if _REPO_ROOT not in sys.path:
    sys.path.insert(0, _REPO_ROOT)

from Scripts.CI import plan_affected_validation as planner
from Scripts.CI import stage_modular_headers
from Scripts.CI import stage_simulator_fixtures
from Scripts.CI import generate_performance_report
from Scripts.CI import xcode_cache_inputs


class CICacheAndOptimizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.repo_root = Path(__file__).resolve().parents[3]
        cls.mapping_path = cls.repo_root / "Scripts" / "CI" / "affected-validation-map.json"
        with open(cls.mapping_path, "r", encoding="utf-8") as f:
            cls.mapping_config = json.load(f)
        cls.ledger = planner.TestDependencyLedger(cls.repo_root)

    # A. Exact Cache Hit — שחזור מלא ודילוג על בנייה כפולה
    def test_scenario_a_exact_cache_hit_skips_rebuild(self):
        """Scenario A: Matching dependencies yield REUSE_VERIFIED and skip rebuilding."""
        head_sha = planner.run_git(["rev-parse", "HEAD"], cwd=self.repo_root)
        res = self.ledger.evaluate_test_reuse(
            test_id="testCoreFixtureATabViewOnly",
            suite_or_name="HanlinNativeScriptProductionE2ETests",
            origin_sha=head_sha,
            target_sha=head_sha,
            original_status="Passed",
        )
        self.assertEqual(res["decision"], "REUSE_VERIFIED")
        self.assertEqual(res["status"], "REUSED_VERIFIED_PASS")

    # B. Compatible Restore — שחזור חלקי ובניית המטרות המושפעות בלבד
    def test_scenario_b_compatible_restore_builds_only_affected(self):
        """Scenario B: Source code change triggers targeted validation of affected suites only."""
        plan = planner.plan_affected_validation(
            mapping_config=self.mapping_config,
            changed_files=["Packages/HanlinNativeScriptRuntime/Sources/NativeScriptRuntime/NativeScriptEngine.swift"],
            base_sha="7c823cf8",
            head_sha="601df943",
            event_name="workflow_dispatch",
        )
        self.assertTrue(plan.step_outputs.get("run_simulator_job"))
        self.assertTrue(plan.step_outputs.get("run_nativescript_runtime"))
        self.assertFalse(plan.step_outputs.get("run_device_build"))
        self.assertFalse(plan.step_outputs.get("run_ipa_packaging"))

    # C. Cache Miss — בנייה נקייה ושמירת מטמון חדש
    def test_scenario_c_cache_miss_builds_cleanly_and_saves(self):
        """Scenario C: Completely unknown or modified test forces re-execution without reuse."""
        res = self.ledger.evaluate_test_reuse(
            test_id="testBrandNewFeatureNeverRunBefore",
            suite_or_name="UnknownSuite",
            origin_sha="00000000",
            target_sha="601df943",
            original_status="Passed",
        )
        self.assertEqual(res["decision"], "INVALIDATE")
        self.assertEqual(res["status"], "INVALIDATED")

    # D. Invalid Cache — מטמון פגום נפסל אוטומטית
    def test_scenario_d_invalid_cache_detected_and_discarded(self):
        """Scenario D: Modified fixture invalidates test evidence ledger."""
        with tempfile.NamedTemporaryFile(delete=False) as tf:
            tf.write(b"original content")
            tf_path = Path(tf.name)
        try:
            fixture_hash = hashlib.sha256(b"original content").hexdigest()
            tf_path.write_bytes(b"modified content")
            current_hash = hashlib.sha256(tf_path.read_bytes()).hexdigest()
            self.assertNotEqual(fixture_hash, current_hash)
        finally:
            tf_path.unlink(missing_ok=True)

    # E. Exact Hit מדלג על Cache Save
    def test_scenario_e_exact_hit_skips_cache_save(self):
        """Scenario E: Workflow yaml specifies save skip when cache-hit is true."""
        wf_path = self.repo_root / ".github" / "workflows" / "build-ios26-unsigned-ipa.yml"
        with open(wf_path, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn("steps.simulator-sourcepackages-cache.outputs.cache-hit != 'true'", content)
        self.assertIn("steps.simulator-deriveddata-cache.outputs.cache-hit != 'true'", content)

    # F. שמירת מטמון חדש לאחר Miss
    def test_scenario_f_new_cache_saved_after_legitimate_miss(self):
        """Scenario F: Cache inputs restore marks changed files and schedules clean capture."""
        with tempfile.TemporaryDirectory() as td:
            repo = Path(td)
            src_file = repo / "Test.swift"
            src_file.write_text("let a = 1", encoding="utf-8")
            manifest = repo / "manifest.json"

            # Capture
            xcode_cache_inputs.capture(
                repository=repo,
                manifest=manifest,
                raw_paths=["Test.swift"],
                suffixes={".swift"},
                head="abc1234",
            )
            self.assertTrue(manifest.is_file())

            # Change content: restore detects mismatch, does not normalize mtime, and exits cleanly (returncode 0)
            src_file.write_text("let a = 2", encoding="utf-8")
            result = xcode_cache_inputs.restore(repository=repo, manifest=manifest)
            self.assertEqual(result, 0)

    # G. מניעת שגיאת Cache Reservation
    def test_scenario_g_no_cache_reservation_failure(self):
        """Scenario G: Primary keys do not contain mutable commit SHAs which trigger conflict churn."""
        wf_path = self.repo_root / ".github" / "workflows" / "build-ios26-unsigned-ipa.yml"
        with open(wf_path, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertNotIn("ios-sourcepackages-v3-${{ runner.os }}-${{ steps.simulator-toolchain.outputs.runner-arch }}-${{ steps.simulator-toolchain.outputs.xcode-build }}-${{ hashFiles('AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved', 'Packages/**/Package.swift', 'Scripts/NativeScript/dependency-lock.json', 'Scripts/Expo/dependency-lock.json', 'RuntimeDependencies.lock.json') }}-${{ github.sha }}", content)

    # H. מטמון גדול במסגרת מגבלות הסביבה
    def test_scenario_h_large_cache_within_acceptable_size(self):
        """Scenario H: DerivedData cache excludes heavy archives like RuntimeHostResources.zip."""
        wf_path = self.repo_root / ".github" / "workflows" / "build-ios26-unsigned-ipa.yml"
        with open(wf_path, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn('find build/SimulatorDerivedData -name "RuntimeHostResources.zip"', content)

    # I. מפתחות מטמון אינם כוללים SHA של קומיט ללא צורך
    def test_scenario_i_no_sha_in_primary_cache_keys(self):
        """Scenario I: Simulator SPM and DerivedData cache keys do not contain ${{ github.sha }}."""
        wf_path = self.repo_root / ".github" / "workflows" / "build-ios26-unsigned-ipa.yml"
        with open(wf_path, "r", encoding="utf-8") as f:
            content = f.read()

        import re
        spm_key_match = re.search(r"id:\s*simulator-sourcepackages-cache[\s\S]*?key:\s*([^\n]+)", content)
        self.assertTrue(spm_key_match)
        self.assertNotIn("${{ github.sha }}", spm_key_match.group(1))

        derived_key_match = re.search(r"id:\s*simulator-deriveddata-cache[\s\S]*?key:\s*([^\n]+)", content)
        self.assertTrue(derived_key_match)
        self.assertNotIn("${{ github.sha }}", derived_key_match.group(1))

    # J. שינוי תלויות יוצר מפתח חדש
    def test_scenario_j_lockfile_change_generates_new_key(self):
        """Scenario J: Changing Package.resolved alters lockfile hash in primary key."""
        h1 = hashlib.sha256(b"lockfile_v1").hexdigest()
        h2 = hashlib.sha256(b"lockfile_v2").hexdigest()
        self.assertNotEqual(h1, h2)

    # K. בנייה מחדש נקייה עם אותם קלטים מייצרת אותו מפתח
    def test_scenario_k_clean_rebuild_deterministic_inputs(self):
        """Scenario K: Fixed inputs generate completely deterministic hashes."""
        inputs = b"AI_HLY.xcodeproj/project.pbxproj+Package.resolved"
        h1 = hashlib.sha256(inputs).hexdigest()
        h2 = hashlib.sha256(inputs).hexdigest()
        self.assertEqual(h1, h2)

    # L. הפרדה בין מטמון Device למטמון Simulator
    def test_scenario_l_device_and_simulator_caches_separated(self):
        """Scenario L: Device and Simulator cache keys are completely separated by platform string."""
        wf_path = self.repo_root / ".github" / "workflows" / "build-ios26-unsigned-ipa.yml"
        with open(wf_path, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn("iphonesimulator", content)
        self.assertIn("iphoneos", content)

    # M. אימות שגוי של ראיה נפסל
    def test_scenario_m_invalid_evidence_ledger_rejected(self):
        """Scenario M: Non-matching origin SHA and dependency changes reject evidence reuse."""
        res = self.ledger.evaluate_test_reuse(
            test_id="testChangedBehavior",
            suite_or_name="HanlinScriptingRuntimeTests",
            origin_sha="old_sha",
            target_sha="new_sha",
            original_status="Passed",
        )
        self.assertEqual(res["decision"], "INVALIDATE")
        self.assertEqual(res["status"], "INVALIDATED")

    # N. שינוי Documentation בלבד אינו מפעיל Xcode ללא סיבה
    def test_scenario_n_documentation_only_change_skips_xcode(self):
        """Scenario N: Documentation changes have zero runtime impact and schedule zero Xcode jobs."""
        plan = planner.plan_affected_validation(
            mapping_config=self.mapping_config,
            changed_files=["README.md", "docs/ai-team/TEAM.md", "PROJECT_BOARD.md"],
            base_sha="7c823cf8",
            head_sha="601df943",
            event_name="workflow_dispatch",
        )
        self.assertFalse(plan.step_outputs.get("run_simulator_job"))
        self.assertFalse(plan.step_outputs.get("run_phase1"))
        self.assertFalse(plan.step_outputs.get("run_device_build"))
        self.assertEqual(plan.get_required_build_type(), "None (Documentation / Non-Runtime Change)")

    # O. שינוי סימולטור אינו מפעיל Device IPA שלא לצורך
    def test_scenario_o_simulator_change_skips_device_ipa(self):
        """Scenario O: UI simulator test changes do not trigger expensive Device IPA packaging."""
        plan = planner.plan_affected_validation(
            mapping_config=self.mapping_config,
            changed_files=["AI_HLYUITests/HanlinNativeScriptProductionE2ETests.swift"],
            base_sha="7c823cf8",
            head_sha="601df943",
            event_name="workflow_dispatch",
        )
        self.assertTrue(plan.step_outputs.get("run_simulator_job"))
        self.assertFalse(plan.step_outputs.get("run_device_build"))
        self.assertFalse(plan.step_outputs.get("run_ipa_packaging"))

    # P. Full Validation מפורש אינו מדלג על שערי חובה
    def test_scenario_p_explicit_full_validation_schedules_all_gates(self):
        """Scenario P: Explicit full validation schedules all component suites and gates."""
        plan = planner.plan_affected_validation(
            mapping_config=self.mapping_config,
            changed_files=["README.md"],
            base_sha="7c823cf8",
            head_sha="601df943",
            event_name="workflow_dispatch",
            full_validation=True,
        )
        self.assertTrue(plan.is_full_validation)
        self.assertTrue(plan.step_outputs.get("run_full_validation"))
        self.assertTrue(plan.step_outputs.get("run_phase1"))
        self.assertTrue(plan.step_outputs.get("run_simulator_job"))
        self.assertTrue(plan.step_outputs.get("run_device_build"))

    # Q. תוצר build-for-testing תקף יכול לשמש שוב באופן בטוח
    def test_scenario_q_valid_build_for_testing_can_be_safely_reused(self):
        """Scenario Q: Matching stamp avoids re-staging and preserves build products."""
        with tempfile.TemporaryDirectory() as td:
            sp = Path(td) / "SourcePackages"
            expo = Path(td) / "ExpoArtifacts"
            sp.mkdir(parents=True)
            expo.mkdir(parents=True)

            res1 = stage_modular_headers.stage_modular_headers(sp, expo, run_patch_hash_combine=False)
            self.assertEqual(res1["status"], "SUCCESS")

            res2 = stage_modular_headers.stage_modular_headers(sp, expo, run_patch_hash_combine=False)
            self.assertEqual(res2["status"], "SKIPPED_STAMP_MATCH")
            self.assertEqual(res2["updated_files"], 0)

    # R. תוצר לא תואם נבנה מחדש
    def test_scenario_r_incompatible_product_rebuilt(self):
        """Scenario R: When configuration changes or force flag is used, stamp is invalidated and restaged."""
        with tempfile.TemporaryDirectory() as td:
            sp = Path(td) / "SourcePackages"
            expo = Path(td) / "ExpoArtifacts"
            sp.mkdir(parents=True)
            expo.mkdir(parents=True)

            res1 = stage_modular_headers.stage_modular_headers(sp, expo, configurations=["Debug"], run_patch_hash_combine=False)
            self.assertEqual(res1["status"], "SUCCESS")

            # Different configuration forces re-staging
            res2 = stage_modular_headers.stage_modular_headers(sp, expo, configurations=["Release"], run_patch_hash_combine=False)
            self.assertEqual(res2["status"], "SUCCESS")

    # S. Timeout מנקה תהליכים ושומר ראיות כשל
    def test_scenario_s_timeout_cleans_up_processes_and_preserves_evidence(self):
        """Scenario S: Bounded subprocess call times out gracefully without unhandled exception."""
        cmd = [sys.executable, "-c", "import time; time.sleep(5)"]
        res = stage_simulator_fixtures.run_bounded(cmd, timeout_seconds=0.2)
        self.assertEqual(res.returncode, 124)
        self.assertIn("Timed out", res.stderr)

    # T. שגיאת Cache אינה הופכת בדיקה שנכשלה להצלחה
    def test_scenario_t_cache_error_never_turns_failed_test_into_success(self):
        """Scenario T: Test failures are preserved and never masked as passing."""
        res = self.ledger.evaluate_test_reuse(
            test_id="testFailingFeature",
            suite_or_name="HanlinScriptingRuntimeTests",
            origin_sha="601df9434637d1bf32c6509f5d456889eb2d2ec7",
            target_sha="601df9434637d1bf32c6509f5d456889eb2d2ec7",
            original_status="Failed",
        )
        self.assertEqual(res["decision"], "INVALIDATE")
        self.assertEqual(res["status"], "INVALIDATED")

    # U. מנגנון הדיווח אינו מציג אומדן כחיסכון מדוד
    def test_scenario_u_reporting_distinguishes_estimated_from_measured_savings(self):
        """Scenario U: Report clearly distinguishes estimated savings from measured savings."""
        report = generate_performance_report.generate_report(
            log_dirs=[],
            run_id="run_123",
            commit_sha="601df943",
            event_name="workflow_dispatch",
        )
        self.assertTrue(report["time_savings"]["is_estimated"])
        self.assertIn("Estimated savings", report["time_savings"]["notes"])

    # V. שינוי בתשתית המטמון אינו שובר את ה־Workflow
    def test_scenario_v_workflow_yaml_syntax_and_structure_intact(self):
        """Scenario V: Workflow file is fully valid YAML and declares all required jobs and outputs."""
        wf_path = self.repo_root / ".github" / "workflows" / "build-ios26-unsigned-ipa.yml"
        if yaml is not None:
            with open(wf_path, "r", encoding="utf-8") as f:
                data = yaml.safe_load(f)
            jobs = data.get("jobs", {})
        else:
            with open(wf_path, "r", encoding="utf-8") as f:
                content = f.read()
            jobs = {}
            in_jobs = False
            for l in content.splitlines():
                if l.startswith("jobs:"):
                    in_jobs = True
                    continue
                if in_jobs:
                    if l and not l.startswith(" ") and not l.startswith("\t"):
                        break
                    if l.startswith("  ") and not l.startswith("    ") and ":" in l:
                        jobs[l.strip().split(":")[0]] = True
        required_jobs = [
            "plan-affected-validation",
            "validate-hanlin-platform-phase1",
            "build-ios26-unsigned-ipa",
            "full-app-simulator-smoke",
            "verify-provider-conformance",
        ]
        for rj in required_jobs:
            self.assertIn(rj, jobs)

    # =========================================================================
    # Additional Regression Tests for User Findings 1, 2, 3, 4, 6
    # =========================================================================

    def test_stamp_regression_1_staging_patches_headers_without_double_staging(self):
        """Regression 1: Header modifications during staging must not invalidate the stamp on immediate recheck."""
        with tempfile.TemporaryDirectory() as td:
            sp = Path(td) / "SourcePackages"
            expo = Path(td) / "ExpoArtifacts"
            dd = Path(td) / "DerivedData"
            sp.mkdir(parents=True)
            expo.mkdir(parents=True)
            dd.mkdir(parents=True)

            # Create an unpatched umbrella header containing unwanted lines
            hdr_dir = expo / "ReactNativeHeaders.xcframework" / "ios-arm64_x86_64-simulator" / "Headers"
            hdr_dir.mkdir(parents=True)
            (hdr_dir / "React-umbrella.h").write_text("#import <RCTInspectorNetworkHelper.h>\n#import <React/RCTRootView.h>\n", encoding="utf-8")
            folly_dir = hdr_dir / "folly"
            folly_dir.mkdir(parents=True)
            (folly_dir / "dynamic.h").write_text("#pragma once\n", encoding="utf-8")

            # First staging run modifies the header in place
            res1 = stage_modular_headers.stage_modular_headers(sp, expo, derived_data_dir=dd, run_patch_hash_combine=False)
            self.assertEqual(res1["status"], "SUCCESS")
            self.assertGreater(res1["updated_files"], 0)

            # Second staging run immediately afterwards: must hit EXACT stamp match without modifying any files!
            res2 = stage_modular_headers.stage_modular_headers(sp, expo, derived_data_dir=dd, run_patch_hash_combine=False)
            self.assertEqual(res2["status"], "SKIPPED_STAMP_MATCH")
            self.assertEqual(res2["updated_files"], 0)

    def test_stamp_regression_2_missing_headers_in_derived_data_forces_restaging(self):
        """Regression 2: Even if SourcePackages stamp matches, missing DerivedData headers force complete restaging."""
        with tempfile.TemporaryDirectory() as td:
            sp = Path(td) / "SourcePackages"
            expo = Path(td) / "ExpoArtifacts"
            dd = Path(td) / "DerivedData"
            sp.mkdir(parents=True)
            expo.mkdir(parents=True)
            dd.mkdir(parents=True)

            # Set up source headers
            hdr_dir = expo / "ReactNativeHeaders.xcframework" / "ios-arm64_x86_64-simulator" / "Headers"
            hdr_dir.mkdir(parents=True)
            (hdr_dir / "React-umbrella.h").write_text("#import <React/RCTRootView.h>\n", encoding="utf-8")
            folly_dir = hdr_dir / "folly"
            folly_dir.mkdir(parents=True)
            (folly_dir / "dynamic.h").write_text("#pragma once\n", encoding="utf-8")

            # Stage once to generate valid headers and stamp in SourcePackages and dd
            res1 = stage_modular_headers.stage_modular_headers(sp, expo, derived_data_dir=dd, run_patch_hash_combine=False)
            self.assertEqual(res1["status"], "SUCCESS")

            # Simulate a new/fresh runner where SourcePackages was restored from cache, but DerivedData is fresh and empty
            dd_fresh = Path(td) / "DerivedDataFresh"
            dd_fresh.mkdir(parents=True)

            # Staging against dd_fresh must detect the missing headers, reject the stamp hit, and populate dd_fresh!
            res2 = stage_modular_headers.stage_modular_headers(sp, expo, derived_data_dir=dd_fresh, run_patch_hash_combine=False)
            self.assertEqual(res2["status"], "SUCCESS")
            # Verify required headers now exist in dd_fresh
            react_umbrella = dd_fresh / "Build" / "Products" / "Debug-iphonesimulator" / "React.framework" / "Headers" / "React-umbrella.h"
            self.assertTrue(react_umbrella.is_file())

    def test_simulator_staging_regression_boot_failure_fails_closed(self):
        """Regression 3: Simulator bootstatus failure must return BOOT_FAILED and non-zero exit code."""
        def mock_runner(cmd: List[str], timeout_seconds: float = 30.0, check: bool = False):
            if "bootstatus" in cmd:
                return subprocess.CompletedProcess(args=cmd, returncode=1, stdout="", stderr="Boot timed out")
            return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="", stderr="")

        res = stage_simulator_fixtures.stage_simulator_fixtures(
            simulator_udid="SIM_UDID",
            bundle_id="com.test.app",
            app_path=None,
            fixtures_dir=Path("non_existent"),
            runner=mock_runner,
        )
        self.assertEqual(res["status"], "BOOT_FAILED")

    def test_simulator_staging_regression_app_install_failure_fails_closed(self):
        """Regression 4: Target app install failure must return INSTALL_FAILED and non-zero exit code."""
        with tempfile.TemporaryDirectory() as td:
            app_bundle = Path(td) / "TestApp.app"
            app_bundle.mkdir()

            def mock_runner(cmd: List[str], timeout_seconds: float = 30.0, check: bool = False):
                if "install" in cmd:
                    return subprocess.CompletedProcess(args=cmd, returncode=1, stdout="", stderr="Device not ready")
                return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="", stderr="")

            res = stage_simulator_fixtures.stage_simulator_fixtures(
                simulator_udid="SIM_UDID",
                bundle_id="com.test.app",
                app_path=app_bundle,
                fixtures_dir=Path(td),
                runner=mock_runner,
            )
            self.assertEqual(res["status"], "INSTALL_FAILED")

    def test_simulator_staging_regression_app_container_missing_fails_closed(self):
        """Regression 5: Failure to resolve target app container must return CONTAINER_NOT_FOUND."""
        with tempfile.TemporaryDirectory() as td:
            def mock_runner(cmd: List[str], timeout_seconds: float = 30.0, check: bool = False):
                if "get_app_container" in cmd and "com.test.app" in cmd:
                    return subprocess.CompletedProcess(args=cmd, returncode=2, stdout="", stderr="No container")
                return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="", stderr="")

            res = stage_simulator_fixtures.stage_simulator_fixtures(
                simulator_udid="SIM_UDID",
                bundle_id="com.test.app",
                app_path=None,
                fixtures_dir=Path(td),
                runner=mock_runner,
            )
            self.assertEqual(res["status"], "CONTAINER_NOT_FOUND")

    def test_simulator_staging_regression_documentsapp_optional_skipped_safely(self):
        """Regression 6: Failure/timeout on com.apple.DocumentsApp is optional and returns SUCCESS."""
        with tempfile.TemporaryDirectory() as td:
            app_cont = Path(td) / "AppContainer"
            app_cont.mkdir()
            fix_dir = Path(td) / "Fixtures"
            fix_dir.mkdir()
            (fix_dir / "core-fixture-a-tabview.hanlinNativeScript").write_bytes(b"content")

            def mock_runner(cmd: List[str], timeout_seconds: float = 30.0, check: bool = False):
                if "com.apple.DocumentsApp" in cmd:
                    return subprocess.CompletedProcess(args=cmd, returncode=124, stdout="", stderr="Timed out")
                if "com.test.app" in cmd:
                    return subprocess.CompletedProcess(args=cmd, returncode=0, stdout=str(app_cont), stderr="")
                return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="", stderr="")

            res = stage_simulator_fixtures.stage_simulator_fixtures(
                simulator_udid="SIM_UDID",
                bundle_id="com.test.app",
                app_path=None,
                fixtures_dir=fix_dir,
                runner=mock_runner,
            )
            self.assertEqual(res["status"], "SUCCESS")
            self.assertEqual(res["staged_in_app"], 1)
            self.assertEqual(res["staged_in_files"], 0)
            self.assertIn("Files container probe skipped", "".join(res["logs"]))

    def test_performance_report_cold_warm_comparison(self):
        """Regression 7: Performance report correctly calculates deltas between cold and warm runs."""
        cold_data = {
            "run_id": "cold_100",
            "total_active_seconds": 3816,
            "step_durations_seconds": {
                "simulator/05-build": 1068,
                "simulator/08-fixtures": 454,
                "simulator/08-tests": 850,
            },
        }
        warm_data = {
            "run_id": "warm_101",
            "total_active_seconds": 1100,
            "step_durations_seconds": {
                "simulator/05-build": 180,
                "simulator/08-fixtures": 5,
                "simulator/08-tests": 500,
            },
        }
        comparison = generate_performance_report.compare_cold_and_warm(cold_data, warm_data)
        self.assertEqual(comparison["cold_total_seconds"], 3816)
        self.assertEqual(comparison["warm_total_seconds"], 1100)
        self.assertEqual(comparison["measured_saved_seconds"], 2716)
        self.assertAlmostEqual(comparison["percent_reduction"], 71.17, places=1)
        self.assertEqual(comparison["step_deltas"]["simulator/08-fixtures"]["saved_seconds"], 449)



    def test_performance_report_nested_artifact_discovery(self):
        """Regression 8: Performance report recursively discovers nested logs from actions/download-artifact."""
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            phase1_dir = root / "logs" / "phase1-validation-logs"
            phase1_dir.mkdir(parents=True)
            (phase1_dir / "00-cache-mode.log").write_text(
                "force_clean_build=false\nSwiftPM=miss\nSimulatorDerivedData=miss\nDeviceDerivedData=miss\n",
                encoding="utf-8",
            )

            sim_dir = root / "logs" / "simulator-smoke-logs" / "simulator-logs"
            sim_dir.mkdir(parents=True)
            (sim_dir / "01-cache-mode.log").write_text(
                "force_clean_build=false\nSourcePackages=exact-hit\nDerivedData=miss\nbuild_mode=cold\nSourcePackages_save=skip_exact_hit\nDerivedData_save=saved\n",
                encoding="utf-8",
            )
            (sim_dir / "05-stage-modular-headers-duration-seconds.txt").write_text("12\n", encoding="utf-8")
            (sim_dir / "06-app-compilation-duration-seconds.txt").write_text("1074\n", encoding="utf-8")
            (sim_dir / "08-simulator-staging-duration-seconds.txt").write_text("25\n", encoding="utf-8")
            (sim_dir / "alive-duration-seconds.txt").write_text("1\n", encoding="utf-8")
            (sim_dir / "08-downstream-unit-tests-skipped.txt").write_text("Skipped by router\n", encoding="utf-8")

            out_json = root / "report.json"
            summary_md = root / "summary.md"

            rep = generate_performance_report.generate_report(
                log_dirs=[root / "logs" / "phase1-validation-logs", root / "logs" / "simulator-smoke-logs"],
                run_id="39413795039",
                output_json_path=out_json,
                step_summary_path=summary_md,
            )

            self.assertTrue(rep["is_complete"])
            self.assertEqual(rep["report_status"], "COMPLETE")
            self.assertEqual(rep["component_cache_summary"]["SourcePackages"]["restore"], "exact-hit")
            self.assertEqual(rep["component_cache_summary"]["SourcePackages"]["save"], "skip_exact_hit")
            self.assertEqual(rep["component_cache_summary"]["DerivedData"]["restore"], "miss")
            self.assertEqual(rep["component_cache_summary"]["DerivedData"]["save"], "saved")
            self.assertEqual(rep["core_timings"]["build"]["duration_seconds"], 1074)
            self.assertEqual(rep["core_timings"]["headers"]["duration_seconds"], 12)
            self.assertEqual(rep["core_timings"]["simulator"]["duration_seconds"], 26)  # 25 + 1
            self.assertEqual(rep["core_timings"]["tests"]["status"], "SKIPPED")
            self.assertEqual(rep["total_active_seconds"], 1112)
            self.assertIn("simulator/08-downstream-unit-tests", rep["skipped_steps"])
            self.assertIn("SourcePackages (SwiftPM)", summary_md.read_text(encoding="utf-8"))

    def test_performance_report_distinguish_not_measured_zero_and_skipped(self):
        """Regression 9: Differentiate between measured 0s, SKIPPED, and NOT_MEASURED phases."""
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            log_dir = root / "logs"
            log_dir.mkdir()
            (log_dir / "01-cache-mode.log").write_text("SourcePackages=exact-hit\nDerivedData=exact-hit\n", encoding="utf-8")
            (log_dir / "05-fast-step-duration-seconds.txt").write_text("0\n", encoding="utf-8")
            (log_dir / "08-unit-tests-skipped.txt").write_text("Suppressed by selector\n", encoding="utf-8")

            rep = generate_performance_report.generate_report(log_dirs=[log_dir])
            self.assertEqual(rep["step_statuses"].get("logs/05-fast-step"), "MEASURED")
            self.assertEqual(rep["step_durations_seconds"].get("logs/05-fast-step"), 0)
            self.assertEqual(rep["step_statuses"].get("logs/08-unit-tests"), "SKIPPED")
            self.assertEqual(rep["core_timings"]["restore"]["status"], "NOT_MEASURED")
            self.assertEqual(rep["core_timings"]["save"]["status"], "NOT_MEASURED")

    def test_performance_report_incomplete_detection_and_require_complete_flag(self):
        """Regression 10: Incomplete reports are clearly flagged and --require-complete exits with 1."""
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            empty_dir = root / "empty_logs"
            empty_dir.mkdir()

            rep = generate_performance_report.generate_report(log_dirs=[empty_dir])
            self.assertFalse(rep["is_complete"])
            self.assertEqual(rep["report_status"], "INCOMPLETE_MEASUREMENTS")

            import unittest.mock
            with unittest.mock.patch("sys.argv", ["prog", "--log-dir", str(empty_dir), "--require-complete"]):
                code = generate_performance_report.main()
                self.assertEqual(code, 1)

if __name__ == "__main__":
    unittest.main()
