"""Pure reader controls; retained catalog semantics are not OS execution evidence."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Scripts/ProductSplit"))
import observe_shortcut_surfaces as observer


class WidgetCatalogCompatibilityTests(unittest.TestCase):
    def fixture(self, root):
        # Reuse the unchanged semantic registry entry retained by the original
        # Swift projection test; do not invent a supported compatibility value.
        swift = (ROOT / "Packages/HanlinPlatform/Tests/HanlinScriptStoreTests/"
                 "HanlinCanonicalEntrypointProjectionTests.swift").read_text()
        marker = 'private static let storedCatalogEntryJSON = #"""'
        self.assertEqual(swift.count(marker), 1)
        entry = json.loads(swift.split(marker, 1)[1].split('"""#', 1)[0])
        widget = next(row for row in entry["entrypoints"] if row["kind"] == "widget")
        self.assertEqual(widget["compatibility"], "partial")
        record = entry["record"]
        identity = {"installedPackageID": record["installedPackageID"],
                    "packageID": record["packageID"], "generation": record["activeGeneration"],
                    "entrypointID": widget["id"],
                    "variantID": "01234567-89ab-4cde-8f01-23456789abcd"}
        request = {"instanceName": "Canonical widget reader control",
                   "expectedFamily": "systemMedium"}
        fixture = observer.load_widget_fixture(
            ROOT / "Fixtures/Widgets/Hanlin-Expo-Widget-Interactive-Matrix.hanlinExpo")
        data, extensions = root / "data", root / "extensions"
        data.mkdir(); extensions.mkdir()
        program = {"engine": "expo", "abiVersion": 1,
                   "sourceSHA256": fixture["sourceSHA256"],
                   "families": fixture["metadata"]["families"],
                   "actions": fixture["metadata"]["actions"]}
        raw = json.dumps(program, sort_keys=True).encode()
        program_sha = hashlib.sha256(raw).hexdigest()
        reference = "Packages/{}/generations/{}/artifacts/{}".format(
            identity["installedPackageID"], identity["generation"], program_sha)
        artifact = extensions / reference
        artifact.parent.mkdir(parents=True); artifact.write_bytes(raw)
        descriptor = {"layoutRef": reference, "layoutSHA256": program_sha, "props": {}}
        snapshot = {"widgetInstances": [{"identity": identity, "engine": "expo",
                     "displayName": request["instanceName"], "settings": {}}],
                    "widgets": [{"identity": identity, "engine": "expo", "family": family,
                                 "validUntil": (time.time() + 600) * 1000,
                                 "payload": {"expoDescriptor": copy.deepcopy(descriptor)}}
                                for family in fixture["metadata"]["families"]]}
        raw = json.dumps({"schemaVersion": 1, "snapshot": snapshot}, sort_keys=True).encode()
        snapshot_sha = hashlib.sha256(raw).hexdigest()
        revisions = extensions / "Revisions"; revisions.mkdir()
        (revisions / (snapshot_sha + ".json")).write_bytes(raw)
        (extensions / "commit.json").write_text(json.dumps({"version": 1, "snapshotHash": snapshot_sha}))
        catalog = {"schemaVersion": 1, "revision": 1,
                   "packages": {identity["installedPackageID"]: entry}}
        path = data / "Library/Application Support/Hanlin/ScriptingPlatform/Installed/registry/catalog.json"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps(catalog))
        return request, {"data": data, "extensions": extensions}, fixture, catalog, path, artifact

    def test_recorded_partial_widget_qualifies_without_rewriting_catalog(self):
        with tempfile.TemporaryDirectory() as temporary:
            request, roots, fixture, catalog, path, _ = self.fixture(Path(temporary))
            before = path.read_bytes()
            facts = observer.widget_facts(request, roots, fixture)
            self.assertEqual(facts["catalog"]["value"], catalog)
            self.assertEqual(facts["identity"]["generation"], facts["installedRecord"]["activeGeneration"])
            self.assertEqual(path.read_bytes(), before)

    def test_supported_widget_remains_admitted(self):
        with tempfile.TemporaryDirectory() as temporary:
            request, roots, fixture, catalog, path, _ = self.fixture(Path(temporary))
            entry = next(iter(catalog["packages"].values()))
            next(row for row in entry["entrypoints"] if row["kind"] == "widget")["compatibility"] = "supported"
            path.write_text(json.dumps(catalog))
            before = path.read_bytes()
            self.assertEqual(observer.widget_facts(request, roots, fixture)["catalog"]["value"], catalog)
            self.assertEqual(path.read_bytes(), before)

    def test_partial_widget_rejects_invalid_catalog_and_artifact_contracts(self):
        with tempfile.TemporaryDirectory() as temporary:
            request, roots, fixture, catalog, path, artifact = self.fixture(Path(temporary))
            changes = [("compatibility", value) for value in ("unsupported", "unknown", None, {}, [])]
            changes += [("kind", "app"), ("widgetEngine", "legacy"),
                        ("runtimeProfile", "scripting-jsc"), ("supportedContexts", ["mainApplication"]),
                        ("id", "another-entrypoint"), ("enabled", False),
                        ("activeGeneration", 0), ("installedPackageID", "another-installation"),
                        ("packageID", "another-package"), ("recordSchema", 2),
                        ("registrySchema", 2), ("registryRevision", "1"), ("duplicate", True)]
            for field, value in changes:
                with self.subTest(field=field, value=value):
                    candidate = copy.deepcopy(catalog)
                    entry = next(iter(candidate["packages"].values()))
                    widget = next(row for row in entry["entrypoints"] if row["kind"] == "widget")
                    if field == "enabled":
                        entry[field] = value
                    elif field in ("activeGeneration", "installedPackageID", "packageID"):
                        entry["record"][field] = value
                    elif field == "recordSchema":
                        entry["record"]["schemaVersion"] = value
                    elif field == "registrySchema":
                        candidate["schemaVersion"] = value
                    elif field == "registryRevision":
                        candidate["revision"] = value
                    elif field == "duplicate":
                        entry["entrypoints"].append(copy.deepcopy(widget))
                    else:
                        widget[field] = value
                    path.write_text(json.dumps(candidate))
                    before = path.read_bytes()
                    with self.assertRaises(observer.ObservationError):
                        observer.widget_facts(request, roots, fixture)
                    self.assertEqual(path.read_bytes(), before)
            path.write_text(json.dumps(catalog))
            artifact.write_bytes(artifact.read_bytes() + b" ")
            with self.assertRaisesRegex(observer.ObservationError, "committed digest"):
                observer.widget_facts(request, roots, fixture)


if __name__ == "__main__":
    unittest.main()
