"""Report only the three new original-engine .stop continuation controls."""
import hashlib
import json
from pathlib import Path
from verify_native_tool_candidate import inspect_result

PRODUCER = "07431abccbfb151ca2dab67bca6cf86fcb2bd3b8"
SUITE = "HanlinProducerStopContinuationTests"
METHODS = [
    "allowedStopToolContinuesThroughOriginalEngine",
    "deniedStopToolContinuesWithCorrelatedResult",
    "nativeNumericStopToolCannotContinueOrReachHost",
]
EXPECTED = {SUITE: {method: None for method in METHODS}}
SELECTORS = ["HanlinChatCoreTests/" + SUITE + "/" + method for method in METHODS]
COMPOSED_SOURCE = {
    "Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinAISDKAgentEngine.swift":
        "7738b399f1eff40ddd5e99ac9e3976c47f384d94ddb9ba8b37901080a49b3d45",
    "Packages/HanlinAgentSDK/Sources/HanlinAgentCore/Providers/HanlinAppleToolSessionBridge.swift":
        "0ec97844b22e808240bda44715c02c23576c96a91d3eaa4e458afb45085e1c18",
    "Packages/HanlinAgentSDK/Tests/HanlinAgentCoreTests/HanlinAppleToolSessionBridgeTests.swift":
        "74cc8de390b586e4aa4826755375bcc0d3f4f05c1c6404ed725c846b3f9a15ef",
}


def read(path):
    return json.loads(path.read_text())


def require(condition, message):
    if not condition:
        raise ValueError(message)


def summarize(evidence):
    cases, methods, errors = inspect_result(evidence, "StopContinuationTests", EXPECTED)
    try:
        statuses = read(evidence / "process-status.json")
    except (OSError, ValueError):
        statuses = {}
    source = None
    try:
        source = (evidence / "tested-source-commit.txt").read_text().strip()
        require(source == (evidence / "workflow-commit.txt").read_text().strip(),
                "Current source/workflow binding differs.")
        require((evidence / "producer-commit.txt").read_text().strip() == PRODUCER,
                "Current producer is not the deliberate07431 pin.")
        digests = read(evidence / "tested-source-sha256.json")
        require(all(digests.get(path) == digest for path, digest in COMPOSED_SOURCE.items()),
                "Composed native boundary/header sources differ from the reviewed inputs.")
        route = read(evidence / "selected-route.json")
        require(route["exact_test_selector"] == "HanlinStopContinuationDelta" and
                route["target_validation_group"] == "agent_sdk_exact_source_proof",
                "Wrong exact delta route.")
        commands = read(evidence / "commands.json")
        require(not any(c["name"] in {"CoreTests", "SDKTests", "BaselineCoreTests", "ProducerTests"} for c in commands),
                "An existing suite was executed instead of the three-case delta.")
        tests = [c for c in commands if c["argv"][:2] == ["xcodebuild", "test"]]
        require(len(tests) == 1 and tests[0]["name"] == "StopContinuationTests" and
                tests[0]["exit_code"] == statuses.get("delta_test_exit"), "Wrong current test process.")
        test_args = tests[0]["argv"]
        selected = [x.removeprefix("-only-testing:") for x in test_args if x.startswith("-only-testing:")]
        require(sorted(selected) == sorted(SELECTORS), "Wrong exact three-case selection.")
        require(test_args[test_args.index("-destination") + 1] == "platform=macOS",
                "Delta tests must not launch a simulator.")
        builds = [c for c in commands if c["argv"][:2] == ["xcodebuild", "build"]]
        require(len(builds) == 1 and builds[0]["name"] == "IOSBuild" and
                builds[0]["exit_code"] == statuses.get("ios_build_exit"), "Wrong current build process.")
        args = builds[0]["argv"]
        require(args[args.index("-scheme") + 1] == "HanlinAgentCore" and
                args[args.index("-destination") + 1] == "generic/platform=iOS Simulator",
                "Wrong current dependent iOS build scope.")
        require(all(key in statuses and statuses[key] is None for key in
                    ("core_test_exit", "sdk_test_exit", "baseline_core_exit")),
                "Unselected old suites require explicit null process exits.")
        locks = read(evidence / "post-build-resolution.json")
        require(len(locks) == 2 and len({lock["raw_file"] for lock in locks}) == 2,
                "Both distinct actual composed package locks are required.")
        packages = {Path(lock["source_path"]).parent.name for lock in locks}
        require(packages == {"HanlinAgentSDK", "HanlinPlatform"},
                "Raw locks must belong to both composed packages.")
        for lock in locks:
            relative = Path(lock["raw_file"])
            require(not relative.is_absolute() and relative.parts[0] == "raw-locks" and
                    len(relative.parts) == 2 and ".." not in relative.parts,
                    "Raw lock member escaped the evidence folder.")
            raw = (evidence / relative).read_bytes()
            require(hashlib.sha256(raw).hexdigest() == lock["sha256"], "Raw dependency lock digest differs.")
            pins = [pin for pin in json.loads(raw)["pins"] if pin["identity"] == "swift-ai-sdk"]
            require(len(pins) == 1 and pins[0]["state"]["revision"] == PRODUCER, "Raw lock is not pinned07431.")
    except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
        errors.append(str(error))
    passed = (not errors and len(cases) == len(methods) == 3 and
              all(row["status"] == "PASS" for row in cases) and
              all(type(statuses.get(key)) is int and statuses[key] == 0
                  for key in ("preparation_exit", "delta_test_exit", "ios_build_exit")))
    return dict(
        scope="Three new original-engine controls for non-toolCalls finish labels on the composed07431 candidate",
        status="PASS" if passed else "BLOCKED", source_commit=source, producer_commit=PRODUCER,
        expected_invocations=3, expected_method_groups=3, cases=cases, methods=methods,
        errors=sorted(errors), process_status=statuses, reused_cases=[],
        prior_e7_acceptance="SEPARATE_HISTORICAL_EVIDENCE_NOT_RELABELED_AS_CURRENT_EXECUTION",
        ios_agent_core_compile="PASS" if statuses.get("ios_build_exit") == 0 else
            "NOT_RUN" if statuses.get("ios_build_exit") is None else "FAIL",
        shipping_native_tool_capability=False, system_model_generation="NOT_RUN",
    )
