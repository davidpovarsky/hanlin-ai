"""Pure contract controls for the additive real Widget component observer.

These synthetic records exercise admission/rejection only. They do not stand in
for native types, rendering, accessibility, a CLI execution or an OS test.
"""
from pathlib import Path
import copy
import datetime
import sys
import time
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Scripts/ProductSplit"))
import observe_widget_components as subject


def stamp(value):
    return datetime.datetime.fromtimestamp(value, datetime.timezone.utc).isoformat()


class WidgetComponentObserverTests(unittest.TestCase):
    def setUp(self):
        self.now = time.time()
        self.run = "00000000-0000-4000-8000-000000000001"
        self.action = "00000000-0000-4000-8000-000000000002"
        self.nonce = "00000000-0000-4000-8000-000000000003"
        self.request = {
            "schema": 1, "runID": self.run, "engine": "expo", "surface": "widgetComponents",
            "fixtureTitle": "Widget Components Pilot", "instanceName": "Components-systemLarge-" + self.run,
            "expectedFamily": "systemLarge", "sizeLabel": "Large", "priorOrientation": "portrait",
            "startedAt": stamp(self.now - 100),
            "test": "-[HanlinEntrypointSystemSurfaceUITests testMiniAppsLargeWidgetComponentsTrackActualNativeState]",
        }
        self.before = {
            "identity": {"variantID": self.run, "generation": 1},
            "instance": {"settings": {"name": "owned"}},
            "installedRecord": {"sourceDigest": "a" * 64},
            "program": {"sha256": "b" * 64}, "catalog": {"sha256": "c" * 64},
            "otherStatesSHA256": "d" * 64, "values": {},
            "state": {"revision": 0, "committedNonces": []}, "cache": None,
        }
        self.after = copy.deepcopy(self.before)
        self.after["values"] = {"count": 1.0}
        self.after["state"] = {"revision": 1, "committedNonces": [self.nonce]}
        # Literal independent examples. Types deliberately vary; the real UI
        # records the actual enum, rather than assuming a Gauge/Chart category.
        self.row = {
            "index": 0, "attachmentLabel": "widget-components-observation-0",
            "visibleComponentCount": 1, "hostTerminated": True, "orientation": "portrait",
            "screenFrame": [0, 0, 800, 1100], "widgetFrame": [20, 40, 400, 640],
            "window": {"owner": "com.apple.springboard", "matchingWindowCount": 1,
                       "identifier": "observed-window", "exists": True, "hittable": True,
                       "frame": [0, 0, 800, 1100]},
            "requestedAt": stamp(self.now - 45), "capturedAt": stamp(self.now - 43),
            "requestedUptime": 10.0, "capturedUptime": 12.0,
            "configuration": {"instanceName": self.request["instanceName"], "label": self.request["instanceName"],
                              "value": "", "frame": [20, 40, 400, 640],
                              "attachmentLabel": "widget-components-configuration-0",
                              "verifiedAt": stamp(self.now - 44), "verifiedUptime": 11.0},
            "components": {},
        }
        values = {
            "count": ("Components count: 0", "0", [30, 50, 180, 20]),
            "add": ("Add", "Count 0", [30, 80, 80, 30]),
            "progress": ("Progress count 0", "0 of 10", [30, 120, 300, 35]),
            "gauge": ("Gauge count 0", "0 of 10", [30, 170, 300, 40]),
            "chart": ("Chart count 0", "Count 0; Reference 10", [30, 220, 300, 60]),
            "symbol": ("Book count 0", "Outline book", [30, 300, 24, 24]),
            "link": ("Details count 0", "Count 0", [90, 300, 100, 24]),
        }
        for index, (name, (label, value, frame)) in enumerate(values.items(), 1):
            self.row["components"][name] = {
                "identifier": "hanlin-component-" + name, "label": label, "value": value,
                "elementType": "synthetic-observed-type-" + str(index), "elementTypeRaw": index,
                "exists": True, "hittable": True, "enabled": True, "frame": frame,
            }

    def changed_row(self):
        row = copy.deepcopy(self.row)
        row.update(index=1, attachmentLabel="widget-components-observation-1",
                   requestedAt=stamp(self.now - 25), capturedAt=stamp(self.now - 23),
                   requestedUptime=30.0, capturedUptime=32.0)
        row["configuration"].update(attachmentLabel="widget-components-configuration-1",
                                    verifiedAt=stamp(self.now - 24), verifiedUptime=31.0)
        labels = {
            "count": ("Components count: 1", "1"), "add": ("Add", "Count 1"),
            "progress": ("Progress count 1", "1 of 10"), "gauge": ("Gauge count 1", "1 of 10"),
            "chart": ("Chart count 1", "Count 1; Reference 10"),
            "symbol": ("Book count 1", "Filled book"), "link": ("Details count 1", "Count 1"),
        }
        for name, (label, value) in labels.items():
            row["components"][name].update(label=label, value=value)
        return row

    def cached(self, facts, row):
        result = copy.deepcopy(facts)
        result["cache"] = {
            "record": {"identity": copy.deepcopy(facts["identity"]), "engine": "expo", "family": "systemLarge",
                       "programSHA256": "b" * 64, "settings": {"name": "owned"},
                       "renderSHA256": "e" * 64, "renderedAt": (self.now - 42) * 1000},
            "artifact": {"sha256": "e" * 64},
            "node": {"children": [{"identifier": v["identifier"], "label": v["label"], "value": v["value"]}
                                  for v in row["components"].values()]},
        }
        return result

    def test_individual_components_and_real_zero_to_one_contract(self):
        subject.request_identity(self.request)
        admitted = subject.require_observation(self.row, self.request, self.before, 0, (self.now - 50) * 1000)
        self.assertEqual(admitted, self.row)
        updated = self.changed_row()
        subject.require_observation(updated, self.request, self.after, 1, (self.now - 26) * 1000, self.row)
        self.assertEqual(subject.require_transition(self.before, self.after), self.nonce)
        self.assertTrue(subject.fresh_component_cache(self.cached(self.before, self.row), (self.now - 50) * 1000))

    def test_missing_wrong_or_hidden_component_cannot_pass(self):
        alterations = (
            lambda r: r["components"].pop("gauge"),
            lambda r: r["components"]["chart"].update(identifier="hanlin-component-gauge"),
            lambda r: r["components"]["progress"].update(value="9 of 10"),
            lambda r: r["components"]["symbol"].update(label="Book count 1"),
            lambda r: r["components"]["link"].update(hittable=False),
            lambda r: r["components"]["add"].update(enabled=False),
            lambda r: r["components"]["gauge"].update(elementTypeRaw=None),
        )
        for change in alterations:
            row = copy.deepcopy(self.row); change(row)
            with self.subTest(change=change), self.assertRaises(subject.original.ObservationError):
                subject.require_components(row, self.before)

    def test_wrong_window_outside_frame_and_overlap_are_rejected(self):
        alterations = (
            lambda r: r["window"].update(owner="com.itorah.hanlinminiapps"),
            lambda r: r["window"].update(matchingWindowCount=2),
            lambda r: r["components"]["chart"].update(frame=[450, 220, 300, 60]),
            lambda r: r["components"]["gauge"].update(frame=r["components"]["progress"]["frame"]),
            lambda r: r.update(widgetFrame=r["screenFrame"]),
            lambda r: r.update(visibleComponentCount=2),
        )
        for change in alterations:
            row = copy.deepcopy(self.row); change(row)
            with self.subTest(change=change), self.assertRaises(subject.original.ObservationError):
                subject.require_components(row, self.before)

    def test_family_instance_selector_and_current_source_binding_are_exact(self):
        for key, value in (("expectedFamily", "systemMedium"), ("instanceName", "another"),
                           ("fixtureTitle", "Interactive Widget Matrix"), ("engine", "nativescript"),
                           ("test", "another-test]")):
            request = dict(self.request); request[key] = value
            with self.subTest(key=key), self.assertRaises(subject.original.ObservationError):
                subject.request_identity(request)
        roots = {key: key for key in subject.widget.ROOT_FIELDS}
        request = dict(self.request, phase="widget-components-placed", attemptID="attempt", sourceSHA="wrong-source")
        case = {"kind": "widgetComponents", "identity": subject.request_identity(self.request),
                "directory": "/owned/exchange", "roots": roots,
                "inputs": {"value": {"attemptID": "attempt", "sourceSHA": "a" * 40}}}
        with mock.patch.object(subject.original, "product_roots", return_value=roots), \
             self.assertRaises(subject.original.ObservationError):
            subject.observe_case(type("Args", (), {"device": "owned", "bundle_id": "owned"})(),
                                 request, Path("/owned/exchange"), Path("/evidence"), {self.run: case})

    def test_capture_and_configuration_must_follow_real_action(self):
        updated = self.changed_row()
        for change in (
            lambda r: r.update(requestedAt=stamp(self.now - 60)),
            lambda r: r["configuration"].update(instanceName="another"),
            lambda r: r["configuration"].update(frame=[21, 40, 400, 640]),
            lambda r: r.update(capturedUptime=29.0),
            lambda r: r["window"].update(identifier="another-window"),
        ):
            row = copy.deepcopy(updated); change(row)
            with self.subTest(change=change), self.assertRaises(subject.original.ObservationError):
                subject.require_observation(row, self.request, self.after, 1, (self.now - 26) * 1000, self.row)

    def test_render_requires_current_identity_family_and_post_placement_time(self):
        cached = self.cached(self.before, self.row)
        self.assertFalse(subject.fresh_component_cache(cached, (self.now - 40) * 1000))
        for key, value in (("identity", {"variantID": "another", "generation": 1}),
                           ("family", "systemMedium"), ("programSHA256", "f" * 64),
                           ("settings", {"name": "another"}), ("renderedAt", (self.now + 100) * 1000)):
            facts = copy.deepcopy(cached); facts["cache"]["record"][key] = value
            with self.subTest(key=key), self.assertRaises(subject.original.ObservationError):
                subject.fresh_component_cache(facts, (self.now - 50) * 1000)
        missing = copy.deepcopy(cached); missing["cache"]["node"]["children"].pop()
        self.assertFalse(subject.fresh_component_cache(missing, (self.now - 50) * 1000))
        stale = self.cached(self.after, self.row)
        self.assertFalse(subject.fresh_component_cache(stale, (self.now - 50) * 1000))

    def test_native_nonce_revision_and_values_cannot_be_substituted(self):
        for change in (
            lambda f: f["state"].update(revision=0),
            lambda f: f["state"].update(committedNonces=[]),
            lambda f: f["state"].update(committedNonces=[self.nonce, self.nonce]),
            lambda f: f["values"].update(count=2.0),
            lambda f: f["values"].update(unrelated=True),
            lambda f: f["identity"].update(generation=2),
            lambda f: f.update(otherStatesSHA256="f" * 64),
        ):
            facts = copy.deepcopy(self.after); change(facts)
            with self.subTest(change=change), self.assertRaises(subject.original.ObservationError):
                subject.require_transition(self.before, facts)

    def test_missing_owned_cleanup_or_real_orientation_restoration_cannot_pass(self):
        request = dict(self.request, unboundPlacementCreated=False)
        config = copy.deepcopy(self.changed_row()["configuration"])
        config.update(attachmentLabel="widget-components-cleanup-configuration",
                      verifiedAt=stamp(self.now - 20), verifiedUptime=40.0)
        request["cleanup"] = {"instanceName": self.request["instanceName"], "configuration": config,
                              "action": "Remove Widget", "confirmationLabel": "Remove",
                              "visibleComponentCountAfter": 0, "hostTerminated": True,
                              "removedAt": stamp(self.now - 19), "removedUptime": 41.0}
        request["orientationRestoration"] = {"priorOrientation": "portrait", "orientation": "portrait",
                                            "screenFrame": [0, 0, 800, 1100],
                                            "restoredAt": stamp(self.now - 18), "restoredUptime": 42.0}
        subject.require_cleanup(request, self.changed_row(), (self.now - 22) * 1000)
        for change in (
            lambda r: r["cleanup"].update(instanceName="another"),
            lambda r: r["cleanup"].update(visibleComponentCountAfter=1),
            lambda r: r["orientationRestoration"].update(orientation="landscapeLeft"),
            lambda r: r.update(cleanupFailure="actual cleanup error"),
        ):
            changed = copy.deepcopy(request); change(changed)
            with self.subTest(change=change), self.assertRaises(subject.original.ObservationError):
                subject.require_cleanup(changed, self.changed_row(), (self.now - 22) * 1000)


if __name__ == "__main__":
    unittest.main()
