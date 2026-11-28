"""Pure controls for the original runner's ordinary system-surface input producer.

All inputs below are temporary unit documents. No simulator, HTTP endpoint,
production queue or native acceptance is invoked by this module.
"""
from pathlib import Path
import copy
import hashlib
import importlib.util
import json
import os
import sys
import tempfile
import unittest
import uuid
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
with patch.dict(os.environ, {"SPLIT_EVIDENCE": "/unit-only-not-a-native-run"}):
    spec = importlib.util.spec_from_file_location("original_system_input_runner",
                                                ROOT / "run_paired_acceptance.py")
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
import observe_shortcut_surfaces as common


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    raw = (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")
    path.write_bytes(raw)
    return hashlib.sha256(raw).hexdigest()


class OriginalSystemInputProducerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.evidence = self.root / "paired-product"
        self.evidence.mkdir()
        self.evidence_patch = patch.object(runner, "EVIDENCE", self.evidence)
        self.evidence_patch.start()
        self.addCleanup(self.evidence_patch.stop)
        self.data = self.root / "unit-miniapps-data"
        (self.data / "Documents").mkdir(parents=True)
        outputs = self.evidence / "shortcut-surface-fixtures"
        outputs.mkdir()
        rows = []
        for engine, name in (("expo", "SurfaceExpo.hanlinExpo"),
                             ("nativescript", "SurfaceNativeScript.hanlinNativeScript")):
            raw = ("unit producer archive bytes for " + engine).encode()
            (outputs / name).write_bytes(raw)
            rows.append({"engine": engine, "archive": name, "archiveSHA256": hashlib.sha256(raw).hexdigest()})
        self.inputs, self.resources = runner.system_surface_inputs({"archives": rows})

    def request(self, engine="expo"):
        run_id = str(uuid.uuid4())
        app_id = "hanlin.surface." + engine
        challenge = "actual-prepared-123"
        identity = {"installedPackageID": "installed-" + engine, "packageID": app_id,
                    "generation": 7, "entrypointID": "surface-share", "variantID": "default"}
        catalog = {"schemaVersion": 1, "revision": 1, "packages": {
            identity["installedPackageID"]: {"enabled": True, "record": {
                "schemaVersion": 1, "installedPackageID": identity["installedPackageID"],
                "packageID": app_id, "activeGeneration": identity["generation"]}}}}
        write_json(self.data / "Library/Application Support/Hanlin/ScriptingPlatform/Installed/registry/catalog.json", catalog)
        proof = (self.data / "Library/Application Support/HanlinPackages" /
                 identity["installedPackageID"] / "State/surface-proof.json") if engine == "expo" else (
                 self.data / "Library/Application Support/Hanlin/MiniApps" / app_id / "State/surface-proof.json")
        sha = write_json(proof, {"schemaVersion": 1, "appID": app_id,
                                "challenge": challenge, "counter": 0, "lastResult": None})
        value = {"schema": 1, "runID": run_id, "engine": engine, "appID": app_id,
                 "seed": self.inputs["value"]["seed"], "challenge": challenge,
                 "preparedProofSHA256": sha, "dataContainer": str(self.data),
                 "startedAt": "2026-11-27T05:00:00.123456+00:00", "installedIdentity": identity}
        path = self.evidence / "shortcut-observer" / run_id / "share-input-request.json"
        write_json(path, value)
        return path, value, proof

    def response_path(self, value):
        return self.evidence / "system-surface-share-inputs" / (value["runID"] + ".json")

    def test_both_engines_receive_exact_ordinary_files_and_input_provenance_only(self):
        for engine in ("expo", "nativescript"):
            with self.subTest(engine=engine):
                path, value, proof = self.request(engine)
                before = proof.read_bytes()
                calls = []
                def resolve():
                    calls.append("read-current-container")
                    return self.data
                response = runner.stage_system_surface_share_input(path, self.inputs, resolve)
                self.assertEqual(calls, ["read-current-container"] * 2)
                self.assertEqual(response["status"], "STAGED_INPUTS_ONLY")
                self.assertEqual(response["producerRequestSHA256"], hashlib.sha256(path.read_bytes()).hexdigest())
                self.assertEqual(response["shareInputFolder"], "HanlinSurfaceInputs-" + value["runID"])
                files = {row["name"]: row for row in response["shareInputFiles"]}
                self.assertEqual(set(files), {"share-input.json", "share-note.txt"})
                expected_json = {"schema": 1, "kind": "hanlin.surface.share-input", "runID": value["runID"],
                                 "appID": value["appID"], "seed": value["seed"], "challenge": value["challenge"]}
                expected_text = "Hanlin Share input {} {} {} {}\n".format(
                    value["seed"], value["runID"], engine, value["challenge"])
                expected = {"share-input.json": json.dumps(expected_json, ensure_ascii=False,
                                                           sort_keys=True, indent=2) + "\n",
                            "share-note.txt": expected_text}
                folder = self.data / "Documents" / response["shareInputFolder"]
                for name, text in expected.items():
                    raw = text.encode("utf-8")
                    self.assertEqual((folder / name).read_bytes(), raw)
                    self.assertEqual(files[name], {"name": name, "bytes": len(raw),
                                                  "sha256": hashlib.sha256(raw).hexdigest(), "text": text})
                self.assertEqual(proof.read_bytes(), before)
                self.assertEqual(json.loads(self.response_path(value).read_text()), response)
                self.assertEqual(set(response), set(value) | {
                    "status", "producerRequestSHA256", "shareInputFolder", "shareInputFiles"})

    def test_unprepared_or_consistently_rebound_request_cannot_create_inputs(self):
        for mutation in ("hash", "challenge", "seed", "schema", "extra", "counter"):
            with self.subTest(mutation=mutation):
                path, value, proof = self.request()
                if mutation == "hash":
                    value["preparedProofSHA256"] = "0" * 64
                elif mutation == "challenge":
                    value["challenge"] = "different-fresh-456"
                elif mutation == "seed":
                    value["seed"] = str(uuid.uuid4())
                elif mutation == "schema":
                    value["schema"] = True
                elif mutation == "extra":
                    value["productionQueuePath"] = "/must-not-be-written"
                else:
                    state = json.loads(proof.read_text())
                    state["counter"] = False
                    value["preparedProofSHA256"] = write_json(proof, state)
                write_json(path, value)
                with self.assertRaises((common.ObservationError, ValueError)):
                    runner.stage_system_surface_share_input(path, self.inputs, lambda: self.data)
                self.assertFalse(self.response_path(value).exists())
                self.assertFalse((self.data / "Documents" / ("HanlinSurfaceInputs-" + value["runID"])).exists())

    def test_replay_cannot_overwrite_existing_files_or_provenance(self):
        path, value, _ = self.request()
        response = runner.stage_system_surface_share_input(path, self.inputs, lambda: self.data)
        target = self.data / "Documents" / response["shareInputFolder"] / "share-note.txt"
        target.write_text("actual user modification retained\n")
        original_response = self.response_path(value).read_bytes()
        with self.assertRaises(common.ObservationError):
            runner.stage_system_surface_share_input(path, self.inputs, lambda: self.data)
        self.assertEqual(target.read_text(), "actual user modification retained\n")
        self.assertEqual(self.response_path(value).read_bytes(), original_response)

    def test_old_or_replaced_mcm_never_receives_a_ready_input_response(self):
        replacement = self.root / "replacement-data"
        (replacement / "Documents").mkdir(parents=True)
        path, value, _ = self.request()
        with self.assertRaises(common.ObservationError):
            runner.stage_system_surface_share_input(path, self.inputs, lambda: replacement)
        self.assertFalse(list((self.data / "Documents").iterdir()))
        observed = iter((self.data, replacement))
        with self.assertRaises(common.ObservationError):
            runner.stage_system_surface_share_input(path, self.inputs, lambda: next(observed))
        self.assertFalse(self.response_path(value).exists())
        self.assertFalse(list((replacement / "Documents").iterdir()))

    def test_changed_private_preparation_during_staging_never_writes_provenance(self):
        path, value, proof = self.request()
        calls = []
        def resolve():
            calls.append(True)
            if len(calls) == 2:
                state = json.loads(proof.read_text())
                state["challenge"] = "replacement-owner-challenge"
                write_json(proof, state)
            return self.data
        with self.assertRaises(common.ObservationError):
            runner.stage_system_surface_share_input(path, self.inputs, resolve)
        self.assertFalse(self.response_path(value).exists())

    def test_linked_request_or_documents_cannot_escape_the_owned_input_path(self):
        path, value, _ = self.request()
        retained = self.root / "outside-request.json"
        path.rename(retained)
        path.symlink_to(retained)
        with self.assertRaises(common.ObservationError):
            runner.stage_system_surface_share_input(path, self.inputs, lambda: self.data)
        path.unlink()
        path.write_bytes(retained.read_bytes())
        documents = self.data / "Documents"
        documents.rmdir()
        outside = self.root / "outside-documents"
        outside.mkdir()
        documents.symlink_to(outside, target_is_directory=True)
        with self.assertRaises(common.ObservationError):
            runner.stage_system_surface_share_input(path, self.inputs, lambda: self.data)
        self.assertFalse(list(outside.iterdir()))
        self.assertFalse(self.response_path(value).exists())

    def test_changed_manifest_or_cancelled_producer_cannot_write_inputs(self):
        path, value, _ = self.request()
        manifest = Path(self.inputs["path"])
        original = manifest.read_bytes()
        manifest.write_bytes(original + b" ")
        with self.assertRaises(common.ObservationError):
            runner.stage_system_surface_share_input(path, self.inputs, lambda: self.data)
        manifest.write_bytes(original)
        with self.assertRaises(common.ObservationError):
            runner.stage_system_surface_share_input(path, self.inputs, lambda: self.data, lambda: True)
        self.assertFalse(list((self.data / "Documents").iterdir()))
        self.assertFalse(self.response_path(value).exists())

    def test_translation_pages_are_retained_real_input_bytes_without_a_transport_claim(self):
        self.assertFalse((self.evidence / "shortcut-observer").exists())
        actual = common.load_system_inputs(Path(self.inputs["path"]), self.evidence / "shortcut-observer")
        self.assertEqual(actual, self.inputs)
        for engine, page in actual["value"]["translation"].items():
            route = "/surfaces/" + actual["value"]["seed"] + "/" + engine
            status, content_type, body = self.resources[route]
            self.assertEqual((status, content_type), (200, "text/html; charset=utf-8"))
            self.assertEqual(hashlib.sha256(body).hexdigest(), page["htmlSHA256"])
            self.assertEqual((self.evidence / "system-surface-pages" / (engine + ".html")).read_bytes(), body)
            self.assertIn(page["text"].encode("utf-8"), body)
            self.assertEqual(page["url"], "http://localhost:49173" + route)
        self.assertFalse(Path(actual["value"]["transportLog"]).exists())


    def test_request_installation_identity_and_generation_cannot_be_rebound(self):
        for mutation in ("missing", "other-id", "other-app", "generation", "bool-generation",
                         "traversal", "absolute", "entrypoint", "variant", "extra"):
            with self.subTest(mutation=mutation):
                path, value, proof = self.request()
                before = proof.read_bytes()
                identity = value["installedIdentity"]
                if mutation == "missing": del value["installedIdentity"]
                if mutation == "other-id": identity["installedPackageID"] = "uninstalled-sibling"
                if mutation == "other-app": identity["packageID"] = "hanlin.surface.nativescript"
                if mutation == "generation": identity["generation"] += 1
                if mutation == "bool-generation": identity["generation"] = True
                if mutation == "traversal": identity["installedPackageID"] = "../installed-expo"
                if mutation == "absolute": identity["installedPackageID"] = str(self.data)
                if mutation == "entrypoint": identity["entrypointID"] = "surface-translation"
                if mutation == "variant": identity["variantID"] = "other"
                if mutation == "extra": identity["unexpected"] = "unbound"
                write_json(path, value)
                with self.assertRaises(common.ObservationError):
                    runner.stage_system_surface_share_input(path, self.inputs, lambda: self.data)
                self.assertFalse(self.response_path(value).exists())
                self.assertFalse((self.data / "Documents" / ("HanlinSurfaceInputs-" + value["runID"])).exists())
                self.assertEqual(proof.read_bytes(), before)

    def test_catalog_identity_is_revalidated_before_and_after_input_writes(self):
        catalog_path = self.data / "Library/Application Support/Hanlin/ScriptingPlatform/Installed/registry/catalog.json"
        for boundary in (1, 2):
            for mutation in ("missing", "disabled", "id", "app", "generation", "bool-generation"):
                with self.subTest(boundary=boundary, mutation=mutation):
                    path, value, proof = self.request()
                    before = proof.read_bytes()
                    calls = []
                    def resolve():
                        calls.append(True)
                        if len(calls) == boundary:
                            catalog = json.loads(catalog_path.read_text())
                            installed_id = value["installedIdentity"]["installedPackageID"]
                            entry = catalog["packages"][installed_id]
                            if mutation == "missing": del catalog["packages"][installed_id]
                            if mutation == "disabled": entry["enabled"] = False
                            if mutation == "id": entry["record"]["installedPackageID"] = "other"
                            if mutation == "app": entry["record"]["packageID"] = "other"
                            if mutation == "generation": entry["record"]["activeGeneration"] += 1
                            if mutation == "bool-generation": entry["record"]["activeGeneration"] = True
                            write_json(catalog_path, catalog)
                        return self.data
                    with self.assertRaises(common.ObservationError):
                        runner.stage_system_surface_share_input(path, self.inputs, resolve)
                    self.assertEqual(len(calls), boundary)
                    self.assertFalse(self.response_path(value).exists())
                    if boundary == 1:
                        self.assertFalse((self.data / "Documents" / ("HanlinSurfaceInputs-" + value["runID"])).exists())
                    self.assertEqual(proof.read_bytes(), before)

    def test_enabled_sibling_package_proof_cannot_replace_the_bound_installation(self):
        path, value, proof = self.request()
        sibling = self.data / "Library/Application Support/HanlinPackages/installed-sibling/State/surface-proof.json"
        sibling.parent.mkdir(parents=True)
        proof.rename(sibling)
        catalog_path = self.data / "Library/Application Support/Hanlin/ScriptingPlatform/Installed/registry/catalog.json"
        catalog = json.loads(catalog_path.read_text())
        sibling_entry = copy.deepcopy(catalog["packages"][value["installedIdentity"]["installedPackageID"]])
        sibling_entry["record"]["installedPackageID"] = "installed-sibling"
        catalog["packages"]["installed-sibling"] = sibling_entry
        write_json(catalog_path, catalog)
        with self.assertRaises(common.ObservationError):
            runner.stage_system_surface_share_input(path, self.inputs, lambda: self.data)
        self.assertFalse(self.response_path(value).exists())
        self.assertFalse(list((self.data / "Documents").iterdir()))


if __name__ == "__main__":
    unittest.main()
