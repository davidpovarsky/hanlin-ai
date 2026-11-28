"""Read-only phase helpers for the four original Widget/Activity OS methods.

The original XCTest body performs every placement, ActivityKit start and system
button tap. This module reads the existing snapshot, canonical command and
private five-runtime result; it never creates a production state or receipt.
"""
from pathlib import Path
import io
import json
import math
import os
import re
import stat
import time
import uuid
import zipfile

import observe_shortcut_surfaces as common

SURFACES = ("widget", "liveActivity")
FAMILIES = ("systemSmall", "systemMedium", "systemLarge")


def validate_request(request):
    common.require(isinstance(request, dict) and type(request.get("schema")) is int
                   and request["schema"] == 1, "Unknown original surface request")
    run_id = request.get("runID")
    common.require(isinstance(run_id, str) and str(uuid.UUID(run_id)) == run_id,
                   "The actual original UI run must have its lowercase UUID")
    common.require(request.get("surface") in SURFACES
                   and request.get("engine") in ("expo", "nativescript")
                   and request.get("fixtureAppID") == "hanlin.surface." + request["engine"]
                   and request.get("fixtureTitle") ==
                       ("Surface Expo" if request["engine"] == "expo" else "Surface NativeScript"),
                   "Unknown original installed fixture/surface")
    challenge = request.get("challenge")
    common.require(isinstance(challenge, str)
                   and re.fullmatch(r"[a-z0-9]+-[a-z0-9]+-[a-z0-9]+", challenge)
                   and type(request.get("baselineCounter")) is int
                   and request["baselineCounter"] == 0,
                   "A fresh actual UI-prepared challenge/counter is required")
    common._epoch_milliseconds(request["startedAt"])
    return run_id


def input_bytes(path, trusted_root, maximum=64 * 1024 * 1024):
    """Read only a bounded regular producer input beneath the evidence root."""
    root = Path(trusted_root).resolve(strict=True)
    path = Path(path)
    common.require(path.is_absolute() and not Path(trusted_root).is_symlink(),
                   "The producer input must use the actual evidence root")
    parts = path.relative_to(root).parts
    common.require(parts and all(part not in ("", ".", "..") for part in parts),
                   "The producer input left the evidence root")
    current = root
    for part in parts:
        current = current / part
        common.require(not current.is_symlink(), "Linked producer input")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(fd)
        common.require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1
                       and 0 <= info.st_size <= maximum,
                       "The producer input is not one bounded regular file")
        with os.fdopen(fd, "rb", closefd=False) as stream:
            data = stream.read(maximum + 1)
        common.require(len(data) <= maximum, "The producer input grew beyond its bound")
        return data
    finally:
        os.close(fd)


def widget_fixture(inputs, engine):
    manifest = inputs["value"]
    common.require(type(manifest.get("schema")) is int and manifest["schema"] == 1,
                   "Unknown original system input manifest")
    row = manifest.get("surfaceArchives", {}).get(engine)
    common.require(isinstance(row, dict), "The original authored archive is missing")
    raw = input_bytes(row["path"], Path(inputs["path"]).parent)
    common.require(common.digest(raw) == row.get("sha256"),
                   "The actual original authored archive changed")
    entry = "widget.json" if engine == "expo" else "widget.jsx"
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        names = archive.namelist()
        common.require(len(names) == len(set(names))
                       and all(not name.startswith("/") and ".." not in Path(name).parts for name in names),
                       "Ambiguous original archive member")
        script = common.parse_json(archive.read("script.json"))
        source = archive.read(entry)
    widget_engine = "expo" if engine == "expo" else "scriptwidget"
    common.require(script.get("hanlinAppID") == "hanlin.surface." + engine
                   and script.get("widgetEngine") == widget_engine
                   and script.get("hanlinRuntime") == "hanlin-" + engine,
                   "The archive belongs to another original fixture")
    metadata = script.get("hanlinWidget")
    common.require(isinstance(metadata, dict) and metadata.get("abiVersion") == 1
                   and metadata.get("families") == list(FAMILIES),
                   "The original fixture's three declared families changed")
    actions = metadata.get("actions")
    common.require(isinstance(actions, list) and len(actions) == 1
                   and actions[0].get("id") == "surface-host-run"
                   and actions[0].get("kind") == "hostAction"
                   and actions[0].get("hostAction") == {
                       "entrypointID": "surface-intent", "actionName": "surface.run",
                       "parameters": {"surface": "widget", "fixture": "hanlin.surface." + engine}},
                   "The fixture's actual declared Host target changed")
    return {"archivePath": row["path"], "archiveSHA256": row["sha256"],
            "widgetSource": entry, "widgetSourceSHA256": common.digest(source),
            "engine": widget_engine, "metadata": metadata}


def widget_publication(request, roots, anchor, fixture):
    document = common.snapshot_document(roots["extensions"])
    snapshot = document["value"]["snapshot"]
    target = anchor["identity"]
    expected = {**target, "entrypointID": "widget", "variantID": "default"}
    common.require(target["installedPackageID"] not in snapshot.get("inactiveWidgetInstallations", []),
                   "The current widget installation is disabled")
    instances = [row for row in snapshot.get("widgetInstances", [])
                 if row.get("identity") == expected and row.get("engine") == fixture["engine"]]
    common.require(len(instances) == 1 and instances[0].get("displayName") == request["fixtureTitle"],
                   "The exact current default fixture widget is absent or ambiguous")
    instance = instances[0]
    templates = [row for row in snapshot.get("widgets", [])
                 if row.get("identity") == expected and row.get("engine") == fixture["engine"]]
    common.require(len(templates) == len(FAMILIES)
                   and sorted(row.get("family", "") for row in templates) == sorted(FAMILIES),
                   "The current widget publication differs from the original family declaration")
    programs = {}
    descriptors = {}
    for template in templates:
        common.require(type(template.get("validUntil")) in (int, float)
                       and math.isfinite(template["validUntil"])
                       and template["validUntil"] > time.time() * 1000,
                       "The current widget publication expired")
        payload = template.get("payload", {})
        if fixture["engine"] == "expo":
            common.require(payload.get("kind") == "expo", "Wrong original Expo payload")
            descriptor = payload.get("expoDescriptor", {})
            reference, expected_sha = descriptor.get("layoutRef"), descriptor.get("layoutSHA256")
        else:
            common.require(payload.get("kind") == "scriptwidget", "Wrong original ScriptWidget payload")
            descriptor = payload.get("scriptDescriptor", {})
            reference, expected_sha = descriptor.get("scriptRef"), descriptor.get("scriptSHA256")
        artifact = common.widget_artifact(roots["extensions"], expected, reference, expected_sha)
        program = artifact["value"]
        common.require(program.get("abiVersion") == 1 and program.get("engine") == fixture["engine"]
                       and program.get("sourceSHA256") == fixture["widgetSourceSHA256"]
                       and program.get("families") == list(FAMILIES)
                       and common.equal_typed_json(program.get("actions"), fixture["metadata"]["actions"]),
                       "The installed widget program differs from its actual authored archive")
        programs[template["family"]] = artifact
        descriptors[template["family"]] = descriptor
    common.require(len({row["sha256"] for row in programs.values()}) == 1,
                   "The current family templates disagree about the actual program")
    states = [row for row in snapshot.get("widgetStates", [])
              if row.get("identity") == expected and row.get("engine") == fixture["engine"]]
    common.require(len(states) <= 1, "Ambiguous actual default-instance state")
    if states:
        common.require(type(states[0].get("revision")) is int and states[0]["revision"] >= 0
                       and states[0].get("artifactSHA256") == next(iter(programs.values()))["sha256"],
                       "State belongs to another widget program")
    # The installed catalog's widget entry must be current as well as its action.
    catalog = common.installed_catalog(roots["data"], anchor)
    package = catalog["value"]["packages"][target["installedPackageID"]]
    entries = [row for row in package["entrypoints"] if row.get("id") == "widget"]
    common.require(len(entries) == 1 and entries[0].get("kind") == "widget"
                   and entries[0].get("widgetEngine") == fixture["engine"]
                   and entries[0].get("compatibility") == "supported"
                   and "widget" in entries[0].get("supportedContexts", []),
                   "The publication is not the actual supported widget entrypoint")
    return {"identity": expected, "instance": instance, "engine": fixture["engine"],
            "programs": programs, "descriptors": descriptors, "states": states,
            "snapshotSHA256": document["sha256"], "catalogSHA256": catalog["sha256"],
            "archive": fixture}


def require_fresh_widget_publication(request, publication):
    if request["surface"] == "widget" and request["engine"] == "expo":
        for descriptor in publication["descriptors"].values():
            props = {key: common.decode_value(value) for key, value in descriptor.get("props", {}).items()}
            common.require(props.get("challenge") == request["challenge"]
                           and type(props.get("counter")) is int and props["counter"] == 0,
                           "Publish widget has not committed this actual fresh UI challenge")
    if request["surface"] == "liveActivity" and request["engine"] == "nativescript":
        states = publication["states"]
        common.require(len(states) == 1, "The original ActivityKit preparation did not commit its state")
        values = {key: common.decode_value(value) for key, value in states[0]["values"].items()}
        common.require(values.get("challenge") == request["challenge"]
                       and type(values.get("counter")) is int and values["counter"] == 0,
                       "The actual ScriptWidget ActivityKit state belongs to another start")


def native_origin(invocation, request, publication):
    delivery = invocation.get("delivery")
    common.require(invocation.get("continueInForeground") is True
                   and isinstance(delivery, dict) and delivery.get("schemaVersion") == 1
                   and type(delivery.get("schemaVersion")) is int
                   and delivery.get("appID") == request["fixtureAppID"]
                   and delivery.get("source") == request["surface"]
                   and delivery.get("userGesturePresent") is True
                   and delivery.get("canPresentUI") is True,
                   "The command lacks the original system-surface native delivery")
    parameters = common.decode_value(invocation.get("parameters"))
    expected = {"surface": request["surface"], "fixture": request["fixtureAppID"]}
    if request["surface"] == "liveActivity" and request["engine"] == "expo":
        expected["shownChallenge"] = request["challenge"]
        common.require(delivery.get("widgetOrigin") is None,
                       "The native-node ActivityKit route must not invent WidgetProgram provenance")
    else:
        origin = delivery.get("widgetOrigin")
        common.require(isinstance(origin, dict) and origin.get("identity") == publication["identity"]
                       and origin.get("engine") == publication["engine"]
                       and origin.get("actionID") == "surface-host-run"
                       and origin.get("family") in publication["programs"],
                       "The actual native origin belongs to another widget instance, family or action")
        program = publication["programs"][origin["family"]]
        common.require(origin.get("artifactSHA256") == program["sha256"]
                       and isinstance(origin.get("parametersSHA256"), str)
                       and re.fullmatch(r"[0-9a-f]{64}", origin["parametersSHA256"]),
                       "The native origin did not retain the actual verified widget program/parameters digest")
        encoded_parameters = json.dumps({"parameters": invocation["parameters"]},
                                        sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
        allowed_parameters = {common.digest(b"{}"), common.digest(encoded_parameters)}
        common.require(origin["parametersSHA256"] in allowed_parameters,
                       "The native origin digest does not bind omitted/default or exact actual parameters")
        if request["surface"] == "liveActivity":
            common.require(origin["family"] == "systemMedium",
                           "The original ScriptWidget activity was started in another family")
    common.require(common.equal_typed_json(parameters, expected),
                   "The actual native parameters differ from the authored system button")
    return parameters


def completed(request, anchor, baseline_ids, commands, proofs, publication, admitted_ms):
    validate_request(request)
    matches = []
    for identifier, document in commands.items():
        if identifier in baseline_ids:
            continue
        row = document["value"]
        invocation = row.get("invocation", {})
        if invocation.get("identity") != anchor["identity"] or invocation.get("entityID") != "surface.run":
            continue
        delivery = invocation.get("delivery", {})
        if not isinstance(delivery, dict) or delivery.get("source") != request["surface"]:
            continue
        parameters = native_origin(invocation, request, publication)
        common.require(type(row.get("createdAt")) in (int, float)
                       and math.isfinite(row["createdAt"]) and row["createdAt"] >= admitted_ms,
                       "The actual system command predates this admitted UI attempt")
        matches.append((identifier, document, parameters))
    common.require(len(matches) <= 1, "The original system button executed more than once")
    if not matches:
        return None
    identifier, document, parameters = matches[0]
    receipt = document["value"]["receipt"]
    if receipt.get("status") in ("queued", "running"):
        return None
    common.require(receipt.get("status") == "succeeded" and receipt.get("failure") is None
                   and receipt.get("cancellationRequested") is False
                   and receipt.get("leaseID") is None and receipt.get("leaseExpiresAt") is None
                   and type(receipt.get("attempt")) is int and receipt["attempt"] == 1,
                   "The actual system invocation did not succeed exactly once")
    result = common.decode_value(receipt.get("value"))
    if isinstance(result, str):
        result = common.parse_json(result)
    common.require(isinstance(result, dict), "No actual structured native result")
    common._validate_five_receipts(result, request)
    common.require(common.equal_typed_json(result.get("request"), parameters),
                   "The returned native handler payload differs from the actual command")
    if request["engine"] == "expo":
        common.require(result.get("requestIDOrigin") == "host-invocation"
                       and str(uuid.UUID(result.get("requestID", ""))) == identifier,
                       "The Expo result belongs to another native invocation")
    else:
        common.require(result.get("requestIDOrigin") == "javascript-handler"
                       and result.get("requestID") == result["nonce"],
                       "The original NativeScript handler nonce differs")
    durable = [proof for proof in proofs
               if proof["value"].get("schemaVersion") == 1
               and proof["value"].get("appID") == request["fixtureAppID"]
               and proof["value"].get("challenge") == request["challenge"]
               and common.equal_typed_json(proof["value"].get("counter"), result["counter"])
               and common.equal_typed_json(proof["value"].get("lastResult"), result)]
    common.require(len(durable) == 1, "The exact native result is not in one current private state file")
    return {"schema": 1, "runID": request["runID"], "status": "EXECUTED_PASS",
            "challenge": request["challenge"], "counter": result["counter"],
            "engines": list(common.CANONICAL_ENGINES), "invocationID": identifier,
            "receipt": receipt, "command": document, "privateProof": durable[0],
            "identity": anchor, "sourcePublication": publication,
            "scope": "Actual native system-origin command and five-runtime result; the original XCTest supplies actual OS placement/start/tap evidence."}


def write_phase_response(directory, name, value):
    common.require(name in ("widget.json", "activity.json"),
                   "Only the original Widget/Activity phase responses are permitted")
    common.require(directory.is_dir() and not directory.is_symlink(),
                   "The actual XCTest exchange directory is absent")
    target = directory / name
    common.require(not target.exists(), "A prior original phase response cannot be replaced")
    temporary = directory / (name + ".observer-tmp")
    with temporary.open("x") as stream:
        json.dump(value, stream, ensure_ascii=False, sort_keys=True, indent=2)
        stream.write("\n")
    os.replace(temporary, target)


def retain_response(directory, output, name, value):
    if name in ("identity.json", "completion.json"):
        common.write_response(directory, name, value)
    else:
        write_phase_response(directory, name, value)
    (output / name).write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n")


def current_product(args, expected_roots, expected_extension):
    actual = common.product_roots(args.device, args.bundle_id)
    common.require(all(actual[key] == expected_roots[key] for key in ("app", "data", "group", "extensions"))
                   and actual["configuration"] == expected_roots["configuration"]
                   and actual["infoSHA256"] == expected_roots["infoSHA256"]
                   and common.widget_extension_executable(actual) == expected_extension,
                   "The actual installed product, MCM containers or WidgetKit extension changed")
    return actual




def installed_fixture(request, roots, anchor, catalog, inputs):
    from observe_share_translation_surfaces import input_document, verify_installed_fixture_archive
    manifest, parent = input_document(inputs)
    return verify_installed_fixture_archive(
        roots["data"], anchor["identity"], catalog,
        manifest["surfaceArchives"][request["engine"]], parent)


REQUEST_IDENTITY_FIELDS = ("runID", "engine", "surface", "fixtureAppID", "fixtureTitle",
                           "challenge", "baselineCounter", "startedAt")


def require_prepared_case(request, directory, case):
    common.require(case.get("kind") == "originalWidgetActivity"
                   and case["directory"] == str(directory)
                   and common.equal_typed_json(
                       {key: request[key] for key in REQUEST_IDENTITY_FIELDS}, case["requestIdentity"]),
                   "The prepared UI run, exchange directory or challenge changed")


def require_original_owner(result, case):
    common.require(result["privateProof"]["path"] == case["prepared"]["path"],
                   "The system action completed in a different foreground owner")
    if case["requestIdentity"]["surface"] == "liveActivity":
        common.require(case["phaseResponse"] is not None
                       and result["privateProof"]["value"].get("activityID") ==
                           case["phaseResponse"].get("activityID"),
                       "The actual foreground ActivityKit identity changed before completion")


def observe_case(args, request, directory, evidence, seen, inputs, apps):
    run_id = validate_request(request)
    common.require(inputs is not None, "This original surface needs the original runner's actual input manifest")
    case = seen.get(run_id)
    if case is None:
        common.require(request.get("phase") == "prepared",
                       "Observe the actual preparation before any original system action")
        roots = common.product_roots(args.device, args.bundle_id)
        extension = common.widget_extension_executable(roots)
        fixture = widget_fixture(inputs, request["engine"])
    else:
        require_prepared_case(request, directory, case)
        roots, extension, fixture = case["rootsAtPreparation"], case["extension"], case["fixture"]
        if request.get("phase") != case["phase"]:
            current_product(args, roots, extension)
            case["phase"] = request.get("phase")
    snapshot = common.snapshot_document(roots["extensions"])
    anchor = common.action_identity(request, snapshot)
    catalog = common.installed_catalog(roots["data"], anchor)
    anchor["catalogSHA256"] = catalog["sha256"]
    anchor["installedRecord"] = catalog["value"]["packages"][
        anchor["identity"]["installedPackageID"]]["record"]
    commands = common.queue_documents(roots["extensions"])
    proofs = common.proof_documents(roots["data"], request["fixtureAppID"],
                                    expo_installed_package_id=anchor["identity"]["installedPackageID"]
                                    if request["engine"] == "expo" else None)
    publication = widget_publication(request, roots, anchor, fixture)
    if case is None:
        source = installed_fixture(request, roots, anchor, catalog, inputs)
        prepared = common.prepared_proof(request, proofs)
        output = evidence / run_id
        output.mkdir(exist_ok=False)
        response = {"schema": 1, "runID": run_id, "status": "READY",
                    **anchor["identity"], **anchor, "systemApps": apps,
                    "productConfiguration": roots["configuration"],
                    "productInfoSHA256": roots["infoSHA256"],
                    "actualContainers": {key: str(roots[key]) for key in ("app", "data", "group")},
                    "widgetExtension": extension, "preparedProof": prepared,
                    "inputManifest": inputs, "catalog": catalog, "installedFixture": source}
        case = {"kind": "originalWidgetActivity", "directory": str(directory),
                "requestIdentity": {key: request[key] for key in REQUEST_IDENTITY_FIELDS},
                "rootsAtPreparation": roots, "extension": extension, "fixture": fixture,
                "anchor": anchor, "baselineIDs": set(commands), "prepared": prepared,
                "installedFixture": source,
                "phase": request["phase"], "finished": False, "output": output,
                "admittedMilliseconds": time.time() * 1000, "phaseResponse": None}
        retain_response(directory, output, "identity.json", response)
        seen[run_id] = case
    common.require(anchor["identity"] == case["anchor"]["identity"]
                   and anchor["hostActionHandler"] == case["anchor"]["hostActionHandler"],
                   "The current installed action changed during the original surface attempt")
    phase = request.get("phase")
    if request["surface"] == "widget" and phase == "widget-published" and case["phaseResponse"] is None:
        require_fresh_widget_publication(request, publication)
        response = {"schema": 1, "runID": run_id, "status": "READY",
                    "configurationTitle": "Hanlin Script", "entityTitle": request["fixtureTitle"],
                    "publication": publication,
                    "scope": "Current native publication only; the original UI must still place and tap it."}
        retain_response(directory, case["output"], "widget.json", response)
        case["phaseResponse"] = response
    if request["surface"] == "liveActivity" and phase == "activity-started" and case["phaseResponse"] is None:
        require_fresh_widget_publication(request, publication)
        candidates = [proof for proof in proofs
                      if proof["path"] == case["prepared"]["path"]
                      and proof["value"].get("challenge") == request["challenge"]
                      and type(proof["value"].get("counter")) is int
                      and proof["value"]["counter"] == 0
                      and proof["value"].get("lastResult") is None]
        common.require(len(candidates) == 1, "The actual prepared owner changed during ActivityKit start")
        proof = candidates[0]
        identifier = proof["value"].get("activityID")
        common.require(isinstance(identifier, str) and 0 < len(identifier) <= 256
                       and identifier != case["prepared"]["value"].get("activityID"),
                       "The actual Host ActivityKit start has not returned a fresh activity ID")
        response = {"schema": 1, "runID": run_id, "status": "READY", "activityID": identifier,
                    "actualPrivateStartResult": proof, "publication": publication,
                    "scope": "ID persisted only after the original Host start returns. Actual visible ActivityKit rendering/tap remains the original XCTest's responsibility; no OS availability is inferred."}
        retain_response(directory, case["output"], "activity.json", response)
        case["phaseResponse"] = response
    if phase == "system-action-sent" and not case["finished"]:
        common.require(case["phaseResponse"] is not None and request.get("systemLaunchObserved") is True,
                       "The actual original publication/start and system tap were not observed")
        result = completed(request, anchor, case["baselineIDs"], commands, proofs,
                           publication, case["admittedMilliseconds"])
        if result is not None:
            require_original_owner(result, case)
            current_product(args, roots, extension)
            current_snapshot = common.snapshot_document(roots["extensions"])
            current_anchor = common.action_identity(request, current_snapshot)
            current_catalog = common.installed_catalog(roots["data"], current_anchor)
            current_source = installed_fixture(request, roots, current_anchor, current_catalog, inputs)
            common.require(common.equal_typed_json(current_source, case["installedFixture"]),
                           "The actual installed fixture/source changed before terminal observation")
            current_publication = widget_publication(request, roots, current_anchor, fixture)
            common.require(current_anchor["identity"] == anchor["identity"]
                           and current_anchor["hostActionHandler"] == anchor["hostActionHandler"]
                           and current_publication["identity"] == publication["identity"]
                           and {key: row["sha256"] for key, row in current_publication["programs"].items()}
                               == {key: row["sha256"] for key, row in publication["programs"].items()},
                           "The current installed generation/program changed before terminal observation")
            result["originalPhaseObservation"] = case["phaseResponse"]
            current_product(args, roots, extension)
            retain_response(directory, case["output"], "completion.json", result)
            case["finished"] = True
