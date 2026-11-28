"""Pure negative controls for the existing Widget/Activity observer inputs.

These temporary documents are unit inputs only, never native/OS acceptance
evidence or files written to a simulator. Existing Shortcuts fixtures are reused
without running or changing their original test bodies.
"""
from pathlib import Path
import copy
import hashlib
import importlib.util
import json
import sys
import tempfile
import time
import unittest
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import observe_widget_action_surfaces as surfaces

spec = importlib.util.spec_from_file_location("original_shortcut_unit_inputs",
                                            Path(__file__).with_name("test_shortcut_surface_observer.py"))
original = importlib.util.module_from_spec(spec)
spec.loader.exec_module(original)


def example(engine="expo", surface="widget"):
    request, anchor, commands, proofs = original.example(engine, True)
    request.update(surface=surface, fixtureTitle="Surface Expo" if engine == "expo" else "Surface NativeScript")
    parameters = {"surface": surface, "fixture": request["fixtureAppID"]}
    if surface == "liveActivity" and engine == "expo":
        parameters["shownChallenge"] = request["challenge"]
    identity = {**anchor["identity"], "entrypointID": "widget", "variantID": "default"}
    publication = {"identity": identity, "engine": "expo" if engine == "expo" else "scriptwidget",
                   "programs": {family: {"sha256": "a" * 64} for family in surfaces.FAMILIES}}
    row = next(iter(commands.values()))["value"]
    row["invocation"]["parameters"] = original.tagged(parameters)
    delivery = row["invocation"]["delivery"]
    delivery.update(source=surface, canPresentUI=True)
    if not (surface == "liveActivity" and engine == "expo"):
        parameter_bytes = json.dumps({"parameters": row["invocation"]["parameters"]},
                                    sort_keys=True, separators=(",", ":")).encode()
        delivery["widgetOrigin"] = {"identity": copy.deepcopy(identity), "engine": publication["engine"],
            "artifactSHA256": "a" * 64, "family": "systemMedium", "actionID": "surface-host-run",
            "parametersSHA256": hashlib.sha256(parameter_bytes).hexdigest()}
    original.change_result(commands, proofs,
                           lambda value: value.update(request=parameters, requestedSurface=surface))
    return request, anchor, commands, proofs, publication


def completed(values, baseline=()):
    request, anchor, commands, proofs, publication = values
    return surfaces.completed(request, anchor, set(baseline), commands, proofs, publication, 1795737600000)


def fixture_metadata(engine):
    return {"abiVersion": 1, "sourceFormat": "expo-layout" if engine == "expo" else "jsx",
            "families": list(surfaces.FAMILIES),
            "actions": [{"id": "surface-host-run", "kind": "hostAction", "hostAction": {
                "entrypointID": "surface-intent", "actionName": "surface.run",
                "parameters": {"surface": "widget", "fixture": "hanlin.surface." + engine}}}]}


def publication_tree(root, engine="expo"):
    values = example(engine)
    request, anchor = values[:2]
    data, extensions = root / "data", root / "group" / "HanlinMiniApps/v1/ScriptingExtensions"
    data.mkdir(parents=True)
    extensions.mkdir(parents=True)
    identity = values[4]["identity"]
    widget_engine = values[4]["engine"]
    source = b"unit-only actual authored entry bytes\n"
    fixture = {"widgetSourceSHA256": hashlib.sha256(source).hexdigest(),
               "engine": widget_engine, "metadata": fixture_metadata(engine)}
    program = {"abiVersion": 1, "engine": widget_engine, "sourceSHA256": fixture["widgetSourceSHA256"],
               "families": list(surfaces.FAMILIES), "actions": fixture["metadata"]["actions"],
               "javaScript": "unit fixture, never executed"}
    program_raw = json.dumps(program, sort_keys=True).encode()
    program_sha = hashlib.sha256(program_raw).hexdigest()
    reference = "Packages/{}/generations/{}/artifacts/{}".format(
        identity["installedPackageID"], identity["generation"], program_sha)
    artifact = extensions / reference
    artifact.parent.mkdir(parents=True)
    artifact.write_bytes(program_raw)
    descriptor = ({"layoutRef": reference, "layoutSHA256": program_sha,
                   "props": {"challenge": original.tagged(request["challenge"]), "counter": original.tagged(0)}}
                  if engine == "expo" else {"scriptRef": reference, "scriptSHA256": program_sha})
    payload = {"kind": widget_engine,
               "expoDescriptor" if engine == "expo" else "scriptDescriptor": descriptor}
    snapshot = {"widgetInstances": [{"identity": identity, "engine": widget_engine,
                                     "displayName": request["fixtureTitle"], "settings": {}}],
                "widgets": [{"identity": identity, "engine": widget_engine,
                             "family": family, "validUntil": (time.time() + 600) * 1000,
                             "payload": copy.deepcopy(payload)} for family in surfaces.FAMILIES],
                "widgetStates": [], "inactiveWidgetInstallations": []}
    catalog = data / "Library/Application Support/Hanlin/ScriptingPlatform/Installed/registry/catalog.json"
    catalog.parent.mkdir(parents=True)
    entry = {"enabled": True, "record": {"schemaVersion": 1,
             "installedPackageID": identity["installedPackageID"], "packageID": identity["packageID"],
             "activeGeneration": identity["generation"]},
             "entrypoints": [
                 {"id": "surface-intent", "kind": "appIntent", "compatibility": "supported",
                  "supportedContexts": ["appIntent"], "runtimeProfile": "hanlin-" + engine,
                  "runtimePolicyID": "prepared-foreground-action-v1", "exportedSymbol": "surface.run",
                  "sourcePath": anchor["hostActionHandler"]},
                 {"id": "widget", "kind": "widget", "widgetEngine": widget_engine,
                  "compatibility": "supported", "supportedContexts": ["widget"]}]}
    catalog.write_text(json.dumps({"schemaVersion": 1, "revision": 1, "packages": {
        identity["installedPackageID"]: entry}}))
    def publish():
        raw = json.dumps({"schemaVersion": 1, "snapshot": snapshot}, sort_keys=True).encode()
        digest = hashlib.sha256(raw).hexdigest()
        revisions = extensions / "Revisions"
        revisions.mkdir(exist_ok=True)
        (revisions / (digest + ".json")).write_bytes(raw)
        (extensions / "commit.json").write_text(json.dumps({"version": 1, "snapshotHash": digest}))
    publish()
    return request, {"data": data, "extensions": extensions}, anchor, fixture, snapshot, publish, artifact


class OriginalWidgetActivityEvidenceControls(unittest.TestCase):
    def test_both_original_engines_and_real_native_source_forms_qualify(self):
        for engine in ("expo", "nativescript"):
            for surface in surfaces.SURFACES:
                with self.subTest(engine=engine, surface=surface):
                    result = completed(example(engine, surface))
                    self.assertEqual(result["status"], "EXECUTED_PASS")
                    self.assertEqual(result["engines"], list(surfaces.common.CANONICAL_ENGINES))
                    self.assertEqual(result["command"]["value"]["invocation"]["delivery"]["source"], surface)

    def test_stale_wrong_or_unbound_widget_origins_cannot_qualify(self):
        mutations = [
            lambda origin: origin["identity"].update(generation=4),
            lambda origin: origin["identity"].update(variantID="another"),
            lambda origin: origin.update(engine="legacy"),
            lambda origin: origin.update(family="systemExtraLarge"),
            lambda origin: origin.update(actionID="different"),
            lambda origin: origin.update(artifactSHA256="b" * 64),
            lambda origin: origin.update(parametersSHA256="c" * 64),
        ]
        for engine in ("expo", "nativescript"):
            for index, mutate in enumerate(mutations):
                with self.subTest(engine=engine, mutation=index):
                    values = example(engine)
                    mutate(next(iter(values[2].values()))["value"]["invocation"]["delivery"]["widgetOrigin"])
                    with self.assertRaises(surfaces.common.ObservationError):
                        completed(values)

    def test_consistent_wrong_native_button_payload_still_fails(self):
        for engine in ("expo", "nativescript"):
            for surface in surfaces.SURFACES:
                with self.subTest(engine=engine, surface=surface):
                    values = example(engine, surface)
                    row = next(iter(values[2].values()))["value"]
                    payload = {"surface": surface, "fixture": "another.fixture"}
                    row["invocation"]["parameters"] = original.tagged(payload)
                    if row["invocation"]["delivery"].get("widgetOrigin"):
                        raw = json.dumps({"parameters": row["invocation"]["parameters"]},
                                         sort_keys=True, separators=(",", ":")).encode()
                        row["invocation"]["delivery"]["widgetOrigin"]["parametersSHA256"] = hashlib.sha256(raw).hexdigest()
                    original.change_result(values[2], values[3], lambda result: result.update(request=payload))
                    with self.assertRaises(surfaces.common.ObservationError):
                        completed(values)

    def test_native_node_activity_cannot_borrow_a_widget_origin(self):
        values = example("expo", "liveActivity")
        row = next(iter(values[2].values()))["value"]
        row["invocation"]["delivery"]["widgetOrigin"] = {"identity": values[4]["identity"]}
        with self.assertRaisesRegex(surfaces.common.ObservationError, "must not invent"):
            completed(values)
        values = example("nativescript", "liveActivity")
        next(iter(values[2].values()))["value"]["invocation"]["delivery"].pop("widgetOrigin")
        with self.assertRaises(surfaces.common.ObservationError):
            completed(values)

    def test_pending_replayed_cancelled_or_duplicate_system_commands_do_not_pass(self):
        values = example()
        self.assertIsNone(completed(values, values[2]))
        row = next(iter(values[2].values()))["value"]
        for pending in ("queued", "running"):
            row["receipt"]["status"] = pending
            self.assertIsNone(completed(values))
        row["receipt"]["status"] = "cancelled"
        with self.assertRaises(surfaces.common.ObservationError):
            completed(values)
        values = example()
        row = next(iter(values[2].values()))["value"]
        row["createdAt"] = 1795737599000
        with self.assertRaisesRegex(surfaces.common.ObservationError, "predates"):
            completed(values)
        values = example()
        key = str(uuid.uuid4())
        values[2][key] = copy.deepcopy(next(iter(values[2].values())))
        with self.assertRaisesRegex(surfaces.common.ObservationError, "more than once"):
            completed(values)
        values = example()
        next(iter(values[2].values()))["value"]["invocation"]["delivery"]["source"] = "foreground"
        self.assertIsNone(completed(values))

    def test_current_publication_verifies_exact_artifact_bytes_and_generation(self):
        for engine in ("expo", "nativescript"):
            with self.subTest(engine=engine), tempfile.TemporaryDirectory() as temporary:
                request, roots, anchor, fixture, snapshot, publish, artifact = publication_tree(Path(temporary), engine)
                observed = surfaces.widget_publication(request, roots, anchor, fixture)
                self.assertEqual(set(observed["programs"]), set(surfaces.FAMILIES))
                artifact.write_bytes(artifact.read_bytes() + b" ")
                with self.assertRaises(surfaces.common.ObservationError):
                    surfaces.widget_publication(request, roots, anchor, fixture)
        for mutation in ("family", "generation", "expired", "source", "disabled"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temporary:
                request, roots, anchor, fixture, snapshot, publish, artifact = publication_tree(Path(temporary))
                if mutation == "family":
                    snapshot["widgets"][0]["family"] = "systemExtraLargePortrait"
                elif mutation == "generation":
                    snapshot["widgetInstances"][0]["identity"]["generation"] += 1
                elif mutation == "expired":
                    snapshot["widgets"][0]["validUntil"] = 1
                elif mutation == "source":
                    fixture["widgetSourceSHA256"] = "0" * 64
                else:
                    snapshot["inactiveWidgetInstallations"] = [anchor["identity"]["installedPackageID"]]
                publish()
                with self.assertRaises(surfaces.common.ObservationError):
                    surfaces.widget_publication(request, roots, anchor, fixture)

    def test_widget_and_activity_publications_bind_the_ui_prepared_challenge(self):
        with tempfile.TemporaryDirectory() as temporary:
            request, roots, anchor, fixture, snapshot, publish, artifact = publication_tree(Path(temporary))
            publication = surfaces.widget_publication(request, roots, anchor, fixture)
            surfaces.require_fresh_widget_publication(request, publication)
            publication["descriptors"]["systemSmall"]["props"]["challenge"] = original.tagged("stale-abc-def")
            with self.assertRaises(surfaces.common.ObservationError):
                surfaces.require_fresh_widget_publication(request, publication)
        request = example("nativescript", "liveActivity")[0]
        publication = {"states": [{"values": {"challenge": original.tagged(request["challenge"]),
                                              "counter": original.tagged(0)}}]}
        surfaces.require_fresh_widget_publication(request, publication)
        publication["states"][0]["values"]["counter"] = original.tagged(False)
        with self.assertRaises(surfaces.common.ObservationError):
            surfaces.require_fresh_widget_publication(request, publication)

    def test_original_archive_is_byte_bound_and_cannot_be_replaced_by_a_link(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "SurfaceExpo.hanlinExpo"
            script = {"hanlinAppID": "hanlin.surface.expo", "widgetEngine": "expo",
                      "hanlinRuntime": "hanlin-expo", "hanlinWidget": fixture_metadata("expo")}
            with zipfile.ZipFile(archive, "w") as packed:
                packed.writestr("script.json", json.dumps(script))
                packed.writestr("widget.json", "(props) => ({type:'Text',props:{children:props.challenge}})")
            inputs = {"path": str(root / "inputs.json"), "value": {"schema": 1,
                "surfaceArchives": {"expo": {"path": str(archive),
                    "sha256": hashlib.sha256(archive.read_bytes()).hexdigest()}}}}
            self.assertEqual(surfaces.widget_fixture(inputs, "expo")["metadata"], script["hanlinWidget"])
            inputs["value"]["surfaceArchives"]["expo"]["sha256"] = "0" * 64
            with self.assertRaises(surfaces.common.ObservationError):
                surfaces.widget_fixture(inputs, "expo")
            real = root / "retained.zip"
            archive.rename(real)
            archive.symlink_to(real)
            with self.assertRaises(surfaces.common.ObservationError):
                surfaces.widget_fixture(inputs, "expo")


    def test_changed_prepared_request_or_exchange_cannot_rebind_a_live_case(self):
        request = example()[0]
        directory = Path("/unit-xctest/Documents/HanlinSystemSurfaceObservation") / request["runID"]
        case = {"kind": "originalWidgetActivity", "directory": str(directory),
                "requestIdentity": {key: request[key] for key in surfaces.REQUEST_IDENTITY_FIELDS}}
        surfaces.require_prepared_case(request, directory, case)
        for field, value in (("challenge", "fresh-but-replaced"), ("surface", "liveActivity"),
                             ("startedAt", "2026-11-27T00:00:01Z"), ("baselineCounter", False),
                             ("fixtureAppID", "hanlin.surface.nativescript")):
            changed = {**request, field: value}
            with self.subTest(field=field), self.assertRaises(surfaces.common.ObservationError):
                surfaces.require_prepared_case(changed, directory, case)
        with self.assertRaises(surfaces.common.ObservationError):
            surfaces.require_prepared_case(request, directory.parent / str(uuid.uuid4()), case)

    def test_identical_sibling_result_or_replaced_activity_cannot_claim_the_owner(self):
        for engine in ("expo", "nativescript"):
            for surface in ("widget", "liveActivity"):
                with self.subTest(engine=engine, surface=surface):
                    values = example(engine, surface)
                    result = completed(values)
                    result["privateProof"]["value"]["activityID"] = "actual-host-start-id"
                    case = {"prepared": copy.deepcopy(result["privateProof"]),
                            "requestIdentity": {"surface": surface},
                            "phaseResponse": {"activityID": "actual-host-start-id"}}
                    surfaces.require_original_owner(result, case)
                    result["privateProof"]["path"] += ".different-window"
                    with self.assertRaises(surfaces.common.ObservationError):
                        surfaces.require_original_owner(result, case)
                    result["privateProof"]["path"] = case["prepared"]["path"]
                    if surface == "liveActivity":
                        result["privateProof"]["value"]["activityID"] = "replacement-activity"
                        with self.assertRaises(surfaces.common.ObservationError):
                            surfaces.require_original_owner(result, case)

    def test_current_extension_root_replacement_is_not_a_terminal_product_match(self):
        from types import SimpleNamespace
        from unittest.mock import patch
        roots = {"app": Path("/unit/app"), "data": Path("/unit/data"), "group": Path("/unit/group"),
                 "extensions": Path("/unit/group/HanlinMiniApps/v1/ScriptingExtensions"),
                 "configuration": {"StorageNamespace": "HanlinMiniApps/v1"}, "infoSHA256": "a" * 64}
        extension = {"path": "/unit/app/PlugIns/ActualWidget.appex", "sha256": "b" * 64}
        changed = {**roots, "extensions": Path("/unit/group/replaced")}
        args = SimpleNamespace(device="unit-device", bundle_id="com.itorah.hanlinminiapps")
        with patch.object(surfaces.common, "product_roots", return_value=changed), \
                patch.object(surfaces.common, "widget_extension_executable", return_value=extension), \
                self.assertRaises(surfaces.common.ObservationError):
            surfaces.current_product(args, roots, extension)


if __name__ == "__main__":
    unittest.main()
