"""Portable ownership regressions; no native simulator commands are executed."""
import contextlib
import copy
import io
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from Scripts.CI import boot_motion_simulator as boot
from Scripts.CI.owned_simulator_receipts import (
    created_selection, motion_run_from_environment, motion_run_identity,
    verify_owned_motion_creation, verify_owned_simulator,
)

ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = ROOT / "Scripts/CI"
DEVICE = "10000000-0000-4000-8000-000000000001"
SOURCE = "10000000-0000-4000-8000-000000000002"
RUN = "mac-motion-b-20261124"
ATTEMPT = "2"
ENV = {"HANLIN_LOCAL_RUN_ID": RUN, "HANLIN_LOCAL_RUN_ATTEMPT": ATTEMPT}


class LocalMotionOwnershipTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.out = Path(temporary.name)
        self.selection = self.out / "verified-environment.json"
        self.identity = motion_run_from_environment(ENV)
        runtime_root = self.out / "runtime-root"
        runtime_root.mkdir()
        bundle = self.out / "runtime-bundle"
        (bundle / "Contents").mkdir(parents=True)
        (bundle / "Contents/Info.plist").write_bytes(b"fixture")
        self.runtime = {
            "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            "platform": "iOS", "version": "27.0", "isAvailable": True,
            "runtimeRoot": str(runtime_root), "bundlePath": str(bundle),
        }
        self.source = {
            "udid": SOURCE, "name": "iPad fixture", "state": "Shutdown",
            "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPad",
            "isAvailable": True,
        }
        self.created = {**self.source, "udid": DEVICE, "name": self.identity["name"]}
        self.before = {"devices": {self.runtime["identifier"]: [self.source]}}
        self.observed = {"devices": {self.runtime["identifier"]: [self.source, self.created]}}
        self.selected = created_selection(
            {"device": self.source, "runtime": self.runtime}, self.before, self.observed,
            self.identity["name"], DEVICE, RUN, ATTEMPT, run_provider="local-mac")
        self.selection.write_text(json.dumps(self.selected))
        self.calls = []

    def ready(self, statuses):
        pending = iter(statuses)
        def command(arguments, timeout, path):
            self.calls.append((arguments, timeout))
            code, timed_out = next(pending) if arguments[2] == "bootstatus" else (0, False)
            path.write_text("fixture native command")
            return {"command": arguments, "timeout_seconds": timeout, "return_code": code,
                    "timed_out": timed_out, "elapsed_seconds": 0.01,
                    "output_file": path.name, "output_sha256": boot.digest(path)}
        return boot.ensure_ready(
            DEVICE, self.selection, "fresh", RUN, ATTEMPT,
            runner=command, run_provider="local-mac")

    def test_local_identity_is_explicit_and_original_github_numeric_validation_remains(self):
        self.assertEqual(self.identity, {
            "run_provider": "local-mac", "run_id": RUN, "run_attempt": ATTEMPT,
            "name": "Hanlin-Phase2-Motion-local-" + RUN + "-" + ATTEMPT,
        })
        github = motion_run_from_environment({"GITHUB_RUN_ID": "44454057890", "GITHUB_RUN_ATTEMPT": "1"})
        self.assertEqual(github["name"], "Hanlin-Phase2-Motion-44454057890")
        self.assertEqual(github["run_provider"], "github")
        for run, attempt in [(RUN, "1"), ("44454057890", None), ("0", "1"), ("44454057890", "0")]:
            with self.subTest(run=run, attempt=attempt), self.assertRaises(RuntimeError):
                motion_run_identity(run, attempt)

    def test_missing_malformed_or_mixed_local_context_fails_closed(self):
        invalid = [
            {"HANLIN_LOCAL_RUN_ID": RUN},
            {"HANLIN_LOCAL_RUN_ATTEMPT": "1"},
            {**ENV, "HANLIN_LOCAL_RUN_ID": "../other"},
            {**ENV, "HANLIN_LOCAL_RUN_ID": "x" * 65},
            {**ENV, "HANLIN_LOCAL_RUN_ATTEMPT": "0"},
            {**ENV, "GITHUB_ACTIONS": "true"},
            {**ENV, "GITHUB_RUN_ID": "44454057890"},
            {**ENV, "GITHUB_RUN_ATTEMPT": "1"},
        ]
        for environment in invalid:
            with self.subTest(environment=environment), self.assertRaises(RuntimeError):
                motion_run_from_environment(environment)
        with self.assertRaises(RuntimeError):
            motion_run_identity(RUN, ATTEMPT, "unrecognized")

    def test_local_boot_retains_real_readiness_requirement_and_provider(self):
        receipt = self.ready([(0, False)])
        self.assertEqual([command[2] for command, _ in self.calls], ["boot", "bootstatus"])
        self.assertEqual(receipt["status"], "READY_FROM_NATIVE_BOOTSTATUS")
        self.assertEqual(receipt["run_provider"], "local-mac")
        self.assertEqual(receipt["ownership"]["run_id"], RUN)
        self.assertEqual(receipt["recovery_count"], 0)
        self.assertIn("product tests NOT_RUN", receipt["scope"])

    def test_local_recovery_remains_one_targeted_cycle_with_unchanged_deadlines(self):
        receipt = self.ready([(124, True), (0, False)])
        self.assertEqual([command[2] for command, _ in self.calls],
                         ["boot", "bootstatus", "shutdown", "boot", "bootstatus"])
        self.assertEqual([timeout for _, timeout in self.calls], [15, 300, 20, 15, 300])
        self.assertTrue(all(command[3] == DEVICE for command, _ in self.calls))
        self.assertEqual(receipt["recovery_count"], 1)
        self.assertEqual(receipt["ownership"]["run_provider"], "local-mac")

    def test_foreign_run_attempt_provider_or_missing_local_marker_gets_no_native_command(self):
        for field, value in [("run_id", "other-local-run"), ("run_attempt", "3"),
                             ("run_provider", "github"), ("run_provider", None)]:
            selected = copy.deepcopy(self.selected)
            if value is None:
                del selected["ownership"][field]
            else:
                selected["ownership"][field] = value
            self.selection.write_text(json.dumps(selected))
            self.calls.clear()
            with self.subTest(field=field, value=value), self.assertRaises(RuntimeError):
                self.ready([(0, False)])
            self.assertEqual(self.calls, [])

    def test_local_receipt_cannot_authorize_github_live_provider_staging(self):
        selected = copy.deepcopy(self.selected)
        selected["ownership"].update(run_id="44454057890", run_attempt="1",
                                     name="Hanlin-Phase2-44454057890-1")
        selected["device"]["name"] = selected["ownership"]["name"]
        (self.out / "verified-simulator-environment.json").write_text(json.dumps(selected))
        (self.out / "simulator-udid.txt").write_text(DEVICE)
        with self.assertRaisesRegex(RuntimeError, "freshly created"):
            verify_owned_simulator(self.out, "44454057890", "1")
        with self.assertRaises(RuntimeError):
            verify_owned_motion_creation(self.selection, DEVICE, RUN, ATTEMPT)

    def select_cli(self, environment, name):
        commands = []
        def read(command, **kwargs):
            commands.append(command)
            if command[:3] == ["xcrun", "--sdk", "iphonesimulator"]:
                return "27.0"
            if command[2:4] == ["list", "runtimes"]:
                return json.dumps({"runtimes": [self.runtime]})
            if command[2:4] == ["list", "devices"]:
                return json.dumps(self.observed if any(c[2] == "create" for c in commands) else self.before)
            if command[2] == "create":
                self.assertEqual(command[3:], [self.identity["name"], self.source["deviceTypeIdentifier"],
                                              self.runtime["identifier"]])
                return DEVICE
            self.fail("Unexpected command: " + repr(command))
        argv = [str(SCRIPTS / "select_installed_simulator.py"), "--output", str(self.selection),
                "--create-owned", name]
        with patch.dict(os.environ, environment, clear=True), patch.object(sys, "argv", argv), \
                patch.object(sys, "path", [str(SCRIPTS), *sys.path]), \
                patch("subprocess.check_output", side_effect=read), contextlib.redirect_stdout(io.StringIO()):
            try:
                runpy.run_path(argv[0], run_name="__main__")
            finally:
                self.calls = commands

    def test_selection_cli_records_local_provenance_and_native_creation_readback(self):
        self.select_cli(ENV, self.identity["name"])
        selected = json.loads(self.selection.read_text())
        self.assertEqual(selected["ownership"]["run_provider"], "local-mac")
        self.assertEqual(selected["ownership"]["run_id"], RUN)
        self.assertTrue(selected["ownership"]["absent_before_create"])
        self.assertEqual(sum(command[2] == "create" for command in self.calls), 1)

    def test_selection_rejects_invalid_context_or_name_before_native_creation(self):
        for environment, name in [
            ({**ENV, "GITHUB_RUN_ID": "44454057890"}, self.identity["name"]),
            (ENV, "Hanlin-Phase2-Motion-local-wrong-2"),
            ({"GITHUB_RUN_ID": RUN, "GITHUB_RUN_ATTEMPT": "1"}, "Hanlin-Phase2-Motion-" + RUN),
        ]:
            with self.subTest(environment=environment, name=name), self.assertRaises((ValueError, RuntimeError)):
                self.select_cli(environment, name)
            self.assertFalse(any(command[2] == "create" for command in self.calls))

    def test_original_cleanup_hook_verifies_current_local_owner_before_exact_device_commands(self):
        wrapper = (ROOT / "docs/chat-motion/run_motion_ui.sh").read_text()
        cleanup = wrapper.split("<<'PY' || cleanup_code=$?\n", 1)[1].split("\nPY\n", 1)[0]
        argv = ["-", str(ROOT), DEVICE, str(self.selection)]
        with patch.dict(os.environ, ENV, clear=True), patch.object(sys, "argv", argv), \
                patch("subprocess.run", return_value=subprocess.CompletedProcess([], 0)) as native, \
                contextlib.redirect_stdout(io.StringIO()):
            exec(compile(cleanup, "run_motion_ui.sh:cleanup", "exec"), {})
        self.assertEqual([call.args[0] for call in native.call_args_list],
                         [["xcrun", "simctl", "shutdown", DEVICE], ["xcrun", "simctl", "delete", DEVICE]])
        self.selected["ownership"]["run_attempt"] = "3"
        self.selection.write_text(json.dumps(self.selected))
        with patch.dict(os.environ, ENV, clear=True), patch.object(sys, "argv", argv), \
                patch("subprocess.run") as native, self.assertRaises(RuntimeError):
            exec(compile(cleanup, "run_motion_ui.sh:cleanup", "exec"), {})
        native.assert_not_called()


if __name__ == "__main__":
    unittest.main()
