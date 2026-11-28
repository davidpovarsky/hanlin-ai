"""Portable rejection controls for actual-evidence admission, never OS receipts."""
import copy
import datetime
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "ProductSplit"))
import observe_widget_layout as reader

Error = reader.original.ObservationError


def stamp(value):
    return datetime.datetime.fromtimestamp(value, datetime.timezone.utc).isoformat(timespec="milliseconds")


def fixture():
    # Synthetic inputs exercise the parser only. No AX/PNG/native receipt is
    # generated, exported, or attributed to Simulator by these controls.
    now = time.time() - 600
    run = str(uuid.uuid4())
    request = {"schema": 1, "surface": "widgetLayout", "engine": "expo", "runID": run,
               "fixtureTitle": "Interactive Widget Matrix", "expectedFamily": "systemMedium", "sizeLabel": "Medium",
               "instanceName": "Layout-systemMedium-" + run, "priorOrientation": "portrait",
               "startedAt": stamp(now), "test": "-[HanlinEntrypointSystemSurfaceUITests "
                    + "testMiniAppsMediumWidgetNativeControlsStayVisibleAcrossStateAndRotation]",
               "attemptID": str(uuid.uuid4()), "sourceSHA": "1" * 40, "hostTerminated": True,
               "unboundPlacementCreated": False, "addWidgetTappedAt": stamp(now + 5)}
    request["prePlacement"] = {"visibleMatrixCount": 0, "visiblePlaceholderCount": 0,
        "screenFrame": [0, 0, 768, 1024], "orientation": "portrait", "at": stamp(now + 2), "uptime": 1002}
    request["galleryPages"] = [{"index": 0, "selected": True, "observedAt": stamp(now + 3), "uptime": 1003,
        "attachmentLabel": "widget-family-gallery-0", "rows": [
            {"label": "Hanlin Script", "value": "", "frame": [10, 10, 200, 30]},
            {"label": "Medium", "value": "", "frame": [10, 40, 200, 30]}]}]
    identity = {"installedPackageID": str(uuid.uuid4()), "packageID": "matrix", "generation": 1,
                "entrypointID": "widget", "variantID": str(uuid.uuid4())}
    initial = {"identity": identity, "instance": {"displayName": request["instanceName"], "settings": {}},
               "installedRecord": {"sourceDigest": "a" * 64, "activeGeneration": 1},
               "state": {"revision": 0, "values": {}, "committedNonces": []}, "values": {},
               "program": {"sha256": "b" * 64}, "catalog": {"sha256": "c" * 64},
               "otherStatesSHA256": "d" * 64, "cache": None}
    nonces = [str(uuid.uuid4()) for _ in range(3)]
    facts = []
    rows = []
    # Explicit expectations from the unchanged Matrix: Toggle also increments
    # count; Add increments again; Refresh commits a new nonce without a value edit.
    plan = [("portrait", 0, False, 0), ("portrait", 1, True, 1), ("portrait", 2, True, 2),
            ("portrait", 2, True, 3), ("landscapeLeft", 2, True, 3), ("portrait", 2, True, 3)]
    for index, (orientation, count, enabled, revision) in enumerate(plan):
        current = copy.deepcopy(initial)
        values = {} if revision == 0 else {"count": float(count), "enabled": enabled}
        current["values"] = values
        current["state"] = {"revision": revision, "values": values, "committedNonces": nonces[:revision]}
        rendered = now + (6.5 if index == 0 else 5.5 + 10 * min(index, 3))
        current["cache"] = {"record": {"identity": identity, "engine": "expo", "family": "systemMedium",
            "programSHA256": "b" * 64, "settings": {}, "renderSHA256": "e" * 64, "renderedAt": rendered * 1000},
            "artifact": {"sha256": "e" * 64}, "node": ["Matrix count: " + str(count),
                {"type": "ToggleView", "props": {"target": "enabled", "isOn": enabled}}]}
        facts.append(current)
        screen = [0, 0, 1024, 768] if orientation == "landscapeLeft" else [0, 0, 768, 1024]
        bounds = [40, 140 if orientation == "landscapeLeft" else 180, 600, 260]
        x, y = bounds[:2]
        controls = {
            "count": {"kind": "staticText", "label": "Matrix count: " + str(count), "value": "",
                      "frame": [x + 20, y + 15, 300, 30]},
            "toggle": {"kind": "switch", "label": "Widget notifications", "value": "1" if enabled else "0",
                       "frame": [x + 20, y + 65, 300, 48]},
            "add": {"kind": "button", "label": "Add", "value": "", "frame": [x + 20, y + 140, 190, 48]},
            "refresh": {"kind": "button", "label": "Refresh", "value": "", "frame": [x + 240, y + 140, 190, 48]},
        }
        for control in controls.values():
            control.update(exists=True, hittable=True, enabled=True)
        start = 6 + 10 * index
        configuration = {"instanceName": request["instanceName"], "label": request["instanceName"], "value": "",
            "frame": bounds, "verifiedAt": stamp(now + start + 1), "verifiedUptime": 1000 + start + 1,
            "attachmentLabel": "widget-layout-configuration-" + str(index)}
        rows.append({"index": index, "requestedOrientation": orientation, "orientation": orientation,
            "requestedAt": stamp(now + start), "requestedUptime": 1000 + start,
            "capturedAt": stamp(now + start + 2), "capturedUptime": 1000 + start + 2,
            "visibleMatrixCount": 1, "hostTerminated": True, "screenFrame": screen, "widgetFrame": bounds,
            "window": {"owner": "com.apple.springboard", "kind": "window", "matchingWindowCount": 1,
                       "identifier": "parser-control-window", "exists": True, "hittable": True, "frame": screen},
            "controls": controls, "configuration": configuration, "attachmentLabel": "widget-layout-observation-" + str(index)})
    steps = [{"index": 1, "actionID": str(uuid.uuid4()), "action": "toggle", "desiredValue": True},
             {"index": 2, "actionID": str(uuid.uuid4()), "action": "add", "desiredValue": None},
             {"index": 3, "actionID": str(uuid.uuid4()), "action": "refresh", "desiredValue": None}]
    request["observations"] = rows
    request["completedActionIDs"] = [step["actionID"] for step in steps]
    return request, initial, facts, steps, now


def case_for(request, initial, facts, now, directory):
    roots = {key: "parser-control-" + key for key in reader.widget.ROOT_FIELDS}
    inputs = {"value": {"attemptID": request["attemptID"], "sourceSHA": request["sourceSHA"]}, "sha256": "f" * 64}
    case = {"kind": "widgetLayout", "finished": False, "identity": reader.request_identity(request),
            "directory": str(directory), "roots": roots, "initial": initial, "previous": facts[0], "inputs": inputs,
            "admittedAt": (now + 1) * 1000, "placement": {"at": (now + 4) * 1000,
                "gallery": reader.family.require_gallery(request, (now + 1) * 1000)},
            "addWidgetTappedAt": request["addWidgetTappedAt"], "observations": [request["observations"][0]],
            "actions": [], "armedAction": None, "lastObservedAt": (now + 9) * 1000}
    return roots, case


class WidgetLayoutEvidenceControls(unittest.TestCase):
    def test_complete_medium_action_and_rotation_evidence_is_admitted(self):
        request, initial, facts, steps, now = fixture()
        reader.request_identity(request)
        previous = initial
        for index, current in enumerate(facts):
            reader.require_variant(current, initial)
            reader.require_observation(request["observations"][index], request, current, index,
                                       (now + 5 + 10 * index) * 1000,
                                       request["observations"][index - 1] if index else None)
            if 1 <= index <= 3:
                self.assertEqual(reader.require_transition(previous, current, steps[index - 1]),
                                 current["state"]["committedNonces"][-1])
            previous = current
        self.assertEqual(reader.widget.count_and_value(facts[-1]), (2, True))
        self.assertEqual(facts[-1]["state"]["revision"], 3)

    def test_wrong_family_selector_variant_or_future_start_is_rejected(self):
        request, _, _, _, _ = fixture()
        for key, value in [("expectedFamily", "systemSmall"), ("sizeLabel", "Large"), ("schema", True),
                           ("instanceName", "old-instance"), ("priorOrientation", "unknown"),
                           ("test", "testAnotherMethod]"), ("startedAt", stamp(time.time() + 60))]:
            changed = copy.deepcopy(request); changed[key] = value
            with self.subTest(key=key), self.assertRaises(Error):
                reader.request_identity(changed)

    def test_source_attempt_and_actual_container_changes_are_rejected(self):
        request, initial, facts, _, now = fixture()
        roots, case = case_for(request, initial, facts, now, Path("/parser-control"))
        for field in ("sourceSHA", "attemptID"):
            changed = copy.deepcopy(request); changed[field] = "different"
            with self.subTest(field=field), self.assertRaises(Error):
                reader.require_attempt(changed, reader.request_identity(changed), Path(case["directory"]), roots, case)
        for field in reader.widget.ROOT_FIELDS:
            changed = dict(roots); changed[field] = "another-current-container"
            with self.subTest(field=field), self.assertRaises(Error):
                reader.require_attempt(request, case["identity"], Path(case["directory"]), changed, case)
        with self.assertRaises(Error):
            reader.require_attempt(request, case["identity"], Path("/another-exchange"), roots, case)

    def test_original_producer_fixture_manifest_and_current_source_must_match(self):
        request, _, _, _, _ = fixture()
        class Args:
            device = "parser-simulator"
            runner_bundle_id = "parser.runner.xctrunner"
        with tempfile.TemporaryDirectory() as temp:
            evidence = Path(temp) / "observer"; evidence.mkdir()
            Args.widget_layout_inputs = evidence.parent / "widget-layout-inputs.json"
            archive = {"archiveSHA256": "a" * 64, "sourceSHA256": "b" * 64}
            value = {"schema": 1, "kind": "widget-layout-inputs", "attemptID": request["attemptID"],
                "sourceSHA": request["sourceSHA"], "createdAt": time.time() - 10, "device": Args.device,
                "runnerBundleIdentifier": Args.runner_bundle_id, "sourceFiles": {"source": "current"},
                "fixture": {"status": "STAGED_INPUT_ONLY", **archive}}
            with patch.object(reader.original, "read_document", return_value={"value": value}), \
                 patch.object(reader, "source_identity", return_value={"source": "current"}):
                reader.load_inputs(Args, evidence, archive)
                for field in ("archiveSHA256", "sourceSHA256"):
                    changed = {**archive, field: "0" * 64}
                    with self.subTest(field=field), self.assertRaises(Error):
                        reader.load_inputs(Args, evidence, changed)
                value["sourceFiles"] = {"source": "foreign"}
                with self.assertRaises(Error): reader.load_inputs(Args, evidence, archive)

    def test_other_instance_program_generation_or_settings_changes_are_rejected(self):
        _, initial, facts, _, _ = fixture()
        mutations = [lambda x: x["identity"].update(variantID=str(uuid.uuid4())),
                     lambda x: x["identity"].update(generation=2),
                     lambda x: x["instance"].update(settings={"changed": True}),
                     lambda x: x["installedRecord"].update(sourceDigest="0" * 64),
                     lambda x: x["program"].update(sha256="0" * 64),
                     lambda x: x["catalog"].update(sha256="0" * 64),
                     lambda x: x.update(otherStatesSHA256="0" * 64)]
        for mutate in mutations:
            changed = copy.deepcopy(facts[1]); mutate(changed)
            with self.assertRaises(Error): reader.require_variant(changed, initial)

    def test_missing_hidden_disabled_or_wrong_valued_controls_cannot_qualify(self):
        request, _, facts, _, _ = fixture()
        row = request["observations"][1]
        mutations = [lambda x: x["controls"].pop("refresh"),
                     lambda x: x["controls"]["toggle"].update(value="0"),
                     lambda x: x["controls"]["count"].update(label="Matrix count: 0"),
                     lambda x: x["controls"]["add"].update(enabled=False),
                     lambda x: x["controls"]["refresh"].update(hittable=False),
                     lambda x: x["controls"]["toggle"].update(exists=False),
                     lambda x: x.update(visibleMatrixCount=2),
                     lambda x: x.update(hostTerminated=False)]
        for mutate in mutations:
            changed = copy.deepcopy(row); mutate(changed)
            with self.assertRaises(Error): reader.require_controls(changed, facts[1])

    def test_wrong_window_owner_ambiguity_or_noncontaining_window_is_rejected(self):
        request, _, facts, _, _ = fixture()
        for key, value in [("owner", "com.itorah.hanlinminiapps"), ("kind", "other"),
                           ("matchingWindowCount", 2), ("matchingWindowCount", True), ("hittable", False),
                           ("frame", [700, 0, 50, 1024]), ("frame", [0, 0, 900, 1200])]:
            row = copy.deepcopy(request["observations"][0]); row["window"][key] = value
            with self.subTest(key=key), self.assertRaises(Error):
                reader.require_controls(row, facts[0])

    def test_clipped_nonfinite_or_zero_area_control_frames_are_rejected(self):
        request, _, facts, _, _ = fixture()
        for bad in ([39, 195, 300, 30], [60, 195, 700, 30], [60, 195, 300, 300],
                    [60, 195, 0, 30], [True, 195, 300, 30], [float("nan"), 195, 300, 30]):
            row = copy.deepcopy(request["observations"][0]); row["controls"]["count"]["frame"] = bad
            with self.subTest(frame=bad), self.assertRaises(Error): reader.require_controls(row, facts[0])
        row = copy.deepcopy(request["observations"][0]); row["widgetFrame"] = [-1, 180, 600, 260]
        with self.assertRaises(Error): reader.require_controls(row, facts[0])

    def test_pairwise_control_overlap_is_rejected_even_inside_the_widget(self):
        request, _, facts, _, _ = fixture()
        for a, b in (("count", "toggle"), ("add", "refresh"), ("toggle", "add")):
            row = copy.deepcopy(request["observations"][0])
            row["controls"][a]["frame"] = list(row["controls"][b]["frame"])
            with self.subTest(pair=(a, b)), self.assertRaises(Error):
                reader.require_controls(row, facts[0])

    def test_layout_requires_fresh_named_configuration_and_ordered_wall_and_monotonic_times(self):
        request, _, facts, _, now = fixture()
        row = request["observations"][1]
        mutations = [lambda x: x["configuration"].update(instanceName="another"),
                     lambda x: x["configuration"].update(label="previous", value=""),
                     lambda x: x["configuration"].update(verifiedAt=stamp(now + 12)),
                     lambda x: x["configuration"].update(verifiedUptime=1000),
                     lambda x: x.update(capturedAt=stamp(now + 16)),
                     lambda x: x.update(capturedUptime=1016),
                     lambda x: x.update(requestedAt=stamp(time.time() + 10)),
                     lambda x: x.update(index=True)]
        for mutate in mutations:
            changed = copy.deepcopy(row); mutate(changed)
            with self.assertRaises(Error):
                reader.require_observation(changed, request, facts[1], 1, (now + 15) * 1000,
                                           request["observations"][0])

    def test_assigning_rotation_without_actual_changed_geometry_cannot_pass(self):
        request, _, facts, _, now = fixture()
        row = copy.deepcopy(request["observations"][4])
        row["screenFrame"] = [0, 0, 768, 1024]
        row["window"]["frame"] = list(row["screenFrame"])
        with self.assertRaises(Error):
            reader.require_observation(row, request, facts[4], 4, (now + 45) * 1000, request["observations"][3])
        row = copy.deepcopy(request["observations"][4]); row["screenFrame"] = [0, 0, 1100, 800]
        with self.assertRaises(Error):
            reader.require_observation(row, request, facts[4], 4, (now + 45) * 1000, request["observations"][3])

    def test_missing_revision_nonce_or_actual_refresh_commit_is_rejected(self):
        _, _, facts, steps, _ = fixture()
        for index in (1, 2, 3):
            before, after = facts[index - 1], facts[index]
            for mutation in ("no_revision", "no_nonce", "malformed_nonce", "extra_nonce"):
                current = copy.deepcopy(after)
                if mutation == "no_revision": current["state"]["revision"] = before["state"]["revision"]
                if mutation == "no_nonce": current["state"]["committedNonces"] = list(before["state"]["committedNonces"])
                if mutation == "malformed_nonce": current["state"]["committedNonces"][-1] = "not-a-uuid"
                if mutation == "extra_nonce": current["state"]["committedNonces"].append(str(uuid.uuid4()))
                rejection = ValueError if mutation == "malformed_nonce" else Error
                with self.subTest(index=index, mutation=mutation), self.assertRaises(rejection):
                    reader.require_transition(before, current, steps[index - 1])
            if index > 1:
                replay = copy.deepcopy(after)
                replay["state"]["committedNonces"][-1] = before["state"]["committedNonces"][-1]
                with self.assertRaises(Error):
                    reader.require_transition(before, replay, steps[index - 1])
        unchanged_refresh = copy.deepcopy(facts[2])
        with self.assertRaises(Error): reader.require_transition(facts[2], unchanged_refresh, steps[2])

    def test_native_uuid_letter_case_is_preserved_but_case_equivalent_replay_is_rejected(self):
        _, initial, facts, steps, _ = fixture()
        first = copy.deepcopy(facts[1])
        first["state"]["committedNonces"][-1] = first["state"]["committedNonces"][-1].upper()
        self.assertEqual(reader.require_transition(initial, first, steps[0]),
                         first["state"]["committedNonces"][-1])
        second = copy.deepcopy(facts[2])
        second["state"]["committedNonces"][0] = first["state"]["committedNonces"][0]
        second["state"]["committedNonces"][-1] = second["state"]["committedNonces"][-1].upper()
        self.assertEqual(reader.require_transition(first, second, steps[1]),
                         second["state"]["committedNonces"][-1])
        second["state"]["committedNonces"][-1] = first["state"]["committedNonces"][0].lower()
        with self.assertRaises(Error): reader.require_transition(first, second, steps[1])

    def test_original_toggle_add_and_refresh_value_semantics_cannot_be_replaced(self):
        _, initial, facts, steps, _ = fixture()
        for index, before in ((1, initial), (2, facts[1]), (3, facts[2])):
            current = copy.deepcopy(facts[index])
            current["values"]["count"] = 100.0
            with self.subTest(index=index), self.assertRaises(Error):
                reader.require_transition(before, current, steps[index - 1])
        changed = copy.deepcopy(facts[1]); changed["values"]["enabled"] = 1
        with self.assertRaises(Error): reader.require_transition(initial, changed, steps[0])
        step = {**steps[0], "desiredValue": False}
        with self.assertRaises(Error): reader.require_transition(initial, facts[1], step)

    def test_invalid_or_out_of_order_action_identity_is_rejected(self):
        _, _, _, steps, _ = fixture()
        for key, value in [("index", True), ("index", 2), ("actionID", "replay"), ("action", "refresh")]:
            step = {**steps[0], key: value}
            rejection = ValueError if key == "actionID" else Error
            with self.subTest(key=key), self.assertRaises(rejection): reader.require_step(step, 1)
        with self.assertRaises(Error): reader.require_step(steps[0], 4)

    def test_actual_placement_time_is_frozen_and_preplacement_render_cannot_qualify(self):
        request, initial, facts, _, now = fixture()
        _, case = case_for(request, initial, facts, now, Path("/parser-control"))
        case["addWidgetTappedAt"] = None; case["observations"] = []
        self.assertAlmostEqual(reader.freeze_placement(request, case, "widget-layout-placed"), (now + 5) * 1000,
                         delta=1)
        changed = copy.deepcopy(request); changed["addWidgetTappedAt"] = stamp(now + 5.5)
        with self.assertRaises(Error): reader.freeze_placement(changed, case, "widget-layout-placed")
        old = copy.deepcopy(facts[0]); old["cache"]["record"]["renderedAt"] = (now + 4.5) * 1000
        self.assertFalse(reader.family.fresh_family_cache(old, "systemMedium", (now + 5) * 1000))
        stale = copy.deepcopy(facts[1]); stale["cache"]["record"]["renderedAt"] = (now + 13.5) * 1000
        self.assertFalse(reader.family.fresh_family_cache(stale, "systemMedium", (now + 14) * 1000))

    def test_pending_native_action_has_no_acknowledgment_and_tap_interval_cannot_be_rewritten(self):
        request, initial, facts, steps, now = fixture()
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp) / "exchange"
            evidence = Path(temp) / "evidence"
            roots, case = case_for(request, initial, facts, now, directory)
            request["phase"] = "widget-layout-applied"
            request["observations"] = request["observations"][:2]
            request["step"] = steps[0]
            request["tap"] = {"actionID": steps[0]["actionID"], "beganAt": stamp(now + 14),
                              "beganUptime": 1014, "returnedAt": stamp(now + 15), "returnedUptime": 1015}
            case["armedAction"] = {"admission": {"step": steps[0]}, "before": facts[0], "at": (now + 13) * 1000}
            with patch.object(reader.original, "product_roots", return_value=roots), \
                 patch.object(reader.family, "read_native", return_value=facts[0]), \
                 patch.object(reader.widget, "retain_response") as reply:
                reader.observe_case(type("Args", (), {"device": "parser", "bundle_id": "parser"}), request,
                                    directory, evidence, {request["runID"]: case}, {})
                reply.assert_not_called()
                self.assertEqual(len(case["observations"]), 1)
                self.assertEqual(case["actions"], [])
                request["tap"]["returnedAt"] = stamp(now + 15.5)
                with self.assertRaises(Error):
                    reader.observe_case(type("Args", (), {"device": "parser", "bundle_id": "parser"}), request,
                                        directory, evidence, {request["runID"]: case}, {})

    def test_completion_cannot_omit_actions_rotations_or_leave_an_action_pending(self):
        request, initial, facts, steps, now = fixture()
        request["phase"] = "widget-layout-complete"
        with tempfile.TemporaryDirectory() as temp:
            directory, evidence = Path(temp) / "exchange", Path(temp) / "evidence"
            roots, complete = case_for(request, initial, facts, now, directory)
            complete.update(previous=facts[-1], observations=request["observations"],
                            actions=[{"step": step} for step in steps], lastObservedAt=(now + 59) * 1000)
            for missing in ("action", "rotation", "pending"):
                case = copy.deepcopy(complete)
                if missing == "action": case["actions"].pop()
                if missing == "rotation": case["observations"].pop()
                if missing == "pending": case["armedAction"] = {"pending": True}
                with patch.object(reader.original, "product_roots", return_value=roots), \
                     patch.object(reader.family, "read_native", return_value=facts[-1]), \
                     patch.object(reader.widget, "retain_response") as reply, self.subTest(missing=missing), self.assertRaises(Error):
                    reader.observe_case(type("Args", (), {"device": "parser", "bundle_id": "parser"}), request,
                                        directory, evidence, {request["runID"]: case}, {})
                reply.assert_not_called()


if __name__ == "__main__":
    unittest.main()
