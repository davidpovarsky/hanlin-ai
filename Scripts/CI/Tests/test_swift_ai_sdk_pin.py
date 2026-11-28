import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

READER = Path(__file__).resolve().parents[1] / "IntegrationValidation" / "swift_ai_sdk_pin.py"
SPEC = importlib.util.spec_from_file_location("swift_ai_sdk_pin", READER)
reader = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(reader)


class SwiftAISDKPinTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.manifest = self.root / reader.CANONICAL_MANIFEST
        self.manifest.parent.mkdir(parents=True)

    def write_manifest(self, revision="a" * 40, url=reader.SDK_URL, extra=""):
        self.manifest.write_text(
            'let package = Package(dependencies: [\n'
            '  .package(url: "https://example.invalid/unrelated.git", revision: "' + "c" * 40 + '"),\n'
            '  .package(\n    url: "' + url + '",\n    revision: "' + revision + '"\n  ),\n'
            + extra + '\n])\n'
        )

    def test_uses_current_canonical_pin_instead_of_a_previous_revision(self):
        self.write_manifest()
        self.assertEqual(reader.canonical_revision(self.root), "a" * 40)
        self.write_manifest(revision="b" * 40)
        self.assertEqual(reader.canonical_revision(self.root), "b" * 40)

    def test_rejects_other_forks(self):
        self.write_manifest(url="https://github.com/another-owner/swift-ai-sdk.git")
        with self.assertRaisesRegex(ValueError, "original Hanlin fork URL"):
            reader.canonical_revision(self.root)

    def test_rejects_non_commit_or_malformed_revision(self):
        for revision in ["main", "a" * 39, "g" * 40, "A" * 40, "a" * 41]:
            with self.subTest(revision=revision):
                self.write_manifest(revision=revision)
                with self.assertRaisesRegex(ValueError, "40-character Git SHA"):
                    reader.canonical_revision(self.root)

    def test_rejects_missing_or_ambiguous_revision_dependency(self):
        for text in [
            "let package = Package(dependencies: [])",
            '.package(url: "' + reader.SDK_URL + '", branch: "main")',
        ]:
            self.manifest.write_text(text)
            with self.assertRaisesRegex(ValueError, "one revision-pinned"):
                reader.canonical_revision(self.root)
        self.write_manifest(extra='.package(url: "' + reader.SDK_URL + '", revision: "' + "b" * 40 + '")')
        with self.assertRaisesRegex(ValueError, "one revision-pinned"):
            reader.canonical_revision(self.root)

    def test_cli_uses_explicit_repository_from_a_different_working_directory(self):
        self.write_manifest()
        result = subprocess.run(
            [sys.executable, str(READER), str(self.root)],
            cwd=self.manifest.parent,
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertEqual(result.stdout, "a" * 40 + "\n")
        self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
