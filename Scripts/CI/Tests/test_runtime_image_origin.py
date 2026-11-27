"""Controlled reader/protocol negatives; these do not execute or certify iOS."""
import copy
import ast
import importlib.util
import json
import os
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import uuid


MODULE = Path(__file__).resolve().parents[3] / "Scripts/ProductSplit/observe_runtime_image_origin.py"
SPEC = importlib.util.spec_from_file_location("runtime_image_origin", MODULE)
origin = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(origin)


def thin(identifier, cpu=0x0100000C, subtype=0):
    # Explicit controlled binary input for the LC_UUID reader, never a runnable
    # artifact or a claimed native image receipt.
    return struct.pack("<8I", 0xFEEDFACF, cpu, subtype, 6, 1, 24, 0, 0) + struct.pack("<2I", 0x1B, 24) + uuid.UUID(identifier).bytes


class RuntimeImageOriginTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.device = self.root / "owned-device"
        self.app = self.device / "data/Containers/Bundle/Application/owned/app.app"
        self.app.mkdir(parents=True)
        self.products = self.root / "products"
        self.products.mkdir()
        self.platform = self.root / "platform"
        self.platform.mkdir()
        self.catalog = {}
        for name, identifier in [
            ("MiniApps", "11111111-1111-4111-8111-111111111111"),
            ("Frameworks/NativeScript.framework/NativeScript", "22222222-2222-4222-8222-222222222222"),
            ("Frameworks/React.framework/React", "33333333-3333-4333-8333-333333333333"),
            ("Frameworks/hermesvm.framework/hermesvm", "44444444-4444-4444-8444-444444444444"),
        ]:
            path = self.app / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(thin(identifier))
            self.catalog[name] = {"file": origin.record(path), "uuids": {"arm64": identifier}}
        self.attempt = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        self.source = "b" * 40
        self.request = {"schema": 1, "attempt": self.attempt, "source": self.source,
                        "checkpoint": "nativescript", "requestID": "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
                        "pid": 101, "runnerPID": 102, "bundleID": origin.APP_ID,
                        "caseName": "-[HanlinMiniAppsUITests.MiniAppsProductionRuntimeUITests " + origin.CHECKPOINTS["nativescript"] + "]",
                        "at": 105.0, "accessibilityHeader": "Attributes: Application, 0x123, pid: 101, label: 'Hanlin MiniApps'"}

    def sample(self, checkpoint="nativescript"):
        paths = ["MiniApps", *origin.REQUIRED_IMAGES[checkpoint]]
        return {"header": {"pid": 101, "Path": str(self.app / "MiniApps"), "Platform": "iOS Simulator",
                           "Launch TimeEpoch": 102.123, "Date/TimeEpoch": 106.234},
                "images": [{"start": 4096 * (i + 1), "end": 4096 * (i + 1) + 1023,
                            "label": Path(name).name, "path": str(self.app / name),
                            "uuid": self.catalog[name]["uuids"]["arm64"]} for i, name in enumerate(paths)]}

    def classify(self, sample, checkpoint="nativescript"):
        return origin.classify_images(sample, app=self.app, products=self.products, device_root=self.device,
            catalog=self.catalog, architecture="arm64", executable="MiniApps", checkpoint=checkpoint,
            platform_roots=[self.platform])

    def identity(self, sample, before=None, after=None):
        process = {"pid": 101, "parentPID": 50, "launchEpoch": 102.0, "path": str(self.app / "MiniApps")}
        return origin.validate_sample_identity(sample, before or process, after or process,
            executable=self.app / "MiniApps", started=100.5, request_at=105.0,
            sample_started=106.0, sample_finished=107.5)

    def request_is_valid(self, request, **overrides):
        values = {"attempt": self.attempt, "source": self.source, "checkpoint": "nativescript",
                  "started": 100.5, "now": 108.0, "modified": 105.1}
        values.update(overrides)
        return origin.validate_request(request, **values)

    def test_actual_sample_grammar_retains_every_uuid_and_path_but_macos_is_not_simulator_proof(self):
        # Grammar observed in original real602 sample e70c29c6, Report Version7.
        # Values below are controlled; this is explicitly not an execution receipt.
        text = ("Process:         MiniApps [101]\nPath:            " + str(self.app / "MiniApps") +
                "\nCode Type:       ARM64\nPlatform:        macOS\n"
                "Date/Time:       1970-01-01 00:01:46.234 +0000\n"
                "Launch Time:     1970-01-01 00:01:42.123 +0000\n\nBinary Images:\n"
                "  0x1000 - 0x13ff +MiniApps (1) <11111111-1111-4111-8111-111111111111> " +
                str(self.app / "MiniApps") + "\n")
        parsed = origin.parse_sample(text)
        self.assertEqual(parsed["images"][0]["uuid"], self.catalog["MiniApps"]["uuids"]["arm64"])
        with self.assertRaisesRegex(RuntimeError, "macOS"):
            self.identity(parsed)
        for changed in [text.replace("<11111111-1111-4111-8111-111111111111>", "<missing>"),
                        text.replace("\nBinary Images:\n", "\nOther:\n"), text + "unparsed image\n"]:
            with self.assertRaises(RuntimeError):
                origin.parse_sample(changed)

    def test_macho_uuid_reader_qualifies_actual_slices_and_rejects_missing_duplicate_or_overlapping_commands(self):
        first = (self.app / "MiniApps").read_bytes()
        second_id = "55555555-5555-4555-8555-555555555555"
        second = thin(second_id, cpu=0x01000007, subtype=3)
        path = self.root / "universal"
        path.write_bytes(struct.pack(">2I", 0xCAFEBABE, 2) +
                         struct.pack(">5I", 0x0100000C, 0, 64, len(first), 4) +
                         struct.pack(">5I", 0x01000007, 3, 128, len(second), 4) +
                         b"\0" * 16 + first + b"\0" * 8 + second)
        self.assertEqual(origin.macho_uuids(path), {"arm64": self.catalog["MiniApps"]["uuids"]["arm64"], "x86_64": second_id})
        for changed in [first[:-1], first[:16] + struct.pack("<I", 2) + first[20:],
                        first[:36] + struct.pack("<I", 400) + first[40:]]:
            path.write_bytes(changed)
            with self.assertRaises(RuntimeError):
                origin.macho_uuids(path)

    def test_nonce_source_case_and_scalar_types_cannot_self_qualify(self):
        self.assertEqual(self.request_is_valid(self.request), self.request)
        changes = {"schema": True, "pid": True, "runnerPID": 101, "attempt": "d" * 36,
                   "source": "c" * 40, "checkpoint": "expo", "bundleID": "com.other.app",
                   "caseName": "-[OtherTests differentMethod]", "accessibilityHeader": "Attributes: Application, pid: 999,"}
        for key, value in changes.items():
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                self.request_is_valid({**self.request, key: value})

    def test_stale_future_and_nonfinite_requests_are_rejected(self):
        for value in (100.4, 108.1, float("nan"), float("inf"), True):
            with self.subTest(value=value), self.assertRaises(RuntimeError):
                self.request_is_valid({**self.request, "at": value})
        for modified in (100.4, 108.1):
            with self.assertRaises(RuntimeError):
                self.request_is_valid(self.request, modified=modified)

    def test_current_pid_path_launch_and_sample_window_must_all_agree(self):
        self.identity(self.sample())
        for key, value in [("pid", 999), ("Platform", "macOS"), ("Date/TimeEpoch", 105.9),
                           ("Date/TimeEpoch", 108.0), ("Launch TimeEpoch", 100.2), ("Launch TimeEpoch", 105.1)]:
            sample = self.sample()
            sample["header"][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(RuntimeError):
                self.identity(sample)
        replacement = {"pid": 101, "parentPID": 50, "launchEpoch": 104.0, "path": str(self.app / "MiniApps")}
        with self.assertRaises(RuntimeError):
            self.identity(self.sample(), after=replacement)

    def test_loaded_product_bytes_uuid_and_architecture_must_match_frozen_built_catalog(self):
        result = self.classify(self.sample())
        self.assertEqual(len(result["productImages"]), 2)
        sample = self.sample()
        sample["images"][1]["uuid"] = "e" * 36
        with self.assertRaises(RuntimeError):
            self.classify(sample)
        original = (self.app / "MiniApps").read_bytes()
        (self.app / "MiniApps").write_bytes(original + b"modified-after-build")
        with self.assertRaises(RuntimeError):
            self.classify(self.sample())

    def test_product_sidecopy_is_rejected_even_when_uuid_and_bytes_match(self):
        sidecopy = self.products / "NativeScript"
        sidecopy.write_bytes((self.app / "Frameworks/NativeScript.framework/NativeScript").read_bytes())
        sample = self.sample()
        sample["images"][1]["path"] = str(sidecopy)
        with self.assertRaisesRegex(RuntimeError, "outside"):
            self.classify(sample)

    def test_foreign_container_unknown_image_and_duplicate_image_cannot_qualify(self):
        for path in [self.device / "foreign/app/Unknown", self.root / "unqualified/Unknown"]:
            sample = self.sample()
            sample["images"].append({"start": 9999, "end": 10000, "path": str(path), "label": "Unknown",
                                     "uuid": "99999999-9999-4999-8999-999999999999"})
            with self.assertRaises(RuntimeError):
                self.classify(sample)
        sample = self.sample()
        sample["images"].append(dict(sample["images"][1]))
        with self.assertRaises(RuntimeError):
            self.classify(sample)

    def test_platform_rows_are_explicitly_separate_and_cannot_replace_selected_engine(self):
        sample = self.sample()
        sample["images"].append({"start": 9999, "end": 10000, "path": str(self.platform / "Foundation"),
                                 "label": "Foundation", "uuid": "99999999-9999-4999-8999-999999999999"})
        result = self.classify(sample)
        self.assertEqual(result["platformToolchainImages"][0]["qualification"],
                         "RECORDED_PLATFORM_TOOLCHAIN_IMAGE_NOT_PRODUCT_SOURCE_PROOF")
        sample["images"] = [sample["images"][0], sample["images"][2]]
        with self.assertRaises(RuntimeError):
            self.classify(sample)
        self.assertEqual(len(self.classify(self.sample("expo"), "expo")["productImages"]), 3)

    def test_descriptor_only_injects_fresh_attempt_in_the_one_original_ui_target(self):
        for version in (1, 2):
            target = {"BlueprintName": origin.UI_TARGET, "IsUITestBundle": True,
                      "EnvironmentVariables": {"ORIGINAL": "preserved"}, "OnlyTestIdentifiers": ["unchanged"],
                      "TestHostPath": "/original/runner", "TestBundlePath": "/original/test"}
            document = ({origin.UI_TARGET: target, "OtherUnitTests": {"untouched": True}}
                        if version == 1 else {"__xctestrun_metadata__": {"FormatVersion": 2},
                        "TestConfigurations": [{"IsEnabled": True, "TestTargets": [target, {"BlueprintName": "OtherUnitTests"}]}]})
            original = copy.deepcopy(document)
            result = origin.origin_descriptor(document, self.attempt, self.source)
            self.assertEqual(document, original)
            current = origin.descriptor_target(result)
            self.assertEqual(current["EnvironmentVariables"], {"ORIGINAL": "preserved",
                             origin.ATTEMPT_ENV: self.attempt, origin.SOURCE_ENV: self.source})
            del current["EnvironmentVariables"][origin.ATTEMPT_ENV]
            del current["EnvironmentVariables"][origin.SOURCE_ENV]
            self.assertEqual(result, document)
            with self.assertRaises(RuntimeError):
                origin.origin_descriptor(origin.origin_descriptor(document, self.attempt, self.source), self.attempt, self.source)

    def test_ambiguous_disabled_foreign_or_coerced_descriptor_is_rejected(self):
        target = {"BlueprintName": origin.UI_TARGET, "IsUITestBundle": True}
        candidates = [
            {"__xctestrun_metadata__": {"FormatVersion": True}, origin.UI_TARGET: target},
            {origin.UI_TARGET: {**target, "IsEnabled": False}},
            {origin.UI_TARGET: {**target, "UseDestinationArtifacts": True}},
            {"__xctestrun_metadata__": {"FormatVersion": 2},
             "TestConfigurations": [{"TestTargets": [target, dict(target)]}]},
            {"__xctestrun_metadata__": {"FormatVersion": 2},
             "TestConfigurations": [{"IsEnabled": "true", "TestTargets": [target]}]},
        ]
        for candidate in candidates:
            with self.subTest(candidate=candidate), self.assertRaises(RuntimeError):
                origin.origin_descriptor(candidate, self.attempt, self.source)

    def test_terminal_cannot_turn_missing_failed_or_boolean_native_exit_into_pass(self):
        for value in [{}, {"status": "REQUIRES_ORIGINAL_25_XCTEST_AND_THREE_BRIDGE_RESULT_GATES", "nativeExit": False},
                      {"status": "ORIGIN_NOT_QUALIFIED", "nativeExit": 0},
                      {"status": "REQUIRES_ORIGINAL_25_XCTEST_AND_THREE_BRIDGE_RESULT_GATES", "nativeExit": 0,
                       "stopReason": None, "errors": [], "observations": {"expo": {}}, "attempted": ["expo"]}]:
            with self.subTest(value=value), self.assertRaises(RuntimeError):
                origin.validate_origin_terminal(value, self.root)

    def test_descriptor_invocation_keeps_original_selection_and_rejects_reuse_or_hidden_skips(self):
        selectors = ["HanlinMiniAppsTests/OriginalUnits", "HanlinMiniAppsUITests/OriginalUI"]
        argv = ["xcodebuild", "-project", "AI_HLY.xcodeproj", "-scheme", "HanlinMiniApps",
                "-destination", "platform=iOS Simulator,id=owned,arch=arm64",
                "-parallel-testing-enabled", "NO", "-derivedDataPath", "/original/DerivedData",
                "-skipPackagePluginValidation", "CODE_SIGNING_ALLOWED=YES", "test-without-building",
                "-resultBundlePath", "/owned/Original.xcresult", *["-only-testing:" + value for value in selectors]]
        with patch.dict(os.environ, {"SPLIT_REUSE_NATIVE_PROOF": "0"}):
            result = origin.origin_test_command(argv, "/original/Products/attempt.xctestrun", selectors)
            self.assertEqual(result, ["xcodebuild", "-destination", "platform=iOS Simulator,id=owned,arch=arm64",
                "-parallel-testing-enabled", "NO", "-skipPackagePluginValidation", "CODE_SIGNING_ALLOWED=YES",
                "test-without-building", "-resultBundlePath", "/owned/Original.xcresult",
                *["-only-testing:" + value for value in selectors], "-xctestrun", "/original/Products/attempt.xctestrun"])
            for changed in [argv + ["-skip-testing:HanlinMiniAppsUITests/OriginalUI"],
                            argv[:-1], argv + ["-only-testing:Unrequested"],
                            ["YES" if value == "NO" else value for value in argv]]:
                with self.assertRaises(RuntimeError):
                    origin.origin_test_command(changed, "/descriptor", selectors)
        with patch.dict(os.environ, {"SPLIT_REUSE_NATIVE_PROOF": "1"}), self.assertRaises(RuntimeError):
            origin.origin_test_command(argv, "/descriptor", selectors)

    def test_additive_scope_uses_complete_original_plan_and_keeps_all_three_runtime_verifiers(self):
        path = MODULE.with_name("run_native_acceptance.py")
        tree = ast.parse(path.read_text())
        plan_nodes = [node for node in tree.body if isinstance(node, ast.Assign)
                      and any(isinstance(target, ast.Name) and target.id == "UI_PLANS"
                              or isinstance(target, ast.Subscript) and isinstance(target.value, ast.Name)
                              and target.value.id == "UI_PLANS" for target in node.targets)]
        namespace = {}
        exec(compile(ast.Module(body=plan_nodes, type_ignores=[]), str(path), "exec"), namespace)
        plans = namespace["UI_PLANS"]
        self.assertIs(plans["production_runtimes_with_origin"], plans["production_runtimes"])
        self.assertEqual(plans["production_runtimes"][1], 25)
        self.assertEqual(plans["baseline"][1], 7)
        self.assertEqual(plans["cross_app"][1], 23)
        self.assertEqual(plans["notification_os"][1], 1)
        main = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == "main")
        verification = [node for node in ast.walk(main) if isinstance(node, ast.If)
                        and "production_runtimes_with_origin" in ast.unparse(node.test)
                        and any(isinstance(call, ast.Call) and isinstance(call.func, ast.Name)
                                and call.func.id == "command" and any(isinstance(arg, ast.Constant)
                                and arg.value == "external-modal-actual-result.json" for arg in call.args)
                                for call in ast.walk(node))]
        self.assertEqual(len(verification), 1)
        body = ast.unparse(verification[0])
        for name in ("external-modal-actual-result.json", "nativescript-window-actual-results.json",
                     "nativescript-package-window-actual-results.json"):
            self.assertIn(name, body)


if __name__ == "__main__":
    unittest.main()
