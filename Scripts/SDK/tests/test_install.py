"""Real Git checkout/update tests; fixture generator is not Hanlin host acceptance."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "install.py"
spec = importlib.util.spec_from_file_location("sdk_install", SCRIPT)
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

GENERATOR = r'''import argparse,json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument("--products",nargs="+");a=p.parse_args()
root=Path(__file__).resolve().parents[2]
products=", ".join('.library(name: "'+name+'", targets: ["CanonicalCore"])' for name in a.products)
native="HanlinRuntimeCore" in a.products
dependencies='dependencies: ["NodeMobile"], ' if native else ""
binary=', .binaryTarget(name: "NodeMobile", path: "Vendor/NodeMobile/NodeMobile.xcframework")' if native else ""
(root/"Package.swift").write_text('// swift-tools-version: 6.2\nimport PackageDescription\nlet package = Package(name: "HanlinSDK", products: ['+products+'], targets: [.target(name: "CanonicalCore", '+dependencies+'path: "Sources/CanonicalCore")'+binary+'])\n')
(root/"docs/agent-sdk/unified-package-manifest.json").write_text(json.dumps({"products":a.products}))
'''


class SDKInstallTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(
            prefix="hanlin-sdk-install-test-", dir=os.environ.get("HANLIN_SDK_TEST_ROOT"))
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repository = self.root / "canonical"
        self.host = self.root / "host"
        self.host.mkdir()
        (self.repository / "Scripts/SDK").mkdir(parents=True)
        (self.repository / "Sources/CanonicalCore").mkdir(parents=True)
        (self.repository / "docs/agent-sdk").mkdir(parents=True)
        (self.repository / "Scripts/SDK/generate_manifest.py").write_text(GENERATOR)
        (self.repository / "Scripts/SDK/native_artifacts.py").write_text(
            'from pathlib import Path\nPath(".hanlin-sdk/native-attempted").write_text("selected")\n'
            'raise SystemExit("Native assets have not been published")\n')
        (self.repository / "Sources/CanonicalCore/Value.swift").write_text(
            "public func canonicalValue() -> Int { 42 }\n")
        (self.repository / "Package.swift").write_text("// original full manifest\n")
        (self.repository / "docs/agent-sdk/unified-package-manifest.json").write_text("{}\n")
        (self.repository / "docs/native-artifacts.json").write_text(
            json.dumps({"state": "unpublished", "requiredTargets": ["NodeMobile"]}))
        (self.repository / ".gitignore").write_text("/.build/\n/Vendor/\n")
        self.git("init", "-b", "main")
        self.git("add", ".")
        self.git("commit", "-m", "Canonical source fixture")
        self.revision = self.git("rev-parse", "HEAD")
        self.lock = self.host / "HanlinSDK.lock.json"
        self.lock_products(["HanlinAgentCore"])

    def git(self, *arguments):
        return subprocess.check_output(
            ["git", "-C", str(self.repository), "-c", "user.name=ChatGPT",
             "-c", "user.email=noreply@openai.com", *arguments],
            text=True, stderr=subprocess.PIPE).strip()

    def lock_products(self, products, revision=None):
        self.lock.write_text(json.dumps({"revision": revision or self.revision, "products": products}))

    def install(self):
        return installer.install(self.host, self.lock, "Vendor/HanlinSDK", self.root / "cache",
                                 repository=str(self.repository))

    def test_source_only_profile_uses_pinned_git_without_native_preparation(self):
        receipt = self.install()
        sdk = self.host / "Vendor/HanlinSDK"
        self.assertEqual(receipt["revision"], self.revision)
        self.assertEqual(receipt["state"], "installed")
        self.assertEqual(receipt["binaryTargets"], [])
        self.assertEqual(receipt["managedNativeTargets"], [])
        self.assertFalse((sdk / ".hanlin-sdk/native-attempted").exists())
        self.assertIn("/Vendor/HanlinSDK/", (self.host / ".gitignore").read_text())
        self.assertEqual(installer.check(self.host, self.lock, "Vendor/HanlinSDK")["state"], "installed")

    def test_product_update_replaces_only_expected_generated_files(self):
        self.install()
        sdk = self.host / "Vendor/HanlinSDK"
        original = (sdk / "Sources/CanonicalCore/Value.swift").read_bytes()
        self.lock_products(["HanlinChatUI"])
        receipt = self.install()
        self.assertEqual(receipt["products"], ["HanlinChatUI"])
        self.assertEqual((sdk / "Sources/CanonicalCore/Value.swift").read_bytes(), original)
        self.assertIn("HanlinChatUI", (sdk / "Package.swift").read_text())
        self.assertNotIn("HanlinAgentCore", (sdk / "Package.swift").read_text())

    def test_revision_update_reuses_the_canonical_checkout(self):
        self.install()
        source = self.repository / "Sources/CanonicalCore/Value.swift"
        source.write_text("public func canonicalValue() -> Int { 43 }\n")
        self.git("add", str(source))
        self.git("commit", "-m", "Next canonical SDK revision")
        revision = self.git("rev-parse", "HEAD")
        self.lock_products(["HanlinAgentCore"], revision)
        receipt = self.install()
        self.assertEqual(receipt["revision"], revision)
        self.assertIn("43", (self.host / "Vendor/HanlinSDK/Sources/CanonicalCore/Value.swift").read_text())

    def test_actual_source_edit_is_preserved_and_blocks_update(self):
        self.install()
        source = self.host / "Vendor/HanlinSDK/Sources/CanonicalCore/Value.swift"
        source.write_text("host source edit must be preserved\n")
        with self.assertRaisesRegex(ValueError, "actual source edit"):
            self.install()
        self.assertEqual(source.read_text(), "host source edit must be preserved\n")

    def test_manual_generated_manifest_edit_is_not_silently_overwritten(self):
        self.install()
        manifest = self.host / "Vendor/HanlinSDK/Package.swift"
        manifest.write_text("// host deliberately changed its profile\n")
        with self.assertRaisesRegex(ValueError, "edited outside the installer"):
            self.install()
        self.assertEqual(manifest.read_text(), "// host deliberately changed its profile\n")

    def interrupt_selected_source_materialization(self):
        original_sparse_checkout = installer.sparse_checkout

        def fail_selected_sources(root, patterns, *, materialize):
            if materialize and "/Sources/CanonicalCore/" in patterns:
                # The real pinned generator and SwiftPM manifest evaluation have
                # completed. Inject only the subsequent source-fetch failure.
                self.assertIn("CanonicalCore", (root / "Package.swift").read_text())
                self.assertEqual(
                    json.loads((root / "docs/agent-sdk/unified-package-manifest.json").read_text())["products"],
                    json.loads(self.lock.read_text())["products"])
                raise RuntimeError("Selected source fetch interrupted")
            return original_sparse_checkout(root, patterns, materialize=materialize)

        with mock.patch.object(installer, "sparse_checkout", side_effect=fail_selected_sources):
            with self.assertRaisesRegex(RuntimeError, "Selected source fetch interrupted"):
                self.install()
        return self.host / "Vendor/HanlinSDK"

    def test_interrupted_selected_source_update_is_retryable(self):
        self.install()
        source = self.repository / "Sources/CanonicalCore/Value.swift"
        source.write_text("public func canonicalValue() -> Int { 43 }\n")
        self.git("add", str(source))
        self.git("commit", "-m", "New canonical revision before interrupted update")
        revision = self.git("rev-parse", "HEAD")
        self.lock_products(["HanlinAgentCore"], revision)

        sdk = self.interrupt_selected_source_materialization()
        self.assertEqual(installer.git(sdk, "rev-parse", "HEAD"), revision)
        with self.assertRaises(ValueError):
            installer.check(self.host, self.lock, "Vendor/HanlinSDK")

        receipt = self.install()
        self.assertEqual(receipt["state"], "installed")
        self.assertEqual(receipt["revision"], revision)
        self.assertEqual((sdk / "Sources/CanonicalCore/Value.swift").read_bytes(), source.read_bytes())
        self.assertEqual(installer.check(self.host, self.lock, "Vendor/HanlinSDK")["state"], "installed")
        self.assertFalse((sdk / ".hanlin-sdk/native-attempted").exists())

    def test_interrupted_install_preserves_external_generated_and_source_edits(self):
        sdk = self.interrupt_selected_source_materialization()
        cases = [
            ("Package.swift", "edited outside the installer"),
            ("docs/agent-sdk/unified-package-manifest.json", "edited outside the installer"),
            ("Scripts/SDK/generate_manifest.py", "actual source edit"),
        ]
        for relative, error in cases:
            with self.subTest(path=relative):
                path = sdk / relative
                original = path.read_bytes()
                edited = original + b"\n# deliberate external edit must survive\n"
                path.write_bytes(edited)
                try:
                    with self.assertRaisesRegex(ValueError, error):
                        self.install()
                    self.assertEqual(path.read_bytes(), edited)
                finally:
                    # Restore this test's own edit before checking the next
                    # independently rejected edit against the same interruption.
                    path.write_bytes(original)

    def test_selected_native_product_requires_published_assets(self):
        self.lock_products(["HanlinRuntimeCore"])
        with self.assertRaisesRegex(RuntimeError, "Native assets have not been published"):
            self.install()
        sdk = self.host / "Vendor/HanlinSDK"
        self.assertTrue((sdk / ".hanlin-sdk/native-attempted").is_file())
        receipt = json.loads((sdk / ".hanlin-sdk/installation.json").read_text())
        self.assertEqual(receipt["state"], "profile-ready")
        self.assertEqual(receipt["binaryTargets"], ["NodeMobile"])

    def test_shared_source_cache_borrows_existing_objects_and_preserves_canonical_origin(self):
        self.git("remote", "add", "origin", str(self.repository))
        receipt = installer.install(self.host, self.lock, "Vendor/HanlinSDK", self.root / "cache",
                                    repository=str(self.repository), source_cache=self.repository)
        sdk = self.host / "Vendor/HanlinSDK"
        self.assertEqual(receipt["revision"], self.revision)
        self.assertEqual(installer.git(sdk, "remote", "get-url", "origin"), str(self.repository))
        alternates = sdk / ".git/objects/info/alternates"
        self.assertTrue(alternates.is_file())
        self.assertIn(str(self.repository / ".git/objects"), alternates.read_text())


    def test_sparse_bootstrap_never_materializes_unselected_application_payload(self):
        payload = self.repository / "AI_HLY/Unselected/large-runtime.dat"
        payload.parent.mkdir(parents=True)
        payload.write_bytes(b"unselected application resource" * 1024)
        generator = self.repository / "Scripts/SDK/generate_manifest.py"
        generator.write_text(GENERATOR.replace(
            'root=Path(__file__).resolve().parents[2]',
            'root=Path(__file__).resolve().parents[2]\n'
            'assert not (root/"AI_HLY/Unselected/large-runtime.dat").exists(), "unselected payload materialized before product filtering"'))
        self.git("add", ".")
        self.git("commit", "-m", "Guard against full checkout before profile selection")
        self.revision = self.git("rev-parse", "HEAD")
        self.lock_products(["HanlinAgentCore"])
        receipt = self.install()
        sdk = self.host / "Vendor/HanlinSDK"
        self.assertEqual(receipt["checkoutMode"], "sparse")
        self.assertFalse((sdk / "AI_HLY/Unselected/large-runtime.dat").exists())
        self.assertTrue((sdk / "Sources/CanonicalCore/Value.swift").is_file())
        self.assertEqual(installer.git(sdk, "ls-files", "-t", "--", "AI_HLY/Unselected/large-runtime.dat"),
                         "S AI_HLY/Unselected/large-runtime.dat")
        self.assertEqual(installer.check(self.host, self.lock, "Vendor/HanlinSDK")["state"], "installed")

    def test_sparse_bootstrap_includes_original_project_graph_imports(self):
        canonical = SCRIPT.parents[2]
        for relative in (
            "Scripts/CI/IntegrationValidation/project_graph.py",
            "Scripts/ProductSplit/extension_inventory.py",
        ):
            path = self.repository / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes((canonical / relative).read_bytes())
        # Match the canonical repository's interpreter-cache exclusions.
        ignore = self.repository / ".gitignore"
        ignore.write_text(ignore.read_text() + "__pycache__/\n")
        generator = self.repository / "Scripts/SDK/generate_manifest.py"
        generator.write_text(GENERATOR.replace(
            "root=Path(__file__).resolve().parents[2]",
            "root=Path(__file__).resolve().parents[2]\n"
            "import sys\n"
            "sys.path.insert(0,str(root/'Scripts/CI/IntegrationValidation'))\n"
            "from project_graph import parse_project\n"
            "assert parse_project('{}') == {}"))
        self.git("add", ".")
        self.git("commit", "-m", "Use original generator project graph imports")
        self.revision = self.git("rev-parse", "HEAD")
        self.lock_products(["HanlinAgentCore"])

        receipt = self.install()
        sdk = self.host / "Vendor/HanlinSDK"
        self.assertEqual(receipt["state"], "installed")
        self.assertTrue((sdk / "Scripts/ProductSplit/extension_inventory.py").is_file())
        self.assertEqual(installer.check(self.host, self.lock, "Vendor/HanlinSDK")["state"], "installed")

    def test_mutable_ref_and_destination_escape_are_rejected(self):
        self.lock.write_text(json.dumps({"revision": "main", "products": ["HanlinAgentCore"]}))
        with self.assertRaisesRegex(ValueError, "immutable"):
            installer.read_lock(self.lock)
        with self.assertRaisesRegex(ValueError, "inside the host"):
            installer.destination_path(self.host, "../another-project")


if __name__ == "__main__":
    unittest.main()
