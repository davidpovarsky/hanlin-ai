"""Pure evidence controls only: these fixtures are never system acceptance proof."""
from contextlib import ExitStack
import copy
import datetime
import json
from pathlib import Path
import plistlib
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "ProductSplit"))
import observe_widget_state as reader

Error = reader.original.ObservationError


def stamp(value):
    return datetime.datetime.fromtimestamp(value, datetime.timezone.utc).isoformat()


def request_fixture():
    run_id = str(uuid.uuid4())
    return {"schema": 1, "runID": run_id, "surface": "widgetState", "engine": "expo",
            "fixtureTitle": "Interactive Widget Matrix", "expectedFamily": "systemMedium",
            "instanceNames": {key: "State-" + key + "-" + run_id for key in ("A", "B")},
            "startedAt": stamp(time.time() - 60),
            "test": "-[HanlinEntrypointSystemSurfaceUITests testMiniAppsPlacedWidgetToggleKeepsIndependentInstanceState]",
            "attemptID": str(uuid.uuid4()), "sourceSHA": "a" * 40, "hostTerminated": True}


def refresh_facts(pair):
    for key, facts in pair.items():
        other = "B" if key == "A" else "A"
        facts["otherStatesSHA256"] = reader.original.digest(json.dumps(pair[other]["state"], sort_keys=True).encode())
        count, enabled = reader.count_and_value(facts)
        facts["cache"] = {"record": {"renderedAt": time.time() * 1000, "family": "systemMedium"},
                          "node": {"type": "VStack", "children": [
                              {"type": "Text", "props": {"text": "Matrix count: " + str(count)}},
                              {"type": "ToggleView", "props": {"target": "enabled", "isOn": enabled}}]}}
    return pair


def pair_fixture(request):
    pair = {}
    for key in ("A", "B"):
        identity = {"installedPackageID": "installation", "packageID": "matrix", "generation": 2,
                    "entrypointID": "widget", "variantID": str(uuid.uuid4())}
        pair[key] = {"identity": identity, "instance": {"identity": identity, "settings": {},
                     "displayName": request["instanceNames"][key]}, "program": {"sha256": "b" * 64},
                     "installedRecord": {"sourceDigest": "c" * 64, "activeGeneration": 2},
                     "state": {"revision": 0, "committedNonces": [], "values": {}},
                     "values": {}, "snapshotSHA256": "d" * 64}
    return refresh_facts(pair)


def changed_pair(before, target, count, enabled):
    result = copy.deepcopy(before)
    row = result[target]
    row["values"] = {"count": float(count), "enabled": enabled}
    row["state"]["revision"] += 1
    row["state"]["values"] = copy.deepcopy(row["values"])
    row["state"]["committedNonces"].append(str(uuid.uuid4()).upper())
    return refresh_facts(result)


def step(index, target, action, desired=None):
    return {"index": index, "actionID": str(uuid.uuid4()), "instance": target,
            "action": action, "desiredValue": desired}


def ui_fixture(pair):
    rows = {}
    for index, key in enumerate(("A", "B")):
        count, enabled = reader.count_and_value(pair[key])
        y = index * 200
        rows[key] = {"count": count, "switchValue": "1" if enabled else "0",
                     "switchEnabled": True, "switchHittable": True, "addHittable": True,
                     "refreshHittable": True, "frame": [0, y, 300, 160],
                     "switchFrame": [10, y + 30, 80, 30], "addFrame": [10, y + 90, 60, 30],
                     "refreshFrame": [100, y + 90, 80, 30]}
    return rows


def attach_bindings(request, pair):
    request["ui"] = ui_fixture(pair)
    request["configurationBindings"] = {key: {
        "instanceName": request["instanceNames"][key], "count": request["ui"][key]["count"],
        "label": "Interactive Widget Matrix · expo · " + request["instanceNames"][key], "value": "",
        "frame": request["ui"][key]["frame"], "verifiedAt": stamp(time.time() - 1),
    } for key in ("A", "B")}
    return request


def six_steps(request):
    pair = pair_fixture(request)
    initial = copy.deepcopy(pair)
    rows = []
    # Explicit expected outcomes of the authored fixture; not read from STEPS.
    plan = [("A", "toggle", True, 1, True), ("A", "toggle", False, 2, False),
            ("A", "add", None, 3, False), ("B", "toggle", True, 1, True),
            ("B", "toggle", False, 2, False), ("B", "refresh", None, 2, False)]
    for index, (key, action, desired, count, enabled) in enumerate(plan, 1):
        after = changed_pair(pair, key, count, enabled)
        action_record = step(index, key, action, desired)
        nonce = reader.require_transition(pair, after, action_record)
        rows.append({"step": action_record, "nativeNonce": nonce, "observedAt": (time.time() - 5) * 1000})
        pair = after
    return initial, pair, rows


class WidgetStateEvidenceControls(unittest.TestCase):
    def test_six_sequential_boolean_add_refresh_outcomes_and_other_instance(self):
        request = request_fixture()
        _, final, rows = six_steps(request)
        self.assertEqual(len({row["nativeNonce"] for row in rows}), 6)
        self.assertEqual(reader.count_and_value(final["A"]), (3, False))
        self.assertEqual(reader.count_and_value(final["B"]), (2, False))
        self.assertEqual(final["B"]["state"]["revision"], 3)

    def test_consistently_coerced_boolean_cannot_self_validate(self):
        before = pair_fixture(request_fixture())
        after = changed_pair(before, "A", 1, True)
        for desired, actual in [(1, 1), (True, 1), (1, True)]:
            with self.subTest(desired=desired, actual=actual):
                changed = copy.deepcopy(after)
                changed["A"]["values"]["enabled"] = actual
                with self.assertRaises(Error):
                    reader.require_transition(before, changed, step(1, "A", "toggle", desired))

    def test_untouched_instance_state_and_other_namespace_cannot_change(self):
        before = pair_fixture(request_fixture())
        valid = changed_pair(before, "A", 1, True)
        for field in ("state", "otherStatesSHA256"):
            changed = copy.deepcopy(valid)
            if field == "state":
                changed["B"]["state"]["revision"] += 1
            else:
                changed["A"][field] = "changed-other-state"
            with self.subTest(field=field), self.assertRaises(Error):
                reader.require_transition(before, changed, step(1, "A", "toggle", True))

    def test_current_variant_generation_program_and_settings_are_required(self):
        before = pair_fixture(request_fixture())
        for key, field, subkey, replacement in [
            ("A", "identity", "variantID", str(uuid.uuid4())),
            ("B", "identity", "generation", 3), ("A", "program", "sha256", "e" * 64),
            ("B", "instance", "settings", {"changed": True})]:
            changed = copy.deepcopy(before)
            changed[key][field][subkey] = replacement
            with self.subTest(key=key, field=field), self.assertRaises(Error):
                reader.require_same_variants(changed, before)

    def test_duplicate_or_cross_instance_nonce_cannot_count_as_one_tap(self):
        request = request_fixture()
        before = pair_fixture(request)
        before["B"]["state"]["committedNonces"] = [str(uuid.uuid4()).upper()]
        refresh_facts(before)
        valid = changed_pair(before, "A", 1, True)
        repeated = copy.deepcopy(valid)
        repeated["A"]["state"]["committedNonces"] = [before["B"]["state"]["committedNonces"][0].lower()]
        duplicated = copy.deepcopy(valid)
        duplicated["A"]["state"]["revision"] += 1
        duplicated["A"]["state"]["committedNonces"].append(str(uuid.uuid4()))
        for changed in (repeated, duplicated):
            with self.subTest(state=changed["A"]["state"]), self.assertRaises(Error):
                reader.require_transition(before, changed, step(1, "A", "toggle", True))

    def test_refresh_must_keep_values_and_append_its_own_native_invocation(self):
        _, before, _ = six_steps(request_fixture())
        after = changed_pair(before, "B", 3, False)
        with self.assertRaises(Error):
            reader.require_transition(before, after, step(6, "B", "refresh"))
        unchanged = copy.deepcopy(before)
        with self.assertRaises(Error):
            reader.require_transition(before, unchanged, step(6, "B", "refresh"))

    def test_cache_requires_current_boolean_and_fresh_real_render(self):
        facts = pair_fixture(request_fixture())["A"]
        start = facts["cache"]["record"]["renderedAt"]
        self.assertTrue(reader.cache_matches(facts, start))
        self.assertFalse(reader.cache_matches(facts, start + 1))
        facts["cache"]["node"]["children"][1]["props"]["isOn"] = 0
        self.assertFalse(reader.cache_matches(facts))

    def test_zero_counts_are_not_saved_variant_identity(self):
        request = request_fixture()
        pair = pair_fixture(request)
        attach_bindings(request, pair)
        reader.configuration_bindings(request, pair, ["A", "B"], after=0)
        for key in ("A", "B"):
            changed = copy.deepcopy(request)
            del changed["configurationBindings"][key]
            with self.subTest(key=key), self.assertRaises(Error):
                reader.configuration_bindings(changed, pair, ["A", "B"], after=0)

    def test_swapped_physical_selection_or_unrelated_frame_is_rejected(self):
        request = request_fixture()
        pair = pair_fixture(request)
        attach_bindings(request, pair)
        for field, value in [("label", request["instanceNames"]["A"]),
                             ("frame", request["ui"]["A"]["frame"])]:
            changed = copy.deepcopy(request)
            changed["configurationBindings"]["B"][field] = value
            with self.subTest(field=field), self.assertRaises(Error):
                reader.configuration_bindings(changed, pair, ["A", "B"], after=0)

    def test_final_saved_selection_must_be_fresh_for_both_instances(self):
        request = request_fixture()
        _, pair, _ = six_steps(request)
        attach_bindings(request, pair)
        after = (time.time() - 2) * 1000
        reader.configuration_bindings(request, pair, ["A", "B"], after=after)
        request["configurationBindings"]["B"]["verifiedAt"] = stamp(time.time() - 10)
        with self.assertRaises(Error):
            reader.configuration_bindings(request, pair, ["A", "B"], after=after)

    def test_both_containers_and_every_control_must_remain_physically_bound(self):
        pair = pair_fixture(request_fixture())
        ui = ui_fixture(pair)
        reader.require_ui(ui, pair, ["A", "B"])
        for mutation in ("overlap", "outside", "disabled", "coerced_count"):
            changed = copy.deepcopy(ui)
            if mutation == "overlap":
                changed["B"] = copy.deepcopy(changed["A"])
            elif mutation == "outside":
                changed["B"]["switchFrame"][0] = 400
            elif mutation == "disabled":
                changed["A"]["switchEnabled"] = False
            else:
                changed["A"]["count"] = False
            with self.subTest(mutation=mutation), self.assertRaises(Error):
                reader.require_ui(changed, pair, ["A", "B"])

    def test_wrong_scope_and_out_of_range_action_are_rejected(self):
        request = request_fixture()
        for field, value in [("schema", True), ("expectedFamily", "systemLarge"),
                             ("surface", "widgetRecovery"), ("engine", "nativescript")]:
            with self.subTest(field=field), self.assertRaises(Error):
                reader.request_identity({**request, field: value})
        for index in (0, 7, True):
            with self.subTest(index=index), self.assertRaises(Error):
                reader.require_step(step(index, "A", "toggle", True), index)

    def test_exact_xctest_ax_and_png_are_retained_without_following_links(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source, evidence = root / "runner", root / "evidence"
            source.mkdir(); evidence.mkdir()
            (source / "actual-accessibility.txt").write_text("Actual saved name: State-A-fixture")
            (source / "actual.png").write_bytes(b"\x89PNG\r\n\x1a\n" + b"pure-control")
            result = reader.retain_ui_artifacts(source, evidence, "actual", expected_text="State-A-fixture")
            self.assertEqual((evidence / "actual.png").read_bytes(), (source / "actual.png").read_bytes())
            self.assertEqual(result["actual.png"]["bytes"], 20)
            with self.assertRaises(Error):
                reader.retain_ui_artifacts(source, evidence, "actual", expected_text="another-name")
            (source / "actual.png").unlink()
            (source / "actual.png").symlink_to(evidence / "actual.png")
            with self.assertRaises(Error):
                reader.retain_ui_artifacts(source, evidence, "actual")

    def finish_fixture(self, request_change=None, final_pair_change=None, terminal_root_change=None, extension_change=None):
        request = request_fixture()
        initial, pair, steps = six_steps(request)
        attach_bindings(request, pair)
        request["phase"] = "widget-state-complete"
        roots = {"app": Path("/unit-fixture/MiniApps.app"), "data": Path("/unit-fixture/data"),
                 "group": Path("/unit-fixture/group"), "extensions": Path("/unit-fixture/group/HanlinMiniApps/v1"),
                 "configuration": {"StorageNamespace": "HanlinMiniApps/v1"}, "infoSHA256": "1" * 64}
        extension = {"path": "/unit-fixture/MiniApps.app/PlugIns/Widgets.appex/Widgets", "infoSHA256": "2" * 64}
        inputs = {"sha256": "3" * 64, "value": {"attemptID": request["attemptID"], "sourceSHA": request["sourceSHA"]}}
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder) / request["runID"]
            directory.mkdir()
            evidence = Path(folder) / "evidence"
            evidence.mkdir()
            case = {"kind": "widgetState", "finished": False, "identity": reader.request_identity(request),
                    "directory": str(directory), "roots": roots, "extension": extension,
                    "initial": initial, "previous": pair, "inputs": inputs, "steps": steps,
                    "placed": ["A", "B"], "armed": None,
                    "frames": {key: request["ui"][key]["frame"] for key in ("A", "B")}}
            final_pair, terminal_roots = copy.deepcopy(pair), copy.deepcopy(roots)
            if request_change:
                request_change(request)
            if final_pair_change:
                final_pair_change(final_pair)
            if terminal_root_change:
                terminal_root_change(terminal_roots)
            args = type("Args", (), {"device": "owned", "bundle_id": "com.itorah.hanlinminiapps"})()
            with ExitStack() as context:
                context.enter_context(patch.object(reader.original, "product_roots", side_effect=[roots, roots, terminal_roots]))
                context.enter_context(patch.object(reader.original, "widget_extension_executable", return_value=extension_change or extension))
                context.enter_context(patch.object(reader, "read_pair", side_effect=[pair, final_pair]))
                context.enter_context(patch.object(reader, "load_inputs", return_value=inputs))
                context.enter_context(patch.object(reader, "current_code"))
                context.enter_context(patch.object(reader, "retain_configurations", return_value={}))
                response = context.enter_context(patch.object(reader, "retain_response"))
                try:
                    reader.observe_case(args, request, directory, evidence, {request["runID"]: case}, {})
                except Error:
                    self.assertFalse(case["finished"])
                    response.assert_not_called()
                    raise
                self.assertTrue(case["finished"])
                self.assertEqual(response.call_args.args[-1]["status"], "EXECUTED_PASS")

    def test_completion_requires_both_current_identities_and_request_attempt(self):
        self.finish_fixture()
        for change in (
            lambda row: row.update(startedAt=stamp(time.time() - 70)),
            lambda row: row.update(attemptID=str(uuid.uuid4())),
            lambda row: row.update(hostTerminated=False),
        ):
            with self.assertRaises(Error):
                self.finish_fixture(request_change=change)
        with self.assertRaises(Error):
            self.finish_fixture(final_pair_change=lambda pair: pair["B"]["identity"].update(variantID=str(uuid.uuid4())))

    def test_terminal_mcm_and_installed_extension_replacement_never_write_completion(self):
        with self.assertRaises(Error):
            self.finish_fixture(terminal_root_change=lambda roots: roots.update(data=Path("/unit-fixture/reinstalled-data")))
        with self.assertRaises(Error):
            self.finish_fixture(extension_change={"path": "/unit-fixture/replacement-widget", "infoSHA256": "2" * 64})

    def test_installed_test_binary_mutation_is_not_hidden_by_unchanged_bundle_info(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            runner = root / "Runner.app"
            test = runner / "PlugIns/AI_HLYUITests.xctest"
            test.mkdir(parents=True)
            (test / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "AI_HLYUITests", "CFBundleIdentifier": "test.bundle"}))
            (test / "AI_HLYUITests").write_bytes(b"initial-test-code")
            inputs = {"value": {"product": {}, "testRelativePath": "PlugIns/AI_HLYUITests.xctest",
                                "test": reader.bundle_code(test)}}
            args = type("Args", (), {"device": "owned", "runner_bundle_id": "actual.xctrunner"})()
            with patch.object(reader, "product_code", return_value={}), patch.object(reader.original, "os_container", return_value=runner):
                reader.current_code(args, {"app": root}, inputs)
                (test / "AI_HLYUITests").write_bytes(b"changed-test-code")
                with self.assertRaises(Error):
                    reader.current_code(args, {"app": root}, inputs)


if __name__ == "__main__":
    unittest.main()
