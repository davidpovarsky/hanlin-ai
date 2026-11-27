"""Pure adversarial controls; these fixtures never represent an OS execution."""
from pathlib import Path
import copy
import datetime
import hashlib
import json
import sys
import unittest
import urllib.parse
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import observe_shortcut_concurrency as observer
import observe_shortcut_surfaces as original

T = 1795730000000
APP = "hanlin.surface.nativescript"
BASE = "/data/Library/Application Support/Hanlin/MiniApps/" + APP


def stamp(value):
    return datetime.datetime.fromtimestamp(value / 1000, datetime.timezone.utc).isoformat()


def tagged(value):
    if value is None:
        return {"type": "null"}
    if type(value) is bool:
        return {"type": "bool", "value": value}
    if type(value) is int:
        return {"type": "integer", "value": str(value)}
    if type(value) is float:
        import struct
        return {"type": "number", "value": struct.pack(">d", value).hex()}
    if type(value) is str:
        return {"type": "string", "value": value}
    if type(value) is list:
        return {"type": "array", "value": [tagged(item) for item in value]}
    return {"type": "object", "value": [{"key": key, "value": tagged(item)} for key, item in value.items()]}


def document(value, path):
    raw = json.dumps(value, sort_keys=True).encode()
    return {"path": path, "sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw), "value": value}


def request(scenario="reverseCompletion"):
    run_id = "61f32bb8-91de-42a1-b123-123456789001"
    holds = [45000, 30000, 15000] if scenario == "reverseCompletion" else [45000, 30000, 60000]
    result = {"schema": 1, "runID": run_id, "engine": "nativescript",
              "surface": observer.ROUTE, "scenario": scenario, "fixtureAppID": APP,
              "fixtureTitle": "Surface NativeScript", "startedAt": stamp(T - 10000),
              "challenge": "current-ui-challenge", "baselineCounter": 0, "ownerProcessID": 12345,
              "ownerStatePath": BASE + "/State/surface-proof.json", "ownerWindowID": "original-owner",
              "phase": "overlap-requested",
              "invocations": [], "launches": []}
    for index, hold in enumerate(holds):
        token = str(uuid.UUID(int=index + 1))
        name = "Hanlin-NS-" + run_id[:8] + "-" + str(index + 1)
        payload = {"surface": observer.ROUTE, "challenge": result["challenge"],
                   "concurrency": {"schema": 1, "token": token, "holdMilliseconds": hold},
                   "typed": {"text": "שלום עולם", "count": 42, "enabled": True, "empty": None,
                             "list": [True, 42, "שלום"]}}
        result["invocations"].append({"token": token, "savedShortcutName": name, "configuredInput": payload,
                                     "expectedTerminal": "cancelled" if scenario == "cancelOne" and index == 2 else "succeeded"})
        result["launches"].append({"token": token, "savedShortcutName": name, "systemLaunchObserved": True,
                                  "url": "shortcuts://run-shortcut?name=" + urllib.parse.quote(name),
                                  "requestedAt": stamp(T - 9000 + index), "observedAt": stamp(T - 8000 + index)})
    return result


IDENTITY = {"identity": {"installedPackageID": "installed", "packageID": "package",
                        "generation": 3, "entrypointID": "surface-intent", "variantID": "default"}}


def runtime_receipts(result):
    receipts = []
    for index, kind in enumerate(original.ENGINES):
        marker = ":".join((APP, result["challenge"], result["nonce"], "1", kind, "42"))
        receipt = {"executionID": result["nonce"] + "-runtime-" + str(index),
                   "durationMilliseconds": 1, "didTimeOut": False, "wasCancelled": False,
                   "outputWasTruncated": False, "exitCode": 0, "stdout": marker + "\n"}
        if kind == "javaScriptCore":
            receipt["value"] = marker
        receipts.append({"kind": kind, "marker": marker, "receipt": receipt})
    return receipts


def observed(request, progress=T+100, finished=False):
    commands, journals = {}, []
    for index, spec in enumerate(request["invocations"]):
        token = spec["token"]
        nonce = "nonce-handler-" + str(index)
        filename = "surface-invocation-" + token + "-" + nonce + ".json"
        state_path = BASE + "/Windows/window-" + str(index) + "/State/" + filename
        result = {"schemaVersion": 1, "appID": APP, "action": "surface.run",
                  "challenge": request["challenge"], "nonce": nonce, "requestID": nonce,
                  "requestIDOrigin": "javascript-handler", "caller": "actual-shortcut",
                  "request": copy.deepcopy(spec["configuredInput"]), "requestedSurface": observer.ROUTE,
                  "counter": 1, "startedAt": stamp(T), "status": "running", "receipts": [],
                  "concurrency": {"schema": 1, "token": token,
                      "holdMilliseconds": spec["configuredInput"]["concurrency"]["holdMilliseconds"],
                      "journalFile": filename, "phase": "holding", "reportedProgressAt": stamp(progress)},
                  "presentationSamples": [{"windowID": "window-" + str(index), "statePath": state_path,
                                            "executionMode": "headless-action", "attached": False}]}
        command_id = str(uuid.UUID(int=index + 11))
        receipt = {"invocationID": command_id, "status": "running", "attempt": 1,
                   "cancellationRequested": False, "leaseID": str(uuid.UUID(int=index + 111)).upper(),
                   "leaseExpiresAt": T + 30000, "updatedAt": progress}
        if finished:
            finish = T + spec["configuredInput"]["concurrency"]["holdMilliseconds"] + 100
            result.update(status="completed", finishedAt=stamp(finish))
            result["concurrency"]["phase"] = "completed"
            result["receipts"] = runtime_receipts(result)
            receipt.update(status="succeeded", leaseID=None, leaseExpiresAt=None,
                           updatedAt=finish+10, failure=None, value=tagged(result))
            if spec["expectedTerminal"] == "cancelled":
                receipt.update(status="cancelled", cancellationRequested=True, value=None,
                               failure="cancelled", updatedAt=T+2000)
                result["status"] = "failed"
                result["concurrency"]["phase"] = "failed"
                result["receipts"] = []
        row = {"id": command_id, "deliverySchemaVersion": 1, "createdAt": T-500,
               "invocation": {"identity": copy.deepcopy(IDENTITY["identity"]), "entityID": "surface.run",
                   "parameters": tagged(spec["configuredInput"]), "continueInForeground": False,
                   "delivery": {"schemaVersion": 1, "source": "shortcuts", "appID": APP,
                                "userGesturePresent": True, "canPresentUI": False}},
               "receipt": receipt}
        commands[command_id] = document(row, "/group/ResumeQueue/" + command_id + ".json")
        journals.append(document(result, state_path))
    return commands, journals


def mapping(request, progress=T+100, finished=False):
    commands, journals = observed(request, progress, finished)
    return observer.collect(request, IDENTITY, set(), commands, journals)


def overlap(request):
    return observer.overlap(request, mapping(request, T+100), mapping(request, T+900), T+200, T+1000)


def terminal(request):
    if request["scenario"] == "cancelOne":
        spec = request["invocations"][2]
        request["stop"] = {"token": spec["token"], "savedShortcutName": spec["savedShortcutName"],
                           "visibleShortcutName": spec["savedShortcutName"], "systemStopObserved": True,
                           "requestedAt": stamp(T+1500), "observedAt": stamp(T+1800)}
    return observer.terminal(request, mapping(request, finished=True), overlap(request), T+100000)


def owner(request):
    before = {"schemaVersion": 1, "appID": APP, "challenge": request["challenge"],
              "counter": 0, "activityID": None, "lastResult": None}
    after = copy.deepcopy(before)
    result = {"schemaVersion": 1, "appID": APP, "action": "surface.run",
              "challenge": request["challenge"], "nonce": "owner-live-callback",
              "requestID": "owner-live-callback", "requestIDOrigin": "javascript-handler", "caller": "proof-ui",
              "request": {"surface": "foreground", "fixture": APP}, "requestedSurface": "foreground",
              "counter": 1, "startedAt": stamp(T+100100), "finishedAt": stamp(T+100200), "status": "completed",
              "presentationSamples": [{"windowID": "original-owner", "statePath": request["ownerStatePath"],
                                        "executionMode": "foreground", "attached": True}]}
    result["receipts"] = runtime_receipts(result)
    after.update(counter=1, lastResult=result)
    request.update(ownerProcessIDAfter=request["ownerProcessID"], ownerCallbackObserved=True)
    return document(before, request["ownerStatePath"]), document(after, request["ownerStatePath"])


class ConcurrencyObserverControls(unittest.TestCase):
    def test_exact_request_and_unique_actual_system_launch_contract(self):
        req = request()
        self.assertEqual(observer.validate_request(req), req["runID"])
        self.assertEqual(len(observer.validate_launches(req, True)), 3)
        mutations = [
            lambda r: r.update(engine="expo"),
            lambda r: r.update(ownerProcessID=True),
            lambda r: r["invocations"][0]["configuredInput"]["concurrency"].update(holdMilliseconds=True),
            lambda r: r["invocations"][1].update(token=r["invocations"][0]["token"]),
            lambda r: r["invocations"][0].update(expectedTerminal="cancelled"),
            lambda r: r["invocations"][0]["configuredInput"]["typed"].update(count=42.0),
            lambda r: r["launches"][1].update(token=r["launches"][0]["token"]),
            lambda r: r["launches"][0].update(url="hanlinminiapps://direct-perform"),
        ]
        for mutate in mutations:
            bad = copy.deepcopy(req); mutate(bad)
            with self.subTest(mutate=mutate), self.assertRaises(ObservationError):
                observer.validate_request(bad); observer.validate_launches(bad, True)

    def test_canonical_input_cannot_be_consistently_coerced_or_omitted(self):
        req = request()
        for mutate in (
            lambda p: p["typed"].update(enabled=1),
            lambda p: p["typed"].update(count=42.0),
            lambda p: p["typed"].pop("text"),
            lambda p: p["typed"]["list"].__setitem__(0, 1),
        ):
            commands, journals = observed(req)
            payload = copy.deepcopy(req["invocations"][0]["configuredInput"]); mutate(payload)
            commands[next(iter(commands))]["value"]["invocation"]["parameters"] = tagged(payload)
            journals[0]["value"]["request"] = payload
            with self.subTest(mutate=mutate), self.assertRaises(ObservationError):
                observer.collect(req, IDENTITY, set(), commands, journals)

    def test_foreign_identity_mode_and_system_delivery_cannot_pass(self):
        req = request()
        for change in ("generation", "canPresentUI", "continueInForeground", "source", "createdAt", "attempt"):
            commands, journals = observed(req)
            row = next(iter(commands.values()))["value"]
            if change == "generation": row["invocation"]["identity"]["generation"] += 1
            elif change == "canPresentUI": row["invocation"]["delivery"][change] = True
            elif change == "continueInForeground": row["invocation"][change] = True
            elif change == "source": row["invocation"]["delivery"][change] = "widget"
            elif change == "createdAt": row[change] = T-20000
            else: row["receipt"][change] = 2
            with self.subTest(change=change), self.assertRaises(ObservationError):
                observer.collect(req, IDENTITY, set(), commands, journals)

    def test_duplicate_native_delivery_and_handler_journal_are_rejected(self):
        req = request()
        commands, journals = observed(req)
        extra = copy.deepcopy(next(iter(commands.values())))
        commands[str(uuid.UUID(int=999))] = extra
        with self.assertRaises(ObservationError):
            observer.collect(req, IDENTITY, set(), commands, journals)
        commands, journals = observed(req)
        journals.append(copy.deepcopy(journals[0]))
        with self.assertRaises(ObservationError):
            observer.collect(req, IDENTITY, set(), commands, journals)

    def test_windows_paths_nonces_and_headless_presentation_are_independent(self):
        req = request()
        for change in ("path", "window", "attached", "mode", "nonce"):
            commands, journals = observed(req)
            row = journals[0]["value"]
            if change == "path": row["presentationSamples"][0]["statePath"] = "/wrong/State/x.json"
            elif change == "window": row["presentationSamples"][0]["windowID"] = "window-1"
            elif change == "attached": row["presentationSamples"][0]["attached"] = True
            elif change == "mode": row["presentationSamples"][0]["executionMode"] = "foreground"
            else: row["nonce"] = journals[1]["value"]["nonce"]
            with self.subTest(change=change), self.assertRaises(ObservationError):
                observer.collect(req, IDENTITY, set(), commands, journals)

    def test_two_actual_handler_progress_observations_prove_overlap(self):
        req = request()
        result = overlap(req)
        self.assertEqual(result["status"], "OVERLAP_OBSERVED")
        self.assertEqual(len({r["leaseID"] for r in result["invocations"].values()}), 3)
        self.assertEqual(len({r["windowID"] for r in result["invocations"].values()}), 3)

    def test_queued_leases_missing_handlers_and_serial_execution_are_not_overlap(self):
        req = request()
        first, second = mapping(req), mapping(req, T+900)
        token = req["invocations"][0]["token"]
        del first[token]["journal"]
        self.assertIsNone(observer.overlap(req, first, second, T+200, T+1000))
        first, second = mapping(req), mapping(req, T+900)
        first[token]["journal"]["value"]["status"] = "completed"
        self.assertIsNone(observer.overlap(req, first, second, T+200, T+1000))
        first, second = mapping(req), mapping(req, T+900)
        second[token]["command"]["value"]["receipt"]["status"] = "queued"
        self.assertIsNone(observer.overlap(req, first, second, T+200, T+1000))
        first, second = mapping(req), mapping(req, T+100)
        self.assertIsNone(observer.overlap(req, first, second, T+200, T+1000))

    def test_stale_shared_or_replaced_native_leases_reject_overlap(self):
        req = request()
        token = req["invocations"][0]["token"]
        for change in ("expired", "missing", "replaced", "shared", "oldprogress"):
            first, second = mapping(req), mapping(req, T+900)
            receipt = second[token]["command"]["value"]["receipt"]
            if change == "expired": receipt["leaseExpiresAt"] = T
            elif change == "missing": receipt["leaseID"] = None
            elif change == "replaced": receipt["leaseID"] = str(uuid.UUID(int=777))
            elif change == "shared": receipt["leaseID"] = second[req["invocations"][1]["token"]]["command"]["value"]["receipt"]["leaseID"]
            else: second[token]["journal"]["value"]["concurrency"]["reportedProgressAt"] = stamp(T-6000)
            with self.subTest(change=change), self.assertRaises(ObservationError):
                observer.overlap(req, first, second, T+200, T+1000)

    def test_terminal_success_requires_prior_overlap_and_actual_reverse_order(self):
        req = request()
        self.assertEqual(terminal(req)["status"], "ACTIONS_COMPLETED")
        with self.assertRaises(ObservationError):
            observer.terminal(req, mapping(req, finished=True), None, T+100000)
        actual = mapping(req, finished=True)
        actual[req["invocations"][2]["token"]]["command"]["value"]["receipt"]["updatedAt"] = T+80000
        with self.assertRaises(ObservationError):
            observer.terminal(req, actual, overlap(req), T+100000)

    def test_native_value_private_result_and_five_runtime_outputs_must_match(self):
        req = request()
        for change in ("result", "missingengine", "wrongmarker", "sharedexecution"):
            actual = mapping(req, finished=True)
            token = req["invocations"][0]["token"]
            row = actual[token]
            result = row["journal"]["value"]
            if change == "result":
                result["counter"] = True
            else:
                if change == "missingengine": result["receipts"].pop()
                elif change == "wrongmarker": result["receipts"][0]["receipt"]["stdout"] = "foreign\n"
                else:
                    result["receipts"][0]["receipt"]["executionID"] = actual[req["invocations"][1]["token"]]["journal"]["value"]["receipts"][0]["receipt"]["executionID"]
                row["command"]["value"]["receipt"]["value"] = tagged(result)
            with self.subTest(change=change), self.assertRaises(ObservationError):
                observer.terminal(req, actual, overlap(req), T+100000)

    def test_cancel_requires_actual_stop_selected_token_and_native_cancelled_receipt(self):
        req = request("cancelOne")
        good = terminal(req)
        self.assertEqual(good["status"], "ACTIONS_COMPLETED")
        for change in ("token", "visible", "early", "status", "requested", "value", "lease"):
            bad = copy.deepcopy(req); actual = mapping(bad, finished=True)
            row = actual[bad["invocations"][2]["token"]]["command"]["value"]["receipt"]
            if change == "token": bad["stop"]["token"] = bad["invocations"][0]["token"]
            elif change == "visible": bad["stop"]["visibleShortcutName"] = "different"
            elif change == "early": bad["stop"]["requestedAt"] = stamp(T)
            elif change == "status": row["status"] = "failed"
            elif change == "requested": row["cancellationRequested"] = False
            elif change == "value": row["value"] = tagged("fabricated success")
            else: row["leaseID"] = str(uuid.UUID(int=444))
            with self.subTest(change=change), self.assertRaises(ObservationError):
                observer.terminal(bad, actual, overlap(bad), T+100000)

    def test_cancel_waits_for_stop_and_late_hold_boundary(self):
        req = request("cancelOne")
        self.assertIsNone(observer.terminal(req, mapping(req, finished=True), overlap(req), T+100000))
        terminal(req)
        self.assertIsNone(observer.terminal(req, mapping(req, finished=True), overlap(req), T+60500))

    def test_original_owner_callback_pid_state_window_and_receipts_are_required(self):
        req = request(); done = terminal(req); before, after = owner(req)
        result = observer.owner_completion(req, before, after, done, mapping(req, finished=True))
        self.assertEqual(result["status"], "EXECUTED_PASS")
        for change in ("pid", "path", "counter", "caller", "attached", "window"):
            bad = copy.deepcopy(req); new = copy.deepcopy(after)
            if change == "pid": bad["ownerProcessIDAfter"] += 1
            elif change == "path": new["path"] = "/other/State/surface-proof.json"
            elif change == "counter": new["value"]["counter"] = True
            elif change == "caller": new["value"]["lastResult"]["caller"] = "shortcut"
            elif change == "attached": new["value"]["lastResult"]["presentationSamples"][0]["attached"] = False
            else: new["value"]["lastResult"]["presentationSamples"][0]["windowID"] = "window-0"
            with self.subTest(change=change), self.assertRaises(ObservationError):
                observer.owner_completion(bad, before, new, done, mapping(req, finished=True))

    def test_terminal_cancellation_cannot_be_overwritten_after_owner_callback(self):
        req = request("cancelOne"); done = terminal(req); before, after = owner(req)
        current = mapping(req, finished=True)
        cancelled = current[req["invocations"][2]["token"]]["command"]["value"]["receipt"]
        cancelled["status"] = "succeeded"
        cancelled["value"] = tagged("late callback")
        with self.assertRaises(ObservationError):
            observer.owner_completion(req, before, after, done, current)


    def test_final_native_rows_private_owners_and_callback_chronology_cannot_disappear(self):
        req = request(); done = terminal(req); before, after = owner(req)
        for change in ("missing", "empty", "journal", "window", "privatevalue", "earlycallback"):
            current = mapping(req, finished=True); new = copy.deepcopy(after)
            token = req["invocations"][0]["token"]
            if change == "missing": current.pop(token)
            elif change == "empty": current.clear()
            elif change == "journal": current[token].pop("journal")
            elif change == "window": current[token]["windowID"] = "replacement"
            elif change == "privatevalue": current[token]["journal"]["value"]["status"] = "failed"
            else: new["value"]["lastResult"]["startedAt"] = stamp(T+99900)
            with self.subTest(change=change), self.assertRaises(ObservationError):
                observer.owner_completion(req, before, new, done, current)


    def test_root_state_path_cannot_hide_replacement_foreground_window(self):
        req = request(); done = terminal(req); before, after = owner(req)
        after["value"]["lastResult"]["presentationSamples"][0]["windowID"] = "replacement-foreground"
        self.assertNotIn("/Windows/", before["path"])
        with self.assertRaises(ObservationError):
            observer.owner_completion(req, before, after, done, mapping(req, finished=True))
        req.pop("ownerWindowID")
        with self.assertRaises(ObservationError):
            observer.validate_request(req)

    def test_native_cancel_receipt_cannot_hide_late_successful_handler(self):
        req = request("cancelOne"); terminal(req)
        for change in ("completed", "five-successes", "stop-after-hold"):
            current = mapping(req, finished=True); bad = copy.deepcopy(req)
            row = current[req["invocations"][2]["token"]]
            journal = row["journal"]["value"]
            if change == "completed":
                journal["status"] = "completed"; journal["concurrency"]["phase"] = "completed"
                journal["receipts"] = runtime_receipts(journal)
            elif change == "five-successes":
                journal["receipts"] = runtime_receipts(journal)
            else:
                bad["stop"].update(requestedAt=stamp(T+70000), observedAt=stamp(T+71000))
                row["command"]["value"]["receipt"]["updatedAt"] = T+72000
            with self.subTest(change=change), self.assertRaises(ObservationError):
                observer.terminal(bad, current, overlap(bad), T+100000)
            if change != "stop-after-hold":
                # A successful handler appearing only after actions-complete
                # must also fail the final owner/readback boundary.
                before, after = owner(req)
                done = terminal(req)
                with self.subTest(change=change, phase="owner-after"), self.assertRaises(ObservationError):
                    observer.owner_completion(req, before, after, done, current)


ObservationError = original.ObservationError

if __name__ == "__main__":
    unittest.main()
