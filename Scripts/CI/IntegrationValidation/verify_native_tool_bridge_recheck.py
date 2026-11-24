"""Five affected native profile controls; reuse only 27 independent passes plus one early-rejection pass."""
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
BRIDGE_EXPECTED = {"HanlinAppleToolSessionBridgeTests": {
    name: None for name in FAILED_METHODS + ["nativeGeneratePreservesToolCalls"]
}}
BRIDGE_SELECTORS = [
    "HanlinAgentCoreTests/" + suite + "/" + method + "()"
    for suite, methods in BRIDGE_EXPECTED.items() for method in methods
]
PERMITTED_SOURCE = {
    "Packages/HanlinAgentSDK/Sources/HanlinAgentCore/Providers/HanlinAppleToolSessionBridge.swift":
        "2f3441ea603b186f71bbb13b5faf37f4e1b01c475dd0a0e7df7faeb97dbff418",
    "Packages/HanlinAgentSDK/Tests/HanlinAgentCoreTests/HanlinAppleToolSessionBridgeTests.swift":
        "1296391072e837f04d05423ecc7c611f59556b414fd5ab085b0096c140e54f57",
}
TOOLCHAIN = ("xcode", "swift", "macos-sdk", "ios-sdk", "os")


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError("Bridge reuse rejected: " + message)


def validate_bridge_inputs(evidence, reference, negative):
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
    affected_generate = "HanlinAppleToolSessionBridgeTests/nativeGeneratePreservesToolCalls"
    passed = sorted([row for row in core + sdk if row["status"] == "PASS" and row["id"] != affected_generate], key=lambda row: row["id"])
    require(len(passed) == 27 and [row["id"] for row in passed] == [value for value in manifest["eligible_case_ids"] if value != affected_generate] and
            sorted(failed_ids) == manifest["excluded_failed_case_ids"], "reuse case inventory changed")
    for row in passed:
        row.update(execution="REUSED_VERIFIED", source_commit=SOURCE, run_id=45259715158, run_attempt=1)
    negative_case = validate_negative_reference(evidence, reference, negative)
    passed.append(negative_case)
    passed.sort(key=lambda row: row["id"])
    return json.loads(json.dumps(dict(
        mode="REUSED_VERIFIED", run_id=45259715158, run_attempt=1, source_commit=SOURCE,
        artifact_id=14860542354, zip_sha256=manifest["zip_sha256"],
        reference_manifest_sha256=REFERENCE_SHA256, current_source_commit=current_source,
        producer_commit=PRODUCER, source_files=404, reviewed_changed_source=PERMITTED_SOURCE,
        raw_lock_sha256={name: sha(evidence / (name + "-Package.resolved")) for name in ("core", "sdk")},
        toolchain_sha256=toolchain, reused_cases=passed, excluded_original_failures=sorted(failed_ids),
        baseline_source_commit=baseline["source_commit"],
        qualification="Core12, Schema13 and two pure schema/history methods have unchanged source and do not enter NativeProfile/run. The Authorization case from452735 rejects in the byte-identical early settings guard. All five runtime/profile methods execute again.",
        negative_reference_manifest_sha256=NEGATIVE_REFERENCE_SHA256,
        independent_passes=27, early_rejection_passes=1,
        excluded_affected_prior_pass=affected_generate,
        source_partition=source_partition(evidence, reference, negative)
    )))


def prepare_bridge_reuse(repository, evidence):
    reference = evidence / "bridge-reuse-original"
    shutil.copytree(repository / REFERENCE_PATH, reference)
    negative = evidence / "bridge-negative-original"
    shutil.copytree(repository / NEGATIVE_REFERENCE_PATH, negative)
    receipt = validate_bridge_inputs(evidence, reference, negative)
    (evidence / "bridge-reuse.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


def validate_bridge_reuse(evidence):
    actual = validate_bridge_inputs(evidence, evidence / "bridge-reuse-original", evidence / "bridge-negative-original")
    require(read(evidence / "bridge-reuse.json") == actual, "current reuse receipt differs")
    return actual



NEGATIVE_REFERENCE_PATH = "Scripts/CI/Tests/Fixtures/native-tool-bridge-45273580428"
NEGATIVE_REFERENCE_SHA256 = "3f62752b77b154d3e028c5bef517488a97336c768dd6e53fce097e3e2b025615"
NEGATIVE_SOURCE = "2c41a1b7ed6b191be7529550ae1ca4501632ce8d"
NEGATIVE_ID = "HanlinAppleToolHeaderAdmissionTests/rejectsUnsupportedTransportHeader"


def source_partition(evidence, earlier, negative):
    """Admit only the reviewed code changes and bind each unaffected call path."""
    sources = read(evidence / "tested-source-sha256.json")
    current = []
    for index, relative in enumerate(PERMITTED_SOURCE):
        path = evidence / f"source-current-{index}.swift"
        require(sha(path) == sources[relative] == PERMITTED_SOURCE[relative],
                "current reviewed source bytes are absent or changed")
        current.append(path.read_text())
    old_bridge = (negative / "source-before-0.swift").read_text()
    old_tests = (negative / "source-before-1.swift").read_text()
    earlier_tests = (earlier / "source-before-1.swift").read_text()
    require(current[1].split('@Suite("FoundationModels transport metadata admission")')[0].strip() ==
            earlier_tests.split("// Availability belongs")[0].strip(),
            "original bridge discovery wrappers changed")
    helper_marker = "private struct NativeToolSessionBridgeChecks {"
    require(all(text.count(helper_marker) == 1 for text in (current[1], old_tests, earlier_tests)),
            "private helper source boundary changed")
    current_tests = current[1].split(helper_marker)[1]
    old_tests = old_tests.split(helper_marker)[1]
    earlier_tests = earlier_tests.split(helper_marker)[1]

    def block(text, first, after):
        require(text.count(first) == text.count(after) == 1,
                "reviewed Swift source markers became ambiguous")
        start = text.index(first)
        end = text.index(after, start)
        return text[start:end]

    # This is the original settings guard, before history/schema/session setup.
    marker = "        let history = try HanlinAppleToolHistory(options.prompt)"
    require(current[0].count(marker) == old_bridge.count(marker) == 1,
            "early settings guard boundary changed")
    guard = current[0].split(marker)[0]
    require(guard == old_bridge.split(marker)[0], "reused Authorization guard changed")
    pure = block(current_tests,
                 "    func nativeSchemaConstructorsAndStructuredNumberRejection() throws {",
                 "    private func assertCanonicalContinuation(")
    require(pure == block(earlier_tests,
                 "    func nativeSchemaConstructorsAndStructuredNumberRejection() throws {",
                 "    private func assertCanonicalContinuation("),
            "reused pure schema/history methods changed")
    header = block(current_tests, "    func rejectsUnsupportedTransportHeader() async throws {",
                   "    func nativeGeneratePreservesToolCalls() async throws {")
    require(header == block(old_tests, "    func rejectsUnsupportedTransportHeader() async throws {",
                   "    func nativeGeneratePreservesToolCalls() async throws {"),
            "reused Authorization method changed")
    tail_marker = "    private static let schemaJSON = "
    require(current[1].count(tail_marker) == old_tests.count(tail_marker) == 1,
            "shared immutable fixture boundary changed")
    fixture = current[1].split(tail_marker)[1]
    require(fixture == old_tests.split(tail_marker)[1], "reused schema/model/executor fixture changed")
    digest = lambda text: hashlib.sha256(text.encode()).hexdigest()
    core = {path: value for path, value in sources.items()
            if path.startswith("Packages/HanlinPlatform/")}
    require(len(core) == 238, "independent Core package closure changed")
    return dict(
        changed_files=PERMITTED_SOURCE,
        unchanged_core_files=len(core),
        core_closure_sha256=digest(json.dumps(core, sort_keys=True)),
        pure_schema_history_helpers_sha256=digest(pure),
        early_header_guard_sha256=digest(guard),
        header_negative_helper_sha256=digest(header),
        immutable_fixture_tail_sha256=digest(fixture),
        explanation={
            "Core12": "Complete original Platform package closure unchanged; no dependency on the changed AgentSDK bridge.",
            "Schema13": "Same schema implementation and original separate test file; no NativeProfile/run call.",
            "Pure2": "Exact original schema/history helper bodies and their unchanged implementations; no provider request.",
            "Authorization1": "Same original provider and immutable fixture; byte-identical early settings guard throws before native history/session/profile setup.",
            "Affected5": "Every runtime/profile consumer executes again, including the previously passing direct doGenerate method."
        })

def validate_negative_reference(evidence, earlier, reference):
    require(sha(reference / "reference.json") == NEGATIVE_REFERENCE_SHA256,
            "negative-control reference manifest changed")
    manifest = read(reference / "reference.json")
    require(manifest["run_id"] == 45273580428 and manifest["run_attempt"] == 1 and
            manifest["source_commit"] == NEGATIVE_SOURCE and manifest["producer_commit"] == PRODUCER and
            manifest["artifact_id"] == 14867146247 and manifest["zip_sha256"] ==
            "068f4711ff9b32dc053ccba34933dd6cd57667c08d02bdfae9cceaa95dcecf48",
            "negative-control original identity changed")
    require(manifest["reviewed_current_source_sha256"] == PERMITTED_SOURCE and
            manifest["eligible_case_ids"] == [NEGATIVE_ID], "negative-control source admission changed")
    for name, digest in manifest["files_sha256"].items():
        require(Path(name).name == name and sha(reference / name) == digest,
                "negative-control original bytes changed: " + name)
    run, artifact = read(reference / "terminal-run.json"), read(reference / "artifact-receipt.json")
    require(run["id"] == 45273580428 and run["run_attempt"] == 1 and
            run["head_sha"] == NEGATIVE_SOURCE and run["status"] == "completed" and
            artifact["artifact_id"] == 14867146247 and artifact["source"] == NEGATIVE_SOURCE and
            artifact["zip_sha256"] == manifest["zip_sha256"] and
            artifact["api_digest_verified"] is True and artifact["api_run_source_verified"] is True and
            artifact["zip_crc"] == "PASS", "negative-control artifact authentication changed")
    statuses = read(reference / "process-status.json")
    require(statuses["preparation_exit"] == 0 and statuses["sdk_test_exit"] == 65 and
            all(statuses[key] is None for key in ("core_test_exit", "baseline_core_exit", "ios_build_exit")),
            "negative-control original process attribution changed")
    original_sources, current_sources = read(reference / "tested-source-sha256.json"), read(evidence / "tested-source-sha256.json")
    require(len(original_sources) == 404 and set(original_sources) == set(current_sources),
            "negative-control complete package inventory changed")
    for relative, digest in original_sources.items():
        require(current_sources[relative] == PERMITTED_SOURCE.get(relative, digest),
                "unreviewed change since the negative control: " + relative)
    for index, relative in enumerate(PERMITTED_SOURCE):
        require(sha(reference / f"source-before-{index}.swift") == original_sources[relative],
                "negative-control source snapshot changed")
    for package in ("core", "sdk"):
        require((evidence / (package + "-Package.resolved")).read_bytes() ==
                (reference / (package + "-Package.resolved")).read_bytes(),
                "negative-control actual raw lock changed: " + package)
    commands, old_commands = read(evidence / "commands.json"), read(reference / "commands.json")
    for name in ("select-xcode", *TOOLCHAIN):
        actual = [command for command in commands if command["name"] == name]
        old = [command for command in old_commands if command["name"] == name]
        require(len(actual) == len(old) == 1 and actual[0]["exit_code"] == old[0]["exit_code"] == 0,
                "negative-control toolchain query missing: " + name)
        for stream in ("stdout", "stderr"):
            for command, root in ((actual[0], evidence), (old[0], reference)):
                record = command[stream]
                require(sha(root / record["file"]) == record["sha256"],
                        "negative-control toolchain log changed")
        require((evidence / actual[0]["stdout"]["file"]).read_bytes() ==
                (reference / old[0]["stdout"]["file"]).read_bytes(),
                "negative-control native toolchain/OS changed: " + name)
    cases, methods, errors = inspect_result(reference, "SDKTests", HEADER_EXPECTED)
    failed = {"HanlinAppleToolSessionBridgeTests/" + name for name in
              ("nativeFrameworkHandoffUsesCanonicalExecutorAndHistory",
               "nativeDenialReturnsThroughCanonicalHistory", "nativeCancellationStopsAwaitingExecutor")}
    expected_errors = sorted(["SDKTests: failed or skipped execution"] +
                             ["SDKTests: unexpected aggregate status for " + identity for identity in failed])
    require(errors == expected_errors and len(cases) == len(methods) == 5 and
            {row["id"] for row in cases if row["status"] == "FAIL"} == failed and
            all(row["status"] in {"PASS", "FAIL"} for row in cases),
            "original Header5 identities/outcomes changed")
    selected = [row for row in cases if row["id"] == NEGATIVE_ID and row["status"] == "PASS"]
    require(len(selected) == 1, "the original Authorization control did not pass")
    case = selected[0]
    case.update(execution="REUSED_VERIFIED", source_commit=NEGATIVE_SOURCE, run_id=45273580428, run_attempt=1)
    return case


def validate_current_execution(evidence, statuses):
    commands = read(evidence / "commands.json")
    tests = [command for command in commands if command["argv"][:2] == ["xcodebuild", "test"]]
    require(len(tests) == 1 and tests[0]["name"] == "SDKTests", "current test process scope changed")
    selected = [value.removeprefix("-only-testing:") for value in tests[0]["argv"] if value.startswith("-only-testing:")]
    require(sorted(selected) == sorted(BRIDGE_SELECTORS), "current five exact method selectors changed")
    require(tests[0]["argv"][4:6] == ["-destination", "platform=macOS"] and
            tests[0]["cwd"].endswith("/Packages/HanlinAgentSDK"), "current native test target changed")
    require(tests[0]["exit_code"] == statuses.get("sdk_test_exit"),
            "current test process exit differs from its original command")
    require(all(key in statuses and statuses[key] is None for key in ("core_test_exit", "baseline_core_exit")),
            "reused Core/baseline requires null current process exits")
    require(statuses.get("baseline_execution") == statuses.get("accepted_cases_execution") == "REUSED_VERIFIED",
            "current reuse labels missing")
    builds = [command for command in commands if command["argv"][:2] == ["xcodebuild", "build"]]
    require(len(builds) == 1 and builds[0]["name"] == "IOSBuild", "one current dependent iOS compile is required")
    build = builds[0]
    expected = ["xcodebuild", "build", "-scheme", "HanlinAgentCore",
                "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", None,
                "-resultBundlePath", None, "-skipPackagePluginValidation", "-skipMacroValidation",
                "CODE_SIGNING_ALLOWED=NO"]
    argv = build["argv"]
    require(len(argv) == len(expected) and all(value is None or argv[index] == value
            for index, value in enumerate(expected)) and
            Path(argv[7]).name == "IOSDerivedData" and Path(argv[9]).name == "IOSBuild.xcresult" and
            build["cwd"].endswith("/Packages/HanlinAgentSDK"),
            "current iOS build command/configuration changed")
    require(type(statuses.get("ios_build_exit")) is int and statuses["ios_build_exit"] == build["exit_code"] == 0 and
            statuses.get("ios_build_execution") == "EXECUTED", "changed bridge requires successful current iOS compilation")
    for command in (tests[0], build):
        for stream in ("stdout", "stderr"):
            record = command[stream]
            require(sha(evidence / record["file"]) == record["sha256"], "current native command log changed")
    require(b"** BUILD SUCCEEDED **" in (evidence / build["stdout"]["file"]).read_bytes(),
            "current iOS build success marker absent")
    posts = read(evidence / "post-build-resolution.json")
    require(len(posts) == 2, "current post-build dependency locks are incomplete")
    bindings = {}
    for package, directory in (("core", "HanlinPlatform"), ("sdk", "HanlinAgentSDK")):
        matches = [row for row in posts if row["source_path"].endswith("/Packages/" + directory + "/Package.resolved")]
        require(len(matches) == 1, "duplicate/missing post-build lock for " + package)
        row = matches[0]
        raw = evidence / row["raw_file"]
        require(not Path(row["raw_file"]).is_absolute() and ".." not in Path(row["raw_file"]).parts and
                sha(raw) == row["sha256"] and raw.read_bytes() == (evidence / (package + "-Package.resolved")).read_bytes(),
                "current post-build lock changed for " + package)
        bindings[package] = row["sha256"]
    return dict(mode="EXECUTED", current_source_commit=(evidence / "tested-source-commit.txt").read_text().strip(),
                command=build, post_build_raw_lock_sha256=bindings)


def summarize_bridge_recheck(evidence):
    cases, methods, errors = inspect_result(evidence, "SDKTests", BRIDGE_EXPECTED)
    try:
        statuses = read(evidence / "process-status.json")
    except (OSError, ValueError):
        statuses = {}
    reused, baseline_receipt, ios_receipt = None, None, None
    baseline_cases, _, baseline_errors = inspect_result(
        evidence, "BaselineCoreTests", EXPECTED["CoreTests"], baseline=True)
    try:
        reused = validate_bridge_reuse(evidence)
        baseline_receipt = validate_reuse(evidence)
        ios_receipt = validate_current_execution(evidence, statuses)
        reused_ids = {row["id"] for row in reused["reused_cases"]}
        current_ids = {row["id"] for row in cases}
        require(len(reused_ids) == 28 and len(current_ids) == 5 and not reused_ids & current_ids,
                "executed and reused invocation identities overlap or are incomplete")
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
                  for key in ("preparation_exit", "sdk_test_exit", "ios_build_exit")) and ios_receipt is not None)
    for row in cases:
        row["execution"] = "EXECUTED" if row["status"] in {"PASS", "FAIL"} else "NOT_RUN"
    return dict(
        scope="Five affected original native bridge methods with current iOS build;27 independent original passes plus one early-header rejection reused separately",
        status="PASS" if passed else "BLOCKED", expected_invocations=5, expected_method_groups=5,
        cases=cases, methods=methods,
        reused_cases=[] if reused is None else reused["reused_cases"],
        reused_invocations=0 if reused is None else 28, reuse_admission=reused,
        baseline_negative_control="PASS" if baseline_ok else "BLOCKED",
        baseline_execution="REUSED_VERIFIED" if baseline_ok else "REUSE_INVALID",
        baseline_cases=baseline_cases, baseline_reuse=baseline_receipt,
        errors=sorted(errors), process_status=statuses,
        ios_agent_core_compile="PASS" if ios_receipt is not None else
            "NOT_RUN" if statuses.get("ios_build_exit") is None else "FAIL",
        current_ios_build=ios_receipt,
        shipping_native_tool_capability=False, system_model_generation="NOT_RUN",
    )
