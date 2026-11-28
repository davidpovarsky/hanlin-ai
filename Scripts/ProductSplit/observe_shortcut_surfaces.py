"""Read-only observer for the existing genuine system-surface XCTest exchange.

Only the UI test runner's identity/completion responses and the evidence output
are written. AppGroup catalogs, queues, grants, receipts and app state are read.
A response is never a replacement for XCTest's observed system UI action.
"""
from pathlib import Path
import argparse
import base64
import datetime
import hashlib
import json
import math
import os
import plistlib
import re
import signal
import stat
import struct
import subprocess
import time
import uuid

ENGINES = ("node", "typeScript", "localPython", "javaScriptCore", "shell")
CANONICAL_ENGINES = ("node", "typescript", "python", "javascript", "shell")
SYSTEM_APPS = {"shortcuts": "com.apple.shortcuts", "files": "com.apple.DocumentsApp",
               "safari": "com.apple.mobilesafari"}
MAX_OBSERVATION_BYTES = 16 * 1024 * 1024


class ObservationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ObservationError(message)


def _members(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON member: " + key)
        result[key] = value
    return result


def parse_json(data):
    return json.loads(data, object_pairs_hook=_members,
                      parse_constant=lambda value: (_ for _ in ()).throw(
                          ObservationError("Non-finite JSON number: " + value)))


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_document(path, trusted_root):
    """Reject links beneath the already-resolved OS container/evidence root."""
    require(not Path(trusted_root).is_symlink(), "The trusted observation root is a symbolic link")
    root = Path(trusted_root).resolve(strict=True)
    path = Path(path)
    require(path.is_absolute(), "Observation paths must be absolute")
    try:
        parts = path.relative_to(root).parts
    except ValueError as error:
        raise ObservationError("Observation path left its actual container") from error
    require(parts and all(p not in ("", ".", "..") for p in parts), "Invalid observation path")
    cursor = root
    for part in parts:
        cursor = cursor / part
        require(not cursor.is_symlink(), "A managed observation path is a symbolic link")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(fd)
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1,
                "Observation source must be one regular file")
        require(info.st_size <= MAX_OBSERVATION_BYTES, "Observation file exceeds the reader bound")
        with os.fdopen(fd, "rb", closefd=False) as stream:
            data = stream.read(MAX_OBSERVATION_BYTES + 1)
        require(len(data) <= MAX_OBSERVATION_BYTES, "Observation file changed beyond the reader bound")
    finally:
        os.close(fd)
    return {"path": str(path), "sha256": digest(data), "bytes": len(data),
            "value": parse_json(data)}


def decode_value(encoded):
    """Decode the existing HanlinValue Codable wire representation, not loose JSON."""
    require(isinstance(encoded, dict) and isinstance(encoded.get("type"), str),
            "A canonical HanlinValue is required")
    kind = encoded["type"]
    require(set(encoded) == ({"type"} if kind == "null" else {"type", "value"}),
            "Unexpected HanlinValue members")
    value = encoded.get("value")
    if kind == "null":
        return None
    if kind == "string":
        require(isinstance(value, str), "Invalid string value")
        return value
    if kind == "bool":
        require(type(value) is bool, "Invalid boolean value")
        return value
    if kind == "integer":
        require(isinstance(value, str) and re.fullmatch(r"0|-?[1-9][0-9]*", value) is not None,
                "Invalid canonical integer")
        number = int(value)
        require(-(2**63) <= number < 2**63, "Integer exceeds Int64")
        return number
    if kind == "number":
        require(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{16}", value) is not None,
                "Invalid binary64 value")
        number = struct.unpack(">d", bytes.fromhex(value))[0]
        require(math.isfinite(number), "Non-finite binary64 value")
        return number
    if kind == "array":
        require(isinstance(value, list), "Invalid array value")
        return [decode_value(item) for item in value]
    if kind == "object":
        require(isinstance(value, list), "Canonical object must retain explicit UTF-8 keys")
        result = {}
        for member in value:
            require(isinstance(member, dict) and set(member) == {"key", "value"}
                    and isinstance(member["key"], str) and member["key"] not in result,
                    "Invalid or duplicate canonical object member")
            result[member["key"]] = decode_value(member["value"])
        return result
    if kind == "data":
        require(isinstance(value, dict) and set(value) == {"base64url", "byteCount"}
                and isinstance(value["base64url"], str)
                and re.fullmatch(r"[A-Za-z0-9_-]*", value["base64url"]) is not None
                and type(value["byteCount"]) is int and value["byteCount"] >= 0,
                "Invalid canonical data")
        raw = base64.urlsafe_b64decode(value["base64url"] + "=" * (-len(value["base64url"]) % 4))
        require(len(raw) == value["byteCount"]
                and base64.urlsafe_b64encode(raw).decode().rstrip("=") == value["base64url"],
                "Canonical data identity differs")
        return raw
    raise ObservationError("Unsupported HanlinValue type: " + kind)


def equal_typed_json(left, right):
    """Compare decoded JSON recursively without Python's boolean/numeric coercion."""
    if type(left) is not type(right):
        return False
    if left is None:
        return True
    if type(left) in (bool, int, str):
        return left == right
    if type(left) is float:
        return math.isfinite(left) and math.isfinite(right) and left == right
    if type(left) is list:
        return len(left) == len(right) and all(
            equal_typed_json(a, b) for a, b in zip(left, right))
    if type(left) is dict:
        return (all(type(key) is str for key in left)
                and all(type(key) is str for key in right)
                and left.keys() == right.keys()
                and all(equal_typed_json(left[key], right[key]) for key in left))
    return False


def validate_request(request):
    require(isinstance(request, dict) and request.get("schema") == 1, "Unknown exchange schema")
    run_id = request.get("runID")
    require(isinstance(run_id, str) and str(uuid.UUID(run_id)) == run_id,
            "The UI run identity must be a lowercase UUID")
    require(request.get("engine") in ("expo", "nativescript"), "Unknown original fixture engine")
    require(request.get("fixtureAppID") == "hanlin.surface." + request["engine"],
            "Unexpected original fixture identity")
    require(request.get("surface") in ("shortcuts", "miniAppShortcut"),
            "This observer implements only the original Shortcuts exchange")
    challenge = request.get("challenge")
    require(isinstance(challenge, str) and re.fullmatch(r"[a-z0-9]+-[a-z0-9]+-[a-z0-9]+", challenge),
            "A fresh challenge from the actual fixture UI is required")
    require(type(request.get("baselineCounter")) is int and request["baselineCounter"] == 0,
            "The prepared private counter must be zero")
    if request["surface"] == "miniAppShortcut":
        require(type(request.get("expectedCanPresentUI")) is bool,
                "New Shortcuts execution mode must be explicit")
    return run_id


def snapshot_document(root):
    before = read_document(root / "commit.json", root)
    commit = before["value"]
    key = commit.get("snapshotHash")
    require(commit.get("version") == 1 and isinstance(key, str)
            and re.fullmatch(r"[0-9a-f]{64}", key), "Invalid actual snapshot commit")
    revision = read_document(root / "Revisions" / (key + ".json"), root)
    require(revision["sha256"] == key, "The actual committed snapshot hash differs")
    after = read_document(root / "commit.json", root)
    require(before["sha256"] == after["sha256"], "Snapshot changed during observation")
    envelope = revision["value"]
    require(isinstance(envelope, dict) and isinstance(envelope.get("snapshot"), dict),
            "Invalid snapshot envelope")
    return revision


def action_identity(request, snapshot):
    rows = [row for row in snapshot["value"]["snapshot"].get("intentEntities", [])
            if row.get("appID") == request["fixtureAppID"]
            and row.get("id") == "surface.run"
            and row.get("identity", {}).get("entrypointID") == "surface-intent"]
    require(len(rows) == 1, "Exactly one current published original surface action is required")
    row = rows[0]
    identity = row["identity"]
    require(set(identity) == {"installedPackageID", "packageID", "generation", "entrypointID", "variantID"},
            "Unexpected installed identity shape")
    require(all(isinstance(identity[key], str) and identity[key] for key in
                ("installedPackageID", "packageID", "entrypointID", "variantID"))
            and type(identity["generation"]) is int and identity["generation"] >= 0
            and isinstance(row.get("displayName"), str) and row["displayName"]
            and isinstance(row.get("hostActionHandler"), str) and row["hostActionHandler"],
            "The current action must retain its actual installed native handler")
    return {"identity": identity, "actionID": row["id"], "appID": row["appID"],
            "actionDisplayName": row["displayName"], "hostActionHandler": row["hostActionHandler"],
            "snapshotSHA256": snapshot["sha256"]}



def installed_catalog(data_root, identity):
    path = data_root / "Library" / "Application Support" / "Hanlin" / "ScriptingPlatform" / "Installed" / "registry" / "catalog.json"
    document = read_document(path, data_root)
    catalog = document["value"]
    require(catalog.get("schemaVersion") == 1 and type(catalog.get("revision")) is int,
            "The actual primary installed catalog has an unknown schema")
    packages = catalog.get("packages")
    require(isinstance(packages, dict), "The actual primary catalog has no package registry")
    installed_id = identity["identity"]["installedPackageID"]
    entry = packages.get(installed_id)
    require(isinstance(entry, dict) and entry.get("enabled") is True,
            "The actual installed package is missing or disabled")
    record = entry.get("record", {})
    require(record.get("schemaVersion") == 1
            and record.get("installedPackageID") == installed_id
            and record.get("packageID") == identity["identity"]["packageID"]
            and type(record.get("activeGeneration")) is int
            and record["activeGeneration"] > 0
            and record["activeGeneration"] == identity["identity"]["generation"],
            "Published action identity differs from the current enabled installed generation")
    entrypoints = entry.get("entrypoints")
    require(isinstance(entrypoints, list), "The current installation has no prepared entrypoints")
    matches = [item for item in entrypoints if item.get("id") == identity["identity"]["entrypointID"]]
    require(len(matches) == 1, "The installed action entrypoint is missing or ambiguous")
    entrypoint = matches[0]
    # The original native analyzer deliberately marks declared actions partial.
    # Identity, executable context, runtime, policy and handler must still match.
    require(entrypoint.get("kind") == "appIntent"
            and entrypoint.get("compatibility") in ("supported", "partial")
            and "appIntent" in entrypoint.get("supportedContexts", [])
            and entrypoint.get("runtimeProfile") ==
                ("hanlin-expo" if identity["appID"].endswith(".expo") else "hanlin-nativescript")
            and entrypoint.get("runtimePolicyID") == "prepared-foreground-action-v1"
            and entrypoint.get("exportedSymbol") == identity["actionID"]
            and entrypoint.get("sourcePath") == identity["hostActionHandler"],
            "Published action is not the current supported prepared native entrypoint")
    return document


def queue_documents(root):
    found = {}
    for folder in (root / "ResumeQueue", root / "ResumeQueue" / "Receipts"):
        if not folder.exists():
            continue
        for path in sorted(folder.glob("*.json")):
            require(re.fullmatch(r"[0-9a-f-]{36}\.json", path.name), "Unexpected queue filename")
            document = read_document(path, root)
            row = document["value"]
            command_id = str(uuid.UUID(row.get("id", "")))
            require(path.stem == command_id, "Queue file and actual command identity differ")
            require(command_id not in found, "An invocation is duplicated in pending and terminal storage")
            receipt = row.get("receipt")
            require(isinstance(receipt, dict)
                    and str(uuid.UUID(receipt.get("invocationID", ""))) == command_id
                    and row.get("deliverySchemaVersion") == 1,
                    "A current canonical command and real receipt are required")
            found[command_id] = document
    return found


def proof_documents(data_root, app_id):
    base = data_root / "Library" / "Application Support" / "Hanlin" / "MiniApps" / app_id
    paths = [base / "State" / "surface-proof.json"]
    windows = base / "Windows"
    if windows.exists():
        require(not windows.is_symlink(), "Window storage is a symbolic link")
        paths += sorted(windows.glob("*/State/surface-proof.json"))
    return [read_document(path, data_root) for path in paths if path.exists()]


def prepared_proof(request, proofs):
    matches = [doc for doc in proofs if doc["value"].get("schemaVersion") == 1
               and doc["value"].get("appID") == request["fixtureAppID"]
               and doc["value"].get("challenge") == request["challenge"]
               and equal_typed_json(doc["value"].get("counter"), request["baselineCounter"])
               and doc["value"].get("lastResult") is None]
    require(len(matches) == 1, "Exactly one actual private state must match the fresh UI preparation")
    return matches[0]


def _epoch_milliseconds(value):
    require(isinstance(value, str), "Missing actual UI timestamp")
    parsed = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
    require(parsed.tzinfo is not None, "UI timestamp must include its timezone")
    return parsed.timestamp() * 1000


def _validate_five_receipts(result, request):
    require(result.get("schemaVersion") == 1 and result.get("appID") == request["fixtureAppID"]
            and result.get("action") == "surface.run" and result.get("status") == "completed"
            and result.get("challenge") == request["challenge"]
            and type(result.get("counter")) is int
            and result["counter"] == request["baselineCounter"] + 1,
            "The real result does not match this exact fresh system action")
    nonce = result.get("nonce")
    require(isinstance(nonce, str) and re.fullmatch(r"[a-z0-9]+-[a-z0-9]+-[a-z0-9]+", nonce),
            "Missing actual invocation nonce")
    require(result.get("requestedSurface") == request["surface"],
            "The actual request came from a different test route")
    receipts = result.get("receipts")
    require(isinstance(receipts, list) and [row.get("kind") for row in receipts] == list(ENGINES),
            "All five original runtime invocations, in order, are required")
    execution_ids = set()
    for row in receipts:
        kind = row["kind"]
        marker = ":".join((request["fixtureAppID"], request["challenge"], nonce,
                           str(request["baselineCounter"] + 1), kind, "42"))
        receipt = row.get("receipt")
        require(row.get("marker") == marker and isinstance(receipt, dict),
                "Runtime marker or full actual receipt is missing")
        execution_id = receipt.get("executionID")
        require(isinstance(execution_id, str) and execution_id and execution_id not in execution_ids,
                "Runtime execution identities must be real and distinct")
        execution_ids.add(execution_id)
        require(type(receipt.get("durationMilliseconds")) in (int, float)
                and math.isfinite(receipt["durationMilliseconds"])
                and receipt["durationMilliseconds"] >= 0
                and receipt.get("didTimeOut") is False and receipt.get("wasCancelled") is False
                and receipt.get("outputWasTruncated") is False
                and ("exitCode" not in receipt or receipt["exitCode"] == 0),
                "A runtime was failed, cancelled, timed out or truncated")
        if kind == "javaScriptCore":
            require(receipt.get("value") == marker, "Actual JavaScriptCore result differs")
        else:
            require(isinstance(receipt.get("stdout"), str)
                    and marker in receipt["stdout"].splitlines(), "Actual runtime stdout differs")
    return execution_ids


def completion(request, identity, baseline_ids, commands, proofs):
    """Return only a current terminal proof; pending/no correlated result stays pending."""
    validate_request(request)
    matches = []
    for command_id, document in commands.items():
        if command_id in baseline_ids:
            continue
        row = document["value"]
        invocation = row.get("invocation", {})
        if invocation.get("identity") != identity["identity"] or invocation.get("entityID") != "surface.run":
            continue
        parameters = decode_value(invocation.get("parameters"))
        if not isinstance(parameters, dict) or parameters.get("challenge") != request["challenge"]:
            continue
        require(parameters.get("surface") == request["surface"], "Actual input route differs")
        if request["surface"] == "miniAppShortcut":
            require(equal_typed_json(parameters, request.get("configuredInput")),
                    "Canonical command input differs from the exact UI-configured JSON types or values")
        require(type(row.get("createdAt")) in (int, float)
                and row["createdAt"] >= _epoch_milliseconds(request["startedAt"]),
                "Invocation predates this actual UI test")
        matches.append((command_id, document, invocation))
    require(len(matches) <= 1, "The same system challenge executed more than once")
    if not matches:
        return None
    command_id, document, invocation = matches[0]
    receipt = document["value"]["receipt"]
    if receipt.get("status") in ("queued", "running"):
        return None
    require(receipt.get("status") == "succeeded" and receipt.get("failure") is None
            and receipt.get("cancellationRequested") is False
            and receipt.get("leaseID") is None and receipt.get("leaseExpiresAt") is None
            and type(receipt.get("attempt")) is int and receipt["attempt"] == 1,
            "The actual invocation did not finish successfully exactly once")
    delivery = invocation.get("delivery")
    if request["surface"] == "miniAppShortcut":
        expected_ui = request["expectedCanPresentUI"]
        require(isinstance(delivery, dict) and delivery.get("schemaVersion") == 1
                and delivery.get("appID") == request["fixtureAppID"]
                and delivery.get("source") == "shortcuts" and delivery.get("userGesturePresent") is True
                and delivery.get("canPresentUI") is expected_ui
                and invocation.get("continueInForeground") is expected_ui,
                "The actual OS-selected execution mode or Shortcuts provenance differs")
    else:
        require(invocation.get("continueInForeground") is True,
                "The original legacy intent must continue in the foreground")
    result = decode_value(receipt.get("value"))
    if isinstance(result, str):
        result = parse_json(result)
    require(isinstance(result, dict), "The actual action returned no structured result")
    _validate_five_receipts(result, request)
    require(equal_typed_json(result.get("request"), decode_value(invocation["parameters"])),
            "The private handler payload differs from the canonical command input")
    if result.get("requestIDOrigin") == "host-invocation":
        require(str(uuid.UUID(result.get("requestID", ""))) == command_id,
                "The Expo callback belongs to another native invocation")
    else:
        require(request["engine"] == "nativescript"
                and result.get("requestIDOrigin") == "javascript-handler"
                and result.get("requestID") == result["nonce"],
                "The NativeScript handler nonce is not correlated")
    durable = [doc for doc in proofs if doc["value"].get("appID") == request["fixtureAppID"]
               and doc["value"].get("challenge") == request["challenge"]
               and equal_typed_json(doc["value"].get("counter"), result["counter"])
               and equal_typed_json(doc["value"].get("lastResult"), result)]
    require(len(durable) == 1, "The exact returned result must exist in one real private state file")
    proof = durable[0]
    if request["engine"] == "nativescript" and request["surface"] == "miniAppShortcut":
        samples = result.get("presentationSamples")
        require(isinstance(samples, list) and samples, "Actual NativeScript window observations are missing")
        for sample in samples:
            require(isinstance(sample, dict) and isinstance(sample.get("windowID"), str)
                    and sample.get("statePath") == proof["path"] and type(sample.get("attached")) is bool
                    and Path(proof["path"]).parts[-4:] ==
                        ("Windows", sample["windowID"], "State", "surface-proof.json"),
                    "Result did not remain in its own actual NativeScript window")
        require(len({row["windowID"] for row in samples}) == 1, "The invocation crossed window ownership")
        if request["expectedCanPresentUI"]:
            require(any(row["attached"] for row in samples), "Foreground native content was never attached")
        else:
            require(all(not row["attached"] and row.get("executionMode") == "headless-action"
                        for row in samples), "Background action presented native content")
    return {"schema": 1, "runID": request["runID"], "status": "EXECUTED_PASS",
            "challenge": request["challenge"], "counter": result["counter"],
            "engines": list(CANONICAL_ENGINES), "invocationID": command_id,
            "receipt": receipt, "command": document, "privateProof": proof,
            "identity": identity,
            "scope": "Correlated durable execution; XCTest separately must observe the real Shortcuts UI."}


def command(argv, timeout=20):
    result = subprocess.run(argv, capture_output=True, timeout=timeout)
    require(result.returncode == 0, "Read-only OS command failed: " +
            " ".join(argv) + ": " + result.stderr.decode(errors="replace")[-800:])
    return result.stdout


def os_container(device, bundle, kind):
    raw = command(["xcrun", "simctl", "get_app_container", device, bundle, kind])
    path = Path(raw.decode().strip()).resolve(strict=True)
    require(path.is_dir(), "The OS container is not an existing directory")
    return path


def product_roots(device, bundle):
    app = os_container(device, bundle, "app")
    info_bytes = (app / "Info.plist").read_bytes()
    info = plistlib.loads(info_bytes)
    require(info.get("CFBundleIdentifier") == bundle, "Actual installed bundle identity differs")
    configuration = info.get("HanlinExtensionHost", {})
    require(configuration.get("StorageNamespace") == "HanlinMiniApps/v1",
            "The installed app must explicitly declare the standalone product namespace")
    group = configuration.get("AppGroupIdentifier")
    require(isinstance(group, str) and group, "The installed app has no explicit AppGroup")
    root = os_container(device, bundle, group)
    for relative in ("HanlinMiniApps", "HanlinMiniApps/v1", "HanlinMiniApps/v1/ScriptingExtensions"):
        require(not (root / relative).is_symlink(), "A product storage component is a symbolic link")
    return {"app": app, "group": root, "data": os_container(device, bundle, "data"),
            "extensions": root / "HanlinMiniApps" / "v1" / "ScriptingExtensions",
            "configuration": configuration, "infoSHA256": digest(info_bytes)}


def system_app_observation(device, evidence):
    raw = command(["xcrun", "simctl", "listapps", device])
    (evidence / "installed-apps.plist").write_bytes(raw)
    converted = subprocess.run(["plutil", "-convert", "json", "-o", "-", "-"],
                               input=raw, capture_output=True, timeout=20)
    require(converted.returncode == 0, "The actual OS application inventory could not be parsed")
    apps = parse_json(converted.stdout)
    require(isinstance(apps, dict), "Invalid actual OS application inventory")
    observation = {"command": ["xcrun", "simctl", "listapps", device],
                   "sha256": digest(raw), "path": str(evidence / "installed-apps.plist")}
    return {name: {"bundleIdentifier": bundle, "available": bundle in apps,
                   "observation": observation} for name, bundle in SYSTEM_APPS.items()}



# Widget recovery stays in this original system-surface exchange. It observes
# only the exact authored Matrix source and never changes a production store.
def load_widget_fixture(path):
    import zipfile
    path = Path(path).resolve(strict=True)
    raw = path.read_bytes()
    with zipfile.ZipFile(path) as archive:
        require(set(archive.namelist()) == {"script.json", "package.json", "widget.jsx"},
                "Unexpected original Matrix archive members")
        manifest = parse_json(archive.read("script.json"))
        source = archive.read("widget.jsx")
    require(manifest.get("name") == "Interactive Widget Matrix"
            and manifest.get("kind") == "widget" and manifest.get("widgetEngine") == "expo",
            "The original Matrix widget input is required")
    return {"archiveSHA256": digest(raw), "sourceSHA256": digest(source),
            "metadata": manifest["hanlinWidget"], "entry": manifest["entry"]}


def validate_widget_request(request):
    require(type(request.get("schema")) is int and request["schema"] == 1
            and request.get("surface") == "widgetRecovery" and request.get("engine") == "expo",
            "Unknown original widget recovery exchange")
    run_id = request.get("runID")
    require(isinstance(run_id, str) and str(uuid.UUID(run_id)) == run_id,
            "Invalid widget UI run identity")
    require(request.get("instanceName") == "Recovery-" + run_id
            and request.get("fixtureTitle") == "Interactive Widget Matrix"
            and request.get("expectedFamily") == "systemMedium",
            "A fresh named Matrix instance and the medium-family case are required")
    return run_id


def widget_identity_digest(identity):
    fields = [identity["installedPackageID"], identity["packageID"],
              str(identity["generation"]), identity["entrypointID"], identity["variantID"]]
    require(all(isinstance(field, str) and field for field in fields),
            "Incomplete widget identity")
    material = "".join(str(len(field.encode("utf-8"))) + ":" + field for field in fields)
    return digest(material.encode("utf-8"))


def widget_artifact(root, identity, reference, expected):
    require(isinstance(expected, str) and re.fullmatch(r"[0-9a-f]{64}", expected),
            "Invalid widget artifact digest")
    exact = "Packages/{}/generations/{}/artifacts/{}".format(
        identity["installedPackageID"], identity["generation"], expected)
    require(reference == exact, "Widget artifact reference is not its exact current generation")
    result = read_document(root / reference, root)
    require(result["sha256"] == expected, "Widget artifact bytes do not match the committed digest")
    return result


def widget_facts(request, roots, fixture):
    document = snapshot_document(roots["extensions"])
    snapshot = document["value"]["snapshot"]
    matches = [item for item in snapshot.get("widgetInstances", [])
               if item.get("displayName") == request["instanceName"] and item.get("engine") == "expo"]
    require(len(matches) == 1, "The UI-created widget instance is missing or ambiguous")
    instance = matches[0]
    identity = instance["identity"]
    require(set(identity) == {"installedPackageID", "packageID", "generation", "entrypointID", "variantID"}
            and type(identity["generation"]) is int and identity["generation"] > 0
            and str(uuid.UUID(identity["variantID"])) == identity["variantID"],
            "The widget must be an actual fresh non-default instance")
    require(identity["installedPackageID"] not in snapshot.get("inactiveWidgetInstallations", []),
            "The installed widget has been disabled")
    templates = [item for item in snapshot.get("widgets", [])
                 if item.get("identity") == identity and item.get("engine") == "expo"]
    require(len(templates) == 8 and sorted(item["family"] for item in templates)
            == sorted(fixture["metadata"]["families"]),
            "The current installation did not publish all eight original families")
    require(all(type(item.get("validUntil")) in (int, float)
                and item["validUntil"] > time.time() * 1000 for item in templates),
            "The current widget publication has expired")
    widget = next(item for item in templates if item["family"] == request["expectedFamily"])
    descriptor = widget.get("payload", {}).get("expoDescriptor", {})
    program = widget_artifact(roots["extensions"], identity,
                              descriptor.get("layoutRef"), descriptor.get("layoutSHA256"))
    prepared = program["value"]
    require(prepared.get("engine") == "expo" and prepared.get("abiVersion") == 1
            and prepared.get("sourceSHA256") == fixture["sourceSHA256"]
            and prepared.get("families") == fixture["metadata"]["families"]
            and prepared.get("actions") == fixture["metadata"]["actions"],
            "The installed program differs from the exact authored Matrix source/actions")
    require(all(item.get("payload", {}).get("expoDescriptor", {}).get("layoutSHA256")
                == program["sha256"] for item in templates),
            "Family templates disagree about the current program")
    catalog_path = roots["data"] / "Library/Application Support/Hanlin/ScriptingPlatform/Installed/registry/catalog.json"
    catalog = read_document(catalog_path, roots["data"])
    registry = catalog["value"]
    require(registry.get("schemaVersion") == 1 and type(registry.get("revision")) is int,
            "Unknown current primary installed catalog")
    package = registry.get("packages", {}).get(identity["installedPackageID"], {})
    installed = package.get("record", {})
    require(package.get("enabled") is True and installed.get("schemaVersion") == 1
            and installed.get("installedPackageID") == identity["installedPackageID"]
            and installed.get("packageID") == identity["packageID"]
            and type(installed.get("activeGeneration")) is int
            and installed["activeGeneration"] == identity["generation"],
            "The widget does not belong to its current enabled installation")
    entries = [entry for entry in package.get("entrypoints", [])
               if entry.get("id") == identity["entrypointID"]]
    require(len(entries) == 1 and entries[0].get("kind") == "widget"
            and entries[0].get("widgetEngine") == "expo"
            and entries[0].get("compatibility") in ("supported", "partial")
            and entries[0].get("runtimeProfile") == "hanlin-expo"
            and "widget" in entries[0].get("supportedContexts", []),
            "The widget is not the current supported Expo entrypoint")
    states = [item for item in snapshot.get("widgetStates", [])
              if item.get("identity") == identity and item.get("engine") == "expo"]
    require(len(states) <= 1, "Duplicate state for the current widget instance")
    state = states[0] if states else {"revision": 0, "values": descriptor.get("props", {}),
                                     "committedNonces": []}
    require(type(state.get("revision")) is int and state["revision"] >= 0
            and (not states or state.get("artifactSHA256") == program["sha256"])
            and isinstance(state.get("committedNonces"), list)
            and len(set(state["committedNonces"])) == len(state["committedNonces"]),
            "Invalid current widget state or action nonce history")
    values = {key: decode_value(value) for key, value in state["values"].items()}
    retained = [item for item in snapshot.get("widgetLastSuccessfulRenders", [])
                if item.get("identity") == identity and item.get("engine") == "expo"
                and item.get("family") == request["expectedFamily"]
                and item.get("programSHA256") == program["sha256"]
                and item.get("settings") == instance["settings"]]
    require(len(retained) <= 1, "Duplicate last-good render for the exact configuration")
    cache = None
    if retained:
        record = retained[0]
        artifact = widget_artifact(roots["extensions"], identity,
                                   record["renderRef"], record["renderSHA256"])
        payload = artifact["value"]
        require(set(payload) == {"expo"} and set(payload["expo"]) == {"_0"},
                "The retained node is not the original Expo Codable case")
        cache = {"record": record, "artifact": artifact,
                 "node": decode_value(payload["expo"]["_0"])}
    others = [item for item in snapshot.get("widgetStates", []) if item.get("identity") != identity]
    others.sort(key=lambda item: json.dumps(item.get("identity"), sort_keys=True))
    return {"identity": identity, "identitySHA256": widget_identity_digest(identity),
            "instance": instance, "program": program, "catalog": catalog,
            "installedRecord": installed, "snapshotSHA256": document["sha256"],
            "state": state, "values": values, "cache": cache,
            "otherStatesSHA256": digest(json.dumps(others, sort_keys=True).encode())}


def widget_node_contains(node, value):
    if isinstance(node, dict):
        return any(widget_node_contains(child, value) for child in node.values())
    if isinstance(node, list):
        return any(widget_node_contains(child, value) for child in node)
    return type(node) is str and node == value


def require_widget_cache(facts, count):
    cache = facts["cache"]
    require(cache is not None and widget_node_contains(cache["node"], "Matrix count: " + str(count))
            and widget_node_contains(cache["node"], "failRefresh")
            and widget_node_contains(cache["node"], "recover"),
            "The verified current last-good node lacks its actual count or original recovery controls")
    return cache["record"]["renderSHA256"]


def require_widget_transition(facts, baseline, *, recovered):
    expected = 2 if recovered else 1
    values = facts["values"]
    require(facts["state"]["revision"] == baseline["state"]["revision"] + expected,
            "The native widget revision does not identify exactly the expected actions")
    count = values.get("count")
    require(type(count) in (int, float) and math.isfinite(count) and count == expected
            and values.get("fail") is (False if recovered else True),
            "The actual source callback did not commit the expected typed state")
    retry = values.get("retryAfter")
    require(type(retry) in (int, float) and math.isfinite(retry)
            and (retry == 0 if recovered else retry > 0),
            "A passive clock-expired render is not a successful Recover callback")
    before = set(baseline["state"]["committedNonces"])
    current = set(facts["state"]["committedNonces"])
    require(before <= current and len(current - before) == expected
            and facts["otherStatesSHA256"] == baseline["otherStatesSHA256"],
            "The actions did not retain exact nonce/other-instance ownership")


def widget_extension_executable(roots):
    found = []
    for extension in (roots["app"] / "PlugIns").glob("*.appex"):
        raw = (extension / "Info.plist").read_bytes()
        info = plistlib.loads(raw)
        if info.get("NSExtension", {}).get("NSExtensionPointIdentifier") != "com.apple.widgetkit-extension":
            continue
        configuration = info.get("HanlinExtensionHost", {})
        require(configuration.get("StorageNamespace") == roots["configuration"]["StorageNamespace"]
                and configuration.get("AppGroupIdentifier") == roots["configuration"]["AppGroupIdentifier"],
                "Installed widget extension does not share this product's explicit configuration")
        executable = info.get("CFBundleExecutable")
        require(isinstance(executable, str) and Path(executable).name == executable,
                "Invalid installed widget executable")
        found.append({"path": str((extension / executable).resolve(strict=True)),
                      "bundleIdentifier": info.get("CFBundleIdentifier"), "infoSHA256": digest(raw)})
    require(len(found) == 1, "The actual standalone WidgetKit extension is missing or ambiguous")
    return found[0]


def matching_widget_fallback(event, facts, extension, armed_at, retry_after):
    if event.get("subsystem") != "com.hanlin.ai" or event.get("category") != "WidgetRender":
        return False
    message = event.get("eventMessage", "")
    pattern = (r"widget_render_retained v=1 engine=expo identitySHA256=([0-9a-f]{64}) "
               r"generation=([0-9]+) family=([A-Za-z]+) programSHA256=([0-9a-f]{64}) "
               r"stateRevision=([0-9]+) renderSHA256=([0-9a-f]{64}) pid=([0-9]+)")
    match = re.fullmatch(pattern, message)
    if match is None or facts["cache"] is None:
        return False
    identity, generation, family, program, revision, rendered, pid = match.groups()
    stamp = _epoch_milliseconds(event.get("timestamp"))
    return (identity == facts["identitySHA256"] and int(generation) == facts["identity"]["generation"]
            and family == facts["cache"]["record"]["family"]
            and program == facts["program"]["sha256"] and int(revision) == facts["state"]["revision"]
            and rendered == facts["cache"]["record"]["renderSHA256"]
            and type(event.get("processID")) is int and event["processID"] == int(pid) > 0
            and isinstance(event.get("processImagePath"), str)
            and str(Path(event["processImagePath"]).resolve()) == extension["path"]
            and armed_at <= stamp < retry_after)


def widget_log_events(path, offset):
    require(path.is_file() and not path.is_symlink(), "Missing actual WidgetRender log capture")
    raw = path.read_bytes()
    require(len(raw) <= MAX_OBSERVATION_BYTES, "WidgetRender log capture exceeded its bound")
    events = []
    position = 0
    for line in raw.splitlines(keepends=True):
        start = position
        position += len(line)
        if start < offset or not line.endswith(b"\n") or not line.lstrip().startswith(b"{"):
            continue
        event = parse_json(line)
        require(isinstance(event, dict), "Invalid actual system log record")
        events.append(event)
    return events, {"path": str(path), "sha256": digest(raw), "bytes": len(raw)}


def observe_widget_case(args, request, directory, evidence, seen, fixture):
    run_id = validate_widget_request(request)
    require(fixture is not None, "The original runner must provide the exact Matrix source archive")
    phase = request.get("phase")
    case = seen.get(run_id)
    if case is None:
        require(phase == "widget-installed", "Observe the UI-created instance before any widget action")
        roots = product_roots(args.device, args.bundle_id)
        facts = widget_facts(request, roots, fixture)
        extension = widget_extension_executable(roots)
        output = evidence / run_id
        output.mkdir(exist_ok=False)
        log_path = output / "widget-render.ndjson"
        log_output = log_path.open("xb")
        argv = ["xcrun", "simctl", "spawn", args.device, "log", "stream", "--style", "ndjson",
                "--predicate", 'subsystem == "com.hanlin.ai" AND category == "WidgetRender"']
        try:
            process = subprocess.Popen(argv, stdout=log_output, stderr=subprocess.STDOUT)
        except BaseException:
            log_output.close()
            raise
        case = {"finished": False, "kind": "widgetRecovery", "phase": phase, "rootsAtPreparation": roots,
                "initial": facts, "extension": extension, "logProcess": process, "logOutput": log_output,
                "logPath": log_path, "logCommand": argv, "output": output}
        seen[run_id] = case
        response = {"schema": 1, "runID": run_id, "status": "READY",
                    "identity": facts["identity"], "instance": facts["instance"],
                    "source": fixture, "widgetExtension": extension, "programSHA256": facts["program"]["sha256"]}
        write_response(directory, "identity.json", response)
        (output / "identity.json").write_text(json.dumps(response, indent=2) + "\n")
        return
    roots = case["rootsAtPreparation"]
    if phase != case["phase"]:
        current = product_roots(args.device, args.bundle_id)
        require(all(current[key] == roots[key] for key in ("app", "data", "group")),
                "Actual product containers changed during widget acceptance")
        case["phase"] = phase
    require(case["logProcess"].poll() is None, "The real Simulator log stream ended unexpectedly")
    facts = widget_facts(request, roots, fixture)
    require(facts["identity"] == case["initial"]["identity"]
            and facts["instance"] == case["initial"]["instance"]
            and facts["program"]["sha256"] == case["initial"]["program"]["sha256"]
            and facts["installedRecord"] == case["initial"]["installedRecord"],
            "Widget installation, generation, program or configuration changed during the case")
    response = None
    name = None
    if phase == "widget-baseline" and "baseline" not in case:
        require(request.get("placedWidgetObserved") is True and request.get("visibleCount") == 0,
                "XCTest must observe the actual newly placed zero-count widget")
        require(facts["state"]["revision"] == 0 and not facts["state"]["committedNonces"]
                and facts["values"].get("count", 0) == 0 and facts["values"].get("fail", False) is False,
                "The fresh widget instance already has action state")
        require_widget_cache(facts, 0)
        case["baseline"] = facts
        name, response = "widget-baseline.json", {"status": "READY", "baseline": facts}
    elif phase == "before-widget-failure" and "armedAt" not in case:
        baseline = case["baseline"]
        require(facts["state"] == baseline["state"]
                and require_widget_cache(facts, 0) == require_widget_cache(baseline, 0),
                "The actual baseline changed before the failure action")
        case["armedAt"] = time.time() * 1000
        case["logOffsetAtArm"] = case["logPath"].stat().st_size
        name, response = "widget-armed.json", {"status": "READY", "armedAt": case["armedAt"]}
    elif phase == "widget-failure-requested" and "failure" not in case:
        require(request.get("failActionObserved") is True, "A genuine SpringBoard Fail refresh tap is required")
        baseline = case["baseline"]
        if facts["state"]["revision"] == baseline["state"]["revision"]:
            return
        require_widget_transition(facts, baseline, recovered=False)
        require(require_widget_cache(facts, 0) == require_widget_cache(baseline, 0),
                "The failed refresh did not retain the same verified last-good layout")
        events, provenance = widget_log_events(case["logPath"], case["logOffsetAtArm"])
        matching = [event for event in events if matching_widget_fallback(
            event, facts, case["extension"], case["armedAt"], facts["values"]["retryAfter"])]
        if not matching:
            return
        case["failure"] = facts
        case["fallback"] = matching[0]
        name, response = "widget-failure.json", {
            "status": "RETAINED_AFTER_REAL_FAILURE", "facts": facts,
            "event": matching[0], "log": provenance, "retryAfter": facts["values"]["retryAfter"]}
    elif phase == "before-widget-recovery" and "recoverArmedAt" not in case:
        failure = case["failure"]
        require(facts["state"] == failure["state"]
                and require_widget_cache(facts, 0) == require_widget_cache(case["baseline"], 0),
                "The layout recovered passively before the actual Recover action")
        require(time.time() * 1000 >= failure["values"]["retryAfter"],
                "The authored recovery boundary has not yet arrived")
        case["recoverArmedAt"] = time.time() * 1000
        name, response = "widget-recovery-ready.json", {"status": "READY"}
    elif phase == "widget-recovery-requested" and not case["finished"]:
        require(request.get("recoverActionObserved") is True and request.get("visibleRecoveredCount") == 2,
                "XCTest must observe the actual Recover tap and its new displayed count")
        baseline = case["baseline"]
        if facts["state"]["revision"] <= baseline["state"]["revision"] + 1:
            return
        require_widget_transition(facts, baseline, recovered=True)
        require(set(case["failure"]["state"]["committedNonces"]) < set(facts["state"]["committedNonces"]),
                "The actual Recover action did not append its own native nonce")
        require(require_widget_cache(facts, 2) != require_widget_cache(baseline, 0)
                and facts["cache"]["record"]["renderedAt"] >= case["recoverArmedAt"],
                "A fresh successful render after the Recover action is required")
        name, response = "completion.json", {"status": "EXECUTED_PASS", "identity": facts["identity"],
            "family": request["expectedFamily"], "sameGeneration": True,
            "failureEvent": case["fallback"], "failure": case["failure"], "recovered": facts,
            "scope": "Current state/cache/system-log correlation; genuine WidgetKit UI assertions remain in XCTest"}
    if response is not None:
        if name == "completion.json":
            current = product_roots(args.device, args.bundle_id)
            require(all(current[key] == roots[key]
                        for key in ("app", "data", "group", "extensions", "configuration", "infoSHA256")),
                    "Actual product containers or configuration changed before widget completion")
            require(widget_extension_executable(current) == case["extension"],
                    "The installed WidgetKit extension changed before widget completion")
        response.update(schema=1, runID=run_id)
        write_response(directory, name, response)
        (case["output"] / name).write_text(json.dumps(response, indent=2) + "\n")
        if name == "completion.json":
            case["finished"] = True


def close_widget_logs(seen):
    for case in seen.values():
        if case.get("kind") != "widgetRecovery":
            continue
        process = case["logProcess"]
        try:
            if process.poll() is None:
                process.terminate()
            code = process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            code = process.wait(timeout=5)
        finally:
            case["logOutput"].close()
        (case["output"] / "log-capture.json").write_text(json.dumps(
            {"argv": case["logCommand"], "exitCodeAfterOwnedStop": code,
             "scope": "Actual filtered Simulator system log; no synthetic event or production write"},
            indent=2) + "\n")


def write_response(directory, name, value):
    require(name in ("identity.json", "completion.json", "widget-baseline.json", "widget-armed.json",
                     "widget-failure.json", "widget-recovery-ready.json"),
            "Not an original test exchange response")
    require(directory.is_dir() and not directory.is_symlink(), "The UI run directory is missing")
    target = directory / name
    require(not target.exists(), "A prior response must not be overwritten")
    temporary = directory / (name + ".observer-tmp")
    with temporary.open("x") as stream:
        json.dump(value, stream, ensure_ascii=False, sort_keys=True, indent=2)
        stream.write("\n")
    os.replace(temporary, target)




def original_system_fixture(request, roots, identity, catalog, inputs):
    from observe_share_translation_surfaces import input_document, verify_installed_fixture_archive
    manifest, parent = input_document(inputs)
    return verify_installed_fixture_archive(
        roots["data"], identity["identity"], catalog,
        manifest["surfaceArchives"][request["engine"]], parent)


def load_system_inputs(path, evidence):
    """Bind the original runner's retained inputs; no OS success is inferred."""
    path = Path(path)
    parent = evidence.parent.resolve(strict=True)
    require(path.is_absolute() and path == parent / "system-surface-inputs.json",
            "The original system input manifest must be in this runner's evidence")
    document = read_document(path, parent)
    value = document["value"]
    require(type(value.get("schema")) is int and value["schema"] == 1,
            "Unknown original system input manifest")
    seed = value.get("seed")
    require(isinstance(seed, str) and str(uuid.UUID(seed)) == seed,
            "The original producer must retain a fresh input UUID")
    expected = {"expo": "SurfaceExpo.hanlinExpo", "nativescript": "SurfaceNativeScript.hanlinNativeScript"}
    archives, translations = value.get("surfaceArchives"), value.get("translation")
    require(isinstance(archives, dict) and set(archives) == set(expected)
            and isinstance(translations, dict) and set(translations) == set(expected),
            "The original two-engine input set is incomplete")
    for engine, name in expected.items():
        row = archives[engine]
        require(isinstance(row, dict) and set(row) == {"path", "sha256"}
                and row["path"] == str(parent / "shortcut-surface-fixtures" / name)
                and isinstance(row["sha256"], str) and re.fullmatch(r"[0-9a-f]{64}", row["sha256"]),
                "The authored archive must be the retained original producer output")
        page = translations[engine]
        require(isinstance(page, dict) and set(page) == {"url", "text", "htmlSHA256"}
                and page["url"] == "http://localhost:49173/surfaces/" + seed + "/" + engine
                and page["text"] == "Hanlin Translation input " + seed + " " + engine + " שלום עולם"
                and isinstance(page["htmlSHA256"], str) and re.fullmatch(r"[0-9a-f]{64}", page["htmlSHA256"]),
                "The genuine Safari input must bind this original producer run")
    require(value.get("transportLog") == str(parent / "system-surface-http-requests.jsonl")
            and value.get("shareInputProducer") == {
                "requestRoot": str(evidence), "responseRoot": str(parent / "system-surface-share-inputs")},
            "The original producer/transport must use only its owned evidence paths")
    return document


def observe(args, stopping=lambda: False):
    evidence = Path(args.output).resolve()
    roots = product_roots(args.device, args.bundle_id)
    require(all(not evidence.is_relative_to(roots[key]) for key in ("app", "data", "group")),
            "Observer evidence must be outside production containers")
    evidence.mkdir(parents=True, exist_ok=False)
    apps = system_app_observation(args.device, evidence)
    widget_fixture = load_widget_fixture(args.widget_fixture) if args.widget_fixture else None
    system_inputs = load_system_inputs(args.system_inputs, evidence) if args.system_inputs else None
    seen = {}
    last_error = None
    end = time.monotonic() + args.duration
    while time.monotonic() < end and not stopping():
        try:
            runner = os_container(args.device, args.runner_bundle_id, "data")
            exchange = runner / "Documents" / "HanlinSystemSurfaceObservation"
            active = read_document(exchange / "active.json", runner)["value"]
            run_id = active.get("runID", "")
            require(isinstance(run_id, str) and str(uuid.UUID(run_id)) == run_id,
                    "Invalid actual active UI run")
            directory = exchange / run_id
            request_document = read_document(directory / "request.json", runner)
            request = request_document["value"]
            require(request.get("runID") == run_id and request.get("engine") == active.get("engine")
                    and request.get("surface") == active.get("surface"),
                    "Active and per-run observation requests differ")
            if request.get("phase") in ("preparing", "finished"):
                time.sleep(0.25)
                continue
            if request.get("surface") == "studioEditor":
                from observe_studio_editor import observe_case
                observe_case(args, request, directory, evidence, seen)
                last_error = None
                time.sleep(0.25)
                continue
            if request.get("surface") == "studioGallery":
                from observe_studio_gallery import observe_case
                observe_case(args, request, directory, evidence, seen)
                last_error = None
                time.sleep(0.25)
                continue
            if request.get("surface") == "widgetLayout":
                from observe_widget_layout import observe_case
                observe_case(args, request, directory, evidence, seen, widget_fixture)
                last_error = None
                time.sleep(0.25)
                continue
            if request.get("surface") == "widgetFamilies":
                from observe_widget_families import observe_case
                observe_case(args, request, directory, evidence, seen, widget_fixture)
                last_error = None
                time.sleep(0.25)
                continue
            if request.get("surface") == "widgetVoiceOver":
                from observe_widget_voiceover import observe_case
                observe_case(args, request, directory, evidence, seen, widget_fixture)
                last_error = None
                time.sleep(0.25)
                continue
            if request.get("surface") == "widgetState":
                from observe_widget_state import observe_case
                observe_case(args, request, directory, evidence, seen, widget_fixture)
                last_error = None
                time.sleep(0.25)
                continue
            if request.get("surface") == "widgetRecovery":
                observe_widget_case(args, request, directory, evidence, seen, widget_fixture)
                last_error = None
                time.sleep(0.25)
                continue
            if request.get("surface") in ("widget", "liveActivity"):
                from observe_widget_action_surfaces import observe_case
                observe_case(args, request, directory, evidence, seen, system_inputs, apps)
                last_error = None
                time.sleep(0.25)
                continue
            if request.get("surface") in ("share", "translation"):
                from observe_share_translation_surfaces import observe_case
                observe_case(args, request, directory, evidence, seen, system_inputs, apps)
                last_error = None
                time.sleep(0.25)
                continue
            validate_request(request)
            if system_inputs is not None:
                require(type(request.get("schema")) is int and request["schema"] == 1,
                        "The original system request schema must be explicit")
            case = seen.get(run_id)
            if case is None:
                require(request.get("phase") == "prepared",
                        "Observer must bind post-XCTest containers before an action")
                roots = product_roots(args.device, args.bundle_id)
            else:
                if system_inputs is not None:
                    require(case["exchangeDirectory"] == str(directory) and equal_typed_json(
                        {key: request[key] for key in case["requestIdentity"]}, case["requestIdentity"]),
                        "The prepared original Shortcuts request changed")
                roots = case["rootsAtPreparation"]
                if request.get("phase") != case["phase"]:
                    actual_roots = product_roots(args.device, args.bundle_id)
                    require(all(actual_roots[key] == roots[key] for key in ("app", "data", "group")),
                            "Actual product MCM containers changed during the system attempt")
                    case["phase"] = request.get("phase")
            snapshot = snapshot_document(roots["extensions"])
            identity = action_identity(request, snapshot)
            catalog = installed_catalog(roots["data"], identity)
            identity["catalogSHA256"] = catalog["sha256"]
            identity["installedRecord"] = catalog["value"]["packages"][
                identity["identity"]["installedPackageID"]]["record"]
            commands = queue_documents(roots["extensions"])
            proofs = proof_documents(roots["data"], request["fixtureAppID"])
            if case is None:
                require(request.get("phase") == "prepared",
                        "Observer must bind the actual preparation before a system action")
                prepared = prepared_proof(request, proofs)
                response = {"schema": 1, "runID": run_id, "status": "READY",
                            **identity["identity"], **identity, "systemApps": apps,
                            "productConfiguration": roots["configuration"],
                            "productInfoSHA256": roots["infoSHA256"],
                            "actualContainers": {key: str(roots[key]) for key in ("app", "data", "group")},
                            "preparedProof": prepared, "catalog": catalog}
                installed_fixture = original_system_fixture(
                    request, roots, identity, catalog, system_inputs) if system_inputs is not None else None
                if installed_fixture is not None:
                    response["installedFixture"] = installed_fixture
                    response["inputManifest"] = system_inputs
                write_response(directory, "identity.json", response)
                case = {"identity": identity, "baselineIDs": set(commands), "finished": False,
                        "rootsAtPreparation": roots, "phase": request.get("phase")}
                if system_inputs is not None:
                    case["exchangeDirectory"] = str(directory)
                    case["requestIdentity"] = {key: request[key] for key in (
                        "schema", "runID", "engine", "surface", "fixtureAppID", "fixtureTitle",
                        "challenge", "baselineCounter", "startedAt", "visibleStateBefore")}
                    case["installedFixture"] = installed_fixture
                seen[run_id] = case
                case_evidence = evidence / run_id
                case_evidence.mkdir(exist_ok=False)
                (case_evidence / "identity.json").write_text(
                    json.dumps(response, ensure_ascii=False, sort_keys=True, indent=2) + "\n")
            require(identity["identity"] == case["identity"]["identity"]
                    and identity["hostActionHandler"] == case["identity"]["hostActionHandler"],
                    "Installed package generation/action changed during the system attempt")
            if request.get("phase") == "system-action-sent" and not case["finished"]:
                result = completion(request, identity, case["baselineIDs"], commands, proofs)
                if result is not None:
                    actual_roots = product_roots(args.device, args.bundle_id)
                    require(all(actual_roots[key] == roots[key] for key in ("app", "data", "group")),
                            "Actual product MCM containers changed before terminal observation")
                    require(request.get("systemLaunchObserved") is True,
                            "The real system action was not observed by XCTest")
                    if system_inputs is not None:
                        current_snapshot = snapshot_document(actual_roots["extensions"])
                        current_identity = action_identity(request, current_snapshot)
                        current_catalog = installed_catalog(actual_roots["data"], current_identity)
                        require(current_identity["identity"] == identity["identity"]
                                and current_identity["hostActionHandler"] == identity["hostActionHandler"],
                                "The original Shortcuts publication changed before completion")
                        current_fixture = original_system_fixture(
                            request, actual_roots, current_identity, current_catalog, system_inputs)
                        require(equal_typed_json(current_fixture, case["installedFixture"]),
                                "The actual original Shortcuts source changed before completion")
                        final_roots = product_roots(args.device, args.bundle_id)
                        require(all(final_roots[key] == roots[key] for key in
                                    ("app", "data", "group", "extensions", "configuration", "infoSHA256")),
                                "The actual original Shortcuts product changed at terminal observation")
                        result["installedFixture"] = current_fixture
                    write_response(directory, "completion.json", result)
                    (evidence / run_id / "completion.json").write_text(
                        json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2) + "\n")
                    case["finished"] = True
            last_error = None
        except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
            # Transient app writes/reinstallation may race a read. Preserve the
            # observation; never turn an unreadable/stale value into a PASS.
            message = type(error).__name__ + ": " + str(error)
            if message != last_error:
                with (evidence / "observations.jsonl").open("a") as stream:
                    stream.write(json.dumps({"at": time.time(), "error": message}) + "\n")
                last_error = message
        time.sleep(0.25)
    close_widget_logs(seen)
    (evidence / "observer.json").write_text(json.dumps({
        "status": "OBSERVER_FINISHED", "scope": "Read-only coordination, not an OS acceptance result",
        "runs": {key: {"completionWritten": value["finished"]} for key, value in seen.items()},
        "lastObservationError": last_error}, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--runner-bundle-id", required=True)
    parser.add_argument("--bundle-id", default="com.itorah.hanlinminiapps",
                        choices=["com.itorah.hanlinminiapps"])
    parser.add_argument("--output", required=True)
    parser.add_argument("--duration", type=float, default=1200)
    parser.add_argument("--widget-fixture", type=Path,
                        help="Exact original Matrix archive, for the separate widget recovery or state scopes")
    parser.add_argument("--widget-state-inputs", type=Path,
                        help="Original source/product attempt manifest, only for two-instance WidgetKit state acceptance")
    parser.add_argument("--widget-voiceover-inputs", type=Path,
                        help="Original source/product attempt manifest for the separate public VoiceOver widget pilot")
    parser.add_argument("--widget-layout-inputs", type=Path,
                        help="Original source/product attempt manifest for the separate real Medium control-layout pilot")
    parser.add_argument("--widget-families-inputs", type=Path,
                        help="Original source/product attempt manifest for four real Home Screen family and rotation cases")
    parser.add_argument("--system-inputs", type=Path,
                        help="Original runner input manifest, only for the original ten system-surface methods")
    parser.add_argument("--studio-inputs", type=Path,
                        help="Original runner ordinary source-folder input manifest, only for Studio editor acceptance")
    args = parser.parse_args()
    require(0 < args.duration <= 7200, "Observer lifetime must be bounded")
    require(args.runner_bundle_id.endswith(".xctrunner"), "An actual XCTest runner bundle is required")
    stopping = [False]
    signal.signal(signal.SIGTERM, lambda signum, frame: stopping.__setitem__(0, True))
    signal.signal(signal.SIGINT, lambda signum, frame: stopping.__setitem__(0, True))
    observe(args, stopping=lambda: stopping[0])


if __name__ == "__main__":
    main()
