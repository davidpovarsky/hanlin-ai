"""Portable Gallery reader controls; these are not compiler or OS acceptance."""
from pathlib import Path
import copy
import json
import re
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Scripts" / "ProductSplit"))
import observe_studio_gallery as gallery


class StudioGalleryCanonicalCompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.sequence = 0

    @staticmethod
    def json_bytes(value):
        return (json.dumps(value, sort_keys=True) + "\n").encode()

    def installed_fixture(self, compatibility=None):
        # Reuse the unchanged Swift projection test's actual stored registry
        # semantics, including its partial foreground app and original policy.
        source = (
            ROOT / "Packages/HanlinPlatform/Tests/HanlinScriptStoreTests"
            / "HanlinCanonicalEntrypointProjectionTests.swift"
        ).read_text()
        match = re.search(
            r'private static let storedCatalogEntryJSON = #"""\n(.*?)\n    """#',
            source, re.S,
        )
        self.assertIsNotNone(match)
        original = json.loads(match.group(1))
        entry = copy.deepcopy(original)
        app = next(item for item in entry["entrypoints"] if item["kind"] == "app")
        self.assertEqual(app["compatibility"], "partial")
        self.assertEqual(app["runtimePolicyID"], "foreground-app-v1")
        self.assertEqual(app["runtimeProfile"], "hanlin-expo")
        self.assertEqual(app["supportedContexts"], ["mainApplication"])
        self.assertEqual(app["sourcePath"], "source/" + entry["manifest"]["entry"])
        if compatibility is not None:
            app["compatibility"] = compatibility

        self.sequence += 1
        data = self.root / str(self.sequence) / "data"
        data.mkdir(parents=True)
        archive_path = data / "build" / "Gallery.hanlinExpo"
        archive_path.parent.mkdir()
        # Small controlled reader input, never a compiler-produced package.
        # The serialized registry's contract fields stay original; only byte
        # provenance is rebound to these real ZIP/generation test files.
        members = {
            "script.json": self.json_bytes(entry["manifest"]),
            "bundle.js": b"export const portableGalleryReaderControl = true;\n",
        }
        with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED) as archive:
            for name, raw in members.items():
                archive.writestr(name, raw)
        archive_hash = gallery.shared.digest(archive_path.read_bytes())
        files = [
            {"logicalPath": "source/" + name, "sha256": gallery.shared.digest(raw),
             "byteCount": len(raw)}
            for name, raw in sorted(members.items())
        ]
        artifact_hash = gallery.shared.digest(
            "\n".join(item["logicalPath"] + ":" + item["sha256"] for item in files).encode()
        )
        entry["record"]["sourceDigest"] = archive_hash
        entry["record"]["artifactDigest"] = artifact_hash
        for item in entry["entrypoints"]:
            item["artifactDigest"] = artifact_hash
        installed_id = entry["record"]["installedPackageID"]
        catalog = {"schemaVersion": 1, "revision": 1, "packages": {installed_id: entry}}
        catalog_path = data / gallery.INSTALLED / "registry/catalog.json"
        catalog_path.parent.mkdir(parents=True)
        catalog_path.write_bytes(self.json_bytes(catalog))
        generation = (
            data / gallery.INSTALLED / "packages" / installed_id / "generations"
            / str(entry["record"]["activeGeneration"])
        )
        generation.mkdir(parents=True)
        metadata = {
            **entry["record"], "entrypoints": copy.deepcopy(entry["entrypoints"]),
            "manifest": copy.deepcopy(entry["manifest"]),
        }
        (generation / "generation.json").write_bytes(self.json_bytes(metadata))
        artifact = {
            "schemaVersion": 1, "packageContentDigest": archive_hash,
            "cacheFingerprint": artifact_hash, "files": files,
        }
        (generation / "artifact-manifest.json").write_bytes(self.json_bytes(artifact))
        for name, raw in members.items():
            path = generation / "source" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
        return {
            "case": {
                "fixed": {"engine": "expo"}, "baselineInstalledIDs": [],
                "build": {
                    "archive": {"path": str(archive_path), "sha256": archive_hash},
                    "manifest": copy.deepcopy(entry["manifest"]),
                },
            },
            "roots": {"data": data}, "entry": entry, "originalEntry": original,
            "catalog": catalog, "catalogPath": catalog_path, "generation": generation,
            "archivePath": archive_path, "members": members, "app": app,
        }

    def write_catalog(self, fixture):
        fixture["catalogPath"].write_bytes(self.json_bytes(fixture["catalog"]))

    def alter_document(self, path, key, value):
        document = json.loads(path.read_text())
        document[key] = value
        path.write_bytes(self.json_bytes(document))

    def test_original_serialized_partial_app_passes_every_archive_guard(self):
        fixture = self.installed_fixture()
        result = gallery.installed_build(fixture["case"], fixture["roots"])
        self.assertEqual(result["entrypoint"], fixture["app"])
        self.assertEqual(result["record"], fixture["entry"]["record"])
        self.assertEqual(result["identity"]["generation"], 10)
        self.assertEqual(result["identity"]["entrypointID"], "app")
        self.assertEqual(result["source"]["authorManifest"], fixture["originalEntry"]["manifest"])
        self.assertEqual(
            set(result["source"]["installedSources"]),
            {"source/" + name for name in fixture["members"]},
        )
        for name, raw in fixture["members"].items():
            self.assertEqual(
                result["source"]["installedSources"]["source/" + name]["sha256"],
                gallery.shared.digest(raw),
            )

    def test_supported_app_keeps_the_original_archive_admission(self):
        fixture = self.installed_fixture("supported")
        result = gallery.installed_build(fixture["case"], fixture["roots"])
        self.assertEqual(result["entrypoint"]["compatibility"], "supported")
        self.assertEqual(
            result["source"]["archive"]["sha256"],
            fixture["case"]["build"]["archive"]["sha256"],
        )

    def test_partial_app_cannot_bypass_original_identity_and_artifact_guards(self):
        def duplicate_archive(fixture):
            duplicate = copy.deepcopy(fixture["entry"])
            fixture["catalog"]["packages"]["another-install"] = duplicate

        mutations = [
            ("boolean catalog schema", lambda f: f["catalog"].update(schemaVersion=True),
             "primary catalog revision"),
            ("boolean catalog revision", lambda f: f["catalog"].update(revision=True),
             "primary catalog revision"),
            ("duplicate archive package", duplicate_archive, "exactly one current installed package"),
            ("preexisting package", lambda f: f["case"]["baselineInstalledIDs"].append(
                f["entry"]["record"]["installedPackageID"]), "fresh enabled package"),
            ("disabled", lambda f: f["entry"].update(enabled=False), "fresh enabled package"),
            ("wrong installed identity", lambda f: f["entry"]["record"].update(
                installedPackageID="another-install"), "fresh enabled package"),
            ("zero generation", lambda f: f["entry"]["record"].update(activeGeneration=0),
             "fresh enabled package"),
            ("boolean generation", lambda f: f["entry"]["record"].update(activeGeneration=True),
             "fresh enabled package"),
            ("wrong kind", lambda f: f["app"].update(kind="widget"), "foreground app entry"),
            ("duplicate app", lambda f: f["entry"]["entrypoints"].append(copy.deepcopy(f["app"])),
             "foreground app entry"),
            ("unsupported", lambda f: f["app"].update(compatibility="unsupported"), "foreground app entry"),
            ("unknown compatibility", lambda f: f["app"].update(compatibility="ready"), "foreground app entry"),
            ("missing compatibility", lambda f: f["app"].pop("compatibility"), "foreground app entry"),
            ("boolean compatibility", lambda f: f["app"].update(compatibility=True), "foreground app entry"),
            ("other runtime", lambda f: f["app"].update(runtimeProfile="hanlin-nativescript"),
             "foreground app entry"),
            ("other context", lambda f: f["app"].update(supportedContexts=["widget"]),
             "foreground app entry"),
            ("unprefixed source", lambda f: f["app"].update(sourcePath="bundle.js"), "foreground app entry"),
            ("other source", lambda f: f["app"].update(sourcePath="source/other.js"), "foreground app entry"),
            ("changed archive bytes", lambda f: f["archivePath"].write_bytes(
                f["archivePath"].read_bytes() + b"changed"), "Produced archive bytes changed"),
            ("changed generation metadata", lambda f: self.alter_document(
                f["generation"] / "generation.json", "version", "other"),
             "generation metadata differs"),
            ("changed artifact archive binding", lambda f: self.alter_document(
                f["generation"] / "artifact-manifest.json", "packageContentDigest", "0" * 64),
             "artifact provenance differs"),
            ("changed artifact fingerprint", lambda f: self.alter_document(
                f["generation"] / "artifact-manifest.json", "cacheFingerprint", "0" * 64),
             "artifact provenance differs"),
            ("changed retained source", lambda f: (f["generation"] / "source/bundle.js").write_bytes(
                b"changed"), "Actual installed source differs"),
            ("changed expected author manifest", lambda f: f["case"]["build"]["manifest"].update(
                name="another app"), "current installed source no longer names"),
        ]
        for name, mutate, message in mutations:
            with self.subTest(defect=name):
                fixture = self.installed_fixture()
                mutate(fixture)
                self.write_catalog(fixture)
                with self.assertRaisesRegex(gallery.shared.ObservationError, message):
                    gallery.installed_build(fixture["case"], fixture["roots"])


if __name__ == "__main__":
    unittest.main()
