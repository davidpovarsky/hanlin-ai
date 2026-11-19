import copy
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from Scripts.CI.owned_simulator_receipts import (
    BOOT_FILE, SELECTION_FILE, created_selection, record_owned_boot,
    verify_owned_simulator, verify_staged_owner,
)

SOURCE = Path(__file__).resolve().parents[1] / "stage_live_provider_acceptance.py"
RUN = "44385752088"
ATTEMPT = "2"
DEVICE = "11111111-2222-3333-4444-555555555555"
ORIGINAL = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
OTHER = "99999999-8888-7777-6666-555555555555"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-2"
TYPE = "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5"
NAME = "Hanlin-Phase2-" + RUN + "-" + ATTEMPT


class OwnedSimulatorReceiptTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="live-ownership-guard-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.log = self.root / "logs"
        self.log.mkdir()
        self.source = {"udid": ORIGINAL, "name": "iPad Pro 13-inch (M5)",
                       "deviceTypeIdentifier": TYPE, "isAvailable": True}
        self.created = {"udid": DEVICE, "name": NAME, "deviceTypeIdentifier": TYPE,
                        "isAvailable": True, "state": "Shutdown"}
        self.before = {"devices": {RUNTIME: [self.source]}}
        self.observed = {"devices": {RUNTIME: [self.source, self.created]}}
        self.selected = created_selection(
            {"runtime": {"identifier": RUNTIME}, "device": self.source},
            self.before, self.observed, NAME, DEVICE, RUN, ATTEMPT)
        self.save_selection()
        (self.log / "simulator-udid.txt").write_text(DEVICE, encoding="utf-8")
        self.success = subprocess.CompletedProcess(
            ["xcrun", "simctl", "bootstatus", DEVICE, "-b"], 0, "Boot completed", "")
        record_owned_boot(self.log, DEVICE, self.success, RUN, ATTEMPT)

    def save_selection(self):
        (self.log / SELECTION_FILE).write_text(json.dumps(self.selected), encoding="utf-8")

    def verify(self):
        return verify_owned_simulator(self.log, RUN, ATTEMPT)

    def load_stage_module(self):
        with patch.dict(os.environ, {"LOG_DIR": str(self.log)}):
            specification = importlib.util.spec_from_file_location(
                "Scripts.CI.live_provider_under_test", SOURCE)
            module = importlib.util.module_from_spec(specification)
            specification.loader.exec_module(module)
        module.EVIDENCE = self.root / "evidence"
        return module

    def test_fresh_creation_and_actual_boot_receipts_need_no_new_native_inventory(self):
        with patch("subprocess.run", side_effect=AssertionError("No redundant native query")):
            proof = self.verify()
        self.assertEqual(proof["simulator"], DEVICE)
        self.assertEqual(proof["run_id"], RUN)
        self.assertEqual(len(proof["selection_sha256"]), 64)

    def test_create_cannot_claim_a_preexisting_device_even_with_the_expected_name(self):
        before = {"devices": {RUNTIME: [self.source, self.created]}}
        with self.assertRaisesRegex(RuntimeError, "already existed"):
            created_selection({"runtime": {"identifier": RUNTIME}, "device": self.source},
                              before, self.observed, NAME, DEVICE, RUN, ATTEMPT)

    def test_native_readback_must_match_name_hardware_runtime_and_availability(self):
        for field, value in [("name", "Somebody else's device"),
                             ("deviceTypeIdentifier", "iPhone"), ("isAvailable", False)]:
            with self.subTest(field=field):
                observed = copy.deepcopy(self.observed)
                observed["devices"][RUNTIME][1][field] = value
                with self.assertRaises(RuntimeError):
                    created_selection({"runtime": {"identifier": RUNTIME}, "device": self.source},
                                      self.before, observed, NAME, DEVICE, RUN, ATTEMPT)
        with self.assertRaises(RuntimeError):
            created_selection({"runtime": {"identifier": RUNTIME}, "device": self.source},
                              self.before, {"devices": {"other-runtime": [self.created]}},
                              NAME, DEVICE, RUN, ATTEMPT)

    def test_other_run_or_attempt_cannot_reuse_receipts(self):
        for run, attempt in [(RUN, "3"), ("44385752089", ATTEMPT)]:
            with self.subTest(run=run, attempt=attempt), self.assertRaises(RuntimeError):
                verify_owned_simulator(self.log, run, attempt)

    def test_missing_boot_receipt_cannot_authorize_staging(self):
        (self.log / BOOT_FILE).unlink()
        with self.assertRaises(FileNotFoundError):
            self.verify()

    def test_failed_or_wrong_device_boot_cannot_produce_a_boot_receipt(self):
        path = self.log / BOOT_FILE
        path.unlink()
        for command, result in [
            (["xcrun", "simctl", "bootstatus", DEVICE, "-b"], 124),
            (["xcrun", "simctl", "bootstatus", OTHER, "-b"], 0),
            (["xcrun", "simctl", "list", "devices", "-j"], 0),
        ]:
            with self.subTest(command=command, result=result), self.assertRaises(RuntimeError):
                record_owned_boot(self.log, DEVICE, subprocess.CompletedProcess(command, result, "", ""),
                                  RUN, ATTEMPT)
            self.assertFalse(path.exists())

    def test_changed_selection_cannot_reuse_an_older_successful_boot(self):
        self.selected["model"] = "Changed after boot"
        self.save_selection()
        with self.assertRaisesRegex(RuntimeError, "boot receipt"):
            self.verify()

    def test_wrong_udid_file_or_incomplete_creation_provenance_fails_closed(self):
        (self.log / "simulator-udid.txt").write_text(OTHER, encoding="utf-8")
        with self.assertRaises(RuntimeError):
            self.verify()
        (self.log / "simulator-udid.txt").write_text(DEVICE, encoding="utf-8")
        self.selected["ownership"]["absent_before_create"] = False
        self.save_selection()
        with self.assertRaises(RuntimeError):
            self.verify()

    def test_boot_receipt_cannot_be_transplanted_or_relabelled(self):
        original = json.loads((self.log / BOOT_FILE).read_text(encoding="utf-8"))
        for field, value in [("simulator", OTHER), ("run_attempt", "1"),
                             ("selection_sha256", "0" * 64), ("exit_code", 124)]:
            with self.subTest(field=field):
                changed = {**original, field: value}
                (self.log / BOOT_FILE).write_text(json.dumps(changed), encoding="utf-8")
                with self.assertRaises(RuntimeError):
                    self.verify()

    def test_staged_credential_owner_is_immutable_across_cleanup(self):
        proof = self.verify()
        staged = {"simulator": DEVICE, "ownership": proof}
        verify_staged_owner(staged, proof)
        for field, value in [("simulator", OTHER), ("run_attempt", "1"),
                             ("selection_sha256", "0" * 64)]:
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                verify_staged_owner(staged, {**proof, field: value})

    def test_invalid_ownership_stops_before_install_or_any_credential_write(self):
        module = self.load_stage_module()
        (self.log / BOOT_FILE).unlink()
        with patch.dict(os.environ, {"GITHUB_RUN_ID": RUN, "GITHUB_RUN_ATTEMPT": ATTEMPT,
                                     "HANLIN_LIVE_GEMINI_API_KEY": "unit-test-placeholder"}), \
                patch.object(module, "call") as native:
            with self.assertRaises(FileNotFoundError):
                module.stage()
        native.assert_not_called()
        self.assertFalse(module.EVIDENCE.exists())
        self.assertEqual(list(self.root.rglob("provider.json")), [])

    def test_fixture_staging_records_the_successful_targeted_boot_before_seeding(self):
        from Scripts.CI.stage_simulator_fixtures import stage_simulator_fixtures, FIXTURE_NAMES
        (self.log / BOOT_FILE).unlink()
        fixtures = self.root / "fixtures"
        fixtures.mkdir()
        (fixtures / FIXTURE_NAMES[0]).write_text("unit fixture", encoding="utf-8")
        data = self.root / "app-data"
        data.mkdir()
        def native(command, **kwargs):
            result = 1 if "com.apple.DocumentsApp" in command else 0
            output = str(data) if "get_app_container" in command else "Boot completed"
            return subprocess.CompletedProcess(command, result, output, "")
        with patch.dict(os.environ, {"GITHUB_RUN_ID": RUN, "GITHUB_RUN_ATTEMPT": ATTEMPT}):
            result = stage_simulator_fixtures(DEVICE, "com.itorah.chavrusachat", None,
                                             fixtures, self.log, runner=native)
        self.assertEqual(result["status"], "SUCCESS")
        self.assertEqual(self.verify()["simulator"], DEVICE)

    def test_failed_fixture_boot_cannot_emit_an_ownership_boot_receipt(self):
        from Scripts.CI.stage_simulator_fixtures import stage_simulator_fixtures
        (self.log / BOOT_FILE).unlink()
        def native(command, **kwargs):
            return subprocess.CompletedProcess(command, 124, "", "Timed out")
        with patch.dict(os.environ, {"GITHUB_RUN_ID": RUN, "GITHUB_RUN_ATTEMPT": ATTEMPT}):
            result = stage_simulator_fixtures(DEVICE, "com.itorah.chavrusachat", None,
                                             self.root, self.log, runner=native)
        self.assertEqual(result["status"], "BOOT_FAILED")
        self.assertFalse((self.log / BOOT_FILE).exists())

    def test_stage_uses_only_exact_device_install_and_container_calls(self):
        module = self.load_stage_module()
        app = self.root / "AI_HLY.app"
        app.mkdir()
        (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.itorah.chavrusachat"}))
        (self.log / "app-path.txt").write_text(str(app), encoding="utf-8")
        data = self.root / "private-data"
        data.mkdir()
        calls = []
        def native(argv, *args, **kwargs):
            calls.append(argv)
            return subprocess.CompletedProcess(argv, 0,
                str(data) if "get_app_container" in argv else "", "")
        with patch.dict(os.environ, {"GITHUB_RUN_ID": RUN, "GITHUB_RUN_ATTEMPT": ATTEMPT,
                                     "HANLIN_LIVE_GEMINI_API_KEY": "unit-test-placeholder"}), \
                patch.object(module, "call", side_effect=native), \
                patch.object(module.subprocess, "check_output", return_value="source-sha"):
            module.stage()
        self.assertEqual([command[2] for command in calls], ["install", "get_app_container"])
        self.assertTrue(all(command[3] == DEVICE for command in calls))
        self.assertNotIn("unit-test-placeholder", json.dumps(calls))
        staged = json.loads((module.EVIDENCE / "stage.json").read_text(encoding="utf-8"))
        verify_staged_owner(staged, self.verify())
        self.assertNotIn("unit-test-placeholder", json.dumps(staged))
        provider = data / "Library/Application Support/HanlinLiveProviderAcceptance/provider.json"
        self.assertEqual(json.loads(provider.read_text())["apiKey"], "unit-test-placeholder")

    def test_install_failure_preserves_bounded_redacted_evidence_and_cleans_only_owned_device(self):
        module = self.load_stage_module()
        app = self.root / "AI_HLY.app"
        app.mkdir()
        (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.itorah.chavrusachat"}))
        (self.log / "app-path.txt").write_text(str(app), encoding="utf-8")
        key = "unit-test-placeholder"
        calls = []
        def native(argv, **kwargs):
            calls.append(argv)
            code = 124 if argv[2] == "install" else 0
            return subprocess.CompletedProcess(argv, code, key + ("x" * 9000),
                "Native install timed out: " + key if code else "")
        with patch.dict(os.environ, {"GITHUB_RUN_ID": RUN, "GITHUB_RUN_ATTEMPT": ATTEMPT,
                                     "HANLIN_LIVE_GEMINI_API_KEY": key}), \
                patch("Scripts.CI.stage_simulator_fixtures.run_bounded", side_effect=native), \
                patch.object(module.subprocess, "check_output", return_value="a" * 40):
            with self.assertRaisesRegex(RuntimeError, "simctl install"):
                module.stage()
            stage = json.loads((module.EVIDENCE / "stage.json").read_text())
            self.assertEqual(stage["status"], "PREPARING")
            verify_staged_owner(stage, self.verify())
            failures = list(module.EVIDENCE.glob("preparation-failure-*.json"))
            self.assertEqual(len(failures), 1)
            failure = json.loads(failures[0].read_text())
            self.assertEqual(failure["command"], ["xcrun", "simctl", "install"])
            self.assertEqual(failure["exit_code"], 124)
            self.assertEqual(failure["timeout_seconds"], 300)
            self.assertLessEqual(len(failure["stdout_tail"]), 8192)
            self.assertNotIn(key, json.dumps(failure))
            self.assertIn("<redacted>", failure["stderr_tail"])
            self.assertEqual(module.finish(), 1)
        self.assertEqual([command[2] for command in calls], ["install", "shutdown", "delete"])
        self.assertTrue(all(command[3] == DEVICE for command in calls))
        self.assertEqual(list(self.root.rglob("provider.json")), [])
        acceptance = json.loads((module.EVIDENCE / "acceptance.json").read_text())
        self.assertEqual(acceptance["status"], "NOT_ACCEPTED")
        self.assertEqual(acceptance["credential_cleanup"], "OWNED_SIMULATOR_REMOVED")
        self.assertNotIn(key.encode(), b"".join(file.read_bytes() for file in module.EVIDENCE.iterdir()))

    def test_partial_private_write_keeps_atomic_ownership_for_cleanup(self):
        module = self.load_stage_module()
        app = self.root / "AI_HLY.app"
        app.mkdir()
        (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.itorah.chavrusachat"}))
        (self.log / "app-path.txt").write_text(str(app), encoding="utf-8")
        data = self.root / "private-data"
        data.mkdir()
        calls = []
        def native(argv, *args, **kwargs):
            calls.append(argv)
            return subprocess.CompletedProcess(argv, 0,
                str(data) if "get_app_container" in argv else "", "")
        def interrupted_write(value, output):
            output.write('{"apiKey":"unit-test-placeholder"')
            raise OSError("injected private-file failure")
        with patch.dict(os.environ, {"GITHUB_RUN_ID": RUN, "GITHUB_RUN_ATTEMPT": ATTEMPT,
                                     "HANLIN_LIVE_GEMINI_API_KEY": "unit-test-placeholder"}), \
                patch.object(module, "call", side_effect=native), \
                patch.object(module.subprocess, "check_output", return_value="a" * 40):
            with patch.object(module.json, "dump", side_effect=interrupted_write):
                with self.assertRaisesRegex(OSError, "private-file"):
                    module.stage()
            stage = json.loads((module.EVIDENCE / "stage.json").read_text())
            self.assertEqual(stage["status"], "PREPARING")
            verify_staged_owner(stage, self.verify())
            self.assertEqual(module.finish(), 1)
        self.assertEqual([command[2] for command in calls], ["install", "get_app_container", "shutdown", "delete"])
        self.assertTrue(all(command[3] == DEVICE for command in calls))
        self.assertNotIn(b"unit-test-placeholder",
            b"".join(file.read_bytes() for file in module.EVIDENCE.iterdir()))
        self.assertEqual(json.loads((module.EVIDENCE / "acceptance.json").read_text())["status"], "NOT_ACCEPTED")

    def test_changed_staged_owner_cannot_delete_another_simulator(self):
        module = self.load_stage_module()
        module.EVIDENCE.mkdir()
        proof = self.verify()
        (module.EVIDENCE / "stage.json").write_text(
            json.dumps({"simulator": OTHER, "ownership": proof}), encoding="utf-8")
        with patch.dict(os.environ, {"GITHUB_RUN_ID": RUN, "GITHUB_RUN_ATTEMPT": ATTEMPT,
                                     "HANLIN_LIVE_GEMINI_API_KEY": "unit-test-placeholder"}), \
                patch.object(module, "call") as native:
            self.assertEqual(module.finish(), 1)
        native.assert_not_called()
        acceptance = json.loads((module.EVIDENCE / "acceptance.json").read_text())
        self.assertEqual(acceptance["credential_cleanup"], "FAILED")
        self.assertEqual(acceptance["status"], "NOT_ACCEPTED")


if __name__ == "__main__":
    unittest.main()
