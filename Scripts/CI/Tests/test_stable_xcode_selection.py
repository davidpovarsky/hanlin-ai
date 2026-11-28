import subprocess
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

from Scripts.CI.select_stable_xcode import select
from Scripts.CI.select_installed_simulator import select as select_simulator
from Scripts.CI.select_installed_simulator import family_for_selectors
from Scripts.CI.verify_exact_json_vendor import verify


class StableEnvironmentTests(unittest.TestCase):
    def test_compact_selectors_require_a_real_narrow_device_and_cannot_mix_wide_ui(self):
        narrow = "AI_HLYUITests/HanlinMorphComposerUITests/testCompactNavigationKeepsDraft"
        self.assertEqual(family_for_selectors(narrow + ",AI_HLYTests/NativeComposerLineSizingTests"), "iPhone")
        self.assertEqual(family_for_selectors("AI_HLYUITests/HanlinMorphComposerUITests/testWideNavigationKeepsDraft"), "iPad")
        with self.assertRaisesRegex(ValueError, "separate narrow-device run"):
            family_for_selectors(narrow + ",AI_HLYUITests/HanlinMorphComposerUITests/testWideNavigationKeepsDraft")

    def test_explicit_narrow_family_does_not_select_a_wide_ipad(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "Contents").mkdir(); (root / "Contents/Info.plist").touch()
            identity = "com.apple.CoreSimulator.SimRuntime.iOS-27-2"
            runtime = {"platform":"iOS", "version":"27.2", "isAvailable":True,
                "identifier":identity, "runtimeRoot":str(root), "bundlePath":str(root)}
            devices = {"devices":{identity:[
                {"isAvailable":True,"name":"iPad Pro 13-inch (M5)","udid":"wide"},
                {"isAvailable":True,"name":"iPhone 18","udid":"narrow"}]}}
            self.assertEqual(select_simulator(devices,{"runtimes":[runtime]},"27.2","iPhone")["device"]["udid"], "narrow")

    def test_parallel_iphone_runtime_does_not_make_valid_ipad_selection_ambiguous(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            info = root / "Contents/Info.plist"
            info.parent.mkdir(); info.touch()
            canonical = "com.apple.CoreSimulator.SimRuntime.iOS-27-2"
            records = [{"platform": "iOS", "version": "27.2", "isAvailable": True,
                "identifier": identity, "runtimeRoot": str(root), "bundlePath": str(root)}
                for identity in [canonical, canonical + "-iPhone19-4"]]
            devices = {"devices": {canonical: [{"isAvailable": True, "name": "iPad Pro 13-inch (M5)", "udid": "original-ipad"}],
                canonical + "-iPhone19-4": [{"isAvailable": True, "name": "iPhone 18", "udid": "other-device"}]}}
            self.assertEqual(select_simulator(devices, {"runtimes": records}, "27.2")["device"]["udid"], "original-ipad")
            info.unlink()
            with self.assertRaisesRegex(RuntimeError, "No available iPad"):
                select_simulator(devices, {"runtimes": records}, "27.2")

    def test_owned_renamed_device_reuse_preserves_exact_hardware_runtime_and_identity(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); (root / "Contents").mkdir(); (root / "Contents/Info.plist").touch()
            identity = "com.apple.CoreSimulator.SimRuntime.iOS-27-2"
            runtime = {"platform": "iOS", "version": "27.2", "isAvailable": True,
                "identifier": identity, "runtimeRoot": str(root), "bundlePath": str(root)}
            prepared = {"isAvailable": True, "name": "Hanlin-Phase2-owned-123", "udid": "prepared",
                "state": "Booted", "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5"}
            devices = {"devices": {identity: [
                {"isAvailable": True, "name": "iPad Pro 13-inch (M5)", "udid": "unused", "state": "Shutdown"},
                prepared]}}
            chosen = select_simulator(devices, {"runtimes": [runtime]}, "27.2", "iPad", "prepared")
            self.assertEqual(chosen["device"], prepared)
            for family, udid in [("iPhone", "prepared"), ("iPad", "missing")]:
                with self.assertRaises(RuntimeError):
                    select_simulator(devices, {"runtimes": [runtime]}, "27.2", family, udid)
            with self.assertRaises(RuntimeError):
                select_simulator(devices, {"runtimes": [runtime]}, "27.1", "iPad", "prepared")

    def test_actual_beta_build_behind_stable_spelling_cannot_win(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in ["Xcode_27.2.app", "Xcode_27.3.app"]:
                binary = root / name / "Contents/Developer/usr/bin/xcodebuild"
                binary.parent.mkdir(parents=True)
                binary.touch()
            def version(command, **_):
                beta = "27.3" in command[0]
                return subprocess.CompletedProcess(command, 0,
                    "Xcode 27.3\nBuild version 27C5020n\n" if beta else "Xcode 27.2\nBuild version 27B52\n", "")
            with patch("Scripts.CI.select_stable_xcode.subprocess.run", side_effect=version):
                self.assertEqual(select(root), (root / "Xcode_27.2.app").resolve())

    def test_absent_stable_toolchain_fails_without_beta_fallback(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "Xcode_27.3_beta.app").mkdir()
            with self.assertRaisesRegex(RuntimeError, "No installed stable"):
                select(root)

    def test_vendored_validator_preserves_original_bytes_after_only_bundle_spelling(self):
        proof = verify(Path(__file__).resolve().parents[3])
        self.assertEqual(proof["files"], 132)


if __name__ == "__main__":
    unittest.main()
