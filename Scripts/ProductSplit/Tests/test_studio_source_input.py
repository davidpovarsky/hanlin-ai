"""Bounded controls for ordinary source input staging, never native acceptance."""
from pathlib import Path
import copy
import json
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import studio_source_input as producer
import observe_studio_editor as reader
import observe_studio_gallery as gallery
import observe_shortcut_surfaces as shared
from test_studio_editor_observer import EditorFixture


class StudioSourceInputTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(); self.addCleanup(self.temporary.cleanup)
        self.fixture = EditorFixture(Path(self.temporary.name), "import")
        f = self.fixture
        self.inputs = producer.create_manifest(f.evidence.parent)
        f.args.studio_inputs = self.inputs["path"]
        # No Studio copy is created by this setup or by the producer.
        f.phase("gallery-ready", galleryLoaded=True)
        self.path = f.evidence / f.run / "studio-import-input-request.json"
        self.original = shared.read_document(self.path, f.evidence)["value"]

    def stage(self, resolve=None, stopping=lambda: False):
        f = self.fixture
        with mock.patch.object(gallery, "bind_sdk", return_value=f.sdk), \
             mock.patch.object(gallery, "verify_sdk_unchanged"):
            return producer.stage(self.path, self.inputs, resolve or (lambda: f.roots), stopping)

    def response(self):
        return Path(self.inputs["value"]["responseRoot"]) / (self.fixture.run + ".json")

    def change_request(self, **fields):
        self.path.write_text(json.dumps({**self.original, **fields}))

    def test_stages_only_the_current_template_in_normal_documents(self):
        f = self.fixture; before = f.snapshot()
        result = self.stage()
        self.assertEqual(result["status"], "STAGED_INPUTS_ONLY")
        self.assertEqual(list(f.workspace.iterdir()), [])
        copied = f.data / "Documents" / result["inputFolder"] / result["projectFolder"]
        self.assertEqual(gallery.hashes(gallery.source_tree(copied, f.data)), self.original["templateHashes"])
        for name, value in before.items(): self.assertEqual((f.data / name).read_bytes(), value)
        changes = set(f.snapshot()) - set(before)
        self.assertTrue(changes and all(name.startswith("Documents/HanlinStudioImport-" + f.run + "/") for name in changes))
        admitted = reader.verify_input(f.seen[f.run], f.args, f.roots, f.evidence)
        self.assertEqual(admitted["folder"], result["inputFolder"])

    def test_unknown_schema_engine_marker_and_paths_fail_before_write(self):
        for fields in ({"schema": True}, {"engine": "nativescript"}, {"marker": "foreign"},
                       {"exampleID": "../../drafts"}, {"extra": "unapproved"},
                       {"dataContainer": str(self.fixture.root / "elsewhere")}):
            self.change_request(**fields)
            with self.subTest(fields=fields), self.assertRaises((ValueError, FileNotFoundError)): self.stage()
            self.assertFalse(self.response().exists())
            self.assertFalse((self.fixture.data / "Documents" / ("HanlinStudioImport-" + self.fixture.run)).exists())

    def test_wrong_sdk_archive_or_template_hash_cannot_stage(self):
        for fields in ({"hostArchiveSHA256": "0" * 64}, {"templateHashes": {"index.ts": "0" * 64}}):
            self.change_request(**fields)
            with self.subTest(fields=fields), self.assertRaises(ValueError): self.stage()
        self.assertFalse(self.response().exists())

    def test_existing_ordinary_input_is_never_overwritten(self):
        folder = self.fixture.data / "Documents" / ("HanlinStudioImport-" + self.fixture.run)
        folder.mkdir(); (folder / "user.txt").write_text("keep")
        with self.assertRaises(FileExistsError): self.stage()
        self.assertEqual((folder / "user.txt").read_text(), "keep")
        self.assertFalse(self.response().exists())

    def test_documents_link_cannot_redirect_the_writer(self):
        f = self.fixture; target = f.root / "outside"; target.mkdir()
        (f.data / "Documents").rmdir(); (f.data / "Documents").symlink_to(target, target_is_directory=True)
        with self.assertRaises(ValueError): self.stage()
        self.assertEqual(list(target.iterdir()), [])

    def test_changed_actual_product_during_copy_prevents_response(self):
        roots = iter([self.fixture.roots, {**self.fixture.roots, "infoSHA256": "changed"}])
        with self.assertRaises(ValueError): self.stage(resolve=lambda: next(roots))
        self.assertFalse(self.response().exists())
        self.assertEqual(list(self.fixture.workspace.iterdir()), [])

    def test_stop_and_late_request_mutation_cannot_publish_provenance(self):
        with self.assertRaises(ValueError): self.stage(stopping=lambda: True)
        self.assertFalse(self.response().exists())
        calls = [0]
        def resolve():
            calls[0] += 1
            if calls[0] == 2: self.change_request(marker="changed after copy")
            return self.fixture.roots
        with self.assertRaises(ValueError): self.stage(resolve=resolve)
        self.assertFalse(self.response().exists())

    def test_atomic_response_and_import_reader_reject_extra_or_changed_source(self):
        f = self.fixture; result = self.stage()
        self.assertFalse(self.response().with_suffix(".json.producer-tmp").exists())
        value = json.loads(self.response().read_text())
        self.response().write_text(json.dumps({**value, "completed": True}))
        with self.assertRaises(ValueError): reader.verify_input(f.seen[f.run], f.args, f.roots, f.evidence)
        self.response().write_text(json.dumps(value))
        path = f.data / "Documents" / result["inputFolder"] / result["projectFolder"] / "index.ts"
        path.write_text("not the original selected SDK source")
        with self.assertRaises(ValueError): reader.verify_input(f.seen[f.run], f.args, f.roots, f.evidence)


if __name__ == "__main__":
    unittest.main()
