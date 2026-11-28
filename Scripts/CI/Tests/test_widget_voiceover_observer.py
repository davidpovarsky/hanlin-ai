"""Pure evidence controls; none of these records is a native VoiceOver receipt."""
from contextlib import ExitStack
import copy
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "ProductSplit"))
import observe_widget_voiceover as reader
import test_widget_state_observer as state_controls

Error = reader.original.ObservationError
stamp = state_controls.stamp


def fixture(prior=False):
    now = time.time() - 40
    request = state_controls.request_fixture()
    request.update(surface="widgetVoiceOver", requestedSpeechLocale="en_US", priorVoiceOverEnabled=prior,
                   startedAt=stamp(now), placed=["A"],
                   test="-[HanlinEntrypointSystemSurfaceUITests " + reader.SELECTOR + "]")
    request["instanceNames"] = {key: "VoiceOver-" + key + "-" + request["runID"] for key in ("A", "B")}
    initial = state_controls.pair_fixture(request)
    first = state_controls.changed_pair(initial, "A", 1, True)
    final = state_controls.changed_pair(first, "A", 2, False)
    events, previous = [], prior
    for reason, desired, seconds in [("setup", False, 1), ("exercise", True, 4),
                                     ("final-configuration", False, 30), ("restore-prior", prior, 34)]:
        events.append({"reason": reason, "requestedEnabled": desired, "beforeEnabled": previous,
                       "afterEnabled": desired, "status": "OK",
                       "operation": "unchanged" if previous is desired else ("enable" if desired else "disable"),
                       "startedAt": stamp(now + seconds), "finishedAt": stamp(now + seconds + .1),
                       "startedUptime": 1000 + seconds, "finishedUptime": 1000 + seconds + .1})
        previous = desired
    request["voiceOverEvents"] = events
    request["voiceOverRestoration"] = {"priorEnabled": prior, "afterEnabled": prior,
                                       "restoredAt": stamp(now + 35), "restoredUptime": 1035.0}
    return request, initial, first, final, now


def ui(pair):
    return {"A": state_controls.ui_fixture(pair)["A"]}


def speech(request, pair, phase, now, seconds):
    enabled = reader.widget.count_and_value(pair["A"])[1]
    return {"schema": 1, "runID": request["runID"], "attemptID": request["attemptID"],
            "sourceSHA": request["sourceSHA"], "phase": phase, "label": "Widget notifications",
            "visibleMatchingSwitchCount": 1, "ui": ui(pair), "startedAt": stamp(now + seconds),
            "startedUptime": 1000 + seconds, "trace": [{"index": 0, "operation": "currentSpeech",
                "at": stamp(now + seconds + 1), "uptime": 1001 + seconds,
                "utterance": "Widget notifications, " + ("On" if enabled else "Off") + ", Switch.",
                "serviceEnabled": True, "hostTerminated": True}]}


def step_fixture(request, before, after, now, index):
    seconds = 5 if index == 1 else 20
    action = {"index": index, "actionID": str(uuid.uuid4()), "instance": "A",
              "action": "toggle", "desiredValue": index == 1}
    pre = speech(request, before, "before-" + str(index), now, seconds)
    post = speech(request, after, "after-" + str(index), now, seconds + 6)
    armed = {"step": action, "before": before, "speech": pre,
             "frames": {"A": ui(before)["A"]["frame"]}, "armedAt": (now + seconds + 2) * 1000}
    gesture = {"schema": 1, "runID": request["runID"], "attemptID": request["attemptID"],
               "sourceSHA": request["sourceSHA"], "index": index, "actionID": action["actionID"],
               "method": "XCUIElement.doubleTap", "label": "Widget notifications",
               "visibleMatchingSwitchCount": 1, "beforeUI": ui(before),
               "currentSpeech": {"utterance": pre["trace"][-1]["utterance"],
                                 "at": stamp(now + seconds + 3), "uptime": 1003 + seconds},
               "startedAt": stamp(now + seconds + 4), "finishedAt": stamp(now + seconds + 5),
               "startedUptime": 1004 + seconds, "finishedUptime": 1005 + seconds,
               "serviceEnabledBefore": True, "serviceEnabledAfter": True,
               "hostTerminatedBefore": True, "hostTerminatedAfter": True}
    return armed, gesture, post


def roots_fixture():
    return {"app": Path("/pure-control/MiniApps.app"), "data": Path("/pure-control/data"),
            "group": Path("/pure-control/group"), "extensions": Path("/pure-control/group/HanlinMiniApps/v1"),
            "configuration": {"StorageNamespace": "HanlinMiniApps/v1"}, "infoSHA256": "1" * 64}


class WidgetVoiceOverEvidenceControls(unittest.TestCase):
    def test_actual_speech_gesture_and_two_native_transitions_agree(self):
        request, initial, first, final, now = fixture()
        nonces = []
        for index, before, after in [(1, initial, first), (2, first, final)]:
            armed, gesture, post = step_fixture(request, before, after, now, index)
            reader.require_step(armed["step"], index)
            reader.require_speech(armed["speech"], request, before, armed["frames"], "before-" + str(index), now * 1000)
            reader.require_speech(post, request, after, armed["frames"], "after-" + str(index), armed["armedAt"])
            reader.require_gesture(gesture, request, armed, post)
            nonces.append(reader.widget.require_transition(before, after, armed["step"]))
        self.assertEqual(len(set(nonces)), 2)
        self.assertEqual(reader.widget.count_and_value(final["A"]), (2, False))
        self.assertEqual(final["B"]["state"], initial["B"]["state"])

    def test_speech_requires_unique_label_and_actual_whole_state_word(self):
        for invalid in ["Widget notifications, only", "Widget notifications, Off, turn On",
                        "Widget notifications, On; Widget notifications, On", "Notifications, On",
                        "Widget notifications, מופעל", "Widget notifications, offline", None]:
            with self.subTest(raw=invalid), self.assertRaises(Error):
                reader.spoken_value(invalid)
        self.assertTrue(reader.spoken_value("WIDGET NOTIFICATIONS. ON. Switch"))
        self.assertFalse(reader.spoken_value("Widget notifications — off — switch"))

    def test_correct_native_value_cannot_validate_stale_or_disabled_speech(self):
        request, initial, first, _, now = fixture()
        armed, _, post = step_fixture(request, initial, first, now, 1)
        for field, value in [("utterance", "Widget notifications, Off, Switch"),
                             ("serviceEnabled", False), ("hostTerminated", False)]:
            changed = copy.deepcopy(post)
            changed["trace"][-1][field] = value
            with self.subTest(field=field), self.assertRaises(Error):
                reader.require_speech(changed, request, first, armed["frames"], "after-1", armed["armedAt"])

    def test_ambiguous_physical_switch_or_replaced_frame_cannot_bind_speech(self):
        request, initial, _, _, now = fixture()
        value = speech(request, initial, "before-1", now, 5)
        frames = {"A": value["ui"]["A"]["frame"]}
        for mutate in [lambda x: x.update(visibleMatchingSwitchCount=2),
                       lambda x: x.update(visibleMatchingSwitchCount=True),
                       lambda x: x["ui"]["A"].update(frame=[1, 0, 300, 160])]:
            changed = copy.deepcopy(value); mutate(changed)
            with self.assertRaises(Error):
                reader.require_speech(changed, request, initial, frames, "before-1", now * 1000)

    def test_speech_and_gesture_must_retain_exact_run_attempt_source(self):
        request, initial, first, _, now = fixture()
        armed, gesture, post = step_fixture(request, initial, first, now, 1)
        for key in ("runID", "attemptID", "sourceSHA"):
            changed = copy.deepcopy(post); changed[key] = "different"
            with self.subTest(key=key), self.assertRaises(Error):
                reader.require_speech(changed, request, first, armed["frames"], "after-1", armed["armedAt"])
            changed = copy.deepcopy(gesture); changed[key] = "different"
            with self.subTest(gestureKey=key), self.assertRaises(Error):
                reader.require_gesture(changed, request, armed, post)

    def test_other_gesture_disabled_service_or_started_host_is_rejected(self):
        request, initial, first, _, now = fixture()
        armed, gesture, post = step_fixture(request, initial, first, now, 1)
        for key, value in [("method", "XCUIElement.tap"), ("actionID", str(uuid.uuid4())),
                           ("serviceEnabledBefore", False), ("serviceEnabledAfter", False),
                           ("hostTerminatedBefore", False), ("hostTerminatedAfter", False)]:
            changed = copy.deepcopy(gesture); changed[key] = value
            with self.subTest(key=key), self.assertRaises(Error):
                reader.require_gesture(changed, request, armed, post)

    def test_immediate_current_speech_and_monotonic_order_are_required(self):
        request, initial, first, _, now = fixture()
        armed, gesture, post = step_fixture(request, initial, first, now, 1)
        for mutate in [lambda x: x["currentSpeech"].update(utterance="Widget notifications, On, Switch"),
                       lambda x: x["currentSpeech"].update(at=stamp(now + 1)),
                       lambda x: x.update(finishedUptime=x["startedUptime"] - 1),
                       lambda x: x.update(finishedAt=stamp(now + 38))]:
            changed = copy.deepcopy(gesture); mutate(changed)
            with self.assertRaises(Error):
                reader.require_gesture(changed, request, armed, post)

    def apply_fixture(self, pair_mutation=None):
        request, initial, first, _, now = fixture()
        armed, gesture, post = step_fixture(request, initial, first, now, 1)
        request.update(phase="widget-voiceover-applied", step=armed["step"], voiceOverBefore=armed["speech"],
                       voiceOverGesture=gesture, voiceOverAfter=post, ui=ui(first),
                       configurationBindings={"A": {"retained": "pure binding"}}, voiceOverEvents=request["voiceOverEvents"][:2])
        case = {"kind": "widgetVoiceOver", "finished": False, "identity": reader.request_identity(request),
                "roots": roots_fixture(), "initial": initial, "previous": initial, "steps": [],
                "inputs": {"value": {"attemptID": request["attemptID"], "sourceSHA": request["sourceSHA"]}},
                "frames": armed["frames"], "bindings": request["configurationBindings"],
                "events": request["voiceOverEvents"], "armed": armed, "placed": True}
        observed = copy.deepcopy(first)
        if pair_mutation:
            observed = pair_mutation(observed, initial)
        with tempfile.TemporaryDirectory() as folder, ExitStack() as context:
            directory = Path(folder) / request["runID"]; directory.mkdir()
            evidence = Path(folder) / "evidence"; evidence.mkdir()
            case["directory"] = str(directory)
            context.enter_context(patch.object(reader.original, "product_roots", return_value=case["roots"]))
            context.enter_context(patch.object(reader.widget, "read_pair", return_value=observed))
            context.enter_context(patch.object(reader.widget, "retain_ui_artifacts", return_value={}))
            context.enter_context(patch.object(reader, "retain_json", return_value={}))
            response = context.enter_context(patch.object(reader.widget, "retain_response"))
            args = type("Args", (), {"device": "owned", "bundle_id": "com.itorah.hanlinminiapps"})()
            reader.observe_case(args, request, directory, evidence, {request["runID"]: case}, {})
            return case, response.call_args

    def test_spoken_and_ax_claim_without_actual_native_transition_cannot_pass(self):
        valid, output = self.apply_fixture()
        self.assertEqual(len(valid["steps"]), 1)
        self.assertEqual(output.args[-1]["status"], "APPLIED")
        unchanged, output = self.apply_fixture(lambda observed, initial: initial)
        self.assertEqual(unchanged["steps"], [])
        self.assertIsNone(output)

    def test_an_untouched_B_change_or_duplicate_native_nonce_rejects_the_actual_phase(self):
        def other_changed(observed, initial):
            observed["B"]["state"]["revision"] += 1
            return observed
        def no_new_nonce(observed, initial):
            observed["A"]["state"]["committedNonces"] = initial["A"]["state"]["committedNonces"]
            return observed
        for mutation in (other_changed, no_new_nonce):
            with self.assertRaises(Error):
                self.apply_fixture(mutation)

    def test_prior_service_lifecycle_requires_real_success_and_exact_restoration(self):
        for prior in (False, True):
            request, _, _, _, now = fixture(prior)
            events = reader.require_events(request, 4)
            reader.require_restoration(request, events, (now + 32) * 1000)
            for mutate in [lambda x: x["voiceOverEvents"][-1].update(status="FAILED"),
                           lambda x: x["voiceOverEvents"][-1].update(afterEnabled=not prior),
                           lambda x: x["voiceOverRestoration"].update(afterEnabled=not prior),
                           lambda x: x.update(restorationFailure="actual service failed"),
                           lambda x: x["voiceOverRestoration"].update(restoredAt=stamp(now + 20))]:
                changed = copy.deepcopy(request); mutate(changed)
                with self.subTest(prior=prior), self.assertRaises(Error):
                    result = reader.require_events(changed, 4)
                    reader.require_restoration(changed, result, (now + 32) * 1000)

    def test_actual_json_artifact_cannot_be_missing_changed_or_linked(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "runner"; source.mkdir()
            evidence = Path(folder) / "evidence"; evidence.mkdir()
            value = {"utterance": "Actual pure-control input only"}
            path = source / "speech.json"; path.write_text(json.dumps(value))
            result = reader.retain_json(source, evidence, "speech.json", value)
            self.assertEqual(result["sha256"], reader.original.digest(path.read_bytes()))
            with self.assertRaises(Error):
                reader.retain_json(source, evidence, "speech.json", {"utterance": "substituted"})
            path.unlink(); path.symlink_to(evidence / "speech.json")
            with self.assertRaises(Error):
                reader.retain_json(source, evidence, "speech.json", value)

    def finish_fixture(self, request_mutation=None, final_mutation=None, roots_mutation=None, prior=False):
        request, initial, first, final, now = fixture(prior)
        steps = []
        for index, before, after in [(1, initial, first), (2, first, final)]:
            armed, gesture, post = step_fixture(request, before, after, now, index)
            nonce = reader.widget.require_transition(before, after, armed["step"])
            steps.append({"step": armed["step"], "nativeNonce": nonce, "observedAt": (now + (13 if index == 1 else 28)) * 1000})
        request.update(phase="widget-voiceover-complete", ui=ui(final), configurationBindings={"A": {
            "instanceName": request["instanceNames"]["A"], "count": 2,
            "label": request["instanceNames"]["A"], "value": "", "frame": ui(final)["A"]["frame"],
            "verifiedAt": stamp(now + 32)}})
        roots = roots_fixture()
        extension = {"path": "/pure-control/MiniApps.app/PlugIns/Widgets.appex/Widgets", "infoSHA256": "2" * 64}
        inputs = {"sha256": "3" * 64, "value": {"attemptID": request["attemptID"], "sourceSHA": request["sourceSHA"]}}
        case = {"kind": "widgetVoiceOver", "finished": False, "identity": reader.request_identity(request),
                "roots": roots, "extension": extension, "initial": initial, "previous": final,
                "inputs": inputs, "steps": steps, "placed": True, "armed": None,
                "frames": {"A": ui(final)["A"]["frame"]}, "events": request["voiceOverEvents"][:2]}
        final_pair, terminal_roots = copy.deepcopy(final), copy.deepcopy(roots)
        # An unplaced B legitimately has no rendered cache. It is not a second
        # placed widget and completion may not invent that obligation or proof.
        final_pair["B"]["cache"] = None
        if request_mutation: request_mutation(request)
        if final_mutation: final_mutation(final_pair)
        if roots_mutation: roots_mutation(terminal_roots)
        with tempfile.TemporaryDirectory() as folder, ExitStack() as context:
            directory = Path(folder) / request["runID"]; directory.mkdir()
            evidence = Path(folder) / "evidence"; evidence.mkdir()
            case["directory"] = str(directory)
            context.enter_context(patch.object(reader.original, "product_roots", side_effect=[roots, roots, terminal_roots]))
            context.enter_context(patch.object(reader.original, "widget_extension_executable", return_value=extension))
            context.enter_context(patch.object(reader.widget, "read_pair", side_effect=[final, final_pair]))
            context.enter_context(patch.object(reader, "load_inputs", return_value=inputs))
            context.enter_context(patch.object(reader.widget, "current_code"))
            context.enter_context(patch.object(reader.widget, "retain_configurations", return_value={}))
            context.enter_context(patch.object(reader, "retain_json", return_value={}))
            output = context.enter_context(patch.object(reader.widget, "retain_response"))
            args = type("Args", (), {"device": "owned", "bundle_id": "com.itorah.hanlinminiapps"})()
            try:
                reader.observe_case(args, request, directory, evidence, {request["runID"]: case}, {})
            except Error:
                self.assertFalse(case["finished"]); output.assert_not_called(); raise
            self.assertTrue(case["finished"])
            self.assertEqual(output.call_args.args[-1]["status"], "EXECUTED_PASS")

    def test_completion_admits_one_placement_and_requires_both_current_identities(self):
        self.finish_fixture(prior=False)
        self.finish_fixture(prior=True)
        for change in [lambda row: row.update(placed=["A", "B"]),
                       lambda row: row.update(attemptID=str(uuid.uuid4())),
                       lambda row: row.update(priorVoiceOverEnabled=True),
                       lambda row: row["configurationBindings"]["A"].update(label=row["instanceNames"]["B"])]:
            with self.assertRaises(Error): self.finish_fixture(request_mutation=change)
        for change in [lambda pair: pair["B"]["identity"].update(variantID=str(uuid.uuid4())),
                       lambda pair: pair["B"]["state"].update(revision=1)]:
            with self.assertRaises(Error): self.finish_fixture(final_mutation=change)

    def test_final_MCM_replacement_and_stale_restoration_never_write_completion(self):
        with self.assertRaises(Error):
            self.finish_fixture(roots_mutation=lambda row: row.update(data=Path("/pure-control/replaced")))
        with self.assertRaises(Error):
            self.finish_fixture(request_mutation=lambda row: row.pop("voiceOverRestoration"))

    def test_final_configuration_service_order_and_other_state_are_bound(self):
        request, _, _, _, now = fixture()
        for mutate in [lambda row: row["voiceOverEvents"][-1].update(startedAt=stamp(now + 31)),
                       lambda row: row["voiceOverEvents"][-2].update(finishedAt=stamp(now + 33))]:
            changed = copy.deepcopy(request); mutate(changed)
            events = reader.require_events(changed, 4)
            with self.assertRaises(Error):
                reader.require_restoration(changed, events, (now + 32) * 1000)
        with self.assertRaises(Error):
            self.finish_fixture(final_mutation=lambda pair: pair["A"].update(otherStatesSHA256="changed"))


if __name__ == "__main__":
    unittest.main()
