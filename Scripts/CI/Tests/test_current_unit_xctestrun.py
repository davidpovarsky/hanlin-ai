from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from types import SimpleNamespace

SCRIPT_PATH = Path(__file__).resolve().parents[1] / "current_unit_xctestrun.py"
sys.path.insert(0, str(SCRIPT_PATH.parent))
SPEC = importlib.util.spec_from_file_location("current_unit_xctestrun", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
admission = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(admission)
from owned_simulator_receipts import created_selection, record_owned_boot

# The actual 12 requested selectors from DATA run 44451321578, not a smaller
# provider-only replacement. The workflow preserves its supplied selector list.
DATA_SELECTORS = ['AI_HLYTests/HanlinAppAgentSessionOwnerTests', 'AI_HLYTests/RuntimeAutonomyV3Tests/nativeKeychainReplacementPreservesOriginalServiceIsolation()', 'AI_HLYTests/RuntimeAutonomyV3Tests/runtimeEnvironmentCommitFailurePreservesTheOriginalSecret(operation:)', 'AI_HLYTests/RuntimeAutonomyV3Tests/mcpEnvironmentPrimaryWriteFailureRetainsBothDurableGenerations()', 'AI_HLYTests/RuntimeAutonomyV3Tests/mcpEnvironmentUnknownReadAfterBackupCommitPreservesTheStagedCredential()', 'AI_HLYTests/RuntimeAutonomyV3Tests/mcpEnvironmentPrecommitFailureKeepsOriginalSecretAndRemovesOnlyStagedValue()', 'AI_HLYTests/RuntimeAutonomyV3Tests/mcpEnvironmentEditPreservesOtherFieldsSharedReferencesAndRejectsStaleDraft()', 'AI_HLYTests/RuntimeAutonomyV3Tests/savedEnvironmentPrecedenceFollowsScopesAndPreservesUserPaths()', 'AI_HLYTests/HanlinUnifiedHostServicesTests/authorizedAttachmentRegistryCrossChatDenial()', 'AI_HLYTests/AgentSkillsExposureTests/fullSDKSkillToToolFlow()', 'AI_HLYTests/ClassicChatRestorationTests/mcpInstallSelectInvokeUninstallE2E()', 'AI_HLYTests/HanlinAppSplitOriginTests']
DEVICE = "10000000-0000-4000-8000-000000000001"
SOURCE_DEVICE = "10000000-0000-4000-8000-000000000002"


class CurrentUnitXctestrunTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.products = self.root / "build/SimulatorDerivedData/Build/Products"
        self.log = self.root / "simulator-logs"
        self.products.mkdir(parents=True)
        self.log.mkdir()
        self.host = self.products / "Debug-iphonesimulator/AI_Hanlin.app"
        self.tests = self.host / "PlugIns/AI_HLYTests.xctest"
        self.context = {
            "run_id": "44451321578", "run_attempt": "1", "source_sha": "0" * 40,
            "configuration": "Debug", "selectors": DATA_SELECTORS,
            "products_root": str(self.products), "developer_directory": "/Synthetic/Xcode/Developer",
            "xcode_version": "Synthetic Xcode fixture",
            "tracked_diff_sha256": "1" * 64, "tracked_workspace_modified": True,
            "diagnostics_provenance_sha256": "2" * 64,
            "diagnostics_tracked_workspace_modified": True,
        }

    def bundle(self, path, identifier, executable):
        path.mkdir(parents=True, exist_ok=True)
        (path / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": identifier, "CFBundleExecutable": executable}))
        (path / executable).write_bytes(b"synthetic test file; not native binary")

    def target(self):
        return {
            "BlueprintName": "AI_HLYTests", "IsUITestBundle": False,
            "TestHostBundleIdentifier": "com.itorah.chavrusachat",
            "TestHostPath": "__TESTROOT__/Debug-iphonesimulator/AI_Hanlin.app",
            "TestBundlePath": "__TESTHOST__/PlugIns/AI_HLYTests.xctest",
            "EnvironmentVariables": {"ORIGINAL_TEST_SETTING": "unchanged"},
        }

    def generated(self, version=1, document=None):
        self.bundle(self.host, "com.itorah.chavrusachat", "AI_Hanlin")
        self.bundle(self.tests, "com.itorah.chavrusachat.tests", "AI_HLYTests")
        (self.host / "AI_Hanlin.debug.dylib").write_bytes(b"original synthetic app code")
        if document is None:
            document = ({"AI_HLYTests": self.target()} if version == 1 else {
                "__xctestrun_metadata__": {"FormatVersion": 2},
                "TestConfigurations": [{"Name": "Default", "IsEnabled": True,
                                        "TestTargets": [self.target()]}],
            })
        path = self.products / "AI_HLY_iphonesimulator-arm64.xctestrun"
        path.write_bytes(plistlib.dumps(document))
        (self.log / "06-xcodebuild-simulator.log").write_text(
            "Command line invocation:\nxcodebuild original-selector-flags build-for-testing\n"
            "** TEST BUILD SUCCEEDED **\n", encoding="utf-8")
        return path

    def owned_device(self):
        device = {"udid": SOURCE_DEVICE, "name": "Original iPad",
                  "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPad",
                  "isAvailable": True}
        selected = {"device": device,
                    "runtime": {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-2"}}
        runtime = selected["runtime"]["identifier"]
        name = "Hanlin-Phase2-" + self.context["run_id"] + "-" + self.context["run_attempt"]
        created = {**device, "udid": DEVICE, "name": name}
        proof = created_selection(selected, {"devices": {runtime: [device]}},
                                  {"devices": {runtime: [device, created]}},
                                  name, DEVICE, self.context["run_id"], self.context["run_attempt"])
        (self.log / "verified-simulator-environment.json").write_text(json.dumps(proof))
        (self.log / "simulator-udid.txt").write_text(DEVICE)
        record_owned_boot(self.log, DEVICE, SimpleNamespace(
            args=["xcrun", "simctl", "bootstatus", DEVICE, "-b"],
            returncode=0, stdout="synthetic boot receipt", stderr=""),
            self.context["run_id"], self.context["run_attempt"])

    def prepare(self):
        admission.prepare(self.products, self.log, self.context)

    def seal(self):
        return admission.seal(self.products, self.log, self.context)

    def test_current_v1_products_preserve_all_original_selectors_and_manifest_bytes(self):
        old = self.generated()
        old_bytes = old.read_bytes()
        self.prepare()
        self.assertFalse(old.exists())
        self.assertEqual((self.log / "prior-unit-xctestrun" / old.name).read_bytes(), old_bytes)
        current = self.generated()
        raw = current.read_bytes()
        self.seal()
        self.owned_device()
        self.assertEqual(admission.admit(self.products, self.log, self.context, DEVICE), str(current.resolve()))
        self.assertEqual(current.read_bytes(), raw)
        self.assertEqual((self.log / "06-generated-unit.xctestrun").read_bytes(), raw)
        record = json.loads((self.log / admission.ADMISSION).read_bytes())
        self.assertEqual(record["context"]["selectors"], DATA_SELECTORS)
        self.assertEqual(len(record["context"]["selectors"]), 12)
        self.assertTrue(record["context"]["diagnostics_tracked_workspace_modified"])
        self.assertEqual(record["status"], "ADMITTED_NOT_EXECUTED")

    def test_current_v2_preserves_environment_and_ignores_disabled_configuration(self):
        self.prepare()
        doc = {"__xctestrun_metadata__": {"FormatVersion": 2},
               "TestConfigurations": [
                   {"Name": "Default", "IsEnabled": True, "TestTargets": [self.target()]},
                   {"Name": "Disabled", "IsEnabled": False, "TestTargets": [self.target()]}]}
        path = self.generated(document=doc)
        raw = path.read_bytes()
        self.assertEqual(self.seal()["products"]["format_version"], 2)
        self.assertEqual(path.read_bytes(), raw)
        self.assertEqual(plistlib.loads(raw)["TestConfigurations"][0]["TestTargets"][0][
            "EnvironmentVariables"], {"ORIGINAL_TEST_SETTING": "unchanged"})

    def test_previous_cached_manifest_cannot_satisfy_current_build(self):
        self.generated()
        self.prepare()
        with self.assertRaisesRegex(RuntimeError, "exactly one current"):
            self.seal()

    def test_two_generated_manifests_are_ambiguous(self):
        self.prepare()
        path = self.generated()
        (self.products / "another.xctestrun").write_bytes(path.read_bytes())
        with self.assertRaisesRegex(RuntimeError, "exactly one current"):
            self.seal()
        retained = self.log / "06-generated-unit-manifests"
        self.assertEqual((retained / path.name).read_bytes(), path.read_bytes())
        self.assertEqual((retained / "another.xctestrun").read_bytes(), path.read_bytes())

    def test_rejected_native_manifest_format_retains_exact_current_bytes(self):
        self.prepare()
        path = self.generated()
        raw = plistlib.dumps({"__xctestrun_metadata__": {"FormatVersion": 999},
                             "FutureNativeField": {"original": "retained without interpretation"}})
        path.write_bytes(raw)
        with self.assertRaisesRegex(RuntimeError, "Unsupported .xctestrun"):
            self.seal()
        retained = self.log / "06-generated-unit-manifests" / path.name
        self.assertEqual(retained.read_bytes(), raw)
        index = json.loads((self.log / "06-generated-unit-manifests.json").read_bytes())
        self.assertEqual(index, [{"name": path.name, "bytes": len(raw),
                                  "sha256": admission.sha256(path)}])
        self.assertEqual(json.loads((self.log / admission.RECEIPT).read_bytes())["status"], "PREPARED")

    def test_absent_wrong_disabled_or_ambiguous_original_target_rejected(self):
        wrong = self.target()
        wrong["BlueprintName"] = "UnrelatedTests"
        disabled = self.target()
        disabled["IsEnabled"] = False
        ui = self.target()
        ui["IsUITestBundle"] = True
        documents = [
            {"OtherTests": wrong}, {"AI_HLYTests": wrong},
            {"AI_HLYTests": disabled}, {"AI_HLYTests": ui},
            {"__xctestrun_metadata__": {"FormatVersion": 99}},
            {"__xctestrun_metadata__": {"FormatVersion": 2},
             "TestConfigurations": [{"TestTargets": [self.target(), self.target()]}]},
            {"__xctestrun_metadata__": {"FormatVersion": 2},
             "TestConfigurations": [{"IsEnabled": "false", "TestTargets": [self.target()]}]},
        ]
        for document in documents:
            with self.subTest(document=document), self.assertRaises(RuntimeError):
                admission.original_unit_target(document)

    def test_wrong_host_identity_configuration_and_bundle_identity_rejected(self):
        self.prepare()
        path = self.generated()
        for field, value in [
            ("TestHostBundleIdentifier", "com.example.other"),
            ("TestHostPath", "__TESTROOT__/Release-iphonesimulator/AI_Hanlin.app"),
            ("TestBundlePath", "__TESTHOST__/PlugIns/UnrelatedTests.xctest"),
        ]:
            target = self.target()
            target[field] = value
            path.write_bytes(plistlib.dumps({"AI_HLYTests": target}))
            with self.subTest(field=field), self.assertRaises((RuntimeError, OSError)):
                self.seal()
        path.write_bytes(plistlib.dumps({"AI_HLYTests": self.target()}))
        self.bundle(self.tests, "com.example.foreign.tests", "AI_HLYTests")
        with self.assertRaisesRegex(RuntimeError, "bundle identity"):
            self.seal()

    def test_missing_original_test_binary_fails_before_execution(self):
        self.prepare()
        self.generated()
        (self.tests / "AI_HLYTests").unlink()
        with self.assertRaises(FileNotFoundError):
            self.seal()

    def test_unresolved_or_outside_product_path_rejected(self):
        self.prepare()
        path = self.generated()
        for value in ["__FOREIGN_ROOT__/AI_HLYTests.xctest", str(self.root), "relative/app"]:
            target = self.target()
            target["TestBundlePath"] = value
            path.write_bytes(plistlib.dumps({"AI_HLYTests": target}))
            with self.subTest(value=value), self.assertRaises(RuntimeError):
                self.seal()

    def test_symlinked_external_test_binary_is_rejected(self):
        self.prepare()
        self.generated()
        binary = self.tests / "AI_HLYTests"
        binary.unlink()
        outside = self.root / "external-binary"
        outside.write_bytes(b"foreign executable")
        try:
            binary.symlink_to(outside)
        except OSError as error:
            self.skipTest("Host cannot create a test symlink: " + str(error))
        with self.assertRaisesRegex(RuntimeError, "escapes"):
            self.seal()

    def test_manifest_test_binary_and_actual_debug_app_code_cannot_change_after_seal(self):
        self.prepare()
        manifest = self.generated()
        self.seal()
        self.owned_device()
        paths = [manifest, self.tests / "AI_HLYTests", self.host / "AI_Hanlin.debug.dylib",
                 self.tests / "Info.plist"]
        for path in paths:
            previous = path.read_bytes()
            path.write_bytes(previous + b"\n")
            with self.subTest(path=path.name), self.assertRaises(RuntimeError):
                admission.admit(self.products, self.log, self.context, DEVICE)
            path.write_bytes(previous)
        self.assertFalse((self.log / admission.ADMISSION).exists())

    def test_context_cannot_cross_run_attempt_source_toolchain_selector_or_dirty_inputs(self):
        self.prepare()
        self.generated()
        self.seal()
        fields = {
            "run_id": "2", "run_attempt": "2", "source_sha": "3" * 40,
            "configuration": "Release", "selectors": DATA_SELECTORS[:-1],
            "developer_directory": "/Other/Xcode", "xcode_version": "Other Xcode",
            "tracked_diff_sha256": "4" * 64,
            "diagnostics_provenance_sha256": "5" * 64,
        }
        for field, value in fields.items():
            context = {**self.context, field: value}
            with self.subTest(field=field), self.assertRaisesRegex(RuntimeError, "changed"):
                admission.admit(self.products, self.log, context, DEVICE)

    def test_failed_or_non_test_build_cannot_be_sealed(self):
        self.prepare()
        self.generated()
        log = self.log / "06-xcodebuild-simulator.log"
        for value in ["xcodebuild build-for-testing\n** TEST BUILD FAILED **\n",
                      "xcodebuild build\n** TEST BUILD SUCCEEDED **\n"]:
            log.write_text(value)
            with self.subTest(value=value), self.assertRaisesRegex(RuntimeError, "successful build-for-testing"):
                self.seal()

    def test_missing_or_wrong_owned_boot_receipt_and_destination_rejected(self):
        self.prepare()
        self.generated()
        self.seal()
        with self.assertRaises(FileNotFoundError):
            admission.admit(self.products, self.log, self.context, DEVICE)
        self.owned_device()
        with self.assertRaisesRegex(RuntimeError, "destination"):
            admission.admit(self.products, self.log, self.context, SOURCE_DEVICE)
        boot_path = self.log / "08-owned-simulator-boot.json"
        boot = json.loads(boot_path.read_bytes())
        boot["run_attempt"] = "2"
        boot_path.write_text(json.dumps(boot))
        with self.assertRaisesRegex(RuntimeError, "boot receipt"):
            admission.admit(self.products, self.log, self.context, DEVICE)
        self.assertFalse((self.log / admission.ADMISSION).exists())

    def test_prepared_receipt_does_not_admit_and_cannot_be_silently_overwritten(self):
        self.prepare()
        self.generated()
        with self.assertRaisesRegex(RuntimeError, "wrong phase"):
            admission.admit(self.products, self.log, self.context, DEVICE)
        with self.assertRaisesRegex(RuntimeError, "already exists"):
            self.prepare()

    def test_selector_validation_retains_parameterized_methods_and_rejects_other_target(self):
        self.assertEqual(admission.selected_identifiers(",".join(DATA_SELECTORS)), DATA_SELECTORS)
        for selectors in ["", "AI_HLYUITests/SomeCase", "AI_HLYTests/with whitespace"]:
            with self.subTest(selectors=selectors), self.assertRaises(RuntimeError):
                admission.selected_identifiers(selectors)

    def test_build_context_reads_actual_git_revision_dirty_diff_and_provenance(self):
        def git(*arguments):
            return subprocess.check_output(["git", "-c", "core.hooksPath=" + str(self.root / "no-hooks"),
                                            *arguments], cwd=self.root, stderr=subprocess.DEVNULL)
        git("init")
        source = self.root / "original.swift"
        source.write_text("let original = 1\n")
        git("add", "original.swift")
        git("-c", "user.name=CI Fixture", "-c", "user.email=ci-fixture@example.invalid",
            "commit", "-m", "Synthetic fixture")
        head = git("rev-parse", "HEAD").decode().strip()
        provenance = self.log / "06-diagnostics-build-provenance.json"
        provenance.write_text(json.dumps({"sourceCommit": head, "trackedWorkspaceModified": False}))
        real_command = subprocess.check_output
        observed = []

        def command(arguments, **kwargs):
            observed.append(arguments)
            if arguments == ["xcode-select", "-p"]:
                return b"/Synthetic/Xcode/Developer\n"
            if arguments == ["xcodebuild", "-version"]:
                return b"Synthetic Xcode fixture\n"
            return real_command(arguments, **kwargs)

        with mock.patch.dict(os.environ, {"GITHUB_RUN_ID": self.context["run_id"],
                                         "GITHUB_RUN_ATTEMPT": "1", "GITHUB_SHA": head}), \
                mock.patch.object(admission.subprocess, "check_output", side_effect=command):
            before = admission.build_context(self.root, self.products, self.log, "Debug",
                                             ",".join(DATA_SELECTORS))
            self.assertFalse(before["tracked_workspace_modified"])
            source.write_text("let original = 2\n")
            after = admission.build_context(self.root, self.products, self.log, "Debug",
                                            ",".join(DATA_SELECTORS))
            self.assertTrue(after["tracked_workspace_modified"])
            self.assertNotEqual(before["tracked_diff_sha256"], after["tracked_diff_sha256"])
            provenance.write_text(json.dumps({"sourceCommit": "f" * 40, "trackedWorkspaceModified": True}))
            with self.assertRaisesRegex(RuntimeError, "different source"):
                admission.build_context(self.root, self.products, self.log, "Debug", "AI_HLYTests")
        self.assertTrue(all("-resolvePackageDependencies" not in args and "-project" not in args
                            and "-scheme" not in args for args in observed))
        self.assertIn(
            ["git", "--no-optional-locks", "rev-parse", "HEAD"],
            observed,
        )
        self.assertIn(
            ["git", "--no-optional-locks", "diff", "--binary", "--no-ext-diff", "--no-textconv", "HEAD", "--", "."],
            observed,
        )

    def test_git_command_retries_only_timeout_expired_with_backoff_and_enforces_total_budget(self):
        calls = []
        sleeps = []
        now = [100.0]

        def clock():
            return now[0]

        def sleeper(seconds):
            sleeps.append(seconds)
            now[0] += seconds

        def transient_then_ok(arguments, *, cwd, timeout):
            calls.append((arguments, timeout))
            if len(calls) < 3:
                now[0] += 10.0
                raise subprocess.TimeoutExpired(arguments, timeout)
            return b"deadbeef\n"

        with mock.patch.object(admission.subprocess, "check_output", side_effect=transient_then_ok):
            result = admission.run_git_command(
                ["git", "--no-optional-locks", "rev-parse", "HEAD"],
                cwd=self.root, timeout_seconds=30, deadline=160.0,
                retry_delays=(2.0, 5.0), sleeper=sleeper, clock=clock)
        self.assertEqual(result, b"deadbeef\n")
        self.assertEqual(len(calls), 3)
        self.assertEqual(sleeps, [2.0, 5.0])

        error_calls = []

        def fail_once(arguments, *, cwd, timeout):
            error_calls.append(arguments)
            raise subprocess.CalledProcessError(128, arguments)

        with mock.patch.object(admission.subprocess, "check_output", side_effect=fail_once):
            with self.assertRaises(subprocess.CalledProcessError):
                admission.run_git_command(
                    ["git", "--no-optional-locks", "rev-parse", "HEAD"],
                    cwd=self.root, timeout_seconds=30, deadline=160.0,
                    retry_delays=(2.0, 5.0), sleeper=sleeper, clock=clock)
        self.assertEqual(len(error_calls), 1)

        def always_timeout(arguments, *, cwd, timeout):
            now[0] += timeout
            raise subprocess.TimeoutExpired(arguments, timeout)

        now[0] = 200.0
        with mock.patch.object(admission.subprocess, "check_output", side_effect=always_timeout):
            with self.assertRaises(subprocess.TimeoutExpired):
                admission.run_git_command(
                    ["git", "--no-optional-locks", "diff", "--binary", "--no-ext-diff", "--no-textconv", "HEAD", "--", "."],
                    cwd=self.root, timeout_seconds=30, deadline=225.0,
                    retry_delays=(2.0, 5.0), sleeper=sleeper, clock=clock)

        now[0] = 300.0
        with mock.patch.object(admission.subprocess, "check_output", side_effect=always_timeout):
            with self.assertRaisesRegex(RuntimeError, "total run time budget"):
                admission.run_git_command(
                    ["git", "--no-optional-locks", "rev-parse", "HEAD"],
                    cwd=self.root, timeout_seconds=30, deadline=299.0,
                    retry_delays=(2.0, 5.0), sleeper=sleeper, clock=clock)

    def test_workflow_unit_route_preserves_destination_filters_limits_and_result_gate(self):
        workflow = (SCRIPT_PATH.parents[2] / ".github/workflows/build-ios26-unsigned-ipa.yml").read_text(
            encoding="utf-8")
        self.assertGreater(
            workflow.index("      - name: Save successful simulator compiler state\n"),
            workflow.index("      - name: Run simulator test suite\n"),
        )
        unit = workflow.split("      - name: Run simulator test suite\n", 1)[1].split(
            '            if [ "${STAGE_NATIVESCRIPT_AFTER_UNIT:-false}"', 1)[0]
        command = unit.split("              xcodebuild test-without-building \\\n", 1)[1].split(
            '              2>&1 | tee "$LOG_DIR/08-downstream-unit-tests.log"', 1)[0]
        for prohibited in ["-project", "-scheme", "-derivedDataPath", "-clonedSourcePackagesDirPath"]:
            self.assertNotIn(prohibited, command)
        for retained in [
            '-xctestrun "$unit_xctestrun"',
            '-destination "platform=iOS Simulator,id=$SIMULATOR_UDID"',
            '-resultBundlePath "$LOG_DIR/DownstreamTestsResult.xcresult"',
            "-parallel-testing-enabled NO", "-test-timeouts-enabled YES",
            '-maximum-test-execution-time-allowance "$unit_time_allowance"', '"${unit_test_args[@]}"',
        ]:
            self.assertIn(retained, command)
        self.assertIn('unit_test_args+=("-only-testing:$suite")', unit)
        self.assertIn("Scripts/CI/verify_selected_tests.py", unit)
        self.assertLess(unit.index("current_unit_xctestrun.py admit"), unit.index("              set +e\n"))


if __name__ == "__main__":
    unittest.main()
