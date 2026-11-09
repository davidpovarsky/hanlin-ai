import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("patcher", Path(__file__).parents[1] / "apply-node-source-patches.py")
patcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patcher)


class NodeSourcePatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.target = self.source / "deps/v8/test.h"
        self.target.parent.mkdir(parents=True)
        self.target.write_bytes(b"old value")
        self.manifest = self.root / "Scripts/Runtime/Patches/test.json"
        self.manifest.parent.mkdir(parents=True)
        self.change = {"path": "deps/v8/test.h", "beforeSHA256": patcher.digest(b"old value"), "afterSHA256": patcher.digest(b"new value"), "replacements": [{"before": "old", "after": "new"}]}
        self.data = {"schemaVersion": 1, "sourceCommit": "a" * 40, "upstreamCommit": "b" * 40, "files": [self.change]}
        self.lock = self.root / "lock.json"
        self.save()

    def save(self):
        self.manifest.write_text(json.dumps(self.data), encoding="utf-8")
        self.lock_data = {"node": {"commit": "a" * 40, "sourcePatches": [{"path": "Scripts/Runtime/Patches/test.json", "sha256": patcher.digest(self.manifest.read_bytes()), "upstreamCommit": "b" * 40}]}}
        self.lock.write_text(json.dumps(self.lock_data), encoding="utf-8")

    def apply(self):
        return patcher.apply_patches(self.source, self.lock, self.root)

    def test_verified_patch_is_idempotent(self):
        self.assertEqual(len(self.apply()), 1)
        self.assertEqual(self.target.read_bytes(), b"new value")
        self.apply()
        self.assertEqual(self.target.read_bytes(), b"new value")

    def test_tampered_manifest_is_rejected(self):
        self.manifest.write_bytes(self.manifest.read_bytes() + b" ")
        with self.assertRaisesRegex(ValueError, "checksum"):
            self.apply()
        self.assertEqual(self.target.read_bytes(), b"old value")

    def test_other_node_commit_is_rejected(self):
        self.data["sourceCommit"] = "c" * 40
        self.save()
        with self.assertRaisesRegex(ValueError, "source commit"):
            self.apply()

    def test_preimage_validation_precedes_all_writes(self):
        second = self.target.parent / "second.h"
        second.write_bytes(b"unexpected")
        self.data["files"].append({**self.change, "path": "deps/v8/second.h"})
        self.save()
        with self.assertRaisesRegex(ValueError, "preimage"):
            self.apply()
        self.assertEqual(self.target.read_bytes(), b"old value")

    def test_postimage_mismatch_is_rejected(self):
        self.change["afterSHA256"] = "0" * 64
        self.save()
        with self.assertRaisesRegex(ValueError, "postimage"):
            self.apply()
        self.assertEqual(self.target.read_bytes(), b"old value")

    def test_ambiguous_replacement_is_rejected(self):
        self.target.write_bytes(b"old old")
        self.change["beforeSHA256"] = patcher.digest(self.target.read_bytes())
        self.save()
        with self.assertRaisesRegex(ValueError, "Ambiguous"):
            self.apply()

    def test_source_path_escape_is_rejected(self):
        escaped = self.source / "outside.h"
        escaped.write_bytes(b"old value")
        self.change["path"] = "outside.h"
        self.save()
        with self.assertRaisesRegex(ValueError, "escapes"):
            self.apply()
        self.assertEqual(escaped.read_bytes(), b"old value")

    def test_upstream_provenance_mismatch_is_rejected(self):
        self.data["upstreamCommit"] = "c" * 40
        self.save()
        with self.assertRaisesRegex(ValueError, "provenance"):
            self.apply()
