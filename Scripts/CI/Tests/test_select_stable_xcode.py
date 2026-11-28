import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "select_stable_xcode", Path(__file__).resolve().parents[1] / "select_stable_xcode.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class StableXcodeSelectionTests(unittest.TestCase):
    def choose(self, output, name="Xcode.app"):
        with tempfile.TemporaryDirectory() as temporary:
            applications = Path(temporary)
            executable = applications / name / "Contents/Developer/usr/bin/xcodebuild"
            executable.parent.mkdir(parents=True)
            executable.touch()
            with patch.object(module.subprocess, "run", return_value=subprocess.CompletedProcess(
                    [], 0, stdout=output, stderr="")):
                return module.select(applications).name

    def test_public_27_release_with_letter_suffix_is_accepted(self):
        self.assertEqual(self.choose("Xcode 27.0\nBuild version 27A266a\n"), "Xcode.app")

    def test_unknown_letter_suffix_does_not_admit_an_unverified_seed(self):
        with self.assertRaisesRegex(RuntimeError, "No installed stable"):
            self.choose("Xcode 27.0\nBuild version 27A266b\n")

    def test_beta_named_bundle_stays_excluded(self):
        with self.assertRaisesRegex(RuntimeError, "No installed stable"):
            self.choose("Xcode 27.0\nBuild version 27A266a\n", "Xcode-beta.app")

    def test_existing_numeric_release_remains_accepted(self):
        self.assertEqual(self.choose("Xcode 27.1\nBuild version 27A9275\n"), "Xcode.app")


if __name__ == "__main__":
    unittest.main()
