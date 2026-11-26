#!/usr/bin/env python3
"""Strict read-only verifier for the authenticated affected-test plan and ABI0.

API: verify_event_stream(path, plan, source_root, exit_code) -> JSON review.
Optional plan["selectedFamilies"] selects complete named families for one run.
The canonical plan (apart from that selector) is pinned. The caller must require
status == "EXECUTED_PASS"; a failed verification returns status "FAILED".

ABI0 has function IDs, but no structured case ID/argument value. Case proofs
therefore retain actual start/end records and their stream positions. They prove
the source-declared count of serialized case lifecycles, not unavailable ABI
parameter identities. Neither opaque IDs nor runtime results are synthesized.
"""
import hashlib
import json
import math
import re
from pathlib import Path

PLAN_SHA256 = "1fb18829d086ece1841a43fcc00c5f2a0d8a39c9ac140d98c0c7373c01bc6d52"
PLAN_CANONICAL_SHA256 = "80b58c996d58e361eb50b7344a5b594049111e4876bf8179017b881403610c3d"


def _require(condition, message):
    if not condition:
        raise ValueError(message)


def _digest(data):
    return hashlib.sha256(data).hexdigest()


def _json_object(pairs):
    result = {}
    for key, value in pairs:
        _require(key not in result, "Duplicate JSON key: " + key)
        result[key] = value
    return result


def _read_json(line):
    return json.loads(line, object_pairs_hook=_json_object,
                      parse_constant=lambda value: (_ for _ in ()).throw(
                          ValueError("Non-JSON numeric constant: " + value)))


def _reference(path, data):
    return {"path": str(path), "bytes": len(data), "sha256": _digest(data)}


def _expected(plan, source_root):
    _require(isinstance(plan, dict), "Plan must be an object")
    canonical = {key: value for key, value in plan.items() if key != "selectedFamilies"}
    data = json.dumps(canonical, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    _require(_digest(data) == PLAN_CANONICAL_SHA256,
             "Affected-test plan differs from the authenticated original")
    available = {family["id"]: family for family in plan["families"]}
    selected = plan.get("selectedFamilies", list(available))
    _require(isinstance(selected, list) and selected
             and all(isinstance(value, str) for value in selected)
             and len(set(selected)) == len(selected) and set(selected) <= set(available),
             "selectedFamilies must name distinct complete plan families")
    expected, sources = [], []
    for family_name in selected:
        family = available[family_name]
        source_rows = [family["source"], *family.get("additionalSources", [])]
        _require(len({row["path"] for row in source_rows}) == len(source_rows), "Duplicate family source")
        source_data = {}
        for source in source_rows:
            relative = Path(source["path"])
            _require(not relative.is_absolute() and ".." not in relative.parts, "Unsafe source path in plan")
            path = (source_root / relative).resolve(strict=True)
            _require(source_root == path or source_root in path.parents, "Test source resolves outside source_root")
            raw = path.read_bytes()
            _require(len(raw) == source["bytes"] and _digest(raw) == source["sha256"],
                     "Current test source differs: " + source["path"])
            text = raw.decode("utf-8")
            offsets = [0] + [match.end() for match in re.finditer("\n", text)]
            source_data[source["path"]] = (relative, path, text, offsets)
            sources.append(_reference(path, raw))
        for item in family["tests"]:
            source_path = item.get("sourcePath", family["source"]["path"])
            _require(source_path in source_data, "Test uses an unauthenticated family source")
            relative, path, text, offsets = source_data[source_path]
            line = item["sourceLine"]
            start = offsets[line - 1]
            declaration = text.find(item["declaration"], start)
            _require(declaration >= start and declaration - start < 4096,
                     "Source declaration missing near its authenticated annotation")
            _require(text[start:declaration].strip() == item["annotation"], "Annotation/declaration association differs")
            end_line = text.count("\n", 0, declaration) + 1
            expected.append({"family": family_name, "test": item,
                "fileID": item["module"] + "/" + relative.name, "path": str(path),
                "lineFirst": line, "lineLast": end_line,
                "key": item["module"] + "/" + relative.name + ":" + item["functionSignature"]})
    _require(len({item["key"] for item in expected}) == len(expected), "Plan contains ambiguous source functions")
    return selected, expected, sources


def _matches(payload, item):
    test = item["test"]
    location = payload.get("sourceLocation")
    if not isinstance(location, dict):
        return False
    file_id, file_path = location.get("fileID"), location.get("filePath")
    if file_id is None and file_path is None:
        return False
    if file_id is not None and file_id != item["fileID"]:
        return False
    if file_path is not None:
        if not isinstance(file_path, str) or not Path(file_path).is_absolute():
            return False
        if str(Path(file_path).resolve()) != item["path"]:
            return False
    line = location.get("line")
    if type(line) is not int or not item["lineFirst"] <= line <= item["lineLast"]:
        return False
    if payload.get("name") not in (test["functionSignature"], test["function"]):
        return False
    if payload.get("displayName") != test.get("displayName"):
        return False
    return (type(payload.get("isParameterized")) is bool and
            payload["isParameterized"] == bool(test["parameterValues"]))


def verify_event_stream(path, plan, source_root, exit_code):
    review = {
        "schema": 1, "verifier": "affected-swift-testing-abi0-v3",
        "status": "FAILED", "abiVersion": 0, "commandExitCode": exit_code,
        "planSHA256": PLAN_SHA256, "events": None, "selectedFamilies": [],
        "sourceProofs": [], "expectedFunctions": 0, "expectedCases": 0,
        "observedFunctionsStarted": 0, "observedFunctionsEnded": 0,
        "observedCasesStarted": 0, "observedCasesEnded": 0,
        "functionResults": [], "suiteEvents": [], "runEvents": [], "runSegments": [],
        "observedExplicitCaseStarts": 0, "observedExplicitCaseEnds": 0,
        "observedNonParameterizedLifecycles": 0, "coverageComplete": False,
        "ignoredRecordLines": [], "issueSkipCancelEvents": [], "errors": [],
        "caseIdentityBoundary":
            "ABI0 exposes no structured test-case IDs or argument values. "
            "Case proofs retain actual paired record positions and raw events; "
            "they are not invented ABI IDs or semantic argument identities. A nonparameterized source test with no explicit case events is proved by its own actual function start/end records.",
    }
    seen, matches, executions, open_suites = {}, {}, {}, {}
    raw_records, run_open, current_run = [], False, None
    try:
        event_path = Path(path)
        raw = event_path.read_bytes()
        review["events"] = _reference(event_path, raw)
        _require(raw and raw.endswith(b"\n"), "Empty or unterminated JSONL stream")
        selected, expected, sources = _expected(
            plan, Path(source_root).resolve(strict=True))
        review["selectedFamilies"] = selected
        review["sourceProofs"] = sources
        review["expectedFunctions"] = len(expected)
        review["expectedCases"] = sum(
            item["test"]["expectedCaseCount"] for item in expected)
        for number, line in enumerate(raw.decode("utf-8").splitlines(), 1):
            _require(bool(line.strip()), "Empty JSONL record at line " + str(number))
            record = _read_json(line)
            _require(isinstance(record, dict), "JSONL record must be an object")
            entry = {"line": number, "record": record}
            raw_records.append(entry)
            kind = record.get("kind")
            if kind not in ("test", "event"):
                review["ignoredRecordLines"].append(number)
                continue
            _require(type(record.get("version")) is int and record["version"] == 0,
                     "Recognized record is not explicit ABI0")
            payload = record.get("payload")
            _require(isinstance(payload, dict), "Record payload must be an object")
            if kind != "test":
                continue
            identifier = payload.get("id")
            _require(isinstance(identifier, str) and identifier, "Missing opaque test ID")
            _require(identifier not in seen, "Duplicate test definition record")
            _require(payload.get("kind") in ("function", "suite"),
                     "Unrecognized test definition kind")
            seen[identifier] = entry
            if payload["kind"] == "function":
                candidates = [item for item in expected if _matches(payload, item)]
                _require(len(candidates) <= 1, "Ambiguous function source identity")
                if candidates:
                    item = candidates[0]
                    _require(item["key"] not in matches,
                             "Multiple ABI IDs name the same selected source function")
                    matches[item["key"]] = identifier
                    executions[identifier] = {
                        "sourceFunction": item["key"], "family": item["family"],
                        "expectedCases": item["test"]["expectedCaseCount"],
                        "isParameterized": bool(item["test"]["parameterValues"]),
                        "expectedParameterValues": item["test"]["parameterValues"],
                        "testRecord": entry, "testStarted": None, "testEnded": None,
                        "cases": [], "activeCase": None,
                    }
        for entry in raw_records:
            record, number = entry["record"], entry["line"]
            if record.get("kind") != "event":
                continue
            payload = record["payload"]
            kind = payload.get("kind")
            instant = payload.get("instant")
            _require(isinstance(instant, dict) and all(
                type(instant.get(key)) in (int, float)
                and math.isfinite(instant[key])
                for key in ("absolute", "since1970")), "Malformed event instant")
            if kind in ("issueRecorded", "testSkipped", "testCancelled", "testCaseCancelled"):
                review["issueSkipCancelEvents"].append(entry)
                review["errors"].append({"line": number, "message": kind})
                continue
            messages = payload.get("messages", [])
            _require(isinstance(messages, list), "Malformed event messages")
            if any(isinstance(message, dict) and message.get("symbol") in
                   ("fail", "skip", "passWithKnownIssue") for message in messages):
                review["errors"].append({"line": number,
                                         "message": "Failure/skip/known-issue marker"})
            if kind == "runStarted":
                _require(not run_open and not open_suites, "Overlapping or reordered runStarted")
                run_open = True
                current_run = {"started": entry, "ended": None, "functionIDs": []}
                review["runSegments"].append(current_run)
                review["runEvents"].append(entry)
                continue
            if kind == "runEnded":
                _require(run_open, "Unmatched runEnded")
                _require(not open_suites and all(executions[identifier]["testEnded"] is not None
                    for identifier in current_run["functionIDs"]), "runEnded precedes active test/suite completion")
                _require(current_run["started"]["record"]["payload"]["instant"]["absolute"] <= instant["absolute"],
                         "Run end instant precedes its start")
                current_run["ended"] = entry
                run_open = False
                review["runEvents"].append(entry)
                continue
            if kind == "valueAttached":
                continue  # The original event stream retains its attachment reference.
            _require(kind in ("testStarted", "testEnded", "testCaseStarted", "testCaseEnded"),
                     "Unsupported event kind: " + str(kind))
            _require(run_open, "Test lifecycle lies outside the run")
            identifier = payload.get("testID")
            _require(identifier in seen, "Lifecycle event has no test definition")
            definition = seen[identifier]
            _require(definition["line"] < number, "Definition follows its lifecycle event")
            if definition["record"]["payload"]["kind"] == "suite":
                _require(kind in ("testStarted", "testEnded"), "Suite has a test case event")
                if kind == "testStarted":
                    _require(identifier not in open_suites
                             and not any(row["record"]["payload"].get("testID") == identifier
                                         for row in review["suiteEvents"]),
                             "Duplicate suite start")
                    open_suites[identifier] = entry
                else:
                    _require(identifier in open_suites, "Unmatched suite end")
                    del open_suites[identifier]
                review["suiteEvents"].append(entry)
                continue
            _require(identifier in executions, "Unselected function executed: " + str(identifier))
            execution = executions[identifier]
            if kind == "testStarted":
                _require(execution["testStarted"] is None, "Duplicate function start")
                execution["testStarted"] = entry
                current_run["functionIDs"].append(identifier)
                review["observedFunctionsStarted"] += 1
                continue
            _require(execution["testStarted"] is not None and execution["testEnded"] is None,
                     "Function lifecycle is missing a start or already ended")
            if kind == "testCaseStarted":
                _require(execution["activeCase"] is None,
                         "Overlapping case lifecycle cannot establish ABI0 serial pairing")
                execution["activeCase"] = entry
                review["observedCasesStarted"] += 1
                review["observedExplicitCaseStarts"] += 1
            elif kind == "testCaseEnded":
                start = execution["activeCase"]
                _require(start is not None, "Test case ended without a distinct start")
                _require(start["record"]["payload"]["instant"]["absolute"] <= instant["absolute"],
                         "Case end instant precedes its start")
                execution["cases"].append({"proofKind": "explicitTestCaseLifecycle", "started": start, "ended": entry})
                execution["activeCase"] = None
                review["observedCasesEnded"] += 1
                review["observedExplicitCaseEnds"] += 1
            else:
                _require(execution["activeCase"] is None, "Function ended with an open case")
                _require(execution["testStarted"]["record"]["payload"]["instant"]["absolute"] <= instant["absolute"],
                         "Function end instant precedes its start")
                if not execution["isParameterized"] and not execution["cases"]:
                    _require(execution["expectedCases"] == 1, "Nonparameterized source must declare one case")
                    execution["cases"].append({"proofKind": "nonParameterizedFunctionLifecycle",
                        "started": execution["testStarted"], "ended": entry})
                    review["observedCasesStarted"] += 1
                    review["observedCasesEnded"] += 1
                    review["observedNonParameterizedLifecycles"] += 1
                _require(len(execution["cases"]) == execution["expectedCases"],
                         "Wrong case count for " + execution["sourceFunction"])
                execution["testEnded"] = entry
                review["observedFunctionsEnded"] += 1
        _require(set(matches) == {item["key"] for item in expected},
                 "Missing selected source function definitions")
        _require(not run_open and review["runSegments"] and all(segment["ended"] is not None
                 for segment in review["runSegments"]), "Missing complete runStarted/runEnded pair")
        _require(review["observedFunctionsStarted"] == review["observedFunctionsEnded"]
                 == review["expectedFunctions"], "Wrong function execution count")
        _require(review["observedCasesStarted"] == review["observedCasesEnded"]
                 == review["expectedCases"], "Wrong test-case execution count")
        review["coverageComplete"] = True
        _require(type(exit_code) is int and exit_code == 0, "Native command did not exit zero")
        _require(not review["errors"], "Issue, skip, cancellation or failure was recorded")
        review["status"] = "EXECUTED_PASS"
    except (ValueError, TypeError, KeyError, IndexError, OSError, UnicodeError) as error:
        review["errors"].append({"type": type(error).__name__, "message": str(error)})
    finally:
        for execution in executions.values():
            execution["status"] = ("EXECUTED_PASS" if review["status"] == "EXECUTED_PASS"
                                   else "NOT_ACCEPTED")
            review["functionResults"].append(execution)
        review["parsedRecordCount"] = len(raw_records)
        review["countBoundary"] = ("Complete source-bound lifecycle coverage; native verdict retained"
                                  if review["coverageComplete"] else "Observed prefix; raw stream reference is retained")
    return review
