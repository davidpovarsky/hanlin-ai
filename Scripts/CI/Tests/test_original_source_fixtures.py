from pathlib import Path
import hashlib
import json
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Scripts/CI"))
import prepare_original_source_fixtures as fixtures

sys.path.insert(0, str(ROOT / "Scripts/SDK"))
import update_project
from project_graph import parse_project


class OriginalSourceFixtureTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "checkout"
        self.output = Path(self.temporary.name) / "products" / fixtures.BUNDLE_NAME
        self.source_bytes = {}
        for relative in fixtures.input_paths():
            data = ("Current source: " + relative + "\r\n").encode()
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            self.source_bytes[relative] = data

    def test_declared_inputs_cover_the_original_contract_and_final12(self):
        contract_path = "docs/hanlin-dock-v33-source-parity/SOURCE_PRESERVATION_V2.json"
        data = (ROOT / contract_path).read_bytes().replace(b"\r\n", b"\n")
        self.assertEqual(hashlib.sha256(data).hexdigest(),
                         "169e270d596fa000ce9cb043fa55f765cda62fd6043df49eb3bad8e2e160e6e3")
        contract = json.loads(data)
        expected = set(contract["files"]) | {
            contract_path,
            "docs/hanlin-dock-v33-source-parity/SOURCE_PRESERVATION_V2_APPROVED_TRANSITION_467cfcab.json",
            "docs/hanlin-dock-v33-source-parity/SOURCE_REFERENCE_AND_SHA.md",
            "capability-invariants.json",
            "docs/hanlin-platform/personal-runtime-completion/tool-inventory.json",
        }
        self.assertEqual(len(expected), 24)
        self.assertEqual(set(fixtures.input_paths()), expected)

    def test_snapshot_copies_current_bytes_and_records_the_exact_inputs(self):
        manifest = fixtures.prepare(self.root, self.output)
        self.assertEqual(manifest["schemaVersion"], 1)
        self.assertEqual(manifest["producer"], fixtures.PRODUCER_PATH)
        self.assertEqual(json.loads((self.output / "manifest.json").read_text()), manifest)
        self.assertEqual({row["path"] for row in manifest["files"]}, set(self.source_bytes))
        for row in manifest["files"]:
            data = self.source_bytes[row["path"]]
            self.assertEqual((self.output / row["path"]).read_bytes(), data)
            self.assertEqual(row["bytes"], len(data))
            self.assertEqual(row["sha256"], hashlib.sha256(data).hexdigest())

    def test_rebuild_copies_changed_source_without_regenerating_the_expectation(self):
        fixtures.prepare(self.root, self.output)
        (self.output / "obsolete-source.swift").write_text("stale")
        relative = "AI_HLY/Services/ChatServices/APIManager.swift"
        changed = b"Changed actual implementation, not an expected hash\n"
        (self.root / relative).write_bytes(changed)
        manifest = fixtures.prepare(self.root, self.output)
        self.assertFalse((self.output / "obsolete-source.swift").exists())
        self.assertEqual((self.output / relative).read_bytes(), changed)
        row = next(row for row in manifest["files"] if row["path"] == relative)
        self.assertEqual(row["sha256"], hashlib.sha256(changed).hexdigest())
        contract = "docs/hanlin-dock-v33-source-parity/SOURCE_PRESERVATION_V2.json"
        self.assertEqual((self.output / contract).read_bytes(), self.source_bytes[contract])
        amendment = "docs/hanlin-dock-v33-source-parity/SOURCE_PRESERVATION_V2_APPROVED_TRANSITION_467cfcab.json"
        self.assertEqual((self.output / amendment).read_bytes(), self.source_bytes[amendment])

    def test_missing_current_source_cannot_replace_an_existing_valid_snapshot(self):
        fixtures.prepare(self.root, self.output)
        before = (self.output / "manifest.json").read_bytes()
        (self.root / "AI_HLY/Services/ChatServices/APIManager.swift").unlink()
        with self.assertRaisesRegex(ValueError, "Missing"):
            fixtures.prepare(self.root, self.output)
        self.assertEqual((self.output / "manifest.json").read_bytes(), before)

    def test_source_file_and_parent_symlinks_are_rejected(self):
        source = self.root / "capability-invariants.json"
        outside = Path(self.temporary.name) / "outside.json"
        outside.write_text("outside")
        source.unlink()
        source.symlink_to(outside)
        with self.assertRaisesRegex(ValueError, "symlink"):
            fixtures.prepare(self.root, self.output)
        self.assertFalse(self.output.exists())
        source.unlink()
        source.write_bytes(self.source_bytes["capability-invariants.json"])
        directory = self.root / "docs/hanlin-platform/personal-runtime-completion"
        moved = Path(self.temporary.name) / "moved"
        directory.rename(moved)
        directory.symlink_to(moved, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            fixtures.prepare(self.root, self.output)
        self.assertFalse(self.output.exists())

    def test_invalid_duplicate_and_empty_input_lists_are_rejected(self):
        path = Path(self.temporary.name) / "inputs.xcfilelist"
        for text in ["", "/private/file\n", "$(SRCROOT)/../outside\n",
                     "$(SRCROOT)/a/./b\n", "$(SRCROOT)/same\n$(SRCROOT)/same\n"]:
            with self.subTest(text=text):
                path.write_text(text)
                with self.assertRaises(ValueError):
                    fixtures.input_paths(path)

    def test_output_symlink_or_an_input_tree_cannot_be_replaced(self):
        self.output.parent.mkdir()
        self.output.symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "nonsymlink"):
            fixtures.prepare(self.root, self.output)
        self.assertEqual((self.root / "capability-invariants.json").read_bytes(),
                         self.source_bytes["capability-invariants.json"])
        self.output.unlink()
        overlapping = self.root / fixtures.BUNDLE_NAME
        overlapping.mkdir()
        source = overlapping / "source.swift"
        source.write_text("original")
        inputs = Path(self.temporary.name) / "overlap.xcfilelist"
        inputs.write_text("$(SRCROOT)/" + fixtures.BUNDLE_NAME + "/source.swift\n")
        with self.assertRaisesRegex(ValueError, "overlapping"):
            fixtures.prepare(self.root, overlapping, inputs)
        self.assertEqual(source.read_text(), "original")

    def test_canonical_phase_belongs_only_to_the_original_unit_test_product(self):
        project = parse_project(update_project.FILE.read_text())
        objects = project["objects"]
        phase_id = update_project.SOURCE_FIXTURE_PHASE
        owners = [obj["name"] for obj in objects.values()
                  if phase_id in obj.get("buildPhases", [])]
        self.assertEqual(owners, ["AI_HLYTests"])
        phase = objects[phase_id]
        self.assertEqual(phase["inputFileListPaths"],
                         ["$(SRCROOT)/Scripts/CI/original-source-fixtures.xcfilelist"])
        self.assertEqual(phase["inputPaths"], [
            "$(SRCROOT)/Scripts/CI/prepare_original_source_fixtures.py",
            "$(SRCROOT)/Scripts/CI/original-source-fixtures.xcfilelist",
        ])
        self.assertEqual(phase["outputPaths"][0],
                         "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/OriginalSourceFixtures.bundle")
        self.assertEqual(str(phase["alwaysOutOfDate"]), "1")
        self.assertIn('--source-root "$SRCROOT"', phase["shellScript"])
        # The existing project parser retains the quoted PBX newline escape.
        self.assertTrue(phase["shellScript"].startswith(r"set -eu\n/usr/bin/env python3 "))

    def test_sandbox_outputs_cover_the_actual_copied_tree_with_sandboxing_enabled(self):
        fixtures.prepare(self.root, self.output)
        project = parse_project(update_project.FILE.read_text())
        objects = project["objects"]
        phase = objects[update_project.SOURCE_FIXTURE_PHASE]
        output_root = "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/OriginalSourceFixtures.bundle"
        actual = {output_root}
        actual.update(output_root + "/" + path.relative_to(self.output).as_posix()
                      for path in self.output.rglob("*"))
        declared = phase["outputPaths"]
        self.assertEqual(len(declared), len(set(declared)))
        self.assertEqual(set(declared), actual)
        self.assertEqual(len([path for path in self.output.rglob("*") if path.is_file()]), 25)
        self.assertIn(output_root + "/AI_HLY", declared)
        self.assertIn(output_root + "/manifest.json", declared)

        root = objects[project["rootObject"]]
        unit = next(value for value in objects.values()
                    if value.get("isa") == "PBXNativeTarget" and value.get("name") == "AI_HLYTests")
        project_settings = {
            objects[key]["name"]: objects[key]["buildSettings"]
            for key in objects[root["buildConfigurationList"]]["buildConfigurations"]
        }
        for key in objects[unit["buildConfigurationList"]]["buildConfigurations"]:
            config = objects[key]
            setting = config["buildSettings"].get(
                "ENABLE_USER_SCRIPT_SANDBOXING",
                project_settings[config["name"]]["ENABLE_USER_SCRIPT_SANDBOXING"],
            )
            self.assertEqual(setting, "YES")

    def test_canonical_phase_generation_is_idempotent(self):
        text = update_project.FILE.read_text()
        self.assertEqual(update_project.wire_original_source_fixtures(text), text)


if __name__ == "__main__":
    unittest.main()
