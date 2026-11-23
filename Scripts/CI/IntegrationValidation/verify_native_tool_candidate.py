"""Verify the narrowly selected real-Apple candidate controls, including the old-engine negative control."""
import json
from pathlib import Path
import sys
from xcresult_to_xunit import nodes

EXPECTED = {
    "CoreTests": {
        "HanlinAppleToolInputBoundaryTests": [
            "nativeInputStaysNormalized",
            "nativeNumericInputCannotReachApprovalOrExecutor",
            "cloudOriginalInputStillHasExactProvenance",
        ]
    },
    "SDKTests": {
        "HanlinAppleToolSchemaTests": [
            "rejectsUnrepresentedSemantics", "validatesSupportedSubsetBeforeHandoff"
        ],
        "HanlinAppleToolSessionBridgeTests": [
            "nativeFrameworkHandoffUsesCanonicalExecutorAndHistory",
            "nativeDenialReturnsThroughCanonicalHistory",
            "nativeNumericSiblingCannotPartiallyExecute",
            "nativeCancellationStopsAwaitingExecutor",
            "nativeGeneratePreservesToolCalls",
            "nativeSchemaConstructorsAndStructuredNumberRejection",
            "invalidCanonicalHistoriesFailBeforeGeneration",
        ],
    },
}


def read_cases(root, name):
    try:
        data = json.loads((root / (name + ".json")).read_text())
        all_nodes = list(nodes(data))
    except (OSError, ValueError):
        return [], []
    return [node for node in all_nodes if node.get("nodeType") == "Test Case"], all_nodes


def summarize(root):
    statuses = json.loads((root / "process-status.json").read_text())
    records, errors = [], []
    for result, suites in EXPECTED.items():
        cases, all_nodes = read_cases(root, result)
        allowed = {suite + "/" + method for suite, methods in suites.items() for method in methods}
        actual = {}
        for case in cases:
            identity = case.get("nodeIdentifier", "")
            normalized = identity.split("(")[0]
            if normalized not in allowed or normalized in actual:
                errors.append(result + ": unexpected or duplicate case " + identity)
            actual[normalized] = case.get("result")
            records.append({"result": result, "id": identity,
                            "status": {"Passed": "PASS", "Failed": "FAIL"}.get(case.get("result"), "NOT_RUN")})
        for identity in allowed - actual.keys():
            records.append({"result": result, "id": identity, "status": "NOT_RUN"})
            errors.append(result + ": missing " + identity)
        if any(node.get("result") in ["Skipped", "Failed"] for node in all_nodes):
            errors.append(result + ": failed or skipped execution")

    baseline, baseline_nodes = read_cases(root, "BaselineCoreTests")
    baseline_expected = {method: ("Passed" if method == "cloudOriginalInputStillHasExactProvenance" else "Failed")
                         for method in EXPECTED["CoreTests"]["HanlinAppleToolInputBoundaryTests"]}
    baseline_actual = {case.get("nodeIdentifier", "").split("/")[-1].split("(")[0]: case.get("result")
                       for case in baseline}
    baseline_ok = (baseline_actual == baseline_expected and len(baseline) == len(baseline_expected)
                   and statuses.get("baseline_core_exit") not in [None, 0]
                   and not any(node.get("result") == "Skipped" for node in baseline_nodes))
    if not baseline_ok:
        errors.append("Baseline did not reproduce precisely the expected native failures with the cloud control passing.")
    passed = (not errors and records and all(record["status"] == "PASS" for record in records)
              and statuses.get("core_test_exit") == 0 and statuses.get("sdk_test_exit") == 0
              and statuses.get("ios_build_exit") == 0 and statuses.get("preparation_exit") == 0)
    return {
        "scope": "original-provider-and-engine-with-real-FoundationModels-framework-and-deterministic-public-executor",
        "status": "PASS" if passed else "BLOCKED",
        "baseline_negative_control": "PASS" if baseline_ok else "BLOCKED",
        "baseline_actual_results": baseline_actual, "baseline_expected_results": baseline_expected,
        "cases": records, "errors": errors, "process_status": statuses,
        "ios_agent_core_compile": "PASS" if statuses.get("ios_build_exit") == 0 else "NOT_RUN" if statuses.get("ios_build_exit") is None else "FAIL",
        "shipping_native_tool_capability": False,
        "system_model_generation": "NOT_RUN",
        "not_asserted": ["eligible SystemLanguageModel execution", "real native model tool choice or continuation",
                         "original Host app runtime acceptance", "shipping native-tool enablement"],
    }


if __name__ == "__main__":
    result = summarize(Path(sys.argv[1]))
    print(json.dumps(result, indent=2))
    sys.exit(0 if result["status"] == "PASS" else 1)
