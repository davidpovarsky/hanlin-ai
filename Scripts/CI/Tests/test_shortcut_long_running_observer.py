"""Pure adversarial evidence controls. These records are synthetic unit inputs,
never OS/native results and never written into a production container.
"""
from pathlib import Path
import copy
import datetime
import hashlib
import json
import sys
import tempfile
import unittest
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "ProductSplit"))
import observe_shortcut_long_running as observer

T = 1795790000000
COMMAND = "e5f5ea31-7793-4b54-8d65-c9c3ca78af21"
LEASE = "f7fa41ac-42b4-4d04-8368-f339e0013441"
NONCE = "unit-handler-nonce"


def stamp(milliseconds):
    return datetime.datetime.fromtimestamp(milliseconds / 1000, datetime.timezone.utc).isoformat()


def tagged(value):
    if value is None:
        return {"type": "null"}
    if type(value) is bool:
        return {"type": "bool", "value": value}
    if type(value) is int:
        return {"type": "integer", "value": str(value)}
    if type(value) is str:
        return {"type": "string", "value": value}
    if type(value) is list:
        return {"type": "array", "value": [tagged(item) for item in value]}
    return {"type": "object", "value": [{"key": key, "value": tagged(item)} for key, item in value.items()]}


def document(value, path):
    raw = json.dumps(value, sort_keys=True).encode()
    return {"path": path, "sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw), "value": value}


def request(engine="nativescript", scenario="return"):
    run = "26da94b3-7608-4a68-8643-5f0c5e2da647"
    token = "ef0a3c83-baf4-46a2-a355-4e489e4428ca"
    challenge = "unit-ui-challenge"
    name = "Hanlin-LR-" + engine + "-" + run[:8]
    return {"schema": 1, "runID": run, "engine": engine, "surface": observer.ROUTE,
            "scenario": scenario, "fixtureAppID": observer.app_id(engine), "fixtureTitle": observer.title(engine),
            "startedAt": stamp(T - 10000), "challenge": challenge, "baselineCounter": 0,
            "ownerProcessID": 4321, "ownerAccessibilityHeader": "Attributes: Application, example, pid: 4321,",
            "ownerWindowID": "prepared-owner" if engine == "nativescript" else None,
            "token": token, "savedShortcutName": name,
            "configuredInput": {"surface": observer.ROUTE, "challenge": challenge,
                "longRunning": {"schema": 1, "token": token, "profile": observer.PROFILE},
                "typed": {"text": "שלום עולם", "count": 42, "enabled": True, "empty": None,
                          "list": [True, 42, "שלום"]}},
            "savedConfiguration": {"savedShortcutName": name, "reopened": True, "allowLongRunning": True,
                "openWhenRun": False, "resultChainConfigured": True, "observedAt": stamp(T - 2000)},
            "launch": {"savedShortcutName": name, "systemRunTapped": True,
                "requestedAt": stamp(T - 1000), "observedAt": stamp(T - 500)}}


def result(req, completed=1):
    filename = "surface-invocation-" + req["token"] + "-" + NONCE + ".json"
    base = "/data/Library/Application Support/Hanlin/MiniApps/" + req["fixtureAppID"]
    path = base + ("/Windows/background-window/State/" if req["engine"] == "nativescript" else "/State/") + filename
    rows = []
    for ordinal in range(1, completed + 1):
        kind = observer.KINDS[(ordinal - 1) % 5]
        marker = ":".join((req["fixtureAppID"], req["challenge"], NONCE, str(ordinal), kind, "42"))
        receipt = {"executionID": str(uuid.UUID(int=ordinal + 100)), "durationMilliseconds": 1,
                   "didTimeOut": False, "wasCancelled": False, "outputWasTruncated": False,
                   "exitCode": 0, "stdout": marker + "\n", "stderr": ""}
        if kind == "javaScriptCore":
            receipt["value"] = marker
        rows.append({"ordinal": ordinal, "kind": kind, "marker": marker, "receipt": receipt})
    samples = [] if req["engine"] == "expo" else [{"windowID": "background-window", "statePath": path,
        "executionMode": "headless-action", "attached": False}]
    value = {"schemaVersion": 1, "appID": req["fixtureAppID"], "action": "surface.run",
             "challenge": req["challenge"], "nonce": NONCE,
             "requestID": COMMAND if req["engine"] == "expo" else NONCE,
             "requestIDOrigin": "host-invocation" if req["engine"] == "expo" else "javascript-handler",
             "caller": "unit-test", "request": copy.deepcopy(req["configuredInput"]),
             "requestedSurface": observer.ROUTE, "counter": 1, "startedAt": stamp(T),
             "status": "running", "receipts": rows, "presentationSamples": samples,
             "longRunning": {"schema": 1, "token": req["token"], "profile": observer.PROFILE,
                 "journalFile": filename, "phase": "pacing", "completedUnitCount": completed,
                 "totalUnitCount": 35, "reportCount": completed + 1,
                 "reportedProgressAt": stamp(T + 100), "completedPacingTicks": 0,
                 "progressMessage": "LR " + req["token"] + " " + str(completed) + "/35 receipts"}}
    return document(value, path)


def setup(engine="nativescript", scenario="return", completed=1):
    req = request(engine, scenario)
    identity = {"identity": {"installedPackageID": "unit-install", "packageID": "unit-package",
                            "generation": 1, "entrypointID": "surface-intent", "variantID": "default"}}
    receipt = {"invocationID": COMMAND, "status": "running", "attempt": 1, "leaseID": LEASE,
               "leaseExpiresAt": T + 900000, "cancellationRequested": False, "updatedAt": T + 100}
    value = {"id": COMMAND, "deliverySchemaVersion": 1, "createdAt": T,
             "invocation": {"identity": copy.deepcopy(identity["identity"]), "entityID": "surface.run",
                 "parameters": tagged(req["configuredInput"]), "continueInForeground": False,
                 "delivery": {"schemaVersion": 1, "appID": req["fixtureAppID"], "source": "shortcuts",
                              "userGesturePresent": True, "canPresentUI": False}}, "receipt": receipt}
    commands = {COMMAND: document(value, "/group/ResumeQueue/" + COMMAND + ".json")}
    journals = [result(req, completed)]
    return req, identity, commands, journals


def collect(data):
    req, identity, commands, journals = data
    return observer.collect(req, identity, set(), commands, journals)


def process():
    return {"pid": 4321, "parentPID": 4000, "launchEpoch": (T - 5000) / 1000, "path": "/owned/Simulator/MiniApps.app/MiniApps"}


def long_interval(data):
    row = collect(data)
    samples = []
    proof = None
    for second in range(302):
        value = observer.live_observation(row, process(), T + 1000 + second * 1000, 100 + second)
        value["completed"] = min(30, 1 + second // 10)
        value["reportCount"] = 2 + second
        value["reportedProgressAt"] = stamp(value["at"] - 50)
        proof = observer.extend_interval(samples, value)
    return proof


class LongRunningObserverTests(unittest.TestCase):
    def test_exact_requests_and_two_real_storage_shapes_are_admitted(self):
        for engine in ("expo", "nativescript"):
            with self.subTest(engine=engine):
                data = setup(engine)
                self.assertEqual(observer.validate_request(data[0])["engine"], engine)
                self.assertTrue(observer.validate_saved_launch(data[0]))
                self.assertEqual(collect(data)["commandID"], COMMAND)

    def test_input_coercion_or_scalable_profile_cannot_agree_with_itself(self):
        for mutate in (lambda req: req["configuredInput"]["typed"].update(enabled=1),
                       lambda req: req["configuredInput"]["typed"].update(count=True),
                       lambda req: req["configuredInput"]["longRunning"].update(duration=1)):
            req = request(); mutate(req)
            with self.assertRaises(observer.shared.ObservationError):
                observer.validate_request(req)

    def test_saved_settings_must_be_reopened_long_running_and_background(self):
        for key, bad in (("reopened", False), ("allowLongRunning", False), ("openWhenRun", True)):
            req = request(); req["savedConfiguration"][key] = bad
            with self.assertRaises(observer.shared.ObservationError):
                observer.validate_saved_launch(req)

    def test_duplicate_actual_command_or_handler_is_rejected(self):
        data = setup(); data[2][str(uuid.uuid4())] = copy.deepcopy(data[2][COMMAND])
        with self.assertRaises(observer.shared.ObservationError):
            collect(data)
        data = setup(); data[3].append(copy.deepcopy(data[3][0]))
        with self.assertRaises(observer.shared.ObservationError):
            collect(data)

    def test_generation_and_native_input_are_bound_separately_from_journal(self):
        for change in ("generation", "input"):
            data = setup()
            invocation = data[2][COMMAND]["value"]["invocation"]
            if change == "generation":
                invocation["identity"]["generation"] = 2
            else:
                altered = copy.deepcopy(data[0]["configuredInput"]); altered["typed"]["enabled"] = 1
                invocation["parameters"] = tagged(altered)
            with self.assertRaises(observer.shared.ObservationError):
                collect(data)

    def test_window_owner_path_and_attachment_cannot_be_substituted(self):
        for key, bad in (("windowID", "prepared-owner"), ("statePath", "/sibling/State/proof.json"), ("attached", True)):
            data = setup(); data[3][0]["value"]["presentationSamples"][0][key] = bad
            with self.assertRaises(observer.shared.ObservationError):
                collect(data)

    def test_progress_never_leads_or_counts_failed_runtime_work(self):
        for change in ("ahead", "bool", "timeout"):
            data = setup()
            value = data[3][0]["value"]
            if change == "ahead": value["longRunning"]["completedUnitCount"] = 2
            elif change == "bool": value["longRunning"]["completedUnitCount"] = True
            else: value["receipts"][0]["receipt"]["didTimeOut"] = True
            with self.assertRaises(observer.shared.ObservationError):
                collect(data)

    def test_runtime_marker_ordinal_and_unique_execution_ids_are_required(self):
        for change in ("marker", "ordinal", "duplicate"):
            data = setup(completed=2); rows = data[3][0]["value"]["receipts"]
            if change == "marker": rows[1]["marker"] += "-foreign"
            elif change == "ordinal": rows[1]["ordinal"] = 1
            else: rows[1]["receipt"]["executionID"] = rows[0]["receipt"]["executionID"]
            with self.assertRaises(observer.shared.ObservationError):
                collect(data)

    def test_expired_or_cancel_requested_lease_cannot_start_interval(self):
        for key, bad in (("leaseExpiresAt", T), ("cancellationRequested", True), ("status", "queued")):
            data = setup(); data[2][COMMAND]["value"]["receipt"][key] = bad
            with self.assertRaises(observer.shared.ObservationError):
                observer.live_observation(collect(data), process(), T + 1000, 100)

    def test_wall_clock_jump_does_not_qualify_three_hundred_seconds(self):
        row = collect(setup()); samples = []
        first = observer.live_observation(row, process(), T + 1000, 100)
        self.assertIsNone(observer.extend_interval(samples, first))
        after = copy.deepcopy(first); after.update(at=T + 900000, monotonic=101, reportCount=3, completed=2)
        self.assertIsNone(observer.extend_interval(samples, after))

    def test_periodic_monotonic_interval_qualifies_only_after_strictly_more_than_three_hundred(self):
        proof = long_interval(setup())
        self.assertEqual(proof["elapsedMonotonicSeconds"], 301)
        self.assertEqual(proof["sampleCount"], 302)
        self.assertEqual(proof["maximumSampleGapSeconds"], 1)

    def test_process_start_lease_nonce_window_or_sampling_gap_breaks_interval(self):
        first = observer.live_observation(collect(setup()), process(), T + 1000, 100)
        for key, value in (("process", {**process(), "launchEpoch": T / 1000}), ("leaseID", str(uuid.uuid4())),
                           ("nonce", "another-handler-nonce"), ("windowID", "another-window"), ("monotonic", 111)):
            samples = [copy.deepcopy(first)]
            after = copy.deepcopy(first); after.update(monotonic=101, reportCount=3)
            after[key] = value
            with self.assertRaises(observer.shared.ObservationError):
                observer.extend_interval(samples, after)

    def test_real_system_progress_text_cannot_claim_uncompleted_work(self):
        req = request()
        row = {"token": req["token"], "text": "LR " + req["token"] + " 2/35 receipts",
               "completed": 2, "observedAt": stamp(T + 1000)}
        self.assertEqual(observer.validate_progress_ui(row, req, 2), row)
        with self.assertRaises(observer.shared.ObservationError):
            observer.validate_progress_ui(row, req, 1)
        row["completed"] = True
        with self.assertRaises(observer.shared.ObservationError):
            observer.validate_progress_ui(row, req, 2)

    def test_success_requires_exact_native_value_and_all_thirty_five_receipts(self):
        proof = long_interval(setup())
        data = setup(completed=35); value = data[3][0]["value"]
        value.update(status="completed", finishedAt=stamp(T + 345000))
        value["longRunning"].update(phase="completed", completedPacingTicks=340)
        receipt = data[2][COMMAND]["value"]["receipt"]
        receipt.update(status="succeeded", leaseID=None, leaseExpiresAt=None, failure=None,
                       updatedAt=T + 345000, value=tagged(value))
        answer = observer.terminal_result(data[0], collect(data), proof, T + 346000)
        self.assertEqual(answer["status"], "TERMINAL_OBSERVED")
        altered = copy.deepcopy(value); altered["receipts"][-1]["marker"] += "-foreign"
        receipt["value"] = tagged(altered)
        with self.assertRaises(observer.shared.ObservationError):
            observer.terminal_result(data[0], collect(data), proof, T + 346000)

    def test_cancel_requires_actual_selected_stop_after_the_long_interval(self):
        data = setup(scenario="cancel", completed=31); proof = long_interval(setup(scenario="cancel"))
        receipt = data[2][COMMAND]["value"]["receipt"]
        receipt.update(status="cancelled", leaseID=None, leaseExpiresAt=None, cancellationRequested=True,
                       updatedAt=T + 305000, value=None)
        self.assertIsNone(observer.terminal_result(data[0], collect(data), proof, T + 306000))
        data[0]["stop"] = {"token": data[0]["token"], "visibleShortcutName": data[0]["savedShortcutName"],
                           "systemStopObserved": True, "requestedAt": stamp(T + 303000), "observedAt": stamp(T + 304000)}
        self.assertEqual(observer.terminal_result(data[0], collect(data), proof, T + 306000)["status"], "TERMINAL_OBSERVED")
        data[0]["stop"]["requestedAt"] = stamp(T + 299000)
        with self.assertRaises(observer.shared.ObservationError):
            observer.terminal_result(data[0], collect(data), proof, T + 306000)

    def test_cancelled_receipt_never_hides_a_late_successful_handler(self):
        data = setup(scenario="cancel", completed=35); proof = long_interval(setup(scenario="cancel"))
        data[0]["stop"] = {"token": data[0]["token"], "visibleShortcutName": data[0]["savedShortcutName"],
                           "systemStopObserved": True, "requestedAt": stamp(T + 303000), "observedAt": stamp(T + 304000)}
        data[2][COMMAND]["value"]["receipt"].update(status="cancelled", leaseID=None, leaseExpiresAt=None,
            cancellationRequested=True, value=None, updatedAt=T + 305000)
        with self.assertRaises(observer.shared.ObservationError):
            observer.terminal_result(data[0], collect(data), proof, T + 346000)

    def test_partial_late_success_after_cancellation_is_rejected_below_thirty_five(self):
        data = setup(scenario="cancel", completed=31)
        first = {"journal": copy.deepcopy(data[3][0])}
        observer.verify_cancelled_work_unchanged(first, copy.deepcopy(first))
        later = {"journal": result(data[0], completed=32)}
        with self.assertRaises(observer.shared.ObservationError):
            observer.verify_cancelled_work_unchanged(first, later)
        # Even before the fixture can advance counted progress, a new actual
        # successful receipt cannot be disguised as an uncounted tail.
        later["journal"]["value"]["longRunning"]["completedUnitCount"] = 31
        with self.assertRaises(observer.shared.ObservationError):
            observer.verify_cancelled_work_unchanged(first, later)
        later["journal"]["value"]["receipts"][-1]["receipt"]["wasCancelled"] = True
        observer.verify_cancelled_work_unchanged(first, later)
        later["journal"]["value"]["receipts"][0]["receipt"]["stdout"] = "replaced earlier output"
        with self.assertRaises(observer.shared.ObservationError):
            observer.verify_cancelled_work_unchanged(first, later)

    def test_close_event_is_bound_to_the_actual_own_invocation_and_window(self):
        data = setup(); row = collect(data)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            filename = Path(row["journal"]["path"]).name
            directory = root / "Windows" / row["windowID"] / "State"; directory.mkdir(parents=True)
            row["journal"]["path"] = str(directory / filename)
            path = directory / ("long-running-close-" + data[0]["token"] + "-" + row["nonce"] + ".json")
            self.assertIsNone(observer.close_observation(data[0], row, root))
            value = {"schema": 1, "event": "close", "appID": data[0]["fixtureAppID"],
                     "windowID": row["windowID"], "token": data[0]["token"], "nonce": row["nonce"],
                     "journalFile": filename, "statePath": str(path), "at": stamp(T + 305000)}
            path.write_text(json.dumps(value))
            self.assertEqual(observer.close_observation(data[0], row, root)["value"]["event"], "close")
            value["windowID"] = "wrong-window"; path.write_text(json.dumps(value))
            with self.assertRaises(observer.shared.ObservationError):
                observer.close_observation(data[0], row, root)


if __name__ == "__main__":
    unittest.main()
