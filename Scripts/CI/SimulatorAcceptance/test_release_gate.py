"""Synthetic authentication/ZIP/build-binding checks; no ASC or UI execution."""
import copy
import io
from pathlib import Path
import tempfile
import unittest
import zipfile

import gate
import release_gate


class ReleaseGateTests(unittest.TestCase):
    def setUp(self):
        self.policy = gate.read(gate.POLICY_PATH)
        self.run = {"id": 91, "head_sha": "a" * 40, "status": "completed", "conclusion": "success", "path": ".github/workflows/testflight.yml", "event": "workflow_dispatch", "repository": {"id": 11, "full_name": "owner/repo"}}
        self.artifact = {"name": "Hanlin-App-UI-123", "expired": False, "digest": "sha256:" + "b" * 64, "size_in_bytes": 100, "workflow_run": {"id": 91, "head_sha": "a" * 40, "repository_id": 11, "head_repository_id": 11}}

    def test_exact_original_origin_is_accepted(self):
        release_gate.validate_origin(self.artifact, self.run, "owner/repo", "123", self.policy)

    def test_wrong_failed_foreign_or_unapproved_origin_rejected(self):
        for field, value in [("conclusion", "failure"), ("status", "in_progress"), ("event", "pull_request"), ("path", ".github/workflows/other.yml"), ("head_sha", "c" * 40), ("repository", {"id": 11, "full_name": "other/repo"})]:
            run = dict(self.run, **{field: value})
            with self.assertRaises(gate.GateError): release_gate.validate_origin(self.artifact, run, "owner/repo", "123", self.policy)

    def test_expired_wrong_name_fork_or_unsigned_digest_rejected(self):
        for field, value in [("expired", True), ("name", "Hanlin-App-UI-124"), ("digest", ""), ("size_in_bytes", 0)]:
            artifact = dict(self.artifact, **{field: value})
            with self.assertRaises(gate.GateError): release_gate.validate_origin(artifact, self.run, "owner/repo", "123", self.policy)
        artifact = copy.deepcopy(self.artifact);artifact["workflow_run"]["head_repository_id"] = 99
        with self.assertRaises(gate.GateError): release_gate.validate_origin(artifact, self.run, "owner/repo", "123", self.policy)

    def test_zip_digest_and_traversal_are_checked_before_extracting(self):
        for name, good_digest in [("plan.json", False), ("../escape.json", True), ("a/../plan.json", True)]:
            buffer = io.BytesIO()
            with zipfile.ZipFile(buffer, "w") as archive: archive.writestr(name, "{}")
            raw = buffer.getvalue()
            artifact = dict(self.artifact, digest="sha256:" + (gate.digest(raw) if good_digest else "0" * 64))
            with tempfile.TemporaryDirectory(prefix="hanlin-ui-zip-") as directory:
                with self.assertRaises(gate.GateError): release_gate.extract_verified(raw, artifact, Path(directory) / "proof")

    def test_uploaded_build_readback_requires_same_source_and_number(self):
        with tempfile.TemporaryDirectory(prefix="hanlin-ui-bind-") as directory:
            root = Path(directory)
            gate.write(root / "release-binding.json", {"source_sha": "a" * 40, "build_number": "123"})
            for record in [{"sourceSHA": "b" * 40, "buildNumber": "123", "appID": "app", "buildID": "build"}, {"sourceSHA": "a" * 40, "buildNumber": "124", "appID": "app", "buildID": "build"}, {}]:
                gate.write(root / "readiness.json", record)
                with self.assertRaises(gate.GateError): release_gate.bind_uploaded(root, root / "readiness.json")


if __name__ == "__main__":
    unittest.main()
