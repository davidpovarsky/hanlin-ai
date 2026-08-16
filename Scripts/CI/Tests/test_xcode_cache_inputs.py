from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest


SCRIPT_PATH = Path(__file__).parents[1] / "xcode_cache_inputs.py"
SPEC = importlib.util.spec_from_file_location("xcode_cache_inputs", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
xcode_cache_inputs = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(xcode_cache_inputs)


class XcodeCacheInputsTests(unittest.TestCase):
    def test_restores_mtime_only_when_content_is_identical(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            source = repository / "Sources" / "Feature.swift"
            source.parent.mkdir()
            source.write_text("let value = 1\n", encoding="utf-8")
            requested_mtime = 1_700_000_000_123_456_789
            os.utime(source, ns=(requested_mtime, requested_mtime))
            original_mtime = source.stat().st_mtime_ns
            manifest = repository / "build" / "source-mtimes.json"

            self.assertEqual(
                xcode_cache_inputs.capture(
                    repository,
                    manifest,
                    ["Sources"],
                    set(),
                    "abc123",
                ),
                0,
            )
            new_mtime = original_mtime + 5_000_000_000
            os.utime(source, ns=(new_mtime, new_mtime))

            self.assertEqual(xcode_cache_inputs.restore(repository, manifest), 0)
            self.assertEqual(source.stat().st_mtime_ns, original_mtime)

            source.write_text("let value = 2\n", encoding="utf-8")
            changed_mtime = original_mtime + 10_000_000_000
            os.utime(source, ns=(changed_mtime, changed_mtime))

            self.assertEqual(xcode_cache_inputs.restore(repository, manifest), 0)
            self.assertEqual(source.stat().st_mtime_ns, changed_mtime)

    def test_manifest_is_deterministic_and_records_relative_paths(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            (repository / "B.swift").write_text("let b = 2\n", encoding="utf-8")
            (repository / "A.swift").write_text("let a = 1\n", encoding="utf-8")
            manifest = repository / "manifest.json"

            xcode_cache_inputs.capture(
                repository,
                manifest,
                ["B.swift", "A.swift"],
                set(),
                "def456",
            )
            payload = json.loads(manifest.read_text(encoding="utf-8"))

            self.assertEqual(payload["schemaVersion"], 1)
            self.assertEqual(payload["repositoryHead"], "def456")
            self.assertEqual(
                [record["path"] for record in payload["files"]],
                ["A.swift", "B.swift"],
            )
            self.assertNotIn(str(repository), manifest.read_text(encoding="utf-8"))

    def test_missing_and_outside_paths_are_safe(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            manifest = repository / "manifest.json"
            manifest.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "repositoryHead": "abc123",
                        "files": [
                            {
                                "path": "missing.swift",
                                "sha256": "0" * 64,
                                "size": 0,
                                "mtimeNanoseconds": 1,
                            },
                            {
                                "path": "../outside.swift",
                                "sha256": "0" * 64,
                                "size": 0,
                                "mtimeNanoseconds": 1,
                            },
                        ],
                    }
                ),
                encoding="utf-8",
            )

            self.assertEqual(xcode_cache_inputs.restore(repository, manifest), 0)


if __name__ == "__main__":
    unittest.main()
