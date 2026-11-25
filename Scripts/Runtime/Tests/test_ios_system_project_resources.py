from __future__ import annotations
import re
import shutil
import tempfile
import unittest
from pathlib import Path

from Scripts.Runtime.validate_ios_system_resources import (
    COMMAND_DICTIONARY, EXTRA_DICTIONARY, ResourceValidationError, validate_source_resources,
)
from Scripts.SDK.update_project import edit_object, replace_list, wire_miniapps_ios_system_resources
from Scripts.CI.IntegrationValidation.project_graph import parse_project

ROOT = Path(__file__).resolve().parents[3]


class IOSSystemProjectResourceValidationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ios-system-project-")
        self.root = Path(self.temporary.name)
        for path in (COMMAND_DICTIONARY, EXTRA_DICTIONARY,
                     Path("Packages/IOSSystemLite/Package.swift"),
                     Path("AI_HLY.xcodeproj/project.pbxproj")):
            destination = self.root / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / path, destination)
        self.project = self.root / "AI_HLY.xcodeproj/project.pbxproj"
        self.project.write_text(wire_miniapps_ios_system_resources(self.project.read_text()))

    def tearDown(self):
        self.temporary.cleanup()

    def phase(self, text, name):
        objects = parse_project(text)["objects"]
        target = next(value for value in objects.values()
                      if value.get("isa") == "PBXNativeTarget" and value.get("name") == name)
        key = next(key for key in target["buildPhases"]
                   if objects[key]["isa"] == "PBXResourcesBuildPhase")
        return key, objects[key]["files"]

    def test_valid_target_resources_do_not_require_pbx_comments(self):
        self.project.write_text(re.sub(r"/\*[\s\S]*?\*/", "", self.project.read_text()))
        self.assertEqual(validate_source_resources(self.root)["approvedCommandCount"], 23)

    def remove_app_resources_but_keep_old_comments(self, target_name="HanlinApp"):
        text = self.project.read_text()
        key, files = self.phase(text, target_name)
        objects = parse_project(text)["objects"]
        dictionary_ids = [key for key in files
                          if objects[objects[key]["fileRef"]].get("path")
                          in {COMMAND_DICTIONARY.as_posix(), EXTRA_DICTIONARY.as_posix()}]
        text = edit_object(text, key, lambda block: replace_list(
            block, "files", [value for value in files if value not in dictionary_ids]))
        # Stale display labels cannot authorize a resource copy.
        text += "\n/* commandDictionary.plist in Resources; extraCommandsDictionary.plist in Resources */\n" * 2
        return text, dictionary_ids

    def test_stale_comments_cannot_replace_actual_app_membership(self):
        text, _ = self.remove_app_resources_but_keep_old_comments()
        self.project.write_text(text)
        with self.assertRaisesRegex(ResourceValidationError, "Copy Bundle Resources"):
            validate_source_resources(self.root)

    def test_widget_membership_does_not_supply_the_application_resource(self):
        text, ids = self.remove_app_resources_but_keep_old_comments()
        key, files = self.phase(text, "HanlinScriptingWidgets")
        self.project.write_text(edit_object(text, key, lambda block: replace_list(block, "files", files + ids)))
        with self.assertRaisesRegex(ResourceValidationError, "Copy Bundle Resources"):
            validate_source_resources(self.root)

    def test_missing_miniapps_membership_is_rejected_even_when_ai_has_both_resources(self):
        text, _ = self.remove_app_resources_but_keep_old_comments("HanlinMiniApps")
        self.project.write_text(text)
        with self.assertRaisesRegex(ResourceValidationError, "Copy Bundle Resources.*HanlinMiniApps"):
            validate_source_resources(self.root)

    def test_generator_repairs_missing_miniapps_membership_without_changing_ai_and_is_idempotent(self):
        text, _ = self.remove_app_resources_but_keep_old_comments("HanlinMiniApps")
        ai_phase = self.phase(text, "HanlinApp")
        repaired = wire_miniapps_ios_system_resources(text)
        self.assertEqual(self.phase(repaired, "HanlinApp"), ai_phase)
        self.assertEqual(wire_miniapps_ios_system_resources(repaired), repaired)
        self.project.write_text(repaired)
        self.assertEqual(validate_source_resources(self.root)["approvedCommandCount"], 23)

    def test_plist_conversion_is_still_rejected(self):
        self.project.write_text(self.project.read_text().replace(
            "explicitFileType = text; name = commandDictionary.plist;",
            "explicitFileType = text.plist.xml; name = commandDictionary.plist;"))
        with self.assertRaisesRegex(ResourceValidationError, "raw text"):
            validate_source_resources(self.root)


if __name__ == "__main__":
    unittest.main()
