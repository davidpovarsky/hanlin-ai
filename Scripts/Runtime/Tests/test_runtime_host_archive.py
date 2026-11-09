from __future__ import annotations
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

SPEC = importlib.util.spec_from_file_location("host_archive", Path(__file__).parents[1] / "runtime_host_archive.py")
archive_module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(archive_module)

class RuntimeHostArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.source.mkdir()
        self.manifest = {"name":"host", "type":"module", "dependencies":{"node-fetch":"3.3.2"}}
        self.lock = {"lockfileVersion":3,"packages":{"node_modules/node-fetch":{"version":"3.3.2"}}}
        (self.source / "package.json").write_text(json.dumps(self.manifest), encoding="utf-8")
        (self.source / "package-lock.json").write_text(json.dumps(self.lock), encoding="utf-8")
        (self.source / "host.mjs").write_text("export default 'current';", encoding="utf-8")
        self.archive = self.root / "Host.zip"

    def write_archive(self, destination, *, old_dependencies=False, missing_package=False, old_modules=False):
        with zipfile.ZipFile(destination, "w") as packed:
            manifest = {**self.manifest, "dependencies":{}} if old_dependencies else self.manifest
            lock = {"lockfileVersion":3,"packages":{}} if old_dependencies else self.lock
            packed.writestr("./package.json", json.dumps(manifest, indent=2))
            packed.writestr("./package-lock.json", json.dumps(lock, indent=2))
            if not old_dependencies and not missing_package:
                packed.writestr("./node_modules/node-fetch/package.json", json.dumps({"name":"node-fetch","version":"3.3.2"}))
            packed.writestr("./host.mjs", "export default 'old';" if old_modules else (self.source / "host.mjs").read_text())
            if old_modules:
                packed.writestr("obsolete.mjs", "obsolete")

    def fail_builder(self):
        self.fail("An unchanged dependency closure must not reinstall/retest packages")

    def test_matching_archive_is_reused_without_rebuilding(self):
        self.write_archive(self.archive)
        before = self.archive.read_bytes()
        result = archive_module.synchronize_archive(self.archive, self.source, self.fail_builder)
        self.assertIn("verified existing", result)
        self.assertEqual(self.archive.read_bytes(), before)

    def test_real_zip_with_old_dependencies_is_rebuilt_not_just_overlaid(self):
        self.write_archive(self.archive, old_dependencies=True)
        self.assertTrue(archive_module.validate_archive(self.archive, self.source))
        rebuilt = self.root / "rebuilt.zip"
        self.write_archive(rebuilt)
        calls = []
        def builder():
            calls.append(True)
            return rebuilt
        self.assertIn("rebuilt", archive_module.synchronize_archive(self.archive, self.source, builder))
        self.assertEqual(calls, [True])
        self.assertEqual(archive_module.validate_archive(self.archive, self.source, check_sources=True), [])
        with zipfile.ZipFile(self.archive) as packed:
            value = json.loads(packed.read("./node_modules/node-fetch/package.json"))
            self.assertEqual(value["version"], "3.3.2")

    def test_matching_lock_without_actual_required_package_fails(self):
        self.write_archive(self.archive, missing_package=True)
        self.assertTrue(archive_module.validate_archive(self.archive, self.source))

    def test_source_only_update_preserves_packages_and_removes_obsolete_modules(self):
        self.write_archive(self.archive, old_modules=True)
        self.assertEqual(archive_module.validate_archive(self.archive, self.source), [])
        self.assertTrue(archive_module.validate_archive(self.archive, self.source, check_sources=True))
        archive_module.synchronize_archive(self.archive, self.source, self.fail_builder)
        with zipfile.ZipFile(self.archive) as packed:
            self.assertEqual(packed.read("host.mjs"), (self.source / "host.mjs").read_bytes())
            self.assertNotIn("obsolete.mjs", packed.namelist())
            self.assertEqual(json.loads(packed.read("./node_modules/node-fetch/package.json"))["version"], "3.3.2")

    def test_bad_rebuild_does_not_replace_the_original_archive(self):
        self.write_archive(self.archive, old_dependencies=True)
        before = self.archive.read_bytes()
        broken = self.root / "broken.zip"
        self.write_archive(broken, missing_package=True)
        with self.assertRaisesRegex(RuntimeError, "Rebuilt Host failed"):
            archive_module.synchronize_archive(self.archive, self.source, lambda: broken)
        self.assertEqual(self.archive.read_bytes(), before)

    def make_prepared(self):
        output = self.root / "prepared"
        output.mkdir()
        target = output / "RuntimeHostResources.zip"
        self.write_archive(target)
        fingerprint = '{"node":"24.5.0","platform":"test"}'
        metadata = {"sourceInputsHash":archive_module.input_hash(self.source, fingerprint),
                    "archiveSha256":hashlib.sha256(target.read_bytes()).hexdigest(),
                    "tests":"passed", "jitlessArchiveSmoke":"passed"}
        (output / "host-metadata.json").write_text(json.dumps(metadata), encoding="utf-8")
        return output, fingerprint, metadata

    def test_prepared_reuse_requires_matching_inputs_and_completed_archive_smoke(self):
        output, fingerprint, metadata = self.make_prepared()
        self.assertTrue(archive_module.reusable_prepared_archive(output, self.source, fingerprint))
        metadata["jitlessArchiveSmoke"] = "failed"
        (output / "host-metadata.json").write_text(json.dumps(metadata))
        self.assertFalse(archive_module.reusable_prepared_archive(output, self.source, fingerprint))

    def test_source_or_node_engine_change_invalidates_prepared_reuse(self):
        output, fingerprint, _ = self.make_prepared()
        self.assertFalse(archive_module.reusable_prepared_archive(output, self.source, '{"node":"24.6.0"}'))
        (self.source / "host.mjs").write_text("export default 'changed';")
        self.assertFalse(archive_module.reusable_prepared_archive(output, self.source, fingerprint))

    def test_changed_archive_bytes_cannot_reuse_successful_metadata(self):
        output, fingerprint, _ = self.make_prepared()
        with zipfile.ZipFile(output / "RuntimeHostResources.zip", "a") as packed:
            packed.writestr("unexpected.txt", "changed")
        self.assertFalse(archive_module.reusable_prepared_archive(output, self.source, fingerprint))

    def test_ambiguous_or_escaping_archive_paths_are_rejected(self):
        self.write_archive(self.archive)
        with zipfile.ZipFile(self.archive, "a") as packed:
            packed.writestr("package.json", json.dumps(self.manifest))
        self.assertTrue(archive_module.validate_archive(self.archive, self.source))
        self.write_archive(self.archive)
        with zipfile.ZipFile(self.archive, "a") as packed:
            packed.writestr("../outside.txt", "invalid")
        self.assertTrue(archive_module.validate_archive(self.archive, self.source))

if __name__ == "__main__":
    unittest.main()
