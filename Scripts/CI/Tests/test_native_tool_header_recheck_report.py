"""Only new header-recheck report/admission controls; no Swift/native execution."""
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
import verify_native_tool_header_recheck as header


def read(path):
    return json.loads(path.read_text())


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


class HeaderRecheckReportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.evidence = Path(self.temp.name)
        self.reference = ROOT / header.REFERENCE_PATH
        self.baseline = ROOT / baseline.REFERENCE_PATH
        names = ["core-Package.resolved", "sdk-Package.resolved", "producer-commit.txt",
                 "tested-source-sha256.json", "workflow-sha256.json"]
        commands = read(self.reference / "commands.json")
        kept = [c for c in commands if c["name"] in set(header.TOOLCHAIN) | {"producer-clean"}]
        for command in kept:
            names += [command[stream]["file"] for stream in ("stdout", "stderr")]
        for name in names:
            shutil.copyfile(self.reference / name, self.evidence / name)
        sources = read(self.evidence / "tested-source-sha256.json")
        sources.update(header.PERMITTED_SOURCE)
        write(self.evidence / "tested-source-sha256.json", sources)
        for name in ("tested-source-commit.txt", "workflow-commit.txt"):
            (self.evidence / name).write_text("EXPLICIT_LOCAL_HEADER_REPAIR_REPORT_FIXTURE\n")
        variant = read(self.baseline / "baseline-variant.json")
        for relative in variant["files"]:
            variant["files"][relative]["candidate_sha256"] = sources[relative]
        write(self.evidence / "baseline-variant.json", variant)
        kept += [
            dict(name="SDKTests", argv=["xcodebuild", "test", "-scheme", "HanlinAgentSDK-Package",
                 "-destination", "platform=macOS"] + ["-only-testing:" + s for s in header.HEADER_SELECTORS],
                 exit_code=0),
            dict(name="IOSBuild", argv=["xcodebuild", "build", "-scheme", "HanlinAgentCore",
                 "-destination", "generic/platform=iOS Simulator"], exit_code=0),
        ]
        write(self.evidence / "commands.json", kept)
        baseline.prepare_reuse(ROOT, self.evidence)
        header.prepare_header_reuse(ROOT, self.evidence)
        cases = []
        for suite, methods in header.HEADER_EXPECTED.items():
            for method in methods:
                identity = suite + "/" + method + "()"
                cases.append(dict(nodeType="Test Case", name=method, nodeIdentifier=identity,
                                  nodeIdentifierURL="test://com.apple.xcode/HanlinAgentSDK/HanlinAgentCoreTests/" + identity,
                                  result="Passed"))
        write(self.evidence / "SDKTests.json", dict(testNodes=cases))
        write(self.evidence / "process-status.json",
              dict(preparation_exit=0, baseline_core_exit=None, core_test_exit=None,
                   sdk_test_exit=0, ios_build_exit=0, baseline_execution="REUSED_VERIFIED",
                   accepted_cases_execution="REUSED_VERIFIED"))

    def tearDown(self):
        self.temp.cleanup()

    def test_original28_are_reused_separately_from_only_five_fixture_executions(self):
        report = header.summarize_header_recheck(self.evidence)
        self.assertEqual(report["status"], "PASS", report["errors"])
        self.assertEqual(len(report["cases"]), 5)
        self.assertEqual(report["reused_invocations"], 28)
        self.assertEqual({r["source_commit"] for r in report["reused_cases"]}, {header.SOURCE})
        self.assertEqual(len(report["baseline_cases"]), 12)
        self.assertEqual(sum(r["status"] == "FAIL" for r in report["baseline_cases"]), 10)
        self.assertIsNone(report["process_status"]["baseline_core_exit"])
        self.assertIsNone(report["process_status"]["core_test_exit"])

    def test_reuse_rejects_changed_inputs_or_fabricated_current_execution(self):
        mutations = [
            ("source", "tested-source-sha256.json", lambda d: d.update({"Packages/HanlinPlatform/Package.swift": "changed"})),
            ("reviewed-repair", "tested-source-sha256.json", lambda d: d.update({next(iter(header.PERMITTED_SOURCE)): "changed"})),
            ("receipt", "header-reuse.json", lambda d: d.update({"reused_cases": []})),
            ("core-exit", "process-status.json", lambda d: d.update(core_test_exit=0)),
            ("baseline-exit", "process-status.json", lambda d: d.update(baseline_core_exit=65)),
            ("SDK-command-exit", "commands.json", lambda d: next(c for c in d if c["name"] == "SDKTests").update(exit_code=65)),
            ("duplicate-test-process", "commands.json", lambda d: d.append(copy.deepcopy(next(c for c in d if c["name"] == "SDKTests")))),
            ("wrong-selector", "commands.json", lambda d: next(c for c in d if c["name"] == "SDKTests")["argv"].append("-only-testing:HanlinAgentCoreTests")),
            ("missing-build", "commands.json", lambda d: d.remove(next(c for c in d if c["name"] == "IOSBuild"))),
            ("wrong-build", "commands.json", lambda d: next(c for c in d if c["name"] == "IOSBuild")["argv"].append("-only-testing:Unexpected")),
        ]
        # The final adversary is a wrong actual destination, not an innocuous build argument.
        mutations[-1] = ("wrong-build", "commands.json",
                         lambda d: next(c for c in d if c["name"] == "IOSBuild")["argv"].__setitem__(5, "platform=macOS"))
        for label, name, mutate in mutations:
            with self.subTest(label=label):
                path = self.evidence / name
                original = path.read_bytes()
                value = json.loads(original)
                mutate(value)
                write(path, value)
                self.assertEqual(header.summarize_header_recheck(self.evidence)["status"], "BLOCKED")
                path.write_bytes(original)
        for name in ("sdk-Package.resolved", "producer-commit.txt"):
            with self.subTest(label=name):
                path = self.evidence / name
                original = path.read_bytes()
                path.write_bytes(original + b" " if name.endswith(".resolved") else b"wrong-producer\n")
                self.assertEqual(header.summarize_header_recheck(self.evidence)["status"], "BLOCKED")
                path.write_bytes(original)
        path = self.evidence / "header-reuse-original/CoreTests.json"
        path.write_bytes(path.read_bytes() + b" ")
        self.assertEqual(header.summarize_header_recheck(self.evidence)["status"], "BLOCKED")

    def test_exact_five_methods_and_diagnostics_cannot_be_replaced_by_aggregates(self):
        path = self.evidence / "SDKTests.json"
        original = path.read_bytes()
        for label, mutate in [
            ("missing", lambda nodes: nodes.pop()),
            ("duplicate", lambda nodes: nodes.append(copy.deepcopy(nodes[0]))),
            ("failed", lambda nodes: nodes[0].update(result="Failed")),
            ("skipped", lambda nodes: nodes[0].update(result="Skipped")),
            ("false-passed-diagnostic", lambda nodes: nodes[0].update(children=[dict(nodeType="Failure Message", name="actual failure")])),
            ("wrong-url", lambda nodes: nodes[0].update(nodeIdentifierURL="test://com.apple.xcode/wrong")),
        ]:
            with self.subTest(label=label):
                value = json.loads(original)
                mutate(value["testNodes"])
                write(path, value)
                self.assertEqual(header.summarize_header_recheck(self.evidence)["status"], "BLOCKED")
                path.write_bytes(original)

    def test_source_preserves_all_original_seven_helpers_and_exact_header_selector(self):
        old = (self.reference / "source-before-1.swift").read_text()
        new = (ROOT / list(header.PERMITTED_SOURCE)[1]).read_text()
        old_helper = old.split("private struct NativeToolSessionBridgeChecks {", 1)[1]
        old_before = old_helper.split("    func nativeGeneratePreservesToolCalls()", 1)[0]
        new_helper = new.split("private struct NativeToolSessionBridgeChecks {", 1)[1]
        self.assertTrue(new_helper.startswith(old_before))
        old_after = "    func nativeGeneratePreservesToolCalls()" + old_helper.split("    func nativeGeneratePreservesToolCalls()", 1)[1]
        self.assertTrue(new_helper.endswith(old_after))
        self.assertEqual(len(header.HEADER_SELECTORS), 5)
        self.assertEqual(len(set(header.HEADER_SELECTORS)), 5)
        runner = (ROOT / "Scripts/CI/IntegrationValidation/run_native_tool_candidate.py").read_text()
        self.assertIn('header_recheck = selector == "HanlinNativeToolHeaderRecheck"', runner)
        self.assertIn('if not header_recheck:\n            statuses["core_test_exit"]', runner)
        self.assertIn('sdk_selectors = HEADER_SELECTORS if header_recheck else', runner)
        self.assertIn('inputs.get("target_validation_group") != "agent_sdk_exact_source_proof"', runner)


if __name__ == "__main__":
    unittest.main()
