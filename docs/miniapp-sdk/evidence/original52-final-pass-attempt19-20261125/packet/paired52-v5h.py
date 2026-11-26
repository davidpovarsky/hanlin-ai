"""Execute the fresh original MiniApps25 and AI27 against authenticated retained products.
The sealed native child owns setup and exact original selectors, image and modal proofs.
All four earlier paired charges and both existing grants remain immutable. No build or SDK regeneration.
"""
from pathlib import Path
import argparse, datetime, fcntl, hashlib, json, math, os, shlex, signal, subprocess, sys, time, uuid

ID = 'paired52-continuation-v5'
SOURCE = 'd4a0b115b106d4250ea40ad66153d5156847a07c'
TREE = 'f7a6596a1ef53d8d962ceb9f619460ffa19ee91e'
CHILD_SHA = '04ff68e1ebc6ccd7069363c0aa32894af4b28a815d73a9c8fc6e6d5c3bc5128a'
RUNNER_SHA = 'a99b6194f8dd20bc30998ff2ad9e86ec219415a00615b250c65670f7dfcdba7d'
SDK_ARCHIVE_SHA = '7a426675109c5ebc4c8b5824565547f8aea10584785932280fdb623128530ecc'
SDK_MANIFEST_SHA = '4505c28495d8b6ecd1073254e0e395adcc898cc02dd1d40699591f51db4dee92'
SDK_INPUT_SHA = 'ba8f3f1f09054887eed62532fa1d5ca2ac3bd60e6aa99a98ab1035c7653882a2'
NODE_SHA = '336b5b3ebc5deb86df842102b20b6e4761605b7a667823e68dda7761b91a161b'
EXPECTED_GROUPS = {'OriginalRuntimes': 25, 'Paired': 27}
REMAINING_ALLOWANCE = 3720.3727040829836

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

def historical_group_exclusion(terminal, authority, root, derived, live_group, utc):
    pgid = int(terminal["phasePID"])
    initial = live_group(pgid)
    if not initial:
        return None
    # Numeric process-group identifiers can be reused after an authenticated clear.
    assert terminal.get("remainingOwnedProcessGroup") == []
    finished = datetime.datetime.fromisoformat(terminal["finishedAt"])
    assert finished.tzinfo is not None
    finished = finished.astimezone(datetime.timezone.utc)
    pids = {line.split()[0] for line in initial}
    argv = ["/bin/ps", "-p", ",".join(sorted(pids, key=int)),
            "-o", "pid=,pgid=,state=,lstart=,command="]
    query = subprocess.run(argv, text=True, capture_output=True, timeout=10,
                           env=dict(os.environ, TZ="UTC", LC_ALL="C"))
    assert query.returncode == 0 or (query.returncode == 1 and not query.stdout.strip() and not query.stderr.strip()), query.stderr
    months = {month: number for number, month in enumerate("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(), 1)}
    markers = [str(root), str(derived)]
    device = terminal.get("ownedSimulatorCleanup", {}).get("device")
    if device:
        markers.append(str(device))
    members = []
    for line in query.stdout.splitlines():
        values = line.split(None, 8)
        assert len(values) == 9, line
        if values[0] not in pids or values[1] != str(pgid) or values[2].startswith("Z"):
            continue
        started = datetime.datetime(int(values[7]), months[values[4]], int(values[5]),
            *map(int, values[6].split(":")), tzinfo=datetime.timezone.utc)
        command = values[8]
        related = [marker for marker in markers if marker and marker in command]
        assert started > finished and not related, {"historicalPGID": pgid,
            "terminal": authority, "finishedAt": finished.isoformat(),
            "startedAtUTC": started.isoformat(), "command": command, "ownedMarkers": related}
        members.append({"pid": int(values[0]), "pgid": pgid, "state": values[2],
            "startedAtUTC": started.isoformat(), "command": command})
    remaining = {int(line.split()[0]) for line in live_group(pgid)}
    assert remaining <= {member["pid"] for member in members}, "Historical group changed during targeted identity observation"
    if not members:
        return None
    return {"terminal": authority, "historicalPGID": pgid, "priorFinishedAt": terminal["finishedAt"],
        "priorRemainingOwnedProcessGroup": [], "observedAt": utc(),
        "disposition": "UNRELATED_PGID_REUSE_AFTER_AUTHENTICATED_CLEAR",
        "query": {"argv": argv, "environment": {"TZ": "UTC", "LC_ALL": "C"},
                  "exitCode": query.returncode, "stdout": query.stdout, "stderr": query.stderr},
        "members": members, "recheckedLivePIDs": sorted(remaining)}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--decision", type=Path, required=True)
    args = parser.parse_args()
    decision_path = args.decision.resolve()
    decision_bytes = decision_path.read_bytes()
    decision = json.loads(decision_bytes)
    assert decision["schema"] == 1 and decision["owner"] == "/root/native_execution"
    assert decision["id"] == ID
    assert decision["source"] == SOURCE and decision["sourceTree"] == TREE
    assert decision["commandCeilingsSeconds"] == {"OriginalRuntimes": 2400, "Paired": 2100}
    assert set(decision["groups"]) == set(EXPECTED_GROUPS)
    assert all(decision["groups"][name]["expected"] == count for name, count in EXPECTED_GROUPS.items())
    assert decision["scope"] == "miniapp_complete" and decision["expectedCases"] == 52
    assert decision["originalTotalPairedAllowanceSeconds"] == 4500
    root = Path(decision["root"]).resolve()
    ctrl = root / "build/primary-control"
    expected_grants = [("paired52-additional-grant-20261125", 2400),
        ("paired52-additional-grant-20261125-supplement", 600)]
    assert len(decision["additionalGrants"]) == len(expected_grants)
    grants, grant_bytes_list, total_grant = [], [], 4500
    for item, (expected_id, amount) in zip(decision["additionalGrants"], expected_grants):
        grant_path = relative(root, item["path"])
        assert grant_path.is_relative_to(ctrl)
        assert digest(grant_path) == item["sha256"]
        grant_bytes = grant_path.read_bytes()
        grant = json.loads(grant_bytes)
        assert grant["schema"] == 1 and grant["id"] == expected_id
        assert grant["owner"] == "/root/native_execution" and grant["authorization"]["by"] == "/root"
        assert grant["originalTotalPairedAllowanceSeconds"] == 4500
        assert grant["additionalOperationalAllowanceSeconds"] == amount
        total_grant += amount
        assert grant["totalPairedAllowanceSeconds"] == total_grant
        if grants:
            assert grant["previousGrantSHA256"] == hashlib.sha256(grant_bytes_list[-1]).hexdigest()
        grants.append(grant)
        grant_bytes_list.append(grant_bytes)
    allowance = decision["allowanceSeconds"]
    prior_charge = decision["priorContinuationChargedSeconds"]
    assert math.isfinite(allowance) and 0 < allowance <= total_grant
    assert math.isfinite(prior_charge) and 0 <= prior_charge < total_grant
    assert allowance == total_grant - prior_charge == REMAINING_ALLOWANCE
    assert decision["authorization"]["by"] == "/root" and decision["authorization"]["scope"] == "one original paired52 continuation"
    receipts = decision["priorContinuations"]
    assert [x["id"] for x in receipts] == ["paired52-continuation-v1", "paired52-continuation-v2", "paired52-continuation-v3", "paired52-continuation-v4"]
    charges = []
    for item in receipts:
        prior_path = ctrl / item["id"] / "state.json"
        assert digest(prior_path) == item["stateSHA256"]
        prior = json.loads(prior_path.read_text())
        assert prior["id"] == item["id"] and prior["status"] == "FAILED"
        assert prior["allowanceSeconds"] == (total_grant if item["id"].endswith("-v4") else 4500) - math.fsum(charges)
        assert not prior["remainingOwnedProcessGroup"] and not prior["cleanupErrors"] and not prior["sourceErrors"]
        assert prior["chargedSeconds"] == item["chargedSeconds"]
        assert math.isfinite(prior["chargedSeconds"]) and prior["chargedSeconds"] >= 0
        charges.append(prior["chargedSeconds"])
    assert math.fsum(charges) == decision["priorContinuationChargedSeconds"]
    granted_before = 4500
    for grant in grants:
        assert grant["priorContinuations"] == receipts[:3]
        original_grant_charge = math.fsum(charges[:3])
        assert grant["priorContinuationChargedSeconds"] == original_grant_charge
        assert grant["remainingBeforeGrantSeconds"] == granted_before - original_grant_charge
        granted_before += grant["additionalOperationalAllowanceSeconds"]
        assert grant["remainingAfterGrantSeconds"] == granted_before - original_grant_charge
    assert math.isclose(grants[-1]["remainingAfterGrantSeconds"] - charges[3], allowance, abs_tol=1e-8)
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
    prior_charges = primary["continuationCharges"]
    assert len(prior_charges) == 4
    assert [x["id"] for x in prior_charges] == [x["id"] for x in receipts]
    assert [x["chargedSeconds"] for x in prior_charges] == charges
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
    required = decision["requiredFiles"]
    assert len({x["path"] for x in required}) == len(required)
    required_map = {x["path"]: x["sha256"] for x in required}
    for item in required:
        path = relative(root, item["path"])
        assert path.is_file() and digest(path) == item["sha256"], item["path"]
    assert required_map["Scripts/ProductSplit/run_paired_acceptance.py"] == RUNNER_SHA
    assert required_map["AI_HLY/RuntimeHostResources.zip"] == SDK_ARCHIVE_SHA
    assert "Scripts/CI/verify_selected_tests.py" in required_map
    sdk = decision["sdk"]
    sdk_path = relative(root, sdk["manifestPath"])
    assert digest(sdk_path) == sdk["manifestSHA256"] == SDK_MANIFEST_SHA
    assert sdk["archiveSHA256"] == SDK_ARCHIVE_SHA and sdk["inputSHA256"] == SDK_INPUT_SHA
    manifest = json.loads(sdk_path.read_text())
    assert manifest["inputSHA256"] == SDK_INPUT_SHA
    assert len(manifest["sourceInputs"]) == sdk["sourceInputCount"] == 235
    assert len({x["path"] for x in manifest["sourceInputs"]}) == 235
    for row in manifest["sourceInputs"]:
        assert required_map.get(row["path"]) == row["sha256"], row["path"]
    child_path = relative(root, decision["child"]["path"])
    assert child_path.is_relative_to(ctrl)
    assert digest(child_path) == decision["child"]["sha256"] == CHILD_SHA

    def live_group(pgid):
        pgid = int(pgid)
        assert pgid > 1
        try:
            os.killpg(pgid, 0)
        except ProcessLookupError:
            return []
        candidates = subprocess.run(["/usr/bin/pgrep", "-g", str(pgid)],
                                    text=True, capture_output=True, timeout=10)
        assert candidates.returncode == 0 or (candidates.returncode == 1 and not candidates.stdout.strip() and not candidates.stderr.strip()), candidates.stderr
        pids = candidates.stdout.split()
        if not pids:
            return []
        assert all(pid.isdigit() and int(pid) > 1 for pid in pids)
        query = subprocess.run(["/bin/ps", "-p", ",".join(pids), "-o", "pid=,pgid=,state="],
                               text=True, capture_output=True, timeout=10)
        assert query.returncode == 0 or (query.returncode == 1 and not query.stdout.strip() and not query.stderr.strip()), query.stderr
        return [line for line in query.stdout.splitlines() if len(v := line.split()) == 3
                and v[0] in pids and v[1] == str(pgid) and not v[2].startswith("Z")]

    historical_group_exclusions = []
    terminals = decision["priorTerminals"]
    preserved = decision["preservedLedgers"]
    assert terminals and preserved
    prior_controllers = {primary.get("controllerPID")} - {None}
    for item in terminals:
        path = relative(root, item["path"])
        assert path.is_relative_to(ctrl) and digest(path) == item["sha256"]
        old = json.loads(path.read_text())
        assert old["status"] not in ("STARTING", "RUNNING", "WAITING", "READY")
        assert not old.get("remainingOwnedProcessGroup", []) and not old.get("cleanupErrors", [])
        if old.get("phasePID") is not None:
            exclusion = historical_group_exclusion(old, item, root, Path(decision["derivedData"]), live_group, utc)
            if exclusion is not None:
                historical_group_exclusions.append(exclusion)
        if old.get("controllerPID") is not None:
            prior_controllers.add(old["controllerPID"])
    for item in preserved:
        assert digest(relative(root, item["path"])) == item["sha256"]
    historic_pids = prior_controllers - {os.getpid()}
    process_rows = []
    if historic_pids:
        query = subprocess.run(["/bin/ps", "-p", ",".join(str(pid) for pid in sorted(historic_pids)),
                                "-o", "pid=,state=,command="], text=True, capture_output=True, timeout=10)
        assert query.returncode == 0 or (query.returncode == 1 and not query.stdout.strip() and not query.stderr.strip()), query.stderr
        process_rows = query.stdout.splitlines()
    for pid in historic_pids:
        for line in process_rows:
            values = line.split(None, 2)
            if len(values) != 3 or values[0] != str(pid) or values[1].startswith("Z"):
                continue
            try:
                arguments = shlex.split(values[2])
            except ValueError:
                arguments = values[2].split()
            python = bool(arguments) and Path(arguments[0]).name.lower().startswith("python")
            owned_script = any(argument.startswith(str(ctrl) + "/")
                               and Path(argument).suffix == ".py" for argument in arguments[1:])
            if python and owned_script:
                raise RuntimeError("Prior owned controller remains active: " +
                                   json.dumps({"pid": pid, "argv": arguments}, sort_keys=True))
    original_node = decision["originalNode"]
    node_path = Path(original_node["path"]).resolve(strict=True)
    assert node_path.is_file() and digest(node_path) == original_node["sha256"] == NODE_SHA
    node_identity = json.loads(run([str(node_path), "-p",
        "JSON.stringify({node:process.versions.node,platform:process.platform,architecture:process.arch})"]))
    assert node_identity["node"] == original_node["version"] == "24.5.0"
    for engine in ["Expo", "NativeScript"]:
        receipt = json.loads((root / "Scripts" / engine / "node_modules/.hanlin-miniapp-install.json").read_text())
        assert all(node_identity[k] == receipt["inputs"][k] for k in node_identity)
    assert decision["resourceAssessment"]["decision"] == "FITS_MEASURED_NEXT_PHASE"
    # Resource estimates are specific input evidence; no fixed free/CPU/load rule is introduced.
    disk = run(["df", "-k", "/System/Volumes/Data"])
    fresh_free = int(disk.splitlines()[-1].split()[3]) * 1024
    need = decision["resourceAssessment"]["estimatedIncrementalBytes"] + decision["resourceAssessment"]["concurrentAndOSAllowanceBytes"]
    assert fresh_free >= need, "Measured phase requirement no longer fits; preserve decision, do not dispatch."
    out.mkdir()
    (out / "decision.json").write_bytes(decision_bytes)
    (out / "grants").mkdir()
    for grant, grant_bytes in zip(grants, grant_bytes_list):
        (out / "grants" / (grant["id"] + ".json")).write_bytes(grant_bytes)
    (out / "primary-state-before.json").write_bytes(primary_path.read_bytes())
    (out / "plan-before.json").write_bytes(plan_path.read_bytes())
    state_path, events = out / "state.json", out / "events.jsonl"
    child_out = out / "native-result"
    # The authenticated native child exclusively creates this output directory.
    env = dict(os.environ)
    env.update({"PATH": str(node_path.parent) + ":/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer", "GITHUB_WORKSPACE": str(root),
        "GITHUB_SHA": decision["source"], "GITHUB_RUN_ID": "primary-ce49e30d-20261124",
        "SPLIT_EVIDENCE": str(child_out),
        "SPLIT_DERIVED_DATA": decision["derivedData"],
        "SPLIT_NATIVE_TEST_SCOPE": "baseline", "PAIRED_TEST_SCOPE": "miniapp_complete",
        "RUNNER_TEMP": str(root / "build/primary-temp"), "PAIRED_PROOF_REUSE_REQUIRED": "false"})
    assert run(["node", "--version"], env=env) == "v24.5.0"
    argv = [sys.executable, str(child_path), "--decision", str(out / "decision.json"), "--output", str(child_out)]
    log = out / "controller-child.log"
    state = {"schema": 1, "owner": decision["owner"], "id": decision["id"], "source": decision["source"],
        "scope": "miniapp_complete", "expectedCases": 52, "status": "STARTING",
        "historicalProcessGroupExclusions": historical_group_exclusions,
        "decisionSHA256": hashlib.sha256(decision_bytes).hexdigest(), "controllerPID": os.getpid(),
        "activeBaselineSeconds": baseline, "allowanceSeconds": allowance, "originalPlanMaximumActiveSeconds": 12600,
        "originalTotalPairedAllowanceSeconds": 4500, "priorContinuationChargedSeconds": prior_charge,
        "additionalGrants": [{"id": g["id"], "sha256": hashlib.sha256(raw).hexdigest(),
            "seconds": g["additionalOperationalAllowanceSeconds"]} for g, raw in zip(grants, grant_bytes_list)],
        "additionalOperationalAllowanceSeconds": total_grant - 4500, "totalPairedAllowanceSeconds": total_grant,
        "guard": "authenticated-original25-plus27-retained-products-v5", "argv": argv,
        "log": str(log), "pairedEvidence": str(child_out), "sourceTree": TREE,
        "originalNode": {**original_node, "observedIdentity": node_identity},
        "childSHA256": CHILD_SHA, "expectedGroups": decision["groups"],
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
            "baselineSeconds": baseline, "allowanceSeconds": allowance, "originalPlanMaximumActiveSeconds": 12600})
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
                remaining = allowance - (time.monotonic() - start)
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
        acceptance_path = child_out / "state.json"
        acceptance = json.loads(acceptance_path.read_text())
        state["actualAcceptance"] = {"path": str(acceptance_path), "sha256": digest(acceptance_path),
            "status": acceptance.get("status"), "groups": acceptance.get("groups")}
        assert exit_code == 0, "Original paired child returned " + str(exit_code)
        assert acceptance["source"] == SOURCE and acceptance["tree"] == TREE
        assert acceptance["status"] == acceptance["original52"] == "EXECUTED_PASS"
        assert acceptance["original25"] == acceptance["original27"] == "EXECUTED_PASS"
        assert not acceptance["sourceErrors"] and not acceptance["cleanupErrors"] and not acceptance["errors"]
        assert set(acceptance["groups"]) == set(EXPECTED_GROUPS)
        for label, count in EXPECTED_GROUPS.items():
            group = acceptance["groups"][label]
            assert group["status"] == "PASS" and group["exitCode"] == 0 and group["resultFinalized"] is True
            assert group["selectors"] == decision["groups"][label]["selectors"]
            summary = group["summary"]
            assert summary["totalTestCount"] == summary["passedTests"] == count
            assert summary["failedTests"] == summary["skippedTests"] == 0
        assert {("/pixel.png", 200), ("/missing.png", 404)} <= {
            (x["path"], x["status"]) for x in acceptance["nativeAdapterRequests"]}
        modal = acceptance["externalModalResult"]
        assert modal["status"] == "EXECUTED_PASS" and modal["exitCode"] == 0
        modal_receipt = Path(modal["receiptPath"]).resolve()
        assert modal_receipt == child_out / "external-modal-result.json"
        assert digest(modal_receipt) == modal["receiptSHA256"]
        assert json.loads(modal_receipt.read_text()) == modal["actual"]
        assert modal["actual"]["requestID"].lower() == "4f2ecda0-9c21-46a2-b2e1-8cd4f017c623"
        assert modal["actual"]["status"] == "success" and modal["actual"]["message"] == "Modal invocation survived"
        ownership = child_out / "created-simulator.txt"
        assert ownership.is_file() and not ownership.is_symlink()
        device = str(uuid.UUID(ownership.read_text().strip())).upper()
        assert device == str(uuid.UUID(acceptance["simulator"])).upper()
        state.update(status="EXECUTED_PASS", original52="EXECUTED_PASS")
        checkpoint("actual_terminal", status=state["status"], original52=state["original52"],
                   exitCode=exit_code, childStateSHA256=digest(acceptance_path))
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
            return live_group(process.pid)
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
        created = child_out / "created-simulator.txt"
        if created.exists():
            cleanup = {"ownership": str(created), "startedAt": utc()}
            try:
                assert created.is_file() and not created.is_symlink()
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
                remaining_group = live_group(process.pid)
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
            for item in required + preserved + terminals + decision["additionalGrants"]:
                if digest(relative(root, item["path"])) != item["sha256"]:
                    source_errors.append("Input changed: " + item["path"])
            if digest(child_path) != CHILD_SHA:
                source_errors.append("Bound native child changed")
            if digest(sdk_path) != SDK_MANIFEST_SHA:
                source_errors.append("SDK manifest changed")
            for item in receipts:
                if digest(ctrl / item["id"] / "state.json") != item["stateSHA256"]:
                    source_errors.append("Historical paired terminal changed: " + item["id"])
            if hashlib.sha256(subprocess.check_output(["git", "diff", "--binary", "HEAD"], cwd=root)).hexdigest() != decision["preparedTrackedDiffSHA256"]:
                source_errors.append("Prepared tracked inputs changed")
        except Exception as observation_error:
            source_errors.append("Final input observation failed: " + str(observation_error))
        state["sourceErrors"] = source_errors
        if source_errors:
            state.update(status="INPUT_DRIFT", original52="REQUIRES_TERMINAL_REVIEW")
        elapsed = time.monotonic() - start
        state.update(finishedAt=utc(), elapsedSeconds=elapsed, cumulativeActiveSeconds=baseline + elapsed,
            logBytes=log.stat().st_size if log.exists() else 0,
            logSHA256=digest(log) if log.exists() else None,
            allowanceExceededDuringCleanup=elapsed > allowance)
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
                "allowanceSeconds": allowance, "status": state["status"], "decisionSHA256": state["decisionSHA256"]})
            current.update(status="COMPLETED" if state["status"] == "EXECUTED_PASS" else "FAIL", finishedAt=state["finishedAt"])
            if error:
                current["error"] = error
            write(primary_path, current)
            state["chargeCommitted"] = True
        checkpoint("finalized", status=state["status"], elapsedSeconds=elapsed, cumulativeActiveSeconds=baseline + elapsed)
    return 0 if state["status"] == "EXECUTED_PASS" else 1

if __name__ == "__main__":
    raise SystemExit(main())
