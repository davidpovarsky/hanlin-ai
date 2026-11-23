"""Actual-Git native provenance regressions, not native runtime acceptance.

Cached framework bytes and Host packages are small protocol fixtures. The
complete production installer and original Host archive validator are used.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SDK = Path(__file__).resolve().parents[1]
REPOSITORY = SDK.parents[1]

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

native = load("native_provenance_artifacts", SDK / "native_artifacts.py")
installer = load("native_provenance_installer", SDK / "install.py")
HOST = "AI_HLY/Downstream/RuntimeCore/Node/Host"
VALIDATOR = "Scripts/Runtime/runtime_host_archive.py"


class NativeSourceFixture:
    def __init__(self, root):
        self.root = root
        self.host = root / "host"
        self.sdk = self.host / "Vendor/HanlinSDK"
        self.sdk.mkdir(parents=True)
        self.cache = root / "cache"
        self.lock = self.host / "HanlinSDK.lock.json"
        for name in native.INPUTS:
            path = self.sdk / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("declared preparation fixture: " + name + "\n")
        for name in ("native_artifacts.py", "install.py"):
            path = self.sdk / "Scripts/SDK" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes((SDK / name).read_bytes())
        validator = subprocess.check_output(
            ["git", "-C", str(REPOSITORY), "show", "HEAD:" + VALIDATOR])
        path = self.sdk / VALIDATOR
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(validator)
        host = self.sdk / HOST
        host.mkdir(parents=True)
        (host / "package.json").write_text('{"dependencies":{}}\n')
        (host / "package-lock.json").write_text('{"packages":{}}\n')
        (host / "fixture.mjs").write_text('export const fixture = "original";\n')
        (self.sdk / ".gitignore").write_text(
            "/.hanlin-sdk/\n/Vendor/\n/AI_HLY/RuntimeHostResources.zip\n")
        (self.sdk / "Package.swift").write_text("// generated profile fixture\n")
        profile = self.sdk / "docs/agent-sdk/unified-package-manifest.json"
        profile.parent.mkdir(parents=True)
        profile.write_text("{}\n")
        self.git("init", "-b", "main")
        self.git("add", ".")
        self.git("commit", "-m", "Pinned preparation and Host source fixture")
        producer = self.git("rev-parse", "HEAD")
        self.archives = {}
        framework = root / "NodeMobile.xcframework.zip"
        with zipfile.ZipFile(framework, "w") as archive:
            archive.writestr("NodeMobile.xcframework/selection.txt",
                             "cached-framework-selection-fixture")
        self.archives["NodeMobile"] = framework
        self.host_archive = self.sdk / "AI_HLY/RuntimeHostResources.zip"
        with zipfile.ZipFile(self.host_archive, "w") as archive:
            for name in ("package.json", "package-lock.json", "fixture.mjs"):
                archive.writestr(name, (host / name).read_bytes())
        support = root / "HanlinNodeHostSupport.zip"
        with zipfile.ZipFile(support, "w") as archive:
            archive.writestr("HanlinNodeHostSupport/AI_HLY/RuntimeHostResources.zip",
                             self.host_archive.read_bytes())
        self.archives["HanlinNodeHostSupport"] = support
        records = []
        for name, archive in self.archives.items():
            item = {"target": name, "kind": "xcframework" if name == "NodeMobile" else "host-support",
                    "root": "NodeMobile.xcframework" if name == "NodeMobile" else name,
                    "archive": archive.name, "checksum": native.digest(archive),
                    "bytes": archive.stat().st_size}
            if name == "NodeMobile":
                item["installPath"] = native.TARGETS[name]
            else:
                item.update(installPaths=["AI_HLY/RuntimeHostResources.zip"], requiredBy=["NodeMobile"])
            records.append(item)
        identity = hashlib.sha256(json.dumps({item["target"]: item["checksum"] for item in records},
            sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        tag = "sdk-native-v1-" + identity
        for item in records:
            item["url"] = f"https://github.com/{native.REPOSITORY}/releases/download/{tag}/{item['archive']}"
        self.catalog = {"schemaVersion": 1, "state": "published", "repository": native.REPOSITORY,
            "sourceCommit": producer, "releaseTag": tag, "contentSHA256": identity,
            "requiredTargets": list(native.TARGETS), "artifacts": [records[0]],
            "supportArtifacts": [records[1]], "inputSHA256": native.source_inputs(self.sdk)}
        native.json_write(self.sdk / "docs/native-artifacts.json", self.catalog)
        self.git("add", ".")
        self.git("commit", "-m", "Content-addressed fixture catalog")
        installed = self.sdk / native.TARGETS["NodeMobile"]
        installed.mkdir(parents=True)
        (installed / "selection.txt").write_text("cached-framework-selection-fixture")
        self.native_receipt = self.sdk / ".hanlin-sdk/native-artifacts-installed.json"
        native.json_write(self.native_receipt, {"releaseTag": tag, "paths": {
            native.TARGETS["NodeMobile"]: records[0]["checksum"],
            "AI_HLY/RuntimeHostResources.zip": records[1]["checksum"]}})
        self.pin()

    def git(self, *arguments):
        return subprocess.check_output(["git", "-C", str(self.sdk), "-c", "user.name=ChatGPT",
            "-c", "user.email=noreply@openai.com", *arguments],
            text=True, stderr=subprocess.PIPE).strip()

    def pin(self):
        revision = self.git("rev-parse", "HEAD")
        products = ["HanlinRuntimeCore"]
        self.lock.write_text(json.dumps({"revision": revision, "products": products}))
        native.json_write(self.sdk / installer.RECEIPT, {"state": "installed", "revision": revision,
            "products": products, "generatedSHA256": installer.generated_hashes(self.sdk),
            "managedNativeTargets": ["NodeMobile"]})

    def commit_change(self, name, value):
        path = self.sdk / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)
        self.git("add", name)
        self.git("commit", "-m", "New pinned source fixture")
        self.pin()

    def sparse(self):
        self.git("sparse-checkout", "init", "--no-cone")
        self.git("sparse-checkout", "set", "--no-cone",
                 "/Scripts/SDK/", "/Package.swift", "/docs/", "/.gitignore")
        assert not (self.sdk / native.INPUTS[0]).exists()
        assert not (self.sdk / HOST / "package.json").exists()
        assert not (self.sdk / VALIDATOR).exists()

    def check(self):
        return installer.check(self.host, self.lock, "Vendor/HanlinSDK")


class NativeProvenanceTests(unittest.TestCase):
    def fixture(self):
        temporary = tempfile.TemporaryDirectory(prefix="hanlin-native-provenance-",
            dir=os.environ.get("HANLIN_SDK_TEST_ROOT"))
        self.addCleanup(temporary.cleanup)
        return NativeSourceFixture(Path(temporary.name))

    def rejection(self, fixture, case, operation, expected):
        before = fixture.native_receipt.read_bytes()
        host_before = fixture.host_archive.read_bytes() if fixture.host_archive.exists() else None
        error = None
        try:
            operation()
        except (ValueError, RuntimeError, subprocess.SubprocessError) as caught:
            error = str(caught)
        result = {"case": case, "scope": "ACTUAL_GIT_CONTROLLER_CONTROL_NOT_NATIVE_ACCEPTANCE",
            "nativeScriptSHA256": native.digest(SDK / "native_artifacts.py"),
            "installerSHA256": native.digest(SDK / "install.py"),
            "controlSHA256": native.digest(Path(__file__)), "error": error,
            "gitRevision": fixture.git("rev-parse", "HEAD"),
            "receiptPreserved": fixture.native_receipt.read_bytes() == before,
            "archivePreserved": (fixture.host_archive.read_bytes() if fixture.host_archive.exists() else None) == host_before}
        destination = os.environ.get("HANLIN_NATIVE_PROVENANCE_EVIDENCE")
        if destination:
            native.json_write(Path(destination) / (case + ".json"), result)
        self.assertIsNotNone(error, "Stale or incomplete native source was accepted")
        self.assertIn(expected, error.lower())
        self.assertTrue(result["receiptPreserved"])
        self.assertTrue(result["archivePreserved"])

    def test_install_rejects_stale_incomplete_or_modified_preparation_before_io(self):
        for case in ("pinned-input-sparse", "dirty-input", "missing-input"):
            with self.subTest(case=case):
                fixture = self.fixture()
                if case == "pinned-input-sparse":
                    fixture.commit_change(native.INPUTS[0], "changed pinned preparation\n")
                    fixture.sparse()
                elif case == "dirty-input":
                    (fixture.sdk / native.INPUTS[0]).write_text("uncommitted preparation change\n")
                else:
                    fixture.catalog["inputSHA256"].pop(native.INPUTS[0])
                with patch.object(native, "download", side_effect=AssertionError("must reject before IO")):
                    self.rejection(fixture, case, lambda: native.install(fixture.catalog, fixture.sdk,
                        fixture.cache, ["NodeMobile"], True), "preparation input")

    def test_check_rejects_old_native_source_and_old_host_after_pin_update(self):
        for case, path in (("check-pinned-input", native.INPUTS[0]),
                           ("check-host-module", HOST + "/fixture.mjs")):
            with self.subTest(case=case):
                fixture = self.fixture()
                fixture.commit_change(path, "changed pinned source\n")
                fixture.sparse()
                self.rejection(fixture, case, fixture.check,
                    "preparation input" if case == "check-pinned-input" else "node host")

    def test_stale_host_is_rejected_before_existing_or_new_support_is_committed(self):
        for case in ("cached-host-source", "staged-host-source"):
            with self.subTest(case=case):
                fixture = self.fixture()
                fixture.commit_change(HOST + "/fixture.mjs", 'export const fixture = "changed";\n')
                fixture.sparse()
                if case == "staged-host-source":
                    fixture.host_archive.unlink()
                    receipt = json.loads(fixture.native_receipt.read_text())
                    receipt["paths"].pop("AI_HLY/RuntimeHostResources.zip")
                    native.json_write(fixture.native_receipt, receipt)
                requested = []
                def download(item, cache):
                    requested.append(item["target"])
                    self.assertEqual(item["target"], "HanlinNodeHostSupport")
                    return fixture.archives[item["target"]]
                with patch.object(native, "download", side_effect=download):
                    self.rejection(fixture, case, lambda: native.install(fixture.catalog, fixture.sdk,
                        fixture.cache, ["NodeMobile"], True), "node host")
                self.assertEqual(requested, [] if case == "cached-host-source" else ["HanlinNodeHostSupport"])

    def test_sparse_doc_descendant_preserves_assets_and_passes_install_and_check(self):
        fixture = self.fixture()
        fixture.commit_change("README.md", "Documentation-only descendant\n")
        fixture.sparse()
        original = fixture.host_archive.read_bytes()
        with patch.object(native, "download", side_effect=AssertionError("managed assets must be reused")):
            native.install(fixture.catalog, fixture.sdk, fixture.cache, ["NodeMobile"], True)
        self.assertEqual(fixture.check()["state"], "installed")
        self.assertEqual(fixture.host_archive.read_bytes(), original)
        self.assertFalse((fixture.sdk / HOST / "package.json").exists())
        self.assertFalse((fixture.sdk / VALIDATOR).exists())


if __name__ == "__main__":
    unittest.main()
