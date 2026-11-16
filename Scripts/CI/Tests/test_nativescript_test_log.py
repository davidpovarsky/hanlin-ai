from Scripts.CI import verify_nativescript_test_log as checks
from pathlib import Path
import unittest


class NativeScriptTestLogTests(unittest.TestCase):
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
        workflow = (Path(__file__).resolve().parents[3] / ".github/workflows/build-ios26-unsigned-ipa.yml").read_text(encoding="utf-8")
        check = workflow.split('if [ "$nativescript_e2e_status" -eq 0 ]; then', 1)[1].split("\n              fi", 1)[0]
        self.assertIn("python3 Scripts/CI/verify_nativescript_test_log.py", check)
        self.assertIn('--log "$LOG_DIR/08-nativescript-production.log"', check)
        self.assertIn('--selectors "${SIMULATOR_UI_FILTER:-AI_HLYUITests}"', check)


if __name__ == "__main__":
    unittest.main()
