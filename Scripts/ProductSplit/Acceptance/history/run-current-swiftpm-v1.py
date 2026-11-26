#!/usr/bin/env python3
"""Execute the two original independent SwiftPM obligations and verify later reuse."""
from pathlib import Path
import argparse
import fcntl
import hashlib
import importlib.util
import json
import math
import os
import sys
import time

ID = "current-source-swiftpm-v1"
SOURCE = "542714964a0f12a964651c2306d5f992ca13ae85"
DECISION_SHA = "b6caf28bf3d6aa88077e91edcd507e8d941287689c98b3fec96855ab8db94b97"
LABELS = ("widget-host-action-queue", "affected-swiftpm")


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def context(decision_path):
    path = Path(decision_path)
    assert hashlib.sha256(path.read_bytes()).hexdigest() == DECISION_SHA
    d = json.loads(path.read_bytes())
    assert d["source"] == SOURCE and d["id"] == "current-source-native-v1"
    core_path = Path(d["controller"]["path"])
    assert hashlib.sha256(core_path.read_bytes()).hexdigest() == d["controller"]["sha256"]
    core = load_module("original_current_native_core", core_path)
    core.verified(d["controller"])
    guard = load_module("original_current_native_guard", core.verified(d["guard"]))
    return d, core, guard


def selected(d, core):
    q = d["queueContractGroup"]
    assert (q["expectedFunctions"], q["expectedParameterInstances"], q["commandCeilingSeconds"]) == (10, 16, 1200)
    for row in (q["source"], q["testPlan"], d["affectedSwiftPM"]["inventory"], d["affectedSwiftPM"]["verifier"]):
        core.verified(row)
    inventory = json.loads(Path(d["affectedSwiftPM"]["inventory"]["path"]).read_bytes())
    assert (inventory["expectedDefinitions"], inventory["expectedCases"]) == (118, 198)
    for family in inventory["families"]:
        row = family["source"]
        assert core.digest(core.ROOT / row["path"]) == row["sha256"]
    return inventory


def toolchain(core):
    return {
        "developerDir": os.environ.get("DEVELOPER_DIR") or core.command(["xcode-select", "-p"]),
        "xcode": core.command(["xcodebuild", "-version"]),
        "swift": core.command(["xcrun", "swift", "--version"]),
        "macOS": core.command(["sw_vers", "-productVersion"]),
        "architecture": core.command(["uname", "-m"]),
    }


def original_argv(d, core, inventory, evidence, label):
    common = ["xcrun", "swift", "test", "--package-path", str(core.ROOT / "Packages/HanlinPlatform"),
        "--scratch-path", str(Path(d["derivedData"]) / "swiftpm-widget-host-actions"),
        "--enable-swift-testing", "--no-parallel"]
    if label == LABELS[0]:
        return common + ["--filter", "HanlinWidgetHostActionTests"]
    assert label == LABELS[1]
    return common + ["--filter", inventory["filter"], "--event-stream-output-path",
        str(evidence / "affected-swiftpm-events.jsonl"), "--event-stream-version", "0"]


def verify_groups(d, core, guard, evidence):
    inventory = selected(d, core)
    queue = d["queueContractGroup"]
    queue_plan = json.loads(Path(queue["testPlan"]["path"]).read_bytes())
    affected = load_module("original_affected_swift_verifier", core.verified(d["affectedSwiftPM"]["verifier"]))
    commands = [json.loads(line) for line in (evidence / "commands.jsonl").read_text().splitlines() if line.strip()]
    assert [row["log"] for row in commands] == [label + "-tests.log" for label in LABELS]
    events = [json.loads(line) for line in (evidence / "command-events.jsonl").read_text().splitlines() if line.strip()]
    results = {}
    for label, command in zip(LABELS, commands):
        review_path = evidence / (label + "-review.json")
        review = json.loads(review_path.read_bytes())
        assert review["source"] == SOURCE and review["status"] == "EXECUTED_PASS"
        assert review["commandExitCode"] == command["exit"] == 0
        assert command["argv"] == review["argv"] == original_argv(d, core, inventory, evidence, label)
        assert core.digest(evidence / command["log"]) == command["sha256"]
        terminal = [row for row in events if row["log"] == command["log"] and row.get("completion_recorded")]
        assert len(terminal) == 1 and terminal[0]["status"] == "completed" and terminal[0]["exit"] == 0
        assert terminal[0]["argv"] == review["argv"] and terminal[0]["timeout"] == 1200
        for proof in review["proofs"]:
            core.verified(proof)
        if label == LABELS[0]:
            result = guard.verify_swift_testing_log((evidence / command["log"]).read_text(), queue_plan["tests"], "Declared widget Host actions and canonical delivery")
            assert (result["observedFunctions"], result["observedParameterInstances"]) == (10, 16)
        else:
            result = affected.verify_event_stream(evidence / "affected-swiftpm-events.jsonl", inventory, core.ROOT, 0)
            assert result["status"] == "EXECUTED_PASS"
            assert (review["expectedDefinitions"], review["expectedCases"]) == (118, 198)
        assert result == review["verification"]
        results[label] = {"id": label, "source": SOURCE, "status": "REUSED_VERIFIED_PASS",
            "verification": result, "originalExecution": core.ref(review_path),
            "originalCommands": core.ref(evidence / "commands.jsonl"),
            "originalCommandEvents": core.ref(evidence / "command-events.jsonl"),
            "proofs": review["proofs"], "commandExecutedInCurrentOriginalRun": False,
            "boundary": "Authentic completed standalone current-source SwiftPM execution; not a new command or test pass in the later app run."}
    return results


def verify_completed(current):
    """Verify exact finished input closure, raw execution and ledger before aggregation."""
    binding = current["completedSwiftPM"]
    state_path = Path(binding["state"]["path"])
    assert hashlib.sha256(state_path.read_bytes()).hexdigest() == binding["state"]["sha256"]
    state = json.loads(state_path.read_bytes())
    d, core, guard = context(state["decision"]["path"])
    core.verified(state["decision"])
    core.verified(binding["state"])
    core.verified(binding["helper"])
    assert core.verified(state["helper"]) == Path(__file__).resolve()
    assert binding["helper"] == state["helper"]
    assert state["id"] == ID and state["status"] == "EXECUTED_PASS" and state["chargeCommitted"] is True
    assert not state["sourceErrors"] and state["sourceBefore"] == state["sourceAfter"] == core.source_closure(d)
    assert state["toolchainBefore"] == state["toolchainAfter"] == toolchain(core)
    for name in ("source", "sourceTree", "currentSDK", "queueContractGroup", "affectedSwiftPM", "originalRunner"):
        assert current[name] == d[name], name
    prior = core.validation_history(d)
    seconds = state["actualElapsedSeconds"]
    assert isinstance(seconds, (int, float)) and math.isfinite(seconds) and seconds > 0
    assert state["chargedCurrentValidationBeforeSeconds"] == prior
    assert state["totalCurrentValidationChargedSeconds"] == math.fsum([row["seconds"] for row in d["currentValidationHistory"]] + [seconds]) < 10800
    ledger_path = core.verified(binding["ledger"])
    assert binding["ledger"] == state["ledger"]
    ledger = json.loads(ledger_path.read_bytes())
    assert ledger["id"] == ID and ledger["status"] == "EXECUTED_PASS"
    assert ledger["history"] == d["currentValidationHistory"] and ledger["actualElapsedSeconds"] == seconds
    assert ledger["actualChargedSeconds"] == state["totalCurrentValidationChargedSeconds"]
    evidence = Path(state["evidence"])
    assert evidence == core.ROOT / "validation" / ID / "original" / "paired-product"
    results = verify_groups(d, core, guard, evidence)
    for result in results.values():
        result.update(completedState=binding["state"], completedLedger=binding["ledger"],
                      originalScope=ID, sourceTree=d["sourceTree"])
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--decision", type=Path, required=True)
    args = parser.parse_args()
    d, core, guard = context(args.decision)
    assert core.digest(Path(sys.executable).resolve()) == core.PYTHON_SHA
    assert os.getuid() == core.ROOT.stat().st_uid != 0
    prior = core.validation_history(d)
    out = core.ROOT / "validation" / ID
    evidence = out / "original" / "paired-product"
    scratch = Path(d["derivedData"]) / "swiftpm-widget-host-actions"
    with core.LOCK.open("a+") as owner:
        fcntl.flock(owner, fcntl.LOCK_EX | fcntl.LOCK_NB)
        assert not out.exists() and not scratch.exists() and not scratch.is_symlink()
        os.environ.update(GITHUB_WORKSPACE=str(core.ROOT), GITHUB_SHA=SOURCE, GITHUB_RUN_ID=ID,
            PAIRED_TEST_SCOPE="miniapp_complete", SPLIT_EVIDENCE=str(out / "original"),
            SPLIT_DERIVED_DATA=d["derivedData"], DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
        os.environ["PATH"] = str(core.ROOT / "Tools/node-v24.5.0-darwin-arm64/bin") + ":" + os.environ["PATH"]
        before = core.source_closure(d)
        inventory = selected(d, core)
        initial_toolchain = toolchain(core)
        evidence.mkdir(parents=True)
        sys.path.insert(0, str(core.ROOT / "Scripts/ProductSplit"))
        original = load_module("standalone_original_paired_commands", core.verified(d["originalRunner"]))
        assert original.EVIDENCE == evidence and original.ROOT == core.ROOT
        assessment = json.loads(core.verified(d["resourceAssessment"]["authority"]).read_bytes())
        command = guard.make_resource_checked_command(original.command, assessment, evidence, Path(d["derivedData"]), d)
        state = {"schema": 1, "id": ID, "status": "RUNNING", "source": SOURCE,
            "sourceTree": d["sourceTree"], "decision": core.ref(args.decision), "helper": core.ref(Path(__file__)),
            "startedAt": core.now(), "evidence": str(evidence), "sourceBefore": before,
            "toolchainBefore": initial_toolchain, "sourceErrors": [], "groups": [],
            "chargedCurrentValidationBeforeSeconds": prior, "validationScopeSeconds": 10800,
            "scratch": str(scratch), "scratchRetired": False, "chargeCommitted": False,
            "boundary": "Only the exact original independent queue and affected SwiftPM obligations execute; no app build, simulator, original52, hosted or signing result is implied."}
        started = time.monotonic()
        core.write(out / "state.json", state)
        try:
            queue_plan = json.loads(core.verified(d["queueContractGroup"]["testPlan"]).read_bytes())
            affected = load_module("standalone_original_affected_verifier", core.verified(d["affectedSwiftPM"]["verifier"]))
            for label in LABELS:
                assert 10800 - prior - (time.monotonic() - started) >= 1200, "INSUFFICIENT_REMAINING_VALIDATION_BUDGET"
                if label == LABELS[1]:
                    assert scratch.is_dir() and not scratch.is_symlink()
                argv = original_argv(d, core, inventory, evidence, label)
                review = {"schema": 1, "id": label, "source": SOURCE, "status": "RUNNING",
                    "startedAt": core.now(), "argv": argv, "commandCeilingSeconds": 1200,
                    "expectedDefinitions": 10 if label == LABELS[0] else 118,
                    "expectedCases": 16 if label == LABELS[0] else 198, "proofs": []}
                path = evidence / (label + "-review.json")
                core.write(path, review)
                try:
                    code, raw = command(argv, label + "-tests.log", timeout=1200, allow_failure=True)
                    review["commandExitCode"] = code
                    assert code == 0, {"phase": label, "exitCode": code}
                    selected(d, core)
                    if label == LABELS[0]:
                        review["verification"] = guard.verify_swift_testing_log(raw, queue_plan["tests"], "Declared widget Host actions and canonical delivery")
                        assert (review["verification"]["observedFunctions"], review["verification"]["observedParameterInstances"]) == (10, 16)
                    else:
                        review["verification"] = affected.verify_event_stream(evidence / "affected-swiftpm-events.jsonl", inventory, core.ROOT, code)
                        assert review["verification"]["status"] == "EXECUTED_PASS"
                    review["status"] = "EXECUTED_PASS"
                except BaseException as error:
                    review.update(status="FAILED", error={"type": type(error).__name__, "message": str(error)})
                    raise
                finally:
                    review["finishedAt"] = core.now()
                    review["proofs"] = [core.ref(p) for p in [evidence / (label + "-tests.log"), evidence / "affected-swiftpm-events.jsonl"] if p.is_file() and (label == LABELS[1] or p.name.endswith(".log"))]
                    core.write(path, review)
                    state["groups"].append(core.ref(path))
                    core.write(out / "state.json", state)
            verify_groups(d, core, guard, evidence)
            state["status"] = "EXECUTED_PASS"
        except BaseException as error:
            state.update(status="FAILED", error={"type": type(error).__name__, "message": str(error)})
        finally:
            try:
                state["sourceAfter"] = core.source_closure(d)
                state["toolchainAfter"] = toolchain(core)
                assert state["sourceAfter"] == before and state["toolchainAfter"] == initial_toolchain
            except BaseException as error:
                state["sourceErrors"].append({"type": type(error).__name__, "message": str(error)})
                state["status"] = "FAILED"
            state["finishedAt"] = core.now()
            state["actualElapsedSeconds"] = time.monotonic() - started
            total = math.fsum([row["seconds"] for row in d["currentValidationHistory"]] + [state["actualElapsedSeconds"]])
            if total >= 10800:
                state.update(status="FAILED", error={"type": "ValidationBudgetExceeded", "message": str(total)})
            state["totalCurrentValidationChargedSeconds"] = total
            state["remainingCurrentValidationSeconds"] = max(0, 10800 - total)
            state["chargeCommitted"] = True
            ledger = {"schema": 1, "id": ID, "status": state["status"], "source": SOURCE,
                "currentValidationCeilingSeconds": 10800, "history": d["currentValidationHistory"],
                "actualElapsedSeconds": state["actualElapsedSeconds"], "actualChargedSeconds": total,
                "remainingSeconds": state["remainingCurrentValidationSeconds"]}
            core.write(out / "ledger.json", ledger)
            state["ledger"] = core.ref(out / "ledger.json")
            core.write(out / "state.json", state)
    print(json.dumps({"status": state["status"], "state": core.ref(out / "state.json"), "ledger": state["ledger"]}))
    return 0 if state["status"] == "EXECUTED_PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
