"""Actual sparse Git installation checks; the fixture is not Apple/native evidence."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest

from Scripts.SDK.tests.test_install import SDKInstallTests, installer, SCRIPT

WIDGET_GENERATOR = r'''import argparse,json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument("--products",nargs="+");a=p.parse_args()
root=Path(__file__).resolve().parents[2]
widget=any(name in {"HanlinWidgetUI","HanlinApplication"} for name in a.products)
entry="HanlinScriptingWidgets" if widget else "CanonicalCore"
products=", ".join('.library(name: "'+name+'", targets: ["'+entry+'"])' for name in a.products)
targets='.target(name: "CanonicalCore", path: "Sources/CanonicalCore")'
if widget:
    targets='.target(name: "HanlinScriptingWidgets", dependencies: ["HanlinLocalization"], path: "Packages/HanlinWidgetSDK/Sources/HanlinScriptingWidgets"), .target(name: "HanlinLocalization", path: "Packages/HanlinPresentationSDK/Sources/HanlinLocalization")'
(root/"Package.swift").write_text('// swift-tools-version: 6.2\nimport PackageDescription\nlet package = Package(name: "HanlinSDK", products: ['+products+'], targets: ['+targets+'])\n')
(root/"docs/agent-sdk/unified-package-manifest.json").write_text(json.dumps({"products":a.products}))
'''


class AppIntentsHostResourceInstallTests(unittest.TestCase):
    def setUp(self):
        # Reuse the existing real-Git fixture without inheriting/rerunning its tests.
        self.fixture = SDKInstallTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.repository = self.fixture.repository
        self.host = self.fixture.host
        self.sdk = self.host / "Vendor/HanlinSDK"
        source = SCRIPT.parent / "generate_app_intents_resources.py"
        spec = importlib.util.spec_from_file_location("app_intents_resource_fixture", source)
        generator = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(generator)
        self.catalog_path = generator.SOURCE.relative_to(generator.ROOT)
        self.table_path = generator.OUTPUT.relative_to(generator.ROOT)
        self.key = generator.KEYS[0]
        catalog = {
            "sourceLanguage": "zh-Hans",
            "version": "1.0",
            "strings": {
                key: {"localizations": {
                    language: {"stringUnit": {"state": "translated", "value": language + ": " + key}}
                    for language in ("en", "he", "zh-Hans")
                }} for key in generator.KEYS
            },
        }
        catalog_file = self.repository / self.catalog_path
        catalog_file.parent.mkdir(parents=True)
        catalog_file.write_text(json.dumps(catalog, ensure_ascii=False))
        (self.repository / "Scripts/SDK/generate_app_intents_resources.py").write_bytes(source.read_bytes())
        (self.repository / "Scripts/SDK/generate_manifest.py").write_text(WIDGET_GENERATOR)
        widget_source = self.repository / "Packages/HanlinWidgetSDK/Sources/HanlinScriptingWidgets/Value.swift"
        widget_source.parent.mkdir(parents=True)
        widget_source.write_text("public struct WidgetMarker {}\n")
        (catalog_file.parent.parent / "Value.swift").write_text("public struct LocalizationMarker {}\n")
        self.render_table()
        self.commit_fixture("Canonical host AppIntents table fixture")

    def render_table(self):
        subprocess.run([sys.executable, str(self.repository / "Scripts/SDK/generate_app_intents_resources.py")],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def commit_fixture(self, message):
        self.fixture.git("add", ".")
        self.fixture.git("commit", "-m", message)
        self.fixture.revision = self.fixture.git("rev-parse", "HEAD")

    def check(self):
        return installer.check(self.host, self.fixture.lock, "Vendor/HanlinSDK")

    def test_selected_widget_and_application_table_is_installed_and_updates_from_pin(self):
        for product in ("HanlinWidgetUI", "HanlinApplication"):
            with self.subTest(product=product):
                self.fixture.lock_products([product])
                receipt = self.fixture.install()
                self.assertIn(self.table_path.parent.as_posix(), receipt["sourcePaths"])
                self.assertEqual((self.sdk / self.table_path).read_bytes(),
                                 (self.repository / self.table_path).read_bytes())
                self.assertEqual(self.check()["state"], "installed")
        catalog_file = self.repository / self.catalog_path
        catalog = json.loads(catalog_file.read_text())
        catalog["strings"][self.key]["localizations"]["en"]["stringUnit"]["value"] = "updated canonical fixture"
        catalog_file.write_text(json.dumps(catalog, ensure_ascii=False))
        self.render_table()
        self.commit_fixture("Next immutable canonical translation")
        self.fixture.lock_products(["HanlinWidgetUI"])
        receipt = self.fixture.install()
        self.assertEqual(receipt["revision"], self.fixture.revision)
        self.assertEqual((self.sdk / self.table_path).read_bytes(),
                         (self.repository / self.table_path).read_bytes())
        self.assertIn("updated canonical fixture", (self.sdk / self.table_path).read_text())
        self.assertEqual(self.check()["state"], "installed")
        (self.sdk / self.table_path).unlink()
        with self.assertRaisesRegex(ValueError, "actual source edit"):
            self.check()

    def test_unselected_table_is_absent_and_stale_selected_projection_is_rejected(self):
        catalog_file = self.repository / self.catalog_path
        catalog = json.loads(catalog_file.read_text())
        catalog["strings"][self.key]["localizations"]["he"]["stringUnit"]["value"] += " changed"
        catalog_file.write_text(json.dumps(catalog, ensure_ascii=False))
        # Intentionally commit a stale projection, exercising the pinned validator.
        self.commit_fixture("Intentionally stale projected host table")
        self.fixture.lock_products(["HanlinAgentCore"])
        receipt = self.fixture.install()
        self.assertNotIn(self.table_path.parent.as_posix(), receipt["sourcePaths"])
        self.assertFalse((self.sdk / self.table_path).exists())
        self.assertFalse((self.sdk / self.catalog_path).exists())
        self.assertEqual(self.check()["state"], "installed")
        self.fixture.lock_products(["HanlinWidgetUI"])
        with self.assertRaisesRegex(RuntimeError, "projection is stale"):
            self.fixture.install()
        receipt = json.loads((self.sdk / installer.RECEIPT).read_text())
        self.assertNotEqual(receipt["state"], "installed")


if __name__ == "__main__":
    unittest.main()
