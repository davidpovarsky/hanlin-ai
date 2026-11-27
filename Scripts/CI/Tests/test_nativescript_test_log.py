from Scripts.CI import verify_nativescript_test_log as checks
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[3]


class NativeScriptTestLogTests(unittest.TestCase):
    def workflow_run(self):
        workflow = yaml.safe_load((ROOT / ".github/workflows/build-ios26-unsigned-ipa.yml").read_text(encoding="utf-8"))
        job = next(j for j in workflow["jobs"].values() if j.get("name") == "Launch full app on iPad Simulator")
        return next(s["run"] for s in job["steps"] if s.get("name") == "Run simulator test suite")

    def assert_cohort_log_check(self, run):
        start = run.index('if [ "$cohort_test_status" -eq 0 ]; then')
        end = run.index('printf \'%s\\n\' "$cohort_test_status"', start)
        check = run[start:end]
        self.assertIn("if ! python3 Scripts/CI/verify_nativescript_test_log.py", check)
        self.assertIn('--log "$LOG_DIR/$cohort_native_log"', check)
        self.assertIn('--selectors "$cohort_selectors"', check)
        self.assertIn("cohort_test_status=65", check)
        self.assertIn('if [ "$cohort_test_status" -ne 0 ]; then nativescript_e2e_status="$cohort_test_status"; fi', run[end:])
        return check

    def log(self, markers):
        return "HANLIN_NS_INITIALIZED_EXTERNAL_ROOT path=/sim/App/Library/Application Support/Packages\n" + "\n".join(markers)

    def test_shared_core_does_not_require_an_unselected_swiftui_fixture(self):
        log = self.log([*checks.CORE_MARKERS, "HANLIN_NS_PRODUCTION_SHUTDOWN_OK"])
        self.assertEqual(checks.missing_evidence(log, checks.CORE), [])
        self.assertIn(checks.SWIFTUI_MARKERS[0], checks.missing_evidence(log, checks.SWIFTUI))

    def test_swiftui_lifecycle_keeps_all_original_core_and_swiftui_requirements(self):
        markers = [*checks.CORE_MARKERS, *checks.SWIFTUI_MARKERS, "HANLIN_NS_PRODUCTION_SHUTDOWN_OK"]
        self.assertEqual(checks.missing_evidence(self.log(markers), checks.SWIFTUI + "()"), [])
        for removed in markers:
            with self.subTest(marker=removed):
                self.assertIn(removed, checks.missing_evidence(self.log([m for m in markers if m != removed]), checks.SWIFTUI))

    def test_exact_tab_bar_does_not_require_an_unselected_core_fixture(self):
        self.assertEqual(checks.missing_evidence(self.log([]), checks.SUITE + "/testDirectUIKitTabBarBridge"), [])

    def test_rejected_packages_do_not_claim_to_initialize_a_native_vm(self):
        self.assertEqual(checks.required_markers(",".join(checks.REJECTIONS)), [])

    def test_whole_suite_and_mixed_selectors_retain_full_evidence(self):
        for selector in ["", "AI_HLYUITests", checks.SUITE, "Other/Case," + checks.SUITE,
                         checks.PERFORMANCE + "/testOriginalPerformance"]:
            with self.subTest(selector=selector):
                self.assertEqual(checks.required_markers(selector), checks.required_markers(checks.SWIFTUI))

    def test_similar_names_do_not_select_native_or_swiftui_cases(self):
        for selector in [checks.SUITE + "Extra", checks.SWIFTUI + "Extra", "Other/" + checks.SWIFTUI]:
            self.assertNotIn(checks.SWIFTUI_MARKERS[0], checks.required_markers(selector))

    def test_a_runtime_initialization_marker_cannot_hide_a_wrong_external_root(self):
        self.assertIn("external root under Library/Application Support", checks.missing_evidence(
            "HANLIN_NS_INITIALIZED_EXTERNAL_ROOT path=/tmp/untrusted", checks.CORE))

    def test_combined_release_baseline_requires_only_its_selected_native_fixtures(self):
        selectors = ",".join(["AI_HLYUITests/HanlinExpoProductionE2ETests/testProductionExpoSwiftUIProbeEndToEnd",
            checks.CORE, checks.SUITE + "/testDirectUIKitTabBarBridge",
            "AI_HLYUITests/HanlinMorphComposerUITests/testDismissModelPickerKeepsSelectedModelAndDraft"])
        self.assertEqual(checks.required_markers(selectors), checks.required_markers(checks.CORE))

    def test_actual_workflow_checks_the_original_log_with_the_exact_selection(self):
        run = self.workflow_run()
        self.assert_cohort_log_check(run)
        self.assertIn('cohort_native_log="08-nativescript-production.log"', run)
        self.assertIn('cohort_native_log="08-$cohort_id-production.log"', run)
        self.assertIn('"$log_window_minutes" "$cohort_native_log" "$cohort_capture_status"', run)

    def test_each_cohort_uses_its_own_log_and_selection_and_retains_failure(self):
        check = self.assert_cohort_log_check(self.workflow_run())
        shell = "bash"
        if os.name == "nt":
            git = Path(shutil.which("git") or "")
            shell = str(git.parent.parent / "bin/bash.exe")
            self.assertTrue(Path(shell).is_file(), "Native Git Bash is required for this Windows check")
        with tempfile.TemporaryDirectory() as folder:
            logs = Path(folder)
            complete = self.log([*checks.CORE_MARKERS, "HANLIN_NS_PRODUCTION_SHUTDOWN_OK"])
            cases = [
                ("08-nativescript-production.log", checks.CORE, complete, 0, 0),
                ("08-compact-production.log", checks.SUITE + "/testDirectUIKitTabBarBridge", self.log([]), 0, 0),
                ("08-nativescript-production.log", checks.CORE, self.log([]), 0, 65),
                ("unreadable-prior-failure.log", checks.CORE, None, 65, 65),
            ]
            for filename, selectors, contents, original_status, expected in cases:
                with self.subTest(filename=filename, selectors=selectors, original_status=original_status):
                    if contents is not None:
                        (logs / filename).write_text(contents, encoding="utf-8")
                    result = subprocess.run(
                        [shell, "-c", 'set -eu\n' + check + '\nprintf "\\nCOHORT_STATUS=%s\\n" "$cohort_test_status"'],
                        cwd=ROOT, env={**os.environ, "LOG_DIR": logs.as_posix(),
                            "cohort_native_log": filename, "cohort_selectors": selectors,
                            "cohort_test_status": str(original_status),
                            # A global full-suite filter must not leak into a compact cohort.
                            "SIMULATOR_UI_FILTER": checks.SWIFTUI},
                        capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout.splitlines()[-1], "COHORT_STATUS=" + str(expected))

    def test_wrong_log_global_selection_or_swallowed_failure_cannot_satisfy_the_workflow_contract(self):
        run = self.workflow_run()
        for old, new in [
            ('--log "$LOG_DIR/$cohort_native_log"', '--log "$LOG_DIR/08-nativescript-production.log"'),
            ('--selectors "$cohort_selectors"', '--selectors "${SIMULATOR_UI_FILTER:-AI_HLYUITests}"'),
            ("if ! python3 Scripts/CI/verify_nativescript_test_log.py",
             "if python3 Scripts/CI/verify_nativescript_test_log.py"),
        ]:
            with self.subTest(replacement=new):
                changed = run.replace(old, new)
                self.assertNotEqual(changed, run)
                with self.assertRaises(AssertionError):
                    self.assert_cohort_log_check(changed)


if __name__ == "__main__":
    unittest.main()
