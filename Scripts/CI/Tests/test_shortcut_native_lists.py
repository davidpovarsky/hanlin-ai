"""Portable evidence-reader controls; these do not execute Shortcuts or a native app."""
import copy
import importlib.util
import json
from pathlib import Path
import struct
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
# Keep this reader import local to these controls during shared CI discovery.
with patch.object(sys, "path", [str(ROOT / "Scripts/ProductSplit"), *sys.path]), patch.dict(sys.modules):
    import observe_shortcut_native_lists as reader

RUN = "11111111-1111-4111-8111-111111111111"
COMMAND = "22222222-2222-4222-8222-222222222222"
IDENTITY = {"identity": {"installedPackageID": "owned-package", "packageID": "source-package",
                         "generation": 1, "entrypointID": "native-lists-intent", "variantID": "default"}}


def wire(value, forced=None):
    if forced == "number" or type(value) is float:
        return {"type": "number", "value": struct.pack(">d", float(value)).hex()}
    if type(value) is bool:
        return {"type": "bool", "value": value}
    if type(value) is int:
        return {"type": "integer", "value": str(value)}
    if type(value) is str:
        return {"type": "string", "value": value}
    if type(value) is list:
        return {"type": "array", "value": [wire(item) for item in value]}
    if type(value) is dict:
        return {"type": "object", "value": [{"key": key, "value": wire(item)} for key, item in value.items()]}
    raise AssertionError("Unknown test wire value")


def example(kind="integer", step=0):
    values = {"text": ["שלום", "汉字", RUN], "integer": [-7, 0, 42],
              "number": [-1.25, 0.5, 42.125], "boolean": [True, False]}[kind] if step == 0 else []
    labels = {"text": ("Text List", "textItems"), "integer": ("Integer List", "integerItems"),
              "number": ("Number List", "numberItems"), "boolean": ("Boolean List", "booleanItems")}
    raw = [{"label": "Item", "identifier": "", "value": ("1" if item else "0") if type(item) is bool else str(item)}
           for item in values]
    request = {"runID": RUN, "listKind": kind, "step": step,
               "savedShortcutName": "Hanlin-lists-" + kind + "-" + RUN[:8],
               "builtInChain": ["Get Text from Input", "Show Result"],
               "editor": {"inputMode": kind + "List", "label": labels[kind][0], "parameter": labels[kind][1],
                          "savedAndReopened": True, "processRestarted": True, "openWhenRun": False,
                          "values": values, "rowCount": len(values), "rawRows": raw}}
    result = {"schema": 1, "appID": reader.APP_ID, "actionID": reader.ACTION, "values": values,
              "observedTypes": [{"text": "string", "integer": "number", "number": "number", "boolean": "boolean"}[kind]] * len(values),
              "nonce": "actual123-random456", "caller": "actual-host-caller", "windowID": "actual-window",
              "statePath": "/observed/private/state", "executionMode": "headless-action",
              "attached": False, "observedAt": "2026-11-28T08:00:00.100Z"}
    row = {"id": COMMAND, "createdAt": 1795852800050,
           "invocation": {"identity": copy.deepcopy(IDENTITY["identity"]), "entityID": reader.ACTION,
                          "parameters": wire(values), "continueInForeground": False,
                          "delivery": {"schemaVersion": 1, "appID": reader.APP_ID, "source": "shortcuts",
                                       "userGesturePresent": True, "canPresentUI": False}},
           "receipt": {"status": "succeeded", "failure": None, "cancellationRequested": False,
                       "leaseID": None, "leaseExpiresAt": None, "attempt": 1, "value": wire(result)}}
    return request, {COMMAND: {"value": row}}, 1795852800000


class NativeListReaderTests(unittest.TestCase):
    def result(self, kind="integer", step=0):
        request, commands, armed = example(kind, step)
        return reader.terminal_result(request, IDENTITY, set(), commands, armed)

    def test_retained_real_emitted_dictionary_has_four_native_arrays(self):
        document = json.loads((Path(__file__).parent / "fixtures/native_lists_actionsdata.json").read_text())
        self.assertEqual(len(reader.metadata_contract(document)["parameters"]), 9)

    def test_missing_or_scalar_array_metadata_is_rejected(self):
        original = json.loads((Path(__file__).parent / "fixtures/native_lists_actionsdata.json").read_text())
        for mutation in ("missing", "scalar", "wrongPrimitive", "wrongSwitch"):
            document = copy.deepcopy(original)
            action = document["actions"]["HanlinRunMiniAppShortcutIntent"]
            if mutation == "missing":
                action["parameters"].pop()
            elif mutation == "scalar":
                action["parameters"][-1]["valueType"] = {"primitive": {"wrapper": {"typeIdentifier": 1}}}
            elif mutation == "wrongPrimitive":
                action["parameters"][-2]["valueType"]["array"]["wrapper"]["memberValueType"]["primitive"]["wrapper"]["typeIdentifier"] = 2
            else:
                action["actionConfiguration"]["switchStatement"]["wrapper"]["cases"][0]["configuration"]["actionSummary"]["wrapper"]["summaryString"]["parameterIdentifiers"] = ["action", "input"]
            with self.subTest(mutation=mutation), self.assertRaises((ValueError, KeyError)):
                reader.metadata_contract(document)

    def test_all_four_nonempty_and_cleared_empty_results(self):
        for kind in ("text", "integer", "number", "boolean"):
            with self.subTest(kind=kind):
                self.assertEqual(self.result(kind)["invocationID"], COMMAND)
                self.assertEqual(self.result(kind, 1)["result"]["values"], [])

    def test_equal_numeric_value_with_wrong_native_tag_is_rejected(self):
        request, commands, armed = example()
        commands[COMMAND]["value"]["invocation"]["parameters"]["value"][0] = wire(-7, forced="number")
        with self.assertRaises(ValueError):
            reader.terminal_result(request, IDENTITY, set(), commands, armed)

    def test_number_native_mode_cannot_receive_integer_tags(self):
        with self.assertRaises(ValueError):
            reader.native_input(wire([42]), "number", [42.0])

    def test_boolean_is_not_a_number_or_string(self):
        for value in ([1, 0], ["true", "false"]):
            with self.subTest(value=value), self.assertRaises(ValueError):
                reader.native_input(wire(value), "boolean", [True, False])

    def test_order_and_unicode_are_exact(self):
        for values in (["汉字", "שלום", RUN], ["shalom", "汉字", RUN]):
            with self.subTest(values=values), self.assertRaises(ValueError):
                reader.native_input(wire(values), "text", ["שלום", "汉字", RUN])

    def test_cleared_list_cannot_retain_old_values(self):
        request, commands, armed = example(step=1)
        commands[COMMAND]["value"]["invocation"]["parameters"] = wire([-7, 0, 42])
        with self.assertRaises(ValueError):
            reader.terminal_result(request, IDENTITY, set(), commands, armed)

    def test_replayed_baseline_command_is_not_completion(self):
        request, commands, armed = example()
        self.assertIsNone(reader.terminal_result(request, IDENTITY, {COMMAND}, commands, armed))

    def test_new_but_stale_command_is_rejected(self):
        request, commands, armed = example()
        commands[COMMAND]["value"]["createdAt"] = armed - 1
        with self.assertRaises(ValueError):
            reader.terminal_result(request, IDENTITY, set(), commands, armed)

    def test_duplicate_actual_action_is_rejected(self):
        request, commands, armed = example()
        commands["33333333-3333-4333-8333-333333333333"] = copy.deepcopy(commands[COMMAND])
        with self.assertRaises(ValueError):
            reader.terminal_result(request, IDENTITY, set(), commands, armed)

    def test_foreign_generation_never_proves_our_action(self):
        request, commands, armed = example()
        commands[COMMAND]["value"]["invocation"]["identity"]["generation"] = 2
        self.assertIsNone(reader.terminal_result(request, IDENTITY, set(), commands, armed))

    def test_queued_and_running_are_pending(self):
        for status in ("queued", "running"):
            request, commands, armed = example()
            commands[COMMAND]["value"]["receipt"]["status"] = status
            self.assertIsNone(reader.terminal_result(request, IDENTITY, set(), commands, armed))

    def test_failure_cancellation_retry_and_lease_are_rejected(self):
        for key, value in (("status", "failed"), ("failure", {"code": "failed"}), ("cancellationRequested", True),
                           ("attempt", 2), ("attempt", True), ("leaseID", COMMAND), ("leaseExpiresAt", 1795852801000)):
            request, commands, armed = example()
            commands[COMMAND]["value"]["receipt"][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                reader.terminal_result(request, IDENTITY, set(), commands, armed)

    def test_actual_shortcuts_source_gesture_and_background_are_required(self):
        for key, value in (("source", "url"), ("userGesturePresent", False), ("canPresentUI", True),
                           ("appID", "unrelated")):
            request, commands, armed = example()
            commands[COMMAND]["value"]["invocation"]["delivery"][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                reader.terminal_result(request, IDENTITY, set(), commands, armed)

    def test_editor_public_readback_cannot_be_replaced_by_expected_values(self):
        request, _, _ = example()
        request["editor"]["rawRows"][0]["value"] = "99"
        with self.assertRaises(ValueError):
            reader.validate_editor(request, 0)

    def test_a_json_text_field_is_not_an_array_editor(self):
        request, _, _ = example()
        request["editor"]["rawRows"] = [{"label": "Input", "identifier": "", "value": "[-7,0,42]"}]
        with self.assertRaises(ValueError):
            reader.validate_editor(request, 0)

    def test_unsaved_unreopened_or_wrong_mode_is_rejected(self):
        for key, value in (("savedAndReopened", False), ("processRestarted", False),
                           ("openWhenRun", True), ("parameter", "input"), ("inputMode", "json")):
            request, _, _ = example()
            request["editor"][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                reader.validate_editor(request, 0)

    def test_wrong_saved_shortcut_or_missing_real_chain_is_rejected(self):
        for key, value in (("savedShortcutName", "old Shortcut"), ("builtInChain", ["Show Result"])):
            request, _, _ = example()
            request[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                reader.validate_editor(request, 0)

    def test_result_json_cannot_coerce_boolean_to_number(self):
        with self.assertRaises(ValueError):
            reader.result_values([True], [1])

    def test_foreground_or_stale_handler_result_is_rejected(self):
        for key, value in (("attached", True), ("executionMode", "foreground"),
                           ("observedAt", "2026-11-28T07:59:59Z"), ("nonce", "../old"),
                           ("windowID", "../other"), ("caller", "")):
            request, commands, armed = example()
            result = reader.shared.decode_value(commands[COMMAND]["value"]["receipt"]["value"])
            result[key] = value
            commands[COMMAND]["value"]["receipt"]["value"] = wire(result)
            with self.subTest(key=key), self.assertRaises(ValueError):
                reader.terminal_result(request, IDENTITY, set(), commands, armed)

    def exercise_two_steps(self, damage=None):
        # Actual observer state machine + real temporary reply/private files.
        # OS discovery/source admission are injected observations, not native PASS.
        from tempfile import TemporaryDirectory
        from types import SimpleNamespace
        from unittest.mock import patch
        with TemporaryDirectory() as temporary:
            base = Path(temporary)
            evidence = base / "attempt" / "shortcut-observer"; evidence.mkdir(parents=True)
            directory = base / "runner" / RUN; directory.mkdir(parents=True)
            roots = {key: base / key for key in ("app", "data", "group", "extensions")}
            for path in roots.values(): path.mkdir()
            inputs = {"sha256": "fixed-inputs", "value": {"archive": {"path": "injected", "sha256": "fixed"}}}
            identity = {**IDENTITY, "appID": reader.APP_ID, "actionID": reader.ACTION,
                        "hostActionHandler": "nativescript/app/bundle.mjs", "actionDisplayName": "Actual action"}
            request, _, armed = example()
            request.update(schema=1, engine="nativescript", surface="nativeLists",
                           fixtureAppID=reader.APP_ID, testMethod=reader.METHODS["integer"],
                           startedAt="2026-11-28T08:00:00Z", phase="native-list-installed")
            queue = {}; seen = {}
            args = SimpleNamespace(device="owned", bundle_id="app", runner_bundle_id="runner")
            with patch.object(reader.shared, "product_roots", return_value=roots), \
                 patch.object(reader, "current_inputs", return_value=inputs) as admission, \
                 patch.object(reader, "current_identity", return_value=(identity, {})), \
                 patch.object(reader.archive_binding, "verify_installed_fixture_archive", return_value={"bound": True}), \
                 patch.object(reader.shared, "queue_documents", side_effect=lambda _: copy.deepcopy(queue)), \
                 patch.object(reader.shared, "system_app_observation", return_value={}), \
                 patch.object(reader.time, "time", return_value=armed / 1000):
                reader.observe_case(args, request, directory, evidence, seen)
                for step in (0, 1):
                    update, command, _ = example(step=step)
                    request.update(update, phase="native-list-arm")
                    reader.observe_case(args, request, directory, evidence, seen)
                    command_id = COMMAND if step == 0 else "33333333-3333-4333-8333-333333333333"
                    row = command[COMMAND]["value"]; row["id"] = command_id
                    payload = reader.shared.decode_value(row["receipt"]["value"])
                    payload["nonce"] += str(step)
                    target = roots["data"] / "Library/Application Support/Hanlin/MiniApps" / reader.APP_ID \
                        / "Windows" / payload["windowID"] / "State" / ("native-list-" + payload["nonce"] + ".json")
                    target.parent.mkdir(parents=True, exist_ok=True)
                    payload["statePath"] = str(target)
                    target.write_text(json.dumps(payload))
                    row["receipt"]["value"] = wire(payload)
                    row["receipt"]["status"] = "running"
                    queue[command_id] = {"value": row}
                    request.update(phase="native-list-sent", systemLaunchObserved=True)
                    reader.observe_case(args, request, directory, evidence, seen)
                    self.assertEqual(seen[RUN]["phase"], "native-list-sent")
                    self.assertFalse((directory / ("completion-" + str(step) + ".json")).exists())
                    # Same phase is pending: don't rehash every binary; fresh
                    # terminal source/product/installation admission is mandatory.
                    count = admission.call_count
                    reader.observe_case(args, request, directory, evidence, seen)
                    self.assertEqual(admission.call_count, count)
                    row["receipt"]["status"] = "succeeded"
                    if damage == "private-link" and step == 0:
                        target.unlink(); target.symlink_to(base / "outside.json")
                        (base / "outside.json").write_text(json.dumps(payload))
                    reader.observe_case(args, request, directory, evidence, seen)
                    self.assertEqual(admission.call_count, count + 1)
                    request.update(phase="native-list-chain-read", renderedResult=copy.deepcopy(payload))
                    if damage == "wrong-chain" and step == 0:
                        request["renderedResult"]["values"] = [99]
                    reader.observe_case(args, request, directory, evidence, seen)
                    self.assertEqual(seen[RUN]["finished"], step == 1)
                final = json.loads((directory / "completion.json").read_text())
                self.assertEqual(final["nativeExecutions"], 2)
                self.assertEqual(len(final["steps"]), 2)
                self.assertEqual(final["steps"][1]["result"]["values"], [])
                self.assertNotEqual(final["steps"][0]["invocationID"], final["steps"][1]["invocationID"])

    def test_two_ordered_steps_wait_for_real_terminal_and_chain_then_finish(self):
        self.exercise_two_steps()

    def test_wrong_chain_cannot_admit_second_saved_execution(self):
        with self.assertRaises(ValueError):
            self.exercise_two_steps("wrong-chain")

    def test_private_window_result_cannot_follow_a_link(self):
        with self.assertRaises(ValueError):
            self.exercise_two_steps("private-link")



if __name__ == "__main__":
    unittest.main()
