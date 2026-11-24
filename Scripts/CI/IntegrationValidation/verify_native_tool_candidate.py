"""Verify exact Apple invocations, including each argument tuple and the old-engine control.

Only original xcresult exports are accepted by the runner. Argument displays are
matched to complete source-bound tuples using the observed Swift Testing format:
quoted strings (embedded quotes remain literal), comma-space-separated values,
and lowercase booleans. Unknown or truncated displays block. Aggregate Test Case
results never stand in for parameterized executions.
"""
import json
from pathlib import Path
import re
import sys
from urllib.parse import parse_qs, unquote, urlsplit
from xcresult_to_xunit import nodes

NUMERIC_INPUTS = [
    '{"number":0}',
    '{"nested":[{"number":1.25}]}',
    '{"number":9007199254740993}',
    '{"nested":{"number":1e100}}',
]
UNSUPPORTED_SCHEMAS = [
    '{"type":"object","properties":{"n":{"type":"number"}},"additionalProperties":false}',
    '{"type":"object","properties":{"n":{"type":"integer"}},"additionalProperties":false}',
    '{"type":"object","properties":{"s":{"type":"string","pattern":"x+"}},"additionalProperties":false}',
    '{"type":"object","properties":{"s":{"type":"string","minLength":1}},"additionalProperties":false}',
    '{"type":"object","properties":{}}',
    '{"type":"object","additionalProperties":true}',
    '{"type":"object","properties":{},"required":["missing"],"additionalProperties":false}',
    '{"type":"object","properties":{"x":{"type":"string"}},"required":["x","x"],"additionalProperties":false}',
    '{"type":"object","properties":{"a":{"type":"array","items":{"type":"string"},"minItems":2,"maxItems":1}},"additionalProperties":false}',
    '{"type":"object","properties":{"a":{"type":"array","items":{"type":"string"},"uniqueItems":true}},"additionalProperties":false}',
    '{"type":"object","properties":{"x":{"type":["string","null"]}},"additionalProperties":false}',
    '{"type":"object","properties":{},"oneOf":[{}],"additionalProperties":false}',
]
# None denotes a non-parameterized method; all other rows name every invocation.
EXPECTED = {
    "CoreTests": {
        "HanlinAppleToolInputBoundaryTests": {
            "nativeInputStaysNormalized": [(False,), (True,)],
            "nativeNumericInputCannotReachApprovalOrExecutor":
                [(value, approval) for value in NUMERIC_INPUTS for approval in (False, True)],
            "cloudOriginalInputStillHasExactProvenance": [(False,), (True,)],
        }
    },
    "SDKTests": {
        "HanlinAppleToolSchemaTests": {
            "rejectsUnrepresentedSemantics": [(value,) for value in UNSUPPORTED_SCHEMAS],
            "validatesSupportedSubsetBeforeHandoff": None,
        },
        "HanlinAppleToolSessionBridgeTests": {
            "nativeFrameworkHandoffUsesCanonicalExecutorAndHistory": None,
            "nativeDenialReturnsThroughCanonicalHistory": None,
            "nativeNumericSiblingCannotPartiallyExecute": None,
            "nativeCancellationStopsAwaitingExecutor": None,
            "nativeGeneratePreservesToolCalls": None,
            "nativeSchemaConstructorsAndStructuredNumberRejection": None,
            "invalidCanonicalHistoriesFailBeforeGeneration": None,
        },
    },
}
STATUS = {"Passed": "PASS", "Failed": "FAIL"}
DIAGNOSTIC_TYPES = {"Test Failure", "Runtime Warning", "Failure Message"}
FAILURE_TYPES = {"Test Failure", "Failure Message"}


def read_cases(root, name):
    try:
        data = json.loads((root / (name + ".json")).read_text())
        all_nodes = list(nodes(data))
    except (OSError, ValueError):
        return [], []
    return [node for node in all_nodes if node.get("nodeType") == "Test Case"], all_nodes


def argument_key(arguments):
    # Exact string bytes and Bool values matter; JSON objects inside strings are
    # not parsed/normalized, so a replacement or reformatted input cannot pass.
    return json.dumps(arguments, ensure_ascii=False, separators=(",", ":"))


def argument_display(arguments):
    # xcresult's Arguments.name is a Swift Testing display, not JSON. In the
    # authenticated SDK27 export, quotes inside String values are not escaped.
    # Only this finite, collision-checked expected inventory is admitted.
    if any(type(value) not in (str, bool) for value in arguments):
        raise ValueError("unsupported source argument type")
    return ", ".join(('"' + value + '"') if isinstance(value, str)
                     else ("true" if value else "false") for value in arguments)


def signature(identity, arguments):
    arity = 0 if arguments is None else len(arguments[0])
    return identity + "(" + "_:" * arity + ")"


def valid_method_url(url, identifier):
    if not isinstance(url, str):
        return False
    parsed = urlsplit(url)
    return (parsed.scheme == "test" and parsed.netloc == "com.apple.xcode"
            and unquote(parsed.path).endswith("/" + identifier)
            and not parsed.query and not parsed.fragment)


def valid_argument_url(url, parent):
    if not isinstance(url, str) or not isinstance(parent, str):
        return False
    parsed, expected = urlsplit(url), urlsplit(parent)
    query = parse_qs(parsed.query, keep_blank_values=True)
    return (parsed.scheme == expected.scheme and parsed.netloc == expected.netloc
            and parsed.path == expected.path and not parsed.fragment
            and set(query) == {"args"} and len(query["args"]) == 1
            and re.fullmatch(r"[0-9a-f]{64}", query["args"][0]) is not None)


def inspect_result(root, name, suites, baseline=False):
    cases, all_nodes = read_cases(root, name)
    allowed = {suite + "/" + method: arguments
               for suite, methods in suites.items() for method, arguments in methods.items()}
    actual, records, method_records, errors = {}, [], [], []
    seen_argument_nodes = set()
    seen_argument_urls = set()

    def expected_status(identity):
        return ("Failed" if baseline and
                not identity.endswith("/cloudOriginalInputStillHasExactProvenance") else "Passed")

    def record(identity, arguments, node=None):
        value = dict(result=name, method=identity, arguments=arguments,
                     id=identity if arguments is None else identity + " " + argument_key(arguments),
                     status=STATUS.get((node or {}).get("result"), "NOT_RUN"),
                     expected_status=STATUS[expected_status(identity)])
        if node is not None:
            value.update(node_identifier_url=node.get("nodeIdentifierURL"), argument_display=node.get("name"))
        records.append(value)

    for case in cases:
        raw_identity = case.get("nodeIdentifier", "")
        identity = raw_identity.split("(", 1)[0] if isinstance(raw_identity, str) else ""
        if identity not in allowed or identity in actual:
            errors.append(name + ": unexpected or duplicate method " + str(raw_identity))
            continue
        actual[identity] = case
        arguments = allowed[identity]
        if raw_identity != signature(identity, arguments):
            errors.append(name + ": unexpected method signature " + str(raw_identity))
        parent_url = case.get("nodeIdentifierURL")
        if not valid_method_url(parent_url, raw_identity):
            errors.append(name + ": missing or mismatched method URL " + identity)
        required_status = expected_status(identity)
        method_records.append(dict(result=name, id=raw_identity, status=STATUS.get(case.get("result"), "NOT_RUN"),
                                   expected_status=STATUS[required_status]))
        if case.get("result") != required_status:
            errors.append(name + ": unexpected aggregate status for " + identity)
        if case.get("result") == "Passed" and any(
                node.get("nodeType") in FAILURE_TYPES for node in nodes(case)):
            errors.append(name + ": passed aggregate contains failure diagnostics " + identity)
        children = case.get("children", [])
        if not isinstance(children, list) or any(not isinstance(child, dict) for child in children):
            errors.append(name + ": unknown children shape for " + identity)
            children = []
        if any(child.get("nodeType") not in DIAGNOSTIC_TYPES | {"Arguments"} for child in children):
            errors.append(name + ": unknown child type for " + identity)
        argument_nodes = [child for child in children if child.get("nodeType") == "Arguments"]
        if arguments is None:
            if argument_nodes:
                errors.append(name + ": singleton unexpectedly contains arguments " + identity)
            record(identity, None, case)
            continue

        expected_arguments = {argument_key(values): values for values in arguments}
        expected_displays = {argument_display(values): values for values in arguments}
        if len(expected_displays) != len(expected_arguments):
            errors.append(name + ": source argument displays collide for " + identity)
        seen_arguments = set()
        for child in argument_nodes:
            seen_argument_nodes.add(id(child))
            # Nested Arguments or unknown executable descendants are unsupported.
            descendants = [node for node in nodes(child) if node is not child and node.get("nodeType")]
            if any(node["nodeType"] not in DIAGNOSTIC_TYPES for node in descendants):
                errors.append(name + ": unsupported nested argument execution " + identity)
            child_url = child.get("nodeIdentifierURL")
            if not valid_argument_url(child_url, parent_url) or child_url in seen_argument_urls:
                errors.append(name + ": missing, duplicate or mismatched argument URL " + identity)
            if isinstance(child_url, str):
                seen_argument_urls.add(child_url)
            display = child.get("name")
            values = expected_displays.get(display) if isinstance(display, str) else None
            if values is None:
                errors.append(name + ": unknown or truncated argument display " + identity)
                continue
            key = argument_key(values)
            if key not in expected_arguments or key in seen_arguments:
                errors.append(name + ": unexpected or duplicate arguments " + identity + " " + key)
                continue
            seen_arguments.add(key)
            record(identity, values, child)
            if child.get("result") != required_status:
                errors.append(name + ": unexpected argument status " + identity + " " + key)
        for key in expected_arguments.keys() - seen_arguments:
            record(identity, expected_arguments[key])
            errors.append(name + ": missing arguments " + identity + " " + key)

    for identity in allowed.keys() - actual.keys():
        errors.append(name + ": missing method " + identity)
        for arguments in allowed[identity] if allowed[identity] is not None else [None]:
            record(identity, arguments)
    all_argument_nodes = {id(node) for node in all_nodes if node.get("nodeType") == "Arguments"}
    if all_argument_nodes != seen_argument_nodes:
        errors.append(name + ": argument executions exist outside the exact selected methods")
    if any(node.get("result") == "Skipped" or
           (not baseline and node.get("result") == "Failed") for node in all_nodes):
        errors.append(name + ": failed or skipped execution")
    return (sorted(records, key=lambda row: (row["result"], row["id"])),
            sorted(method_records, key=lambda row: (row["result"], row["id"])),
            sorted(errors))


def summarize(root):
    try:
        statuses = json.loads((root / "process-status.json").read_text())
        if not isinstance(statuses, dict):
            statuses = {}
    except (OSError, ValueError):
        statuses = {}
    records, methods, errors = [], [], []
    for name, suites in EXPECTED.items():
        new_records, new_methods, new_errors = inspect_result(root, name, suites)
        records += new_records; methods += new_methods; errors += new_errors
    baseline, baseline_methods, baseline_errors = inspect_result(
        root, "BaselineCoreTests", EXPECTED["CoreTests"], baseline=True)
    baseline_exit = statuses.get("baseline_core_exit")
    baseline_reuse = None
    baseline_execution = "EXECUTED" if baseline_exit is not None else "NOT_RUN"
    if statuses.get("baseline_execution") == "REUSED_VERIFIED":
        baseline_execution = "REUSE_INVALID"
        try:
            from reuse_native_tool_baseline import validate_reuse
            baseline_reuse = validate_reuse(root)
            if baseline_exit is not None:
                raise ValueError("Reused baseline cannot claim a current baseline process exit")
            baseline_execution = "REUSED_VERIFIED"
        except (OSError, ValueError, KeyError, TypeError) as error:
            baseline_errors.append(str(error))
    baseline_process_ok = ((type(baseline_exit) is int and baseline_exit == 65)
                           if baseline_execution == "EXECUTED"
                           else baseline_execution == "REUSED_VERIFIED")
    baseline_ok = (not baseline_errors and len(baseline) == 12 and baseline_process_ok and
                   all(case["status"] == case["expected_status"] for case in baseline))
    for case in baseline:
        case["execution"] = baseline_execution
    if not baseline_ok:
        errors.append("Baseline did not reproduce all 10 native failures and both passing cloud invocations.")
    errors += baseline_errors
    passed = (not errors and len(records) == 32 and len(methods) == 12 and
              all(record["status"] == "PASS" for record in records) and
              all(type(statuses.get(key)) is int and statuses[key] == 0
                  for key in ("core_test_exit", "sdk_test_exit", "ios_build_exit", "preparation_exit")))
    return {
        "scope": "original-provider-and-engine-with-real-FoundationModels-framework-and-deterministic-public-executor",
        "status": "PASS" if passed else "BLOCKED",
        "expected_invocations": 32, "expected_method_groups": 12,
        "baseline_negative_control": "PASS" if baseline_ok else "BLOCKED",
        "baseline_execution": baseline_execution, "baseline_reuse": baseline_reuse,
        "baseline_expected_invocations": {"FAIL": 10, "PASS": 2},
        "baseline_cases": baseline, "baseline_methods": baseline_methods,
        "cases": records, "methods": methods, "errors": sorted(errors), "process_status": statuses,
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
