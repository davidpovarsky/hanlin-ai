import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

from Scripts.CI import ui_viewport_cohorts as cohorts
from Scripts.CI.select_installed_simulator import family_for_selectors

ROOT = Path(__file__).resolve().parents[3]
MORPH = "AI_HLYUITests/HanlinMorphComposerUITests"
SIDEBAR = "AI_HLYUITests/HanlinSidebarNavigationUITests"


def nodes(selectors, result="Passed"):
    return {"testNodes": [{"nodeType": "Test Case", "nodeIdentifier": selector,
                           "result": result} for selector in selectors]}


class OriginalViewportCohortsTests(unittest.TestCase):
    def test_original87_membership_is_preserved_without_any_paired_inference(self):
        original = json.loads((ROOT / "docs/two-wave-integration/20261126/affected-routing-a35694f7/plan.json").read_text())
        selected = original["selected_tests"]
        units = [s for s in selected if s.startswith("AI_HLYTests/")]
        ui = [s for s in selected if s.startswith("AI_HLYUITests/")]
        value = cohorts.plan(",".join(ui))
        self.assertEqual((len(units), len(ui)), (77, 10))
        self.assertEqual(value["requested_selectors"], ui)
        wide, compact = value["cohorts"]
        self.assertEqual((wide["family"], compact["family"]), ("iPad", "iPhone"))
        self.assertEqual((len(wide["selectors"]), len(compact["selectors"])), (14, 8))
        self.assertFalse(set(wide["selectors"]) & set(compact["selectors"]))
        self.assertEqual(set(wide["selectors"] + compact["selectors"]), set(value["expanded_selectors"]))
        self.assertEqual(family_for_selectors(",".join(compact["selectors"])), "iPhone")
        self.assertEqual(family_for_selectors(",".join(wide["selectors"])), "iPad")
        self.assertEqual(value["application_builds_planned"], 1)
        self.assertNotIn("HanlinPairedProductUITests", ",".join(value["expanded_selectors"]))

    def test_profile_rejects_an_added_original_method_until_it_is_assigned(self):
        profile = cohorts.checked_profile()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for rule in profile["suites"].values():
                path = root / rule["source"]
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text((ROOT / rule["source"]).read_text())
            path = root / profile["suites"][MORPH]["source"]
            path.write_text(path.read_text() + "\nfunc testNewActualObligation() {}\n")
            with self.assertRaisesRegex(ValueError, "membership changed"):
                cohorts.checked_profile(root)

    def test_sidebar_exact_and_suite_selectors_require_a_real_narrow_device(self):
        self.assertEqual(family_for_selectors(SIDEBAR), "iPhone")
        self.assertEqual(family_for_selectors(SIDEBAR + "/testNativeHistoryRowSwipeRemainsAvailable"), "iPhone")
        with self.assertRaisesRegex(ValueError, "separate narrow-device run"):
            family_for_selectors(SIDEBAR + "," + MORPH + "/testWideNavigationKeepsDraft")

    def test_original_full_bundle_keeps_other_tests_and_skips_only_moved_methods(self):
        value = cohorts.plan("AI_HLYUITests")
        wide, compact = value["cohorts"]
        self.assertEqual(wide["selectors"], ["AI_HLYUITests"])
        self.assertEqual(wide["skip_selectors"], compact["selectors"])
        self.assertEqual(len(compact["selectors"]), 8)
        self.assertEqual(value["requested_selectors"], ["AI_HLYUITests"])

    def test_missing_or_skipped_compact_cases_cannot_be_hidden_by_a_wide_pass(self):
        value = cohorts.plan(MORPH + "," + SIDEBAR)
        wide, compact = value["cohorts"]
        result = cohorts.verify_union(value, {"wide": nodes(wide["selectors"]),
            "compact": nodes(compact["selectors"], "Skipped")})
        self.assertEqual(result["status"], "MISSING_COVERAGE")
        self.assertEqual(set(result["cohort_missing"]["compact"]), set(compact["selectors"]))

    def test_second_cohort_pass_does_not_turn_first_native_failure_into_success(self):
        value = cohorts.plan(MORPH + "," + SIDEBAR)
        wide, compact = value["cohorts"]
        result = cohorts.verify_union(value, {"wide": nodes(wide["selectors"], "Failed"),
            "compact": nodes(compact["selectors"])})
        self.assertEqual(result["status"], "FAILED_TESTS")
        self.assertFalse(result["union_missing"])
        self.assertEqual(len(result["failed_cases"]), 6)

    def test_original_selector_union_requires_all14_viewport_methods(self):
        value = cohorts.plan(MORPH + "," + SIDEBAR)
        documents = {c["id"]: nodes(c["selectors"]) for c in value["cohorts"]}
        self.assertEqual(cohorts.verify_union(value, documents)["status"], "EXECUTED_COVERAGE")
        documents["compact"]["testNodes"].pop()
        self.assertEqual(cohorts.verify_union(value, documents)["status"], "MISSING_COVERAGE")

    def test_original_workflow_gate_is_valid_before_any_cohort_is_created(self):
        workflow = (ROOT / ".github/workflows/build-ios26-unsigned-ipa.yml").read_text()
        guard = next(line.strip() for line in workflow.splitlines()
                     if 'if [ "$FAST_VALIDATION_ONLY"' in line and 'RUN_SIMULATOR_TARGETED_UI' in line)
        for selectors, expected in [(MORPH, "selected"), ("", "")]:
            with self.subTest(selectors=selectors):
                environment = dict(os.environ, FAST_VALIDATION_ONLY="false",
                    RUN_SIMULATOR_TARGETED_UI="true", RUN_FULL_VALIDATION="false",
                    SIMULATOR_UI_FILTER=selectors)
                environment.pop("cohort_selectors", None)
                result = subprocess.run(["bash", "-c", "set -eu\n" + guard
                    + "\nprintf selected\nfi\n"], env=environment, text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, expected)

    def test_unknown_method_or_other_test_bundle_fails_closed(self):
        for selector in [MORPH + "/testMisspelled", "HanlinMiniAppsTests/NativeScriptShortcutConcurrencyTests"]:
            with self.assertRaises(ValueError):
                cohorts.plan(selector)


class CurrentUIProductsTests(unittest.TestCase):
    def make_products(self, root):
        derived = root / "DerivedData"
        products = derived / "Build/Products"
        app = products / "Release-iphonesimulator/AI_Hanlin.app"
        runner = products / "Release-iphonesimulator/AI_HLYUITests-Runner.app"
        test = runner / "PlugIns/AI_HLYUITests.xctest"
        for bundle, identifier, name in [(app, "com.itorah.chavrusachat", "AI_Hanlin"),
                (runner, "com.itorah.chavrusachatUITests.xctrunner", "AI_HLYUITests-Runner"),
                (test, "com.itorah.chavrusachatUITests", "AI_HLYUITests")]:
            bundle.mkdir(parents=True, exist_ok=True)
            (bundle / "Info.plist").write_bytes(plistlib.dumps(
                {"CFBundleIdentifier": identifier, "CFBundleExecutable": name}))
            (bundle / name).write_bytes(b"original compiled product")
        target = {"BlueprintName": "AI_HLYUITests", "IsUITestBundle": True,
            "TestHostPath": "__TESTROOT__/Release-iphonesimulator/AI_HLYUITests-Runner.app",
            "TestBundlePath": "__TESTHOST__/PlugIns/AI_HLYUITests.xctest",
            "UITargetAppPath": "__TESTROOT__/Release-iphonesimulator/AI_Hanlin.app"}
        manifest = products / "AI_HLY_iphonesimulator27.2-arm64.xctestrun"
        document = {"__xctestrun_metadata__": {"FormatVersion": 2},
                    "TestConfigurations": [{"TestTargets": [target]}]}
        manifest.write_bytes(plistlib.dumps(document))
        return derived, manifest, test, document

    def test_same_current_manifest_and_ui_binary_are_bound_before_both_viewports(self):
        with tempfile.TemporaryDirectory() as folder:
            derived, manifest, test, _ = self.make_products(Path(folder))
            before = cohorts.product_snapshot(derived, manifest)
            self.assertEqual(before, cohorts.product_snapshot(derived, manifest))
            self.assertEqual(len(before["files"]), 6)
            (test / "AI_HLYUITests").write_bytes(b"different source product")
            self.assertNotEqual(before, cohorts.product_snapshot(derived, manifest))

    def test_retained_original_format_one_shape_uses_the_same_original_product_paths(self):
        with tempfile.TemporaryDirectory() as folder:
            derived, manifest, _, document = self.make_products(Path(folder))
            before = cohorts.product_snapshot(derived, manifest)
            target = document["TestConfigurations"][0]["TestTargets"][0]
            original = {"__xctestrun_metadata__": {"FormatVersion": 1},
                        "AI_HLYUITests": target}
            manifest.write_bytes(plistlib.dumps(original))
            after = cohorts.product_snapshot(derived, manifest)
            self.assertEqual(before["files"], after["files"])
            self.assertNotEqual(before["manifest_sha256"], after["manifest_sha256"])
            target["IsEnabled"] = False
            manifest.write_bytes(plistlib.dumps(original))
            with self.assertRaisesRegex(ValueError, "missing or ambiguous"):
                cohorts.product_snapshot(derived, manifest)

    def test_replacing_manifest_or_missing_original_ui_target_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            derived, manifest, _, document = self.make_products(Path(folder))
            other = Path(folder) / "stale.xctestrun"
            other.write_bytes(manifest.read_bytes())
            with self.assertRaisesRegex(ValueError, "already admitted"):
                cohorts.product_snapshot(derived, other)
            document["TestConfigurations"][0]["TestTargets"] = []
            manifest.write_bytes(plistlib.dumps(document))
            with self.assertRaisesRegex(ValueError, "missing or ambiguous"):
                cohorts.product_snapshot(derived)

    def test_product_path_cannot_escape_original_derived_data(self):
        with tempfile.TemporaryDirectory() as folder:
            derived, manifest, _, document = self.make_products(Path(folder))
            document["TestConfigurations"][0]["TestTargets"][0]["UITargetAppPath"] = str(Path(folder))
            manifest.write_bytes(plistlib.dumps(document))
            with self.assertRaisesRegex(RuntimeError, "escapes the owned"):
                cohorts.product_snapshot(derived)


if __name__ == "__main__":
    unittest.main()
