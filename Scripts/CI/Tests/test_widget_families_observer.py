"""Pure evidence rejection controls, not simulated WidgetKit/Simulator receipts."""
from contextlib import ExitStack
import copy
import datetime
from pathlib import Path
import struct
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "ProductSplit"))
import observe_widget_families as reader

Error = reader.original.ObservationError


def stamp(value):
    return datetime.datetime.fromtimestamp(value, datetime.timezone.utc).isoformat(timespec="milliseconds")


def png_header(width, height):
    # Deliberately only a parser-control header. Never retained as an OS image.
    return b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", width, height)


def fixture(family="systemMedium"):
    now = time.time() - 120
    run = str(uuid.uuid4()); label, selector = reader.FAMILIES[family]
    request = {"schema": 1, "surface": "widgetFamilies", "engine": "expo", "runID": run,
               "fixtureTitle": "Interactive Widget Matrix", "expectedFamily": family, "sizeLabel": label,
               "instanceName": "Family-" + family + "-" + run, "priorOrientation": "portrait",
               "startedAt": stamp(now), "test": "-[HanlinEntrypointSystemSurfaceUITests " + selector + "]",
               "attemptID": str(uuid.uuid4()), "sourceSHA": "1" * 40, "hostTerminated": True,
               "unboundPlacementCreated": False, "addWidgetTappedAt": stamp(now + 8)}
    request["prePlacement"] = {"visibleMatrixCount": 0, "visiblePlaceholderCount": 0,
        "screenFrame": [0, 0, 768, 1024], "orientation": "portrait", "at": stamp(now + 5), "uptime": 1005}
    request["galleryPages"] = [{"index": 0, "selected": True, "observedAt": stamp(now + 6), "uptime": 1006,
        "attachmentLabel": "widget-family-gallery-0", "rows": [
            {"label": "Hanlin Script", "value": "", "frame": [10, 10, 200, 30]},
            {"label": label, "value": "", "frame": [10, 40, 200, 30]}]}]
    native_identity = {"installedPackageID": str(uuid.uuid4()), "packageID": "matrix", "generation": 1,
                       "entrypointID": "widget", "variantID": str(uuid.uuid4())}
    initial = {"identity": native_identity, "instance": {"displayName": request["instanceName"], "settings": {}},
               "installedRecord": {"sourceDigest": "a" * 64, "activeGeneration": 1},
               "state": {"revision": 0, "values": {}, "committedNonces": []}, "values": {},
               "program": {"sha256": "b" * 64}, "catalog": {"sha256": "c" * 64},
               "otherStatesSHA256": "d" * 64, "cache": None}
    current = copy.deepcopy(initial)
    current["cache"] = {"record": {"identity": native_identity, "engine": "expo", "family": family,
        "programSHA256": "b" * 64, "settings": {}, "renderSHA256": "e" * 64, "renderedAt": (now + 8.5) * 1000},
        "artifact": {"sha256": "e" * 64}, "node": ["Matrix count: 0",
            {"type": "ToggleView", "props": {"target": "enabled", "isOn": False}}]}
    request["rotations"] = []
    for index, orientation in enumerate(reader.ORIENTATIONS):
        start = 9 + 4 * index
        screen = [0, 0, 768, 1024] if index != 1 else [0, 0, 1024, 768]
        bounds = [20 + 10 * index, 80, 300, 160]
        binding = {"instanceName": request["instanceName"], "label": request["instanceName"], "value": "",
                   "frame": bounds, "verifiedAt": stamp(now + start + 1), "verifiedUptime": 1000 + start + 1,
                   "attachmentLabel": "widget-family-configuration-" + str(index)}
        request["rotations"].append({"index": index, "requestedOrientation": orientation, "orientation": orientation,
            "requestedAt": stamp(now + start), "requestedUptime": 1000 + start,
            "capturedAt": stamp(now + start + 2), "capturedUptime": 1000 + start + 2,
            "visibleMatrixCount": 1, "markerLabel": "Matrix count: 0", "markerHittable": True,
            "hostTerminated": True, "screenFrame": screen, "widgetFrame": bounds,
            "markerFrame": [bounds[0] + 5, 90, 120, 20], "configuration": binding,
            "attachmentLabel": "widget-family-rotation-" + str(index)})
    final_binding = copy.deepcopy(request["rotations"][-1]["configuration"])
    final_binding.update(verifiedAt=stamp(now + 21), verifiedUptime=1021,
                         attachmentLabel="widget-family-cleanup-configuration")
    request["cleanup"] = {"instanceName": request["instanceName"], "configuration": final_binding,
        "action": "Remove Widget", "confirmationLabel": "Remove", "visibleMatrixCountAfter": 0,
        "hostTerminated": True, "removedAt": stamp(now + 22), "removedUptime": 1022}
    request["orientationRestoration"] = {"priorOrientation": "portrait", "orientation": "portrait",
        "screenFrame": [0, 0, 768, 1024], "restoredAt": stamp(now + 23), "restoredUptime": 1023}
    return request, initial, current, now


class WidgetFamilyEvidenceControls(unittest.TestCase):
    def test_four_distinct_family_contracts_accept_complete_correlated_evidence(self):
        for family in reader.FAMILIES:
            with self.subTest(family=family):
                request, initial, current, now = fixture(family)
                reader.request_identity(request)
                reader.require_gallery(request, (now + 4) * 1000)
                reader.require_same_native(current, initial)
                self.assertTrue(reader.fresh_family_cache(current, family, (now + 7) * 1000))
                for index, row in enumerate(request["rotations"]):
                    reader.require_rotation(row, request, index, (now + 8 + 4 * index) * 1000,
                                            request["rotations"][index - 1] if index else None)
                reader.require_cleanup_and_restoration(request, request["rotations"][-1], (now + 20) * 1000)

    def test_unsupported_family_mismatched_selector_and_nonexact_types_are_rejected(self):
        request, _, _, _ = fixture()
        for key, value in [("expectedFamily", "systemExtraLargePortrait"), ("expectedFamily", "accessoryCircular"),
                           ("sizeLabel", "Small"), ("schema", True), ("priorOrientation", "unknown"),
                           ("instanceName", "previous-case"), ("test", "testSomeOtherCase]")]:
            changed = copy.deepcopy(request); changed[key] = value
            with self.subTest(key=key, value=value), self.assertRaises((Error, ValueError)):
                reader.request_identity(changed)

    def test_prior_zero_count_widget_or_placeholder_cannot_be_admitted_as_new(self):
        request, _, _, now = fixture()
        for field, value in [("visibleMatrixCount", 1), ("visiblePlaceholderCount", 1),
                             ("visibleMatrixCount", False), ("at", stamp(now + 1))]:
            changed = copy.deepcopy(request); changed["prePlacement"][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(Error):
                reader.require_gallery(changed, (now + 4) * 1000)

    def test_swipe_ordinal_wrong_configuration_and_replayed_page_are_not_family_proof(self):
        request, _, _, now = fixture()
        changes = [lambda x: x["galleryPages"][0]["rows"][1].update(label="Page 2 of 4"),
                   lambda x: x["galleryPages"][0]["rows"][0].update(label="Expo MiniApp"),
                   lambda x: x["galleryPages"][0].update(selected=False),
                   lambda x: x["galleryPages"][0].update(index=True)]
        for change in changes:
            changed = copy.deepcopy(request); change(changed)
            with self.assertRaises(Error): reader.require_gallery(changed, (now + 4) * 1000)
        changed = copy.deepcopy(request); first = copy.deepcopy(changed["galleryPages"][0]); first["selected"] = False
        changed["galleryPages"][0]["index"] = 1; changed["galleryPages"][0]["attachmentLabel"] = "widget-family-gallery-1"
        changed["galleryPages"].insert(0, first)
        with self.assertRaises(Error): reader.require_gallery(changed, (now + 4) * 1000)

    def test_native_render_must_bind_family_instance_program_settings_and_verified_bytes(self):
        request, _, current, now = fixture()
        for key, value in [("family", "systemSmall"), ("engine", "scriptWidget"), ("programSHA256", "f" * 64),
                           ("settings", {"different": True}), ("renderSHA256", "0" * 64),
                           ("identity", {**current["identity"], "variantID": str(uuid.uuid4())})]:
            changed = copy.deepcopy(current); changed["cache"]["record"][key] = value
            with self.subTest(key=key), self.assertRaises(Error):
                reader.fresh_family_cache(changed, request["expectedFamily"], (now + 7) * 1000)

    def test_template_or_stale_preplacement_cache_cannot_count_as_fresh_render(self):
        request, initial, current, now = fixture()
        self.assertFalse(reader.fresh_family_cache(initial, request["expectedFamily"], (now + 7) * 1000))
        current["cache"]["record"]["renderedAt"] = (now + 6) * 1000
        self.assertFalse(reader.fresh_family_cache(current, request["expectedFamily"], (now + 7) * 1000))
        for value in [float("nan"), True, (time.time() + 60) * 1000]:
            current["cache"]["record"]["renderedAt"] = value
            with self.assertRaises(Error): reader.fresh_family_cache(current, request["expectedFamily"], (now + 7) * 1000)

    def test_family_rotation_cannot_modify_state_nonce_program_or_unrelated_instances(self):
        _, initial, current, _ = fixture()
        mutations = [lambda x: x["state"].update(revision=1), lambda x: x["state"]["committedNonces"].append("new"),
                     lambda x: x["program"].update(sha256="changed"), lambda x: x["catalog"].update(sha256="changed"),
                     lambda x: x.update(otherStatesSHA256="changed"), lambda x: x["instance"].update(settings={"a": 1}),
                     lambda x: x["identity"].update(generation=True)]
        for mutate in mutations:
            changed = copy.deepcopy(current); mutate(changed)
            with self.assertRaises(Error): reader.require_same_native(changed, initial)

    def test_physical_configuration_cannot_alias_another_case_or_frame(self):
        request, _, _, now = fixture(); row = request["rotations"][0]
        for key, value in [("instanceName", "another-run"), ("label", "Family-systemMedium-old"),
                           ("frame", [1, 1, 300, 160]), ("verifiedAt", stamp(now + 1))]:
            changed = copy.deepcopy(row); changed["configuration"][key] = value
            with self.subTest(key=key), self.assertRaises(Error):
                reader.require_rotation(changed, request, 0, (now + 8) * 1000)

    def test_two_visible_zero_widgets_or_missing_actual_marker_fail_closed(self):
        request, _, _, now = fixture(); row = request["rotations"][0]
        for key, value in [("visibleMatrixCount", 2), ("visibleMatrixCount", True), ("markerLabel", "Matrix count: 1"),
                           ("markerHittable", False), ("hostTerminated", False), ("markerFrame", [900, 0, 10, 10])]:
            changed = copy.deepcopy(row); changed[key] = value
            with self.subTest(key=key), self.assertRaises(Error):
                reader.require_rotation(changed, request, 0, (now + 8) * 1000)

    def test_orientation_assignment_without_effective_rotation_is_rejected(self):
        request, _, _, now = fixture(); previous, row = request["rotations"][:2]
        for key, value in [("orientation", "portrait"), ("screenFrame", [0, 0, 768, 1024]),
                           ("screenFrame", [0, 0, 1100, 768]), ("requestedUptime", 900),
                           ("requestedAt", stamp(now + 1))]:
            changed = copy.deepcopy(row); changed[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(Error):
                reader.require_rotation(changed, request, 1, (now + 12) * 1000, previous)

    def test_actual_png_dimensions_must_agree_with_effective_screen_geometry(self):
        self.assertEqual(reader.png_geometry(png_header(1536, 2048), "portrait", [0, 0, 768, 1024]), [1536, 2048])
        for raw in [b"", png_header(2048, 1536), png_header(100, 200), png_header(0, 0)]:
            with self.assertRaises(Error): reader.png_geometry(raw, "portrait", [0, 0, 768, 1024])

    def test_phase_attachment_absence_or_wrong_saved_name_cannot_qualify(self):
        request, _, _, _ = fixture(); row = request["rotations"][0]
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "source"; target = Path(folder) / "retained"
            source.mkdir(); target.mkdir()
            with self.assertRaises(Error): reader.retain_rotation(source, target, row, request)
            for label, text in [(row["attachmentLabel"], "Matrix count: 0"),
                                (row["configuration"]["attachmentLabel"], "wrong saved UUID")]:
                (source / (label + "-accessibility.txt")).write_text(text)
                (source / (label + ".png")).write_bytes(png_header(1536, 2048))
            with self.assertRaises(Error): reader.retain_rotation(source, target, row, request)

    def test_cleanup_requires_exact_owned_name_and_actual_confirmed_removal(self):
        request, _, _, now = fixture()
        for key, value in [("instanceName", "another-widget"), ("action", "Delete native state"),
                           ("confirmationLabel", "Cancel"), ("visibleMatrixCountAfter", 1),
                           ("visibleMatrixCountAfter", False), ("removedAt", stamp(now + 1))]:
            changed = copy.deepcopy(request); changed["cleanup"][key] = value
            with self.subTest(key=key), self.assertRaises(Error):
                reader.require_cleanup_and_restoration(changed, changed["rotations"][-1], (now + 20) * 1000)

    def test_prior_orientation_restoration_must_follow_cleanup_and_be_effective(self):
        request, _, _, now = fixture()
        for key, value in [("priorOrientation", "landscapeLeft"), ("orientation", "landscapeLeft"),
                           ("screenFrame", [0, 0, 1024, 768]), ("restoredUptime", 1000),
                           ("restoredAt", stamp(now + 1))]:
            changed = copy.deepcopy(request); changed["orientationRestoration"][key] = value
            with self.subTest(key=key), self.assertRaises(Error):
                reader.require_cleanup_and_restoration(changed, changed["rotations"][-1], (now + 20) * 1000)

    def finish_control(self, *, change_request=None, change_final=None, change_roots=None, change_inputs=None, change_extension=False):
        request, initial, current, now = fixture()
        request["phase"] = "widget-family-complete"
        roots = {"app": Path("/pure-control/App.app"), "data": Path("/pure-control/data"), "group": Path("/pure-control/group"),
                 "extensions": Path("/pure-control/group/extensions"), "configuration": {"StorageNamespace": "test-only"}, "infoSHA256": "2" * 64}
        extension = {"path": "/pure-control/App.app/PlugIns/Widget.appex/Widget", "infoSHA256": "3" * 64}
        inputs = {"sha256": "4" * 64, "value": {"attemptID": request["attemptID"], "sourceSHA": request["sourceSHA"]}}
        case = {"kind": "widgetFamilies", "finished": False, "identity": reader.request_identity(request), "roots": roots,
                "initial": initial, "inputs": inputs, "admittedAt": (now + 4) * 1000,
                "armed": {"at": (now + 7) * 1000, "gallery": reader.require_gallery(request, (now + 4) * 1000)},
                "addWidgetTappedAt": request["addWidgetTappedAt"],
                "rotations": copy.deepcopy(request["rotations"]), "rotationArtifacts": [],
                "lastObservedAt": (now + 20) * 1000, "extension": extension}
        final, terminal, current_inputs = copy.deepcopy(current), copy.deepcopy(roots), copy.deepcopy(inputs)
        if change_request: change_request(request)
        if change_final: change_final(final)
        if change_roots: change_roots(terminal)
        if change_inputs: change_inputs(current_inputs)
        with tempfile.TemporaryDirectory() as folder, ExitStack() as context:
            directory = Path(folder) / request["runID"]; directory.mkdir()
            evidence = Path(folder) / "evidence"; target = evidence / request["runID"]; target.mkdir(parents=True)
            (target / "widget-family-restored.png").write_bytes(png_header(1536, 2048))
            case["directory"] = str(directory)
            context.enter_context(patch.object(reader.original, "product_roots", side_effect=[roots, roots, terminal]))
            context.enter_context(patch.object(reader.original, "widget_extension_executable", return_value={} if change_extension else extension))
            context.enter_context(patch.object(reader, "read_native", side_effect=[current, final]))
            context.enter_context(patch.object(reader, "load_inputs", return_value=current_inputs))
            code_check = context.enter_context(patch.object(reader.widget, "current_code"))
            context.enter_context(patch.object(reader.widget, "retain_ui_artifacts", return_value={}))
            output = context.enter_context(patch.object(reader.widget, "retain_response"))
            args = type("Args", (), {"device": "pure-control", "bundle_id": "com.itorah.hanlinminiapps"})()
            try: reader.observe_case(args, request, directory, evidence, {request["runID"]: case}, {})
            except Error:
                self.assertFalse(case["finished"]); output.assert_not_called(); raise
            self.assertTrue(case["finished"]); code_check.assert_called_once()
            self.assertEqual(output.call_args.args[-1]["status"], "EXECUTED_PASS")

    def test_final_source_attempt_MCM_and_extension_substitution_never_writes_completion(self):
        self.finish_control()
        for key in reader.widget.ROOT_FIELDS:
            with self.subTest(root=key), self.assertRaises(Error):
                self.finish_control(change_roots=lambda row, key=key: row.update({key: "replacement"}))
        with self.assertRaises(Error): self.finish_control(change_inputs=lambda row: row.update(sha256="changed"))
        with self.assertRaises(Error): self.finish_control(change_extension=True)
        with self.assertRaises(Error): self.finish_control(change_request=lambda row: row.update(attemptID=str(uuid.uuid4())))

    def test_final_native_reread_and_frozen_rotation_history_are_required(self):
        for change in [lambda row: row["state"].update(revision=1), lambda row: row.update(otherStatesSHA256="changed"),
                       lambda row: row["cache"]["record"].update(family="systemSmall"),
                       lambda row: row["identity"].update(variantID=str(uuid.uuid4()))]:
            with self.assertRaises(Error): self.finish_control(change_final=change)
        with self.assertRaises(Error): self.finish_control(change_request=lambda row: row["rotations"][0].update(widgetFrame=[0, 0, 1, 1]))
        with self.assertRaises(Error): self.finish_control(change_request=lambda row: row.update(cleanupFailure="actual removal failed"))

    def test_post_arm_pre_add_render_and_rewritten_add_time_cannot_qualify(self):
        request, initial, current, now = fixture()
        request["phase"] = "widget-family-placed"
        request["rotations"] = request["rotations"][:1]
        roots = {key: Path("/pure-control") / key for key in reader.widget.ROOT_FIELDS}
        case = {"kind": "widgetFamilies", "finished": False, "identity": reader.request_identity(request),
                "roots": roots, "initial": initial,
                "inputs": {"value": {"attemptID": request["attemptID"], "sourceSHA": request["sourceSHA"]}},
                "admittedAt": (now + 4) * 1000,
                "armed": {"at": (now + 7) * 1000, "gallery": reader.require_gallery(request, (now + 4) * 1000)},
                "addWidgetTappedAt": None, "rotations": [], "rotationArtifacts": []}
        with tempfile.TemporaryDirectory() as folder, ExitStack() as context:
            directory = Path(folder) / request["runID"]; directory.mkdir()
            evidence = Path(folder) / "evidence"; (evidence / request["runID"]).mkdir(parents=True)
            case["directory"] = str(directory)
            context.enter_context(patch.object(reader.original, "product_roots", return_value=roots))
            context.enter_context(patch.object(reader, "read_native", return_value=current))
            artifacts = context.enter_context(patch.object(reader, "retain_rotation", return_value={"screenshotPixels": [1536, 2048]}))
            output = context.enter_context(patch.object(reader.widget, "retain_response"))
            args = type("Args", (), {"device": "pure-control", "bundle_id": "com.itorah.hanlinminiapps"})()
            current["cache"]["record"]["renderedAt"] = (now + 7.5) * 1000
            reader.observe_case(args, request, directory, evidence, {request["runID"]: case}, {})
            self.assertEqual(case["addWidgetTappedAt"], request["addWidgetTappedAt"])
            self.assertEqual(case["rotations"], [])
            artifacts.assert_not_called(); output.assert_not_called()
            current["cache"]["record"]["renderedAt"] = (now + 8.5) * 1000
            reader.observe_case(args, request, directory, evidence, {request["runID"]: case}, {})
            self.assertEqual(len(case["rotations"]), 1)
            self.assertEqual(output.call_args.args[-1]["status"], "READY")
            output.reset_mock()
            request["addWidgetTappedAt"] = stamp(now + 8.1)
            with self.assertRaisesRegex(Error, "timestamp changed"):
                reader.observe_case(args, request, directory, evidence, {request["runID"]: case}, {})
            output.assert_not_called()
        with self.assertRaisesRegex(Error, "post-placement family render"):
            self.finish_control(change_final=lambda row: row["cache"]["record"].update(
                renderedAt=row["cache"]["record"]["renderedAt"] - 1000))
        with self.assertRaisesRegex(Error, "timestamp changed"):
            self.finish_control(change_request=lambda row: row.update(addWidgetTappedAt=stamp(
                reader.original._epoch_milliseconds(row["addWidgetTappedAt"]) / 1000 + 0.001)))


if __name__ == "__main__":
    unittest.main()
