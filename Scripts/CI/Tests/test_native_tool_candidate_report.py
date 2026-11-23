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
                            display = subject.argument_display(values)
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
                    original = children[0]["name"][1:-1]
                    children[0]["name"] = '"' + json.dumps(json.loads(original), sort_keys=True) + '"'
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

    def test_unobserved_parenthesized_or_reescaped_displays_are_blocked(self):
        for variant in ["parenthesized", "reescaped"]:
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); self.fixture(root)
                path = root / "CoreTests.json"; data = json.loads(path.read_text())
                child = data["testNodes"][1]["children"][0]
                if variant == "parenthesized":
                    child["name"] = "(" + child["name"] + ")"
                else:
                    child["name"] = ", ".join(json.dumps(value) for value in (subject.NUMERIC_INPUTS[0], False))
                path.write_text(json.dumps(data))
                self.assertEqual(subject.summarize(root)["status"], "BLOCKED")

    def test_authentic_apple_exports_preserve_the_executed_outcomes(self):
        fixtures = Path(__file__).parent / "Fixtures/native-tool-candidate-45240721804"
        digests = {"BaselineCoreTests": "5a1da0ade219ac177d3e664c65939ce03a8c8f5ea817d83fd0e980c180203d84",
                   "CoreTests": "e5ab426ea3a4835a5618f4868cf0daa84c012929b3df3305ecd77e14c8199245"}
        for name, digest in digests.items():
            self.assertEqual(hashlib.sha256((fixtures / (name + ".json")).read_bytes()).hexdigest(), digest)
        rows, methods, errors = subject.inspect_result(fixtures, "BaselineCoreTests", subject.EXPECTED["CoreTests"], baseline=True)
        self.assertEqual(errors, [])
        self.assertEqual(len(rows), 12)
        self.assertEqual(sum(row["status"] == "FAIL" for row in rows), 10)
        self.assertEqual(sum(row["status"] == "PASS" for row in rows), 2)
        rows, methods, errors = subject.inspect_result(fixtures, "CoreTests", subject.EXPECTED["CoreTests"])
        self.assertEqual(len(rows), 12)
        self.assertEqual(sum(row["status"] == "FAIL" for row in rows), 7)
        self.assertEqual(sum(row["status"] == "PASS" for row in rows), 5)
        self.assertTrue(errors)
        self.assertFalse(any("missing arguments" in error or "unknown" in error for error in errors))

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



class NativeToolBaselineReuseTests(unittest.TestCase):
    """Exercise reuse guards with synthetic current-run metadata and original baseline bytes."""
    def fixture(self, root):
        import shutil
        import reuse_native_tool_baseline as reuse
        NativeToolCandidateReportTests.fixture(self, root)
        reference = REPOSITORY / reuse.REFERENCE_PATH
        for name in ["tested-source-sha256.json", "baseline-variant.json", "core-Package.resolved", "producer-commit.txt"]:
            shutil.copyfile(reference / name, root / name)
        current_source = "f" * 40  # Explicit report fixture, never a claimed Git/native execution.
        (root / "tested-source-commit.txt").write_text(current_source + "\n")
        (root / "workflow-commit.txt").write_text(current_source + "\n")
        manifest = json.loads((root / "tested-source-sha256.json").read_text())
        variant = json.loads((root / "baseline-variant.json").read_text())
        engine = next(path for path in reuse.VARIANT_FILES if path.endswith("HanlinAISDKAgentEngine.swift"))
        manifest[engine] = "e" * 64
        variant["files"][engine]["candidate_sha256"] = manifest[engine]
        (root / "tested-source-sha256.json").write_text(json.dumps(manifest))
        (root / "baseline-variant.json").write_text(json.dumps(variant))
        commands = [command for command in json.loads((reference / "commands.json").read_text())
                    if command["name"] in set(reuse.TOOLCHAIN) | {"producer-clean"}]
        for command in commands:
            for stream in ("stdout", "stderr"):
                record = command[stream]
                if (reference / record["file"]).exists():
                    shutil.copyfile(reference / record["file"], root / record["file"])
                elif record["sha256"] == hashlib.sha256(b"").hexdigest():
                    (root / record["file"]).write_bytes(b"")
                # The original query stderr is not part of output equivalence.
        (root / "commands.json").write_text(json.dumps(commands))
        reuse.prepare_reuse(REPOSITORY, root)
        statuses = json.loads((root / "process-status.json").read_text())
        statuses.update(baseline_core_exit=None, baseline_execution="REUSED_VERIFIED")
        (root / "process-status.json").write_text(json.dumps(statuses))

    def test_verified_baseline_is_separate_from_current_process_status(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); self.fixture(root)
            result = subject.summarize(root)
            self.assertEqual(result["status"], "PASS", result["errors"])
            self.assertIsNone(result["process_status"]["baseline_core_exit"])
            self.assertEqual(result["baseline_execution"], "REUSED_VERIFIED")
            self.assertEqual(result["baseline_reuse"]["baseline_scope_files"], 238)
            self.assertEqual(result["baseline_reuse"]["original_baseline_exit"], 65)
            self.assertEqual(len(result["cases"]), 32)
            self.assertEqual(len(result["baseline_cases"]), 12)
            self.assertTrue(all(row["execution"] == "REUSED_VERIFIED" for row in result["baseline_cases"]))

    def test_changed_reuse_inputs_or_fabricated_current_exit_block_acceptance(self):
        import reuse_native_tool_baseline as reuse
        for mutation in ["test_source", "overlay", "raw_lock", "toolchain", "original_export",
                         "duplicate_execution", "receipt", "current_exit", "producer", "missing_proof"]:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); self.fixture(root)
                if mutation == "test_source":
                    path = root / "tested-source-sha256.json"; data = json.loads(path.read_text())
                    key = "Packages/HanlinPlatform/Tests/HanlinChatCoreTests/HanlinAppleToolInputBoundaryTests.swift"
                    data[key] = "0" * 64; path.write_text(json.dumps(data))
                elif mutation == "overlay":
                    path = root / "baseline-variant.json"; data = json.loads(path.read_text())
                    data["files"][next(iter(reuse.VARIANT_FILES))]["baseline_sha256"] = "0" * 64
                    path.write_text(json.dumps(data))
                elif mutation == "raw_lock":
                    with (root / "core-Package.resolved").open("a") as out: out.write("\n")
                elif mutation == "toolchain":
                    with (root / "06-swift.stdout.log").open("a") as out: out.write("\n")
                elif mutation == "original_export":
                    with (root / "baseline-reuse-original/BaselineCoreTests.json").open("a") as out: out.write("\n")
                elif mutation == "duplicate_execution":
                    path = root / "commands.json"; data = json.loads(path.read_text())
                    data.append(dict(name="BaselineCoreTests", exit_code=65)); path.write_text(json.dumps(data))
                elif mutation == "receipt":
                    path = root / "baseline-reuse.json"; data = json.loads(path.read_text())
                    data["baseline_scope_files"] = 1; path.write_text(json.dumps(data))
                elif mutation == "current_exit":
                    path = root / "process-status.json"; data = json.loads(path.read_text())
                    data["baseline_core_exit"] = 65; path.write_text(json.dumps(data))
                elif mutation == "producer":
                    (root / "producer-commit.txt").write_text("0" * 40)
                elif mutation == "missing_proof":
                    (root / "baseline-reuse-original/reference.json").unlink()
                result = subject.summarize(root)
                self.assertEqual(result["status"], "BLOCKED")
                self.assertEqual(result["baseline_negative_control"], "BLOCKED")


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
            for selector in [None, "HanlinChatCoreTests", "HanlinNativeToolCandidates", "HanlinNativeToolCandidate", "HanlinNativeToolCandidateRecheck"]:
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
                                     "candidate" if selector in {"HanlinNativeToolCandidate", "HanlinNativeToolCandidateRecheck"} else "legacy")


if __name__ == "__main__":
    unittest.main()
