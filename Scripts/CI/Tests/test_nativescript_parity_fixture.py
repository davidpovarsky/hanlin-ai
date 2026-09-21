import json
import unittest
import zipfile
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
SOURCE_ROOT = REPOSITORY_ROOT / "DemoMiniApps" / "hanlin-script-parity"
ARCHIVE_PATH = REPOSITORY_ROOT / "DemoMiniApps" / "hanlin-script-parity.hanlinNativeScript"


class NativeScriptParityFixtureTests(unittest.TestCase):
    def test_archive_matches_source_byte_for_byte(self) -> None:
        source_files = {
            path.relative_to(SOURCE_ROOT).as_posix(): path.read_bytes().replace(b"\r\n", b"\n")
            for path in SOURCE_ROOT.rglob("*")
            if path.is_file()
        }
        with zipfile.ZipFile(ARCHIVE_PATH) as archive:
            archive_files = {
                name.replace("\\", "/"): archive.read(name).replace(b"\r\n", b"\n")
                for name in archive.namelist()
                if not name.endswith("/")
            }
        self.assertEqual(archive_files, source_files)

    def test_actions_and_intent_use_the_same_declared_handler(self) -> None:
        manifest = json.loads((SOURCE_ROOT / "script.json").read_text(encoding="utf-8"))
        intent = json.loads((SOURCE_ROOT / "intent.json").read_text(encoding="utf-8"))
        actions = {action["id"]: action for action in manifest["actions"]}

        self.assertEqual(set(actions), {"share.value", "parity.intent"})
        self.assertEqual(intent["action"], "parity.intent")
        for action in actions.values():
            self.assertEqual(action["capability"], "inter-app.share")
            self.assertEqual(action["handler"], "nativescript/app/bundle.mjs")

    def test_bundle_uses_exported_bridge_and_canonical_roots(self) -> None:
        bundle = (SOURCE_ROOT / "nativescript" / "app" / "bundle.mjs").read_text(encoding="utf-8")
        metadata_wrapper = (
            REPOSITORY_ROOT / "Scripts" / "NativeScript" / "build-step-metadata-generator-wrapper.py"
        ).read_text(encoding="utf-8")

        self.assertIn('typeof HanlinNativeServicesBridge !== "undefined"', bundle)
        self.assertIn('"HANLIN_MINIAPP_STATE_DIR"', bundle)
        self.assertIn('"HANLIN_MINIAPP_DATA_ROOT"', bundle)
        self.assertNotIn('"HANLIN_STATE_DIR"', bundle)
        self.assertNotIn('"HANLIN_DATA_ROOT"', bundle)
        self.assertIn('"share.value", "inter-app.share"', bundle)
        self.assertIn('"parity.intent", "inter-app.share"', bundle)
        self.assertIn('"HanlinNativeServicesBridge.h"', metadata_wrapper)


if __name__ == "__main__":
    unittest.main()
