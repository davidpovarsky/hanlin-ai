#!/usr/bin/env python3
"""Run the original paired acceptance and separately verified affected groups."""
from pathlib import Path
import argparse, ast, copy, datetime, fcntl, hashlib, importlib.util, json
import math, os, signal, subprocess, sys, time, traceback

ID = "current-source-native-v1"
ROOT = Path("/Users/m1/builds/hanlin-current-entrypoints-20261126")
LOCK = Path("/Users/m1/builds/hanlin-native-action-handler-fix-20261126/validation/.paired52-r4-owner.lock")
PYTHON_SHA = "ab825fde913c394f6fb8dc57da39108ad98e1827a5404119993de3d3bc6d8fb7"
RUNNER_SHA = "a99b6194f8dd20bc30998ff2ad9e86ec219415a00615b250c65670f7dfcdba7d"


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def ref(path):
    path = Path(path)
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": digest(path)}


def verified(row):
    path = Path(row["path"])
    assert path.is_file() and not path.is_symlink(), str(path)
    assert path.stat().st_size == row["bytes"] and digest(path) == row["sha256"], str(path)
    return path


def write(path, data):
    path = Path(path)
    temp = path.with_name(path.name + ".tmp")
    with temp.open("w") as stream:
        json.dump(data, stream, indent=2)
        stream.write("\n"); stream.flush(); os.fsync(stream.fileno())
    temp.replace(path)


def command(argv, timeout=30, cwd=ROOT):
    result = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    assert result.returncode == 0, {"argv": argv, "exitCode": result.returncode,
                                  "stdout": result.stdout, "stderr": result.stderr}
    return result.stdout.strip()


def source_closure(d):
    result = {"head": command(["git", "rev-parse", "HEAD"]),
              "tree": command(["git", "rev-parse", "HEAD^{tree}"]),
              "trackedDiff": command(["git", "status", "--porcelain", "--untracked-files=no"])}
    assert result == {"head": d["source"], "tree": d["sourceTree"], "trackedDiff": ""}, result
    for row in d["requiredFiles"]:
        verified(row)
    manifest = json.loads(verified(d["currentSDK"]["manifest"]).read_text())
    assert manifest["inputSHA256"] == d["currentSDK"]["inputSHA256"]
    assert len(manifest["sourceInputs"]) == d["currentSDK"]["sourceInputs"]
    for row in manifest["sourceInputs"]:
        path = ROOT / row["path"]
        assert path.is_file() and digest(path) == row["sha256"], row
    result.update(sdkSourceInputsVerified=len(manifest["sourceInputs"]),
                  requiredFilesVerified=len(d["requiredFiles"]),
                  host=d["currentSDK"]["host"], sdkManifest=d["currentSDK"]["manifest"])
    return result

def validation_history(d):
    """Charge the actual failed 542 attempt; grant no prior test/build result."""
    history = d["currentValidationHistory"]
    assert "completedSwiftPM" not in d
    assert d["validationScopeSeconds"] == 10800
    assert [row["id"] for row in history] == ["current-source-builds-v1",
        "camera-isolated-conformance-probe-v1", "camera-isolated-conformance-probe-v2",
        "current-source-swiftpm-v1", "current-source-swiftpm-v1-supervision"]
    for row in history:
        authority = json.loads(verified(row["authority"]).read_text())
        assert authority["id"] == row["id"] and authority["status"] == row["status"]
        seconds_field = "additionalObservedElapsedSeconds" if row["id"] == "current-source-swiftpm-v1-supervision" else "actualElapsedSeconds"
        assert row.get("secondsField", "actualElapsedSeconds") == seconds_field
        assert authority[seconds_field] == row["seconds"]
        assert isinstance(row["seconds"], (int, float)) and math.isfinite(row["seconds"]) and row["seconds"] > 0
    assert history[3]["authority"]["sha256"] == "262736a12db1ae311550e54770da20caaaa9c37310d90a78fa872bcaf4c839f9"
    assert history[4]["authority"]["sha256"] == "d14ab36d110a229aa488e91950480745274ac2f509aec5136ff59782722a8435"
    child = json.loads(verified(history[3]["authority"]).read_text())
    outer = json.loads(verified(history[4]["authority"]).read_text())
    assert child["status"] == outer["status"] == "FAILED"
    origin_path = verified(child["decision"])
    assert digest(origin_path) == "b6caf28bf3d6aa88077e91edcd507e8d941287689c98b3fec96855ab8db94b97"
    origin = json.loads(origin_path.read_text())
    # These are historical input identities, not the later current closure.
    assert origin["source"] == child["source"] == outer["source"] == "542714964a0f12a964651c2306d5f992ca13ae85"
    assert origin["sourceTree"] == child["sourceTree"] == outer["sourceTree"]
    assert not child["sourceErrors"] and child["sourceBefore"] == child["sourceAfter"]
    assert child["sourceBefore"]["head"] == origin["source"] and child["sourceBefore"]["tree"] == origin["sourceTree"]
    assert child["sourceBefore"]["trackedDiff"] == ""
    assert child["sourceBefore"]["host"] == origin["currentSDK"]["host"]
    assert child["sourceBefore"]["sdkManifest"] == origin["currentSDK"]["manifest"]
    assert child["toolchainBefore"] == child["toolchainAfter"]
    ledger = json.loads(verified(child["ledger"]).read_text())
    assert ledger["id"] == child["id"] and ledger["status"] == "FAILED"
    assert ledger["history"] == origin["currentValidationHistory"] == history[:3]
    prior = math.fsum(row["seconds"] for row in history[:3])
    assert child["chargedCurrentValidationBeforeSeconds"] == origin["chargedCurrentValidationBeforeSeconds"] == prior
    assert child["validationScopeSeconds"] == ledger["currentValidationCeilingSeconds"] == 10800
    assert ledger["actualElapsedSeconds"] == child["actualElapsedSeconds"] == history[3]["seconds"]
    assert child["totalCurrentValidationChargedSeconds"] == ledger["actualChargedSeconds"] == math.fsum(row["seconds"] for row in history[:4])
    assert child["chargeCommitted"] is True and outer["childChargeCommitted"] is True
    assert outer["childState"] == history[3]["authority"] and outer["childLedger"] == child["ledger"]
    assert outer["runner"] == child["helper"] and outer["decision"] == child["decision"]
    assert outer["childStatus"] == "FAILED" and outer["childExitCode"] == 1
    assert outer["ownedProcessGroupAbsent"] is True and not outer["cleanupErrors"]
    assert not outer.get("timedOut") and not outer.get("error")
    assert digest(verified(history[4]["controller"])) == "19c237580de1d42aeec0eb1443f34643d2dfdd6ad36d82e745461b575d680259"
    assert outer["childReportedActualElapsedSeconds"] == child["actualElapsedSeconds"]
    assert outer["actualElapsedSeconds"] >= child["actualElapsedSeconds"]
    assert outer["additionalObservedElapsedSeconds"] == outer["actualElapsedSeconds"] - child["actualElapsedSeconds"]
    total = math.fsum(row["seconds"] for row in history)
    assert total == d["chargedCurrentValidationBeforeSeconds"] < d["validationScopeSeconds"]
    return total

def verify_acceptance(d):
    evidence = Path(d["output"]) / "original" / "paired-product"
    acceptance_path = evidence / "acceptance.json"
    raw = json.loads(acceptance_path.read_text())
    assert raw["sha"] == d["source"]
    assert all(raw[key] == "EXECUTED_PASS" for key in ["status", "build", "mini_build", "ai_build", "ui"])
    summaries = [("originalMini25", raw["original_runtime_summary"], 25),
                 ("originalAI27", raw["summary"], 27)]
    for name, summary, count in summaries:
        assert summary["passedTests"] == count and summary.get("failedTests", 0) == 0
        assert summary.get("skippedTests", 0) == 0 and summary.get("totalTestCount", count) == count
    assert raw["native_adapter_assets"]["native_request_proof"] == "EXECUTED_PASS_RESOURCE_TRANSPORT"
    commands_path = evidence / "commands.jsonl"
    rows = [json.loads(line) for line in commands_path.read_text().splitlines() if line.strip()]
    for name in ["mini-build.log", "original-a2ui-generator.log", "ai-build.log",
                 "original-runtimes.log", "paired-tests.log"]:
        actual = [row for row in rows if row["log"] == name]
        assert len(actual) == 1 and actual[0]["exit"] == 0, name
        assert digest(evidence / name) == actual[0]["sha256"]
    groups = []
    for key in ["handlerRegression", "routeContractGroup", "newHostedRegression", "assistantHostedRegression"]:
        expected = d[key]
        p = evidence / (expected["id"] + "-review.json")
        review = json.loads(p.read_text())
        assert review["source"] == d["source"] and review["status"] == "EXECUTED_PASS"
        assert review["commandExitCode"] == 0 and review["selectors"] == expected["selectors"]
        assert review["expectedCases"] == expected["expectedCases"]
        for proof in review["proofs"]:
            verified(proof)
        groups.append({"id": expected["id"], "authority": ref(p),
                       "summary": review["summary"], "status": review["status"]})
    for label, definitions, cases in [("widget-host-action-queue", 10, 16), ("affected-swiftpm", 118, 198)]:
        p = evidence / (label + "-review.json")
        review = json.loads(p.read_text())
        assert review["status"] == "EXECUTED_PASS" and review["source"] == d["source"] and review["commandExitCode"] == 0
        if label == "widget-host-action-queue":
            assert review["verification"]["observedFunctions"] == definitions
            assert review["verification"]["observedParameterInstances"] == cases
        else:
            assert review["verification"]["status"] == "EXECUTED_PASS"
            assert review["expectedDefinitions"] == definitions and review["expectedCases"] == cases
        for proof in review.get("proofs", []):
            verified(proof)
        groups.append({"id": label, "authority": ref(p), "verification": review["verification"],
                       "status": review["status"]})
    metadata = []
    for label in ["metadata-after-mini-build", "metadata-after-ai-build"]:
        p = evidence / label / "receipt.json"
        receipt = json.loads(p.read_text())
        assert receipt["status"] == "VERIFIED_COMPILED_METADATA" and not receipt["errors"]
        assert receipt["source"] == d["source"] and receipt["sourceTree"] == d["sourceTree"]
        metadata.append(ref(p))
    shipping_path = evidence / "current-shipping-bundles.json"
    shipping = json.loads(shipping_path.read_text())
    assert shipping["status"] == "VERIFIED_16_BUILT_SHIPPING_BUNDLES" and shipping["source"] == d["source"]
    assert len(shipping["bundles"]) == 16
    for bundle in shipping["bundles"]:
        assert bundle["signatureExitCode"] == 0
        verified(bundle["info"]); verified(bundle["executable"])
    return {"schema": 1, "id": ID, "status": "EXECUTED_PASS", "source": d["source"],
            "sourceTree": d["sourceTree"], "acceptance": ref(acceptance_path),
            "originalCommands": ref(commands_path),
            "original52": {"mini": raw["original_runtime_summary"], "ai": raw["summary"]},
            "separateGroups": groups, "compiledMetadata": metadata,
            "shippingBundles": ref(shipping_path),
            "boundary": "Actual original current-source builds, original25+27 and all separately affected groups. No prior build/test verdict substituted; distribution, separate NS/OS and system-surface obligations remain separate."}

def group_alive(pgid):
    try:
        os.killpg(pgid, 0)
        return True
    except ProcessLookupError:
        return False


def stop_group(process, cleanup):
    pgid = process.pid
    for sig, wait in [(signal.SIGINT, 10), (signal.SIGTERM, 5), (signal.SIGKILL, 5)]:
        if not group_alive(pgid):
            break
        os.killpg(pgid, sig)
        cleanup.append({"pgid": pgid, "signal": sig.name, "observedAt": now()})
        deadline = time.monotonic() + wait
        while group_alive(pgid) and time.monotonic() < deadline:
            process.poll()
            time.sleep(0.2)
    process.poll()
    return [pgid] if group_alive(pgid) else []


def clean_device(d):
    evidence = Path(d["output"]) / "original" / "paired-product"
    created = evidence / "created-simulator.txt"
    if not created.is_file():
        return {"status": "NOT_CREATED"}
    import uuid
    identifier = created.read_text().strip()
    assert str(uuid.UUID(identifier)).upper() == identifier.upper()
    def observe():
        raw = command(["xcrun", "simctl", "list", "devices", "--json"], timeout=30)
        rows = [x for group in json.loads(raw)["devices"].values() for x in group
                if x["udid"] == identifier]
        assert len(rows) == 1 and rows[0]["name"] == "HanlinPaired-" + ID, rows
        return rows[0]
    before = observe()
    if before["state"] != "Shutdown":
        command(["xcrun", "simctl", "shutdown", identifier], timeout=60)
    after = observe()
    assert after["state"] == "Shutdown", after
    return {"status": "SHUTDOWN", "creation": ref(created), "before": before, "after": after}


def coordinate(d, decision_path):
    assert d["id"] == ID and d["root"] == str(ROOT) and d["status"] == "SEALED"
    prior = validation_history(d)
    assert verified(d["controller"]) == Path(__file__).resolve()
    assert verified(d["originalMainGuard"]) == verified(d["guard"])
    assert digest(verified(d["originalRunner"])) == RUNNER_SHA
    assert digest(Path(sys.executable).resolve()) == PYTHON_SHA
    out = Path(d["output"]); derived = Path(d["derivedData"])
    assert out.parent == ROOT / "validation" and out.name == ID
    assert derived == Path("/Users/m1/caches/DerivedData/hanlin-current-entrypoints-20261126")
    with LOCK.open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        assert not out.exists()
        assert derived.is_dir() and not derived.is_symlink() and derived.stat().st_uid == os.getuid()
        before = source_closure(d)
        stat = os.statvfs(ROOT); free = stat.f_bavail * stat.f_frsize
        assert free >= d["resourceAssessment"]["minimumFreeBytes"], {"freeBytes": free, "required": d["resourceAssessment"]["minimumFreeBytes"]}
        out.mkdir()
        started = time.monotonic()
        remaining = 10800.0 - prior
        state = {"schema": 1, "id": ID, "source": d["source"], "sourceTree": d["sourceTree"],
                 "status": "RUNNING", "startedAt": now(), "decision": ref(decision_path),
                 "sourceBefore": before, "resourceAdmission": {"freeBytes": free, "requiredBytes": d["resourceAssessment"]["minimumFreeBytes"]},
                 "sourceErrors": [], "cleanupErrors": [], "cleanupSignals": [], "remainingOwnedProcessGroup": [],
                 "historicalC34": d["historicalC34"], "preparationHistory": d["preparationHistory"],
                 "currentValidationHistory": d["currentValidationHistory"],
                 "chargedCurrentValidationBeforeSeconds": prior, "validationScopeSeconds": 10800}
        write(out / "state.json", state)
        process = None
        env = dict(os.environ, GITHUB_WORKSPACE=str(ROOT), GITHUB_SHA=d["source"],
                   GITHUB_RUN_ID=ID, PAIRED_TEST_SCOPE="miniapp_complete",
                   SPLIT_EVIDENCE=str(out / "original"), SPLIT_DERIVED_DATA=str(derived),
                   DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
        env["PATH"] = str(ROOT / "Tools/node-v24.5.0-darwin-arm64/bin") + ":" + env["PATH"]
        try:
            with (out / "child.log").open("xb") as log:
                process = subprocess.Popen([sys.executable, d["originalMainGuard"]["path"],
                                            "--decision", str(decision_path)],
                                           cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT,
                                           start_new_session=True)
                state["childPID"] = state["ownedPGID"] = process.pid
                write(out / "state.json", state)
                try:
                    code = process.wait(timeout=remaining)
                except subprocess.TimeoutExpired:
                    state["deadlineExceeded"] = True
                    state["remainingOwnedProcessGroup"] = stop_group(process, state["cleanupSignals"])
                    code = process.poll()
                state["childExitCode"] = code
            assert code == 0, {"childExitCode": code}
            state["result"] = verify_acceptance(d)
            write(out / "acceptance-result.json", state["result"])
            state["resultAuthority"] = ref(out / "acceptance-result.json")
            state["status"] = "EXECUTED_PASS"
        except BaseException as error:
            state["status"] = "FAILED"
            state["error"] = {"type": type(error).__name__, "message": str(error)}
            traceback.print_exc()
        finally:
            if process is not None:
                try:
                    state["remainingOwnedProcessGroup"] = stop_group(process, state["cleanupSignals"])
                    assert not state["remainingOwnedProcessGroup"]
                except BaseException as error:
                    state["cleanupErrors"].append({"type": type(error).__name__, "message": str(error)})
            try:
                state["ownedDevice"] = clean_device(d)
            except BaseException as error:
                state["cleanupErrors"].append({"type": type(error).__name__, "message": str(error)})
            try:
                state["sourceAfter"] = source_closure(d)
                assert state["sourceAfter"] == state["sourceBefore"]
            except BaseException as error:
                state["sourceErrors"].append({"type": type(error).__name__, "message": str(error)})
            if state["sourceErrors"] or state["cleanupErrors"]:
                state["status"] = "FAILED"
            state["finishedAt"] = now()
            state["actualElapsedSeconds"] = time.monotonic() - started
            total = math.fsum([prior, state["actualElapsedSeconds"]])
            state["totalCurrentValidationChargedSeconds"] = total
            state["remainingCurrentValidationSeconds"] = max(0.0, 10800.0 - total)
            state["chargeCommitted"] = True
            stat = os.statvfs(ROOT); state["availableBytesAfter"] = stat.f_bavail * stat.f_frsize
            write(out / "ledger.json", {"schema": 1, "id": ID,
                  "historicalC34": d["historicalC34"], "preparationHistory": d["preparationHistory"],
                  "currentValidationCeilingSeconds": 10800,
                  "history": d["currentValidationHistory"], "actualChargedSeconds": total,
                  "remainingSeconds": state["remainingCurrentValidationSeconds"],
                  "phase": {"id": ID, "status": state["status"], "startedAt": state["startedAt"],
                            "finishedAt": state["finishedAt"], "seconds": state["actualElapsedSeconds"]}})
            write(out / "state.json", state)
        return 0 if state["status"] == "EXECUTED_PASS" else 1

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--decision", type=Path, required=True)
    args = parser.parse_args()
    d = json.loads(args.decision.read_text())
    return coordinate(d, args.decision)

if __name__ == "__main__":
    sys.exit(main())
