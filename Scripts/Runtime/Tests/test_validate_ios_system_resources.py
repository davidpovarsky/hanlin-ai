from __future__ import annotations

import plistlib
import shutil
import tempfile
import unittest
from pathlib import Path

from Scripts.Runtime.validate_ios_system_resources import (
    COMMAND_DICTIONARY,
    EXTRA_DICTIONARY,
    ResourceValidationError,
    validate_app_resources,
)


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
CANONICAL_COMMAND = REPOSITORY_ROOT / COMMAND_DICTIONARY
CANONICAL_EXTRA = REPOSITORY_ROOT / EXTRA_DICTIONARY


class IOSSystemAppResourceValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory(prefix="ios-system-resources-")
        self.app = Path(self.temporary_directory.name) / "AI_Hanlin.app"
        self.app.mkdir()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def install_valid_resources(self) -> None:
        shutil.copyfile(CANONICAL_COMMAND, self.app / "commandDictionary.plist")
        shutil.copyfile(CANONICAL_EXTRA, self.app / "extraCommandsDictionary.plist")

    def validate(self) -> dict[str, object]:
        return validate_app_resources(self.app, CANONICAL_COMMAND, CANONICAL_EXTRA)

    def test_valid_root_resources_pass(self) -> None:
        self.install_valid_resources()
        result = self.validate()
        self.assertEqual(result["approvedCommandCount"], 23)
        self.assertEqual(result["unexpectedCommands"], [])

    def test_semantically_equal_binary_plist_fails_canonical_byte_check(self) -> None:
        self.install_valid_resources()
        path = self.app / "commandDictionary.plist"
        value = plistlib.loads(path.read_bytes())
        path.write_bytes(plistlib.dumps(value, fmt=plistlib.FMT_BINARY, sort_keys=False))
        with self.assertRaisesRegex(ResourceValidationError, "canonical source bytes"):
            self.validate()

    def test_missing_root_dictionary_fails(self) -> None:
        shutil.copyfile(CANONICAL_EXTRA, self.app / "extraCommandsDictionary.plist")
        with self.assertRaisesRegex(ResourceValidationError, "Required plist is missing"):
            self.validate()

    def test_package_bundle_only_dictionary_fails(self) -> None:
        bundle = self.app / "IOSSystemLite_IOSSystemLite.bundle"
        bundle.mkdir()
        shutil.copyfile(CANONICAL_COMMAND, bundle / "commandDictionary.plist")
        shutil.copyfile(CANONICAL_EXTRA, bundle / "extraCommandsDictionary.plist")
        with self.assertRaisesRegex(ResourceValidationError, "Required plist is missing"):
            self.validate()

    def test_unexpected_command_fails(self) -> None:
        self.install_valid_resources()
        path = self.app / "commandDictionary.plist"
        value = plistlib.loads(path.read_bytes())
        value["sh"] = ["shell.framework/shell", "sh_main", "", "file"]
        path.write_bytes(plistlib.dumps(value))
        with self.assertRaisesRegex(ResourceValidationError, r"unexpected=\['sh'\]"):
            self.validate()

    def test_nonempty_extra_dictionary_fails(self) -> None:
        self.install_valid_resources()
        path = self.app / "extraCommandsDictionary.plist"
        path.write_bytes(plistlib.dumps({"ssh": ["ssh.framework/ssh", "ssh_main", "", "file"]}))
        with self.assertRaisesRegex(ResourceValidationError, "must be empty"):
            self.validate()


if __name__ == "__main__":
    unittest.main()
