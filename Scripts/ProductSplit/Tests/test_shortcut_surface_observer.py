"""Negative evidence controls for the original Shortcuts observation contract.

All records below are unit-test inputs in temporary directories. They are never
written into a simulator, an app container, or an external acceptance receipt.
"""
from pathlib import Path
import copy
import hashlib
import importlib.util
import json
import struct
import tempfile
import unittest
import uuid

MODULE = Path(__file__).resolve().parents[1] / "observe_shortcut_surfaces.py"
SPEC = importlib.util.spec_from_file_location("shortcut_surface_observer", MODULE)
observer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(observer)


def tagged(value):
    if value is None:
        return {"type": "null"}
    if type(value) is bool:
        return {"type": "bool", "value": value}
    if type(value) is int:
        return {"type": "integer", "value": str(value)}
    if type(value) is float:
        return {"type": "number", "value": struct.pack(">d", value).hex()}
    if isinstance(value, str):
        return {"type": "string", "value": value}
    if isinstance(value, list):
        return {"type": "array", "value": [tagged(item) for item in value]}
    if isinstance(value, dict):
        return {"type": "object", "value": [
            {"key": key, "value": tagged(item)} for key, item in value.items()]}
    raise TypeError(type(value))


def example(engine="expo", foreground=False):
    app_id = "hanlin.surface." + engine
    command_id = str(uuid.uuid4())
    request = {"schema": 1, "runID": str(uuid.uuid4()), "engine": engine,
               "fixtureAppID": app_id, "surface": "miniAppShortcut",
               "challenge": "fresh-abc-def", "baselineCounter": 0,
               "expectedCanPresentUI": foreground, "startedAt": "2026-11-27T00:00:00Z"}
    identity = {"identity": {"installedPackageID": "fixture-install", "packageID": app_id,
                "generation": 3, "entrypointID": "surface-intent", "variantID": "default"},
                "appID": app_id, "actionID": "surface.run",
                "hostActionHandler": "bundle.js" if engine == "expo" else "nativescript/app/bundle.mjs"}
    payload = {"surface": "miniAppShortcut", "challenge": request["challenge"],
               "typed": {"text": "שלום עולם", "count": 42, "enabled": True, "empty": None}}
    request["configuredInput"] = copy.deepcopy(payload)
    result = {"schemaVersion": 1, "appID": app_id, "action": "surface.run",
              "challenge": request["challenge"], "counter": 1, "nonce": "nonce-abc-def",
              "requestID": command_id if engine == "expo" else "nonce-abc-def",
              "requestIDOrigin": "host-invocation" if engine == "expo" else "javascript-handler",
              "requestedSurface": request["surface"], "request": payload,
              "status": "completed", "receipts": []}
    for kind in observer.ENGINES:
        marker = ":".join((app_id, request["challenge"], result["nonce"], "1", kind, "42"))
        receipt = {"executionID": str(uuid.uuid4()), "durationMilliseconds": 1,
                   "didTimeOut": False, "wasCancelled": False, "outputWasTruncated": False,
                   "exitCode": 0, "stdout": marker + "\n", "stderr": ""}
        if kind == "javaScriptCore":
            receipt["value"] = marker
        result["receipts"].append({"kind": kind, "marker": marker, "receipt": receipt})
    proof_path = "/unit-only/Library/Application Support/Hanlin/MiniApps/" + app_id + "/State/surface-proof.json"
    if engine == "nativescript":
        window_id = str(uuid.uuid4())
        proof_path = "/unit-only/Library/Application Support/Hanlin/MiniApps/" + app_id + \
            "/Windows/" + window_id + "/State/surface-proof.json"
        result["presentationSamples"] = [{"windowID": window_id, "statePath": proof_path,
            "executionMode": "foreground" if foreground else "headless-action", "attached": foreground}]
    row = {"id": command_id, "deliverySchemaVersion": 1, "createdAt": 1795737601000,
           "invocation": {"identity": copy.deepcopy(identity["identity"]), "entityID": "surface.run",
               "parameters": tagged(payload), "continueInForeground": foreground,
               "delivery": {"schemaVersion": 1, "appID": app_id, "source": "shortcuts",
                            "userGesturePresent": True, "canPresentUI": foreground}},
           "receipt": {"invocationID": command_id, "status": "succeeded", "attempt": 1,
                       "updatedAt": 1795737602000, "cancellationRequested": False, "value": tagged(result)}}
    commands = {command_id: {"path": "/unit-only/ResumeQueue/Receipts/" + command_id + ".json",
                             "sha256": "unit-input", "value": row}}
    proofs = [{"path": proof_path, "sha256": "unit-input", "value": {
        "schemaVersion": 1, "appID": app_id, "challenge": request["challenge"],
        "counter": 1, "lastResult": result}}]
    return request, identity, commands, proofs


def change_result(commands, proofs, update):
    result = copy.deepcopy(proofs[0]["value"]["lastResult"])
    update(result)
    proofs[0]["value"]["lastResult"] = result
    next(iter(commands.values()))["value"]["receipt"]["value"] = tagged(result)


class ShortcutEvidenceControls(unittest.TestCase):
    def accepted(self, values, baseline=()):
        request, identity, commands, proofs = values
        return observer.completion(request, identity, set(baseline), commands, proofs)

    def test_original_wire_format_preserves_unicode_and_types(self):
        value = {"text": "שלום", "count": 42, "enabled": True, "empty": None,
                 "é": "composed", "e\u0301": "decomposed"}
        self.assertEqual(observer.decode_value(tagged(value)), value)
        malformed = {"type": "object", "value": [
            {"key": "same", "value": tagged(1)}, {"key": "same", "value": tagged(2)}]}
        with self.assertRaises(observer.ObservationError):
            observer.decode_value(malformed)
        with self.assertRaises(observer.ObservationError):
            observer.parse_json('{"same":1,"same":2}')

    def test_ui_configured_input_rejects_consistently_coerced_native_results(self):
        changes = [
            ("boolean-to-integer", lambda typed: typed.update(enabled=1)),
            ("integer-to-binary64", lambda typed: typed.update(count=42.0)),
            ("integer-to-string", lambda typed: typed.update(count="42")),
            ("text-to-number", lambda typed: typed.update(text=42)),
            ("null-to-string", lambda typed: typed.update(empty="")),
            ("null-to-array", lambda typed: typed.update(empty=[])),
            ("missing-field", lambda typed: typed.pop("text")),
            ("extra-field", lambda typed: typed.update(extra="undeclared")),
        ]
        for name, mutate in changes:
            with self.subTest(mutation=name):
                values = example()
                payload = copy.deepcopy(values[0]["configuredInput"])
                mutate(payload["typed"])
                row = next(iter(values[2].values()))["value"]
                row["invocation"]["parameters"] = tagged(payload)
                change_result(values[2], values[3],
                              lambda result: result.update(request=copy.deepcopy(payload)))
                with self.assertRaisesRegex(observer.ObservationError, "UI-configured JSON"):
                    self.accepted(values)
        values = example()
        del values[0]["configuredInput"]
        with self.assertRaisesRegex(observer.ObservationError, "UI-configured JSON"):
            self.accepted(values)

    def test_returned_and_private_scalar_types_cannot_coerce(self):
        for mutation in ("returned-boolean", "private-boolean", "returned-counter", "private-counter"):
            with self.subTest(mutation=mutation):
                values = example()
                if mutation == "returned-boolean":
                    change_result(values[2], values[3],
                                  lambda result: result["request"]["typed"].update(enabled=1))
                elif mutation == "private-boolean":
                    state = values[3][0]["value"]
                    state["lastResult"] = copy.deepcopy(state["lastResult"])
                    state["lastResult"]["request"]["typed"]["enabled"] = 1
                elif mutation == "returned-counter":
                    change_result(values[2], values[3], lambda result: result.update(counter=True))
                    values[3][0]["value"]["counter"] = True
                else:
                    values[3][0]["value"]["counter"] = True
                with self.assertRaises(observer.ObservationError):
                    self.accepted(values)

    def test_current_expo_result_qualifies_only_its_exact_challenge(self):
        values = example()
        result = self.accepted(values)
        self.assertEqual(result["engines"], list(observer.CANONICAL_ENGINES))
        self.assertEqual(result["challenge"], values[0]["challenge"])
        values[0]["challenge"] = "another-abc-def"
        self.assertIsNone(self.accepted(values))

    def test_native_window_and_mode_are_independently_bound(self):
        for foreground in (False, True):
            with self.subTest(foreground=foreground):
                self.assertEqual(self.accepted(example("nativescript", foreground))["status"], "EXECUTED_PASS")
        for mutation in ("wrong-window", "wrong-path", "attached-background", "wrong-execution-mode"):
            with self.subTest(mutation=mutation):
                values = example("nativescript")
                def mutate(result):
                    sample = result["presentationSamples"][0]
                    if mutation == "wrong-window":
                        sample["windowID"] = str(uuid.uuid4())
                    elif mutation == "wrong-path":
                        sample["statePath"] = "/another-window/State/surface-proof.json"
                    elif mutation == "attached-background":
                        sample["attached"] = True
                    else:
                        sample["executionMode"] = "foreground"
                change_result(values[2], values[3], mutate)
                with self.assertRaises(observer.ObservationError):
                    self.accepted(values)

    def test_pending_and_preexisting_invocations_cannot_pass(self):
        values = example()
        self.assertIsNone(self.accepted(values, baseline=values[2]))
        row = next(iter(values[2].values()))["value"]
        for status in ("queued", "running"):
            row["receipt"]["status"] = status
            self.assertIsNone(self.accepted(values))

    def test_terminal_failure_or_cancellation_never_qualifies(self):
        for field, value in (("status", "failed"), ("status", "cancelled"), ("status", "stale"),
                             ("failure", "actionFailed"), ("cancellationRequested", True),
                             ("leaseID", str(uuid.uuid4())), ("attempt", 2)):
            with self.subTest(field=field, value=value):
                values = example()
                next(iter(values[2].values()))["value"]["receipt"][field] = value
                with self.assertRaises(observer.ObservationError):
                    self.accepted(values)

    def test_current_identity_and_exact_native_payload_are_required(self):
        values = example()
        next(iter(values[2].values()))["value"]["invocation"]["identity"]["generation"] += 1
        self.assertIsNone(self.accepted(values))
        values = example()
        change_result(values[2], values[3], lambda result: result["request"]["typed"].update(count=43))
        with self.assertRaises(observer.ObservationError):
            self.accepted(values)
        values = example()
        change_result(values[2], values[3], lambda result: result.update(requestID=str(uuid.uuid4())))
        with self.assertRaises(observer.ObservationError):
            self.accepted(values)

    def test_self_reported_engine_labels_without_outputs_cannot_pass(self):
        for mutation in ("missing-output", "wrong-marker", "duplicate-execution", "timeout", "truncated"):
            with self.subTest(mutation=mutation):
                values = example()
                def mutate(result):
                    rows = result["receipts"]
                    if mutation == "missing-output":
                        rows[0]["receipt"]["stdout"] = ""
                    elif mutation == "wrong-marker":
                        rows[1]["marker"] = "another-challenge"
                    elif mutation == "duplicate-execution":
                        rows[2]["receipt"]["executionID"] = rows[0]["receipt"]["executionID"]
                    elif mutation == "timeout":
                        rows[3]["receipt"]["didTimeOut"] = True
                    else:
                        rows[4]["receipt"]["outputWasTruncated"] = True
                change_result(values[2], values[3], mutate)
                with self.assertRaises(observer.ObservationError):
                    self.accepted(values)

    def test_os_delivery_and_mode_cannot_be_inferred(self):
        for field, value in (("source", "foreground"), ("appID", "another.app"),
                             ("userGesturePresent", False), ("canPresentUI", True)):
            with self.subTest(field=field):
                values = example()
                next(iter(values[2].values()))["value"]["invocation"]["delivery"][field] = value
                with self.assertRaises(observer.ObservationError):
                    self.accepted(values)

    def test_duplicate_execution_and_unmatched_private_result_fail(self):
        values = example()
        second = str(uuid.uuid4())
        duplicate = copy.deepcopy(next(iter(values[2].values())))
        duplicate["value"]["id"] = second
        duplicate["value"]["receipt"]["invocationID"] = second
        values[2][second] = duplicate
        with self.assertRaises(observer.ObservationError):
            self.accepted(values)
        values = example()
        values[3][0]["value"]["counter"] = 2
        with self.assertRaises(observer.ObservationError):
            self.accepted(values)

    def test_snapshot_hash_and_links_are_checked(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            revisions = root / "Revisions"
            revisions.mkdir()
            data = json.dumps({"schemaVersion": 1, "snapshot": {"intentEntities": []}}).encode()
            key = hashlib.sha256(data).hexdigest()
            (revisions / (key + ".json")).write_bytes(data)
            (root / "commit.json").write_text(json.dumps({"version": 1, "snapshotHash": key}))
            self.assertEqual(observer.snapshot_document(root)["sha256"], key)
            (revisions / (key + ".json")).write_text("{}")
            with self.assertRaises(observer.ObservationError):
                observer.snapshot_document(root)
            (root / "linked.json").symlink_to(root / "commit.json")
            with self.assertRaises(observer.ObservationError):
                observer.read_document(root / "linked.json", root)

    def test_primary_catalog_requires_enabled_current_supported_action(self):
        values = example()
        identity = values[1]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / "Library/Application Support/Hanlin/ScriptingPlatform/Installed/registry/catalog.json"
            path.parent.mkdir(parents=True)
            entry = {"enabled": True, "record": {"schemaVersion": 1,
                     "installedPackageID": identity["identity"]["installedPackageID"],
                     "packageID": identity["identity"]["packageID"], "activeGeneration": 3},
                     "entrypoints": [{"id": "surface-intent", "kind": "appIntent",
                         "compatibility": "supported", "supportedContexts": ["appIntent"],
                         "runtimeProfile": "hanlin-expo", "runtimePolicyID": "prepared-foreground-action-v1",
                         "exportedSymbol": "surface.run", "sourcePath": "bundle.js"}]}
            def write(value):
                path.write_text(json.dumps({"schemaVersion": 1, "revision": 1, "packages": {
                    identity["identity"]["installedPackageID"]: value}}))
            write(entry)
            self.assertEqual(observer.installed_catalog(root, identity)["path"], str(path))
            for mutation in ("disabled", "old-generation", "wrong-handler", "unsupported", "wrong-runtime"):
                with self.subTest(mutation=mutation):
                    candidate = copy.deepcopy(entry)
                    if mutation == "disabled":
                        candidate["enabled"] = False
                    elif mutation == "old-generation":
                        candidate["record"]["activeGeneration"] = 2
                    elif mutation == "wrong-handler":
                        candidate["entrypoints"][0]["sourcePath"] = "unrelated.js"
                    elif mutation == "unsupported":
                        candidate["entrypoints"][0]["compatibility"] = "unsupported"
                    else:
                        candidate["entrypoints"][0]["runtimeProfile"] = "legacy"
                    write(candidate)
                    with self.assertRaises(observer.ObservationError):
                        observer.installed_catalog(root, identity)

    def test_run_path_and_preparation_schema_are_strict(self):
        values = example()
        for key, value in (("runID", "../../other"), ("fixtureAppID", "another.app"),
                           ("baselineCounter", 1), ("expectedCanPresentUI", None)):
            with self.subTest(key=key):
                request = copy.deepcopy(values[0])
                request[key] = value
                with self.assertRaises((observer.ObservationError, ValueError)):
                    observer.validate_request(request)




def widget_example():
    identity = {"installedPackageID": "installation-1", "packageID": "matrix-package",
                "generation": 3, "entrypointID": "widget",
                "variantID": "87654321-1234-1234-1234-123456789abc"}
    before = {"state": {"revision": 0, "committedNonces": []}, "otherStatesSHA256": "other"}
    facts = {"identity": identity, "identitySHA256": observer.widget_identity_digest(identity),
             "program": {"sha256": "a" * 64}, "state": {"revision": 1, "committedNonces": ["native-fail"]},
             "values": {"count": 1, "fail": True, "retryAfter": 1795747290000},
             "cache": {"record": {"family": "systemMedium", "renderSHA256": "b" * 64}},
             "otherStatesSHA256": "other"}
    extension = {"path": str(Path("/unit-fixture/MiniAppsWidgets.appex/Widget").resolve())}
    event = {"subsystem": "com.hanlin.ai", "category": "WidgetRender",
             "timestamp": "2026-11-27 04:00:01.000+0000", "processID": 123,
             "processImagePath": extension["path"]}
    event["eventMessage"] = (
        "widget_render_retained v=1 engine=expo identitySHA256=" + facts["identitySHA256"] +
        " generation=3 family=systemMedium programSHA256=" + "a" * 64 +
        " stateRevision=1 renderSHA256=" + "b" * 64 + " pid=123")
    start = observer._epoch_milliseconds("2026-11-27T04:00:00Z")
    facts["values"]["retryAfter"] = start + 90000
    return before, facts, extension, event, start


class WidgetRecoveryObservationTests(unittest.TestCase):
    """Pure negative controls, never Simulator or system-log acceptance evidence."""

    def test_actual_event_fields_must_match_one_current_failed_render(self):
        baseline, facts, extension, event, start = widget_example()
        observer.require_widget_transition(facts, baseline, recovered=False)
        self.assertTrue(observer.matching_widget_fallback(event, facts, extension, start, start + 90000))

    def test_foreign_identity_generation_family_program_revision_render_and_process_are_rejected(self):
        _, facts, extension, event, start = widget_example()
        substitutions = [
            (facts["identitySHA256"], "c" * 64), ("generation=3", "generation=4"),
            ("family=systemMedium", "family=systemSmall"), ("programSHA256=" + "a" * 64, "programSHA256=" + "d" * 64),
            ("stateRevision=1", "stateRevision=0"), ("renderSHA256=" + "b" * 64, "renderSHA256=" + "e" * 64),
            ("pid=123", "pid=124"),
        ]
        for old, new in substitutions:
            with self.subTest(field=old):
                changed = copy.deepcopy(event)
                changed["eventMessage"] = changed["eventMessage"].replace(old, new)
                self.assertFalse(observer.matching_widget_fallback(changed, facts, extension, start, start + 90000))
        for key, value in [("processID", True), ("processID", 124),
                           ("processImagePath", "/unit-fixture/HanlinAI.app/Hanlin")]:
            with self.subTest(field=key, value=value):
                changed = {**event, key: value}
                self.assertFalse(observer.matching_widget_fallback(changed, facts, extension, start, start + 90000))

    def test_old_event_and_event_after_authored_failure_window_are_rejected(self):
        _, facts, extension, event, start = widget_example()
        for stamp in ["2026-11-27T03:59:59Z", "2026-11-27T04:01:30Z"]:
            with self.subTest(timestamp=stamp):
                self.assertFalse(observer.matching_widget_fallback(
                    {**event, "timestamp": stamp}, facts, extension, start, start + 90000))

    def test_passive_clock_expiry_cannot_satisfy_a_recover_callback(self):
        baseline, failed, _, _, _ = widget_example()
        recovered = copy.deepcopy(failed)
        recovered["state"] = {"revision": 2, "committedNonces": ["native-fail", "native-recover"]}
        recovered["values"] = {"count": 2, "fail": False, "retryAfter": 0}
        observer.require_widget_transition(recovered, baseline, recovered=True)
        for field, value in [("fail", True), ("retryAfter", failed["values"]["retryAfter"]),
                             ("count", True), ("count", 1)]:
            with self.subTest(field=field):
                changed = copy.deepcopy(recovered)
                changed["values"][field] = value
                with self.assertRaises(observer.ObservationError):
                    observer.require_widget_transition(changed, baseline, recovered=True)

    def test_nonce_and_other_instance_changes_cannot_self_validate(self):
        baseline, failed, _, _, _ = widget_example()
        recovered = copy.deepcopy(failed)
        recovered["state"] = {"revision": 2, "committedNonces": ["native-fail", "native-recover"]}
        recovered["values"] = {"count": 2, "fail": False, "retryAfter": 0}
        for state, other in [({"revision": 1, "committedNonces": ["native-fail"]}, "other"),
                             ({"revision": 2, "committedNonces": ["native-fail"]}, "other"),
                             (recovered["state"], "changed-other-instance")]:
            with self.subTest(state=state, other=other):
                changed = {**recovered, "state": state, "otherStatesSHA256": other}
                with self.assertRaises(observer.ObservationError):
                    observer.require_widget_transition(changed, baseline, recovered=True)

    def test_widget_request_requires_its_fresh_ui_created_instance_and_exact_scope(self):
        run_id = str(uuid.uuid4())
        request = {"schema": 1, "runID": run_id, "surface": "widgetRecovery", "engine": "expo",
                   "instanceName": "Recovery-" + run_id, "fixtureTitle": "Interactive Widget Matrix",
                   "expectedFamily": "systemMedium"}
        self.assertEqual(observer.validate_widget_request(request), run_id)
        for key, value in [("schema", True), ("instanceName", "Default"), ("expectedFamily", "systemLarge"),
                           ("fixtureTitle", "Another package"), ("engine", "nativescript")]:
            with self.subTest(field=key):
                with self.assertRaises(observer.ObservationError):
                    observer.validate_widget_request({**request, key: value})


if __name__ == "__main__":
    unittest.main()
