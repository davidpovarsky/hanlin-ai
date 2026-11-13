from copy import deepcopy
import hashlib
from pathlib import Path
import stat
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).parents[1]))
import verify_runtime_reuse as reuse


class NativeReuseTests(unittest.TestCase):
    def setUp(self):
        self.run = {"id": 100, "status": "completed", "conclusion": "failure", "head_sha": "a" * 40,
                    "path": ".github/workflows/build-ios26-unsigned-ipa.yml",
                    "repository": {"id": 10, "full_name": "owner/repo"},
                    "head_repository": {"id": 10, "full_name": "owner/repo"}}
        self.jobs, self.artifacts = [], []
        for index, (_, (prefix, name, step)) in enumerate(reuse.COMPONENTS.items()):
            self.jobs.append({"id": 200 + index, "run_id": 100, "run_attempt": 1, "head_sha": "a" * 40,
                "name": "Run split RuntimeCore bundle pipeline / " + name,
                "status": "completed", "conclusion": "success", "completed_at": "2026-11-10T02:00:00Z",
                "steps": [{"name": step, "status": "completed", "conclusion": "success",
                           "started_at": "2026-11-10T01:00:00Z", "completed_at": "2026-11-10T01:30:00Z"}]})
            self.artifacts.append({"id": 300 + index, "name": prefix + "-" + "b" * 64, "expired": False,
                "size_in_bytes": 10, "digest": "sha256:" + "d" * 64,
                "workflow_run": {"id": 100, "head_sha": "a" * 40, "repository_id": 10, "head_repository_id": 10},
                "created_at": "2026-11-10T01:31:00Z", "updated_at": "2026-11-10T01:32:00Z"})

    def verify(self):
        return reuse.verify(self.run, self.jobs, self.artifacts, "owner/repo", "b" * 64, "c" * 64, "c" * 64)

    def test_native_components_can_pass_when_unrelated_parent_or_host_failed(self):
        receipt = self.verify()
        self.assertEqual(receipt["scope"], "native-component-production-only")
        self.assertEqual(receipt["sourceRunConclusion"], "failure")
        self.assertEqual(set(receipt["components"]), {"node-device", "node-simulator", "python"})
        self.assertEqual(receipt["components"]["node-device"]["artifactID"], 300)
        self.assertNotIn("host", receipt["components"])

    def test_in_progress_foreign_or_unexpected_workflow_cannot_supply_components(self):
        for key, value in (("status", "in_progress"), ("path", ".github/workflows/other.yml"),
                           ("head_sha", "x; arbitrary"), ("head_repository", {"id": 11, "full_name": "fork/repo"})):
            with self.subTest(key=key):
                original = deepcopy(self.run)
                self.run[key] = value
                with self.assertRaises(ValueError):
                    self.verify()
                self.run = original

    def test_native_identity_change_cannot_be_hidden_by_matching_artifact_names(self):
        with self.assertRaisesRegex(ValueError, "Native binary inputs changed"):
            reuse.verify(self.run, self.jobs, self.artifacts, "owner/repo", "b" * 64, "c" * 64, "e" * 64)

    def test_different_host_dependency_hash_keeps_exact_original_native_artifact_identity(self):
        receipt = reuse.verify(self.run, self.jobs, self.artifacts, "owner/repo", "e" * 64,
                               "c" * 64, "c" * 64, source_dependency_hash="b" * 64)
        self.assertEqual(receipt["sourceDependencyHash"], "b" * 64)
        self.assertEqual(receipt["consumerDependencyHash"], "e" * 64)
        self.assertEqual(receipt["components"]["python"]["artifactName"], "python-runtime-" + "b" * 64)

    def test_missing_duplicate_expired_empty_or_unsigned_artifact_is_rejected(self):
        original = deepcopy(self.artifacts)
        for kind in ("missing", "duplicate", "expired", "size", "digest", "foreign", "wrong-sha", "wrong-attempt"):
            with self.subTest(kind=kind):
                self.artifacts = deepcopy(original)
                if kind == "missing":
                    self.artifacts.pop()
                elif kind == "duplicate":
                    self.artifacts.append(deepcopy(self.artifacts[0]))
                elif kind == "expired":
                    self.artifacts[0]["expired"] = True
                elif kind == "size":
                    self.artifacts[0]["size_in_bytes"] = 0
                elif kind == "digest":
                    self.artifacts[0]["digest"] = None
                elif kind == "foreign":
                    self.artifacts[0]["workflow_run"]["repository_id"] = 11
                elif kind == "wrong-sha":
                    self.artifacts[0]["workflow_run"]["head_sha"] = "e" * 40
                else:
                    self.artifacts[0]["created_at"] = "2026-11-09T01:31:00Z"
                with self.assertRaises((ValueError, TypeError)):
                    self.verify()

    def test_zero_step_success_is_not_actual_production(self):
        self.jobs[0]["steps"] = []
        with self.assertRaisesRegex(ValueError, "No actual producer execution"):
            self.verify()

    def test_failed_job_is_rejected_even_if_build_wrapper_exited_success(self):
        self.jobs[0]["conclusion"] = "failure"
        with self.assertRaisesRegex(ValueError, "did not pass"):
            self.verify()

    def test_later_actual_failed_attempt_cannot_reuse_an_old_success(self):
        failed = deepcopy(self.jobs[0])
        failed.update(id=500, run_attempt=2, conclusion="failure")
        failed["steps"][0]["started_at"] = "2026-11-10T03:00:00Z"
        self.jobs.append(failed)
        with self.assertRaisesRegex(ValueError, "did not pass"):
            self.verify()

    def test_cloned_rerun_steps_keep_original_executed_attempt_and_job(self):
        clone = deepcopy(self.jobs[0])
        clone.update(id=500, run_attempt=2)
        self.jobs.append(clone)
        component = self.verify()["components"]["node-device"]
        self.assertEqual(component["producerAttempt"], 1)
        self.assertEqual(component["producerJobID"], 200)

    def test_zero_step_later_allocation_cancel_does_not_invent_a_failed_execution(self):
        clone = deepcopy(self.jobs[0])
        clone.update(id=500, run_attempt=2, conclusion="cancelled", steps=[])
        self.jobs.append(clone)
        self.assertEqual(self.verify()["components"]["node-device"]["producerJobID"], 200)

    def test_later_setup_failure_with_a_never_started_build_is_not_an_execution(self):
        for started_at in (None, "0001-01-01T00:00:00Z"):
            with self.subTest(started_at=started_at):
                clone = deepcopy(self.jobs[0])
                clone.update(id=500, run_attempt=2, conclusion="failure")
                clone["steps"][0].update(conclusion="skipped", started_at=started_at)
                self.jobs.append(clone)
                self.assertEqual(self.verify()["components"]["node-device"]["producerJobID"], 200)

    def test_wrong_job_run_sha_or_nonexecuted_step_cannot_pass(self):
        original = deepcopy(self.jobs)
        for kind in ("run", "sha", "step", "timestamp"):
            with self.subTest(kind=kind):
                self.jobs = deepcopy(original)
                if kind == "run":
                    self.jobs[0]["run_id"] = 101
                elif kind == "sha":
                    self.jobs[0]["head_sha"] = "e" * 40
                elif kind == "step":
                    self.jobs[0]["steps"][0]["conclusion"] = "skipped"
                else:
                    self.jobs[0]["steps"][0]["started_at"] = "0001-01-01T00:00:00Z"
                with self.assertRaises(ValueError):
                    self.verify()

    def test_real_archive_bytes_must_match_authenticated_digest_before_extraction(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "artifact.zip"
            with zipfile.ZipFile(archive, "w") as zipped:
                zipped.writestr("framework.sha256", "actual hash\n")
            digest = "sha256:" + hashlib.sha256(archive.read_bytes()).hexdigest()
            reuse.extract_verified(archive, digest, root / "good")
            self.assertEqual((root / "good/framework.sha256").read_text(), "actual hash\n")
            with self.assertRaisesRegex(ValueError, "digest mismatch"):
                reuse.extract_verified(archive, "sha256:" + "0" * 64, root / "bad")
            self.assertFalse((root / "bad").exists())

    def test_even_correctly_hashed_archive_cannot_escape_its_input_directory(self):
        for name in ("../escape", "/absolute", "C:/drive", "dir\\escape", "symlink"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                archive = root / "artifact.zip"
                with zipfile.ZipFile(archive, "w") as zipped:
                    member = zipfile.ZipInfo(name)
                    # ZipInfo normalizes backslashes on Windows during construction.
                    # Write the adversarial central-directory name verbatim.
                    member.filename = name
                    if name == "symlink":
                        member.external_attr = (stat.S_IFLNK | 0o777) << 16
                    zipped.writestr(member, "unsafe")
                digest = "sha256:" + hashlib.sha256(archive.read_bytes()).hexdigest()
                with self.assertRaises(ValueError):
                    reuse.extract_verified(archive, digest, root / "output")
                self.assertFalse((root / "output").exists())


class RuntimeReuseWorkflowTests(unittest.TestCase):
    def test_reuse_requires_current_host_and_carries_exact_receipt_into_bundle(self):
        import yaml
        root = Path(__file__).parents[3]
        workflow = yaml.safe_load((root / ".github/workflows/build-runtime-bundle.yml").read_text(encoding="utf-8"))
        jobs = workflow["jobs"]
        self.assertNotIn("reuse_artifacts_run_id", jobs["prepare-runtime-host"]["if"])
        self.assertIn("needs.prepare-runtime-host.result == 'success'", jobs["assemble-runtime-bundle"]["if"])
        self.assertIn("needs.plan-runtime.result == 'success'", jobs["assemble-runtime-bundle"]["if"])
        steps = jobs["assemble-runtime-bundle"]["steps"]
        host = next(step for step in steps if step.get("name") == "Download runtime host")
        self.assertNotIn("if", host)
        self.assertNotIn("run-id", host["with"])
        self.assertFalse(any(step.get("name") == "Download runtime host from reusable run" for step in steps))
        receipt = next(step for step in steps if step.get("name") == "Download authenticated native reuse receipt")
        self.assertIn("artifact-ids", receipt["with"])
        verified = next(step for step in steps if step.get("name") == "Download immutable native archives and verify their actual digests")
        self.assertIn("verify_runtime_reuse.py", verified["run"])
        self.assertIn("--download-to build/runtime-inputs", verified["run"])
        assembly = (root / "Scripts/Runtime/assemble-runtime-bundle.sh").read_text(encoding="utf-8")
        self.assertLess(assembly.index('"${OUTPUT_ROOT}/NativeReuseProvenance.json"'), assembly.index('bundle_name='))
        self.assertIn("!result.descriptorOwnership", assembly)
        self.assertIn("!result.wasmEvidence?.refArrayBounds", assembly)


if __name__ == "__main__":
    unittest.main()
