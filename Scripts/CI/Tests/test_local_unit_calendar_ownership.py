"""Portable local-app ownership and Calendar grant regressions; no native commands."""
import contextlib
import io
import json
import os
from pathlib import Path
import plistlib
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import current_unit_xctestrun as admission
import owned_simulator_receipts as owned
import prepare_calendar_acceptance as calendar

RUN = "hanlin-149101-ipad"
ATTEMPT = "1"
SOURCE_SHA = "a" * 40
DEVICE = "10000000-0000-4000-8000-000000000001"
SOURCE_DEVICE = "10000000-0000-4000-8000-000000000002"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
ENV = {"HANLIN_LOCAL_RUN_ID": RUN, "HANLIN_LOCAL_RUN_ATTEMPT": ATTEMPT,
       "HANLIN_LOCAL_SOURCE_SHA": SOURCE_SHA}
SELECTOR = calendar.MUTATION_SUITE + "/eventNotePatchPreservesAlarmAndRecurrence()"


class LocalUnitCalendarOwnershipTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.log = self.root / "logs"
        self.log.mkdir()
        self.products = self.root / "build/SimulatorDerivedData/Build/Products"
        self.products.mkdir(parents=True)
        self.identity = owned.simulator_run_from_environment(ENV)
        self.runtime_root = self.root / "runtime"
        self.runtime_root.mkdir()
        self.runtime_bundle = self.root / "runtime-bundle"
        (self.runtime_bundle / "Contents").mkdir(parents=True)
        (self.runtime_bundle / "Contents/Info.plist").write_bytes(b"synthetic runtime")
        self.runtime = {"identifier": RUNTIME, "platform": "iOS", "version": "27.0",
                        "isAvailable": True, "runtimeRoot": str(self.runtime_root),
                        "bundlePath": str(self.runtime_bundle)}
        self.source = {"udid": SOURCE_DEVICE, "name": "iPad fixture",
                       "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPad",
                       "isAvailable": True}
        self.device = {**self.source, "udid": DEVICE, "name": self.identity["name"]}
        self.before = {"devices": {RUNTIME: [self.source]}}
        self.after = {"devices": {RUNTIME: [self.source, self.device]}}
        self.selection = owned.created_selection(
            {"device": self.source, "runtime": self.runtime}, self.before, self.after,
            self.identity["name"], DEVICE, RUN, ATTEMPT, run_provider="local-mac")
        (self.log / owned.SELECTION_FILE).write_text(json.dumps(self.selection))
        (self.log / "simulator-udid.txt").write_text(DEVICE)
        self.context = {"run_provider": "local-mac", "run_id": RUN, "run_attempt": ATTEMPT,
                        "configuration": "Release", "source_sha": SOURCE_SHA,
                        "selectors": [SELECTOR], "products_root": str(self.products)}

    def boot(self):
        result = subprocess.CompletedProcess(
            ["xcrun", "simctl", "bootstatus", DEVICE, "-b"], 0, "synthetic boot result", "")
        with patch.dict(os.environ, ENV, clear=True):
            return owned.record_owned_boot(self.log, DEVICE, result)

    def prepare_and_seal(self):
        admission.prepare(self.products, self.log, self.context)
        host = self.products / "Release-iphonesimulator/AI_Hanlin.app"
        tests = host / "PlugIns/AI_HLYTests.xctest"
        for path, identifier, executable in [
            (host, admission.HOST_ID, "AI_Hanlin"),
            (tests, admission.TEST_ID, "AI_HLYTests"),
        ]:
            path.mkdir(parents=True, exist_ok=True)
            (path / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": identifier, "CFBundleExecutable": executable}))
            (path / executable).write_bytes(b"synthetic fixture; not a native executable")
        manifest = self.products / "AI_HLY_iphonesimulator-arm64.xctestrun"
        manifest.write_bytes(plistlib.dumps({"AI_HLYTests": {
            "BlueprintName": "AI_HLYTests", "IsUITestBundle": False,
            "TestHostBundleIdentifier": admission.HOST_ID,
            "TestHostPath": "__TESTROOT__/Release-iphonesimulator/AI_Hanlin.app",
            "TestBundlePath": "__TESTHOST__/PlugIns/AI_HLYTests.xctest",
        }}))
        (self.log / "06-xcodebuild-simulator.log").write_text(
            "Synthetic command fixture: xcodebuild build-for-testing\n"
            "** TEST BUILD SUCCEEDED **\n")
        admission.seal(self.products, self.log, self.context)
        return manifest, host

    def test_local_creation_boot_admission_and_calendar_grants_keep_exact_device_and_host(self):
        manifest, host = self.prepare_and_seal()
        self.boot()
        admitted = admission.admit(self.products, self.log, self.context, DEVICE)
        self.assertEqual(admitted, str(manifest))
        calls = []
        def native(command, **kwargs):
            calls.append(command)
            return subprocess.CompletedProcess(command, 0, "synthetic grant result", "")
        receipt = calendar.prepare(SELECTOR, admitted, self.products, self.log, RUN, ATTEMPT,
                                   runner=native, run_provider="local-mac")
        self.assertEqual(calls, [
            ["xcrun", "simctl", "install", DEVICE, str(host)],
            ["xcrun", "simctl", "privacy", DEVICE, "grant", "calendar", admission.HOST_ID],
            ["xcrun", "simctl", "privacy", DEVICE, "grant", "reminders", admission.HOST_ID],
        ])
        self.assertEqual(receipt["owned_simulator"]["run_provider"], "local-mac")
        self.assertEqual(receipt["selected_selectors"], [SELECTOR.removesuffix("()")])
        self.assertNotIn("selected_method", receipt)
        with self.assertRaises(RuntimeError):
            owned.verify_owned_simulator(self.log, RUN, ATTEMPT)
        with self.assertRaises(RuntimeError):
            owned.verify_owned_motion_creation(self.log / owned.SELECTION_FILE, DEVICE,
                                               RUN, ATTEMPT, run_provider="local-mac")

    def test_local_proof_cannot_claim_existing_device_or_accept_failed_boot(self):
        with self.assertRaisesRegex(RuntimeError, "already existed"):
            owned.created_selection(
                {"device": self.source, "runtime": self.runtime}, self.after, self.after,
                self.identity["name"], DEVICE, RUN, ATTEMPT, run_provider="local-mac")
        for simulator, code in [(DEVICE, 124), (SOURCE_DEVICE, 0)]:
            result = subprocess.CompletedProcess(
                ["xcrun", "simctl", "bootstatus", simulator, "-b"], code, "", "")
            with self.subTest(simulator=simulator), self.assertRaises(RuntimeError):
                owned.record_owned_boot(self.log, DEVICE, result, RUN, ATTEMPT,
                                        run_provider="local-mac")
        self.assertFalse((self.log / owned.BOOT_FILE).exists())

    def test_wrong_or_missing_provider_fails_before_calendar_install_or_grants(self):
        manifest, _ = self.prepare_and_seal()
        self.boot()
        path = self.log / owned.BOOT_FILE
        original = json.loads(path.read_text())
        for provider in ["github", None]:
            changed = {**original, "run_provider": provider}
            if provider is None:
                del changed["run_provider"]
            path.write_text(json.dumps(changed))
            with self.subTest(provider=provider):
                with self.assertRaises(RuntimeError):
                    admission.admit(self.products, self.log, self.context, DEVICE)
                with patch.object(calendar, "run_bounded") as native, self.assertRaises(RuntimeError):
                    calendar.prepare(SELECTOR, manifest, self.products, self.log, RUN, ATTEMPT,
                                     runner=native, run_provider="local-mac")
                native.assert_not_called()

    def test_local_build_context_requires_its_actual_source_pin_and_rejects_mixed_identity(self):
        (self.log / "06-diagnostics-build-provenance.json").write_text(json.dumps({
            "sourceCommit": SOURCE_SHA, "trackedWorkspaceModified": False}))
        def git(command, **kwargs):
            if command == ["git", "rev-parse", "HEAD"]:
                return (SOURCE_SHA + "\n").encode()
            if command[:3] == ["git", "diff", "--binary"]:
                return b""
            self.fail("Unexpected native or source query: " + repr(command))
        with patch.object(admission.subprocess, "check_output", side_effect=git), \
                patch.object(admission, "current_xcode_identity", return_value={"xcode_version": "fixture"}):
            with patch.dict(os.environ, ENV, clear=True):
                context = admission.build_context(self.root, self.products, self.log, "Release", SELECTOR)
            self.assertEqual(context["run_provider"], "local-mac")
            self.assertEqual(context["source_sha"], SOURCE_SHA)
            for environment in [
                {k: v for k, v in ENV.items() if k != "HANLIN_LOCAL_SOURCE_SHA"},
                {**ENV, "HANLIN_LOCAL_SOURCE_SHA": "b" * 40},
                {**ENV, "GITHUB_RUN_ID": "123"},
                {**ENV, "GITHUB_ACTIONS": "true"},
            ]:
                with self.subTest(environment=environment), patch.dict(os.environ, environment, clear=True), \
                        self.assertRaises(RuntimeError):
                    admission.build_context(self.root, self.products, self.log, "Release", SELECTOR)

    def test_calendar_selection_covers_mutation_suite_and_methods_without_neighbor_suites(self):
        for selectors in ["AI_HLYTests", calendar.SUITE, calendar.METHOD + "()",
                          calendar.MUTATION_SUITE, SELECTOR, "AI_HLYTests/Unrelated," + SELECTOR]:
            with self.subTest(selectors=selectors):
                self.assertTrue(calendar.selected(selectors))
        for selectors in ["", "AI_HLYTests/CalendarToolTests",
                          "AI_HLYTests/CalendarNativeMutationTestsExtra/eventNotePatchPreservesAlarmAndRecurrence()",
                          "AI_HLYUITests/CalendarNativeMutationTests"]:
            with self.subTest(selectors=selectors):
                self.assertFalse(calendar.selected(selectors))

    def select_cli(self, environment, name):
        commands = []
        self.selection_commands = commands
        def read(command, **kwargs):
            commands.append(command)
            if command[:3] == ["xcrun", "--sdk", "iphonesimulator"]:
                return "27.0"
            if command[2:4] == ["list", "runtimes"]:
                return json.dumps({"runtimes": [self.runtime]})
            if command[2:4] == ["list", "devices"]:
                return json.dumps(self.after if any(c[2] == "create" for c in commands) else self.before)
            if command[2] == "create":
                self.assertEqual(command[3:], [self.identity["name"],
                                              self.source["deviceTypeIdentifier"], RUNTIME])
                return DEVICE
            self.fail("Unexpected command: " + repr(command))
        argv = [str(SCRIPTS / "select_installed_simulator.py"),
                "--output", str(self.log / owned.SELECTION_FILE),
                "--family", "iPad", "--create-owned", name]
        with patch.dict(os.environ, environment, clear=True), patch.object(sys, "argv", argv), \
                patch("subprocess.check_output", side_effect=read), contextlib.redirect_stdout(io.StringIO()):
            runpy.run_path(argv[0], run_name="__main__")
        return commands

    def test_general_create_cli_uses_local_provenance_and_keeps_native_readback(self):
        commands = self.select_cli(ENV, self.identity["name"])
        self.assertEqual(sum(command[2] == "create" for command in commands), 1)
        selected = json.loads((self.log / owned.SELECTION_FILE).read_text())
        self.assertEqual(selected["ownership"]["run_provider"], "local-mac")
        self.assertTrue(selected["ownership"]["absent_before_create"])
        self.assertEqual(selected["source_device"]["udid"], SOURCE_DEVICE)

    def test_general_create_cli_rejects_wrong_name_and_mixed_provider_before_create(self):
        for environment, name in [
            (ENV, "Hanlin-Phase2-local-other-1"),
            ({**ENV, "GITHUB_RUN_ID": "123"}, self.identity["name"]),
            ({**ENV, "HANLIN_LOCAL_RUN_ATTEMPT": "0"}, self.identity["name"]),
        ]:
            with self.subTest(name=name), self.assertRaises((ValueError, RuntimeError)):
                self.select_cli(environment, name)
            self.assertFalse(any(command[2] == "create" for command in self.selection_commands))


if __name__ == "__main__":
    unittest.main()
