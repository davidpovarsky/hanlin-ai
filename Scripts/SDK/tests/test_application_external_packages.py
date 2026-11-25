import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("cache_generate_manifest", ROOT / "Scripts/SDK/generate_manifest.py")
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


class ApplicationExternalPackageTests(unittest.TestCase):
    def evaluate(self, packages):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "application_products.json"
            source.write_text(json.dumps({"externalPackages": packages}))
            with patch.object(generator, "APPLICATION_PRODUCTS", source):
                return generator.application_external_packages()

    def test_original_lru_library_is_exactly_owned_by_application(self):
        self.assertEqual(generator.application_external_packages(), [
            ("lrucache", "https://github.com/nicklockwood/LRUCache.git", 'exact: "1.3.0"')
        ])

    def test_missing_optional_app_dependencies_preserve_old_graph(self):
        self.assertEqual(self.evaluate([]), [])

    def test_duplicate_package_identity_and_unpinned_entries_are_rejected(self):
        original = {"url": "https://github.com/nicklockwood/LRUCache.git", "exact": "1.3.0"}
        for entries in [[original, original], [{"url": original["url"]}],
                        [{"url": "http://example.com/library", "exact": "1.0.0"}]]:
            with self.subTest(entries=entries), self.assertRaises(ValueError):
                self.evaluate(entries)


if __name__ == "__main__":
    unittest.main()
