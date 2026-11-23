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
import reuse_native_header_ios_build as ios_reuse


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
        compile_reference = ROOT / ios_reuse.REFERENCE_PATH
        selection = next(c for c in read(compile_reference / "commands.json") if c["name"] == "select-xcode")
        kept.append(selection)
        selected_logs = {selection[stream]["file"] for stream in ("stdout", "stderr")}
        for command in kept:
            names += [command[stream]["file"] for stream in ("stdout", "stderr")]
        for name in names:
            source = compile_reference if name in selected_logs else self.reference
            shutil.copyfile(source / name, self.evidence / name)
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
        ]
        write(self.evidence / "commands.json", kept)
        baseline.prepare_reuse(ROOT, self.evidence)
        header.prepare_header_reuse(ROOT, self.evidence)
        ios_reference = ROOT / ios_reuse.REFERENCE_PATH
        shutil.copyfile(ios_reference / "post-build-resolution.json", self.evidence / "post-build-resolution.json")
        shutil.copytree(ios_reference / "raw-locks", self.evidence / "raw-locks")
        ios_reuse.prepare_reuse(ROOT, self.evidence)
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
                   sdk_test_exit=0, ios_build_exit=None, baseline_execution="REUSED_VERIFIED",
                   accepted_cases_execution="REUSED_VERIFIED", ios_build_execution="REUSED_VERIFIED"))

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
        self.assertIsNone(report["process_status"]["ios_build_exit"])
        self.assertEqual(report["ios_agent_core_compile"], "REUSED_VERIFIED")
        self.assertEqual(report["ios_build_reuse"]["original_run_id"], 45268041311)
        self.assertEqual(report["ios_build_reuse"]["original_source_commit"], ios_reuse.SOURCE)

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
            ("missing-build-receipt", "ios-build-reuse.json", lambda d: d.clear()),
            ("unexpected-build", "commands.json", lambda d: d.append(dict(name="IOSBuild", argv=["xcodebuild", "build"], exit_code=0))),
        ]
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

    def test_ios_compile_reuse_rejects_mismatch_and_pretended_current_execution(self):
        receipt = ios_reuse.validate_reuse(self.evidence)
        self.assertEqual(receipt["mode"], "REUSED_VERIFIED")
        self.assertEqual(receipt["original_run_id"], 45268041311)
        self.assertEqual(receipt["original_build"]["exit_code"], 0)
        self.assertEqual(receipt["current_build_process"], "NOT_INVOKED")
        mutations = [
            ("source", "tested-source-sha256.json", lambda d: d.update({"Packages/HanlinPlatform/Package.swift": "changed"})),
            ("current-exit", "process-status.json", lambda d: d.update(ios_build_exit=0)),
            ("missing-null-exit", "process-status.json", lambda d: d.pop("ios_build_exit")),
            ("missing-mode", "process-status.json", lambda d: d.pop("ios_build_execution")),
            ("false-source", "ios-build-reuse.json", lambda d: d.update(original_source_commit="pretended")),
            ("actual-current-build", "commands.json", lambda d: d.append(dict(name="IOSBuild", argv=["xcodebuild", "build"], exit_code=0))),
            ("missing-post-lock", "post-build-resolution.json", lambda d: d.pop()),
            ("duplicated-post-lock", "post-build-resolution.json", lambda d: d.__setitem__(1, copy.deepcopy(d[0]))),
            ("changed-post-lock", "post-build-resolution.json", lambda d: d[0].update(sha256="changed")),
        ]
        for label, relative, mutate in mutations:
            with self.subTest(label=label):
                path = self.evidence / relative
                original = path.read_bytes()
                value = json.loads(original)
                mutate(value); write(path, value)
                with self.assertRaises(ValueError):
                    ios_reuse.validate_reuse(self.evidence)
                self.assertEqual(header.summarize_header_recheck(self.evidence)["status"], "BLOCKED")
                path.write_bytes(original)
        for relative in ("sdk-Package.resolved", "core-Package.resolved",
                         "ios-build-reuse-original/17-IOSBuild.stdout.log"):
            with self.subTest(label=relative):
                path = self.evidence / relative
                original = path.read_bytes()
                path.write_bytes(original + b" ")
                with self.assertRaises(ValueError):
                    ios_reuse.validate_reuse(self.evidence)
                path.write_bytes(original)
        # A self-consistent new command/log hash cannot impersonate the
        # original Xcode/native SDK fingerprint.
        command_path = self.evidence / "commands.json"
        original_commands = command_path.read_bytes()
        for name in ios_reuse.FINGERPRINT:
            with self.subTest(label="toolchain-" + name):
                commands = json.loads(original_commands)
                command = next(c for c in commands if c["name"] == name)
                path = self.evidence / command["stdout"]["file"]
                original = path.read_bytes()
                path.write_bytes(original + b"changed-toolchain")
                command["stdout"]["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
                write(command_path, commands)
                with self.assertRaises(ValueError):
                    ios_reuse.validate_reuse(self.evidence)
                path.write_bytes(original)
                command_path.write_bytes(original_commands)

    def test_function_selectors_match_authenticated_original_swift_identifiers(self):
        original = read(self.reference / "SDKTests.json")
        authentic = []
        def visit(node):
            if isinstance(node, dict):
                identity = node.get("nodeIdentifier", "")
                if node.get("nodeType") == "Test Case" and identity.startswith("HanlinAppleToolSessionBridgeTests/"):
                    basename = identity.rsplit("/", 1)[-1].split("(", 1)[0]
                    if basename in header.FAILED_METHODS:
                        self.assertTrue(identity.endswith("()"))
                        authentic.append("HanlinAgentCoreTests/" + identity)
                for value in node.values():
                    visit(value)
            elif isinstance(node, list):
                for value in node:
                    visit(value)
        visit(original)
        self.assertEqual(len(authentic), 4)
        self.assertEqual(len(set(authentic)), 4)
        # This one new function has not executed yet; bind its declared singleton
        # signature independently rather than fabricate an original outcome.
        source = (ROOT / list(header.PERMITTED_SOURCE)[1]).read_text()
        declaration = source.split("struct HanlinAppleToolHeaderAdmissionTests {", 1)[1].split(
            "// Availability belongs", 1)[0]
        self.assertIn("func rejectsUnsupportedTransportHeader() async throws", declaration)
        authentic.append("HanlinAgentCoreTests/HanlinAppleToolHeaderAdmissionTests/rejectsUnsupportedTransportHeader()")
        self.assertCountEqual(header.HEADER_SELECTORS, authentic)

        # Even a fixture claiming five passes cannot excuse a command with the
        # exact missing-parentheses defect observed in run45268041311.
        commands = read(self.evidence / "commands.json")
        selected = next(command for command in commands if command["name"] == "SDKTests")
        selected["argv"] = [
            argument[:-2] if argument.startswith("-only-testing:") and argument.endswith("()")
            else argument for argument in selected["argv"]
        ]
        write(self.evidence / "commands.json", commands)
        self.assertEqual(header.summarize_header_recheck(self.evidence)["status"], "BLOCKED")

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
