"""Pure negative controls for the original OS observer; never native/OS proof."""
from pathlib import Path
import copy
import datetime
import io
import json
import math
import os
import struct
import sys
import tempfile
import time
import unittest
import uuid
import zipfile
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import observe_share_translation_surfaces as observer
import observe_shortcut_surfaces as common


def encoded(value):
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
        return {"type": "array", "value": [encoded(item) for item in value]}
    return {"type": "object", "value": [{"key": key, "value": encoded(item)} for key, item in value.items()]}


def timestamp(seconds=None):
    return datetime.datetime.fromtimestamp(time.time() if seconds is None else seconds,
                                            datetime.timezone.utc).isoformat(timespec="microseconds")


def request(engine="expo", surface="share"):
    now = time.time()
    return {"schema": 1, "runID": str(uuid.uuid4()), "engine": engine, "surface": surface,
            "fixtureAppID": "hanlin.surface." + engine,
            "fixtureTitle": "Surface Expo" if engine == "expo" else "Surface NativeScript",
            "challenge": "fresh-clock-random", "baselineCounter": 0,
            "startedAt": timestamp(now - 2), "observedAt": timestamp(now - 1),
            "phase": "prepared", "systemLaunchObserved": False, "visibleStateBefore": "actual UI text"}


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n")


def native_example(engine="expo", surface="share"):
    req = request(engine, surface)
    native_id = str(uuid.uuid4())
    identity = {"installedPackageID": "installed-test", "packageID": req["fixtureAppID"],
                "generation": 7, "entrypointID": "surface-" + surface, "variantID": "default"}
    now = time.time()
    prepared_path = "/private/data/Library/Application Support/Hanlin/MiniApps/" + req["fixtureAppID"]
    prepared_path += "/Windows/prepared-window/State/surface-proof.json" if engine == "nativescript" else "/State/surface-proof.json"
    proof_path = prepared_path.replace("prepared-window", "new-share-window") if engine == "nativescript" and surface == "share" else prepared_path
    payload = {"shareBatchID": native_id, "items": [{"id": str(uuid.uuid4()), "ordinal": 0, "kind": "text", "typeIdentifier": "public.text", "text": "selected"}]} if surface == "share" else {"query": "exact fresh Safari text", "source": "translationUI"}
    batch = {"batchID": native_id, "createdAtMilliseconds": now * 1000} if surface == "share" else None
    nonce = "actual-native-nonce"
    result = {"schemaVersion": 1, "appID": req["fixtureAppID"], "action": "surface.run", "status": "completed",
              "challenge": req["challenge"], "counter": 1, "nonce": nonce, "request": payload,
              "requestedSurface": "external" if batch else "translationUI", "startedAt": timestamp(now),
              "finishedAt": timestamp(now + .01), "requestID": native_id if engine == "expo" else nonce,
              "requestIDOrigin": "host-invocation" if engine == "expo" else "javascript-handler", "receipts": []}
    for kind in common.ENGINES:
        marker = ":".join((req["fixtureAppID"], req["challenge"], nonce, "1", kind, "42"))
        receipt = {"executionID": str(uuid.uuid4()), "durationMilliseconds": 1,
                   "didTimeOut": False, "wasCancelled": False, "outputWasTruncated": False, "exitCode": 0}
        receipt["value" if kind == "javaScriptCore" else "stdout"] = marker
        result["receipts"].append({"kind": kind, "marker": marker, "receipt": receipt})
    if engine == "nativescript":
        window = "new-share-window" if batch else "prepared-window"
        result["presentationSamples"] = [{"windowID": window, "statePath": proof_path,
                                            "executionMode": "foreground", "attached": True}]
    invocation = {"identity": identity, "entityID": "surface.run", "continueInForeground": True,
                  "parameters": encoded({"shareBatchID": native_id} if batch else payload)}
    if batch:
        invocation["delivery"] = {"schemaVersion": 1, "appID": req["fixtureAppID"], "source": "share",
                                  "expectedResult": "value", "expiresAt": now * 1000 + 86400000,
                                  "userGesturePresent": True, "canPresentUI": False,
                                  "idempotent": False, "maximumAttempts": 1}
    row = {"id": native_id, "createdAt": now * 1000, "invocation": invocation,
           "receipt": {"invocationID": native_id, "status": "succeeded", "failure": None,
                       "cancellationRequested": False, "leaseID": None, "leaseExpiresAt": None,
                       "attempt": 1, "value": encoded(result)}}
    document = {"path": "/private/group/ResumeQueue/Receipts/" + native_id + ".json", "sha256": "a" * 64, "value": row}
    proof = {"path": proof_path, "sha256": "b" * 64,
             "value": {"schemaVersion": 1, "appID": req["fixtureAppID"], "challenge": req["challenge"],
                       "counter": 1, "lastResult": result}}
    case = {"baselineIDs": set(), "preparedAt": common._epoch_milliseconds(req["observedAt"]),
            "facts": {"identity": identity}, "prepared": {"path": prepared_path}}
    return req, case, {native_id: document}, [proof], payload, batch


class ShareTranslationObserverTests(unittest.TestCase):
    def accepted(self, example):
        return observer.terminal_result(*example)

    def rejected(self, call):
        with self.assertRaises((common.ObservationError, ValueError, KeyError, TypeError)):
            call()

    def test_all_four_actual_payload_routes_and_private_windows_are_admitted(self):
        for engine in ("expo", "nativescript"):
            for surface in ("share", "translation"):
                with self.subTest(engine=engine, surface=surface):
                    result = self.accepted(native_example(engine, surface))
                    self.assertEqual(result["status"], "EXECUTED_PASS")
                    self.assertEqual(result["engines"], list(common.CANONICAL_ENGINES))
        # The prior foreground owner may use app-root State. The new Share
        # invocation must still prove its own distinct actual window storage.
        example = native_example("nativescript", "share")
        example[1]["prepared"]["path"] = example[1]["prepared"]["path"].replace("/Windows/prepared-window", "")
        self.assertEqual(self.accepted(example)["status"], "EXECUTED_PASS")

    def test_native_pending_missing_and_prior_commands_never_pass(self):
        for status in ("queued", "running"):
            example = native_example()
            next(iter(example[2].values()))["value"]["receipt"]["status"] = status
            self.assertIsNone(self.accepted(example))
        example = native_example()
        example[1]["baselineIDs"].update(example[2])
        self.assertIsNone(self.accepted(example))
        self.assertIsNone(self.accepted((example[0], example[1], {}, *example[3:])))

    def test_canonical_share_identity_date_delivery_and_resolved_payload_are_required(self):
        for mutate in (
            lambda row: row.update(createdAt=row["createdAt"] + 3),
            lambda row: row["invocation"]["delivery"].update(source="shortcuts"),
            lambda row: row["invocation"]["delivery"].update(canPresentUI=True),
            lambda row: row["invocation"]["delivery"].update(expiresAt=row["createdAt"] + 3),
            lambda row: row["invocation"]["delivery"].update(idempotent=True),
            lambda row: row["invocation"]["delivery"].update(maximumAttempts=True),
            lambda row: row["invocation"]["delivery"].update(widgetOrigin={"identity": "other"}),
            lambda row: row["receipt"].update(attempt=True),
            lambda row: row["receipt"].update(leaseID="still-owned"),
            lambda row: row["receipt"].update(status="cancelled"),
        ):
            example = native_example()
            mutate(next(iter(example[2].values()))["value"])
            self.rejected(lambda: self.accepted(example))
        example = native_example()
        result = copy.deepcopy(example[3][0]["value"]["lastResult"])
        result["request"] = {"shareBatchID": example[5]["batchID"]}
        next(iter(example[2].values()))["value"]["receipt"]["value"] = encoded(result)
        example[3][0]["value"]["lastResult"] = result
        self.rejected(lambda: self.accepted(example))

    def test_translation_cannot_invent_delivery_or_coerce_query_types(self):
        example = native_example("expo", "translation")
        next(iter(example[2].values()))["value"]["invocation"]["delivery"] = {"source": "translation"}
        self.rejected(lambda: self.accepted(example))
        for query in (42, True, None):
            example = native_example("expo", "translation")
            next(iter(example[2].values()))["value"]["invocation"]["parameters"] = encoded({"query": query, "source": "translationUI"})
            self.assertIsNone(self.accepted(example))

    def test_wrong_or_missing_runtime_receipt_and_self_consistent_wrong_result_fail(self):
        for mutation in ("missing", "marker", "timeout", "duplicate-execution", "bool-counter", "wrong-route"):
            example = native_example()
            result = example[3][0]["value"]["lastResult"]
            if mutation == "missing": result["receipts"].pop()
            if mutation == "marker": result["receipts"][0]["receipt"]["stdout"] = "unrelated"
            if mutation == "timeout": result["receipts"][0]["receipt"]["didTimeOut"] = True
            if mutation == "duplicate-execution": result["receipts"][1]["receipt"]["executionID"] = result["receipts"][0]["receipt"]["executionID"]
            if mutation == "bool-counter": result["counter"] = True; example[3][0]["value"]["counter"] = True
            if mutation == "wrong-route": result["requestedSurface"] = "share"
            next(iter(example[2].values()))["value"]["receipt"]["value"] = encoded(result)
            self.rejected(lambda: self.accepted(example))

    def test_new_share_window_and_original_translation_owner_cannot_be_substituted(self):
        for surface in ("share", "translation"):
            for mutation in ("wrong-path", "wrong-sample", "detached", "duplicate-proof"):
                example = native_example("nativescript", surface)
                proof = example[3][0]
                result = proof["value"]["lastResult"]
                if mutation == "wrong-path":
                    new_path = example[1]["prepared"]["path"] if surface == "share" else proof["path"].replace("prepared-window", "replacement-window")
                    proof["path"] = new_path
                    result["presentationSamples"][0].update(statePath=new_path, windowID=Path(new_path).parts[-3])
                if mutation == "wrong-sample": result["presentationSamples"][0]["windowID"] = "sibling"
                if mutation == "detached": result["presentationSamples"][0]["attached"] = False
                if mutation == "duplicate-proof": example[3].append(copy.deepcopy(proof))
                next(iter(example[2].values()))["value"]["receipt"]["value"] = encoded(result)
                self.rejected(lambda: self.accepted(example))

    def batch_fixture(self, root, as_text=False):
        req = request("nativescript")
        seed = str(uuid.uuid4())
        expected = observer.expected_share_files(req, seed)
        batch_id = str(uuid.uuid4())
        batch_root = root / "HanlinMiniApps/v1/ShareInbox/Batches" / batch_id
        items = []
        for ordinal, item in enumerate(expected):
            item_id = str(uuid.uuid4())
            row = {"id": item_id.upper(), "ordinal": ordinal, "typeIdentifier": "public.text",
                   "name": item["name"], "content": "text" if as_text else "file"}
            if as_text:
                row["text"] = item["text"]
            else:
                row.update(file=item_id, bytes=item["bytes"], sha256=item["sha256"])
                path = batch_root / "Files" / item_id
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(item["text"])
            items.append(row)
        batch = {"schemaVersion": 1, "id": batch_id.upper(), "createdAt": time.time() - 978307200, "items": items}
        path = batch_root / "batch.json"
        write_json(path, batch)
        return req, expected, batch_id, path, batch

    def test_actual_share_files_and_exact_text_representations_use_foundation_epoch(self):
        for as_text in (False, True):
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                req, expected, batch_id, _, _ = self.batch_fixture(root, as_text)
                result = observer.observe_batch(root, batch_id, expected, common._epoch_milliseconds(req["observedAt"]))
                self.assertEqual(result["payload"]["shareBatchID"], batch_id)
                self.assertEqual(len(result["payload"]["items"]), 2)
                self.assertLess(abs(result["createdAtMilliseconds"] - time.time() * 1000), 1000)

    def test_share_rejected_extra_duplicate_tampered_and_stale_batches_fail(self):
        for mutation in ("rejected", "extra", "duplicate-id", "ordinal-bool", "date-epoch", "stale", "bytes", "link", "text-substitution"):
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                req, expected, batch_id, path, batch = self.batch_fixture(root)
                first = batch["items"][0]
                owned = path.parent / "Files" / first["file"]
                if mutation == "rejected": first.update(content="rejected", failure="providerFailed")
                if mutation == "extra": batch["items"].append(copy.deepcopy(first))
                if mutation == "duplicate-id": batch["items"][1]["id"] = first["id"]
                if mutation == "ordinal-bool": first["ordinal"] = False
                if mutation == "date-epoch": batch["createdAt"] = time.time()
                if mutation == "stale": batch["createdAt"] -= 20
                if mutation == "bytes": owned.write_text("different actual bytes")
                if mutation == "link":
                    sibling = root / "other.txt"; sibling.write_text(expected[0]["text"])
                    owned.unlink(); owned.symlink_to(sibling)
                if mutation == "text-substitution":
                    first.update(content="text", text="different")
                    for key in ("file", "bytes", "sha256"): first.pop(key)
                write_json(path, batch)
                self.rejected(lambda: observer.observe_batch(root, batch_id, expected, common._epoch_milliseconds(req["observedAt"])))

    def archive_fixture(self, root):
        data = root / "data"; data.mkdir()
        evidence = root / "evidence"; evidence.mkdir()
        identity = {"installedPackageID": "test-install", "packageID": "hanlin.surface.expo", "generation": 2,
                    "entrypointID": "surface-share", "variantID": "default"}
        source = {"script.json": b'{"hanlinAppID":"hanlin.surface.expo","hanlinRuntime":"hanlin-expo"}', "bundle.js": b"original handler"}
        archive = evidence / "original.hanlinExpo"
        with zipfile.ZipFile(archive, "w") as output:
            for name, value in source.items(): output.writestr(name, value)
        source_digest = common.digest(archive.read_bytes())
        files = [{"logicalPath": "source/" + name, "byteCount": len(raw), "sha256": common.digest(raw), "context": "app"}
                 for name, raw in sorted(source.items())]
        fingerprint = common.digest("\n".join(row["logicalPath"] + ":" + row["sha256"] for row in files).encode())
        record = {"schemaVersion": 1, "installedPackageID": "test-install", "packageID": identity["packageID"],
                  "activeGeneration": 2, "version": "1.0.0", "sourceDigest": source_digest, "artifactDigest": fingerprint}
        entry = {"enabled": True, "record": record, "entrypoints": [{"id": "surface-share"}], "manifest": {"name": "Surface Expo"}}
        catalog = {"value": {"packages": {"test-install": entry}}}
        generation = data / observer.INSTALLED / "packages/test-install/generations/2"
        metadata = {key: record[key] for key in ("packageID", "version", "sourceDigest", "artifactDigest")}
        metadata.update(entrypoints=entry["entrypoints"], manifest=entry["manifest"])
        artifact = {"schemaVersion": 1, "packageContentDigest": source_digest, "cacheFingerprint": fingerprint, "files": files}
        write_json(generation / "generation.json", metadata)
        write_json(generation / "artifact-manifest.json", artifact)
        for name, raw in source.items():
            path = generation / "source" / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(raw)
        return data, identity, catalog, {"path": str(archive), "sha256": source_digest}, evidence, generation

    def test_exact_original_archive_current_metadata_and_retained_source_are_bound(self):
        with tempfile.TemporaryDirectory() as temporary:
            args = self.archive_fixture(Path(temporary))
            result = observer.verify_installed_fixture_archive(*args[:5])
            self.assertEqual(result["sourceDigestBasis"], "SHA256 of original imported archiveData")
            self.assertEqual(len(result["installedSources"]), 2)

    def test_wrong_generation_digest_source_and_manifest_never_pass_archive_binding(self):
        for mutation in ("disabled", "schema-bool", "generation-bool", "wrong-source-digest", "changed-source", "changed-generation", "changed-artifact", "link-source"):
            with tempfile.TemporaryDirectory() as temporary:
                args = self.archive_fixture(Path(temporary))
                entry = args[2]["value"]["packages"]["test-install"]
                if mutation == "disabled": entry["enabled"] = False
                if mutation == "schema-bool": entry["record"]["schemaVersion"] = True
                if mutation == "generation-bool": args[1]["generation"] = True
                if mutation == "wrong-source-digest": entry["record"]["sourceDigest"] = "0" * 64
                if mutation == "changed-source": (args[5] / "source/bundle.js").write_text("edited")
                if mutation == "changed-generation":
                    path = args[5] / "generation.json"; value = json.loads(path.read_text()); value["manifest"] = {}; write_json(path, value)
                if mutation == "changed-artifact":
                    path = args[5] / "artifact-manifest.json"; value = json.loads(path.read_text()); value["files"][0]["byteCount"] = True; write_json(path, value)
                if mutation == "link-source":
                    path = args[5] / "source/bundle.js"; other = args[4] / "other"; other.write_bytes(path.read_bytes()); path.unlink(); path.symlink_to(other)
                self.rejected(lambda: observer.verify_installed_fixture_archive(*args[:5]))

    def test_safari_transport_requires_fresh_original_seed_hash_and_browser(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); req = request("expo", "translation"); seed = str(uuid.uuid4())
            expected = {"url": "http://localhost:49173/surfaces/" + seed + "/expo", "text": "fresh input", "htmlSHA256": "a" * 64}
            value = {"seed": seed, "translation": {"expo": expected}, "transportLog": str(root / "requests.jsonl")}
            row = {"path": "/surfaces/" + seed + "/expo", "status": 200, "bytes": 123, "sha256": "a" * 64,
                   "at": timestamp(time.time() - .5), "method": "GET", "userAgent": "Mozilla/5.0 AppleWebKit/605.1.15 Version/27.0 Safari/605.1.15"}
            req["observedAt"] = timestamp()
            case = {"preparedAt": time.time() * 1000 - 1000}
            write_json(root / "requests.jsonl", row)
            # JSONL contains one compact object per actual HTTP event.
            (root / "requests.jsonl").write_text(json.dumps(row) + "\n")
            self.assertEqual(len(observer.translation_transport(req, case, value, root)["requests"]), 1)
            for key, replacement in (("at", timestamp(time.time() - 30)), ("sha256", "b" * 64), ("method", "HEAD"),
                                     ("status", 404), ("userAgent", "Python urllib"), ("path", "/surfaces/other/expo")):
                changed = {**row, key: replacement}; (root / "requests.jsonl").write_text(json.dumps(changed) + "\n")
                self.rejected(lambda: observer.translation_transport(req, case, value, root))

    def test_share_input_response_cannot_forge_matching_but_wrong_challenge_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); data = root / "data"; data.mkdir(); evidence = root / "evidence"; evidence.mkdir()
            req = request("nativescript"); seed = str(uuid.uuid4()); output = evidence / req["runID"]; output.mkdir()
            response_root = evidence / "responses"; response_root.mkdir()
            value = {"seed": seed, "shareInputProducer": {"requestRoot": str(evidence), "responseRoot": str(response_root)}}
            case = {"prepared": {"sha256": "a" * 64}, "roots": {"data": data}, "output": output,
                    "facts": {"identity": {"installedPackageID": "installed-test", "packageID": req["fixtureAppID"],
                                           "generation": 7, "entrypointID": "surface-share", "variantID": "default"}}}
            case["producerRequest"] = observer.share_producer_request(req, case, value, evidence)
            expected = observer.expected_share_files(req, seed)
            folder = "HanlinSurfaceInputs-" + req["runID"]
            response = {**case["producerRequest"]["value"], "status": "STAGED_INPUTS_ONLY",
                        "producerRequestSHA256": case["producerRequest"]["sha256"],
                        "shareInputFolder": folder, "shareInputFiles": expected}
            for item in expected:
                path = data / "Documents" / folder / item["name"]; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(item["text"])
            response_path = response_root / (req["runID"] + ".json"); write_json(response_path, response)
            self.assertEqual(observer.staged_share_inputs(req, case, value, evidence)["files"], expected)
            for item in response["shareInputFiles"]:
                item["text"] = item["text"].replace(req["challenge"], "wrong-clock-random")
                item["bytes"] = len(item["text"].encode()); item["sha256"] = common.digest(item["text"].encode())
                (data / "Documents" / folder / item["name"]).write_text(item["text"])
            write_json(response_path, response)
            self.rejected(lambda: observer.staged_share_inputs(req, case, value, evidence))

    def test_polled_share_request_is_published_only_after_complete_atomic_write(self):
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary); req = request("nativescript"); output = evidence / req["runID"]; output.mkdir()
            case = {"prepared": {"sha256": "a" * 64}, "roots": {"data": Path("/actual/data")}, "output": output,
                    "facts": {"identity": {"installedPackageID": "installed-test", "packageID": req["fixtureAppID"],
                                           "generation": 7, "entrypointID": "surface-share", "variantID": "default"}}}
            value = {"seed": str(uuid.uuid4()), "shareInputProducer": {"requestRoot": str(evidence)}}
            original_replace = os.replace
            observed = []
            def publish(source, destination):
                self.assertEqual(destination, output / "share-input-request.json")
                self.assertFalse(destination.exists(), "Producer must never see a partial JSON document")
                complete = common.parse_json(source.read_bytes())
                self.assertEqual(complete["challenge"], req["challenge"])
                self.assertEqual(len(complete), 10)
                observed.append(complete)
                return original_replace(source, destination)
            with patch.object(observer.os, "replace", side_effect=publish):
                result = observer.share_producer_request(req, case, value, evidence)
            self.assertEqual(result["value"], observed[0])
            self.assertFalse((output / "share-input-request.json.observer-tmp").exists())
            self.rejected(lambda: observer.share_producer_request(req, case, value, evidence))

    def test_phase_request_identity_and_exchange_cannot_replace_prepared_case(self):
        req = request(); req["phase"] = "system-action-sent"
        fixed = {key: req.get(key) for key in observer.FIXED_REQUEST}
        case = {"kind": "originalShareTranslation", "directory": "/actual/exchange", "fixedRequest": fixed, "finished": True}
        with patch.object(observer, "input_document", return_value=({}, Path("/evidence"))):
            for key, replacement in (("challenge", "replacement-clock-random"), ("surface", "translation"), ("baselineCounter", True)):
                changed = {**req, key: replacement}
                self.rejected(lambda: observer.observe_case(None, changed, Path("/actual/exchange"), Path("/evidence"), {req["runID"]: case}, {}, {}))
            self.rejected(lambda: observer.observe_case(None, req, Path("/other/exchange"), Path("/evidence"), {req["runID"]: case}, {}, {}))

    def test_terminal_mcm_configuration_replacement_is_rejected(self):
        roots = {key: Path("/actual/" + key) for key in ("app", "data", "group", "extensions")}
        roots.update(configuration={"StorageNamespace": "HanlinMiniApps/v1"}, infoSHA256="a" * 64)
        args = type("Args", (), {"device": "actual-device", "bundle_id": "com.itorah.hanlinminiapps"})()
        for key in observer.ROOT_KEYS:
            current = copy.deepcopy(roots)
            current[key] = {} if key == "configuration" else "replaced"
            with patch.object(common, "product_roots", return_value=current):
                self.rejected(lambda: observer.same_roots(args, roots))


if __name__ == "__main__":
    unittest.main()
