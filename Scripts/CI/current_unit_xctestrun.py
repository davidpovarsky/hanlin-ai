#!/usr/bin/env python3
"""Admit only this invocation's original app-hosted unit-test products.

The workflow still runs build-for-testing, including its existing cache policy.
Only old .xctestrun descriptors are moved aside, before that build. A successful
build may reuse compiled objects; this receipt never calls those objects newly
compiled. No simulator or package-resolution command is performed here.

Apple TN2339 documents test-without-building -xctestrun and its bundle paths.
The manifest is not rewritten: its environment, test plan, and settings survive.
Exact -only-testing flags and the existing result-completeness verifier remain
in the workflow. This admission is not a test result.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import uuid

try:
    from .owned_simulator_receipts import verify_owned_simulator
except ImportError:
    from owned_simulator_receipts import verify_owned_simulator


RECEIPT = "06-current-unit-xctestrun.json"
ADMISSION = "08-current-unit-xctestrun-admission.json"
TARGET = "AI_HLYTests"
HOST_NAME = "AI_Hanlin.app"
HOST_ID = "com.itorah.chavrusachat"
TEST_ID = HOST_ID + ".tests"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
    try:
        with temporary.open("x", encoding="utf-8") as stream:
            json.dump(value, stream, indent=2, sort_keys=True)
            stream.write("\n")
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def selected_identifiers(raw):
    values = [value.strip() for value in raw.split(",") if value.strip()]
    require(values, "No unit selectors were requested")
    require(all(value.split("/", 1)[0] == TARGET and not any(c.isspace() for c in value)
                for value in values), "This admission is scoped to original AI_HLYTests selectors")
    return values


def contained(path, root, *, kind):
    root = Path(root).resolve(strict=True)
    path = Path(path).resolve(strict=True)
    require(path.is_relative_to(root), "Test product escapes the owned Build/Products directory")
    require(path.is_dir() if kind == "directory" else path.is_file(),
            "Required test product has the wrong file type")
    return path


def descriptors(products):
    products = Path(products)
    candidates = sorted(products.glob("*.xctestrun"))
    require(all(p.is_file() and not p.is_symlink() for p in candidates),
            "Generated .xctestrun descriptors must be regular owned files")
    return candidates


def build_context(repository, products, log, configuration, selectors):
    repository = Path(repository).resolve(strict=True)
    products = Path(products).resolve()
    log = Path(log).resolve(strict=True)
    require(products.is_relative_to(repository / "build") and products.name == "Products"
            and products.parent.name == "Build",
            "Test products must be in this checkout's owned build directory")
    require(log.is_relative_to(repository) and not log.is_relative_to(products),
            "Test receipts must remain in this checkout outside Build/Products")
    run_id, attempt = os.environ.get("GITHUB_RUN_ID", ""), os.environ.get("GITHUB_RUN_ATTEMPT", "")
    require(all(re.fullmatch(r"[1-9][0-9]*", value) for value in (run_id, attempt)),
            "Current GitHub run and attempt are required")

    def command(arguments, *, timeout_seconds=30):
        return subprocess.check_output(arguments, cwd=repository, timeout=timeout_seconds)

    head = command(["git", "rev-parse", "HEAD"]).decode().strip()
    require(head == os.environ.get("GITHUB_SHA"), "Checkout differs from this run's source SHA")
    # Run 45019487094: full-checkout binary diff exceeded 30s at native admit after build IO.
    diff = command(["git", "diff", "--binary", "--no-ext-diff", "--no-textconv", "HEAD", "--", "."],
                   timeout_seconds=120)
    provenance_path = log / "06-diagnostics-build-provenance.json"
    provenance = json.loads(provenance_path.read_bytes())
    require(provenance.get("sourceCommit") == head, "Build provenance belongs to a different source")
    require(type(provenance.get("trackedWorkspaceModified")) is bool,
            "Build provenance lacks its tracked-tree qualification")
    require(configuration in ("Debug", "Release"), "Unsupported original app configuration")
    return {
        "run_id": run_id, "run_attempt": attempt, "source_sha": head,
        "configuration": configuration, "selectors": selected_identifiers(selectors),
        "products_root": str(products),
        "developer_directory": command(["xcode-select", "-p"]).decode().strip(),
        "xcode_version": command(["xcodebuild", "-version"]).decode().strip(),
        "tracked_diff_sha256": hashlib.sha256(diff).hexdigest(),
        "tracked_workspace_modified": bool(diff),
        "diagnostics_provenance_sha256": sha256(provenance_path),
        "diagnostics_tracked_workspace_modified": provenance["trackedWorkspaceModified"],
    }


def prepare(products, log, context):
    products, log = Path(products), Path(log)
    products.mkdir(parents=True, exist_ok=True)
    require(not (log / RECEIPT).exists(), "A current-build receipt already exists; do not reuse it")
    candidates = descriptors(products)
    archive = log / "prior-unit-xctestrun"
    require(not archive.exists(), "Prior-descriptor archive already exists")
    prior = [{"name": path.name, "sha256": sha256(path)} for path in candidates]
    receipt = {"schema_version": 1, "status": "PREPARING", "context": context,
               "prior_descriptors": prior,
               "qualification": "Current build-for-testing may reuse validated compiler products; no fresh-compilation claim."}
    write_json(log / RECEIPT, receipt)
    archive.mkdir(parents=True)
    for path in candidates:
        path.rename(archive / path.name)
    require(not descriptors(products), "A prior descriptor survived preparation")
    receipt["status"] = "PREPARED"
    write_json(log / RECEIPT, receipt)
    return receipt


def read_receipt(log, context, status):
    value = json.loads((Path(log) / RECEIPT).read_bytes())
    require(value.get("schema_version") == 1 and value.get("status") == status,
            "Current-build receipt is missing or is in the wrong phase")
    require(value.get("context") == context,
            "Source, selector, run, toolchain or tracked build inputs changed")
    return value


def original_unit_target(document):
    require(isinstance(document, dict), "Malformed .xctestrun document")
    metadata = document.get("__xctestrun_metadata__", {})
    require(isinstance(metadata, dict), "Malformed .xctestrun metadata")
    version = metadata.get("FormatVersion", 1)
    require(type(version) is int and version in (1, 2), "Unsupported .xctestrun format version")
    if version == 1:
        require("TestConfigurations" not in document, "Conflicting .xctestrun format declarations")
        values = [document[TARGET]] if TARGET in document else []
    else:
        configurations = document.get("TestConfigurations")
        require(isinstance(configurations, list), "Missing .xctestrun test configurations")
        values = []
        for configuration in configurations:
            require(isinstance(configuration, dict), "Malformed test configuration")
            enabled = configuration.get("IsEnabled", True)
            require(type(enabled) is bool, "Malformed configuration enablement")
            if not enabled:
                continue
            targets = configuration.get("TestTargets")
            require(isinstance(targets, list) and all(isinstance(t, dict) for t in targets),
                    "Malformed .xctestrun test targets")
            values.extend(t for t in targets if t.get("BlueprintName") == TARGET)
    require(len(values) == 1 and isinstance(values[0], dict),
            "The original unit target is absent or ambiguous")
    target = values[0]
    require(target.get("BlueprintName", TARGET) == TARGET
            and target.get("IsEnabled", True) is True
            and target.get("IsUITestBundle", False) is False,
            "The manifest does not select the original app-hosted unit target")
    require(target.get("TestHostBundleIdentifier") == HOST_ID, "Wrong original test-host identity")
    return version, target


def product_path(value, products, host=None):
    require(isinstance(value, str) and value, "Missing original test product path")
    value = value.replace("__TESTROOT__", str(products))
    if host is not None:
        value = value.replace("__TESTHOST__", str(host))
    require(not re.search(r"__[A-Z_]+__", value), "Unresolved test product path placeholder")
    candidate = Path(value)
    require(candidate.is_absolute(), "Relative test product path is unsupported")
    return contained(candidate, products, kind="directory")


def bundle_files(bundle, bundle_id, products):
    info_path = contained(bundle / "Info.plist", products, kind="file")
    require(info_path.stat().st_size < 1024 * 1024, "Unexpectedly large test product Info.plist")
    info = plistlib.loads(info_path.read_bytes())
    require(isinstance(info, dict) and info.get("CFBundleIdentifier") == bundle_id,
            "Built product bundle identity differs from the original target")
    name = info.get("CFBundleExecutable")
    require(isinstance(name, str) and name and "/" not in name and "\\" not in name
            and name not in (".", ".."), "Invalid original product executable")
    binary = contained(bundle / name, products, kind="file")
    paths = [info_path, binary]
    # Debug executables can be launch stubs; bind the actual adjacent app code too.
    debug_library = bundle / (name + ".debug.dylib")
    if debug_library.exists() or debug_library.is_symlink():
        paths.append(contained(debug_library, products, kind="file"))
    return [{"path": str(path.relative_to(products)), "bytes": path.stat().st_size,
             "sha256": sha256(path)} for path in paths]


def inspect_manifest(products, configuration):
    products = Path(products).resolve(strict=True)
    candidates = descriptors(products)
    require(len(candidates) == 1, "Expected exactly one current generated .xctestrun descriptor")
    manifest = candidates[0]
    require(manifest.stat().st_size < 8 * 1024 * 1024, "Unexpectedly large .xctestrun descriptor")
    version, target = original_unit_target(plistlib.loads(manifest.read_bytes()))
    host = product_path(target.get("TestHostPath"), products)
    expected_host = contained(products / (configuration + "-iphonesimulator") / HOST_NAME,
                              products, kind="directory")
    require(host == expected_host, "Wrong original app host or build configuration")
    test_bundle = product_path(target.get("TestBundlePath"), products, host)
    require(test_bundle.name == TARGET + ".xctest"
            and test_bundle in (host / "PlugIns" / (TARGET + ".xctest"),
                                expected_host.parent / (TARGET + ".xctest")),
            "Wrong original unit-test bundle location")
    files = bundle_files(host, HOST_ID, products) + bundle_files(test_bundle, TEST_ID, products)
    return {
        "manifest": manifest.name, "manifest_sha256": sha256(manifest), "format_version": version,
        "host_path": str(host.relative_to(products)),
        "test_bundle_path": str(test_bundle.relative_to(products)),
        "files": sorted(files, key=lambda item: item["path"]),
    }


def seal(products, log, context):
    products, log = Path(products), Path(log)
    receipt = read_receipt(log, context, "PREPARED")
    build_log = log / "06-xcodebuild-simulator.log"
    # The preceding workflow step must also exit successfully under pipefail.
    # A marker binds the archived command/result; it is not the success authority.
    with build_log.open("r", encoding="utf-8", errors="replace") as stream:
        first_lines = "".join(stream.readline() for _ in range(20))
        successful = "** TEST BUILD SUCCEEDED **" in first_lines or any(
            "** TEST BUILD SUCCEEDED **" in line for line in stream)
    require("build-for-testing" in first_lines and successful,
            "The current workflow has no successful build-for-testing record")
    # Retain actual generated bytes before interpreting a native format. If a
    # future Xcode format/path or multiple manifests are rejected, the failure
    # artifact must still contain the evidence needed to diagnose that gate.
    evidence = log / "06-generated-unit-manifests"
    evidence.mkdir(exist_ok=True)
    generated = []
    for candidate in descriptors(products):
        require(candidate.stat().st_size < 8 * 1024 * 1024,
                "Unexpectedly large .xctestrun descriptor")
        retained = evidence / candidate.name
        shutil.copyfile(candidate, retained)
        digest = sha256(candidate)
        require(sha256(retained) == digest, "Manifest evidence copy differs")
        generated.append({"name": candidate.name, "bytes": candidate.stat().st_size,
                          "sha256": digest})
    write_json(log / "06-generated-unit-manifests.json", generated)
    observed = inspect_manifest(products, context["configuration"])
    # Compatibility evidence name only; execution keeps the original __TESTROOT__.
    shutil.copyfile(evidence / observed["manifest"], log / "06-generated-unit.xctestrun")
    receipt.update(status="SEALED", products=observed, build_log_sha256=sha256(build_log))
    write_json(log / RECEIPT, receipt)
    return receipt


def admit(products, log, context, simulator):
    products, log = Path(products), Path(log)
    receipt = read_receipt(log, context, "SEALED")
    require(inspect_manifest(products, context["configuration"]) == receipt.get("products"),
            "Generated manifest or original test products changed after the successful build")
    owner = verify_owned_simulator(log, context["run_id"], context["run_attempt"])
    require(owner["simulator"] == simulator.upper(), "Test destination differs from this job's owned device")
    write_json(log / ADMISSION, {
        "schema_version": 1, "status": "ADMITTED_NOT_EXECUTED", "context": context,
        "build_receipt_sha256": sha256(log / RECEIPT), "products": receipt["products"],
        "ownership": owner, "qualification": receipt["qualification"],
    })
    return str((products / receipt["products"]["manifest"]).resolve(strict=True))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("prepare", "seal", "admit"))
    parser.add_argument("--repository", type=Path, required=True)
    parser.add_argument("--derived-data", type=Path, required=True)
    parser.add_argument("--log-dir", type=Path, required=True)
    parser.add_argument("--configuration", required=True)
    parser.add_argument("--selectors", required=True)
    parser.add_argument("--simulator-udid")
    args = parser.parse_args()
    products = (args.derived_data / "Build" / "Products").resolve()
    log = args.log_dir.resolve()
    try:
        context = build_context(args.repository, products, log, args.configuration, args.selectors)
        if args.action == "admit":
            require(args.simulator_udid is not None, "An owned simulator is required for admission")
            print(admit(products, log, context, args.simulator_udid))
        else:
            result = (prepare if args.action == "prepare" else seal)(products, log, context)
            print(json.dumps({"status": result["status"], "receipt": str(log / RECEIPT)}))
    except (OSError, RuntimeError, ValueError, KeyError, subprocess.SubprocessError,
            plistlib.InvalidFileException) as error:
        print("Current unit-test product admission failed: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
