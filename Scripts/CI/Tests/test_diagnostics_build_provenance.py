import importlib.util
import json
import pathlib
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "write_diagnostics_build_provenance.py"
spec = importlib.util.spec_from_file_location("diagnostic_provenance", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class DiagnosticProvenanceTests(unittest.TestCase):
    def test_exact_checkout_pins_without_authenticated_locations_and_stable_mtime(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            lock = root / "AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
            lock.parent.mkdir(parents=True)
            lock.write_text(json.dumps({"pins": [{"identity": "sdk", "location": "https://credential@example.invalid/sdk", "state": {"revision": "a" * 40}}]}))
            resource = root / "AI_HLY/Downstream/AgentDiagnostics/HanlinDiagnosticsBuildProvenance.json"
            resource.parent.mkdir(parents=True)
            resource.write_text("{}")
            for args in [("init",), ("add", "."), ("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-m", "fixture")]:
                subprocess.run(["git", *args], cwd=root, check=True, capture_output=True)
            output = module.write_provenance(root)
            value = json.loads(output.read_bytes())
            actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
            self.assertEqual(value["sourceCommit"], actual)
            self.assertFalse(value["trackedWorkspaceModified"])
            self.assertEqual(value["dependencyPins"][0]["state"]["revision"], "a" * 40)
            self.assertNotIn("credential", output.read_text())
            before = output.stat().st_mtime_ns
            module.write_provenance(root)
            self.assertEqual(output.stat().st_mtime_ns, before)
            lock.write_text(lock.read_text().replace("a" * 40, "b" * 40))
            module.write_provenance(root)
            changed = json.loads(output.read_bytes())
            self.assertTrue(changed["trackedWorkspaceModified"])
            self.assertNotEqual(changed["packageResolvedSHA256"], value["packageResolvedSHA256"])
            self.assertEqual(changed["dependencyPins"][0]["state"]["revision"], "b" * 40)

    def test_stale_lock_cannot_claim_the_requested_fork_revision(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            project = root / "AI_HLY.xcodeproj/project.pbxproj"
            project.parent.mkdir(parents=True)
            project.write_text('repositoryURL = "https://github.com/owner/renderer"; requirement = { kind = revision; revision = ' + "a" * 40 + '; };')
            lock = project.parent / "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
            lock.parent.mkdir(parents=True)
            lock.write_text(json.dumps({"pins": [{"identity": "old-renderer", "location": "https://github.com/other/renderer", "state": {"revision": "b" * 40}}]}))
            output = root / "AI_HLY/Downstream/AgentDiagnostics/HanlinDiagnosticsBuildProvenance.json"
            output.parent.mkdir(parents=True)
            output.write_text("{}"); before = output.read_bytes()
            with self.assertRaisesRegex(ValueError, "resolve Xcode packages"):
                module.write_provenance(root)
            self.assertEqual(output.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
