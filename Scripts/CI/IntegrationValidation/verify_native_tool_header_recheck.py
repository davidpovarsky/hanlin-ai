"""Exact five-case header repair, with source-qualified reuse of28 earlier passes."""
import hashlib
import json
from pathlib import Path
import shutil

from reuse_native_tool_baseline import validate_reuse
from verify_native_tool_candidate import EXPECTED, inspect_result

REFERENCE_PATH = "Scripts/CI/Tests/Fixtures/native-tool-header-45259715158"
REFERENCE_SHA256 = "785bf2b27c4c9ec5b4c107135a52bc9568f1c12f4e07cea67c469b12c3310ddd"
SOURCE = "c93b966e6c378f56b98d7805b5086a72d3061803"
PRODUCER = "e7bf34111e603ca977becd007dd4e5bb109af857"
FAILED_METHODS = [
    "nativeFrameworkHandoffUsesCanonicalExecutorAndHistory",
    "nativeDenialReturnsThroughCanonicalHistory",
    "nativeNumericSiblingCannotPartiallyExecute",
    "nativeCancellationStopsAwaitingExecutor",
]
HEADER_EXPECTED = {
    "HanlinAppleToolSessionBridgeTests": {name: None for name in FAILED_METHODS},
    "HanlinAppleToolHeaderAdmissionTests": {"rejectsUnsupportedTransportHeader": None},
}
HEADER_SELECTORS = [
    "HanlinAgentCoreTests/" + suite + "/" + method
    for suite, methods in HEADER_EXPECTED.items() for method in methods
]
PERMITTED_SOURCE = {
    "Packages/HanlinAgentSDK/Sources/HanlinAgentCore/Providers/HanlinAppleToolSessionBridge.swift":
        "0ec97844b22e808240bda44715c02c23576c96a91d3eaa4e458afb45085e1c18",
    "Packages/HanlinAgentSDK/Tests/HanlinAgentCoreTests/HanlinAppleToolSessionBridgeTests.swift":
        "74cc8de390b586e4aa4826755375bcc0d3f4f05c1c6404ed725c846b3f9a15ef",
}
TOOLCHAIN = ("xcode", "swift", "macos-sdk", "ios-sdk", "os")


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError("Header reuse rejected: " + message)


def validate_header_inputs(evidence, reference):
    require(sha(reference / "reference.json") == REFERENCE_SHA256, "reference manifest changed")
    manifest = read(reference / "reference.json")
    require(manifest["run_id"] == 45259715158 and manifest["run_attempt"] == 1 and
            manifest["source_commit"] == SOURCE and manifest["producer_commit"] == PRODUCER and
            manifest["artifact_id"] == 14860542354 and manifest["zip_sha256"] ==
            "e3301405f1b28281ca93cc1ce5086c19a0f2e25976ffee2da4eff825dbcf3e09",
            "original identity changed")
    for name, digest in manifest["files_sha256"].items():
        require(Path(name).name == name and sha(reference / name) == digest,
                "original bytes changed: " + name)
    run = read(reference / "terminal-run.json")
    artifact = read(reference / "artifact-receipt.json")
    require(run["id"] == 45259715158 and run["run_attempt"] == 1 and
            run["head_sha"] == SOURCE and run["status"] == "completed" and
            artifact["artifact_id"] == 14860542354 and artifact["source"] == SOURCE and
            artifact["zip_sha256"] == manifest["zip_sha256"] and
            artifact["api_digest_verified"] is True and artifact["api_run_source_verified"] is True and
            artifact["zip_crc"] == "PASS", "original artifact/source authentication changed")
    old_status = read(reference / "process-status.json")
    require(old_status == dict(preparation_exit=0, baseline_core_exit=None, core_test_exit=0,
                               sdk_test_exit=65, ios_build_exit=0, baseline_execution="REUSED_VERIFIED"),
            "original process statuses changed")
    current_source = (evidence / "tested-source-commit.txt").read_text().strip()
    require(current_source == (evidence / "workflow-commit.txt").read_text().strip() and
            (evidence / "producer-commit.txt").read_text().strip() == PRODUCER,
            "current source/workflow/producer binding changed")
    old_sources = read(reference / "tested-source-sha256.json")
    current_sources = read(evidence / "tested-source-sha256.json")
    require(len(old_sources) == 404 and set(current_sources) == set(old_sources),
            "package source closure changed")
    require(manifest["permitted_current_source_sha256"] == PERMITTED_SOURCE,
            "reviewed source admission changed")
    for relative, digest in old_sources.items():
        require(current_sources[relative] == PERMITTED_SOURCE.get(relative, digest),
                "unreviewed source change: " + relative)
    for index, relative in enumerate(PERMITTED_SOURCE):
        require(sha(reference / f"source-before-{index}.swift") == old_sources[relative],
                "original reviewed source changed")
    # Existing32 verifier, baseline admission and result walker remain byte-identical.
    old_workflow = read(reference / "workflow-sha256.json")
    current_workflow = read(evidence / "workflow-sha256.json")
    for name in ("verify_native_tool_candidate.py", "reuse_native_tool_baseline.py", "xcresult_to_xunit.py"):
        relative = "Scripts/CI/IntegrationValidation/" + name
        require(current_workflow[relative] == old_workflow[relative],
                "shared proof implementation changed: " + name)
    for name in ("core", "sdk"):
        require((evidence / (name + "-Package.resolved")).read_bytes() ==
                (reference / (name + "-Package.resolved")).read_bytes(),
                "actual raw " + name + " dependency lock changed")
    commands = read(evidence / "commands.json")
    require(not any(c["name"] in {"CoreTests", "BaselineCoreTests"} for c in commands),
            "an accepted core or baseline suite was executed again")
    old_commands = read(reference / "commands.json")
    toolchain = {}
    for name in TOOLCHAIN:
        current = [c for c in commands if c["name"] == name]
        original = [c for c in old_commands if c["name"] == name]
        require(len(current) == len(original) == 1 and current[0]["exit_code"] == original[0]["exit_code"] == 0,
                "missing toolchain observation: " + name)
        current_out, original_out = current[0]["stdout"], original[0]["stdout"]
        require(sha(evidence / current_out["file"]) == current_out["sha256"] and
                sha(reference / original_out["file"]) == original_out["sha256"] and
                (evidence / current_out["file"]).read_bytes() == (reference / original_out["file"]).read_bytes(),
                "Apple toolchain/OS/architecture changed: " + name)
        toolchain[name] = current_out["sha256"]
    baseline = validate_reuse(evidence)  # Retains every original strict e7 baseline guard.
    core, core_methods, core_errors = inspect_result(reference, "CoreTests", EXPECTED["CoreTests"])
    sdk, sdk_methods, sdk_errors = inspect_result(reference, "SDKTests", EXPECTED["SDKTests"])
    failed_ids = {"HanlinAppleToolSessionBridgeTests/" + name for name in FAILED_METHODS}
    expected_errors = sorted(["SDKTests: failed or skipped execution"] +
                             ["SDKTests: unexpected aggregate status for " + value for value in failed_ids])
    require(not core_errors and len(core) == 12 and len(core_methods) == 3 and
            all(row["status"] == "PASS" for row in core), "original Core12 is incomplete")
    require(sdk_errors == expected_errors and len(sdk) == 20 and len(sdk_methods) == 9 and
            {row["id"] for row in sdk if row["status"] == "FAIL"} == failed_ids and
            all(row["status"] in {"PASS", "FAIL"} for row in sdk),
            "original SDK20 outcomes or argument identities changed")
    passed = sorted([row for row in core + sdk if row["status"] == "PASS"], key=lambda row: row["id"])
    require(len(passed) == 28 and [row["id"] for row in passed] == manifest["eligible_case_ids"] and
            sorted(failed_ids) == manifest["excluded_failed_case_ids"], "reuse case inventory changed")
    for row in passed:
        row.update(execution="REUSED_VERIFIED", source_commit=SOURCE, run_id=45259715158, run_attempt=1)
    return json.loads(json.dumps(dict(
        mode="REUSED_VERIFIED", run_id=45259715158, run_attempt=1, source_commit=SOURCE,
        artifact_id=14860542354, zip_sha256=manifest["zip_sha256"],
        reference_manifest_sha256=REFERENCE_SHA256, current_source_commit=current_source,
        producer_commit=PRODUCER, source_files=404, reviewed_changed_source=PERMITTED_SOURCE,
        raw_lock_sha256={name: sha(evidence / (name + "-Package.resolved")) for name in ("core", "sdk")},
        toolchain_sha256=toolchain, reused_cases=passed, excluded_original_failures=sorted(failed_ids),
        baseline_source_commit=baseline["source_commit"],
        qualification="Only User-Agent admission and one added negative control differ. The original28 passing inputs do not enter the repaired nonempty-User-Agent branch."
    )))


def prepare_header_reuse(repository, evidence):
    reference = evidence / "header-reuse-original"
    shutil.copytree(repository / REFERENCE_PATH, reference)
    receipt = validate_header_inputs(evidence, reference)
    (evidence / "header-reuse.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


def validate_header_reuse(evidence):
    actual = validate_header_inputs(evidence, evidence / "header-reuse-original")
    require(read(evidence / "header-reuse.json") == actual, "current reuse receipt differs")
    return actual


def summarize_header_recheck(evidence):
    cases, methods, errors = inspect_result(evidence, "SDKTests", HEADER_EXPECTED)
    try:
        statuses = read(evidence / "process-status.json")
    except (OSError, ValueError):
        statuses = {}
    reused, baseline_receipt = None, None
    baseline_cases, _, baseline_errors = inspect_result(
        evidence, "BaselineCoreTests", EXPECTED["CoreTests"], baseline=True)
    try:
        reused = validate_header_reuse(evidence)
        baseline_receipt = validate_reuse(evidence)
        require("core_test_exit" in statuses and "baseline_core_exit" in statuses and
                statuses["core_test_exit"] is None and statuses["baseline_core_exit"] is None,
                "reused tests require explicit null current process exits")
        require(statuses.get("baseline_execution") == "REUSED_VERIFIED" and
                statuses.get("accepted_cases_execution") == "REUSED_VERIFIED",
                "current reuse execution labels missing")
        commands = read(evidence / "commands.json")
        tests = [c for c in commands if c["argv"][:2] == ["xcodebuild", "test"]]
        require(len(tests) == 1 and tests[0]["name"] == "SDKTests", "current test process scope changed")
        selected = [x.removeprefix("-only-testing:") for x in tests[0]["argv"] if x.startswith("-only-testing:")]
        require(sorted(selected) == sorted(HEADER_SELECTORS), "current five method selectors changed")
        require(tests[0]["exit_code"] == statuses.get("sdk_test_exit"),
                "SDK test process status does not match its command")
        builds = [c for c in commands if c["argv"][:2] == ["xcodebuild", "build"]]
        require(len(builds) == 1 and builds[0]["name"] == "IOSBuild" and
                builds[0]["exit_code"] == statuses.get("ios_build_exit"),
                "current iOS build process or status missing")
        build_args = builds[0]["argv"]
        require(build_args[build_args.index("-scheme") + 1] == "HanlinAgentCore" and
                build_args[build_args.index("-destination") + 1] == "generic/platform=iOS Simulator",
                "current dependent iOS build scope changed")
    except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
        errors.append(str(error))
    baseline_ok = (baseline_receipt is not None and not baseline_errors and len(baseline_cases) == 12 and
                   all(row["status"] == row["expected_status"] for row in baseline_cases))
    for row in baseline_cases:
        row["execution"] = "REUSED_VERIFIED" if baseline_ok else "REUSE_INVALID"
    if not baseline_ok:
        errors.append("Original baseline12 reuse did not satisfy every guard.")
    errors += baseline_errors
    passed = (not errors and len(cases) == len(methods) == 5 and
              all(row["status"] == "PASS" for row in cases) and reused is not None and
              all(type(statuses.get(key)) is int and statuses[key] == 0
                  for key in ("preparation_exit", "sdk_test_exit", "ios_build_exit")))
    for row in cases:
        row["execution"] = "EXECUTED" if row["status"] in {"PASS", "FAIL"} else "NOT_RUN"
    return dict(
        scope="Original native header repair: five executed cases and28 separately source-qualified reused passes",
        status="PASS" if passed else "BLOCKED", expected_invocations=5,
        expected_method_groups=5, cases=cases, methods=methods,
        reused_cases=[] if reused is None else reused["reused_cases"],
        reused_invocations=0 if reused is None else 28, reuse_admission=reused,
        baseline_negative_control="PASS" if baseline_ok else "BLOCKED",
        baseline_execution="REUSED_VERIFIED" if baseline_ok else "REUSE_INVALID",
        baseline_cases=baseline_cases, baseline_reuse=baseline_receipt,
        errors=sorted(errors), process_status=statuses,
        ios_agent_core_compile="PASS" if statuses.get("ios_build_exit") == 0 else
            "NOT_RUN" if statuses.get("ios_build_exit") is None else "FAIL",
        shipping_native_tool_capability=False, system_model_generation="NOT_RUN",
    )
