import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("source", Path(__file__).parents[1] / "runtime_bundle_source.py")
source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source)


class RuntimeBundleSourceTests(unittest.TestCase):
    def setUp(self):
        self.repo = "owner/repository"
        self.hash = "a" * 64
        self.name = "hanlin-runtime-bundle-" + self.hash
        self.run = {"head_repository": {"full_name": self.repo}, "status": "completed", "conclusion": "success"}
        self.artifacts = [{"name": self.name, "expired": False}]

    def test_completed_same_repository_candidate_is_accepted(self):
        source.validate_source(self.run, self.artifacts, self.repo, self.name)

    def test_fork_and_incomplete_sources_are_rejected(self):
        for update in ({"head_repository": {"full_name": "fork/repository"}},
                       {"head_repository": None}, {"status": "in_progress"}, {"conclusion": "cancelled"}, {"conclusion": "failure"}):
            with self.subTest(update=update), self.assertRaises(ValueError):
                source.validate_source({**self.run, **update}, self.artifacts, self.repo, self.name)

    def test_missing_expired_and_ambiguous_artifacts_are_rejected(self):
        for artifacts in ([], [{"name": self.name, "expired": True}], self.artifacts * 2):
            with self.subTest(artifacts=artifacts), self.assertRaises(ValueError):
                source.validate_source(self.run, artifacts, self.repo, self.name)

    def test_actual_archive_bytes_are_pinned(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bundle.zip"
            path.write_bytes(b"actual candidate bytes")
            expected = hashlib.sha256(path.read_bytes()).hexdigest()
            source.verify_archive(path, expected)
            path.write_bytes(b"mutated bytes")
            with self.assertRaisesRegex(ValueError, "checksum"):
                source.verify_archive(path, expected)
            with self.assertRaisesRegex(ValueError, "verified"):
                source.verify_archive(path, None)

    def test_download_verifies_before_exposing_candidate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = b"verified payload"
            expected = hashlib.sha256(payload).hexdigest()
            def gh(*arguments):
                if arguments[0] == "api":
                    return json.dumps([{"artifacts": self.artifacts}]) if "--slurp" in arguments else json.dumps(self.run)
                self.assertEqual(arguments[:5], ("run", "download", "123", "--repo", self.repo))
                extracted = Path(arguments[-1])
                extracted.mkdir()
                (extracted / ("hanlin-runtime-" + self.hash + ".zip")).write_bytes(payload)
                return ""
            with patch.object(source, "gh", side_effect=gh):
                result = source.download_candidate(self.repo, "123", self.hash, expected, root)
            self.assertEqual(result.read_bytes(), payload)

    def test_download_rejects_changed_bytes_without_exposing_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def gh(*arguments):
                if arguments[0] == "api":
                    return json.dumps([{"artifacts": self.artifacts}]) if "--slurp" in arguments else json.dumps(self.run)
                extracted = Path(arguments[-1])
                extracted.mkdir()
                (extracted / ("hanlin-runtime-" + self.hash + ".zip")).write_bytes(b"unverified bytes")
                return ""
            with patch.object(source, "gh", side_effect=gh), self.assertRaisesRegex(ValueError, "checksum"):
                source.download_candidate(self.repo, "123", self.hash, "0" * 64, root)
            self.assertFalse((root / ("hanlin-runtime-" + self.hash + ".zip")).exists())

    def test_invalid_identifiers_do_not_call_github(self):
        with patch.object(source, "gh") as gh:
            for repository, run_id, digest in (("../other", "123", self.hash), (self.repo, "../123", self.hash), (self.repo, "123", "invalid")):
                with self.assertRaises(ValueError):
                    source.download_candidate(repository, run_id, digest, "b" * 64, ".")
            gh.assert_not_called()
