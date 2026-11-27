"""Original paired-runner producer for one ordinary Files source-folder input.

It copies the actual bundled SDK template only into a new MiniApps Documents
folder. Studio, drafts, preferences, logs and acceptance results are never
producer destinations. Only the shipping UI imports and edits this input.
"""
from pathlib import Path
import json
import os
import re
import stat
import threading
import time
import uuid

import observe_shortcut_surfaces as shared
import observe_studio_gallery as gallery
from observe_share_translation_surfaces import raw_file

require = shared.require
equal = shared.equal_typed_json


def create_manifest(evidence):
    evidence = Path(evidence).resolve(strict=True)
    responses = evidence / "studio-source-inputs"
    responses.mkdir(exist_ok=False)
    value = {"schema": 1, "kind": "studio-source-input-v1",
             "requestRoot": str(evidence / "shortcut-observer"), "responseRoot": str(responses)}
    path = evidence / "studio-source-inputs.json"
    require(not path.exists() and not path.is_symlink(), "A Studio input manifest already exists")
    with path.open("x") as stream:
        stream.write(json.dumps(value, sort_keys=True, indent=2) + "\n")
        stream.flush()
        os.fsync(stream.fileno())
    return shared.read_document(path, evidence)


def stage(request_path, inputs, resolve_roots, stopping=lambda: False):
    manifest_path = Path(inputs["path"])
    evidence = manifest_path.parent.resolve(strict=True)
    current_manifest = shared.read_document(manifest_path, evidence)
    require(equal(current_manifest, inputs), "The original Studio input manifest changed")
    manifest = inputs["value"]
    request_root, response_root = evidence / "shortcut-observer", evidence / "studio-source-inputs"
    require(equal(manifest, {"schema": 1, "kind": "studio-source-input-v1",
            "requestRoot": str(request_root), "responseRoot": str(response_root)})
            and response_root.is_dir() and not response_root.is_symlink(),
            "Studio input paths must be the original runner's owned evidence")
    request_path = Path(request_path)
    require(request_path.parent.parent == request_root and request_path.name == "studio-import-input-request.json",
            "Only the original observer's per-run Studio input request is accepted")
    document = shared.read_document(request_path, evidence)
    require(document["bytes"] <= 65536, "The Studio input request exceeds its bound")
    request = document["value"]
    fields = {"schema", "runID", "engine", "exampleID", "marker", "startedAt", "dataContainer",
              "appContainer", "hostArchiveSHA256", "templateHashes"}
    require(isinstance(request, dict) and set(request) == fields
            and type(request["schema"]) is int and request["schema"] == 1,
            "Unknown original Studio input request")
    run_id = request["runID"]
    require(isinstance(run_id, str) and str(uuid.UUID(run_id)) == run_id and request_path.parent.name == run_id
            and request["engine"] == "expo" and request["exampleID"] == "expo-hello-world"
            and request["marker"] == "שלום Editor " + run_id[:8],
            "Only the single selected original Expo Files import case may stage an input")
    started = shared._epoch_milliseconds(request["startedAt"]) / 1000
    require(time.time() - 7200 <= started <= time.time() + 5,
            "A stale or future Studio preparation cannot create a normal input")
    require(isinstance(request["hostArchiveSHA256"], str)
            and re.fullmatch(r"[0-9a-f]{64}", request["hostArchiveSHA256"])
            and isinstance(request["templateHashes"], dict) and request["templateHashes"],
            "The actual shipped template identity is absent")
    roots = resolve_roots()
    for key, field in (("data", "dataContainer"), ("app", "appContainer")):
        declared = Path(request[field])
        require(declared.is_absolute() and not declared.is_symlink() and declared.is_dir()
                and declared.resolve(strict=True) == declared == roots[key],
                "The actual MiniApps app/data container differs from the prepared source")
    require(all(not evidence.is_relative_to(roots[key]) for key in ("app", "data", "group")),
            "Input provenance must be outside all production containers")
    sdk = gallery.bind_sdk(roots, request)
    require(sdk["archive"]["sha256"] == request["hostArchiveSHA256"]
            and equal(gallery.hashes(sdk["template"]), request["templateHashes"]),
            "The actual shipped original source differs from the admitted template")
    documents = roots["data"] / "Documents"
    require(documents.is_dir() and not documents.is_symlink(), "The actual MiniApps Documents directory is unavailable")
    response = response_root / (run_id + ".json")
    require(not response.exists() and not response.is_symlink() and not stopping(),
            "Input staging was stopped or already completed")
    folder_name = "HanlinStudioImport-" + run_id
    folder = documents / folder_name
    folder.mkdir(exist_ok=False)
    project = folder / request["exampleID"]
    project.mkdir(exist_ok=False)
    for relative, source in sorted(sdk["template"].items()):
        require(not stopping(), "Studio ordinary input staging stopped")
        # bind_sdk/source_tree already rejects links, traversal and extra source.
        path = project / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("xb") as stream:
            stream.write(source["raw"])
            stream.flush()
            os.fsync(stream.fileno())
        info = path.lstat()
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1
                and raw_file(path, roots["data"])["sha256"] == source["sha256"],
                "An ordinary copied input is not the actual original source")
    require(equal(gallery.hashes(gallery.source_tree(project, roots["data"])), request["templateHashes"]),
            "The staged Files source-folder inventory changed")
    current = resolve_roots()
    require(current == roots, "Actual app/data/group/configuration changed during normal input staging")
    gallery.verify_sdk_unchanged({"sdk": sdk, "fixed": request}, current)
    require(raw_file(Path(sdk["archive"]["path"]), roots["app"], 256 * 1024 * 1024)["sha256"]
            == request["hostArchiveSHA256"]
            and shared.read_document(request_path, evidence)["sha256"] == document["sha256"]
            and equal(shared.read_document(manifest_path, evidence), inputs) and not stopping(),
            "Source/request/manifest changed or staging stopped before provenance publication")
    value = {**request, "status": "STAGED_INPUTS_ONLY", "producerRequestSHA256": document["sha256"],
             "inputFolder": folder_name, "projectFolder": request["exampleID"]}
    temporary = response.with_suffix(".json.producer-tmp")
    with temporary.open("x") as stream:
        stream.write(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n")
        stream.flush()
        os.fsync(stream.fileno())
    require(not response.exists() and not response.is_symlink(), "An input response appeared before publication")
    temporary.replace(response)
    return value


def start(simulator, inputs, state):
    stopped = threading.Event()
    report = {"status": "RUNNING_INPUT_PRODUCER", "runs": {}, "errors": [],
              "scope": "One ordinary Documents source-folder input; no Studio or OS result writes"}
    state["studio_source_inputs"] = report
    request_root = Path(inputs["value"]["requestRoot"])
    processed = set()

    def produce():
        try:
            while not stopped.wait(0.1):
                if not request_root.exists():
                    continue
                require(not request_root.is_symlink(), "The original Studio request root changed")
                for path in sorted(request_root.glob("*/studio-import-input-request.json")):
                    if stopped.is_set():
                        return
                    if path in processed:
                        continue
                    processed.add(path)
                    require(len(processed) == 1, "Only one original Files import input is selected")
                    response = stage(path, inputs,
                        lambda: shared.product_roots(simulator, "com.itorah.hanlinminiapps"), stopped.is_set)
                    report["runs"][response["runID"]] = response
        except Exception as error:
            report["errors"].append(type(error).__name__ + ": " + str(error))
        finally:
            report["status"] = "INPUT_PRODUCER_FAILED" if report["errors"] else "INPUT_PRODUCER_STOPPED"

    thread = threading.Thread(target=produce, name="original-studio-source-input-producer", daemon=True)
    thread.start()
    return stopped, thread


def finish(producer, state):
    stopped, thread = producer
    stopped.set()
    thread.join(timeout=25)
    report = state["studio_source_inputs"]
    if thread.is_alive():
        report["errors"].append("The bounded Studio input producer did not stop")
        report["status"] = "INPUT_PRODUCER_FAILED"
    report["allSelectedInputsStaged"] = (not report["errors"] and not thread.is_alive()
        and len(report["runs"]) == 1
        and all(row["status"] == "STAGED_INPUTS_ONLY" for row in report["runs"].values()))
    return report["allSelectedInputsStaged"]
