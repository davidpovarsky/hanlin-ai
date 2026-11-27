"""Real Git + original SDK fingerprint/Host validator; no native acceptance.

The original producer hashes canonical source inputs. Compiler/framework bytes
below are explicit archive-protocol fixtures; no packages are installed or run.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from test_native_provenance import HOST, REPOSITORY, NativeSourceFixture, native, installer


SOURCE_ROOTS = (
    "Scripts/MiniApps", "Scripts/Expo", "Scripts/ExpoNativeAPI", "Scripts/NativeScript",
    "Packages/HanlinExpoNativeAPI", "Packages/HanlinExpoNativeAPIJS",
    "Packages/HanlinExpoRuntime", "Packages/HanlinExpoUI",
    "Packages/HanlinNativeScriptRuntime", "Packages/HanlinPlatform",
    "Tools/SwiftUIBridge", "docs/miniapp-sdk", "docs/widget-engines",
    "docs/hanlin-expo-runtime.md", "docs/hanlin-nativescript-guide.md",
)


def fingerprint(root):
    return json.loads(subprocess.check_output([
        "node", str(root / "Scripts/MiniApps/stage-sdk.mjs"),
        "--fingerprint", "--repository=" + str(root)], text=True))


class AuthoringSourceFixture(NativeSourceFixture):
    def __init__(self, root, sources):
        super().__init__(root)
        for name, content in sources.items():
            path = self.sdk / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        (self.sdk / HOST / "miniapp-authoring.mjs").write_text(
            "export const fixture = 'authoring-enabled';\n")
        self.git("add", ".")
        self.git("commit", "-m", "Original SDK producer and canonical source inputs")
        producer = self.git("rev-parse", "HEAD")
        self.git_documents = {name: (self.sdk / name).read_bytes()
                              for name in native.PREPARED_SDK_DOCUMENTS}
        self.git_widgets = {name: (self.sdk / name).read_bytes() for name in native.PREPARED_WIDGET_FILES}
        # Original preparation regenerates these four tracked docs. Distinct
        # valid bytes exercise that overlay rather than silently using Git docs.
        for name, content in self.git_documents.items():
            (self.sdk / name).write_bytes(content + b"\n")
        widget_receipt = self.sdk / native.WIDGET_RUNTIME_ROOT / "original-runtime-receipt.json"
        widget_receipt.write_bytes(widget_receipt.read_bytes() + b"\n")
        inputs = fingerprint(self.sdk)
        sdk_files = {name: (self.sdk / name).read_bytes()
                     for name in native.PREPARED_SDK_DOCUMENTS}
        sdk_files["compiler/typescript.js"] = b"// archive-presence fixture, never executed\n"
        engines = {}
        for engine in ("expo", "nativescript", "scriptwidget"):
            sdk_files[engine + "/tsconfig.json"] = b"{}\n"
            engines[engine] = {"tsconfigPath": engine + "/tsconfig.json",
                               "typescriptPath": "compiler/typescript.js"}
        manifest = {"schemaVersion": 1, "inputSHA256": inputs["sha256"],
                    "sourceInputs": inputs["files"], "engines": engines,
                    "files": [{"path": name, "sha256": hashlib.sha256(content).hexdigest(),
                               "bytes": len(content)} for name, content in sorted(sdk_files.items())]}
        self.members = {"MiniAppSDK/" + name: content for name, content in sdk_files.items()}
        self.members["MiniAppSDK/miniapp-sdk.json"] = json.dumps(manifest).encode()
        host = self.sdk / HOST
        for name in ("package.json", "package-lock.json", "fixture.mjs", "miniapp-authoring.mjs"):
            self.members[name] = (host / name).read_bytes()
        self.write_archive()
        support = self.archives["HanlinNodeHostSupport"]
        with zipfile.ZipFile(support, "w") as archive:
            archive.writestr("HanlinNodeHostSupport/AI_HLY/RuntimeHostResources.zip",
                             self.host_archive.read_bytes())
        record = self.catalog["supportArtifacts"][0]
        record.update(checksum=native.digest(support), bytes=support.stat().st_size)
        widget_support = self.archives["HanlinExpoWidgetRuntimeSupport"]
        with zipfile.ZipFile(widget_support, "w") as archive:
            for name in sorted(native.PREPARED_WIDGET_FILES):
                archive.writestr("HanlinExpoWidgetRuntimeSupport/" + name, (self.sdk / name).read_bytes())
        widget_record = self.catalog["supportArtifacts"][1]
        widget_record.update(checksum=native.digest(widget_support), bytes=widget_support.stat().st_size)
        records = self.catalog["artifacts"] + self.catalog["supportArtifacts"]
        identity = hashlib.sha256(json.dumps({item["target"]: item["checksum"] for item in records},
            sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        tag = "sdk-native-v1-" + identity
        for item in records:
            item["url"] = f"https://github.com/{native.REPOSITORY}/releases/download/{tag}/{item['archive']}"
        self.catalog.update(sourceCommit=producer, releaseTag=tag, contentSHA256=identity,
                            inputSHA256=native.source_inputs(self.sdk))
        native.json_write(self.sdk / "docs/native-artifacts.json", self.catalog)
        self.git("add", "docs/native-artifacts.json")
        self.git("commit", "-m", "Pin authoring Host support fixture")
        native.json_write(self.native_receipt, {"releaseTag": tag, "paths": {
            native.TARGETS["NodeMobile"]: self.catalog["artifacts"][0]["checksum"],
            "AI_HLY/RuntimeHostResources.zip": record["checksum"],
            native.WIDGET_RUNTIME_ROOT: widget_record["checksum"]}})
        self.pin()

    def write_archive(self):
        with zipfile.ZipFile(self.host_archive, "w") as archive:
            for name, content in self.members.items():
                archive.writestr(name, content)

    def restore_git_documents(self):
        for name, content in self.git_documents.items():
            (self.sdk / name).write_bytes(content)

    def sparse(self):
        # Begin with the actual clean sparse-consumer state, then let the real
        # installer retrieve the published prepared dependency in canonical order.
        for name, content in self.git_widgets.items():
            (self.sdk / name).write_bytes(content)
        super().sparse()
        import shutil
        shutil.rmtree(self.sdk / native.WIDGET_RUNTIME_ROOT, ignore_errors=True)

    def validate(self):
        native.validate_node_support(self.sdk, self.host_archive, self.git("rev-parse", "HEAD"))


class NativeAuthoringProvenanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Snapshot once, then retain only the inputs selected by the actual
        # original producer. The broad Git roots also work from a sparse tree.
        with tempfile.TemporaryDirectory(prefix="hanlin-sdk-fingerprint-source-",
                dir=os.environ.get("HANLIN_SDK_TEST_ROOT")) as directory:
            root = Path(directory)
            _, sources = native.pinned_files(REPOSITORY, SOURCE_ROOTS)
            for name, content in sources.items():
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(content)
            inputs = fingerprint(root)
            cls.sources = {item["path"]: sources[item["path"]] for item in inputs["files"]}

    def fixture(self):
        temporary = tempfile.TemporaryDirectory(prefix="hanlin-authoring-provenance-",
            dir=os.environ.get("HANLIN_SDK_TEST_ROOT"))
        self.addCleanup(temporary.cleanup)
        return AuthoringSourceFixture(Path(temporary.name), self.sources)

    def test_prepared_authoring_host_uses_original_sdk_fingerprint(self):
        fixture = self.fixture()
        archive = fixture.host_archive.read_bytes()
        documents = {name: (fixture.sdk / name).read_bytes() for name in fixture.git_documents}
        fixture.validate()
        self.assertEqual(fixture.host_archive.read_bytes(), archive)
        self.assertEqual({name: (fixture.sdk / name).read_bytes() for name in documents}, documents)

    def test_pristine_and_sparse_installed_consumers_use_verified_prepared_docs(self):
        fixture = self.fixture()
        fixture.restore_git_documents()
        before = fixture.host_archive.read_bytes()
        # Full producer worktrees retain their original dirty-source guard.
        with self.assertRaisesRegex(ValueError, "actual source edit"):
            fixture.check()
        fixture.sparse()
        self.assertFalse((fixture.sdk / "Scripts/MiniApps/stage-sdk.mjs").exists())
        requested = []
        def download(item, cache):
            requested.append(item["target"])
            return fixture.archives[item["target"]]
        with patch.object(native, "download", side_effect=download):
            native.install(fixture.catalog, fixture.sdk, fixture.cache, ["NodeMobile"], True)
        self.assertEqual(requested, ["HanlinExpoWidgetRuntimeSupport"])
        self.assertEqual(fixture.check()["state"], "installed")
        self.assertEqual(fixture.host_archive.read_bytes(), before)
        self.assertFalse((fixture.sdk / "Scripts/MiniApps/stage-sdk.mjs").exists())

    def test_new_pinned_sdk_file_rejects_stale_support_before_receipt_commit(self):
        fixture = self.fixture()
        fixture.restore_git_documents()
        fixture.commit_change("Scripts/MiniApps/new-public-contract.mjs", "export const changed = true;\n")
        fixture.sparse()
        fixture.host_archive.unlink()
        receipt = json.loads(fixture.native_receipt.read_text())
        receipt["paths"].pop("AI_HLY/RuntimeHostResources.zip")
        native.json_write(fixture.native_receipt, receipt)
        before = fixture.native_receipt.read_bytes()
        requested = []
        def download(item, cache):
            requested.append(item["target"])
            return fixture.archives[item["target"]]
        with patch.object(native, "download", side_effect=download):
            with self.assertRaisesRegex(ValueError, "MiniApp SDK differs from current host source inputs"):
                native.install(fixture.catalog, fixture.sdk, fixture.cache, ["NodeMobile"], True)
        self.assertEqual(requested, ["HanlinExpoWidgetRuntimeSupport", "HanlinNodeHostSupport"])
        expected_receipt = json.loads(before)
        expected_receipt["preparedSourceSHA256"] = native.widget_source_hashes(fixture.sdk)
        self.assertEqual(json.loads(fixture.native_receipt.read_text()), expected_receipt)
        self.assertNotIn("AI_HLY/RuntimeHostResources.zip", expected_receipt["paths"])
        self.assertFalse(fixture.host_archive.exists())

    def test_dirty_sdk_source_and_unrelated_prepared_doc_are_rejected(self):
        fixture = self.fixture()
        script = fixture.sdk / "Scripts/MiniApps/stage-sdk.mjs"
        original = script.read_bytes()
        script.write_bytes(original + b"\n// uncommitted SDK change\n")
        with self.assertRaisesRegex(ValueError, "Modified native preparation input"):
            fixture.validate()
        script.write_bytes(original)
        document = fixture.sdk / "docs/miniapp-sdk/source-inventory.json"
        document.write_bytes(document.read_bytes() + b"\n")
        with self.assertRaisesRegex(ValueError, "Modified prepared SDK document"):
            fixture.validate()

    def test_tampered_prepared_document_and_ambiguous_input_inventory_are_rejected(self):
        fixture = self.fixture()
        name = "MiniAppSDK/docs/miniapp-sdk/source-inventory.json"
        original = fixture.members[name]
        fixture.members[name] = original + b"\n"
        fixture.write_archive()
        with self.assertRaisesRegex(ValueError, "Prepared SDK document digest differs"):
            fixture.validate()
        fixture.members[name] = original
        name = "MiniAppSDK/miniapp-sdk.json"
        manifest = json.loads(fixture.members[name])
        manifest["sourceInputs"].append(manifest["sourceInputs"][0])
        fixture.members[name] = json.dumps(manifest).encode()
        fixture.write_archive()
        with self.assertRaisesRegex(ValueError, "Duplicate or invalid MiniApp SDK source input"):
            fixture.validate()


    def test_pristine_resource_adoption_and_upgrade_preserve_exact_ownership(self):
        fixture = self.fixture()
        fixture.restore_git_documents()
        for name, content in fixture.git_widgets.items():
            (fixture.sdk / name).write_bytes(content)
        # An older full catalog has the carrier but not the new requiredBy edge.
        widget = next(item for item in fixture.catalog["supportArtifacts"]
                      if item["target"] == "HanlinExpoWidgetRuntimeSupport")
        widget["requiredBy"] = ["ExpoUI", "ExpoModulesCore"]
        native.json_write(fixture.sdk / "docs/native-artifacts.json", fixture.catalog)
        fixture.git("add", "docs/native-artifacts.json")
        fixture.git("commit", "-m", "Original older full catalog metadata")
        fixture.pin()
        receipt = json.loads(fixture.native_receipt.read_text())
        receipt["paths"].pop(native.WIDGET_RUNTIME_ROOT)
        native.json_write(fixture.native_receipt, receipt)
        downloaded = []
        def download(item, cache):
            downloaded.append(item["target"])
            return fixture.archives[item["target"]]
        with patch.object(native, "download", side_effect=download):
            native.install(fixture.catalog, fixture.sdk, fixture.cache, ["NodeMobile"], True)
        self.assertEqual(downloaded, ["HanlinExpoWidgetRuntimeSupport"])
        self.assertEqual(fixture.check()["state"], "installed")
        self.assertEqual(set(native.managed_source_outputs(fixture.sdk)), native.PREPARED_WIDGET_FILES)
        receipt_path = fixture.sdk / native.WIDGET_RUNTIME_ROOT / "original-runtime-receipt.json"
        installed = receipt_path.read_bytes()
        receipt_path.write_bytes(installed + b"\n")
        with self.assertRaisesRegex(ValueError, "edited outside the installer"):
            fixture.check()
        with self.assertRaisesRegex(ValueError, "edited outside the installer"):
            installer.reset_generated(fixture.sdk)
        self.assertEqual(receipt_path.read_bytes(), installed + b"\n")
        receipt_path.write_bytes(installed)
        host_before = fixture.host_archive.read_bytes()
        installer.reset_generated(fixture.sdk)
        self.assertEqual({name: (fixture.sdk / name).read_bytes() for name in fixture.git_widgets}, fixture.git_widgets)
        after = json.loads(fixture.native_receipt.read_text())
        self.assertNotIn(native.WIDGET_RUNTIME_ROOT, after["paths"])
        self.assertNotIn("preparedSourceSHA256", after)
        self.assertEqual(fixture.host_archive.read_bytes(), host_before)
        # The next install can safely adopt that same pristine set again.
        with patch.object(native, "download", side_effect=download):
            native.install(fixture.catalog, fixture.sdk, fixture.cache, ["NodeMobile"], True)
        self.assertEqual(fixture.check()["state"], "installed")

    def test_modified_or_extra_unmanaged_widget_resources_cannot_be_adopted(self):
        for extra in (False, True):
            with self.subTest(extra=extra):
                fixture = self.fixture()
                fixture.restore_git_documents()
                for name, content in fixture.git_widgets.items():
                    (fixture.sdk / name).write_bytes(content)
                receipt = json.loads(fixture.native_receipt.read_text())
                receipt["paths"].pop(native.WIDGET_RUNTIME_ROOT)
                native.json_write(fixture.native_receipt, receipt)
                changed = fixture.sdk / native.WIDGET_RUNTIME_ROOT / ("user-file.js" if extra else "original-runtime-receipt.json")
                changed.write_bytes(b"unmanaged user bytes")
                before = fixture.native_receipt.read_bytes()
                with patch.object(native, "download", side_effect=lambda item, cache: fixture.archives[item["target"]]):
                    with self.assertRaises(ValueError):
                        native.install(fixture.catalog, fixture.sdk, fixture.cache, ["NodeMobile"], True)
                self.assertEqual(changed.read_bytes(), b"unmanaged user bytes")
                self.assertEqual(fixture.native_receipt.read_bytes(), before)

    def test_incomplete_published_widget_set_preserves_pristine_source_and_receipt(self):
        fixture = self.fixture()
        fixture.restore_git_documents()
        for name, content in fixture.git_widgets.items():
            (fixture.sdk / name).write_bytes(content)
        receipt = json.loads(fixture.native_receipt.read_text())
        receipt["paths"].pop(native.WIDGET_RUNTIME_ROOT)
        native.json_write(fixture.native_receipt, receipt)
        before = fixture.native_receipt.read_bytes()
        widget = next(item for item in fixture.catalog["supportArtifacts"]
                      if item["target"] == "HanlinExpoWidgetRuntimeSupport")
        carrier = fixture.archives[widget["target"]]
        omitted = native.WIDGET_RUNTIME_ROOT + "/README.txt"
        with zipfile.ZipFile(carrier, "w") as archive:
            for name in sorted(native.PREPARED_WIDGET_FILES - {omitted}):
                archive.writestr("HanlinExpoWidgetRuntimeSupport/" + name,
                                 (fixture.sdk / name).read_bytes())
        widget.update(checksum=native.digest(carrier), bytes=carrier.stat().st_size)
        with patch.object(native, "download", side_effect=lambda item, cache: fixture.archives[item["target"]]):
            with self.assertRaisesRegex(ValueError, "Prepared Expo Widget source inventory differs"):
                native.install(fixture.catalog, fixture.sdk, fixture.cache, ["NodeMobile"], True)
        self.assertEqual(fixture.native_receipt.read_bytes(), before)
        self.assertEqual({name: (fixture.sdk / name).read_bytes() for name in fixture.git_widgets},
                         fixture.git_widgets)

    def test_missing_widget_carrier_and_modified_legacy_support_fail_closed(self):
        fixture = self.fixture()
        incomplete = {**fixture.catalog, "supportArtifacts": [
            item for item in fixture.catalog["supportArtifacts"] if item["target"] != "HanlinExpoWidgetRuntimeSupport"]}
        with patch.object(native, "download", side_effect=AssertionError("must reject incomplete catalog before IO")):
            with self.assertRaisesRegex(ValueError, "Selected host support has not been published"):
                native.install(incomplete, fixture.sdk, fixture.cache, ["NodeMobile"], True)
        changed = fixture.sdk / native.WIDGET_RUNTIME_ROOT / "original-runtime-receipt.json"
        changed.write_bytes(changed.read_bytes() + b"\n")
        before = fixture.native_receipt.read_bytes()
        with patch.object(native, "download", side_effect=lambda item, cache: fixture.archives[item["target"]]):
            with self.assertRaisesRegex(ValueError, "Refusing to adopt modified legacy Widget resources"):
                native.install(fixture.catalog, fixture.sdk, fixture.cache, ["NodeMobile"], True)
        self.assertEqual(fixture.native_receipt.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
