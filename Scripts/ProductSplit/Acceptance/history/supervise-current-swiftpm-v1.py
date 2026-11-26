#!/usr/bin/env python3
"""Supervise one unchanged independent SwiftPM invocation and its owned group."""
from pathlib import Path
import argparse, datetime, hashlib, json, math, os, signal, subprocess, sys, time

R = Path("/Users/m1/builds/hanlin-current-entrypoints-20261126")
CONTROL = R / "validation/current-independent-swiftpm-controls-v1"
RUNNER = CONTROL / "run-current-swiftpm-v1.py"
RUNNER_SHA = "edcca6408f8a2df57692b7c253b2c8f2ca2367fb443b420dc8b3f534dded10e3"
OUT = R / "validation/current-source-swiftpm-v1-supervision"
CHILD = R / "validation/current-source-swiftpm-v1"
TIMEOUT = 2700

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def ref(path):
    raw = Path(path).read_bytes()
    return {"path": str(path), "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}

def write(path, value):
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w") as stream:
        json.dump(value, stream, indent=2); stream.write("\n")
        stream.flush(); os.fsync(stream.fileno())
    temporary.replace(path)

def group_exists(pgid):
    try:
        os.killpg(pgid, 0)
        return True
    except ProcessLookupError:
        return False

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--decision", type=Path, required=True)
    args = parser.parse_args()
    assert ref(RUNNER)["sha256"] == RUNNER_SHA
    assert not OUT.exists() and not CHILD.exists()
    d = json.loads(args.decision.read_bytes())
    assert d["source"] == "542714964a0f12a964651c2306d5f992ca13ae85"
    assert TIMEOUT < 10800 - d["chargedCurrentValidationBeforeSeconds"]
    OUT.mkdir()
    argv = [sys.executable, "-B", str(RUNNER), "--decision", str(args.decision)]
    state = {"schema": 1, "id": "current-source-swiftpm-v1-supervision",
             "source": d["source"], "sourceTree": d["sourceTree"], "status": "RUNNING",
             "runner": ref(RUNNER), "decision": ref(args.decision), "argv": argv,
             "startedAt": now(), "timeoutSeconds": TIMEOUT, "signals": [],
             "cleanupErrors": [], "childStatus": None, "childChargeCommitted": False,
             "boundary": "One unchanged runner invocation. Exact owned process-group supervision is separate from its original command and test evidence."}
    started = time.monotonic()
    process = None
    try:
        with (OUT / "runner.log").open("xb") as log:
            process = subprocess.Popen(argv, cwd=R, stdin=subprocess.DEVNULL, stdout=log,
                                       stderr=subprocess.STDOUT, start_new_session=True, close_fds=True)
            state.update(pid=process.pid, pgid=process.pid)
            write(OUT / "state.json", state)
            try:
                state["childExitCode"] = process.wait(timeout=TIMEOUT)
            except subprocess.TimeoutExpired:
                state["timedOut"] = True
                os.killpg(process.pid, signal.SIGINT)
                state["signals"].append({"signal": "SIGINT", "pgid": process.pid, "at": now(), "reason": "owned runner timeout"})
                try:
                    state["childExitCode"] = process.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    state["childExitCode"] = None
    except BaseException as error:
        state["error"] = {"type": type(error).__name__, "message": str(error)}
    finally:
        if process is not None:
            try:
                for signum, duration in [(signal.SIGTERM, 20), (signal.SIGKILL, 10)]:
                    if not group_exists(process.pid):
                        break
                    os.killpg(process.pid, signum)
                    state["signals"].append({"signal": signal.Signals(signum).name, "pgid": process.pid,
                                             "at": now(), "reason": "owned group final cleanup"})
                    deadline = time.monotonic() + duration
                    while group_exists(process.pid) and time.monotonic() < deadline:
                        process.poll()
                        time.sleep(0.25)
                state["childExitCode"] = process.poll()
                state["ownedProcessGroupAbsent"] = not group_exists(process.pid)
                if not state["ownedProcessGroupAbsent"]:
                    state["cleanupErrors"].append({"type": "OwnedProcessGroupStillPresent", "pgid": process.pid})
            except BaseException as error:
                state["cleanupErrors"].append({"type": type(error).__name__, "message": str(error)})
                state["ownedProcessGroupAbsent"] = False
        else:
            state["ownedProcessGroupAbsent"] = True
        child_state = CHILD / "state.json"
        if child_state.is_file():
            value = json.loads(child_state.read_bytes())
            state["childState"] = ref(child_state)
            state["childStatus"] = value.get("status")
            state["childChargeCommitted"] = value.get("chargeCommitted") is True
            state["childReportedActualElapsedSeconds"] = value.get("actualElapsedSeconds")
            ledger = CHILD / "ledger.json"
            if ledger.is_file():
                state["childLedger"] = ref(ledger)
        state["finishedAt"] = now()
        state["actualElapsedSeconds"] = time.monotonic() - started
        child_seconds = state.get("childReportedActualElapsedSeconds")
        if isinstance(child_seconds, (int, float)) and math.isfinite(child_seconds):
            state["additionalObservedElapsedSeconds"] = max(0.0, state["actualElapsedSeconds"] - child_seconds)
        state["status"] = "EXECUTED_PASS_CLEAN" if (state.get("childExitCode") == 0 and
            state["childStatus"] == "EXECUTED_PASS" and state["childChargeCommitted"] and
            state["ownedProcessGroupAbsent"] and not state["cleanupErrors"] and
            not state.get("timedOut") and not state.get("error")) else "FAILED"
        state["accountingBoundary"] = "The unchanged child ledger records its actual phase time. Additional observed supervision time is retained separately for one additive continuation row; no prior charge is reset."
        write(OUT / "state.json", state)
    print(json.dumps({"status": state["status"], "state": ref(OUT / "state.json")}))
    return 0 if state["status"] == "EXECUTED_PASS_CLEAN" else 1

if __name__ == "__main__":
    raise SystemExit(main())
