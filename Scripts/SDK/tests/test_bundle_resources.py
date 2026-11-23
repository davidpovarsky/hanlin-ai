"""Packaging boundary regressions; fixture bundles are not Apple build evidence."""
import importlib.util
from pathlib import Path
import tempfile
import shutil
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


    def framework_copy(self, app, bundle):
        destination = app / "Frameworks" / "HanlinApplication_3ED3A7D0B493F0DF_PackageProduct.framework" / bundle.name
        return shutil.copytree(bundle, destination)

    def test_identical_swiftpm_main_and_framework_bundle_copies_are_validated(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app, bundle, manifest = self.fixture(root)
            (bundle / "Assets.car").write_bytes(b"same original compiled asset fixture")
            copied = self.framework_copy(app, bundle)
            result = resources.validate(root, app, "AI_Hanlin", manifest)
            self.assertEqual(result["status"], "PASS")
            self.assertEqual(result["bundle"], bundle.name)
            self.assertEqual(result["copiedResourceFiles"], 2)
            self.assertEqual([row["path"] for row in result["bundleCopies"]],
                             [bundle.name, str(copied.relative_to(app))])
            self.assertEqual(len({row["inventorySHA256"] for row in result["bundleCopies"]}), 1)

    def test_different_nested_copy_in_framework_cannot_be_ignored(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app, bundle, manifest = self.fixture(root)
            copied = self.framework_copy(app, bundle)
            (copied / "PythonSupport/module.whl").write_bytes(b"different packaged resource")
            with self.assertRaisesRegex(ValueError, "Conflicting.*PythonSupport/module.whl"):
                resources.validate(root, app, "AI_Hanlin", manifest)

    def test_different_processed_resource_in_duplicate_bundle_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app, bundle, manifest = self.fixture(root)
            (bundle / "Assets.car").write_bytes(b"original compiled asset fixture")
            copied = self.framework_copy(app, bundle)
            (copied / "Assets.car").write_bytes(b"stale compiled asset fixture")
            with self.assertRaisesRegex(ValueError, "Conflicting.*Assets.car"):
                resources.validate(root, app, "AI_Hanlin", manifest)

    def test_identical_copies_cannot_mask_a_missing_canonical_resource(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app, bundle, manifest = self.fixture(root)
            (bundle / "RuntimeHostResources.zip").rename(app / "RuntimeHostResources.zip")
            self.framework_copy(app, bundle)
            result = resources.validate(root, app, "AI_Hanlin", manifest)
            self.assertEqual(result["status"], "FAIL")
            self.assertEqual(result["errors"][0]["reason"], "missing from original SDK bundle")

    def test_duplicate_bundle_resource_link_cannot_escape_its_owner(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app, bundle, manifest = self.fixture(root)
            copied = self.framework_copy(app, bundle)
            outside = app / "outside.car"
            outside.write_bytes(b"external compiled asset fixture")
            (copied / "Assets.car").symlink_to(outside)
            with self.assertRaisesRegex(ValueError, "resource escapes"):
                resources.validate(root, app, "AI_Hanlin", manifest)



if __name__ == "__main__":
    unittest.main()
