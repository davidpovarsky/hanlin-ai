"""Accept only the fifteen native cancellation consumers on explicitly composed07431.

Original accepted cases remain separately attributed to their own executions.
The old e7 negative control is a historical reference, not a07431 baseline.
"""
import hashlib
import json
from pathlib import Path
import shutil

from verify_native_tool_candidate import EXPECTED, inspect_result, signature
from verify_stop_continuation_delta import EXPECTED as DELTA_EXPECTED

PRODUCER = "07431abccbfb151ca2dab67bca6cf86fcb2bd3b8"
OLD_PRODUCER = "e7bf34111e603ca977becd007dd4e5bb109af857"
SELECTOR = "HanlinNativeToolCancellationRecheck"
REFERENCE_PATH = "Scripts/CI/Tests/Fixtures/native-cancellation-07431"
REFERENCE_SHA256 = "676dbcdb376fa334925385bf6ce0b17e777cb2b24b74168a3edcd7d5a250c6c0"
CORE_SUITE = "HanlinAppleToolInputBoundaryTests"
BRIDGE_SUITE = "HanlinAppleToolSessionBridgeTests"
DELTA_SUITE = "HanlinProducerStopContinuationTests"
BRIDGE_METHODS = [
    "nativeFrameworkHandoffUsesCanonicalExecutorAndHistory",
    "nativeDenialReturnsThroughCanonicalHistory",
    "nativeNumericSiblingCannotPartiallyExecute",
    "nativeCancellationStopsAwaitingExecutor",
]
CORE_EXPECTED = {
    CORE_SUITE: {name: args for name, args in EXPECTED["CoreTests"][CORE_SUITE].items()
                 if name != "cloudOriginalInputStillHasExactProvenance"},
    DELTA_SUITE: {"nativeNumericStopToolCannotContinueOrReachHost": None},
}
SDK_EXPECTED = {BRIDGE_SUITE: {name: None for name in BRIDGE_METHODS}}
CORE_SELECTORS = ["HanlinChatCoreTests/" + signature(suite + "/" + name, args)
                  for suite, methods in CORE_EXPECTED.items() for name, args in methods.items()]
SDK_SELECTORS = ["HanlinAgentCoreTests/" + signature(suite + "/" + name, args)
                 for suite, methods in SDK_EXPECTED.items() for name, args in methods.items()]
HEADER_EXPECTED = {BRIDGE_SUITE: {name: None for name in BRIDGE_METHODS},
                   "HanlinAppleToolHeaderAdmissionTests": {"rejectsUnsupportedTransportHeader": None}}
BRIDGE_EXPECTED = {BRIDGE_SUITE: {name: None for name in BRIDGE_METHODS + ["nativeGeneratePreservesToolCalls"]}}
TOOLCHAIN = ("select-xcode", "xcode", "swift", "macos-sdk", "ios-sdk", "os")
OLD_NULL_EXITS = ("core_test_exit", "sdk_test_exit", "delta_test_exit", "baseline_core_exit")
UNRELATED_FLAGS = (
    "composer_validation_only", "nativescript_metadata_validation_only", "runtime_job_foundation_only",
    "markdown_renderer_validation_only", "code_fence_webkit_validation_only", "diagnostics_capture_validation_only",
    "testflight_upload", "runtime_bundle_only", "runtime_publish_release", "phase1_validation_only",
    "fast_validation_only", "nativescript_poc_only", "force_clean_build", "measure_warm_rebuild",
    "simulator_e2e_only", "full_validation",
)


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError("Native cancellation admission rejected: " + message)


def safe_file(root, relative):
    path = Path(relative)
    require(not path.is_absolute() and ".." not in path.parts, "evidence path escaped its root")
    return root / path


def frozen_reference(reference):
    require(sha(reference / "reference.json") == REFERENCE_SHA256, "frozen reference digest changed")
    manifest = read(reference / "reference.json")
    for relative, digest in manifest["files_sha256"].items():
        require(sha(safe_file(reference, relative)) == digest, "frozen original changed: " + relative)
    return manifest


def source_snapshot(reference, qualification, label, path):
    relative = qualification["snapshot_paths"][label][path]
    raw = safe_file(reference, relative).read_bytes()
    source_map = read(reference / "current-source-sha256.json") if label == "current" else read(
        reference / label / "tested-source-sha256.json")
    require(hashlib.sha256(raw).hexdigest() == source_map[path], "source snapshot binding differs")
    return raw.decode()


def function(text, marker):
    require(text.count(marker) == 1, "ambiguous source function boundary: " + marker)
    start = text.index(marker)
    end = text.index("\n    }\n", start) + len("\n    }\n")
    return text[start:end]


def source_qualification(evidence, reference, manifest):
    expected = read(reference / "current-source-sha256.json")
    actual = read(evidence / "tested-source-sha256.json")
    require(len(expected) == 404 and actual == expected, "complete composed package source differs")
    qualification = read(reference / "qualification.json")
    require(qualification["current_packages_source_commit"] == manifest["current_packages_source_commit"],
            "composed source origin changed")
    for label in manifest["origins"]:
        old = read(reference / label / "tested-source-sha256.json")
        require(old.keys() == actual.keys(), "original package inventory changed")
        differences = {path: {"before": old[path], "after": actual[path]}
                       for path in old if old[path] != actual[path]}
        require(differences == qualification["compared_source_deltas"][label],
                "unqualified source difference from " + label)
    # The direct provider path and immutable public-executor fixture are exactly
    # the source that actually passed doGenerate in452823; engine is not invoked.
    bridge = "Packages/HanlinAgentSDK/Sources/HanlinAgentCore/Providers/HanlinAppleToolSessionBridge.swift"
    bridge_tests = "Packages/HanlinAgentSDK/Tests/HanlinAgentCoreTests/HanlinAppleToolSessionBridgeTests.swift"
    for path in (bridge, bridge_tests):
        require(actual[path] == read(reference / "bridge/tested-source-sha256.json")[path],
                "direct doGenerate dependency changed")
    for path in (
        "Packages/HanlinAgentSDK/Sources/HanlinAgentCore/Providers/HanlinAppleOnDeviceProvider.swift",
        "Packages/HanlinAgentSDK/Sources/HanlinAgentCore/Providers/HanlinAppleToolSchema.swift",
        "Packages/HanlinAgentSDK/Sources/HanlinAgentCore/Providers/HanlinAppleToolHistory.swift",
        "Packages/HanlinAgentSDK/Tests/HanlinAgentCoreTests/HanlinAppleToolSchemaTests.swift",
    ):
        require(actual[path] == read(reference / "c93/tested-source-sha256.json")[path],
                "independent provider/schema/history source changed")
    boundary = "Packages/HanlinPlatform/Tests/HanlinChatCoreTests/HanlinAppleToolInputBoundaryTests.swift"
    current_boundary = source_snapshot(reference, qualification, "current", boundary)
    for name in EXPECTED["CoreTests"][CORE_SUITE]:
        marker = "    func " + name + "("
        require(function(current_boundary, marker) ==
                function(source_snapshot(reference, qualification, "c93", boundary), marker),
                "original Core assertion body changed: " + name)
    current_tests = source_snapshot(reference, qualification, "current", bridge_tests)
    helper_marker = "private struct NativeToolSessionBridgeChecks {"
    require(current_tests.count(helper_marker) == 1, "private native helper boundary changed")
    current_helper = current_tests.split(helper_marker)[1]
    for label, names in (
        ("c93", ("nativeSchemaConstructorsAndStructuredNumberRejection", "invalidCanonicalHistoriesFailBeforeGeneration")),
        ("header", ("rejectsUnsupportedTransportHeader",)),
    ):
        original_helper = source_snapshot(reference, qualification, label, bridge_tests).split(helper_marker)[1]
        for name in names:
            marker = "    func " + name + "("
            require(function(current_helper, marker) == function(original_helper, marker),
                    "independent reused helper changed: " + name)
    before_history = "        let history = try HanlinAppleToolHistory(options.prompt)"
    current_bridge = source_snapshot(reference, qualification, "current", bridge)
    header_bridge = source_snapshot(reference, qualification, "header", bridge)
    require(current_bridge.split(before_history)[0] == header_bridge.split(before_history)[0],
            "early Authorization rejection guard changed")
    tail_marker = "    private static let schemaJSON = "
    require(current_tests.split(tail_marker)[1] ==
            source_snapshot(reference, qualification, "header", bridge_tests).split(tail_marker)[1],
            "independent native immutable fixture changed")
    current_workflow = read(evidence / "workflow-sha256.json")
    old_workflow = read(reference / "c93/workflow-sha256.json")
    for path in ("Scripts/CI/IntegrationValidation/verify_native_tool_candidate.py",
                 "Scripts/CI/IntegrationValidation/xcresult_to_xunit.py", "Scripts/CI/select_stable_xcode.py"):
        require(current_workflow[path] == old_workflow[path], "common proof/toolchain selection changed")
    require(current_boundary == source_snapshot(reference, qualification, "delta", boundary),
            "already-executed finite delta fixture changed")
    # Pin the complete reviewed transformation. The map/actor-method comparison
    # was recorded from exact Git objects, not from package version strings.
    before = read(reference / "producer-e7-sha256.json")
    after = read(reference / "producer-07431-sha256.json")
    actor = qualification["only_changed_producer_path"]
    require(qualification["producer_before"] == OLD_PRODUCER and qualification["producer_after"] == PRODUCER and
            qualification["production_maps_except_changed_method_equal"] is True and
            before.keys() == after.keys() and {p for p in before if before[p] != after[p]} == {actor},
            "producer change exceeds the reviewed continuation guard")
    return qualification


def check_original(reference, label, origin, evidence):
    folder = reference / label
    run, artifact = read(folder / "terminal-run.json"), read(folder / "artifact-receipt.json")
    require(run["id"] == origin["run_id"] and run["run_attempt"] == origin["run_attempt"] and
            run["head_sha"] == origin["source"] and run["status"] == "completed",
            "original run/source binding changed: " + label)
    require(all(artifact[key] == origin[key] for key in
                ("run_id", "run_attempt", "source", "artifact_id", "zip_sha256")) and
            artifact["api_digest_verified"] is True and artifact["api_run_source_verified"] is True and
            artifact["zip_crc"] == "PASS", "original artifact authentication changed: " + label)
    require(read(folder / "process-status.json") == origin["original_process_status"],
            "original process attribution changed")
    require((folder / "producer-commit.txt").read_text().strip() == origin["producer"],
            "original producer attribution changed")
    current_commands, old_commands = read(evidence / "commands.json"), read(folder / "commands.json")
    for name in TOOLCHAIN:
        current = [c for c in current_commands if c["name"] == name]
        old = [c for c in old_commands if c["name"] == name]
        require(len(current) == len(old) == 1 and current[0]["exit_code"] == old[0]["exit_code"] == 0,
                "toolchain observation missing: " + label + "/" + name)
        for command, root in ((current[0], evidence), (old[0], folder)):
            for stream in ("stdout", "stderr"):
                item = command[stream]
                require(sha(safe_file(root, item["file"])) == item["sha256"], "toolchain output changed")
        require(safe_file(evidence, current[0]["stdout"]["file"]).read_bytes() ==
                safe_file(folder, old[0]["stdout"]["file"]).read_bytes(),
                "Apple toolchain/SDK/OS/architecture changed: " + label + "/" + name)
    for package in ("core", "sdk"):
        current_raw = (evidence / (package + "-Package.resolved")).read_bytes()
        target_raw = (reference / "delta" / (package + "-Package.resolved")).read_bytes()
        require(current_raw == target_raw, "current actual raw dependency lock changed")
        before = read(folder / (package + "-Package.resolved"))
        after = json.loads(current_raw)
        pins = before["pins"]
        for pin in pins:
            if pin["identity"] == "swift-ai-sdk":
                require(pin["state"]["revision"] == origin["producer"], "original raw producer lock changed")
                pin["state"]["revision"] = PRODUCER
        require(before["version"] == after["version"] and pins == after["pins"],
                "an unrelated dependency changed across the producer qualification")


def original_cases(reference, label, name, expected, failed=(), baseline=False):
    cases, methods, errors = inspect_result(reference / label, name, expected, baseline=baseline)
    expected_errors = [] if not failed else sorted(
        [name + ": failed or skipped execution"] +
        [name + ": unexpected aggregate status for " + identity for identity in failed])
    require(errors == expected_errors, "original result inventory/shape changed: " + label + "/" + name)
    require({case["id"] for case in cases if case["status"] == "FAIL"} ==
            (set(failed) if not baseline else {case["id"] for case in cases if case["expected_status"] == "FAIL"}),
            "original failed identities changed")
    require(all(case["status"] in ("PASS", "FAIL") for case in cases), "original case not executed")
    return cases


def validate_reuse(evidence):
    reference = evidence / "cancellation-reuse-original"
    manifest = frozen_reference(reference)
    source = (evidence / "tested-source-commit.txt").read_text().strip()
    require(source == (evidence / "workflow-commit.txt").read_text().strip(), "source/workflow differs")
    require((evidence / "producer-commit.txt").read_text().strip() == PRODUCER, "current producer differs")
    qualification = source_qualification(evidence, reference, manifest)
    for label, origin in manifest["origins"].items():
        check_original(reference, label, origin, evidence)
    core = original_cases(reference, "c93", "CoreTests", EXPECTED["CoreTests"])
    sdk = original_cases(reference, "c93", "SDKTests", EXPECTED["SDKTests"],
                         {BRIDGE_SUITE + "/" + name for name in BRIDGE_METHODS})
    header = original_cases(reference, "header", "SDKTests", HEADER_EXPECTED,
                            {BRIDGE_SUITE + "/" + name for name in BRIDGE_METHODS if "NumericSibling" not in name})
    bridge = original_cases(reference, "bridge", "SDKTests", BRIDGE_EXPECTED,
                            {BRIDGE_SUITE + "/nativeCancellationStopsAwaitingExecutor"})
    delta = original_cases(reference, "delta", "StopContinuationTests", DELTA_EXPECTED)
    selected = {
        "c93": [case for case in core + sdk if
                case["method"] == CORE_SUITE + "/cloudOriginalInputStillHasExactProvenance" or
                case["method"].startswith("HanlinAppleToolSchemaTests/") or case["method"] in {
                    BRIDGE_SUITE + "/nativeSchemaConstructorsAndStructuredNumberRejection",
                    BRIDGE_SUITE + "/invalidCanonicalHistoriesFailBeforeGeneration"}],
        "header": [case for case in header if case["method"] ==
                   "HanlinAppleToolHeaderAdmissionTests/rejectsUnsupportedTransportHeader"],
        "bridge": [case for case in bridge if case["method"] == BRIDGE_SUITE + "/nativeGeneratePreservesToolCalls"],
        "delta": [case for case in delta if case["method"] != DELTA_SUITE + "/nativeNumericStopToolCannotContinueOrReachHost"],
    }
    require({name: len(cases) for name, cases in selected.items()} ==
            {"c93": 17, "header": 1, "bridge": 1, "delta": 2}, "reused partition/count differs")
    reused = []
    for label, cases in selected.items():
        origin = manifest["origins"][label]
        for case in cases:
            require(case["status"] == "PASS", "failed original case cannot be reused")
            case.update(execution="REUSED_VERIFIED", source_commit=origin["source"],
                        run_id=origin["run_id"], run_attempt=origin["run_attempt"],
                        producer_commit=origin["producer"], artifact_id=origin["artifact_id"])
            reused.append(case)
    # This deliberately does not call the old e7 validate_reuse against07431.
    # Its original fixed manifest, statuses and twelve leaves remain historical.
    require(sha(reference / "baseline/reference.json") ==
            "ba8a05d787ab250ad4400c85cea842e5b7ec23e5a8af4d3f6ec1c70c94a5afb2",
            "historical e7 baseline manifest changed")
    require(read(reference / "baseline/process-status.json")["baseline_core_exit"] == 65,
            "historical baseline was not an ordinary test failure")
    baseline = original_cases(reference, "baseline", "BaselineCoreTests", EXPECTED["CoreTests"], baseline=True)
    require(len(baseline) == 12 and all(case["status"] == case["expected_status"] for case in baseline),
            "historical baseline12 differs")
    for case in baseline:
        case.update(execution="HISTORICAL_REFERENCE_ONLY", run_id=45240721804, run_attempt=2,
                    source_commit="f31147911a74e8984f2a510d6e11aec0bfb12975", producer_commit=OLD_PRODUCER)
    return json.loads(json.dumps(dict(
        mode="REUSED_VERIFIED", current_source_commit=source, current_producer_commit=PRODUCER,
        reference_manifest_sha256=REFERENCE_SHA256,
        reused_cases=sorted(reused, key=lambda row: row["id"]), reused_invocations=21,
        historical_baseline_cases=baseline, historical_baseline_current_equivalence=False,
        source_qualification=qualification)))


def prepare_reuse(repository, evidence):
    shutil.copytree(repository / REFERENCE_PATH, evidence / "cancellation-reuse-original")
    receipt = validate_reuse(evidence)
    (evidence / "cancellation-reuse.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


def validate_execution(evidence, statuses):
    route = read(evidence / "selected-route.json")
    require(route["exact_test_selector"] == SELECTOR and
            route["target_validation_group"] == "agent_sdk_exact_source_proof" and
            route["baseline"] == "HISTORICAL_REFERENCE_ONLY", "wrong reviewed opt-in route")
    require(set(route.get("unrelated_flags", {})) == set(UNRELATED_FLAGS) and
            all(value is False or value == "false" for value in route["unrelated_flags"].values()),
            "an unrelated workflow flag is enabled or missing")
    require(all(key in statuses and statuses[key] is None for key in OLD_NULL_EXITS),
            "unselected old processes must have explicit null exits")
    require(statuses.get("accepted_cases_execution") == "REUSED_VERIFIED" and
            statuses.get("baseline_execution") == "HISTORICAL_REFERENCE_ONLY", "reuse attribution differs")
    commands = read(evidence / "commands.json")
    require(not any(c["name"] in {"CoreTests", "SDKTests", "BaselineCoreTests", "StopContinuationTests", "ProducerTests"}
                    for c in commands), "unselected old process invoked")
    tests = [command for command in commands if command["argv"][:2] == ["xcodebuild", "test"]]
    require(len(tests) == 2, "exactly two narrowed macOS test processes required")
    for name, selectors, directory, key in (
        ("NativeCoreTests", CORE_SELECTORS, "HanlinPlatform", "native_core_test_exit"),
        ("NativeSDKTests", SDK_SELECTORS, "HanlinAgentSDK", "native_sdk_test_exit"),
    ):
        matching = [command for command in tests if command["name"] == name]
        require(len(matching) == 1, "missing/duplicate narrowed process")
        command = matching[0]
        argv = command["argv"]
        require(len(argv) == 13 + len(selectors) and argv[:2] == ["xcodebuild", "test"] and argv[2] == "-scheme" and
                argv[3] in (directory, directory + "-Package") and
                argv[4:7] == ["-destination", "platform=macOS", "-derivedDataPath"] and
                Path(argv[7]).name == "MacDerivedData" and argv[8] == "-resultBundlePath" and
                Path(argv[9]).name == name + ".xcresult" and
                argv[10:13] == ["-skipPackagePluginValidation", "-skipMacroValidation", "CODE_SIGNING_ALLOWED=NO"] and
                command["cwd"].endswith("/Packages/" + directory), "wrong native test target")
        selected = [value.removeprefix("-only-testing:") for value in argv if value.startswith("-only-testing:")]
        require(sorted(selected) == sorted(selectors), "wrong exact method signatures/selection")
        require(type(statuses.get(key)) is int and statuses[key] == command["exit_code"],
                "narrowed current process exit differs from its original command")
    builds = [command for command in commands if command["argv"][:2] == ["xcodebuild", "build"]]
    require(len(builds) == 1 and builds[0]["name"] == "IOSBuild", "one current dependent build required")
    build = builds[0]
    expected = ["xcodebuild", "build", "-scheme", "HanlinAgentCore", "-destination",
                "generic/platform=iOS Simulator", "-derivedDataPath", None, "-resultBundlePath", None,
                "-skipPackagePluginValidation", "-skipMacroValidation", "CODE_SIGNING_ALLOWED=NO"]
    argv = build["argv"]
    require(len(argv) == len(expected) and all(value is None or argv[i] == value for i, value in enumerate(expected)) and
            Path(argv[7]).name == "IOSDerivedData" and Path(argv[9]).name == "IOSBuild.xcresult" and
            build["cwd"].endswith("/Packages/HanlinAgentSDK"), "wrong current iOS build")
    require(type(statuses.get("ios_build_exit")) is int and statuses["ios_build_exit"] == build["exit_code"] == 0 and
            statuses.get("ios_build_execution") == "EXECUTED", "new engine requires actual iOS compile")
    for command in tests + builds:
        for stream in ("stdout", "stderr"):
            record = command[stream]
            require(sha(safe_file(evidence, record["file"])) == record["sha256"], "current native log changed")
    require(b"** BUILD SUCCEEDED **" in safe_file(evidence, build["stdout"]["file"]).read_bytes(),
            "current build success marker absent")
    posts = read(evidence / "post-build-resolution.json")
    require(len(posts) == 2 and len({row["raw_file"] for row in posts}) == 2, "two actual post-build locks required")
    for package, directory in (("core", "HanlinPlatform"), ("sdk", "HanlinAgentSDK")):
        matching = [row for row in posts if row["source_path"].endswith("/Packages/" + directory + "/Package.resolved")]
        require(len(matching) == 1, "wrong package raw lock")
        row = matching[0]; path = safe_file(evidence, row["raw_file"])
        require(sha(path) == row["sha256"] and path.read_bytes() == (evidence / (package + "-Package.resolved")).read_bytes(),
                "post-build lock changed")
    checkouts = read(evidence / "producer-checkouts.json")
    require(set(checkouts) == {"core", "sdk"}, "both producer checkouts must be verified")
    expected_map = read(evidence / "cancellation-reuse-original/producer-07431-sha256.json")
    for label, checkout in checkouts.items():
        directory = "HanlinAgentSDK" if label == "sdk" else "HanlinPlatform"
        require(checkout["path"].endswith("/Packages/" + directory + "/.build/checkouts/swift-ai-sdk") and
                checkout["commit"] == PRODUCER and checkout["status"] == "" and
                checkout["source_sha256"] == expected_map, "current producer checkout differs")
    return dict(mode="EXECUTED", command=build, producer_checkouts=["core", "sdk"])


def summarize(evidence):
    core, core_methods, errors = inspect_result(evidence, "NativeCoreTests", CORE_EXPECTED)
    sdk, sdk_methods, sdk_errors = inspect_result(evidence, "NativeSDKTests", SDK_EXPECTED)
    errors += sdk_errors
    try:
        statuses = read(evidence / "process-status.json")
    except (OSError, ValueError):
        statuses = {}
    cases, methods = core + sdk, core_methods + sdk_methods
    reuse, build = None, None
    try:
        reuse = validate_reuse(evidence)
        require(read(evidence / "cancellation-reuse.json") == reuse, "reuse receipt differs")
        build = validate_execution(evidence, statuses)
        current_ids = {case["id"] for case in cases}
        reused_ids = {case["id"] for case in reuse["reused_cases"]}
        require(len(current_ids) == 15 and len(reused_ids) == 21 and not current_ids & reused_ids,
                "current/reused exact invocation partition overlaps or is incomplete")
    except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
        errors.append(str(error))
    for case in cases:
        case["execution"] = "EXECUTED" if case["status"] in ("PASS", "FAIL") else "NOT_RUN"
    passed = (not errors and len(cases) == 15 and len(methods) == 7 and
              all(case["status"] == "PASS" for case in cases) and
              all(type(statuses.get(key)) is int and statuses[key] == 0 for key in
                  ("preparation_exit", "native_core_test_exit", "native_sdk_test_exit")) and
              reuse is not None and build is not None)
    return dict(
        scope="Fifteen affected native cancellation consumers on explicitly composed07431;21 separately source-qualified original product passes",
        status="PASS" if passed else "BLOCKED", expected_invocations=15, expected_method_groups=7,
        current_producer_commit=PRODUCER, cases=cases, methods=methods, errors=sorted(errors),
        process_status=statuses, reuse_admission=reuse,
        reused_cases=[] if reuse is None else reuse["reused_cases"],
        historical_baseline_execution="HISTORICAL_REFERENCE_ONLY",
        historical_baseline_current_equivalence=False,
        ios_agent_core_compile="PASS" if build is not None else
            "NOT_RUN" if statuses.get("ios_build_exit") is None else
            "BLOCKED" if statuses.get("ios_build_exit") == 0 else "FAIL",
        current_ios_build=build, shipping_native_tool_capability=False, system_model_generation="NOT_RUN",
    )
