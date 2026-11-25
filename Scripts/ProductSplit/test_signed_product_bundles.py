"""Original IPA bundle topology and exact signing coverage regressions."""
from pathlib import Path
import plistlib
import tempfile
import unittest

from prepare_signed_products import exported_bundle_targets
from audit_release_resources import product_roles


MAIN = "com.itorah.chavrusachat"
TRANSLATION = MAIN + ".translation-provider"
EXPECTED = {MAIN, MAIN + ".share", MAIN + ".widgets",
            MAIN + ".notification-service", TRANSLATION}


class ExportedBundleTargetsTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.app = Path(temporary.name) / "AI_Hanlin.app"
        self.bundle(self.app, MAIN)
        for name, suffix in (
            ("ChavrusaChatShare", "share"),
            ("HanlinScriptingWidgets", "widgets"),
            ("ChavrusaChatNotificationService", "notification-service"),
        ):
            self.bundle(self.app / "PlugIns" / (name + ".appex"), MAIN + "." + suffix)
        self.translation = self.app / "Extensions/ChavrusaChatTranslationProvider.appex"
        self.bundle(self.translation, TRANSLATION)

    def bundle(self, path, identity):
        path.mkdir(parents=True, exist_ok=True)
        (path / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": identity}))

    def test_original_ipa_includes_extensionkit_and_plugin_extensions(self):
        observed = exported_bundle_targets(self.app, EXPECTED)
        self.assertEqual(set(observed), EXPECTED)
        self.assertEqual(observed[MAIN], self.app)
        self.assertEqual(observed[TRANSLATION], self.translation)
        for identity in EXPECTED - {MAIN, TRANSLATION}:
            self.assertEqual(observed[identity].parent, self.app / "PlugIns")

    def test_missing_extensionkit_identity_is_rejected(self):
        (self.translation / "Info.plist").unlink()
        self.translation.rmdir()
        with self.assertRaisesRegex(RuntimeError, "missing=.*translation-provider"):
            exported_bundle_targets(self.app, EXPECTED)

    def test_unexpected_extension_is_rejected(self):
        self.bundle(self.app / "Extensions/Unexpected.appex", MAIN + ".unexpected")
        with self.assertRaisesRegex(RuntimeError, "unexpected=.*unexpected"):
            exported_bundle_targets(self.app, EXPECTED)

    def test_duplicate_identity_across_containers_is_rejected(self):
        self.bundle(self.app / "PlugIns/DuplicateTranslation.appex", TRANSLATION)
        with self.assertRaisesRegex(RuntimeError, "Duplicate signed bundle identity"):
            exported_bundle_targets(self.app, EXPECTED)

    def test_extension_cannot_duplicate_main_application_identity(self):
        self.bundle(self.app / "Extensions/DuplicateMain.appex", MAIN)
        with self.assertRaisesRegex(RuntimeError, "Duplicate signed bundle identity"):
            exported_bundle_targets(self.app, EXPECTED)

    def test_miniapps_app_only_cannot_satisfy_source_extension_coverage(self):
        app = self.app.parent / "HanlinMiniApps.app"
        identity = "com.itorah.hanlinminiapps"
        self.bundle(app, identity)
        required = {row[1] for row in product_roles("miniapps")}
        expected = {identity, identity + ".widgets", identity + ".share",
                    identity + ".translation-provider", identity + ".notification-service"}
        self.assertEqual(required, expected)
        with self.assertRaisesRegex(RuntimeError, "missing="):
            exported_bundle_targets(app, required)
        for name, suffix, container in (
            ("HanlinMiniAppsWidgets", "widgets", "PlugIns"),
            ("HanlinMiniAppsShare", "share", "PlugIns"),
            ("HanlinMiniAppsNotificationService", "notification-service", "PlugIns"),
            ("HanlinMiniAppsTranslationProvider", "translation-provider", "Extensions"),
        ):
            self.bundle(app / container / (name + ".appex"), identity + "." + suffix)
        self.assertEqual(set(exported_bundle_targets(app, required)), expected)

    def test_profile_selection_retains_both_disjoint_original_app_families(self):
        ai = {row[1] for row in product_roles("ai")}
        miniapps = {row[1] for row in product_roles("miniapps")}
        self.assertEqual(ai, EXPECTED)
        self.assertEqual(len(miniapps), 5)
        self.assertFalse(ai & miniapps)
        with self.assertRaisesRegex(ValueError, "Unknown"):
            product_roles("unregistered-product")


if __name__ == "__main__":
    unittest.main()
