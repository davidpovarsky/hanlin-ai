"""Adversarial synthetic evidence tests. These are not executed app UI cases."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import gate


class GateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hanlin-ui-gate-")
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.policy_path = self.repo / "Scripts/CI/SimulatorAcceptance/contract.json"
        self.policy_path.parent.mkdir(parents=True)
        shutil.copyfile(gate.POLICY_PATH, self.policy_path)
        self.policy = gate.read(self.policy_path)
        self.coverage = {"schema_version": 1, "cases": [{"selector": "AI_HLYUITests/SampleUI/testJourney", "device_families": ["iPhone", "iPad"], "locales": ["en", "he"], "coverage_tags": self.policy["required_coverage_tags"], "fixture_paths": []}]}
        self.coverage_path = self.repo / self.policy["coverage_file"]
        gate.write(self.coverage_path, self.coverage)
        source = self.repo / "AI_HLYUITests/SampleUI.swift"
        source.parent.mkdir()
        source.write_text("import XCTest\nfinal class SampleUI: XCTestCase { func testJourney() {} }\n")
        for args in [["init", "-q"], ["config", "core.autocrlf", "false"], ["add", "."], ["-c", "user.name=GateTest", "-c", "user.email=gate@example.invalid", "commit", "-qm", "synthetic fixture"]]:
            subprocess.run(["git", "-C", str(self.repo), *args], check=True, capture_output=True)
        self.plan = gate.prepare(self.repo, "123", self.policy_path)
        self.evidence = self.root / "evidence"
        gate.write(self.evidence / "plan.json", self.plan)
        for path in self.plan["inputs_sha256"]:
            target = self.evidence / "inputs" / path
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(self.repo / path, target)
        for variant in self.plan["variants"]:
            folder = self.evidence / variant["id"]
            gate.write(folder / "tests.json", {"devices": [{"osVersion": "27.0", "modelName": variant["family"] + " Synthetic", "deviceId": "SYNTHETIC"}], "testNodes": [{"nodeType": "Test Case", "nodeIdentifier": "SampleUI/testJourney()", "result": "Passed"}]})
            gate.write(folder / "context.json", {"family": variant["family"], "locale": variant["locale"], "configuration": "Release", "source_sha": self.plan["candidate_source_sha"], "build_number": "123", "bundle_id": self.policy["app_bundle_id"], "sdk_version": "27.2", "xcode_version": "Xcode 27.2", "runner_os": "Darwin", "xcodebuild_exit_code": 0, "device_udid": "SYNTHETIC"})
            gate.write(folder / "device-creation.json", {"created_by_this_run": True, "was_in_original_inventory": False, "preexisting_app_container": False, "device_udid": "SYNTHETIC"})
            gate.write(folder / "case-attachments.json", {"SampleUI/testJourney": ["screenshots/synthetic.png"]})
            (folder / "screenshots").mkdir()
            (folder / "screenshots/synthetic.png").write_bytes(b"\x89PNG\r\n\x1a\nSYNTHETIC_UNIT_FIXTURE")
            (folder / "Tests.xcresult").mkdir()
            (folder / "Tests.xcresult/Info.plist").write_bytes(b"synthetic unit fixture")

    def tearDown(self):
        self.temp.cleanup()

    def verify(self):
        return gate.verify(self.evidence, "123", self.plan["candidate_source_sha"], self.policy_path)

    def mutate(self, relative, change):
        path = self.evidence / relative
        value = gate.read(path)
        change(value)
        gate.write(path, value)

    def test_complete_synthetic_matrix_is_counted_from_raw_nodes(self):
        self.assertEqual(self.verify()["counts"]["EXECUTED_PASS"], 4)

    def test_missing_empty_or_open_gap_coverage_blocks(self):
        for coverage in [{"schema_version": 1, "cases": []}, dict(self.coverage, required_gaps=["rotation"]), {"schema_version": 99, "cases": self.coverage["cases"]}]:
            gate.write(self.coverage_path, coverage)
            with self.assertRaises(gate.GateError): gate.prepare(self.repo, "123", self.policy_path)
        self.coverage_path.unlink()
        with self.assertRaises(gate.GateError): gate.prepare(self.repo, "123", self.policy_path)

    def test_partial_or_foreign_target_cannot_satisfy_gate(self):
        self.mutate("plan.json", lambda d: d.update(scope="compiled-swift-parity-miniapp-ui-only"))
        with self.assertRaises(gate.GateError): self.verify()

    def test_wrong_build_and_source_are_rejected(self):
        for number, sha in [("124", self.plan["candidate_source_sha"]), ("123", "f" * 40)]:
            with self.assertRaises(gate.GateError): gate.verify(self.evidence, number, sha, self.policy_path)

    def test_skipped_failed_missing_and_duplicate_results_block(self):
        path = self.evidence / "iPhone-en/tests.json"
        original = gate.read(path)
        for result in ["Skipped", "Failed", "Unknown"]:
            data = copy.deepcopy(original);data["testNodes"][0]["result"] = result;gate.write(path, data)
            with self.assertRaises(gate.GateError): self.verify()
        for entries in [[], original["testNodes"] * 2]:
            gate.write(path, dict(original, testNodes=entries))
            with self.assertRaises(gate.GateError): self.verify()

    def test_wrong_runtime_or_model_blocks(self):
        path = self.evidence / "iPad-he/tests.json";original = gate.read(path)
        for device in [{"osVersion": "26.5", "modelName": "iPad"}, {"osVersion": "27.0", "modelName": "iPhone"}, {}]:
            gate.write(path, dict(original, devices=[device]))
            with self.assertRaises(gate.GateError): self.verify()

    def test_locale_configuration_bundle_and_process_mismatch_block(self):
        path = self.evidence / "iPhone-he/context.json";original = gate.read(path)
        for field, value in [("locale", "en"), ("configuration", "Debug"), ("bundle_id", "partial.fixture"), ("xcodebuild_exit_code", 65), ("runner_os", "Windows"), ("sdk_version", "26.5"), ("source_sha", "a" * 40), ("build_number", "999")]:
            gate.write(path, dict(original, **{field: value}))
            with self.assertRaises(gate.GateError): self.verify()

    def test_matrix_removal_and_duplicate_matrix_block(self):
        path = self.evidence / "plan.json"
        for variants in [self.plan["variants"][:-1], [self.plan["variants"][0]] * 4]:
            gate.write(path, dict(self.plan, variants=variants))
            with self.assertRaises(gate.GateError): self.verify()

    def test_raw_bundle_screenshot_and_source_bytes_are_required(self):
        for relative in ["iPhone-en/Tests.xcresult/Info.plist", "iPhone-en/screenshots/synthetic.png", "inputs/AI_HLYUITests/SampleUI.swift"]:
            path = self.evidence / relative;old = path.read_bytes();path.unlink()
            with self.assertRaises((gate.GateError, OSError)): self.verify()
            path.write_bytes(old)

    def test_screenshot_traversal_and_fake_image_are_rejected(self):
        self.mutate("iPhone-en/case-attachments.json", lambda d: d.update({"SampleUI/testJourney": ["../outside.png"]}))
        with self.assertRaises(gate.GateError): self.verify()

    def test_forged_source_hash_or_changed_contract_blocks(self):
        path = self.evidence / "inputs/AI_HLYUITests/SampleUI.swift";path.write_text("altered")
        with self.assertRaises(gate.GateError): self.verify()

    def test_zero_case_plan_cannot_pass(self):
        self.mutate("plan.json", lambda d: d["variants"][0].update(selectors=[]))
        with self.assertRaises(gate.GateError): self.verify()

    def test_existing_simulator_or_container_blocks(self):
        path = self.evidence / "iPad-he/device-creation.json";original = gate.read(path)
        for field, value in [("created_by_this_run", False), ("was_in_original_inventory", True), ("preexisting_app_container", True), ("device_udid", "OTHER")]:
            gate.write(path, dict(original, **{field: value}))
            with self.assertRaises(gate.GateError): self.verify()

    def test_partial_planning_never_enables_release(self):
        self.coverage["cases"][0]["coverage_tags"] = ["navigation"]
        gate.write(self.coverage_path, self.coverage)
        subprocess.run(["git", "-C", str(self.repo), "add", "."], check=True, capture_output=True)
        subprocess.run(["git", "-C", str(self.repo), "-c", "user.name=GateTest", "-c", "user.email=gate@example.invalid", "commit", "-qm", "freeze synthetic partial coverage"], check=True, capture_output=True)
        partial = gate.prepare(self.repo, "123", self.policy_path, allow_incomplete=True)
        self.assertFalse(partial["release_eligible"])
        self.assertTrue(partial["coverage_gaps"])
        gate.write(self.evidence / "plan.json", partial)
        with self.assertRaises(gate.GateError): self.verify()

    def test_unfrozen_assertion_source_cannot_enter_candidate_plan(self):
        (self.repo / "AI_HLYUITests/SampleUI.swift").write_text("import XCTest\nfinal class SampleUI: XCTestCase { func testJourney() { print(1) } }")
        with self.assertRaises(gate.GateError): gate.prepare(self.repo, "123", self.policy_path)


if __name__ == "__main__":
    unittest.main()
