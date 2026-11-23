import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1] / "IntegrationValidation"
sys.path.insert(0, str(ROOT))
import verify_native_tool_candidate as subject


class NativeToolCandidateReportTests(unittest.TestCase):
    def fixture(self, root):
        statuses = dict(preparation_exit=0, baseline_core_exit=65, core_test_exit=0,
                        sdk_test_exit=0, ios_build_exit=0)
        (root / "process-status.json").write_text(json.dumps(statuses))
        for name, suites in subject.EXPECTED.items():
            cases = [{"nodeType": "Test Case", "nodeIdentifier": suite + "/" + method + "()",
                      "result": "Passed"}
                     for suite, methods in suites.items() for method in methods]
            (root / (name + ".json")).write_text(json.dumps({"testNodes": cases}))
        cases = [{"nodeType": "Test Case", "nodeIdentifier": "HanlinAppleToolInputBoundaryTests/" + method + "()",
                  "result": "Passed" if method == "cloudOriginalInputStillHasExactProvenance" else "Failed"}
                 for method in subject.EXPECTED["CoreTests"]["HanlinAppleToolInputBoundaryTests"]]
        (root / "BaselineCoreTests.json").write_text(json.dumps({"testNodes": cases}))

    def test_exact_new_cases_and_expected_baseline_are_required(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); self.fixture(root)
            result = subject.summarize(root)
            self.assertEqual(result["status"], "PASS")
            self.assertEqual(len(result["cases"]), 12)
            self.assertFalse(result["shipping_native_tool_capability"])
            self.assertEqual(result["system_model_generation"], "NOT_RUN")

    def test_missing_skipped_failed_or_extra_case_cannot_pass(self):
        for mutation in ["missing", "skipped", "failed", "extra"]:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); self.fixture(root)
                path = root / "SDKTests.json"; data = json.loads(path.read_text())
                if mutation == "missing": data["testNodes"].pop()
                if mutation == "skipped": data["testNodes"][0]["result"] = "Skipped"
                if mutation == "failed": data["testNodes"][0]["result"] = "Failed"
                if mutation == "extra": data["testNodes"].append({"nodeType": "Test Case", "nodeIdentifier": "Unselected/case()", "result": "Passed"})
                path.write_text(json.dumps(data))
                self.assertEqual(subject.summarize(root)["status"], "BLOCKED")

    def test_false_green_baseline_and_unexecuted_ios_are_blocked(self):
        for mutation in ["baseline_passed", "baseline_missing", "ios_not_run", "preparation_failed"]:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); self.fixture(root)
                if mutation == "baseline_passed":
                    path = root / "BaselineCoreTests.json"; data = json.loads(path.read_text())
                    data["testNodes"][0]["result"] = "Passed"; path.write_text(json.dumps(data))
                elif mutation == "baseline_missing": (root / "BaselineCoreTests.json").unlink()
                else:
                    path = root / "process-status.json"; data = json.loads(path.read_text())
                    data["ios_build_exit" if mutation == "ios_not_run" else "preparation_exit"] = None if mutation == "ios_not_run" else 1
                    path.write_text(json.dumps(data))
                self.assertEqual(subject.summarize(root)["status"], "BLOCKED")

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
