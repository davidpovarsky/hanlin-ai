"""Read-only admission for the original Share and Translation XCTest cases.

The original UI performs every OS action. This leaf observes the current
MiniApps catalog, immutable ShareInbox, native queue/receipts and private state.
It writes only its own evidence and XCTest exchange responses. Ordinary Share
input files are produced by the original runner after the prepared handshake.
"""
from pathlib import Path, PurePosixPath
import io
import json
import math
import os
import re
import stat
import time
import uuid
import zipfile
from urllib.parse import urlsplit

import observe_shortcut_surfaces as shared

require = shared.require
equal = shared.equal_typed_json
UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
SHA = r"[0-9a-f]{64}"
ROOT_KEYS = ("app", "data", "group", "extensions", "configuration", "infoSHA256")
FIXED_REQUEST = ("schema", "runID", "engine", "surface", "fixtureAppID", "fixtureTitle",
                 "startedAt", "challenge", "baselineCounter", "visibleStateBefore")
INSTALLED = Path("Library/Application Support/Hanlin/ScriptingPlatform/Installed")


def raw_file(path, trusted_root, limit=shared.MAX_OBSERVATION_BYTES):
    """The shared JSON reader's containment rules, for actual non-JSON bytes."""
    root = Path(trusted_root)
    require(not root.is_symlink(), "The trusted byte root is a symbolic link")
    root = root.resolve(strict=True)
    path = Path(path)
    require(path.is_absolute(), "Observed byte paths must be absolute")
    try:
        parts = path.relative_to(root).parts
    except ValueError as error:
        raise shared.ObservationError("Observed bytes left their actual root") from error
    require(parts and all(part not in ("", ".", "..") for part in parts), "Invalid byte path")
    cursor = root
    for part in parts:
        cursor /= part
        require(not cursor.is_symlink(), "Observed byte path contains a symbolic link")
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(descriptor)
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and info.st_size <= limit,
                "Observed bytes must be one bounded regular file")
        with os.fdopen(descriptor, "rb", closefd=False) as stream:
            raw = stream.read(limit + 1)
        require(len(raw) <= limit, "Observed bytes exceeded the bound while reading")
    finally:
        os.close(descriptor)
    return {"path": str(path), "bytes": len(raw), "sha256": shared.digest(raw), "raw": raw}


def document_bytes(document):
    return {key: document[key] for key in ("path", "bytes", "sha256")}


def normalized_relative(value):
    require(isinstance(value, str) and value and "\\" not in value
            and not value.startswith("/") and "\x00" not in value
            and all(part not in ("", ".", "..") for part in value.split("/"))
            and str(PurePosixPath(value)) == value, "Non-canonical relative path")
    return value


def verify_installed_fixture_archive(data_root, identity, catalog, archive, evidence_root):
    """Bind exact producer ZIP -> sourceDigest -> generation -> actual source.

    PackageCenter.stage hashes imported archiveData, Bundler assigns that
    source.contentSHA256 to packageContentDigest and copies every source file.
    AtomicScriptStore commits it into generation.json and the primary record.
    This follows those source definitions; it does not substitute an artifact
    fingerprint or an assumed hash of decompressed ZIP members.
    """
    require(isinstance(archive, dict) and re.fullmatch(SHA, archive.get("sha256", "")),
            "The original producer archive is not hash-bound")
    source = raw_file(Path(archive["path"]), evidence_root, 128 * 1024 * 1024)
    require(source["sha256"] == archive["sha256"], "Produced archive bytes changed")
    installed_id = identity["installedPackageID"]
    require(normalized_relative(installed_id) == installed_id and "/" not in installed_id,
            "Invalid installed package directory identity")
    require(type(identity.get("generation")) is int and identity["generation"] > 0,
            "Invalid current installed generation")
    entry = catalog["value"]["packages"][installed_id]
    record = entry["record"]
    require(entry.get("enabled") is True and type(record.get("schemaVersion")) is int and record["schemaVersion"] == 1
            and record.get("installedPackageID") == installed_id
            and record.get("packageID") == identity["packageID"]
            and type(record.get("activeGeneration")) is int
            and record["activeGeneration"] == identity["generation"]
            and record.get("sourceDigest") == source["sha256"],
            "The current enabled package does not originate from this exact archive")
    generation = Path(data_root) / INSTALLED / "packages" / installed_id / "generations" / str(identity["generation"])
    metadata = shared.read_document(generation / "generation.json", data_root)
    artifact = shared.read_document(generation / "artifact-manifest.json", data_root)
    meta, manifest = metadata["value"], artifact["value"]
    require(all(equal(meta.get(key), record.get(key)) for key in
                ("packageID", "version", "sourceDigest", "artifactDigest"))
            and equal(meta.get("entrypoints"), entry.get("entrypoints"))
            and equal(meta.get("manifest"), entry.get("manifest")),
            "Current generation metadata differs from the primary catalog")
    require(type(manifest.get("schemaVersion")) is int and manifest["schemaVersion"] == 1
            and manifest.get("packageContentDigest") == source["sha256"]
            and manifest.get("cacheFingerprint") == record.get("artifactDigest"),
            "Installed artifact provenance differs from the original imported archive")
    files = manifest.get("files")
    require(isinstance(files, list) and files, "The installed artifact file manifest is absent")
    by_path = {}
    for item in files:
        require(isinstance(item, dict), "Invalid installed artifact file record")
        path = normalized_relative(item.get("logicalPath"))
        require(path not in by_path and re.fullmatch(SHA, item.get("sha256", ""))
                and type(item.get("byteCount")) is int and item["byteCount"] >= 0,
                "Invalid or duplicate installed artifact member")
        by_path[path] = item
    fingerprint = shared.digest("\n".join(path + ":" + by_path[path]["sha256"]
                                         for path in sorted(by_path)).encode())
    require(fingerprint == manifest["cacheFingerprint"], "Installed artifact fingerprint differs")
    installed_sources = {}
    with zipfile.ZipFile(io.BytesIO(source["raw"])) as archive_zip:
        entries = archive_zip.infolist()
        require(len(entries) <= 4096 and len({item.filename for item in entries}) == len(entries),
                "The original source archive has duplicate or excessive members")
        members = [item for item in entries if not item.is_dir()]
        require(sum(item.file_size for item in members) <= 128 * 1024 * 1024,
                "The source archive exceeds the bounded fixture size")
        for member in entries:
            normalized_relative(member.filename.rstrip("/"))
            require(not stat.S_ISLNK(member.external_attr >> 16), "Source archive contains a link")
        expected = {"source/" + item.filename for item in members}
        require("source/script.json" in expected
                and expected == {path for path in by_path if path.startswith("source/")},
                "Installed retained source does not have the exact original archive members")
        for member in members:
            raw = archive_zip.read(member)
            path = "source/" + member.filename
            item = by_path[path]
            require(item["byteCount"] == len(raw) and item["sha256"] == shared.digest(raw),
                    "Retained source manifest differs from original archive bytes")
            installed = raw_file(generation / path, data_root)
            require(installed["bytes"] == len(raw) and installed["raw"] == raw,
                    "Actual installed source differs from the exact producer archive")
            installed_sources[path] = document_bytes(installed)
        author = shared.parse_json(archive_zip.read("script.json"))
    return {"archive": document_bytes(source), "generation": metadata,
            "artifactManifest": artifact, "installedSources": installed_sources,
            "authorManifest": author, "sourceDigestBasis": "SHA256 of original imported archiveData"}


def validate_request(request):
    require(type(request.get("schema")) is int and request["schema"] == 1
            and request.get("surface") in ("share", "translation"), "Unknown Share/Translation exchange")
    run_id = request.get("runID")
    require(isinstance(run_id, str) and re.fullmatch(UUID, run_id), "Invalid original UI run UUID")
    require(request.get("engine") in ("expo", "nativescript")
            and request.get("fixtureAppID") == "hanlin.surface." + request["engine"],
            "Unexpected original fixture application")
    require(request.get("fixtureTitle") == ("Surface Expo" if request["engine"] == "expo" else "Surface NativeScript"),
            "Unexpected original fixture title")
    require(isinstance(request.get("challenge"), str)
            and re.fullmatch(r"[a-z0-9]+-[a-z0-9]+-[a-z0-9]+", request["challenge"])
            and type(request.get("baselineCounter")) is int and request["baselineCounter"] == 0,
            "An actual fresh zero-counter UI challenge is required")
    started = shared._epoch_milliseconds(request.get("startedAt"))
    observed = shared._epoch_milliseconds(request.get("observedAt"))
    require(started <= observed <= time.time() * 1000 + 5000, "Invalid actual UI checkpoint time")
    return run_id


def translation_publication(snapshot, identity, request):
    rows = [row for row in snapshot["value"]["snapshot"].get("translationApps", [])
            if equal(row.get("identity"), identity)]
    require(len(rows) == 1, "Current Translation publication is missing or ambiguous")
    row = rows[0]
    require(row.get("appID") == identity["packageID"]
            and row.get("entrypointID") == "surface-translation"
            and row.get("displayName") == request["fixtureTitle"]
            and row.get("nativePresentation") is None,
            "The original Translation action is not the current published route")
    root = row.get("rootNode", {})
    require(root.get("kind") == "vStack" and len(root.get("children", [])) == 2,
            "The original Translation UI root changed")
    text, button = root["children"]
    require(text.get("kind") == "text"
            and shared.decode_value(text.get("properties", {}).get("text")) == "{{selectedText}}"
            and button.get("kind") == "button", "Translation selection/action binding changed")
    expected = {"__hanlinAppIntent": True, "name": "surface.run",
                "parameters": {"query": "{{selectedText}}", "source": "translationUI"}}
    require(equal(shared.decode_value(button.get("properties", {}).get("intent")), expected),
            "The current Translation button does not carry the canonical selected text")
    children = button.get("children", [])
    require(len(children) == 1 and children[0].get("kind") == "text"
            and shared.decode_value(children[0].get("properties", {}).get("text")) ==
                "Run " + request["fixtureTitle"] + " in all five runtimes",
            "The actual original Translation action title changed")
    return row


def surface_facts(request, roots):
    snapshot = shared.snapshot_document(roots["extensions"])
    anchor = shared.action_identity(request, snapshot)
    catalog = shared.installed_catalog(roots["data"], anchor)
    identity = {**anchor["identity"], "entrypointID": "surface-" + request["surface"], "variantID": "default"}
    package = catalog["value"]["packages"][identity["installedPackageID"]]
    rows = [row for row in package["entrypoints"] if row.get("id") == identity["entrypointID"]]
    require(len(rows) == 1, "The original explicit system entrypoint is missing or ambiguous")
    entry = rows[0]
    kind = "share" if request["surface"] == "share" else "translationUI"
    contexts = {"mainApplication"} if kind == "share" else {"translationUI", "mainApplication"}
    require(entry.get("kind") == kind and entry.get("compatibility") == "supported"
            and contexts.issubset(entry.get("supportedContexts", []))
            and entry.get("runtimeProfile") == ("hanlin-expo" if request["engine"] == "expo" else "hanlin-nativescript")
            and entry.get("runtimePolicyID") == "prepared-foreground-action-v1"
            and entry.get("exportedSymbol") == "surface.run"
            and entry.get("sourcePath") == anchor["hostActionHandler"],
            "The actual system route is not the current supported native action")
    published = translation_publication(snapshot, identity, request) if kind == "translationUI" else None
    return {"identity": identity, "anchor": anchor, "catalog": catalog, "entrypoint": entry,
            "publishedTranslation": published, "snapshotSHA256": snapshot["sha256"],
            "record": package["record"]}


def input_document(inputs):
    path = Path(inputs["path"])
    current = shared.read_document(path, path.parent)
    require(all(equal(current.get(key), inputs.get(key)) for key in ("path", "sha256", "bytes", "value")),
            "The actual runner input manifest changed")
    value = current["value"]
    require(type(value.get("schema")) is int and value["schema"] == 1
            and isinstance(value.get("seed"), str) and re.fullmatch(UUID, value["seed"]),
            "The original input producer must bind a fresh seed")
    return value, path.parent


def expected_share_files(request, seed):
    payload = {"schema": 1, "kind": "hanlin.surface.share-input", "runID": request["runID"],
               "appID": request["fixtureAppID"], "seed": seed, "challenge": request["challenge"]}
    contents = {
        "share-input.json": json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        "share-note.txt": "Hanlin Share input {} {} {} {}\n".format(
            seed, request["runID"], request["engine"], request["challenge"]),
    }
    return [{"name": name, "bytes": len(text.encode()), "sha256": shared.digest(text.encode()), "text": text}
            for name, text in contents.items()]


def write_evidence(path, value):
    require(not path.exists() and not path.is_symlink(), "Immutable observer evidence already exists")
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, sort_keys=True, indent=2)
        stream.write("\n")


def write_share_response(directory, response):
    """Only the unchanged original UI's share.json handshake is additional."""
    require(directory.is_dir() and not directory.is_symlink()
            and response.get("schema") == 1 and response.get("status") == "READY"
            and re.fullmatch(UUID, response.get("batchID", "")), "Invalid original Share handshake")
    target = directory / "share.json"
    require(not target.exists() and not target.is_symlink(), "A Share response must not be overwritten")
    temporary = directory / "share.json.observer-tmp"
    write_evidence(temporary, response)
    os.replace(temporary, target)


def share_producer_request(request, case, value, evidence):
    producer = value.get("shareInputProducer", {})
    require(Path(producer.get("requestRoot", "")) == evidence, "Unexpected Share producer request root")
    result = {"schema": 1, "runID": request["runID"], "engine": request["engine"],
              "appID": request["fixtureAppID"], "seed": value["seed"],
              "challenge": request["challenge"], "preparedProofSHA256": case["prepared"]["sha256"],
              "dataContainer": str(case["roots"]["data"]), "startedAt": request["startedAt"],
              "installedIdentity": case["facts"]["identity"]}
    path = case["output"] / "share-input-request.json"
    require(not path.exists() and not path.is_symlink(), "A Share producer request must not be overwritten")
    temporary = case["output"] / "share-input-request.json.observer-tmp"
    write_evidence(temporary, result)
    os.replace(temporary, path)
    return shared.read_document(path, evidence)


def staged_share_inputs(request, case, value, input_root):
    producer = value.get("shareInputProducer", {})
    response_path = Path(producer.get("responseRoot", "")) / (request["runID"] + ".json")
    if not response_path.exists():
        return None
    response = shared.read_document(response_path, input_root)
    actual = response["value"]
    expected = case["producerRequest"]["value"]
    require(all(equal(actual.get(key), item) for key, item in expected.items())
            and actual.get("status") == "STAGED_INPUTS_ONLY"
            and actual.get("producerRequestSHA256") == case["producerRequest"]["sha256"],
            "Share producer response does not bind this exact prepared request")
    folder = "HanlinSurfaceInputs-" + request["runID"]
    expected_files = expected_share_files(request, value["seed"])
    require(actual.get("shareInputFolder") == folder and equal(actual.get("shareInputFiles"), expected_files),
            "Share input producer changed the actual fresh challenge or expected bytes")
    observed = []
    for item in expected_files:
        document = raw_file(case["roots"]["data"] / "Documents" / folder / item["name"], case["roots"]["data"])
        require(document["raw"] == item["text"].encode(), "Actual post-XCTest Share input bytes differ")
        observed.append(document_bytes(document))
    return {"response": response, "folder": folder, "files": expected_files, "actualFiles": observed}


def batch_ids(group):
    root = group / "HanlinMiniApps/v1/ShareInbox/Batches"
    if not root.exists():
        return set()
    require(not root.is_symlink(), "Actual Share batch storage is a symbolic link")
    return {path.name for path in root.iterdir() if path.is_dir() and re.fullmatch(UUID, path.name)}


def observe_batch(group, batch_id, expected_files, earliest_ms):
    require(re.fullmatch(UUID, batch_id), "Invalid immutable Share batch UUID")
    root = group / "HanlinMiniApps/v1/ShareInbox/Batches" / batch_id
    document = shared.read_document(root / "batch.json", group)
    batch = document["value"]
    require(type(batch.get("schemaVersion")) is int and batch["schemaVersion"] == 1
            and str(uuid.UUID(batch.get("id", ""))) == batch_id,
            "Immutable Share batch identity differs")
    date = batch.get("createdAt")
    require(type(date) in (int, float) and math.isfinite(date), "Invalid Foundation Share batch date")
    created_ms = (date + 978307200) * 1000
    require(earliest_ms <= created_ms <= time.time() * 1000 + 5000,
            "Immutable Share batch predates preparation or has a future timestamp")
    items = batch.get("items")
    require(isinstance(items, list) and len(items) == len(expected_files) == 2,
            "Exactly the two actual original Share inputs are required")
    remaining = {item["sha256"]: item for item in expected_files}
    require(len(remaining) == 2, "Original shared input bytes must be distinct")
    payload, ids, owned = [], set(), []
    for ordinal, item in enumerate(items):
        item_id = str(uuid.UUID(item.get("id", "")))
        require(item_id not in ids and type(item.get("ordinal")) is int and item["ordinal"] == ordinal
                and isinstance(item.get("typeIdentifier"), str) and item["typeIdentifier"]
                and item.get("failure") is None and item.get("content") in ("file", "text"),
                "Duplicate, reordered, rejected or unexpected shared item")
        ids.add(item_id)
        row = {"id": item_id, "ordinal": ordinal, "kind": item["content"],
               "typeIdentifier": item["typeIdentifier"]}
        if "name" in item:
            require(isinstance(item["name"], str), "Invalid actual item-provider name")
            row["name"] = item["name"]
        if item["content"] == "file":
            require(item.get("file") == item_id and item.get("text") is None
                    and type(item.get("bytes")) is int and item["bytes"] >= 0
                    and re.fullmatch(SHA, item.get("sha256", "")), "Invalid owned Share file metadata")
            observed = raw_file(root / "Files" / item_id, group)
            require(observed["bytes"] == item["bytes"] and observed["sha256"] == item["sha256"],
                    "Actual owned Share file does not match its immutable batch")
            raw = observed["raw"]
            row.update(fileURL=Path(observed["path"]).as_uri(), bytes=item["bytes"], sha256=item["sha256"])
            owned.append(document_bytes(observed))
        else:
            require(isinstance(item.get("text"), str) and all(item.get(key) is None for key in ("file", "bytes", "sha256")),
                    "Invalid exact Share text representation")
            row["text"] = item["text"]
            raw = item["text"].encode()
        key = shared.digest(raw)
        require(key in remaining and remaining[key]["text"].encode() == raw,
                "Shared item bytes are unexpected or duplicated")
        remaining.pop(key)
        payload.append(row)
    require(not remaining, "An original selected Share item is missing")
    return {"batch": document, "batchID": batch_id, "createdAtMilliseconds": created_ms,
            "ownedFiles": owned, "payload": {"shareBatchID": batch_id, "items": payload}}


def translation_transport(request, case, value, input_root):
    expected = value.get("translation", {}).get(request["engine"], {})
    url = urlsplit(expected.get("url", ""))
    require(url.scheme == "http" and url.netloc == "localhost:49173" and not url.query and not url.fragment
            and url.path == "/surfaces/" + value["seed"] + "/" + request["engine"]
            and isinstance(expected.get("text"), str) and expected["text"]
            and re.fullmatch(SHA, expected.get("htmlSHA256", "")),
            "The original Translation page is not bound to this fresh producer input")
    log = raw_file(Path(value["transportLog"]), input_root)
    matches = []
    for line in log["raw"].splitlines():
        row = shared.parse_json(line)
        if row.get("path") != url.path:
            continue
        at = shared._epoch_milliseconds(row.get("at"))
        require(case["preparedAt"] <= at <= shared._epoch_milliseconds(request["observedAt"])
                and row.get("method") == "GET" and type(row.get("status")) is int and row["status"] == 200
                and row.get("sha256") == expected["htmlSHA256"]
                and type(row.get("bytes")) is int and row["bytes"] > 0
                and isinstance(row.get("userAgent"), str)
                and "Safari/" in row["userAgent"] and "AppleWebKit/" in row["userAgent"],
                "Translation transport is stale, failed, altered or not the actual Safari request")
        matches.append(row)
    require(matches, "The actual fresh Safari page request was not observed")
    return {"log": document_bytes(log), "requests": matches, "input": expected,
            "scope": "Transport binds selected text; original XCTest and native receipts prove OS dispatch"}


def terminal_result(request, case, commands, proofs, payload, batch=None):
    """Correlate the actual native route, including Share's resolved payload."""
    matches = []
    for command_id, document in commands.items():
        if command_id in case["baselineIDs"]:
            continue
        row = document["value"]
        invocation = row.get("invocation", {})
        if not equal(invocation.get("identity"), case["facts"]["identity"]) or invocation.get("entityID") != "surface.run":
            continue
        parameters = shared.decode_value(invocation.get("parameters"))
        expected = {"shareBatchID": batch["batchID"]} if batch else payload
        if not equal(parameters, expected):
            continue
        require(type(row.get("createdAt")) in (int, float) and math.isfinite(row["createdAt"])
                and case["preparedAt"] <= row["createdAt"] <= time.time() * 1000 + 5000,
                "The actual native command is not fresh for this preparation")
        require(invocation.get("continueInForeground") is True,
                "The original Share/Translation action must continue in foreground")
        if batch:
            require(command_id == batch["batchID"] and abs(row["createdAt"] - batch["createdAtMilliseconds"]) <= 1,
                    "The native command does not retain the immutable Share batch identity/date")
            delivery = invocation.get("delivery", {})
            require(type(delivery.get("schemaVersion")) is int and delivery["schemaVersion"] == 1
                    and delivery.get("appID") == request["fixtureAppID"] and delivery.get("source") == "share"
                    and delivery.get("expectedResult") == "value" and delivery.get("userGesturePresent") is True
                    and delivery.get("canPresentUI") is False
                    and delivery.get("idempotent") is False
                    and type(delivery.get("maximumAttempts")) is int and delivery["maximumAttempts"] == 1
                    and delivery.get("widgetOrigin") is None
                    and type(delivery.get("expiresAt")) in (int, float)
                    and abs(delivery["expiresAt"] - (row["createdAt"] + 86400000)) <= 1,
                    "The canonical Share delivery envelope changed")
        else:
            require(invocation.get("delivery") is None,
                    "The original Translation button uses the actual legacy intent without delivery metadata")
        matches.append((command_id, document))
    require(len(matches) <= 1, "The same original system action executed more than once")
    if not matches:
        return None
    command_id, document = matches[0]
    receipt = document["value"]["receipt"]
    if receipt.get("status") in ("queued", "running"):
        return None
    require(receipt.get("status") == "succeeded" and receipt.get("failure") is None
            and receipt.get("cancellationRequested") is False
            and receipt.get("leaseID") is None and receipt.get("leaseExpiresAt") is None
            and type(receipt.get("attempt")) is int and receipt["attempt"] == 1,
            "The actual native action did not succeed exactly once with its lease cleared")
    result = shared.decode_value(receipt.get("value"))
    if isinstance(result, str):
        result = shared.parse_json(result)
    require(isinstance(result, dict) and type(result.get("schemaVersion")) is int
            and result["schemaVersion"] == 1, "No current structured result was returned by the actual handler")
    # These are the original fixture's actual requestedSurface values. Keep all
    # native records untouched: Share resolves an envelope; Translation is legacy.
    shared._validate_five_receipts(result, {**request, "surface": "external" if batch else "translationUI"})
    require(equal(result.get("request"), payload), "The actual handler payload differs from canonical resolution")
    require(shared._epoch_milliseconds(result.get("startedAt")) >= case["preparedAt"]
            and shared._epoch_milliseconds(result.get("finishedAt")) >= shared._epoch_milliseconds(result["startedAt"])
            and shared._epoch_milliseconds(result["finishedAt"]) <= time.time() * 1000 + 5000,
            "The real handler result predates this fresh action")
    if request["engine"] == "expo":
        require(result.get("requestIDOrigin") == "host-invocation"
                and str(uuid.UUID(result.get("requestID", ""))) == command_id,
                "The Expo handler result belongs to another native invocation")
    else:
        require(result.get("requestIDOrigin") == "javascript-handler" and result.get("requestID") == result["nonce"],
                "The NativeScript handler nonce is not correlated")
    durable = [doc for doc in proofs if type(doc["value"].get("schemaVersion")) is int
               and doc["value"]["schemaVersion"] == 1 and doc["value"].get("appID") == request["fixtureAppID"]
               and doc["value"].get("challenge") == request["challenge"]
               and equal(doc["value"].get("counter"), result["counter"])
               and equal(doc["value"].get("lastResult"), result)]
    require(len(durable) == 1, "One actual private state must retain the exact returned result")
    proof = durable[0]
    if request["engine"] == "nativescript":
        samples = result.get("presentationSamples")
        require(isinstance(samples, list) and samples, "Actual NativeScript window observations are missing")
        for sample in samples:
            require(isinstance(sample.get("windowID"), str)
                    and sample.get("statePath") == proof["path"]
                    and type(sample.get("attached")) is bool
                    and Path(proof["path"]).parts[-4:] == ("Windows", sample["windowID"], "State", "surface-proof.json"),
                    "The actual NativeScript result crossed private window ownership")
        require(len({sample["windowID"] for sample in samples}) == 1 and any(sample["attached"] for sample in samples),
                "This foreground action never attached its own actual native window")
        if batch:
            require(proof["path"] != case["prepared"]["path"],
                    "Share must initialize only its new native window from the actual selected file")
        else:
            require(proof["path"] == case["prepared"]["path"], "Translation replaced the prepared native owner")
    else:
        require(proof["path"] == case["prepared"]["path"], "The actual Expo private state moved")
    return {"schema": 1, "runID": request["runID"], "status": "EXECUTED_PASS",
            "challenge": request["challenge"], "counter": result["counter"],
            "engines": list(shared.CANONICAL_ENGINES), "invocationID": command_id,
            "receipt": receipt, "command": document, "privateProof": proof,
            "canonicalHandlerPayload": payload, "identity": case["facts"]["identity"],
            "scope": "Original XCTest system UI plus exact native queue, resolved input and all five actual runtime results"}


def same_roots(args, expected):
    current = shared.product_roots(args.device, args.bundle_id)
    require(all(equal(current[key], expected[key]) if key == "configuration" else current[key] == expected[key]
                for key in ROOT_KEYS), "The actual installed MiniApps roots/configuration changed")
    return current


def observe_case(args, request, directory, evidence, seen, inputs, apps):
    run_id = validate_request(request)
    value, input_root = input_document(inputs)
    case = seen.get(run_id)
    if case is None:
        require(request.get("phase") == "prepared", "Bind actual preparation before any system action")
        roots = shared.product_roots(args.device, args.bundle_id)
        require(all(not evidence.is_relative_to(roots[key]) for key in ("app", "data", "group")),
                "Observer evidence must remain outside every production container")
        facts = surface_facts(request, roots)
        binding = verify_installed_fixture_archive(roots["data"], facts["identity"], facts["catalog"],
                                                   value["surfaceArchives"][request["engine"]], input_root)
        require(binding["authorManifest"].get("hanlinAppID") == request["fixtureAppID"]
                and binding["authorManifest"].get("hanlinRuntime") == "hanlin-" + request["engine"],
                "The actual produced archive belongs to another authored fixture")
        prepared = shared.prepared_proof(request, shared.proof_documents(
            roots["data"], request["fixtureAppID"],
            expo_installed_package_id=facts["identity"]["installedPackageID"]
            if request["engine"] == "expo" else None))
        output = evidence / run_id
        output.mkdir(exist_ok=False)
        case = {"kind": "originalShareTranslation", "directory": str(directory),
                "roots": roots, "facts": facts, "binding": binding, "prepared": prepared,
                "preparedAt": shared._epoch_milliseconds(request["observedAt"]),
                "baselineIDs": set(shared.queue_documents(roots["extensions"])),
                "baselineBatches": batch_ids(roots["group"]), "output": output,
                "fixedRequest": {key: request.get(key) for key in FIXED_REQUEST},
                "phase": "prepared", "finished": False, "identityReady": False}
        if request["surface"] == "share":
            case["producerRequest"] = share_producer_request(request, case, value, evidence)
        seen[run_id] = case
    require(case.get("kind") == "originalShareTranslation" and case["directory"] == str(directory),
            "The actual XCTest run/exchange identity changed")
    require(all(equal(request.get(key), item) for key, item in case["fixedRequest"].items()),
            "The original UI preparation changed during this system attempt")
    if case["finished"]:
        return
    roots = case["roots"]
    if request.get("phase") != case["phase"]:
        same_roots(args, roots)
        case["phase"] = request["phase"]
    current = surface_facts(request, roots)
    require(all(equal(current[key], case["facts"][key]) for key in
                ("identity", "entrypoint", "record", "publishedTranslation"))
            and current["anchor"]["hostActionHandler"] == case["facts"]["anchor"]["hostActionHandler"],
            "The current installed system action changed during the original UI attempt")
    if not case["identityReady"]:
        require(request["phase"] == "prepared", "The original UI advanced before its input identity was ready")
        response = {"schema": 1, "runID": run_id, "status": "READY", "appID": request["fixtureAppID"],
                    **case["facts"]["identity"], "identity": case["facts"]["identity"],
                    "systemApps": apps, "preparedProof": case["prepared"], "catalog": current["catalog"],
                    "fixtureSource": case["binding"], "productConfiguration": roots["configuration"],
                    "productInfoSHA256": roots["infoSHA256"],
                    "actualContainers": {key: str(roots[key]) for key in ("app", "data", "group")}}
        if request["surface"] == "share":
            staged = staged_share_inputs(request, case, value, input_root)
            if staged is None:
                return
            case["staged"] = staged
            response.update(shareInputFolder=staged["folder"], shareInputNames=[item["name"] for item in staged["files"]],
                            shareInputEvidence=staged)
        else:
            translation = value["translation"][request["engine"]]
            response.update(translationInputURL=translation["url"], translationInputText=translation["text"])
        same_roots(args, roots)
        shared.write_response(directory, "identity.json", response)
        write_evidence(case["output"] / "identity.json", response)
        case["identityReady"] = True
    if request["surface"] == "share" and request["phase"] == "share-batch-saved" and "batch" not in case:
        candidates = batch_ids(roots["group"]) - case["baselineBatches"]
        require(len(candidates) <= 1, "More than one fresh Share batch was created in this original attempt")
        if not candidates:
            return
        batch = observe_batch(roots["group"], next(iter(candidates)), case["staged"]["files"], case["preparedAt"])
        response = {"schema": 1, "runID": run_id, "status": "READY", "batchID": batch["batchID"], "batch": batch}
        same_roots(args, roots)
        write_share_response(directory, response)
        write_evidence(case["output"] / "share.json", response)
        case["batch"] = batch
    if request["phase"] != "system-action-sent":
        return
    require(request.get("systemLaunchObserved") is True, "Original XCTest did not observe the real OS action")
    batch, transport = None, None
    if request["surface"] == "share":
        require("batch" in case and request.get("shareBatch", {}).get("batchID") == case["batch"]["batchID"],
                "The actual UI selected a different immutable Share batch")
        batch = observe_batch(roots["group"], case["batch"]["batchID"], case["staged"]["files"], case["preparedAt"])
        require(equal(batch, case["batch"]), "The actual immutable Share batch changed after selection")
        payload = batch["payload"]
    else:
        transport = translation_transport(request, case, value, input_root)
        payload = {"query": transport["input"]["text"], "source": "translationUI"}
    result = terminal_result(request, case, shared.queue_documents(roots["extensions"]),
                             shared.proof_documents(roots["data"], request["fixtureAppID"],
                                 expo_installed_package_id=current["identity"]["installedPackageID"]
                                 if request["engine"] == "expo" else None), payload, batch)
    if result is None:
        return
    # Resolve MCM and current source again at the final boundary. No stale root
    # or mutually-consistent edited input/result can be admitted by this leaf.
    roots = same_roots(args, roots)
    final = surface_facts(request, roots)
    require(all(equal(final[key], current[key]) for key in ("identity", "entrypoint", "record", "publishedTranslation")),
            "The current installed action changed immediately before completion")
    binding = verify_installed_fixture_archive(roots["data"], final["identity"], final["catalog"],
                                               value["surfaceArchives"][request["engine"]], input_root)
    require(equal(binding, case["binding"]), "Installed fixture source changed before completion")
    input_document(inputs)
    if batch:
        require(equal(staged_share_inputs(request, case, value, input_root), case["staged"]),
                "Actual original selected input bytes changed before completion")
        require(equal(observe_batch(roots["group"], batch["batchID"], case["staged"]["files"], case["preparedAt"]), batch),
                "Actual immutable Share bytes changed before completion")
    same_roots(args, roots)
    result.update(inputManifest=inputs, fixtureSource=binding, shareBatch=batch, translationTransport=transport)
    shared.write_response(directory, "completion.json", result)
    write_evidence(case["output"] / "completion.json", result)
    case["finished"] = True
