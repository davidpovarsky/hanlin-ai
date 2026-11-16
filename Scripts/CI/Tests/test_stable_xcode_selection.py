import subprocess
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

from Scripts.CI.select_stable_xcode import select
from Scripts.CI.verify_exact_json_vendor import verify


class StableEnvironmentTests(unittest.TestCase):
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
