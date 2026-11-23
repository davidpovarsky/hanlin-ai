#!/usr/bin/env python3
"""Exercise packaged localization ownership in the actual validator."""
import importlib.util
import json
import plistlib
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("chat_localization", ROOT / "Scripts/CI/validate_chat_localization.py")
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class PackagedLocalizationOwnershipTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / "Hanlin.app"
        self.bundle = self.app / "HanlinSDK_HanlinLocalization.bundle"
        self.bundle.mkdir(parents=True)
        (self.bundle / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "HanlinLocalization"}))
        for table, (relative, _) in CHECK.CATALOGS.items():
            catalog = json.loads((ROOT / relative).read_text())
            for locale in CHECK.LOCALES:
                values = {key: entry.get("localizations", {}).get(locale, {}).get("stringUnit", {}).get("value")
                          for key, entry in catalog["strings"].items()}
                values = {key: value for key, value in values.items() if isinstance(value, str)}
                path = self.bundle / (locale + ".lproj") / (table + ".strings")
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(plistlib.dumps(values, fmt=plistlib.FMT_BINARY))

    def duplicate(self, relative):
        copy = self.app / relative / self.bundle.name
        copy.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(self.bundle, copy)
        return copy

    def change_translation(self, bundle, value):
        path = bundle / "en.lproj/Localizable.strings"
        data = plistlib.loads(path.read_bytes())
        data["Tool permissions"] = value
        path.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_BINARY))

    def test_same_original_bundle_in_app_framework_and_extensions_is_accepted(self):
        self.duplicate("Frameworks/HanlinApplication.framework")
        self.duplicate("PlugIns/Share.appex")
        self.duplicate("Extensions/Translation.appex")
        result = CHECK.validate(ROOT, app=self.app)
        self.assertEqual(result["status"], "PASS", result["errors"])
        self.assertGreater(result["packaged_values"], 0)
        copies = result["bundleCopies"]
        self.assertEqual(len(copies), 4)
        self.assertEqual(len({entry["inventorySHA256"] for entry in copies}), 1)
        self.assertEqual(copies[0]["path"], self.bundle.name)

    def test_stale_translation_in_extension_fails(self):
        copy = self.duplicate("PlugIns/Share.appex")
        self.change_translation(copy, "Stale packaged translation")
        result = CHECK.validate(ROOT, app=self.app)
        self.assertEqual(result["status"], "FAIL")
        self.assertTrue(any("Conflicting" in error["reason"] for error in result["errors"]))

    def test_changed_non_table_entry_in_extension_fails(self):
        copy = self.duplicate("Extensions/Translation.appex")
        (copy / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "Stale"}))
        result = CHECK.validate(ROOT, app=self.app)
        self.assertEqual(result["status"], "FAIL")
        self.assertTrue(any("Info.plist" in error["reason"] for error in result["errors"]))

    def test_two_different_sdk_bundle_identities_remain_ambiguous(self):
        shutil.copytree(self.bundle, self.app / "HanlinPresentationSDK_HanlinLocalization.bundle")
        result = CHECK.validate(ROOT, app=self.app)
        self.assertEqual(result["status"], "FAIL")

    def test_equal_copies_with_wrong_canonical_translation_still_fail(self):
        self.change_translation(self.bundle, "Wrong in every copy")
        self.duplicate("PlugIns/Share.appex")
        result = CHECK.validate(ROOT, app=self.app)
        self.assertEqual(result["status"], "FAIL")
        self.assertTrue(any(error["reason"] == "packaged value differs from source" for error in result["errors"]))

    def test_direct_resource_bundle_input_is_preserved(self):
        result = CHECK.validate(ROOT, app=self.bundle)
        self.assertEqual(result["status"], "PASS", result["errors"])
        self.assertGreater(result["packaged_values"], 0)


if __name__ == "__main__":
    unittest.main()
