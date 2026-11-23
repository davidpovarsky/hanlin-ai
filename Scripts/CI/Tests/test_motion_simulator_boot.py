from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location("boot_motion_simulator", SCRIPTS / "boot_motion_simulator.py")
assert SPEC is not None and SPEC.loader is not None
boot = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(boot)
from owned_simulator_receipts import created_selection, verify_owned_motion_creation, verify_owned_simulator

DEVICE = "10000000-0000-4000-8000-000000000001"
SOURCE = "10000000-0000-4000-8000-000000000002"
RUN = "44454057890"


class MotionSimulatorBootTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.out = Path(self.directory.name)
        self.selection = self.out / "verified-environment.json"
        device = {"udid": SOURCE, "name": "iPad Pro fixture", "state": "Shutdown",
                  "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPad",
                  "isAvailable": True}
        selected = {"device": device, "runtime": {"identifier": "fixture-runtime"}}
        created = {**device, "udid": DEVICE, "name": "Hanlin-Phase2-Motion-" + RUN}
        self.original = created_selection(selected,
            {"devices": {"fixture-runtime": [device]}},
            {"devices": {"fixture-runtime": [device, created]}},
            created["name"], DEVICE, RUN, "1")
        self.selection.write_text(json.dumps(self.original), encoding="utf-8")
        self.calls = []

    def run_fixture(self, statuses, *, strategy="fresh", faults=None, after=None):
        pending = iter(statuses)
        faults = faults or {}

        def command(arguments, timeout, path):
            self.calls.append((arguments, timeout, path.name))
            name = path.stem
            code, timed_out = (next(pending) if arguments[2] == "bootstatus"
                               else faults.get(name, (0, False)))
            path.write_text("synthetic native output for " + name + "\n", encoding="utf-8")
            if after:
                after(name)
            return {"command": arguments, "timeout_seconds": timeout, "return_code": code,
                    "timed_out": timed_out, "elapsed_seconds": timeout if timed_out else 0.01,
                    "output_file": path.name, "output_sha256": boot.digest(path)}

        return boot.ensure_ready(DEVICE, self.selection, strategy, RUN, "1", runner=command)

    def operations(self):
        return [args[2] for args, _, _ in self.calls]

    def receipt(self):
        return json.loads((self.out / "motion-boot-readiness.json").read_bytes())

    def test_success_requires_actual_native_readiness_and_does_not_recover(self):
        result = self.run_fixture([(0, False)])
        self.assertEqual(self.operations(), ["boot", "bootstatus"])
        self.assertEqual(result["status"], "READY_FROM_NATIVE_BOOTSTATUS")
        self.assertEqual(result["recovery_count"], 0)
        self.assertIn("product tests NOT_RUN", result["scope"])
        self.assertTrue((self.out / "bootstatus-attempt-1.log").is_file())

    def test_first_owned_timeout_allows_only_one_targeted_shutdown_boot_and_fresh_readiness(self):
        result = self.run_fixture([(124, True), (0, False)])
        self.assertEqual(self.operations(), ["boot", "bootstatus", "shutdown", "boot", "bootstatus"])
        self.assertEqual([seconds for _, seconds, _ in self.calls], [15, 300, 20, 15, 300])
        self.assertTrue(all(args[3] == DEVICE and args[:2] == ["xcrun", "simctl"]
                            for args, _, _ in self.calls))
        self.assertEqual(result["status"], "READY_FROM_NATIVE_BOOTSTATUS")
        self.assertEqual(result["recovery_count"], 1)
        self.assertTrue(result["attempts"][1]["timed_out"])
        self.assertFalse(result["attempts"][-1]["timed_out"])
        self.assertIn("bootstatus-attempt-1", (self.out / "bootstatus.log").read_text())
        self.assertIn("bootstatus-attempt-2", (self.out / "bootstatus.log").read_text())

    def test_second_timeout_never_retries_again_or_claims_readiness(self):
        with self.assertRaisesRegex(RuntimeError, "no further retry"):
            self.run_fixture([(124, True), (124, True), (0, False)])
        self.assertEqual(self.operations().count("bootstatus"), 2)
        self.assertEqual(self.operations().count("shutdown"), 1)
        self.assertEqual(self.receipt()["status"], "NOT_READY")

    def test_non_timeout_native_failure_including_exit124_does_not_recover(self):
        for code in (1, 124, 204):
            self.calls.clear()
            with self.subTest(code=code), self.assertRaisesRegex(RuntimeError, "not eligible"):
                self.run_fixture([(code, False)])
            self.assertNotIn("shutdown", self.operations())
            self.assertEqual(self.receipt()["recovery_count"], 0)

    def test_ready_device_timeout_does_not_allow_owned_recovery(self):
        value = json.loads(self.selection.read_text())
        value["device"]["state"] = "Booted"
        self.selection.write_text(json.dumps(value))
        with self.assertRaisesRegex(RuntimeError, "not eligible"):
            self.run_fixture([(124, True)], strategy="ready")
        self.assertEqual(self.operations(), ["bootstatus"])
        self.assertEqual(self.receipt()["status"], "NOT_READY")

    def test_booted_inventory_state_is_not_accepted_without_bootstatus_success(self):
        value = json.loads(self.selection.read_text())
        value["device"]["state"] = "Booted"
        self.selection.write_text(json.dumps(value))
        with self.assertRaisesRegex(RuntimeError, "not eligible"):
            self.run_fixture([(1, False)])
        self.assertEqual(self.operations(), ["bootstatus"])
        self.assertEqual(self.receipt()["status"], "NOT_READY")

    def test_foreign_or_incomplete_original_creation_never_receives_native_commands(self):
        for field, replacement in [("run_id", "999"), ("run_attempt", "2"),
                                   ("name", "Hanlin-Phase2-Motion-999"),
                                   ("absent_before_create", False),
                                   ("source_device", DEVICE)]:
            value = json.loads(json.dumps(self.original))
            value["ownership"][field] = replacement
            self.selection.write_text(json.dumps(value))
            self.calls.clear()
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                self.run_fixture([(124, True), (0, False)])
            self.assertEqual(self.calls, [])

    def test_changed_creation_receipt_cannot_authorize_recovery_after_wait(self):
        def after(name):
            if name == "bootstatus-attempt-1":
                self.selection.write_bytes(self.selection.read_bytes() + b"\n")
        with self.assertRaisesRegex(RuntimeError, "selection changed"):
            self.run_fixture([(124, True), (0, False)], after=after)
        self.assertEqual(self.operations(), ["boot", "bootstatus"])
        self.assertEqual(self.receipt()["recovery_count"], 0)

    def test_failed_shutdown_or_reboot_stops_before_a_new_readiness_attempt(self):
        for operation in ("shutdown-recovery", "boot-recovery"):
            self.calls.clear()
            with self.subTest(operation=operation), self.assertRaisesRegex(RuntimeError, "recovery .* failed"):
                self.run_fixture([(124, True), (0, False)], faults={operation: (1, False)})
            self.assertEqual(self.operations().count("bootstatus"), 1)
            self.assertEqual(self.receipt()["status"], "NOT_READY")

    def test_original_non_motion_ownership_namespace_remains_strict(self):
        (self.out / "verified-simulator-environment.json").write_bytes(self.selection.read_bytes())
        (self.out / "simulator-udid.txt").write_text(DEVICE)
        with self.assertRaisesRegex(RuntimeError, "freshly created"):
            verify_owned_simulator(self.out, RUN, "1")
        result = verify_owned_motion_creation(self.selection, DEVICE, RUN, "1")
        self.assertEqual(result["name"], "Hanlin-Phase2-Motion-" + RUN)
        with self.assertRaises(RuntimeError):
            verify_owned_motion_creation(self.selection, DEVICE, RUN, "2")

    def test_non_uuid_ready_selection_cannot_turn_into_an_all_device_command(self):
        value = json.loads(self.selection.read_text())
        value["device"].update(udid="all", state="Booted")
        self.selection.write_text(json.dumps(value))
        def forbidden(*args):
            self.fail("An invalid device must never reach a native command")
        with self.assertRaises(ValueError):
            boot.ensure_ready("all", self.selection, "ready", RUN, "1", runner=forbidden)
        self.assertEqual(self.receipt()["status"], "NOT_READY")

    def test_real_bounded_runner_retains_timeout_output_and_distinguishes_native_exit124(self):
        path = self.out / "bounded-timeout.log"
        result = boot.native_command([sys.executable, "-c",
            "import time; print('owned-command-started', flush=True); time.sleep(5)"], 0.3, path)
        self.assertTrue(result["timed_out"])
        self.assertEqual(result["return_code"], 124)
        self.assertIn("owned-command-started", path.read_text())
        failed = boot.native_command([sys.executable, "-c",
            "import sys; print('native-exit'); sys.exit(124)"], 5, self.out / "native-exit.log")
        self.assertFalse(failed["timed_out"])
        self.assertEqual(failed["return_code"], 124)


    def test_timeout_observations_preserve_real_partial_stdout_and_stderr(self):
        with self.assertRaises(subprocess.TimeoutExpired) as captured:
            subprocess.run([sys.executable, "-c",
                "import sys,time; print('partial-out',flush=True); "
                "print('partial-error',file=sys.stderr,flush=True); time.sleep(5)"],
                capture_output=True, timeout=0.3)
        def observe(command, **kwargs):
            self.assertIn(kwargs["timeout"], (5, 15))
            if command[0] != "ps":
                raise captured.exception
            return subprocess.CompletedProcess(command, 0, b"", b"")
        with patch.object(boot.subprocess, "run", side_effect=observe):
            boot.retain_failure_observations(self.out)
        for name in ("devices-after", "core-simulator-log"):
            self.assertIn(b"partial-out", (self.out / (name + ".stdout")).read_bytes())
            self.assertIn(b"partial-error", (self.out / (name + ".stderr")).read_bytes())
            self.assertEqual((self.out / (name + ".timeout")).read_text(), "15s observation deadline")

    def test_process_observation_is_bounded_filtered_and_retains_timeout_status(self):
        uid = os.geteuid()
        output = (f"101 1 {uid} S /Library/Frameworks/CoreSimulatorService\n"
                  f"102 1 {uid + 1} S /Library/Frameworks/CoreSimulatorService\n"
                  f"103 1 {uid} R /usr/bin/unrelated-command\n"
                  f"104 1 {uid} S /Applications/Xcode.app/Contents/Developer/usr/bin/simctl\n").encode()
        def observe(command, **kwargs):
            if command[0] == "ps":
                self.assertEqual(kwargs["timeout"], 5)
                self.assertEqual(command, ["ps", "-u", str(uid), "-o", "pid=,ppid=,uid=,stat=,comm="])
                raise subprocess.TimeoutExpired(command, 5, output=output, stderr=b"partial ps error")
            return subprocess.CompletedProcess(command, 0, b"[]", b"")
        with patch.object(boot.subprocess, "run", side_effect=observe):
            boot.retain_failure_observations(self.out)
        result = json.loads((self.out / "simulator-process-observation.json").read_text())
        self.assertTrue(result["timed_out"])
        self.assertEqual(result["return_code"], 124)
        self.assertEqual([row["pid"] for row in result["processes"]], [101, 104])
        self.assertEqual(result["stderr"], "partial ps error")

    def test_startup_context_records_exact_developer_path_without_environment_dump(self):
        selected = "/Applications/Xcode_27.2.app/Contents/Developer"
        tool = selected + "/usr/bin/simctl"
        def locate(command, timeout, output):
            self.assertEqual(command, ["xcrun", "--find", "simctl"])
            self.assertEqual(timeout, 5)
            output.write_text(tool + "\n")
            return {"command": command, "timeout_seconds": timeout, "return_code": 0,
                    "timed_out": False, "output_file": output.name}
        with patch.dict(os.environ, {"DEVELOPER_DIR": selected, "UNRELATED_SECRET": "must-not-be-retained"}), \
                patch.object(boot, "native_command", side_effect=locate):
            boot.retain_startup_context(self.out)
        raw = (self.out / "motion-startup-context.json").read_text()
        result = json.loads(raw)
        self.assertEqual(result["developer_dir"], selected)
        self.assertEqual(result["simctl_path"], tool)
        self.assertNotIn("must-not-be-retained", raw)
        self.assertFalse((self.out / "motion-boot-readiness.json").exists())

    def test_missing_diagnostic_tools_do_not_mask_the_readiness_verdict(self):
        self.selection.write_text(json.dumps(self.original))
        with self.assertRaisesRegex(RuntimeError, "not eligible"):
            self.run_fixture([(1, False)])
        original = (self.out / "motion-boot-readiness.json").read_bytes()
        with patch.object(boot, "native_command", side_effect=OSError("tool unavailable")), \
                patch.object(boot.subprocess, "run", side_effect=OSError("observation unavailable")):
            boot.retain_startup_context(self.out)
            boot.retain_failure_observations(self.out)
        self.assertEqual((self.out / "motion-boot-readiness.json").read_bytes(), original)
        self.assertIn("tool unavailable", (self.out / "motion-startup-context.json").read_text())
        self.assertIn("observation unavailable", (self.out / "simulator-process-observation.json").read_text())


if __name__ == "__main__":
    unittest.main()
