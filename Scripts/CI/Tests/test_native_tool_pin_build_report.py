"""New local report controls. Current build outputs below are synthetic, not Apple proof."""
import copy
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Scripts/CI/IntegrationValidation"))
import verify_native_tool_pin_build as report


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


class NativePinBuildAdmissionTests(unittest.TestCase):
    def setUp(self):
        parent = ROOT / "build/native-pin-build-report-controls"
        parent.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=parent)
        self.evidence = Path(self.temp.name)
        report.prepare_reference(ROOT, self.evidence)
        manifest, proof = report.reference(self.evidence)
        self.old = proof / "original"
        e = self.evidence
        for name in ("tested-source-commit.txt", "workflow-commit.txt"):
            (e / name).write_text(manifest["source_pin_commit"] + "\n")
        (e / "producer-commit.txt").write_text(report.PRODUCER + "\n")
        write(e / "tested-source-sha256.json", report.expected_source(manifest, proof))
        # The synthetic positive control retains its authenticated historical guards.
        frozen_workflow = report.read(self.old / "workflow-sha256.json")
        write(e / "workflow-sha256.json", {name: frozen_workflow[name] for name in
              ("Scripts/CI/IntegrationValidation/verify_native_tool_candidate.py",
               "Scripts/CI/IntegrationValidation/verify_native_tool_cancellation_recheck.py",
               "Scripts/CI/IntegrationValidation/xcresult_to_xunit.py", "Scripts/CI/select_stable_xcode.py")})
        self.commands = []
        for command in report.read(self.old / "commands.json"):
            if command["name"] in report.original.TOOLCHAIN:
                self.commands.append(copy.deepcopy(command))
                for stream in ("stdout", "stderr"):
                    shutil.copyfile(self.old / command[stream]["file"], e / command[stream]["file"])
        cli, pre, posts = [], [], []
        for name, directory in (("sdk", "HanlinAgentSDK"), ("core", "HanlinPlatform")):
            data = report.read(self.old / (name + "-Package.resolved"))
            # Deliberately synthetic new resolver origin metadata. These bytes
            # test admission and never constitute a native resolver observation.
            data["originHash"] = ("1" if name == "sdk" else "2") * 64
            for rel in (name + "-Package.resolved", "cli-locks/" + name + "-Package.resolved",
                        "raw-locks/" + name + "-Package.resolved"):
                path = e / rel
                path.parent.mkdir(exist_ok=True)
                write(path, data)
            source = "/fixture/Packages/" + directory + "/Package.resolved"
            cli.append(dict(package=name, source_path=source, file="cli-locks/" + name + "-Package.resolved",
                            sha256=report.sha(e / ("cli-locks/" + name + "-Package.resolved")), resolved=data))
            pre.append(dict(package=name, source_path=source, file=name + "-Package.resolved",
                            sha256=report.sha(e / (name + "-Package.resolved")), resolved=data))
            posts.append(dict(package=name, source_path=source, raw_file="raw-locks/" + name + "-Package.resolved",
                              sha256=report.sha(e / ("raw-locks/" + name + "-Package.resolved")), resolved=data))
            self.add(name + "-resolve", ["xcrun", "swift", "package", "--package-path", "/fixture/Packages/" + directory, "resolve"])
        write(e / "cli-resolution.json", cli)
        write(e / "pre-build-resolution.json", dict(resolver_command="XcodeResolve",
              captured_utc="2026-11-24T01:00:02+00:00", locks=pre))
        write(e / "post-build-resolution.json", posts)
        resolution = "LOCAL REPORT CONTROL\nResolved source packages:\n  ZIPFoundation: https://github.com/weichsel/ZIPFoundation.git @ 0.9.19\n"
        self.add("XcodeResolve", ["xcodebuild", "-resolvePackageDependencies", "-scheme", "HanlinAgentCore",
                 "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", "/fixture/IOSDerivedData"], resolution)
        producer_map = report.read(self.old / "cancellation-reuse-original/producer-07431-sha256.json")
        checkouts = {}
        for phase in ("before", "after"):
            for name, location in (("sdk", "/fixture/Packages/HanlinAgentSDK/.build/checkouts/swift-ai-sdk"),
                                   ("core", "/fixture/Packages/HanlinPlatform/.build/checkouts/swift-ai-sdk"),
                                   ("xcode", "/fixture/IOSDerivedData/SourcePackages/checkouts/swift-ai-sdk")):
                self.add(name + "-" + phase + "-producer-status",
                         ["git", "status", "--porcelain", "--untracked-files=all", "--", "Package.swift", "Sources"],
                         "", cwd=location)
                checkouts[name] = dict(path=location, commit=report.PRODUCER, status="", source_sha256=producer_map)
            write(e / ("producer-checkouts-" + phase + ".json"), checkouts)
        old_build = report.command(self.old, "IOSBuild")
        old_log = (self.old / old_build["stdout"]["file"]).read_text()
        graph = "note: Target dependency graph" + old_log.split("note: Target dependency graph", 1)[1].split("GatherProvisioningInputs", 1)[0]
        self.add("IOSBuild", ["xcodebuild", "build", "-scheme", "HanlinAgentCore", "-destination",
                 "generic/platform=iOS Simulator", "-derivedDataPath", "/fixture/IOSDerivedData", "-resultBundlePath",
                 "/fixture/IOSBuild.xcresult", "-disableAutomaticPackageResolution",
                 "-skipPackagePluginValidation", "-skipMacroValidation", "CODE_SIGNING_ALLOWED=NO"],
                 resolution + graph + "GatherProvisioningInputs\n** BUILD SUCCEEDED **\n", start="2026-11-24T01:00:03+00:00")
        write(e / "commands.json", self.commands)
        write(e / "selected-route.json", dict(exact_test_selector=report.SELECTOR,
              target_validation_group="agent_sdk_exact_source_proof", current_test_invocations=0,
              baseline="HISTORICAL_REFERENCE_ONLY", run_id="LOCAL_CONTROL_NOT_AN_APPLE_RUN",
              unrelated_flags={name: "false" for name in report.UNRELATED_FLAGS}))
        write(e / "process-status.json", dict(preparation_exit=0, ios_resolve_exit=0, ios_build_exit=0,
              current_test_invocations=0, native15_execution="REUSED_VERIFIED", accepted_cases_execution="REUSED_VERIFIED",
              baseline_execution="HISTORICAL_REFERENCE_ONLY", ios_build_execution="EXECUTED",
              **{key: None for key in report.NULL_EXITS}))
        write(e / "pin-build-reuse.json", report.validate_reuse(e))

    def add(self, name, argv, stdout="LOCAL REPORT CONTROL\n", cwd="/fixture/Packages/HanlinAgentSDK",
            start="2026-11-24T01:00:00+00:00"):
        command = dict(name=name, argv=argv, cwd=cwd, exit_code=0,
                       started_utc=start, finished_utc="2026-11-24T01:00:01+00:00" if name != "IOSBuild" else "2026-11-24T01:00:05+00:00")
        for stream, value in (("stdout", stdout), ("stderr", "")):
            path = self.evidence / (name + "." + stream + ".log")
            path.write_text(value)
            command[stream] = dict(file=path.name, sha256=report.sha(path))
        self.commands.append(command)

    def tearDown(self):
        self.temp.cleanup()

    def reject_json(self, name, mutate, expected=None):
        path = self.evidence / name
        raw = path.read_bytes()
        value = json.loads(raw)
        mutate(value)
        write(path, value)
        try:
            result = report.summarize(self.evidence)
            self.assertEqual(result["status"], "BLOCKED", result)
            if expected:
                self.assertTrue(any(expected in error for error in result["errors"]), result["errors"])
            return result
        finally:
            path.write_bytes(raw)

    def test_changed_frozen_workflow_guards_still_block_reuse(self):
        self.assertEqual(report.summarize(self.evidence)["status"], "PASS")
        guards = report.read(self.evidence / "workflow-sha256.json")
        for guard in guards:
            with self.subTest(guard=guard):
                self.reject_json(
                    "workflow-sha256.json",
                    lambda value, path=guard: value.update({path: "0" * 64}),
                    "old strict guard/toolchain selector changed",
                )

    def test_original_fifteen_and_prior_twentyone_keep_sources_with_zero_current_tests(self):
        result = report.summarize(self.evidence)
        self.assertEqual(result["errors"], [])
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["current_test_cases"], [])
        self.assertEqual(result["current_test_invocations"], 0)
        self.assertEqual(len(result["reused_native15_cases"]), 15)
        self.assertEqual({row["run_id"] for row in result["reused_native15_cases"]}, {45292176348})
        self.assertEqual(len(result["reused_prior21_cases"]), 21)
        self.assertEqual({row["run_id"] for row in result["reused_prior21_cases"]},
                         {45259715158, 45273580428, 45282347722, 45273687114})
        self.assertEqual(result["reuse_admission"]["original_summary_status"], "BLOCKED")
        self.assertEqual(result["ios_agent_core_compile"], "PASS")
        self.assertFalse(result["shipping_native_tool_capability"])
        self.assertEqual(result["system_model_generation"], "NOT_RUN")

    def test_post_build_pin_or_origin_drift_cannot_be_relabelled(self):
        path = self.evidence / "raw-locks/sdk-Package.resolved"
        posts_path = self.evidence / "post-build-resolution.json"
        original_raw, original_posts = path.read_bytes(), posts_path.read_bytes()
        for raw in ((self.old / "raw-locks/00-Package.resolved").read_bytes(),
                    json.dumps({**json.loads(original_raw), "originHash": "3" * 64}).encode()):
            path.write_bytes(raw)
            rows = json.loads(original_posts)
            row = next(row for row in rows if row["package"] == "sdk")
            row.update(sha256=report.sha(path), resolved=json.loads(raw))
            write(posts_path, rows)
            result = report.summarize(self.evidence)
            self.assertEqual(result["status"], "BLOCKED")
            self.assertEqual(result["ios_agent_core_compile"], "BLOCKED")
            self.assertIn("Native pin-build admission rejected: post-build raw dependency lock changed", result["errors"])
        path.write_bytes(original_raw)
        posts_path.write_bytes(original_posts)

    def test_source_case_and_producer_tampering_reject_reuse(self):
        self.reject_json("tested-source-sha256.json", lambda value: value.update(
            {"Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinAISDKAgentEngine.swift": "0" * 64}),
            "current source differs beyond")
        self.reject_json("pin-build-original/original/NativeSDKTests.json", lambda value: value.update(tampered=True),
                         "original proof file changed")
        self.reject_json("producer-checkouts-after.json", lambda value: value["xcode"].update(commit=report.original.OLD_PRODUCER),
                         "actual producer checkout changed")
        self.reject_json("selected-route.json", lambda value: value["unrelated_flags"].update(runtime_publish_release="true"),
                         "unrelated workflow flag")

    def test_no_current_test_or_compile_claim_without_its_process_and_graph(self):
        self.reject_json("process-status.json", lambda value: value.update(native_core_test_exit=0),
                         "unexecuted tests were attributed")
        result = self.reject_json("process-status.json", lambda value: value.update(ios_build_exit=None, ios_build_execution="REUSED_VERIFIED"))
        self.assertEqual(result["ios_agent_core_compile"], "NOT_RUN")
        self.reject_json("commands.json", lambda value: next(row for row in value if row["name"] == "IOSBuild")["argv"].remove("-disableAutomaticPackageResolution"),
                         "wrong current iOS build command")
        self.reject_json("commands.json", lambda value: next(row for row in value if row["name"] == "IOSBuild")["argv"].append("-only-testing:Unapproved/test()"),
                         "invoked tests/simulator")
        path = self.evidence / "IOSBuild.stdout.log"
        commands = self.evidence / "commands.json"
        raw, original_commands = path.read_bytes(), commands.read_bytes()
        path.write_bytes(raw.replace(b"HanlinHostContracts", b"UnexpectedHostModule"))
        values = json.loads(original_commands)
        next(row for row in values if row["name"] == "IOSBuild")["stdout"]["sha256"] = report.sha(path)
        write(commands, values)
        result = report.summarize(self.evidence)
        self.assertEqual(result["status"], "BLOCKED")
        self.assertIn("Native pin-build admission rejected: current compiled target graph changed", result["errors"])
        path.write_bytes(raw)
        commands.write_bytes(original_commands)


if __name__ == "__main__":
    unittest.main()
