"""New bridge report controls only: fixtures are never native execution evidence."""
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
import reuse_native_tool_baseline as baseline
import verify_native_tool_bridge_recheck as bridge
from verify_native_tool_candidate import read_cases


def read(path):
    return json.loads(path.read_text())


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


class BridgeRecheckReportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.evidence = Path(self.temp.name)
        self.earlier = ROOT / bridge.REFERENCE_PATH
        self.negative = ROOT / bridge.NEGATIVE_REFERENCE_PATH
        names = ["core-Package.resolved", "sdk-Package.resolved", "producer-commit.txt",
                 "tested-source-sha256.json", "workflow-sha256.json"]
        commands = read(self.negative / "commands.json")
        kept = [command for command in commands if command["name"] in
                set(bridge.TOOLCHAIN) | {"select-xcode", "producer-clean"}]
        for command in kept:
            names += [command[stream]["file"] for stream in ("stdout", "stderr")]
        for name in names:
            shutil.copyfile(self.negative / name, self.evidence / name)
        sources = read(self.evidence / "tested-source-sha256.json")
        sources.update(bridge.PERMITTED_SOURCE)
        write(self.evidence / "tested-source-sha256.json", sources)
        for index, relative in enumerate(bridge.PERMITTED_SOURCE):
            shutil.copyfile(ROOT / relative, self.evidence / f"source-current-{index}.swift")
        for name in ("tested-source-commit.txt", "workflow-commit.txt"):
            (self.evidence / name).write_text("EXPLICIT_LOCAL_BRIDGE_REPORT_FIXTURE\n")
        variant = read(ROOT / baseline.REFERENCE_PATH / "baseline-variant.json")
        for relative in variant["files"]:
            variant["files"][relative]["candidate_sha256"] = sources[relative]
        write(self.evidence / "baseline-variant.json", variant)

        def fixture_command(name, argv, output):
            streams = {}
            for stream, content in (("stdout", output), ("stderr", "")):
                path = self.evidence / (name + "-fixture." + stream + ".log")
                path.write_text(content)
                streams[stream] = dict(file=path.name, sha256=hashlib.sha256(path.read_bytes()).hexdigest())
            return dict(name=name, argv=argv, cwd="/EXPLICIT_FIXTURE/Packages/HanlinAgentSDK",
                        exit_code=0, **streams)

        kept += [fixture_command("SDKTests", [
            "xcodebuild", "test", "-scheme", "HanlinAgentSDK-Package", "-destination", "platform=macOS",
            "-derivedDataPath", "/EXPLICIT_FIXTURE/MacDerivedData",
            "-resultBundlePath", "/EXPLICIT_FIXTURE/SDKTests.xcresult",
            "-skipPackagePluginValidation", "-skipMacroValidation", "CODE_SIGNING_ALLOWED=NO",
            *["-only-testing:" + selector for selector in bridge.BRIDGE_SELECTORS]],
            "REPORT CONTROL FIXTURE ONLY: not a native run\n")]
        kept += [fixture_command("IOSBuild", [
            "xcodebuild", "build", "-scheme", "HanlinAgentCore", "-destination", "generic/platform=iOS Simulator",
            "-derivedDataPath", "/EXPLICIT_FIXTURE/IOSDerivedData",
            "-resultBundlePath", "/EXPLICIT_FIXTURE/IOSBuild.xcresult",
            "-skipPackagePluginValidation", "-skipMacroValidation", "CODE_SIGNING_ALLOWED=NO"],
            "REPORT CONTROL FIXTURE ONLY\n** BUILD SUCCEEDED **\n")]
        write(self.evidence / "commands.json", kept)
        baseline.prepare_reuse(ROOT, self.evidence)
        bridge.prepare_bridge_reuse(ROOT, self.evidence)
        posts = []
        for index, (package, directory) in enumerate((("core", "HanlinPlatform"), ("sdk", "HanlinAgentSDK"))):
            raw = self.evidence / (package + "-Package.resolved")
            posts.append(dict(source_path="/EXPLICIT_FIXTURE/Packages/" + directory + "/Package.resolved",
                              raw_file=raw.name, sha256=hashlib.sha256(raw.read_bytes()).hexdigest()))
        write(self.evidence / "post-build-resolution.json", posts)
        original_cases = read_cases(self.earlier, "SDKTests")[0]
        wanted = set(bridge.BRIDGE_SELECTORS)
        cases = []
        for original in original_cases:
            if "HanlinAgentCoreTests/" + original["nodeIdentifier"] in wanted:
                case = copy.deepcopy(original)
                case["result"] = "Passed"
                case.pop("children", None)
                cases.append(case)
        write(self.evidence / "SDKTests.json", dict(testNodes=cases))
        write(self.evidence / "process-status.json",
              dict(preparation_exit=0, baseline_core_exit=None, core_test_exit=None,
                   sdk_test_exit=0, ios_build_exit=0, baseline_execution="REUSED_VERIFIED",
                   accepted_cases_execution="REUSED_VERIFIED", ios_build_execution="EXECUTED"))

    def tearDown(self):
        self.temp.cleanup()


    def test_five_affected_methods_are_separate_from_27_plus_one_and_baseline12(self):
        report = bridge.summarize_bridge_recheck(self.evidence)
        self.assertEqual(report["status"], "PASS", report["errors"])
        self.assertEqual(len(report["cases"]), 5)
        self.assertEqual(report["reused_invocations"], 28)
        reused = report["reused_cases"]
        self.assertEqual(sum(row["run_id"] == 45259715158 for row in reused), 27)
        self.assertEqual([row["id"] for row in reused if row["run_id"] == 45273580428], [bridge.NEGATIVE_ID])
        self.assertNotIn("HanlinAppleToolSessionBridgeTests/nativeGeneratePreservesToolCalls",
                         {row["id"] for row in reused})
        self.assertEqual(len(report["baseline_cases"]), 12)
        self.assertEqual(sum(row["status"] == "FAIL" for row in report["baseline_cases"]), 10)
        self.assertIsNone(report["process_status"]["core_test_exit"])
        self.assertIsNone(report["process_status"]["baseline_core_exit"])
        self.assertEqual(report["current_ios_build"]["mode"], "EXECUTED")
        self.assertEqual(report["reuse_admission"]["source_partition"]["unchanged_core_files"], 238)

    def test_selector_audit_uses_authentic_ids_and_rejects_previous_header_scope(self):
        authentic = {
            "HanlinAgentCoreTests/" + row["nodeIdentifier"]
            for row in read_cases(self.earlier, "SDKTests")[0]
            if row["nodeIdentifier"].split("(", 1)[0] in {
                "HanlinAppleToolSessionBridgeTests/" + name for name in
                ("nativeFrameworkHandoffUsesCanonicalExecutorAndHistory",
                 "nativeDenialReturnsThroughCanonicalHistory", "nativeNumericSiblingCannotPartiallyExecute",
                 "nativeCancellationStopsAwaitingExecutor", "nativeGeneratePreservesToolCalls")}
        }
        self.assertEqual(len(authentic), 5)
        self.assertEqual(set(bridge.BRIDGE_SELECTORS), authentic)
        path = self.evidence / "commands.json"
        original = path.read_bytes()
        for label in ("missing-parentheses", "old-header-scope", "missing-generate"):
            with self.subTest(label=label):
                commands = json.loads(original)
                test = next(command for command in commands if command["name"] == "SDKTests")
                if label == "missing-parentheses":
                    test["argv"] = [value[:-2] if value.startswith("-only-testing:") and value.endswith("()")
                                    else value for value in test["argv"]]
                elif label == "old-header-scope":
                    test["argv"] = [value.replace("HanlinAppleToolSessionBridgeTests/nativeGeneratePreservesToolCalls()",
                                      "HanlinAppleToolHeaderAdmissionTests/rejectsUnsupportedTransportHeader()")
                                    for value in test["argv"]]
                else:
                    test["argv"] = [value for value in test["argv"] if "nativeGeneratePreservesToolCalls" not in value]
                write(path, commands)
                self.assertEqual(bridge.summarize_bridge_recheck(self.evidence)["status"], "BLOCKED")
                path.write_bytes(original)

    def test_changed_independent_inputs_and_pretended_reuse_or_execution_are_blocked(self):
        mutations = [
            ("history-dependency", "tested-source-sha256.json",
             lambda data: data.update({"Packages/HanlinAgentSDK/Sources/HanlinAgentCore/Providers/HanlinAppleToolHistory.swift": "changed"})),
            ("runtime-source", "tested-source-sha256.json",
             lambda data: data.update({next(iter(bridge.PERMITTED_SOURCE)): "changed"})),
            ("claimed-core-execution", "process-status.json", lambda data: data.update(core_test_exit=0)),
            ("claimed-baseline-execution", "process-status.json", lambda data: data.update(baseline_core_exit=65)),
            ("omitted-current-build", "process-status.json", lambda data: data.update(ios_build_exit=None)),
            ("pretended-reused-build", "process-status.json", lambda data: data.update(ios_build_execution="REUSED_VERIFIED")),
            ("missing-current-build-command", "commands.json",
             lambda data: data.__setitem__(slice(None), [row for row in data if row["name"] != "IOSBuild"])),
            ("changed-post-lock", "post-build-resolution.json", lambda data: data[0].update(sha256="changed")),
            ("promoted-original-failure", "bridge-reuse.json",
             lambda data: data["reused_cases"][0].update(id="HanlinAppleToolSessionBridgeTests/nativeDenialReturnsThroughCanonicalHistory")),
            ("missing-current-case", "SDKTests.json", lambda data: data["testNodes"].pop()),
            ("current-failure", "SDKTests.json", lambda data: data["testNodes"][0].update(result="Failed")),
        ]
        for label, relative, mutate in mutations:
            with self.subTest(label=label):
                path = self.evidence / relative
                original = path.read_bytes()
                data = json.loads(original)
                mutate(data)
                write(path, data)
                self.assertEqual(bridge.summarize_bridge_recheck(self.evidence)["status"], "BLOCKED")
                path.write_bytes(original)
        for relative in ("source-current-0.swift", "source-current-1.swift",
                         "bridge-negative-original/SDKTests.json", "sdk-Package.resolved"):
            with self.subTest(label=relative):
                path = self.evidence / relative
                original = path.read_bytes()
                path.write_bytes(original + b" ")
                self.assertEqual(bridge.summarize_bridge_recheck(self.evidence)["status"], "BLOCKED")
                path.write_bytes(original)


if __name__ == "__main__":
    unittest.main()
