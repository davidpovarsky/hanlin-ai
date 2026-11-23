"""Report-parser controls with synthetic xcresult-shaped data, not native test execution."""
import hashlib
import json
from pathlib import Path
import re
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1] / "IntegrationValidation"
REPOSITORY = ROOT.parents[2]
sys.path.insert(0, str(ROOT))
import verify_native_tool_candidate as subject


class NativeToolCandidateReportTests(unittest.TestCase):
    def fixture(self, root):
        statuses = dict(preparation_exit=0, baseline_core_exit=65, core_test_exit=0,
                        sdk_test_exit=0, ios_build_exit=0)
        (root / "process-status.json").write_text(json.dumps(statuses))
        for name, suites in {**subject.EXPECTED, "BaselineCoreTests": subject.EXPECTED["CoreTests"]}.items():
            cases = []
            for suite, methods in suites.items():
                for method, arguments in methods.items():
                    identity = subject.signature(suite + "/" + method, arguments)
                    status = ("Failed" if name == "BaselineCoreTests" and
                              method != "cloudOriginalInputStillHasExactProvenance" else "Passed")
                    parent_url = "test://com.apple.xcode/Fixture/FixtureTests/" + identity
                    case = dict(nodeType="Test Case", nodeIdentifier=identity, nodeIdentifierURL=parent_url,
                                name=method, result=status)
                    if arguments is not None:
                        case["children"] = []
                        for values in arguments:
                            display = ", ".join(json.dumps(value, ensure_ascii=False) for value in values)
                            # Synthetic fixture IDs are not claimed to reproduce Apple's hash algorithm.
                            digest = hashlib.sha256(subject.argument_key(values).encode()).hexdigest()
                            case["children"].append(dict(
                                nodeType="Arguments", name=display, result=status,
                                nodeIdentifierURL=parent_url + "?args=" + digest))
                    cases.append(case)
            (root / (name + ".json")).write_text(json.dumps({"testNodes": cases}))

    def test_exact_32_invocations_and_12_baseline_invocations_are_required(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); self.fixture(root)
            result = subject.summarize(root)
            self.assertEqual(result["status"], "PASS", result["errors"])
            self.assertEqual(len(result["cases"]), 32)
            self.assertEqual(len(result["methods"]), 12)
            self.assertEqual(len(result["baseline_cases"]), 12)
            self.assertEqual(sum(row["status"] == "FAIL" for row in result["baseline_cases"]), 10)
            self.assertEqual(sum(row["status"] == "PASS" for row in result["baseline_cases"]), 2)
            self.assertFalse(result["shipping_native_tool_capability"])
            self.assertEqual(result["system_model_generation"], "NOT_RUN")

    def test_missing_skipped_failed_or_extra_method_cannot_pass(self):
        for mutation in ["missing", "skipped", "failed", "extra"]:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); self.fixture(root)
                path = root / "SDKTests.json"; data = json.loads(path.read_text())
                if mutation == "missing": data["testNodes"].pop()
                if mutation == "skipped": data["testNodes"][0]["result"] = "Skipped"
                if mutation == "failed": data["testNodes"][0]["result"] = "Failed"
                if mutation == "extra":
                    data["testNodes"].append(dict(nodeType="Test Case", nodeIdentifier="Unselected/case()", result="Passed"))
                path.write_text(json.dumps(data))
                self.assertEqual(subject.summarize(root)["status"], "BLOCKED")

    def test_aggregate_only_false_green_is_blocked_for_candidate_and_baseline(self):
        for name in ["CoreTests", "SDKTests", "BaselineCoreTests"]:
            with self.subTest(result=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); self.fixture(root)
                path = root / (name + ".json"); data = json.loads(path.read_text())
                for case in data["testNodes"]:
                    case.pop("children", None)
                path.write_text(json.dumps(data))
                result = subject.summarize(root)
                self.assertEqual(result["status"], "BLOCKED")
                rows = result["baseline_cases"] if name == "BaselineCoreTests" else result["cases"]
                self.assertTrue(any(row["status"] == "NOT_RUN" for row in rows))

    def test_argument_omission_replacement_duplicates_identity_and_status_are_blocked(self):
        mutations = ["missing", "duplicate_value", "duplicate_url", "wrong_url", "missing_url",
                     "replacement", "failed", "skipped", "unknown_status", "unknown_type",
                     "nested_execution", "unknown_display"]
        for mutation in mutations:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); self.fixture(root)
                path = root / "CoreTests.json"; data = json.loads(path.read_text())
                children = data["testNodes"][1]["children"]  # Eight numeric tuples; aggregate stays Passed.
                if mutation == "missing": children.pop()
                if mutation == "duplicate_value": children[1]["name"] = children[0]["name"]
                if mutation == "duplicate_url": children[1]["nodeIdentifierURL"] = children[0]["nodeIdentifierURL"]
                if mutation == "wrong_url": children[0]["nodeIdentifierURL"] = children[0]["nodeIdentifierURL"].replace("nativeNumericInputCannotReachApprovalOrExecutor", "unrelated")
                if mutation == "missing_url": children[0].pop("nodeIdentifierURL")
                if mutation == "replacement": children[0]["name"] = '"{\\"number\\":-1}", false'
                if mutation == "failed": children[0]["result"] = "Failed"
                if mutation == "skipped": children[0]["result"] = "Skipped"
                if mutation == "unknown_status": children[0]["result"] = "Not Run"
                if mutation == "unknown_type": children[0]["nodeType"] = "Unknown Format"
                if mutation == "nested_execution": children[0]["children"] = [dict(children[1])]
                if mutation == "unknown_display": children[0]["name"] = "values unavailable"
                path.write_text(json.dumps(data))
                self.assertEqual(subject.summarize(root)["status"], "BLOCKED")

    def test_each_schema_value_is_required_without_json_normalization_or_truncation(self):
        for mutation in ["duplicate", "reordered_json", "truncated", "boolean_instead_of_string"]:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); self.fixture(root)
                path = root / "SDKTests.json"; data = json.loads(path.read_text())
                children = data["testNodes"][0]["children"]
                if mutation == "duplicate": children[1]["name"] = children[0]["name"]
                if mutation == "reordered_json":
                    original = json.loads(children[0]["name"])
                    children[0]["name"] = json.dumps(json.dumps(json.loads(original), sort_keys=True))
                if mutation == "truncated": children[0]["name"] = children[0]["name"][:40]
                if mutation == "boolean_instead_of_string": children[0]["name"] = "false"
                path.write_text(json.dumps(data))
                self.assertEqual(subject.summarize(root)["status"], "BLOCKED")

    def test_each_baseline_failure_and_cloud_pass_must_execute(self):
        for mutation in ["native_pass", "numeric_pass", "cloud_fail", "missing_argument", "duplicate_argument"]:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); self.fixture(root)
                path = root / "BaselineCoreTests.json"; data = json.loads(path.read_text())
                if mutation == "native_pass": data["testNodes"][0]["children"][0]["result"] = "Passed"
                if mutation == "numeric_pass": data["testNodes"][1]["children"][0]["result"] = "Passed"
                if mutation == "cloud_fail": data["testNodes"][2]["children"][0]["result"] = "Failed"
                if mutation == "missing_argument": data["testNodes"][1]["children"].pop()
                if mutation == "duplicate_argument": data["testNodes"][1]["children"][1]["name"] = data["testNodes"][1]["children"][0]["name"]
                path.write_text(json.dumps(data))
                result = subject.summarize(root)
                self.assertEqual(result["status"], "BLOCKED")
                self.assertEqual(result["baseline_negative_control"], "BLOCKED")

    def test_invalid_process_status_or_absent_exports_cannot_pass(self):
        for mutation in ["baseline_passed", "baseline_missing", "baseline_timeout", "baseline_signal", "baseline_infrastructure", "ios_not_run", "preparation_failed", "boolean_exit"]:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); self.fixture(root)
                if mutation == "baseline_missing":
                    (root / "BaselineCoreTests.json").unlink()
                else:
                    path = root / "process-status.json"; data = json.loads(path.read_text())
                    key, value = {"baseline_passed": ("baseline_core_exit", 0),
                                  "baseline_timeout": ("baseline_core_exit", 124),
                                  "baseline_signal": ("baseline_core_exit", -15),
                                  "baseline_infrastructure": ("baseline_core_exit", 1),
                                  "ios_not_run": ("ios_build_exit", None),
                                  "preparation_failed": ("preparation_exit", 1),
                                  "boolean_exit": ("core_test_exit", False)}[mutation]
                    data[key] = value; path.write_text(json.dumps(data))
                self.assertEqual(subject.summarize(root)["status"], "BLOCKED")

    def test_tuple_values_are_exact_with_parenthesized_display(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); self.fixture(root)
            for name in ["CoreTests", "BaselineCoreTests"]:
                path = root / (name + ".json"); data = json.loads(path.read_text())
                for child in data["testNodes"][1]["children"]:
                    child["name"] = "(" + child["name"] + ")"
                path.write_text(json.dumps(data))
            self.assertEqual(subject.summarize(root)["status"], "PASS")

    def test_inventory_is_bound_to_authored_swift_arguments_and_methods(self):
        core = (REPOSITORY / "Packages/HanlinPlatform/Tests/HanlinChatCoreTests/HanlinAppleToolInputBoundaryTests.swift").read_text()
        schema = (REPOSITORY / "Packages/HanlinAgentSDK/Tests/HanlinAgentCoreTests/HanlinAppleToolSchemaTests.swift").read_text()
        bridge = (REPOSITORY / "Packages/HanlinAgentSDK/Tests/HanlinAgentCoreTests/HanlinAppleToolSessionBridgeTests.swift").read_text()
        numeric_test = core.split("func nativeNumericInputCannotReachApprovalOrExecutor", 1)[0].rsplit("@Test", 1)[1]
        schema_test = schema.split("func rejectsUnrepresentedSemantics", 1)[0].rsplit("@Test", 1)[1]
        self.assertEqual(re.findall(r'#"(.*?)"#', numeric_test, re.S), subject.NUMERIC_INPUTS)
        self.assertEqual(re.findall(r'#"(.*?)"#', schema_test, re.S), subject.UNSUPPORTED_SCHEMAS)
        for method in subject.EXPECTED["CoreTests"]["HanlinAppleToolInputBoundaryTests"]:
            declaration = core.split("func " + method, 1)[0].rsplit("@Test", 1)[1]
            self.assertRegex(declaration, r"\[false,\s*true\]")
        for source, suite, result in [
            (core, "HanlinAppleToolInputBoundaryTests", "CoreTests"),
            (schema, "HanlinAppleToolSchemaTests", "SDKTests"),
            (bridge, "HanlinAppleToolSessionBridgeTests", "SDKTests"),
        ]:
            authored = re.findall(r"@Test\b.*?\bfunc\s+(\w+)\s*\(", source, re.S)
            self.assertEqual(set(authored), set(subject.EXPECTED[result][suite]))
            self.assertEqual(len(authored), len(subject.EXPECTED[result][suite]))


class NativeToolCandidateSelectorTests(unittest.TestCase):
    def test_only_exact_opt_in_changes_the_existing_route(self):
        import os
        import subprocess
        script = (ROOT / "run_agent_sdk.sh").read_text()
        marker = 'python3 "$(git rev-parse --show-toplevel)/Scripts/CI/verify_exact_json_vendor.py"'
        prefix = script.split(marker, 1)[0]
        self.assertIn("HanlinNativeToolCandidate", prefix)
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            wrapper = "#!" + sys.executable + "\n" + """import os,pathlib,subprocess,sys
if pathlib.Path(sys.argv[0]).name == "git":
    print(os.environ["HANLIN_SELECTOR_REPO"])
elif sys.argv[1].endswith("/run_native_tool_candidate.py"):
    print("candidate")
else:
    sys.exit(subprocess.call([sys.executable,*sys.argv[1:]]))
"""
            for name in ["python3", "git"]:
                path = folder / name; path.write_text(wrapper); path.chmod(0o755)
            for selector in [None, "HanlinChatCoreTests", "HanlinNativeToolCandidates", "HanlinNativeToolCandidate"]:
                with self.subTest(selector=selector):
                    env = os.environ.copy()
                    env["PATH"] = str(folder) + os.pathsep + env["PATH"]
                    env["HANLIN_SELECTOR_REPO"] = str(folder)
                    env.pop("GITHUB_EVENT_PATH", None)
                    if selector is not None:
                        event = folder / "event.json"
                        event.write_text(json.dumps({"inputs": {"exact_test_selector": selector}}))
                        env["GITHUB_EVENT_PATH"] = str(event)
                    completed = subprocess.run(["bash", "-c", prefix + "\nprintf 'legacy\\n'\n"],
                                               text=True, capture_output=True, env=env)
                    self.assertEqual(completed.returncode, 0, completed.stderr)
                    self.assertEqual(completed.stdout.strip(),
                                     "candidate" if selector == "HanlinNativeToolCandidate" else "legacy")


if __name__ == "__main__":
    unittest.main()
