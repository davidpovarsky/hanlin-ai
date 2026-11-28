"""Source-only counterexamples for the separate ActivityKit lifecycle observer.

Constructed documents exercise admission, not ActivityKit, native AX or gestures.
The two actual authored fixtures and original System10 are never rewritten here.
"""
import copy
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Scripts/ProductSplit"))
import observe_liveactivity_lifecycle as observation

RUN = "2f9b2b4e-9752-4a58-8e35-3817cb95d416"
START = 1_800_000_000_000
NOW = 1_800_000_010.0


def request(engine="expo"):
    fixture = observation.fixture_contract(engine)
    return {"schema": 1, "runID": RUN, "engine": engine, "surface": "liveActivityLifecycle",
            "fixtureAppID": fixture["appID"], "fixtureTitle": fixture["title"],
            "testMethod": fixture["method"], "startedAt": "2027-01-15T08:00:00.000Z",
            "ownerProcessID": 42, "attemptID": RUN, "sourceSHA": "a" * 40}


def stamp(milliseconds):
    return datetime.fromtimestamp(milliseconds / 1000, timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def tap(name, ordinal):
    offset = (ordinal - 1) * 10
    return {"name": name, "ordinal": ordinal,
            "beganAt": stamp(START + offset), "returnedAt": stamp(START + offset + 1),
            "beganUptime": 1.0 + ordinal, "returnedUptime": 1.1 + ordinal}


def call(name, result=None, include=True):
    value = {"method": name, "requestedAtEpochMilliseconds": START + 2,
             "observedReturnAtEpochMilliseconds": START + 2, "outcome": "returned"}
    if include:
        value["result"] = result
    return value


def append(journal, operation, calls):
    result = copy.deepcopy(journal)
    offset = len(result["observations"]) * 10
    timed = copy.deepcopy(calls)
    for item in timed:
        item["requestedAtEpochMilliseconds"] += offset
        item["observedReturnAtEpochMilliseconds"] += offset
    result["observations"].append({"ordinal": len(result["observations"]) + 1, "operation": operation,
        "requestedAtEpochMilliseconds": START + offset + 1, "completedAtEpochMilliseconds": START + offset + 3,
        "outcome": "returned", "calls": timed})
    return result


def prepared(engine):
    journal = {"schemaVersion": 1, "engine": engine, "appID": "hanlin.activity.lifecycle." + engine,
        "runUUID": RUN, "preparedAtEpochMilliseconds": START + 2, "listScope": "source-bound original owner",
        "storage": {"area": "state", "filename": "activity-lifecycle.json"},
        "slots": {"A": None, "B": None}, "lastObservedIDs": [], "observations": []}
    calls = ([call("host.readFile(state)", {"exists": False}), call("createLiveActivity", include=False),
              call("factory.getInstances/getId", [])] if engine == "expo" else
             [call("File.exists(private State journal)", False), call("host.liveActivities.list", [])])
    return append(journal, "prepare", calls)


def start(journal, slot, identity):
    engine = journal["engine"]
    calls = ([call("factory.start", include=False), call("activity.getId", identity)] if engine == "expo" else
             [call("host.liveActivities.areEnabled", True), call("host.liveActivities.start", {"activityID": identity})])
    value = append(journal, "start-" + slot.lower(), calls)
    value["slots"][slot] = {"activityID": identity, "submittedRevision": 0, "endRequestReturned": False}
    return value


def listing(journal, identities):
    name = "factory.getInstances/getId" if journal["engine"] == "expo" else "host.liveActivities.list"
    value = append(journal, "list", [call(name, identities)])
    value["lastObservedIDs"] = identities
    return value


def revised(journal, slot, end=False):
    engine = journal["engine"]
    identity = journal["slots"][slot]["activityID"]
    name = ("end-" + slot.lower()) if end else "update-a"
    if engine == "expo":
        calls = [call("activity.getId", identity), call("activity.end('immediate')" if end else "activity.update", include=False)]
    else:
        calls = [call("host.liveActivities.end" if end else "host.liveActivities.update", {"ok": True})]
    value = append(journal, name, calls)
    value["slots"][slot]["endRequestReturned" if end else "submittedRevision"] = True if end else 1
    return value


def native_element(text, frame=None):
    return {"identifier": "constructed-control-input", "label": text, "value": text,
        "elementType": "ConstructedNativeTypeNotAnObservedAXClaim", "elementTypeRaw": 0,
        "exists": True, "hittable": True, "enabled": True, "matchingCount": 1,
        "frame": frame or [20, 30, 100, 20],
        "window": {"owner": "com.apple.springboard", "exists": True,
                   "matchingWindowCount": 1, "frame": [0, 0, 400, 800]}}


def capture(index):
    name, _, expected, forbidden = observation.PRESENTATIONS[index]
    context = "compact-home" if index == 0 else ("expanded-island" if index == 1 else
              "home" if index == 5 else "notification-centre-pull-down")
    elements = {observation.marker(RUN, *parts): native_element(observation.marker(RUN, *parts))
                for parts in expected}
    gesture = {"kind": "actual-compact-marker-long-press" if index == 1 else
               "public-home" if index in (0, 5) else "public-home-then-pull-down",
               "returnedAt": "2027-01-15T08:00:00.100Z", "returnedUptime": 2.1}
    if index == 1:
        gesture.update(marker=native_element(observation.marker(RUN, "A", "compact-leading", 0)),
                       durationSeconds=1)
    elif index not in (0, 5):
        gesture.update(startNormalized=[0.2, 0.01], endNormalized=[0.2, 0.80])
    witnesses = [native_element("Notification Center")] if index == 6 else []
    return {"index": index, "name": name, "context": context, "attachmentLabel": "activity-lifecycle-" + name,
            "systemOwner": "com.apple.springboard", "systemForeground": True, "miniAppsForeground": False,
            "screenFrame": [0, 0, 400, 800], "requestedAt": "2027-01-15T08:00:00.000Z",
            "capturedAt": "2027-01-15T08:00:00.200Z", "requestedUptime": 2.0, "capturedUptime": 2.2,
            "elements": elements, "visibleOwnedMarkers": list(elements), "forbiddenSlots": list(forbidden),
            "noVisibleOwnedMarkersAtCapture": not elements, "emptyBannerContextWitnesses": witnesses,
            "gesture": gesture}


def scriptwidget_owner_documents(root):
    req = request("nativescript")
    identity = {"installedPackageID": "owned-install", "packageID": "owned-package", "generation": 1}
    expected = {**identity, "entrypointID": "widget", "variantID": "default"}
    source_hash = "1b61cc1b750e82415cac38a9b6af78fc63154ec98d0f7a4dfcddddf2ccf2bc90"
    package = {"identity": identity,
               "source": {"installedSources": {"source/widget.jsx": {"sha256": source_hash}}}}
    program = {"engine": "scriptwidget", "abiVersion": 1, "families": ["systemMedium"],
               "actions": [], "sourceSHA256": source_hash}
    raw = json.dumps(program, sort_keys=True).encode()
    program_hash = observation.shared.digest(raw)
    reference = "Packages/owned-install/generations/1/artifacts/" + program_hash
    path = root / reference
    path.parent.mkdir(parents=True)
    path.write_bytes(raw)
    # These are the original Codable fields; isDefault and entityID are computed
    # Swift properties and therefore absent from the retained snapshot JSON.
    instance = {"identity": copy.deepcopy(expected), "engine": "scriptwidget", "displayName": "Default", "settings": {}}
    snapshot = {"widgetInstances": [instance], "inactiveWidgetInstallations": [], "widgetStates": [],
                "widgets": [{"identity": copy.deepcopy(expected), "engine": "scriptwidget",
                    "displayName": req["fixtureTitle"] + " · Default", "family": "systemMedium",
                    "validUntil": (NOW + 60) * 1000,
                    "payload": {"kind": "scriptwidget", "scriptDescriptor": {
                        "scriptRef": reference, "scriptSHA256": program_hash}}}]}
    return req, package, snapshot


def publish_scriptwidget_owner_snapshot(root, snapshot):
    raw = json.dumps({"snapshot": snapshot}, sort_keys=True).encode()
    key = observation.shared.digest(raw)
    (root / "Revisions").mkdir(exist_ok=True)
    (root / "Revisions" / (key + ".json")).write_bytes(raw)
    (root / "commit.json").write_text(json.dumps({"version": 1, "snapshotHash": key}))


class LiveActivityLifecycleObserverTests(unittest.TestCase):
    def validate(self, value, prior=None):
        name = value["observations"][-1]["operation"]
        req = request(value["engine"])
        req["operation"] = tap(name, len(value["observations"]))
        with patch.object(observation.time, "time", return_value=NOW):
            return observation.journal_transition(value, req, prior, name)

    def test_native_owner_reads_canonical_default_without_computed_json_fields(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            req, package, snapshot = scriptwidget_owner_documents(root)
            publish_scriptwidget_owner_snapshot(root, snapshot)
            with patch.object(observation.time, "time", return_value=NOW):
                actual = observation.native_owner({"extensions": root}, package, req, prepared("nativescript"))
                repeated = observation.native_owner({"extensions": root}, package, req,
                                                    prepared("nativescript"), actual)
            self.assertEqual(actual["instance"], snapshot["widgetInstances"][0])
            self.assertEqual(repeated["instance"], actual["instance"])
            self.assertNotIn("isDefault", actual["instance"])
            self.assertNotIn("entityID", actual["instance"])
            self.assertEqual(actual["identity"]["variantID"], "default")

    def test_native_owner_rejects_wrong_instance_template_and_changed_continuity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            req, package, snapshot = scriptwidget_owner_documents(root)
            publish_scriptwidget_owner_snapshot(root, snapshot)
            with patch.object(observation.time, "time", return_value=NOW):
                accepted = observation.native_owner({"extensions": root}, package, req, prepared("nativescript"))
            for defect in ("instance-name", "variant", "generation", "template-name", "template-family",
                           "template-owner", "changed-instance"):
                changed = copy.deepcopy(snapshot)
                if defect == "instance-name":
                    changed["widgetInstances"][0]["displayName"] = req["fixtureTitle"]
                elif defect == "variant":
                    changed["widgetInstances"][0]["identity"]["variantID"] = "another-variant"
                elif defect == "generation":
                    changed["widgetInstances"][0]["identity"]["generation"] = 2
                elif defect == "template-name":
                    changed["widgets"][0]["displayName"] = "Another fixture · Default"
                elif defect == "template-family":
                    changed["widgets"][0]["family"] = "systemSmall"
                elif defect == "template-owner":
                    changed["widgets"][0]["identity"]["installedPackageID"] = "another-install"
                else:
                    changed["widgetInstances"][0]["settings"] = {"changed": {"type": "bool", "value": True}}
                publish_scriptwidget_owner_snapshot(root, changed)
                with self.subTest(defect=defect), patch.object(observation.time, "time", return_value=NOW):
                    with self.assertRaises(observation.shared.ObservationError):
                        observation.native_owner({"extensions": root}, package, req,
                                                 prepared("nativescript"), accepted)

    def test_actual_authored_call_shapes_keep_two_ids_and_isolated_update_end(self):
        for engine in ("expo", "nativescript"):
            with self.subTest(engine=engine):
                value = self.validate(prepared(engine))
                for next_value in (
                    lambda prior: start(prior, "A", "real-A"),
                    lambda prior: listing(prior, ["real-A"]),
                    lambda prior: start(prior, "B", "real-B"),
                    lambda prior: listing(prior, ["real-B", "real-A"]),
                    lambda prior: revised(prior, "A"),
                    lambda prior: listing(prior, ["real-A", "real-B"]),
                    lambda prior: revised(prior, "A", end=True),
                    lambda prior: listing(prior, ["real-B"]),
                    lambda prior: revised(prior, "B", end=True),
                    lambda prior: listing(prior, []),
                ):
                    value = self.validate(next_value(value), value)
                self.assertEqual(value["slots"]["A"]["submittedRevision"], 1)
                self.assertEqual(value["slots"]["B"]["submittedRevision"], 0)
                self.assertEqual(observation.desired_ids(value), [])
                self.assertEqual(len(value["observations"]), 11)

    def test_private_identity_and_immutable_native_prefix_are_required(self):
        first = prepared("expo")
        for key, wrong in (("runUUID", "foreign"), ("engine", "nativescript"), ("appID", "another.app"), ("schemaVersion", True)):
            changed = copy.deepcopy(first); changed[key] = wrong
            with self.subTest(key=key), self.assertRaises(observation.shared.ObservationError):
                self.validate(changed)
        next_value = start(first, "A", "real-A")
        next_value["observations"][0]["calls"][0]["result"] = {"exists": True}
        with self.assertRaises(observation.shared.ObservationError):
            self.validate(next_value, first)
        req = request(); identity = observation.request_identity(req)
        req.update(phase="activity-lifecycle-operation", operation=tap("start-a", 2), sourceSHA="b" * 40)
        seen = {RUN: {"identity": identity, "directory": "/actual/exchange",
                     "inputs": {"value": {"attemptID": RUN, "sourceSHA": "a" * 40}}}}
        with patch.object(observation.shared, "product_roots") as no_io:
            with self.assertRaises(observation.shared.ObservationError):
                observation.observe_case(None, req, Path("/actual/exchange"), Path("/evidence"), seen)
            no_io.assert_not_called()

    def test_reused_id_cross_slot_update_and_rejected_call_are_not_success(self):
        first = start(prepared("expo"), "A", "real-A")
        same = start(first, "B", "real-A")
        with self.assertRaises(observation.shared.ObservationError):
            self.validate(same, first)
        both = start(first, "B", "real-B")
        changed = revised(both, "A"); changed["slots"]["B"]["submittedRevision"] = 1
        with self.assertRaises(observation.shared.ObservationError):
            self.validate(changed, both)
        changed = revised(both, "A"); changed["observations"][-1]["calls"][-1]["outcome"] = "rejected"
        with self.assertRaises(observation.shared.ObservationError):
            self.validate(changed, both)

    def test_end_return_does_not_rewrite_list_or_accept_a_foreign_id(self):
        both = listing(start(start(prepared("nativescript"), "A", "real-A"), "B", "real-B"), ["real-A", "real-B"])
        ended = self.validate(revised(both, "A", end=True), both)
        self.assertEqual(ended["lastObservedIDs"], ["real-A", "real-B"])
        self.assertEqual(observation.desired_ids(ended), ["real-B"])
        for identifiers in (["real-B", "foreign"], ["real-B", "real-B"]):
            with self.subTest(ids=identifiers), self.assertRaises(observation.shared.ObservationError):
                self.validate(listing(ended, identifiers), ended)
        forged = revised(both, "A", end=True); forged["lastObservedIDs"] = ["real-B"]
        with self.assertRaises(observation.shared.ObservationError):
            self.validate(forged, both)

    def test_seven_capture_contracts_admit_actual_type_values_without_assuming_types(self):
        with patch.object(observation.time, "time", return_value=NOW):
            for index in range(7):
                row = capture(index)
                self.assertEqual(observation.presentation(row, request(), index, START), row)

    def test_system_evidence_rejects_wrong_window_time_bounds_missing_region_and_empty_context(self):
        for defect in ("window", "before", "bounds", "missing", "gesture", "ended-visible", "empty-context"):
            index = 6 if defect in ("ended-visible", "empty-context") else 0
            row = capture(index)
            if defect == "window":
                next(iter(row["elements"].values()))["window"]["owner"] = "another.application"
            elif defect == "before":
                row["requestedAt"] = "2027-01-15T07:59:59.999Z"
            elif defect == "bounds":
                next(iter(row["elements"].values()))["frame"] = [399, 30, 100, 20]
            elif defect == "missing":
                row["elements"].pop(next(iter(row["elements"])))
            elif defect == "gesture":
                row["gesture"]["kind"] = "assumed-expanded"
            elif defect == "ended-visible":
                row["visibleOwnedMarkers"] = [observation.marker(RUN, "A", "banner", 1)]
            else:
                row["emptyBannerContextWitnesses"] = []
            with self.subTest(defect=defect), patch.object(observation.time, "time", return_value=NOW):
                with self.assertRaises(observation.shared.ObservationError):
                    observation.presentation(row, request(), index, START)

    def test_exact_installed_iphone_runtime_and_distinct_build_profiles_are_required(self):
        device = {"identifier": observation.TYPE, "productFamily": "iPhone", "name": "iPhone 16 Pro"}
        runtime = {"identifier": observation.RUNTIME, "isAvailable": True, "version": "27.2",
                   "buildversion": observation.RUNTIME_BUILD, "supportedDeviceTypes": [device]}
        for sdk, xcode in (("27.0", "Xcode 27.0\nBuild version 27A266a\n"),
                           ("27.2", "Xcode 27.2\nBuild version 27B52\n")):
            self.assertEqual(observation.admit_device(sdk, runtime, [device], xcode)[0], device)
        for defect in ("runtime", "build", "model", "profile", "available"):
            changed, offered, xcode = copy.deepcopy(runtime), [copy.deepcopy(device)], "Xcode 27.2\nBuild version 27B52\n"
            if defect == "runtime": changed["identifier"] = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
            elif defect == "build": changed["buildversion"] = "24B8118"
            elif defect == "model": offered[0]["identifier"] = "another.model"
            elif defect == "profile": xcode = "Xcode 27.0\nBuild version 27A266a\n"
            else: changed["isAvailable"] = False
            with self.subTest(defect=defect), self.assertRaises(observation.shared.ObservationError):
                observation.admit_device("27.2", changed, offered, xcode)

    def test_actual_window_path_accepts_double_separator_and_rejects_foreign_or_escape(self):
        with tempfile.TemporaryDirectory() as temporary:
            data = Path(temporary)
            req = request("nativescript")
            path = data / "Library/Application Support/Hanlin/MiniApps" / req["fixtureAppID"] / "Windows/own-window/State/activity-lifecycle.json"
            path.parent.mkdir(parents=True)
            value = prepared("nativescript")
            value["storage"].update(ownerWindowID="own-window", literalStatePath=str(path.parent) + "//activity-lifecycle.json")
            path.write_text(json.dumps(value))
            self.assertEqual(observation.private_journal({"data": data}, {"identity": {}}, req)["path"], str(path))
            for defect in ("owner", "escape", "foreign-path"):
                changed = copy.deepcopy(value)
                if defect == "owner": changed["storage"]["ownerWindowID"] = "another-window"
                elif defect == "escape": changed["storage"]["literalStatePath"] = str(path.parent) + "/../State/activity-lifecycle.json"
                else: changed["storage"]["literalStatePath"] = "/another/container/State/activity-lifecycle.json"
                path.write_text(json.dumps(changed))
                with self.subTest(defect=defect), self.assertRaises(observation.shared.ObservationError):
                    observation.private_journal({"data": data}, {"identity": {}}, req)


if __name__ == "__main__":
    unittest.main()
