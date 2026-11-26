"""Run one unchanged paired52 phase under an explicit, separately authorized allowance.
This file does not edit repository source, the original plan, selectors, or timeouts.
A decision must be sealed only after the final source/preparation input closure exists.
"""
from pathlib import Path
import argparse, datetime, fcntl, hashlib, json, os, signal, subprocess, time, uuid

def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def canonical(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()

def write(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)

def run(argv, *, cwd=None, env=None, timeout=30):
    return subprocess.check_output(argv, cwd=cwd, env=env, text=True, timeout=timeout).strip()

def relative(root, value):
    path = (root / value).resolve()
    if not path.is_relative_to(root):
        raise RuntimeError("Decision path escapes the owned repository: " + value)
    return path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--decision", type=Path, required=True)
    args = parser.parse_args()
    decision_path = args.decision.resolve()
    decision_bytes = decision_path.read_bytes()
    decision = json.loads(decision_bytes)
    assert decision["schema"] == 1 and decision["owner"] == "/root/native_execution"
    assert decision["id"] == "paired52-continuation-v1"
    assert decision["scope"] == "miniapp_complete" and decision["expectedCases"] == 52
    assert decision["allowanceSeconds"] == 4500
    assert decision["authorization"]["by"] == "/root" and decision["authorization"]["scope"] == "one original paired52 continuation"
    root = Path(decision["root"]).resolve()
    ctrl = root / "build/primary-control"
    out = relative(root, decision["outputDirectory"])
    assert out.is_relative_to(ctrl) and not out.exists()
    lock = (ctrl / "native-continuation-owner.lock").open("a")
    fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    plan_path, primary_path = ctrl / "plan.json", ctrl / "state.json"
    assert digest(plan_path) == decision["planSHA256"]
    assert digest(primary_path) == decision["primaryStateSHA256"]
    plan, primary = json.loads(plan_path.read_text()), json.loads(primary_path.read_text())
    assert plan["maximumActiveSeconds"] == 12600
    assert plan["sha"] == primary["source"] == decision["source"]
    assert primary["planSHA256"] == decision["planSHA256"]
    assert primary["status"] in ("READY", "PAUSED_AFTER_PHASE")
    baseline = primary["activeElapsedSeconds"]
    assert baseline == decision["activeBaselineSeconds"]
    assert primary["scope"] == "miniapp_complete" and primary["expectedCases"] == 52
    assert run(["git", "rev-parse", "HEAD"], cwd=root) == decision["source"]
    assert run(["git", "rev-parse", "HEAD^{tree}"], cwd=root) == decision["sourceTree"]
    diff = subprocess.check_output(["git", "diff", "--binary", "HEAD"], cwd=root)
    assert hashlib.sha256(diff).hexdigest() == decision["preparedTrackedDiffSHA256"]
    phase_id = "split-paired-acceptance"
    assert phase_id not in primary["phases"]
    phase = next(x for x in plan["phases"] if x["id"] == phase_id)
    assert phase["script"] == "python3 Scripts/ProductSplit/run_paired_acceptance.py"
    script = ctrl / "phases" / (phase_id + ".sh")
    assert digest(script) == phase["scriptSHA256"] == decision["phaseScriptSHA256"]
    assert phase["scriptSHA256"] == "f271e6f1b95bb261417cee5fc13104e41df44f8ec35d2ab565b1f6135191c0c8"
    expected_prerequisites = [x["id"] for x in plan["phases"] if x["id"] != phase_id]
    assert [x["id"] for x in decision["prerequisites"]] == expected_prerequisites
    for item in decision["prerequisites"]:
        record = primary["phases"][item["id"]]
        assert record["status"] in ("PASS", "REUSED_VERIFIED_SKIP")
        assert canonical(record) == item["recordSHA256"]
    for item in decision["requiredFiles"]:
        path = relative(root, item["path"])
        assert path.is_file() and digest(path) == item["sha256"]
    assert any(x["path"] == "Scripts/ProductSplit/run_paired_acceptance.py" for x in decision["requiredFiles"])
    assert any(x["path"] == "AI_HLY/RuntimeHostResources.zip" for x in decision["requiredFiles"])
    assert decision["resourceAssessment"]["decision"] == "FITS_MEASURED_NEXT_PHASE"
    # Resource estimates are specific input evidence; no fixed free/CPU/load rule is introduced.
    disk = run(["df", "-k", "/System/Volumes/Data"])
    fresh_free = int(disk.splitlines()[-1].split()[3]) * 1024
    need = decision["resourceAssessment"]["estimatedIncrementalBytes"] + decision["resourceAssessment"]["concurrentAndOSAllowanceBytes"]
    assert fresh_free >= need, "Measured phase requirement no longer fits; preserve decision, do not dispatch."
    out.mkdir()
    (out / "decision.json").write_bytes(decision_bytes)
    (out / "primary-state-before.json").write_bytes(primary_path.read_bytes())
    (out / "plan-before.json").write_bytes(plan_path.read_bytes())
    state_path, events = out / "state.json", out / "events.jsonl"
    evidence_base = out / "evidence"
    evidence_base.mkdir()
    env = dict(os.environ)
    tools = root.parent / (root.name + "-tools")
    env.update({"PATH": str(tools / "bin") + ":/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer", "GITHUB_WORKSPACE": str(root),
        "GITHUB_SHA": decision["source"], "GITHUB_RUN_ID": "primary-ce49e30d-20261124",
        "SPLIT_EVIDENCE": str(evidence_base),
        "SPLIT_DERIVED_DATA": "/Users/m1/caches/DerivedData/hanlin-ai-ce49e30d-miniapp-complete",
        "SPLIT_NATIVE_TEST_SCOPE": "baseline", "PAIRED_TEST_SCOPE": "miniapp_complete",
        "RUNNER_TEMP": str(root / "build/primary-temp"), "PAIRED_PROOF_REUSE_REQUIRED": "false"})
    assert run(["node", "--version"], env=env) == "v24.5.0"
    argv = ["/bin/bash", "-e", "-o", "pipefail", str(script)]
    log = out / "original-paired-phase.log"
    state = {"schema": 1, "owner": decision["owner"], "id": decision["id"], "source": decision["source"],
        "scope": "miniapp_complete", "expectedCases": 52, "status": "STARTING",
        "decisionSHA256": hashlib.sha256(decision_bytes).hexdigest(), "controllerPID": os.getpid(),
        "activeBaselineSeconds": baseline, "allowanceSeconds": 4500, "originalPlanMaximumActiveSeconds": 12600,
        "guard": "separately-authorized-paired52-continuation-v1", "argv": argv,
        "log": str(log), "pairedEvidence": str(evidence_base / "paired-product"),
        "resourceObservationAtLaunch": {"observedAt": utc(), "freeBytes": fresh_free, "df": disk},
        "original52": "NOT_RUN"}
    def checkpoint(event, **fields):
        state.update(fields)
        write(state_path, state)
        with events.open("a") as stream:
            stream.write(json.dumps({"at": utc(), "event": event, **fields}) + "\n")
            stream.flush()
            os.fsync(stream.fileno())
        print(json.dumps({"at": utc(), "event": event, **fields}), flush=True)
    checkpoint("prepared")
    process, exit_code, error = None, None, None
    start = time.monotonic()
    state["startedAt"] = utc()
    primary.update(status="RUNNING", controllerPID=os.getpid(), phase=phase_id,
        activeBudget={"id": decision["id"], "decision": str(out / "decision.json"),
            "baselineSeconds": baseline, "allowanceSeconds": 4500, "originalPlanMaximumActiveSeconds": 12600})
    primary["phases"][phase_id] = {"status": "RUNNING", "startedAt": state["startedAt"],
        "argv": argv, "scriptSHA256": phase["scriptSHA256"], "log": str(log),
        "continuationID": decision["id"]}
    write(primary_path, primary)
    def interrupted(signum, frame):
        raise InterruptedError("Continuation received signal " + str(signum))
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        with log.open("xb") as stream:
            process = subprocess.Popen(argv, cwd=root, env=env, stdout=stream,
                stderr=subprocess.STDOUT, start_new_session=True)
            primary["phases"][phase_id]["pid"] = process.pid
            write(primary_path, primary)
            checkpoint("launched", status="RUNNING", phasePID=process.pid, original52="RUNNING")
            while True:
                remaining = 4500 - (time.monotonic() - start)
                if remaining <= 0:
                    raise TimeoutError("Explicit paired52 continuation allowance elapsed")
                try:
                    exit_code = process.wait(timeout=min(30, remaining))
                    break
                except subprocess.TimeoutExpired:
                    fields = {"elapsedSeconds": time.monotonic() - start, "logBytes": log.stat().st_size}
                    try:
                        df = run(["df", "-k", "/System/Volumes/Data"], timeout=10)
                        fields["freeBytes"] = int(df.splitlines()[-1].split()[3]) * 1024
                    except Exception as observation_error:
                        fields["diskObservationError"] = str(observation_error)
                    checkpoint("heartbeat", **fields)
        acceptance_path = evidence_base / "paired-product/acceptance.json"
        acceptance = json.loads(acceptance_path.read_text()) if acceptance_path.exists() else {}
        state["actualAcceptance"] = {"path": str(acceptance_path), "sha256": digest(acceptance_path) if acceptance_path.exists() else None,
            "status": acceptance.get("status"), "miniApps": acceptance.get("original_runtime_summary"), "ai": acceptance.get("summary")}
        assert exit_code == 0, "Original paired phase returned " + str(exit_code)
        assert acceptance.get("sha") == decision["source"] and acceptance.get("test_scope") == "miniapp_complete"
        assert acceptance.get("status") == "EXECUTED_PASS"
        for key, count in [("original_runtime_summary", 25), ("summary", 27)]:
            summary = acceptance[key]
            assert summary.get("passedTests") == count and summary.get("failedTests", 0) == 0 and summary.get("skippedTests", 0) == 0
        state.update(status="EXECUTED_PASS", original52="EXECUTED_PASS")
        checkpoint("actual_terminal", status=state["status"], original52=state["original52"], exitCode=exit_code)
    except BaseException as failure:
        error = type(failure).__name__ + ": " + str(failure)
        state.update(status="TIMED_OUT" if isinstance(failure, TimeoutError) else "FAILED", error=error, original52="FAILED_OR_INCOMPLETE")
        checkpoint("actual_terminal", status=state["status"], error=error, exitCode=exit_code)
    finally:
        # A repeated cancellation cannot bypass accounting and owned cleanup.
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        cleanup_errors = []
        def live_owned_group():
            rows = run(["ps", "-axo", "pid=,pgid=,state=,command="], timeout=10).splitlines()
            return [line for line in rows if len(line.split(None, 3)) == 4
                and line.split(None, 3)[1] == str(process.pid)
                and not line.split(None, 3)[2].startswith("Z")]
        if process is not None:
            # The phase shell can exit before descendants. Its newly created PGID
            # remains our ownership boundary even when the direct child has exited.
            try:
                members = live_owned_group()
                state["ownedProcessGroupAtCleanup"] = members
                if members:
                    try:
                        os.killpg(process.pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                    until = time.monotonic() + 20
                    while members and time.monotonic() < until:
                        if process.poll() is None:
                            try:
                                process.wait(timeout=1)
                            except subprocess.TimeoutExpired:
                                pass
                        else:
                            time.sleep(0.25)
                        members = live_owned_group()
                    if members:
                        try:
                            os.killpg(process.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        until = time.monotonic() + 10
                        while members and time.monotonic() < until:
                            if process.poll() is None:
                                try:
                                    process.wait(timeout=1)
                                except subprocess.TimeoutExpired:
                                    pass
                            else:
                                time.sleep(0.25)
                            members = live_owned_group()
                process.wait(timeout=5)
                state["ownedProcessGroupAfterTermination"] = members
                if members:
                    cleanup_errors.append("Owned phase group survived bounded TERM/KILL cleanup")
            except Exception as cleanup_error:
                cleanup_errors.append("Owned phase group cleanup: " + str(cleanup_error))
            state["observedPhaseExitCode"] = process.returncode
        created = evidence_base / "paired-product/created-simulator.txt"
        if created.exists():
            cleanup = {"ownership": str(created), "startedAt": utc()}
            try:
                owned_device = str(uuid.UUID(created.read_text().strip())).upper()
                cleanup["device"] = owned_device
                result = subprocess.run(["xcrun", "simctl", "shutdown", owned_device],
                    text=True, capture_output=True, timeout=30)
                cleanup.update(exitCode=result.returncode, stdout=result.stdout, stderr=result.stderr)
                devices = json.loads(run(["xcrun", "simctl", "list", "devices", "-j"], timeout=15))
                found = [x for values in devices["devices"].values() for x in values if x["udid"].upper() == owned_device]
                cleanup["observedState"] = found[0]["state"] if len(found) == 1 else "UNKNOWN"
                if cleanup["observedState"] != "Shutdown":
                    cleanup_errors.append("Owned simulator was not confirmed Shutdown")
            except Exception as cleanup_error:
                cleanup["error"] = str(cleanup_error)
                cleanup_errors.append("Owned simulator cleanup: " + str(cleanup_error))
            state["ownedSimulatorCleanup"] = cleanup
        if process is not None:
            try:
                rows = run(["ps", "-axo", "pid=,pgid=,state=,command="]).splitlines()
                remaining_group = [line for line in rows if len(line.split(None, 3)) == 4
                    and line.split(None, 3)[1] == str(process.pid)
                    and not line.split(None, 3)[2].startswith("Z")]
                state["remainingOwnedProcessGroup"] = remaining_group
                if remaining_group:
                    cleanup_errors.append("Owned phase process group has remaining live members")
            except Exception as cleanup_error:
                cleanup_errors.append("Owned process-group observation: " + str(cleanup_error))
        state["cleanupErrors"] = cleanup_errors
        if cleanup_errors:
            state.update(status="CLEANUP_INCOMPLETE", original52="REQUIRES_TERMINAL_REVIEW")
        # Input observation failures also remain explicit and cannot skip the charge.
        source_errors = []
        try:
            if run(["git", "rev-parse", "HEAD"], cwd=root) != decision["source"]:
                source_errors.append("Git HEAD changed")
            for item in decision["requiredFiles"]:
                if digest(relative(root, item["path"])) != item["sha256"]:
                    source_errors.append("Input changed: " + item["path"])
        except Exception as observation_error:
            source_errors.append("Final input observation failed: " + str(observation_error))
        state["sourceErrors"] = source_errors
        if source_errors:
            state.update(status="INPUT_DRIFT", original52="REQUIRES_TERMINAL_REVIEW")
        elapsed = time.monotonic() - start
        state.update(finishedAt=utc(), elapsedSeconds=elapsed, cumulativeActiveSeconds=baseline + elapsed,
            logBytes=log.stat().st_size if log.exists() else 0,
            logSHA256=digest(log) if log.exists() else None,
            allowanceExceededDuringCleanup=elapsed > 4500)
        # Persist the charge journal before touching the shared primary ledger.
        checkpoint("charge_ready", chargedSeconds=elapsed, cumulativeActiveSeconds=baseline + elapsed)
        current = json.loads(primary_path.read_text())
        if current["activeElapsedSeconds"] != baseline or current.get("controllerPID") != os.getpid():
            state.update(status="LEDGER_RECONCILIATION_REQUIRED", uncommittedChargeSeconds=elapsed)
        else:
            current["activeElapsedSeconds"] = baseline + elapsed
            record = {**current["phases"][phase_id], "status": "PASS" if state["status"] == "EXECUTED_PASS" else "FAIL",
                "finishedAt": state["finishedAt"], "exitCode": exit_code, "elapsedSeconds": elapsed,
                "logBytes": state["logBytes"], "logSHA256": state["logSHA256"],
                "continuationDecisionSHA256": state["decisionSHA256"]}
            current["phases"][phase_id] = record
            current.setdefault("continuationCharges", []).append({"id": decision["id"], "source": decision["source"],
                "baselineSeconds": baseline, "chargedSeconds": elapsed, "cumulativeSeconds": baseline + elapsed,
                "allowanceSeconds": 4500, "status": state["status"], "decisionSHA256": state["decisionSHA256"]})
            current.update(status="COMPLETED" if state["status"] == "EXECUTED_PASS" else "FAIL", finishedAt=state["finishedAt"])
            if error:
                current["error"] = error
            write(primary_path, current)
        checkpoint("finalized", status=state["status"], elapsedSeconds=elapsed, cumulativeActiveSeconds=baseline + elapsed)
    return 0 if state["status"] == "EXECUTED_PASS" else 1

if __name__ == "__main__":
    raise SystemExit(main())
