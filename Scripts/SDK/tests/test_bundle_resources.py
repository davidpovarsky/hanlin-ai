"""Packaging boundary regressions; fixture bundles are not Apple build evidence."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "verify_bundle_resources.py"
spec = importlib.util.spec_from_file_location("bundle_resources", SCRIPT)
resources = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resources)


class BundleResourceTests(unittest.TestCase):
    def fixture(self, root):
        source = root / "AI_HLY"
        source.mkdir()
        archive = source / "RuntimeHostResources.zip"
        archive.write_bytes(b"original prepared host archive")
        nested = source / "PythonSupport"
        nested.mkdir()
        (nested / "module.whl").write_bytes(b"original Python resource")
        app = root / "Host.app"
        bundle = app / "HanlinSDK_AI_Hanlin.bundle"
        bundle.mkdir(parents=True)
        (bundle / archive.name).write_bytes(archive.read_bytes())
        (bundle / nested.name).mkdir()
        (bundle / nested.name / "module.whl").write_bytes((nested / "module.whl").read_bytes())
        manifest = {"targets": [{"name": "AI_Hanlin", "path": "AI_HLY", "resources": [
            {"path": archive.name, "rule": {"copy": {}}},
            {"path": nested.name, "rule": {"copy": {}}},
        ]}]}
        return app, bundle, manifest

    def test_original_resources_are_verified_in_sdk_bundle_and_main_copy_cannot_mask_loss(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app, bundle, manifest = self.fixture(root)
            result = resources.validate(root, app, "AI_Hanlin", manifest)
            self.assertEqual(result["status"], "PASS")
            self.assertEqual(result["copiedResourceFiles"], 2)
            (bundle / "RuntimeHostResources.zip").rename(app / "RuntimeHostResources.zip")
            result = resources.validate(root, app, "AI_Hanlin", manifest)
            self.assertEqual(result["status"], "FAIL")
            self.assertEqual(result["errors"][0]["reason"], "missing from original SDK bundle")

    def test_changed_nested_resource_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app, bundle, manifest = self.fixture(root)
            (bundle / "PythonSupport/module.whl").write_bytes(b"stale host-local implementation")
            result = resources.validate(root, app, "AI_Hanlin", manifest)
            self.assertEqual(result["status"], "FAIL")
            self.assertEqual(result["errors"][0]["resource"], "PythonSupport/module.whl")
            self.assertNotEqual(result["errors"][0]["sourceSHA256"], result["errors"][0]["packagedSHA256"])

    def test_duplicate_module_bundle_is_ambiguous(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app, bundle, manifest = self.fixture(root)
            (app / "OldSDK_AI_Hanlin.bundle").mkdir()
            with self.assertRaisesRegex(ValueError, "found 2"):
                resources.validate(root, app, "AI_Hanlin", manifest)


if __name__ == "__main__":
    unittest.main()
