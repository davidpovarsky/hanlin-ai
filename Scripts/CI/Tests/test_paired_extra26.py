"""Pure controls for the original54→26 admission boundary; no native execution."""
from pathlib import Path
import copy
import datetime
import importlib.util
import json
import os
import plistlib
import tempfile
import unittest
from unittest.mock import Mock, patch


ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = ROOT / "Scripts/ProductSplit"
spec = importlib.util.spec_from_file_location("paired_extra26", SCRIPTS / "paired_extra26.py")
extra = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extra)


def scope_document():
    return json.loads((ROOT / extra.INVENTORY).read_text())


def fixture():
    plan = scope_document()["paired"]
    source = "a" * 40
    inputs = {"source": {"head": source, "canonicalWorkingPatchSHA256": "patch", "selectedInputs": {}},
              "sdkInputSHA256": "sdk", "toolchain": {"swift": "original compiler"},
              "hostArchive": {"sha256": "host"}}
    products = {"descriptor": {"path": "/owned/Original.xctestrun", "sha256": "descriptor"},
                "files": {"app": {"sha256": "actual app"}, "tests": {"sha256": "actual tests"}}}
    state = {"status": "EXECUTED_PASS", "ui": "EXECUTED_PASS", "test_scope": "miniapp_complete",
             "sha": source, "simulator": "owned-uuid", "runtime": "original-runtime",
             "simulator_runtime_selection": {"runtime_version": "27.2"},
             "selected_tests": plan["hanlin"]["selectors"],
             "original_runtime_selectors": plan["miniapps"]["selectors"],
             "app_group": {"status": "EXECUTED_PASS"},
             "native_adapter_assets": {"native_request_proof": "EXECUTED_PASS_RESOURCE_TRANSPORT"},
             "external_modal_result": {"actual_original_fixture": "passed"},
             "original54_job_budget": {"status": "ORIGINAL54_COMPLETED_WITHIN_ORIGINAL_JOB_BUDGET",
                 "source": source, "jobStartedAt": 1000, "deadlineEpoch": 13600,
                 "completedAt": 13000, "originalLimitSeconds": 12600}}
    commands, proofs = {}, {}

    def command(name, argv, timeout):
        commands[name] = {"status": "completed", "completion_recorded": True, "exit": 0,
                          "observed_returncode": 0, "timeout": timeout, "argv": argv,
                          "retainedOutput": {"path": "/evidence/" + name, "sha256": name}}
    command("mini-build.log", ["xcodebuild", "-scheme", "HanlinMiniApps", "build-for-testing"], 3600)
    command("ai-build.log", ["xcodebuild", "-scheme", "AI_HLY", "build-for-testing"], 1800)
    for prefix, phase, selected, count, budget, scheme in (
            ("original-runtimes", "original-runtimes.log", "original_runtime_selectors", 25, 2400, "HanlinMiniApps"),
            ("paired", "paired-tests.log", "selected_tests", 29, 2100, "AI_HLY")):
        summary = {"passedTests": count, "failedTests": 0, "skippedTests": 0, "expectedFailures": 0}
        state["original_runtime_summary" if count == 25 else "summary"] = copy.deepcopy(summary)
        result = "/evidence/" + prefix + ".xcresult"
        command(phase, ["xcodebuild", "-scheme", scheme, "test-without-building", "-destination",
                       "platform=iOS Simulator,id=owned-uuid", "-resultBundlePath", result] +
                ["-only-testing:" + selector for selector in state[selected]], budget)
        nodes_name, summary_name, verify = prefix + "-nodes.json", prefix + "-summary.json", prefix + "-verified.log"
        command(nodes_name, ["xcrun", "xcresulttool", "tests"], 60)
        command(summary_name, ["xcrun", "xcresulttool", "summary"], 60)
        command(verify, ["python3", "Scripts/CI/verify_selected_tests.py", "--selectors", ",".join(state[selected]),
                         "--results", "/evidence/" + nodes_name], 60)
        proofs[prefix] = {"summary": summary, "summaryFile": copy.deepcopy(commands[summary_name]["retainedOutput"]),
                          "nodes": copy.deepcopy(commands[nodes_name]["retainedOutput"]), "verificationLog": verify,
                          "summaryLog": summary_name, "nodesLog": nodes_name, "resultBundle": result}
    return {"original54": state, "originalPlan": plan, "commands": commands, "proofs": proofs,
            "beforeInputs": copy.deepcopy(inputs), "currentInputs": copy.deepcopy(inputs),
            "beforeProducts": copy.deepcopy(products), "currentProducts": copy.deepcopy(products),
            "device": {"udid": "owned-uuid", "isAvailable": True, "state": "Booted", "name": "HanlinPaired-123"},
            "runtime": {"identifier": "original-runtime", "version": "27.2", "buildversion": "actual-build"},
            "freeBytes": extra.ADMISSION_FREE_BYTES, "admittedAt": 13100}


class AdmissionTests(unittest.TestCase):
    def reject(self, payload):
        launch = Mock(return_value="native would launch")
        with self.assertRaises((RuntimeError, KeyError, ValueError)):
            extra.admit_and_execute(payload, launch)
        launch.assert_not_called()

    def test_only_complete_original_prerequisites_reach_the_native_launch_once(self):
        launch = Mock(return_value="launched")
        self.assertEqual(extra.admit_and_execute(fixture(), launch), "launched")
        launch.assert_called_once_with()

    def test_failed_omitted_skipped_or_expected_failure_original54_never_launches(self):
        for prefix in ("original-runtimes", "paired"):
            for key, value in (("passedTests", 0), ("failedTests", 1), ("skippedTests", 1), ("expectedFailures", 1)):
                with self.subTest(prefix=prefix, key=key):
                    payload = fixture()
                    payload["proofs"][prefix]["summary"][key] = value
                    self.reject(payload)
        for key, value in (("status", "TEST_FAILED"), ("ui", "NOT_RUN"), ("test_scope", "miniapp_authoring")):
            payload = fixture(); payload["original54"][key] = value; self.reject(payload)

    def test_wrong_source_sdk_compiler_or_actual_resolved_input_patch_never_launches(self):
        for section, key, value in (("source", "head", "b" * 40), ("source", "canonicalWorkingPatchSHA256", "changed"),
                                    ("toolchain", "swift", "another compiler"), ("hostArchive", "sha256", "another host")):
            payload = fixture(); payload["currentInputs"][section][key] = value; self.reject(payload)
        payload = fixture(); payload["currentInputs"]["sdkInputSHA256"] = "another SDK"; self.reject(payload)
        payload = fixture(); payload["original54"]["sha"] = "c" * 40; self.reject(payload)

    def test_wrong_app_test_or_descriptor_product_never_launches(self):
        for name in ("app", "tests"):
            payload = fixture(); payload["currentProducts"]["files"][name]["sha256"] = "replacement"; self.reject(payload)
        for key in ("path", "sha256"):
            payload = fixture(); payload["currentProducts"]["descriptor"][key] = "replacement"; self.reject(payload)

    def test_exceeded_nonfinite_or_replayed_original_job_budget_never_launches(self):
        for key, value in (("completedAt", 13601), ("completedAt", float("nan")), ("jobStartedAt", False),
                           ("originalLimitSeconds", 15000), ("deadlineEpoch", 16000), ("source", "b" * 40)):
            payload = fixture(); payload["original54"]["original54_job_budget"][key] = value; self.reject(payload)
        for admitted in (13601, float("nan"), float("inf"), 12999):
            payload = fixture(); payload["admittedAt"] = admitted; self.reject(payload)

    def test_zero_exit_with_stop_timeout_or_unrecorded_phase_never_launches(self):
        for phase in ("mini-build.log", "ai-build.log", "original-runtimes.log", "paired-tests.log"):
            for key, value in (("status", "timed_out"), ("status", "interrupted"), ("completion_recorded", False),
                               ("exit", 65), ("stopReason", "RESOURCE_FLOOR"), ("timeout", 99999)):
                payload = fixture(); payload["commands"][phase][key] = value; self.reject(payload)

    def test_changed_selectors_or_native_result_bindings_never_launch(self):
        payload = fixture()
        payload["original54"]["selected_tests"] = payload["original54"]["selected_tests"][:-1]
        self.reject(payload)
        for prefix, phase in (("original-runtimes", "original-runtimes.log"), ("paired", "paired-tests.log")):
            for flag in ("-destination", "-scheme", "-resultBundlePath"):
                payload = fixture(); argv = payload["commands"][phase]["argv"]; argv[argv.index(flag) + 1] = "another"; self.reject(payload)
            payload = fixture(); payload["proofs"][prefix]["nodes"]["sha256"] = "replaced"; self.reject(payload)
            payload = fixture(); payload["proofs"][prefix]["summaryFile"]["sha256"] = "replaced"; self.reject(payload)
            payload = fixture(); payload["commands"][payload["proofs"][prefix]["verificationLog"]]["argv"][-1] = "other-nodes"; self.reject(payload)

    def test_wrong_device_resource_floor_or_missing_original_fixture_never_launches(self):
        for key, value in (("udid", "other"), ("isAvailable", False), ("state", "Shutdown"), ("name", "unowned")):
            payload = fixture(); payload["device"][key] = value; self.reject(payload)
        payload = fixture(); payload["runtime"]["identifier"] = "other"; self.reject(payload)
        payload = fixture(); payload["freeBytes"] -= 1; self.reject(payload)
        payload = fixture(); payload["original54"]["external_modal_result"] = None; self.reject(payload)


class JobClockTests(unittest.TestCase):
    def test_actual_job_start_includes_preparation_and_reduces_only_remaining_budget(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); now = 20000
            iso = lambda value: datetime.datetime.fromtimestamp(value, datetime.timezone.utc).isoformat()
            clock = {"schema": 1, "runID": 123, "runAttempt": 2, "observedAt": iso(19000), "jobs": [
                {"run_id": 123, "run_attempt": 2, "head_sha": "a" * 40, "name": "miniapps", "runner_name": "owned",
                 "status": "in_progress", "started_at": iso(10000)}]}
            path = root / "clock.json"; path.write_text(json.dumps(clock))
            env = {"PAIRED_JOB_CLOCK": str(path), "GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "2",
                   "GITHUB_SHA": "a" * 40, "RUNNER_NAME": "owned"}
            with patch.dict(os.environ, env), patch.object(extra.time, "time", return_value=now), patch.object(extra.time, "monotonic", return_value=500):
                deadline = extra.Original54Deadline(root)
                self.assertEqual(deadline.limit("build", 3600), 2600)
                self.assertEqual(deadline.limit("metadata", 60), 60)
                self.assertEqual(deadline.complete()["jobStartedAt"], 10000)
                for mutate in (lambda x: x["jobs"].append(copy.deepcopy(x["jobs"][0])),
                               lambda x: x.update(jobs=[]), lambda x: x.update(runAttempt=1),
                               lambda x: x["jobs"][0].update(head_sha="b" * 40),
                               lambda x: x["jobs"][0].update(started_at=iso(1)),
                               lambda x: x.update(observedAt=iso(now + 1))):
                    bad = copy.deepcopy(clock); mutate(bad); path.write_text(json.dumps(bad))
                    with self.assertRaises(RuntimeError): extra.Original54Deadline(root)


class DescriptorTests(unittest.TestCase):
    def test_actual_descriptor_macros_bind_only_original_app_and_unit_test_products(self):
        with tempfile.TemporaryDirectory() as temporary:
            derived = Path(temporary); products = derived / "Build/Products"; app = products / "Debug-iphonesimulator/HanlinMiniApps.app"
            tests = app / "PlugIns/HanlinMiniAppsTests.xctest"; tests.mkdir(parents=True)
            (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.itorah.hanlinminiapps", "CFBundleExecutable": "HanlinMiniApps"}))
            (tests / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "HanlinMiniAppsTests"}))
            (app / "HanlinMiniApps").write_bytes(b"fake test fixture binary")
            (tests / "HanlinMiniAppsTests").write_bytes(b"fake test fixture binary")
            target = {"BlueprintName": "HanlinMiniAppsTests", "TestHostPath": "__TESTROOT__/Debug-iphonesimulator/HanlinMiniApps.app",
                      "TestBundlePath": "__TESTHOST__/PlugIns/HanlinMiniAppsTests.xctest"}
            descriptor = products / "Original.xctestrun"
            def write(value): descriptor.write_bytes(plistlib.dumps({"TestConfigurations": [{"TestTargets": [value]}]}))
            write(target)
            self.assertEqual(extra.resolve_descriptor(derived)["testHost"], str(app))
            before = extra.product_snapshot(derived)
            (tests / "HanlinMiniAppsTests").write_bytes(b"replacement")
            self.assertNotEqual(before, extra.product_snapshot(derived))
            for key, value in (("UseDestinationArtifacts", True), ("IsUITestBundle", True),
                               ("TestHostBundleIdentifier", "another.app"), ("TestHostPath", "__UNKNOWN__/app")):
                changed = dict(target); changed[key] = value; write(changed)
                with self.assertRaises(RuntimeError): extra.resolve_descriptor(derived)


class NativeReconciliationTests(unittest.TestCase):
    def result(self):
        scope = scope_document()["miniappsAdditional"]
        children = []
        for entry in scope["exactMethods"]:
            identifier = entry["identifier"]; url = "test://" + identifier
            node = {"nodeType": "Test Case", "nodeIdentifier": identifier.split("/", 1)[1], "nodeIdentifierURL": url, "result": "Passed"}
            if entry["parameterValues"] is not None:
                node["children"] = [{"nodeType": "Arguments", "name": str(v).lower() if isinstance(v, bool) else json.dumps(v),
                                     "nodeIdentifierURL": url + "?args=" + str(i), "result": "Passed"}
                                    for i, v in enumerate(entry["parameterValues"])]
            children.append(node)
        tree = {"testNodes": [{"nodeType": "Unit test bundle", "name": "HanlinMiniAppsTests", "children": children}]}
        summary = {"totalTestCount": 22, "passedTests": 22, "failedTests": 0, "skippedTests": 0,
                   "devicesAndConfigurations": [{"device": {"deviceId": "owned", "osVersion": "27.2", "osBuildNumber": "actual"},
                                                  "passedTests": 26, "failedTests": 0, "skippedTests": 0}]}
        return summary, tree, scope, "owned", {"version": "27.2", "buildversion": "actual"}, {"status": "COMPLETED", "exitCode": 0}

    def test_exact_original22_definitions26_invocations7_arguments_are_required(self):
        args = self.result(); result = extra.reconcile(*args)
        self.assertEqual(result["status"], "EXACT_REQUIRED_EXTRA26_PASSED")
        self.assertEqual((result["actualDefinitions"], result["actualInvocations"], result["parameterInvocations"]), (22, 26, 7))
        for mutation in ("missing definition", "missing argument", "wrong parameter", "wrong device"):
            args = list(self.result()); children = args[1]["testNodes"][0]["children"]
            if mutation == "missing definition": children.pop()
            elif mutation == "wrong device": args[0]["devicesAndConfigurations"][0]["device"]["deviceId"] = "other"
            else:
                node = next(node for node in children if node.get("children"))
                if mutation == "missing argument": node["children"].pop()
                else: node["children"][0]["name"] = "different parameter"
            with self.assertRaises(RuntimeError): extra.reconcile(*args)

    def test_zero_exit_after_stop_cannot_be_reported_as_pass(self):
        for change in ({"status": "STOPPED"}, {"stopReason": "RESOURCE_FLOOR"}, {"stopReason": "ORIGINAL_PHASE_TIMEOUT"}, {"exitCode": 65}):
            args = list(self.result()); args[-1].update(change)
            self.assertEqual(extra.reconcile(*args)["status"], "EXACT_REQUIRED_EXTRA26_EXECUTED_WITH_FAILURES")


if __name__ == "__main__":
    unittest.main()
