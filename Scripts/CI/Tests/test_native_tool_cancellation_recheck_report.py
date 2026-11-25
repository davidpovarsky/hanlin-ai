"""Local report/admission controls only; synthetic current outcomes are not native proof."""
import copy
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Scripts/CI/IntegrationValidation"))
import verify_native_tool_cancellation_recheck as report
from verify_native_tool_candidate import read_cases


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


class NativeCancellationAdmissionTests(unittest.TestCase):
    def setUp(self):
        parent = ROOT / "build/native-cancellation-report-controls"
        parent.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=parent)
        self.evidence = Path(self.temporary.name)
        self.reference = ROOT / report.REFERENCE_PATH
        self.seed()

    def tearDown(self):
        self.temporary.cleanup()

    def seed(self):
        evidence, reference = self.evidence, self.reference
        source = json.loads((reference / "reference.json").read_text())["current_packages_source_commit"]
        for filename in ("tested-source-commit.txt", "workflow-commit.txt"):
            (evidence / filename).write_text(source + "\n")
        (evidence / "producer-commit.txt").write_text(report.PRODUCER + "\n")
        shutil.copy2(reference / "current-source-sha256.json", evidence / "tested-source-sha256.json")
        common = ["Scripts/CI/IntegrationValidation/verify_native_tool_candidate.py",
                  "Scripts/CI/IntegrationValidation/xcresult_to_xunit.py", "Scripts/CI/select_stable_xcode.py"]
        write(evidence / "workflow-sha256.json", {p: report.sha(ROOT / p) for p in common})
        for package in ("core", "sdk"):
            shutil.copy2(reference / "delta" / (package + "-Package.resolved"), evidence / (package + "-Package.resolved"))
        commands = []
        for command in json.loads((reference / "c93/commands.json").read_text()):
            if command["name"] in report.TOOLCHAIN:
                commands.append(copy.deepcopy(command))
                for stream in ("stdout", "stderr"):
                    shutil.copy2(reference / "c93" / command[stream]["file"], evidence / command[stream]["file"])
        write(evidence / "commands.json", commands)
        report.prepare_reuse(ROOT, evidence)
        native_core = [copy.deepcopy(node) for node in read_cases(reference / "c93", "CoreTests")[0]
                       if not node["nodeIdentifier"].startswith(report.CORE_SUITE + "/cloud")]
        native_core += [copy.deepcopy(node) for node in read_cases(reference / "delta", "StopContinuationTests")[0]
                        if node["nodeIdentifier"].startswith(report.DELTA_SUITE + "/native")]
        native_sdk = [copy.deepcopy(node) for node in read_cases(reference / "bridge", "SDKTests")[0]
                      if not node["nodeIdentifier"].startswith(report.BRIDGE_SUITE + "/nativeGenerate")]
        # Construct a synthetic positive parser control. The real cancellation
        # FAIL is separately restored and must remain rejected below.
        for node in native_sdk:
            node["result"] = "Passed"
            node.pop("children", None)
        write(evidence / "NativeCoreTests.json", {"testNodes": native_core})
        write(evidence / "NativeSDKTests.json", {"testNodes": native_sdk})
        write(evidence / "selected-route.json", dict(
            exact_test_selector=report.SELECTOR, target_validation_group="agent_sdk_exact_source_proof",
            baseline="HISTORICAL_REFERENCE_ONLY", run_id="LOCAL_CONTROL_NOT_AN_APPLE_RUN",
            unrelated_flags={key: "false" for key in report.UNRELATED_FLAGS}))
        statuses = dict(preparation_exit=0, native_core_test_exit=0, native_sdk_test_exit=0,
                        ios_build_exit=0, ios_build_execution="EXECUTED",
                        baseline_execution="HISTORICAL_REFERENCE_ONLY", accepted_cases_execution="REUSED_VERIFIED",
                        **{key: None for key in report.OLD_NULL_EXITS})
        write(evidence / "process-status.json", statuses)
        for name, directory, selectors in (
            ("NativeCoreTests", "HanlinPlatform", report.CORE_SELECTORS),
            ("NativeSDKTests", "HanlinAgentSDK", report.SDK_SELECTORS),
            ("IOSBuild", "HanlinAgentSDK", None),
        ):
            if selectors is None:
                argv = ["xcodebuild", "build", "-scheme", "HanlinAgentCore", "-destination",
                        "generic/platform=iOS Simulator", "-derivedDataPath", "/fixture/IOSDerivedData",
                        "-resultBundlePath", "/fixture/IOSBuild.xcresult", "-skipPackagePluginValidation",
                        "-skipMacroValidation", "CODE_SIGNING_ALLOWED=NO"]
            else:
                argv = ["xcodebuild", "test", "-scheme", directory, "-destination", "platform=macOS",
                        "-derivedDataPath", "/fixture/MacDerivedData", "-resultBundlePath", "/fixture/" + name + ".xcresult",
                        "-skipPackagePluginValidation", "-skipMacroValidation", "CODE_SIGNING_ALLOWED=NO"]
                argv += ["-only-testing:" + value for value in selectors]
            command = dict(name=name, argv=argv, cwd="/fixture/Packages/" + directory, exit_code=0)
            for stream in ("stdout", "stderr"):
                path = evidence / (name + "." + stream + ".log")
                path.write_text("LOCAL REPORT CONTROL\n** BUILD SUCCEEDED **\n" if stream == "stdout" else "")
                command[stream] = dict(file=path.name, sha256=report.sha(path))
            commands.append(command)
        write(evidence / "commands.json", commands)
        (evidence / "raw-locks").mkdir()
        posts, checkouts = [], {}
        producer_map = json.loads((reference / "producer-07431-sha256.json").read_text())
        for package, directory in (("core", "HanlinPlatform"), ("sdk", "HanlinAgentSDK")):
            relative = "raw-locks/" + package + "-Package.resolved"
            shutil.copy2(evidence / (package + "-Package.resolved"), evidence / relative)
            posts.append(dict(source_path="/fixture/Packages/" + directory + "/Package.resolved",
                              raw_file=relative, sha256=report.sha(evidence / relative)))
            checkouts[package] = dict(path="/fixture/Packages/" + directory + "/.build/checkouts/swift-ai-sdk",
                                     commit=report.PRODUCER, status="", source_sha256=producer_map)
        write(evidence / "post-build-resolution.json", posts)
        write(evidence / "producer-checkouts.json", checkouts)

    def mutate_and_reject(self, filename, mutate):
        path = self.evidence / filename
        original = path.read_bytes()
        data = json.loads(original)
        mutate(data)
        write(path, data)
        self.assertEqual(report.summarize(self.evidence)["status"], "BLOCKED")
        path.write_bytes(original)

    def test_complete_partition_preserves_original_attribution(self):
        result = report.summarize(self.evidence)
        self.assertEqual(result["errors"], [])
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(len(result["cases"]), 15)
        self.assertEqual(len(result["methods"]), 7)
        self.assertEqual(len(result["reused_cases"]), 21)
        self.assertEqual({row["run_id"] for row in result["reused_cases"]},
                         {45259715158, 45273580428, 45282347722, 45273687114})
        baseline = result["reuse_admission"]["historical_baseline_cases"]
        self.assertEqual(sum(row["status"] == "FAIL" for row in baseline), 10)
        self.assertEqual(sum(row["status"] == "PASS" for row in baseline), 2)
        self.assertTrue(all(row["execution"] == "HISTORICAL_REFERENCE_ONLY" for row in baseline))
        self.assertFalse(result["historical_baseline_current_equivalence"])

    def test_selectors_bind_authentic_identifiers_and_block_old_basenames(self):
        actual_core = {"HanlinChatCoreTests/" + node["nodeIdentifier"]
                       for node in read_cases(self.reference / "c93", "CoreTests")[0]
                       if not node["nodeIdentifier"].startswith(report.CORE_SUITE + "/cloud")}
        actual_core |= {"HanlinChatCoreTests/" + node["nodeIdentifier"]
                        for node in read_cases(self.reference / "delta", "StopContinuationTests")[0]
                        if node["nodeIdentifier"].startswith(report.DELTA_SUITE + "/native")}
        actual_sdk = {"HanlinAgentCoreTests/" + node["nodeIdentifier"]
                      for node in read_cases(self.reference / "bridge", "SDKTests")[0]
                      if not node["nodeIdentifier"].startswith(report.BRIDGE_SUITE + "/nativeGenerate")}
        self.assertEqual(set(report.CORE_SELECTORS), actual_core)
        self.assertEqual(set(report.SDK_SELECTORS), actual_sdk)
        def omit_signatures(commands):
            for command in commands:
                command["argv"] = [value.split("(", 1)[0] if value.startswith("-only-testing:") else value
                                   for value in command["argv"]]
        self.mutate_and_reject("commands.json", omit_signatures)
        self.mutate_and_reject("selected-route.json", lambda data: data["unrelated_flags"].update(runtime_publish_release="true"))
        self.mutate_and_reject("process-status.json", lambda data: data.update(baseline_core_exit=0))
        self.mutate_and_reject("process-status.json", lambda data: data.update(baseline_execution="REUSED_VERIFIED"))
        self.mutate_and_reject("process-status.json", lambda data: data.update(ios_build_exit=None, ios_build_execution="REUSED_VERIFIED"))

    def test_source_toolchain_and_checkout_changes_block_reuse(self):
        self.mutate_and_reject("tested-source-sha256.json", lambda data: data.update(
            {"Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinAISDKAgentEngine.swift": "0" * 64}))
        self.mutate_and_reject("producer-checkouts.json", lambda data: data["core"].update(commit=report.OLD_PRODUCER))
        self.mutate_and_reject("producer-checkouts.json", lambda data: data["core"].update(path=data["sdk"]["path"]))
        self.mutate_and_reject("producer-checkouts.json", lambda data: data["sdk"].update(status=" M Sources/changed.swift"))
        self.mutate_and_reject("sdk-Package.resolved", lambda data: data["pins"][0]["state"].update(revision=report.OLD_PRODUCER))
        self.mutate_and_reject("cancellation-reuse-original/bridge/SDKTests.json",
                               lambda data: data.update(unreviewed_fixture_mutation=True))
        self.mutate_and_reject("commands.json", lambda data: next(
            command for command in data if command["name"] == "swift")["stdout"].update(sha256="0" * 64))

    def test_original_cancellation_failure_and_missing_parameter_remain_failures(self):
        original_cancel = next(node for node in read_cases(self.reference / "bridge", "SDKTests")[0]
                               if node["nodeIdentifier"].startswith(report.BRIDGE_SUITE + "/nativeCancellation"))
        original = (self.evidence / "NativeSDKTests.json").read_bytes()
        data = json.loads(original)
        data["testNodes"] = [copy.deepcopy(original_cancel) if node["nodeIdentifier"] == original_cancel["nodeIdentifier"]
                             else node for node in data["testNodes"]]
        write(self.evidence / "NativeSDKTests.json", data)
        statuses = json.loads((self.evidence / "process-status.json").read_text())
        statuses["native_sdk_test_exit"] = 65
        write(self.evidence / "process-status.json", statuses)
        commands = json.loads((self.evidence / "commands.json").read_text())
        next(command for command in commands if command["name"] == "NativeSDKTests")["exit_code"] = 65
        write(self.evidence / "commands.json", commands)
        result = report.summarize(self.evidence)
        self.assertEqual(result["status"], "BLOCKED")
        self.assertEqual(sum(row["status"] == "FAIL" for row in result["cases"]), 1)
        self.assertEqual(result["ios_agent_core_compile"], "PASS")
        self.assertEqual(result["current_ios_build"]["mode"], "EXECUTED")
        (self.evidence / "NativeSDKTests.json").write_bytes(original)
        statuses["native_sdk_test_exit"] = 0
        write(self.evidence / "process-status.json", statuses)
        next(command for command in commands if command["name"] == "NativeSDKTests")["exit_code"] = 0
        write(self.evidence / "commands.json", commands)
        def remove_argument(data):
            target = next(node for node in data["testNodes"] if node["nodeIdentifier"].startswith(
                report.CORE_SUITE + "/nativeNumericInput"))
            target["children"] = target["children"][1:]
        self.mutate_and_reject("NativeCoreTests.json", remove_argument)


if __name__ == "__main__":
    unittest.main()
