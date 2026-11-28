"""Focused provenance controls for the authentic pinned dependency symlinks."""
from pathlib import Path
import hashlib
import importlib.util
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("motion_inputs", ROOT / "docs/chat-motion/record_sdk_inputs.py")
inputs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inputs)


class MotionInputProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="hanlin-motion-inputs-")
        self.root = Path(self.temporary.name) / "checkout"
        self.root.mkdir()
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)

    def tearDown(self):
        self.temporary.cleanup()

    def file(self, path, data=b"original fixture data"):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        return target

    def link(self, path, target):
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.symlink_to(target)
        return file

    def index(self):
        subprocess.run(["git", "-C", str(self.root), "add", "--all"], check=True)

    def test_original_pinned_directory_and_file_links_record_git_blob_bytes(self):
        self.file(".agents/skills/example.md")
        self.file("AGENTS.md")
        original = {
            ".claude/skills": ("../.agents/skills", "2b7a412b8fa0fb7e985b0793321bd4e698f2b6cd"),
            ".github/copilot-instructions.md": ("../AGENTS.md", "be77ac83a1895cfa9e271961ba1e565c273c717c"),
            "CLAUDE.md": ("AGENTS.md", "47dc3e3d863cfb5727b87d785d09abf9743c0a72"),
        }
        for path, (target, _) in original.items():
            self.link(path, target)
        self.index()
        records = {item["path"]: item for item in inputs.tracked_records(self.root, ["."])}
        self.assertEqual(len(records), 5)
        for path, (target, blob) in original.items():
            self.assertEqual(records[path], {"path": path, "bytes": len(target.encode()),
                "sha256": hashlib.sha256(target.encode()).hexdigest(), "symlink": target,
                "gitMode": "120000", "gitBlob": blob})
        self.assertIn(".agents/skills/example.md", records)

    def test_modified_link_is_rejected_against_recorded_git_blob(self):
        link = self.link("link", "original")
        self.index()
        link.unlink(); link.symlink_to("changed")
        with self.assertRaisesRegex(ValueError, "differs from its Git blob"):
            inputs.tracked_records(self.root, ["."])

    def test_link_replaced_with_same_target_text_as_regular_file_is_rejected(self):
        link = self.link("link", "original")
        self.index()
        link.unlink(); link.write_text("original")
        with self.assertRaisesRegex(ValueError, "input type differs from Git"):
            inputs.tracked_records(self.root, ["."])

    def test_regular_file_replaced_with_alias_is_rejected(self):
        source = self.file("source")
        target = self.file("target")
        self.index()
        source.unlink(); source.symlink_to(target.name)
        with self.assertRaisesRegex(ValueError, "input type differs from Git"):
            inputs.tracked_records(self.root, ["."])

    def test_missing_regular_file_is_still_rejected(self):
        source = self.file("source")
        self.index(); source.unlink()
        with self.assertRaisesRegex(ValueError, "not materialized"):
            inputs.tracked_records(self.root, ["."])

    def test_external_directory_link_is_recorded_without_reading_destination(self):
        outside = Path(self.temporary.name) / "outside"
        outside.mkdir(); (outside / "unrelated").write_bytes(b"not a dependency input")
        self.link("link", str(outside)); self.index()
        records = inputs.tracked_records(self.root, ["."])
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["sha256"], hashlib.sha256(os.fsencode(str(outside))).hexdigest())
        self.assertEqual(records[0]["bytes"], len(os.fsencode(str(outside))))


if __name__ == "__main__":
    unittest.main()
