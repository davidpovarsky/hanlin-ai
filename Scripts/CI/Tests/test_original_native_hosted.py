"""Portable admission/reconciliation controls; no Apple command is executed."""
from __future__ import annotations
import collections
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import yaml

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location(
    "original_native", ROOT / "Scripts/CI/IntegrationValidation/run_original_native.py")
native = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(native)
CONTRACT = native.load_contract()
OWNER = {"udid": "01020304-0506-0708-090A-0B0C0D0E0F10", "name": "Owned fixture"}
SIMULATOR = CONTRACT["simulator"]


def synthetic_result():
    """Controller-only input with synthetic URLs; never a native receipt."""
    bundles = collections.defaultdict(list)
    for index, expected in enumerate(CONTRACT["expectedTests"]):
        target, identifier = expected["identifier"].split("/", 1)
        url = "synthetic-controller://case/" + str(index)
        node = {"nodeType": "Test Case", "nodeIdentifier": identifier,
                "nodeIdentifierURL": url, "result": "Passed", "children": []}
        values = expected["parameterValues"]
        if values is not None:
            if identifier.endswith(("(engine:)", "(invalidation:)")):
                names = ["." + str(value) for value in values]
            elif all(isinstance(value, (int, float)) and not isinstance(value, bool) for value in values):
                names = [str(float(value)) for value in values]
            else:
                names = ['"' + value + '"' for value in values]
            node["children"] = [
                {"nodeType": "Arguments", "name": name, "result": "Passed",
                 "nodeIdentifierURL": url + "?args=" + str(number)}
                for number, name in enumerate(names)]
        bundles[target].append(node)
    tree = {"testNodes": [{"nodeType": "Unit test bundle", "name": target, "children": nodes}
                          for target, nodes in sorted(bundles.items())]}
    summary = {"totalTestCount": 64, "passedTests": 64, "failedTests": 0,
               "skippedTests": 0, "expectedFailures": 0,
               "devicesAndConfigurations": [{
                   "device": {"deviceId": OWNER["udid"], "osVersion": "27.2", "osBuildNumber": "24B8117"},
                   "passedTests": 85, "failedTests": 0, "skippedTests": 0, "expectedFailures": 0}]}
    return summary, tree


def reconcile(summary, tree, phase=None):
    return native.reconcile(summary, tree, CONTRACT["expectedTests"],
                            CONTRACT["excludedCollateralIdentifiers"], OWNER, SIMULATOR,
                            phase or {"exitCode": 0, "status": "PASSED"})


def observed_device(udid=OWNER["udid"], name=OWNER["name"]):
    return {"devices": {SIMULATOR["runtimeIdentifier"]: [{
        "udid": udid, "name": name, "isAvailable": True, "state": "Shutdown",
        "deviceTypeIdentifier": SIMULATOR["deviceTypeIdentifier"]}]}}


class OriginalNativeHostedTests(unittest.TestCase):
    def test_original95_current85_and_historical_subset_are_separate(self):
        native.validate_contract(CONTRACT)
        self.assertEqual(len(CONTRACT["originalSelectors"]), 95)
        old = [row for row in CONTRACT["expectedTests"] if row["historical"]]
        self.assertEqual((len(old), sum(row["invocations"] for row in old)), (58, 79))
        self.assertEqual(len(CONTRACT["sourceOnlyExcludedAdditions"]), 10)
        self.assertEqual({row["matchedOriginalInclude"] for row in CONTRACT["sourceOnlyExcludedAdditions"]}, {False})
        summary, tree = synthetic_result()
        result = reconcile(summary, tree)
        self.assertTrue(result["acceptancePassed"])
        self.assertEqual((result["actualDefinitions"], result["actualInvocations"],
                          result["parameterInvocations"]), (64, 85, 28))

    def test_selector_order_normalization_and_extra_exclusion_are_rejected(self):
        for change in ("reverse", "inventory24", "extra-exclusion"):
            with self.subTest(change=change):
                broken = copy.deepcopy(CONTRACT)
                selectors = broken["originalSelectors"]
                if change == "reverse":
                    selectors[0], selectors[1] = selectors[1], selectors[0]
                elif change == "inventory24":
                    broken["originalSelectors"] = selectors[:24]
                else:
                    selectors.append("-skip-testing:HanlinPlatformContractsTests/shortcutNativeTextListPreservesOrderAndExactUnicodeBytes()")
                with self.assertRaises(native.AdmissionError):
                    native.validate_contract(broken)

    def test_changed_expected_codec_or_parameter_contract_is_rejected(self):
        for change in ("drop-codec", "parameter"):
            with self.subTest(change=change):
                broken = copy.deepcopy(CONTRACT)
                if change == "drop-codec":
                    broken["expectedTests"] = [row for row in broken["expectedTests"] if row["historical"]]
                else:
                    row = next(row for row in broken["expectedTests"] if row["parameterValues"] is not None)
                    row["parameterValues"][0] = "changed"
                with self.assertRaises(native.AdmissionError):
                    native.validate_contract(broken)

    def test_missing_unexpected_and_duplicate_actual_methods_do_not_pass_counts(self):
        for change in ("missing", "unexpected", "duplicate"):
            with self.subTest(change=change):
                summary, tree = synthetic_result()
                nodes = tree["testNodes"][0]["children"]
                if change == "missing":
                    nodes.pop()
                elif change == "unexpected":
                    nodes[0]["nodeIdentifier"] = "unexpectedMethod()"
                else:
                    nodes.append(copy.deepcopy(nodes[0]))
                with self.assertRaises(native.AdmissionError):
                    reconcile(summary, tree)

    def test_wrong_parameter_values_or_reused_native_argument_identity_reject(self):
        for change in ("value", "duplicate-url", "missing-url-suffix"):
            with self.subTest(change=change):
                summary, tree = synthetic_result()
                node = next(node for bundle in tree["testNodes"] for node in bundle["children"]
                            if len(node["children"]) > 1)
                if change == "value":
                    node["children"][0]["name"] = "not the original argument"
                elif change == "duplicate-url":
                    node["children"][1]["nodeIdentifierURL"] = node["children"][0]["nodeIdentifierURL"]
                else:
                    node["children"][0]["nodeIdentifierURL"] = node["nodeIdentifierURL"] + "?args="
                with self.assertRaises(native.AdmissionError):
                    reconcile(summary, tree)

    def test_skipped_native_case_and_zero_exit_after_stop_cannot_pass(self):
        summary, tree = synthetic_result()
        node = next(node for bundle in tree["testNodes"] for node in bundle["children"] if not node["children"])
        node["result"] = "Skipped"
        summary.update(passedTests=63, skippedTests=1)
        summary["devicesAndConfigurations"][0].update(passedTests=84, skippedTests=1)
        self.assertFalse(reconcile(summary, tree)["acceptancePassed"])
        summary, tree = synthetic_result()
        self.assertFalse(reconcile(summary, tree, {
            "exitCode": 0, "status": "PASSED", "stopReason": "ORIGINAL_3600_SECOND_JOB_DEADLINE"})["acceptancePassed"])

    def test_native_results_must_bind_actual_owned_runtime_and_build(self):
        for field, value in (("deviceId", "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"),
                             ("osVersion", "27.0"), ("osBuildNumber", "24B8118")):
            with self.subTest(field=field):
                summary, tree = synthetic_result()
                summary["devicesAndConfigurations"][0]["device"][field] = value
                with self.assertRaises(native.AdmissionError):
                    reconcile(summary, tree)

    def test_native_summary_is_methods_not_argument_total(self):
        summary, tree = synthetic_result()
        summary["totalTestCount"] = 85
        with self.assertRaises(native.AdmissionError):
            reconcile(summary, tree)

    def test_create_admission_rejects_prior_uuid_and_wrong_physical_identity(self):
        before, after = {"devices": {}}, observed_device()
        owner = native.bind_created_device(before, after, OWNER["udid"], OWNER["name"], SIMULATOR)
        self.assertTrue(owner["identityReadbackVerified"])
        with self.assertRaises(native.AdmissionError):
            native.bind_created_device(after, after, OWNER["udid"], OWNER["name"], SIMULATOR)
        for field, value in (("name", "Previous job"), ("deviceTypeIdentifier", "wrong-type"), ("isAvailable", False)):
            with self.subTest(field=field):
                changed = copy.deepcopy(after)
                changed["devices"][SIMULATOR["runtimeIdentifier"]][0][field] = value
                with self.assertRaises(native.AdmissionError):
                    native.bind_created_device(before, changed, OWNER["udid"], OWNER["name"], SIMULATOR)

    def test_descriptor_only_adds_original_raster_output(self):
        original = {"__xctestrun_metadata__": {"FormatVersion": 2}, "TestConfigurations": [{
            "TestTargets": [{"BlueprintName": "HanlinScriptExtensionsTests",
                             "EnvironmentVariables": {"ORIGINAL": "retained"},
                             "OnlyTestIdentifiers": ["unchanged"], "TestBundlePath": "__TESTROOT__/Original.xctest"},
                            {"BlueprintName": "OtherTests", "OriginalMarker": 17}]}]}
        changed = native.evidence_descriptor(original, Path("/synthetic-owned-output"))
        changed["TestConfigurations"][0]["TestTargets"][0]["EnvironmentVariables"].pop("HANLIN_WIDGET_EVIDENCE_DIR")
        self.assertEqual(changed, original)
        self.assertNotIn("HANLIN_WIDGET_EVIDENCE_DIR",
                         original["TestConfigurations"][0]["TestTargets"][0]["EnvironmentVariables"])
        bad = copy.deepcopy(original)
        bad["TestConfigurations"][0]["TestTargets"][0]["EnvironmentVariables"]["HANLIN_WIDGET_EVIDENCE_DIR"] = "prior"
        with self.assertRaises(native.AdmissionError):
            native.evidence_descriptor(bad, Path("/synthetic-owned-output"))

    def test_product_path_cannot_escape_fresh_descriptor_root(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            products = root / "Products"
            products.mkdir()
            target = "ExampleTests"
            outside = root / (target + ".xctest")
            outside.mkdir()
            (outside / target).write_bytes(b"controller-only synthetic binary")
            descriptor = {"TestConfigurations": [{"TestTargets": [{
                "BlueprintName": target, "TestBundlePath": str(outside), "TestHostPath": "retained-original"}]}]}
            with self.assertRaises(native.AdmissionError):
                native.selected_products(descriptor, products / "Original.xctestrun", {target})

    def test_all_six_pins_need_exact_clean_unique_checkout(self):
        rows = [{"identity": pin["identity"], "revision": pin["state"]["revision"], "status": ""}
                for pin in CONTRACT["pins"]]
        self.assertEqual(len(rows), 6)
        native.validate_pin_rows(CONTRACT["pins"], rows)
        for change in ("missing", "revision", "dirty", "duplicate"):
            with self.subTest(change=change):
                altered = copy.deepcopy(rows)
                if change == "missing":
                    altered.pop()
                elif change == "revision":
                    altered[0]["revision"] = "0" * 40
                elif change == "dirty":
                    altered[0]["status"] = " M source.swift"
                else:
                    altered[1] = copy.deepcopy(altered[0])
                with self.assertRaises(native.AdmissionError):
                    native.validate_pin_rows(CONTRACT["pins"], altered)

    def test_original_disk_floor_and_phase_or_whole_clock_stops_are_distinct(self):
        self.assertIsNone(native.phase_stop_reason(750_000_000, 3300, 3300))
        self.assertEqual(native.phase_stop_reason(749_999_999, 1, 3300), "ACTUAL_DISK_FLOOR")
        self.assertEqual(native.phase_stop_reason(8_000_000_000, 3301, 3300), "BOUNDED_CONTROLLER_TIMEOUT")
        self.assertEqual(native.phase_stop_reason(12_000_000_000, 1, None, 3600),
                         "ORIGINAL_3600_SECOND_JOB_DEADLINE")
        runner = object.__new__(native.Runner)
        runner.lane, runner.root, runner.env = "generic5", ROOT, {}
        runner.elapsed = lambda: 3600
        with mock.patch.object(native.subprocess, "run") as run:
            with self.assertRaises(native.AdmissionError):
                runner.read(["this-must-never-run"])
            run.assert_not_called()

    def test_stop_refuses_unowned_process_group_and_records_zero_exit_stop(self):
        runner = object.__new__(native.Runner)
        runner.save = lambda: None
        process = mock.Mock(pid=91234)
        process.poll.return_value = None
        with mock.patch.object(native.os, "getpgid", return_value=12345), \
                mock.patch.object(native.os, "killpg") as kill:
            with self.assertRaises(native.AdmissionError):
                runner.stop(process, {}, "CONTROLLER_EXCEPTION")
            kill.assert_not_called()
        process.poll.return_value = 0
        process.wait.return_value = 0
        row = {}
        self.assertEqual(runner.stop(process, row, "ACTUAL_DISK_FLOOR"), 0)
        self.assertEqual(row["stopReason"], "ACTUAL_DISK_FLOOR")

    def test_dispatch_rejects_other_routes_and_conflicting_flags(self):
        environment = {"GITHUB_ACTIONS": "true", "GITHUB_EVENT_NAME": "workflow_dispatch",
                       "GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "1", "GITHUB_SHA": "a" * 40}
        inputs = {"target_validation_group": native.GROUP, "exact_test_selector": native.MODE,
                  "runtime_publish_release": True, "force_clean_build": False}
        native.admit_request(environment, inputs)
        for key, value in (("target_validation_group", "exact_test_selector"),
                           ("exact_test_selector", "HanlinPlatformContractsTests"),
                           ("composer_validation_only", True), ("full_validation", True),
                           ("testflight_upload", True), ("force_clean_build", True)):
            with self.subTest(key=key):
                with self.assertRaises(native.AdmissionError):
                    native.admit_request(environment, {**inputs, key: value})

    def test_exact_original_commands_scripts_bounds_and_hosted_environment(self):
        self.assertEqual(CONTRACT["ios"]["buildPhases"][-1]["limitSeconds"], 3300)
        self.assertEqual(CONTRACT["ios"]["testPhases"][3]["limitSeconds"], 1800)
        for phase in (CONTRACT["ios"]["buildPhases"][-1], CONTRACT["ios"]["testPhases"][3]):
            selectors = [item for item in phase["argv"] if item.startswith(("-only-testing:", "-skip-testing:"))]
            self.assertEqual(selectors, CONTRACT["originalSelectors"])
        self.assertEqual(CONTRACT["generic"]["originalOverallDeadlineSeconds"], 3600)
        self.assertEqual(CONTRACT["generic"]["requiredAdmissionBytes"], 9_901_152_640)
        self.assertEqual(CONTRACT["ios"]["buildAdmission"]["requiredBytes"], 8_073_741_824)
        self.assertEqual(CONTRACT["ios"]["testAdmission"]["requiredBytes"], 4_073_741_824)
        self.assertEqual(CONTRACT["toolchain"]["hosted"], {
            "xcode": "27.2", "build": "27B52", "swift": "6.4.2", "simulatorSDK": "27.2",
            "deviceSDK": "27.2", "architecture": "arm64"})
        self.assertEqual(CONTRACT["toolchain"]["historical"]["build"], "27A266a")
        self.assertEqual([script["phaseName"] for script in CONTRACT["generic"]["scripts"]], [
            "resolve-the-phase-1-swift-package", "compile-the-phase-1-swift-package",
            "discover-generated-package-scheme", "compile-contracts-for-generic-ios-simulator",
            "compile-contracts-for-generic-ios-device"])
        self.assertTrue(all("swift test" not in script["body"] for script in CONTRACT["generic"]["scripts"]))

    def test_all_original_path_placeholders_resolve_without_changing_selectors(self):
        runner = object.__new__(native.Runner)
        runner.bindings = {"<SOURCE>": "/owned/source", "<EVIDENCE>": "/owned/evidence",
                           "<IOS79_DERIVED_DATA>": "/owned/products",
                           "<GENERATED_SCHEME>": "HanlinPlatform-Package",
                           "<OWNED_DEVICE_UUID>": OWNER["udid"],
                           "<SAME_PRODUCTS_DERIVED_DESCRIPTOR>": "/owned/products/evidence.xctestrun"}
        phases = CONTRACT["ios"]["buildPhases"] + CONTRACT["ios"]["testPhases"]
        for phase in phases:
            expanded = [runner.expand(argument) for argument in phase["argv"]]
            self.assertTrue(all("<" not in argument for argument in expanded))
            original_selectors = [argument for argument in phase["argv"]
                                  if argument.startswith(("-only-testing:", "-skip-testing:"))]
            self.assertEqual([argument for argument in expanded
                              if argument.startswith(("-only-testing:", "-skip-testing:"))], original_selectors)
        with self.assertRaises(native.AdmissionError):
            runner.expand("<UNBOUND79_PATH>")

    def test_workflow_isolated_matrix_preserves_old_jobs_and_uploads_failures(self):
        document = yaml.load((ROOT / ".github/workflows/build-ios26-unsigned-ipa.yml").read_text(),
                             Loader=yaml.BaseLoader)
        job = document["jobs"]["original-platform-native"]
        self.assertEqual(job["runs-on"], "xcode-27")
        self.assertEqual(job["strategy"]["fail-fast"], "false")
        self.assertEqual(job["strategy"]["matrix"]["include"], [
            {"lane": "ios-original95", "outer_minutes": "175", "controller_minutes": "152"},
            {"lane": "generic5", "outer_minutes": "85", "controller_minutes": "63"}])
        self.assertNotIn("continue-on-error", job)
        self.assertEqual(document["jobs"]["agent-sdk-proof"]["timeout-minutes"], "60")
        for old in ("agent-sdk-proof", "focused-integration-tests", "focused-composer-tests"):
            self.assertIn("inputs.exact_test_selector != 'HanlinPlatformOriginal79Generic5'",
                          document["jobs"][old]["if"])
        self.assertIn("format('original-platform-run-{0}', github.run_id)", document["concurrency"]["group"])
        upload = job["steps"][-1]
        self.assertEqual(upload["if"], "$" + "{{ always() }}")
        self.assertEqual(upload["with"]["if-no-files-found"], "error")
        self.assertEqual(upload["timeout-minutes"], "10")
        self.assertEqual(document["permissions"], {"actions": "read", "contents": "read"})


if __name__ == "__main__":
    unittest.main()
