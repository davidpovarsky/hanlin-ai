"""Reuse only the authenticated, unchanged twelve-case native baseline.

This never executes tests or retrieves artifacts. The retained originals are
bound to one reviewed artifact, the complete 238-file HanlinPlatform baseline
overlay, its actual raw dependency lock, producer commit and Apple toolchain.
"""
import hashlib
import json
from pathlib import Path
import shutil

REFERENCE_SHA256 = "ba8a05d787ab250ad4400c85cea842e5b7ec23e5a8af4d3f6ec1c70c94a5afb2"
REFERENCE_PATH = "Scripts/CI/Tests/Fixtures/native-tool-candidate-45240721804/baseline-proof"
SOURCE = "f31147911a74e8984f2a510d6e11aec0bfb12975"
BASE = "7523f45cf8ea180a8e30f511ff0fbd3bb5ccae6d"
PRODUCER = "e7bf34111e603ca977becd007dd4e5bb109af857"
VARIANT_FILES = {
    "Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinAISDKAgentEngine.swift":
        "aaf8ae687d478710c2b4388f19350164a606facd02b70375743c808629cbe524",
    "Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinAISDKModels.swift":
        "c8e0ecfdda95960195c3454f76d35fa5bd6c48c08781e920d39903157416eb92",
}
TOOLCHAIN = {"xcode": "05-xcode.stdout.log", "swift": "06-swift.stdout.log",
             "macos-sdk": "07-macos-sdk.stdout.log", "ios-sdk": "08-ios-sdk.stdout.log",
             "os": "09-os.stdout.log"}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text())


def require(condition, message):
    if not condition:
        raise ValueError("Baseline reuse rejected: " + message)


def validate_inputs(evidence, reference):
    require(sha(reference / "reference.json") == REFERENCE_SHA256, "reference manifest digest changed")
    manifest = read(reference / "reference.json")
    require(manifest["source_commit"] == SOURCE and manifest["baseline_commit"] == BASE and
            manifest["producer_commit"] == PRODUCER and manifest["run_id"] == 45240721804 and
            manifest["run_attempt"] == 2 and manifest["artifact_id"] == 14853499914,
            "reference identity changed")
    for name, digest in manifest["files_sha256"].items():
        require(Path(name).name == name and sha(reference / name) == digest, "original bytes changed: " + name)
    require(read(reference / "process-status.json")["baseline_core_exit"] == 65, "baseline did not exit 65")
    run = read(reference / "terminal-run.json")
    require(run["id"] == 45240721804 and run["run_attempt"] == 2 and run["head_sha"] == SOURCE and
            run["status"] == "completed", "original run binding changed")
    original_receipt = read(reference / "artifact-receipt.json")
    require(original_receipt["zip_sha256"] == manifest["zip_sha256"] and
            original_receipt["api_digest_verified"] is True and
            original_receipt["api_run_source_verified"] is True and original_receipt["zip_crc"] == "PASS",
            "artifact authentication is absent")
    current_source = (evidence / "tested-source-commit.txt").read_text().strip()
    require(current_source and current_source == (evidence / "workflow-commit.txt").read_text().strip(),
            "current source/workflow mismatch")
    require((evidence / "producer-commit.txt").read_text().strip() == PRODUCER, "producer pin changed")

    original_sources = read(reference / "tested-source-sha256.json")
    current_sources = read(evidence / "tested-source-sha256.json")
    original_scope = {p: digest for p, digest in original_sources.items()
                      if p.startswith("Packages/HanlinPlatform/")}
    current_scope = {p: digest for p, digest in current_sources.items()
                     if p.startswith("Packages/HanlinPlatform/")}
    original_variant = read(reference / "baseline-variant.json")
    current_variant = read(evidence / "baseline-variant.json")
    for variant, source_hashes in ((original_variant, original_sources), (current_variant, current_sources)):
        require(variant["base_commit"] == BASE and set(variant["files"]) == set(VARIANT_FILES),
                "baseline overlay definition changed")
        for path, digest in VARIANT_FILES.items():
            require(variant["files"][path]["baseline_sha256"] == digest and
                    variant["files"][path]["candidate_sha256"] == source_hashes[path],
                    "baseline overlay/source binding changed: " + path)
    original_scope.update(VARIANT_FILES)
    current_scope.update(VARIANT_FILES)
    require(len(original_scope) == 238 and current_scope == original_scope,
            "complete baseline package, tests, manifest or resource inputs changed")
    require((evidence / "core-Package.resolved").read_bytes() ==
            (reference / "core-Package.resolved").read_bytes(), "actual raw dependency lock changed")

    commands = read(evidence / "commands.json")
    require(not any(c["name"] == "BaselineCoreTests" for c in commands), "baseline was also executed")
    clean = [c for c in commands if c["name"] == "producer-clean"]
    require(len(clean) == 1 and clean[0]["exit_code"] == 0 and
            PRODUCER in clean[0]["argv"], "resolved producer cleanliness was not verified")
    for stream in ("stdout", "stderr"):
        record = clean[0][stream]
        require(sha(evidence / record["file"]) == record["sha256"], "producer check output changed")
    toolchain = {}
    for name, original_file in TOOLCHAIN.items():
        matches = [c for c in commands if c["name"] == name]
        require(len(matches) == 1 and matches[0]["exit_code"] == 0, "missing current toolchain query: " + name)
        record = matches[0]["stdout"]
        require(sha(evidence / record["file"]) == record["sha256"], "current query output changed: " + name)
        require((evidence / record["file"]).read_bytes() == (reference / original_file).read_bytes(),
                "Apple toolchain/OS/architecture changed: " + name)
        toolchain[name] = record["sha256"]

    from verify_native_tool_candidate import EXPECTED, inspect_result
    cases, methods, errors = inspect_result(reference, "BaselineCoreTests", EXPECTED["CoreTests"], baseline=True)
    require(not errors and len(cases) == 12 and len(methods) == 3 and
            sum(case["status"] == "FAIL" for case in cases) == 10 and
            sum(case["status"] == "PASS" for case in cases) == 2,
            "original exact invocation outcomes do not match")
    require((evidence / "BaselineCoreTests.json").read_bytes() ==
            (reference / "BaselineCoreTests.json").read_bytes(), "retained baseline export differs")
    return dict(
        mode="REUSED_VERIFIED", source_commit=SOURCE, run_id=45240721804, run_attempt=2,
        artifact_id=14853499914, zip_sha256=manifest["zip_sha256"],
        reference_manifest_sha256=REFERENCE_SHA256, current_source_commit=current_source,
        baseline_commit=BASE, producer_commit=PRODUCER,
        baseline_scope_files=len(current_scope),
        baseline_scope_sha256=hashlib.sha256(json.dumps(current_scope, sort_keys=True).encode()).hexdigest(),
        raw_lock_sha256=sha(evidence / "core-Package.resolved"), toolchain_sha256=toolchain,
        original_baseline_exit=65, original_baseline_invocations={"FAIL": 10, "PASS": 2},
        baseline_export_sha256=sha(reference / "BaselineCoreTests.json"),
        scope="Original baseline outcomes reused; no baseline process executed in the current run.")


def prepare_reuse(repository, evidence):
    reference = evidence / "baseline-reuse-original"
    shutil.copytree(repository / REFERENCE_PATH, reference)
    shutil.copyfile(reference / "BaselineCoreTests.json", evidence / "BaselineCoreTests.json")
    receipt = validate_inputs(evidence, reference)
    (evidence / "baseline-reuse.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


def validate_reuse(evidence):
    actual = validate_inputs(evidence, evidence / "baseline-reuse-original")
    require(read(evidence / "baseline-reuse.json") == actual, "reuse receipt differs from verified inputs")
    return actual
