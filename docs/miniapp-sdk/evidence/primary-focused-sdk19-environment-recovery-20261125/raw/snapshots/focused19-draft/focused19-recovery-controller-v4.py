"""Original probe production/affected AI build, then only original ManualInput and repair UI.
The native owner seals actual SDK19/prefix/source/ledger inputs before execution.
The child authenticates retained MiniApps products and records the affected AI rebuild.
No prior or full52 result is promoted.
"""
from pathlib import Path
import argparse, fcntl, hashlib, importlib.util, json, math, os, signal, subprocess, sys, time, uuid

ID = "focused19-v4"
SOURCE = "6c006c948f0a6f371f7fc68b90e393f43734f8dd"
PREVIOUS_SOURCE = "62dfff9aebd0a272486c7770d4f77ba603d535ab"
TREE = "ecd109e872e08873410a6bf55db697bd42864fa2"
PRODUCER_SOURCE = "a2c8a1b1be746461272ba77254603304567c309d"
PREFIX_SHA = "846d7b35087174f0c6d5032dc0615d04f5f50eaedc7e48447438d187da90b954"
PREFIX_BASELINE = 15472.911772584037
PRIOR_V1_CHARGE = 366.7222996670025
PRIOR_V2_CHARGE = 977.134837125006
PRIOR_ENV_CHARGE = 39.67624695900304
PRIOR_NATIVE_CHARGE = PRIOR_V1_CHARGE + PRIOR_V2_CHARGE
PRIOR_CHARGE = PRIOR_NATIVE_CHARGE + PRIOR_ENV_CHARGE
NATIVE_BASELINE = 16816.768909376045
ACTIVE_BASELINE = 16856.44515633505
ORIGINAL_ALLOWANCE = 3600
REMAINING_ALLOWANCE = ORIGINAL_ALLOWANCE - PRIOR_CHARGE
CHANGED_SOURCES = ["AI_HLYTests/HanlinOriginalScriptWidgetLiveActivityTests.swift",
                   "AI_HLY/Downstream/AgentDiagnostics/AgentRuntimeUIAcceptanceProvider.swift",
                   "Fixtures/ExpoSwiftUIProbe/ManualAdapterProbe.tsx"]
MUTABLE_FIXTURES = [folder + "/" + name + ".hanlinExpo"
                    for folder in ["Fixtures/ExpoSwiftUIProbe", "AI_HLYUITests/Fixtures"]
                    for name in ["ExpoSwiftUIProbe", "ExpoSwiftUIProbeA", "ExpoSwiftUIProbeB"]]
RECOVERY_INPUTS = "build/primary-control/focused19-v3-recovery-inputs.json"
RECOVERY_INPUTS_SHA = "2791472af9e3fc99292ce8889ac3c2f2b6f08bf11f8faa1bdd1ac7e561d3f56c"
PRIOR_RECORDS = [{'path': 'build/primary-control/focused19-v1/state.json', 'sha256': 'a7ae2d21b27503b71939ff72670333a7e05736e47e999801f52e6ee6c1520dd6'}, {'path': 'build/primary-control/focused19-v1/ledger.json', 'sha256': 'c7835bb97d3017d305628e76ce25b35cfb415433780c4a43f806d0d56fbf708f'}, {'path': 'build/primary-control/focused19-v1/decision.json', 'sha256': '77eef76303d4df1ac274a6cbf3db71b8f7efc4ee7f4e9b623334d565dd3297a3'}, {'path': 'build/primary-control/focused19-v1/native-result/state.json', 'sha256': 'f8f7fd1284b984d77237a2e487961eab0782ba079fadfe43f3805d68148fc24e'}, {'path': 'build/primary-control/focused19-v2/state.json', 'sha256': '9e199031a41095f66c101962da3c1c4ad330e748a9ac2afc267aac71384c2a21'}, {'path': 'build/primary-control/focused19-v2/ledger.json', 'sha256': 'ec1d8b41595201d0a64b86d714a0fbd049cfbc9339b8a494fff25875cf6d6898'}, {'path': 'build/primary-control/focused19-v2/decision.json', 'sha256': '72608e39bc0987c619ea24b0eeea53b18cd5cca6f86c4a3dab688699580a315c'}, {'path': 'build/primary-control/focused19-v2/native-result/state.json', 'sha256': '5a0005645e789fc4979ff7515faf2c7ed28a589ff1f5aacdaa35cfdb388a3339'}, {'path': 'build/primary-control/focused19-v3/state.json', 'sha256': 'fc722c1417dfcb5029336df1b27f06fd1ec636ae2bc5bcfc82a2258d4f894d25'}, {'path': 'build/primary-control/focused19-v3/ledger.json', 'sha256': 'c69a3001ec612c74afeaeafcbdf3e8fc2b0ea59fbb96bf18488a2ff641e76ebf'}, {'path': 'build/primary-control/focused19-v3/decision.json', 'sha256': 'e5317f244c6cf6cecb4b9a9c1b3043b1921fbe646d922f332d7bdcd103fea86a'}, {'path': 'build/primary-control/focused19-v3/native-result/state.json', 'sha256': '627355b9bb7c970106c2c5dee504937235d6d55e5782b2129b7427e3f1024e48'}]

RUNNER = "Scripts/ProductSplit/run_paired_acceptance.py"
RUNNER_SHA = "a99b6194f8dd20bc30998ff2ad9e86ec219415a00615b250c65670f7dfcdba7d"
HELPER_SHA = "dad6581212134987b666a5161ab33994e6d79b57ed38108faba6ffb22c3bb520"
CHILD_SHA = "bfa992d6793451374eb847f9e0b0f4d28d32a153163ded9ae427acd0bfa5f478"
PREFIX_IDS = ["split-upstreams", "generate-manifest", "generate-project", "verify-targets",
              "lint-generated-project", "runtime-version-contract8", "split-native-preparation",
              "split-native-artifacts", "split-restore-inputs", "split-inputs"]
SOURCE_PATHS = ['AI_HLY/ChatView.swift', 'AI_HLYTests/HanlinOriginalScriptWidgetLiveActivityTests.swift', 'HanlinMiniAppsUITests/HanlinMiniAppsUITests.swift', 'Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/HanlinExpoUIModule.swift', 'Packages/HanlinExpoUI/src/manual-components.tsx', 'Scripts/ProductSplit/run_paired_acceptance.py', 'Scripts/ProductSplit/test_run_paired_acceptance.py', 'Fixtures/ExpoSwiftUIProbe/ManualAdapterProbe.tsx', 'AI_HLY/Downstream/AgentDiagnostics/AgentRuntimeUIAcceptanceProvider.swift', 'AI_HLYUITests/MiniAppAuthoringUITests.swift', 'Scripts/Expo/build-probe.mjs']
MINI = ['HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneExpoManualInputLayoutAndDataAdapters']
AI = ['AI_HLYUITests/MiniAppAuthoringUITests/testTypeErrorRepairsThroughOriginalAgentBuildAndCompanionImport']
GROUPS = {'FocusedManual1': {'expected': 1, 'selectors': ['HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneExpoManualInputLayoutAndDataAdapters']}, 'FocusedRepair1': {'expected': 1, 'selectors': ['AI_HLYUITests/MiniAppAuthoringUITests/testTypeErrorRepairsThroughOriginalAgentBuildAndCompanionImport']}}
AUTHORIZATION_SCOPE = 'Only original ManualInput and repair UI after original probe production and affected AI build; reuse authenticated MiniApps product and owned E742. Preserve previous9 actual PASS separately and all original52 requirements.'

def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()

def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--decision", type=Path, required=True)
    args = parser.parse_args()
    decision_bytes = args.decision.resolve().read_bytes()
    d = json.loads(decision_bytes)
    assert d["schema"] == 1 and d["id"] == ID and d["owner"] == "/root/native_execution"
    assert d["authorization"] == {"by": "/root", "scope": AUTHORIZATION_SCOPE}
    assert d["source"] == SOURCE and d["sourceTree"] == TREE
    assert d["allowanceSeconds"] == REMAINING_ALLOWANCE and d["original52Unchanged"] is True
    assert d["producerSource"] == PRODUCER_SOURCE and d["activeBaselineSeconds"] == ACTIVE_BASELINE
    assert d["priorFocusRecords"] == PRIOR_RECORDS
    assert d["groups"] == GROUPS and d["commandCeilingsSeconds"] == {"FocusedManual1": 1260, "FocusedRepair1": 2100}
    assert math.isfinite(d["activeBaselineSeconds"]) and d["activeBaselineSeconds"] >= 0
    root = Path(d["root"]).resolve()
    ctrl = root / "build/primary-control"
    helper_path = (root / d["originalController"]["path"]).resolve()
    child_path = (root / d["child"]["path"]).resolve()
    assert helper_path.is_relative_to(ctrl) and child_path.is_relative_to(ctrl)
    assert digest(helper_path) == d["originalController"]["sha256"] == HELPER_SHA
    assert digest(child_path) == d["child"]["sha256"] == CHILD_SHA
    h = module(helper_path, "original_native_continuation_helpers")
    out = h.relative(root, d["outputDirectory"])
    assert out == ctrl / ID and not out.exists()
    child_out = out / "native-result"
    ownership = child_out / "paired-prefix/created-simulator.txt"
    lock = (ctrl / "native-continuation-owner.lock").open("a")
    fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    primary_path = ctrl / "state.json"
    assert digest(primary_path) == d["primaryStateSHA256"]
    primary_bytes = primary_path.read_bytes()
    primary = json.loads(primary_bytes)
    assert primary["status"] == "PAUSED_AFTER_PHASE" and primary["phase"] == "split-inputs"
    assert primary["source"] == SOURCE and primary["activeElapsedSeconds"] == d["activeBaselineSeconds"]
    assert h.run(["git", "rev-parse", "HEAD"], cwd=root) == SOURCE
    assert h.run(["git", "rev-parse", "HEAD^{tree}"], cwd=root) == TREE
    assert hashlib.sha256(subprocess.check_output(["git", "diff", "--binary", "HEAD"], cwd=root)).hexdigest() == d["preparedTrackedDiffSHA256"]
    prefix_path = h.relative(root, d["prefix"]["path"])
    assert prefix_path.is_relative_to(ctrl) and digest(prefix_path) == d["prefix"]["sha256"] == PREFIX_SHA
    prefix_bytes = prefix_path.read_bytes()
    prefix = json.loads(prefix_bytes)
    assert prefix["source"] == PRODUCER_SOURCE and prefix["status"] == "PASS" and not prefix["cleanupErrors"]
    assert [x["id"] for x in prefix["steps"]] == PREFIX_IDS
    assert all(x["status"] == "PASS" and x["exitCode"] == 0 for x in prefix["steps"])
    assert prefix["cumulativeActiveSeconds"] == PREFIX_BASELINE and prefix["allowanceSeconds"] == 600
    prior = []
    for item in PRIOR_RECORDS:
        path = h.relative(root, item["path"])
        assert path.is_relative_to(ctrl) and digest(path) == item["sha256"]
        prior.append(json.loads(path.read_text()))
    first_state, first_ledger, first_decision, first_child, old_state, old_ledger, old_decision, old_child = prior[:8]
    environment_state, environment_ledger, environment_decision, environment_child = prior[8:]
    assert first_state["source"] == first_decision["source"] == first_child["source"] == PRODUCER_SOURCE
    assert first_state["status"] == first_child["status"] == "FOCUSED_FAILED"
    assert first_state["chargeCommitted"] and not first_state["cleanupErrors"] and not first_state["sourceErrors"]
    assert not first_child["groups"] and not first_child["checkpointReached"]
    assert not first_child["cleanupErrors"] and not first_child["sourceErrors"]
    assert first_state["chargedSeconds"] == first_ledger["activeElapsedSeconds"] == PRIOR_V1_CHARGE
    assert first_state["activeBaselineSeconds"] == PREFIX_BASELINE
    assert first_state["cumulativeActiveSeconds"] == PREFIX_BASELINE + PRIOR_V1_CHARGE
    assert first_ledger["allowanceSeconds"] == first_decision["allowanceSeconds"] == ORIGINAL_ALLOWANCE
    assert len(first_ledger["charges"]) == 1 and first_state["decisionSHA256"] == PRIOR_RECORDS[2]["sha256"]
    assert old_state["source"] == old_decision["source"] == old_child["source"] == PREVIOUS_SOURCE
    assert old_state["status"] == old_child["status"] == "FOCUSED_FAILED"
    assert old_state["chargeCommitted"] and not old_state["cleanupErrors"] and not old_state["sourceErrors"]
    assert not old_child["cleanupErrors"] and not old_child["sourceErrors"]
    assert old_state["chargedSeconds"] == PRIOR_V2_CHARGE
    assert old_ledger["activeElapsedSeconds"] == old_state["cumulativeFocusedSeconds"] == PRIOR_NATIVE_CHARGE
    assert old_state["activeBaselineSeconds"] == first_state["cumulativeActiveSeconds"]
    assert old_state["cumulativeActiveSeconds"] == NATIVE_BASELINE
    assert old_ledger["allowanceSeconds"] == ORIGINAL_ALLOWANCE
    assert old_decision["allowanceSeconds"] == ORIGINAL_ALLOWANCE - PRIOR_V1_CHARGE
    assert len(old_ledger["charges"]) == 2 and old_ledger["charges"][:1] == first_ledger["charges"]
    assert [x["elapsedSeconds"] for x in old_ledger["charges"]] == [PRIOR_V1_CHARGE, PRIOR_V2_CHARGE]
    assert all(x in primary["focusedCharges"] for x in old_ledger["charges"])
    assert old_state["decisionSHA256"] == PRIOR_RECORDS[6]["sha256"]
    for label, passed, failed in [("FocusedMini3", 2, 1), ("FocusedAI8", 7, 1)]:
        group = old_child["groups"][label]
        assert group["resultFinalized"] and group["summary"]["passedTests"] == passed
        assert group["summary"]["failedTests"] == failed and group["summary"]["skippedTests"] == 0
    assert environment_state["source"] == environment_decision["source"] == environment_child["source"] == SOURCE
    assert environment_state["status"] == environment_child["status"] == "FOCUSED_FAILED"
    assert environment_state["chargeCommitted"] and not environment_state["sourceErrors"] and not environment_state["cleanupErrors"]
    assert not environment_state["remainingOwnedProcessGroup"] and not environment_child["groups"]
    assert not environment_child["checkpointReached"] and not environment_child["sourceErrors"] and not environment_child["cleanupErrors"]
    assert environment_state["chargedSeconds"] == PRIOR_ENV_CHARGE
    assert environment_state["activeBaselineSeconds"] == NATIVE_BASELINE
    assert environment_state["cumulativeActiveSeconds"] == ACTIVE_BASELINE
    assert environment_state["cumulativeFocusedSeconds"] == environment_ledger["activeElapsedSeconds"] == PRIOR_CHARGE
    assert environment_ledger["charges"][:2] == old_ledger["charges"] and len(environment_ledger["charges"]) == 3
    assert environment_ledger["charges"][-1]["elapsedSeconds"] == PRIOR_ENV_CHARGE
    assert all(x in primary["focusedCharges"] for x in environment_ledger["charges"])
    assert environment_state["decisionSHA256"] == PRIOR_RECORDS[10]["sha256"]
    old_ledger = environment_ledger
    assert math.isclose(PREFIX_BASELINE + PRIOR_CHARGE, ACTIVE_BASELINE, abs_tol=1e-8)
    assert PRIOR_CHARGE + d["allowanceSeconds"] == ORIGINAL_ALLOWANCE
    assert set(h.run(["git", "diff", "--name-only", PRODUCER_SOURCE, SOURCE], cwd=root).splitlines()) == set(CHANGED_SOURCES)

    def live_group(pgid):
        rows = h.run(["ps", "-axo", "pid=,pgid=,state=,command="], timeout=10).splitlines()
        return [line for line in rows if len(v := line.split(None, 3)) == 4
                and v[1] == str(pgid) and not v[2].startswith("Z")]

    terminal_rows = d["priorTerminals"]
    assert terminal_rows and PRIOR_RECORDS[0] in terminal_rows
    prior_controllers = {primary.get("controllerPID"), prefix.get("controllerPID")} - {None}
    for item in terminal_rows:
        path = h.relative(root, item["path"])
        assert path.is_relative_to(ctrl) and digest(path) == item["sha256"]
        old = json.loads(path.read_text())
        assert old["status"] not in ("STARTING", "RUNNING", "WAITING", "READY")
        assert not old.get("remainingOwnedProcessGroup", []) and not old.get("cleanupErrors", [])
        if old.get("phasePID") is not None:
            assert not live_group(old["phasePID"]), "Prior owned native process group remains"
        if old.get("controllerPID") is not None:
            prior_controllers.add(old["controllerPID"])
    process_rows = h.run(["ps", "-axo", "pid=,state=,command="], timeout=10).splitlines()
    for pid in prior_controllers:
        assert not any(len(v := line.split(None, 2)) == 3 and v[0] == str(pid)
                       and not v[1].startswith("Z") for line in process_rows), "Prior controller remains active"

    required = d["requiredFiles"]
    assert len({x["path"] for x in required}) == len(required)
    required_map = {x["path"]: x["sha256"] for x in required}
    assert set(SOURCE_PATHS + ["Scripts/CI/verify_selected_tests.py", "AI_HLY/RuntimeHostResources.zip"]) <= required_map.keys()
    for item in required:
        assert digest(h.relative(root, item["path"])) == item["sha256"], item["path"]
    assert required_map[RUNNER] == RUNNER_SHA
    assert required_map.get(RECOVERY_INPUTS) == RECOVERY_INPUTS_SHA
    recovery_path = h.relative(root, RECOVERY_INPUTS)
    recovery = json.loads(recovery_path.read_text())
    assert recovery["schema"] == 2 and recovery["source"] == SOURCE and recovery["producerSource"] == PRODUCER_SOURCE
    assert recovery["priorConsumerSource"] == PREVIOUS_SOURCE
    for key, item in [("priorTerminal", PRIOR_RECORDS[4]), ("priorChild", PRIOR_RECORDS[7])]:
        assert h.relative(root, recovery[key]["path"]) == h.relative(root, item["path"])
        assert recovery[key]["sha256"] == item["sha256"]
    mini_proof = h.relative(root, recovery["miniProductObservation"]["path"])
    assert mini_proof.is_relative_to(ctrl)
    assert required_map.get(mini_proof.relative_to(root).as_posix()) == recovery["miniProductObservation"]["sha256"]
    reuse = json.loads(mini_proof.read_text())
    assert reuse["source"] == PRODUCER_SOURCE
    assert reuse["originalMiniBuildCommand"]["exit"] == 0 and reuse["originalMiniBuildCommand"]["completion_recorded"]
    assert len(reuse["files"]) == 5697 and not reuse["symlinks"]
    assert not any(x["modifiedAfterBuildTerminal"] for x in reuse["files"])
    original_ownership = h.relative(root, reuse["ownership"]["path"])
    assert original_ownership == ctrl / "focused19-v1/native-result/paired-prefix/created-simulator.txt"
    assert digest(original_ownership) == reuse["ownership"]["sha256"]
    assert str(uuid.UUID(original_ownership.read_text().strip())).upper() == str(uuid.UUID(reuse["ownership"]["device"])).upper()
    for name in SOURCE_PATHS:
        assert hashlib.sha256(subprocess.check_output(["git", "show", SOURCE + ":" + name], cwd=root)).hexdigest() == required_map[name]
    sdk_path = h.relative(root, d["sdk"]["manifestPath"])
    assert digest(sdk_path) == d["sdk"]["manifestSHA256"]
    sdk = json.loads(sdk_path.read_text())
    assert sdk["inputSHA256"] == d["sdk"]["inputSHA256"]
    assert len(sdk["sourceInputs"]) == d["sdk"]["sourceInputCount"] == 235
    assert not set(CHANGED_SOURCES + MUTABLE_FIXTURES) & {x["path"] for x in sdk["sourceInputs"]}
    assert d["sdk"]["inputSHA256"] == "ba8f3f1f09054887eed62532fa1d5ca2ac3bd60e6aa99a98ab1035c7653882a2"
    assert d["sdk"]["manifestSHA256"] == "4505c28495d8b6ecd1073254e0e395adcc898cc02dd1d40699591f51db4dee92"
    assert d["sdk"]["archiveSHA256"] == "7a426675109c5ebc4c8b5824565547f8aea10584785932280fdb623128530ecc"
    assert len({x["path"] for x in sdk["sourceInputs"]}) == len(sdk["sourceInputs"])
    for row in sdk["sourceInputs"]:
        assert required_map.get(row["path"]) == row["sha256"], row["path"]
    assert digest(root / "AI_HLY/RuntimeHostResources.zip") == d["sdk"]["archiveSHA256"]
    assert required_map["AI_HLY/RuntimeHostResources.zip"] == d["sdk"]["archiveSHA256"]
    preserved = d["preservedLedgers"]
    assert preserved and len({x["path"] for x in preserved}) == len(preserved)
    for item in preserved:
        assert digest(h.relative(root, item["path"])) == item["sha256"], item["path"]
    assert d["resourceAssessment"]["decision"] == "FITS_MEASURED_NEXT_PHASE"
    disk = h.run(["df", "-k", "/System/Volumes/Data"])
    free = int(disk.splitlines()[-1].split()[3]) * 1024
    assert free >= d["resourceAssessment"]["estimatedIncrementalBytes"] + d["resourceAssessment"]["concurrentAndOSAllowanceBytes"]

    out.mkdir()
    # The child exclusively creates native-result and its original paired-prefix.
    frozen = out / "decision.json"
    frozen.write_bytes(decision_bytes)
    (out / "primary-state-before.json").write_bytes(primary_bytes)
    (out / "prefix-state-before.json").write_bytes(prefix_bytes)
    (out / "prior-focused-ledger.json").write_bytes(h.relative(root, PRIOR_RECORDS[9]["path"]).read_bytes())
    state_path, events = out / "state.json", out / "events.jsonl"
    baseline, allowance = d["activeBaselineSeconds"], d["allowanceSeconds"]
    state = {"schema": 1, "id": ID, "owner": d["owner"], "source": SOURCE, "sourceTree": TREE,
             "status": "STARTING", "expectedGroups": GROUPS, "expectedTotal": 2,
             "producerSource": PRODUCER_SOURCE, "originalFocusedAllowanceSeconds": ORIGINAL_ALLOWANCE,
             "priorFocusedChargeSeconds": PRIOR_CHARGE, "priorFocusRecords": PRIOR_RECORDS,
             "controllerPID": os.getpid(), "activeBaselineSeconds": baseline,
             "allowanceSeconds": allowance, "decisionSHA256": hashlib.sha256(decision_bytes).hexdigest(),
             "original52": "UNCHANGED_BY_FOCUSED_RUN", "nativeResult": "NOT_RUN",
             "resourceObservationAtLaunch": {"observedAt": h.utc(), "freeBytes": free, "df": disk}}
    def checkpoint(event, **fields):
        state.update(fields)
        h.write(state_path, state)
        with events.open("a") as stream:
            stream.write(json.dumps({"at": h.utc(), "event": event, **fields}) + "\n")
            stream.flush()
            os.fsync(stream.fileno())
    env = dict(os.environ)
    original_node = d["originalNode"]
    node_path = Path(original_node["path"]).resolve(strict=True)
    assert node_path.is_file() and digest(node_path) == original_node["sha256"]
    installed_inputs = []
    for engine in ["Expo", "NativeScript"]:
        receipt = json.loads((root / "Scripts" / engine / "node_modules/.hanlin-miniapp-install.json").read_text())
        installed_inputs.append(receipt["inputs"])
    node_identity = json.loads(h.run([str(node_path), "-p",
        "JSON.stringify({node:process.versions.node,platform:process.platform,architecture:process.arch})"]))
    assert all(all(node_identity[k] == inputs[k] for k in node_identity) for inputs in installed_inputs)
    assert node_identity["node"] == original_node["version"] == "24.5.0"
    state["originalNode"] = {**original_node, "observedIdentity": node_identity}
    env.update(PATH=str(node_path.parent) + ":/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
               DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer",
               GITHUB_WORKSPACE=str(root), GITHUB_SHA=SOURCE, SPLIT_EVIDENCE=str(child_out),
               SPLIT_DERIVED_DATA=d["derivedData"], PAIRED_TEST_SCOPE="miniapp_complete",
               RUNNER_TEMP=str(root / "build/primary-temp"))
    argv = [sys.executable, str(child_path), "--source", SOURCE, "--output", str(child_out)]
    log = out / "controller-child.log"
    process, exit_code, error = None, None, None
    start = time.monotonic()
    checkpoint("prepared", startedAt=h.utc(), argv=argv)
    running = dict(primary)
    running.update(status="RUNNING", controllerPID=os.getpid(), phase=ID)
    h.write(primary_path, running)
    h.write(out / "ledger.json", {"schema": 1, "id": ID, "allowanceSeconds": allowance,
                                 "activeElapsedSeconds": 0, "charges": [], "otherGrantsUnchanged": True})
    def interrupted(signum, frame):
        raise InterruptedError("Focused19 received signal " + str(signum))
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        with log.open("xb") as stream:
            process = subprocess.Popen(argv, cwd=root, env=env, stdout=stream,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            checkpoint("launched", status="RUNNING", phasePID=process.pid, nativeResult="RUNNING")
            while True:
                remaining = allowance - (time.monotonic() - start)
                if remaining <= 0:
                    raise TimeoutError("Separate focused19 3600-second allowance elapsed")
                try:
                    exit_code = process.wait(timeout=min(30, remaining))
                    break
                except subprocess.TimeoutExpired:
                    checkpoint("heartbeat", elapsedSeconds=time.monotonic() - start, logBytes=log.stat().st_size)
        result_path = child_out / "state.json"
        result = json.loads(result_path.read_text())
        assert exit_code == 0 and result["status"] == "FOCUSED_PASS"
        assert ownership.is_file() and not ownership.is_symlink()
        owned_device = str(uuid.UUID(ownership.read_text().strip())).upper()
        assert owned_device == str(uuid.UUID(result["simulator"])).upper()
        assert result["source"] == SOURCE and result["tree"] == TREE and result["original52"] == "NOT_RUN"
        assert result["originalTestBuilds"] == "PASS_WITH_AUTHENTICATED_MINI_REUSE"
        assert result["miniBuildProducerSource"] == PRODUCER_SOURCE
        assert result["recoveryInputSHA256"] == RECOVERY_INPUTS_SHA
        assert owned_device == str(uuid.UUID(reuse["ownership"]["device"])).upper()
        assert result["reusedSetup"] == [
            {"status": "REUSED_AUTHENTICATED_OWNED_DEVICE", "authority": reuse["ownership"]},
            {"status": "REUSED_EXECUTED_PASS", "authority": recovery["miniProductObservation"], "producerSource": PRODUCER_SOURCE}]
        assert {("/pixel.png", 200), ("/missing.png", 404)} <= {
            (x["path"], x["status"]) for x in result["nativeAdapterRequests"]}
        assert result["selectors"] == {k: v["selectors"] for k, v in GROUPS.items()}
        assert set(result["groups"]) == set(GROUPS)
        assert not result["sourceErrors"] and not result["cleanupErrors"] and not result["errors"]
        for label, expected in GROUPS.items():
            group = result["groups"][label]
            assert group["status"] == "PASS" and group["exitCode"] == 0 and group["resultFinalized"] is True
            assert group["selectors"] == expected["selectors"]
            summary = group["summary"]
            assert summary["totalTestCount"] == summary["passedTests"] == expected["expected"]
            assert summary["failedTests"] == summary["skippedTests"] == 0
        bindings = result["builtInputBindings"]
        product_receipt = Path(bindings["path"]).resolve()
        assert product_receipt == child_out / "built-input-bindings.json"
        assert digest(product_receipt) == bindings["sha256"]
        built = json.loads(product_receipt.read_text())
        assert built["source"] == built["aiBuildProducerSource"] == SOURCE
        assert built["miniBuildProducerSource"] == PRODUCER_SOURCE
        assert built["authenticatedMiniReuse"] == recovery["miniProductObservation"]
        assert result["hostArchiveSHA256"] == d["sdk"]["archiveSHA256"]
        checkpoint("actual_terminal", status="FOCUSED_PASS", nativeResult="EXECUTED_PASS",
                   exitCode=exit_code, childStateSHA256=digest(result_path),
                   builtInputBindingsSHA256=bindings["sha256"], groups=result["groups"])
    except BaseException as failure:
        error = type(failure).__name__ + ": " + str(failure)
        checkpoint("actual_terminal", status="TIMED_OUT" if isinstance(failure, TimeoutError) else "FOCUSED_FAILED",
                   nativeResult="FAILED_OR_INCOMPLETE", error=error, exitCode=exit_code)
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        cleanup = []
        if process is not None:
            try:
                members = live_group(process.pid)
                state["ownedProcessGroupAtCleanup"] = members
                for sig, seconds in [(signal.SIGTERM, 20), (signal.SIGKILL, 10)]:
                    if not members:
                        break
                    try:
                        os.killpg(process.pid, sig)
                    except ProcessLookupError:
                        pass
                    until = time.monotonic() + seconds
                    while members and time.monotonic() < until:
                        if process.poll() is None:
                            try:
                                process.wait(timeout=1)
                            except subprocess.TimeoutExpired:
                                pass
                        else:
                            time.sleep(0.25)
                        members = live_group(process.pid)
                process.wait(timeout=5)
                state["remainingOwnedProcessGroup"] = members
                state["observedPhaseExitCode"] = process.returncode
                if members:
                    cleanup.append("Owned phase group survived bounded TERM/KILL")
            except Exception as failure:
                cleanup.append("Owned phase cleanup: " + str(failure))
        try:
            if ownership.exists():
                # No guessed or previously owned device is ever substituted here.
                assert ownership.is_file() and not ownership.is_symlink()
                device = str(uuid.UUID(ownership.read_text().strip())).upper()
                result = subprocess.run(["xcrun", "simctl", "shutdown", device], capture_output=True,
                                        text=True, timeout=30, env=env)
                devices = json.loads(h.run(["xcrun", "simctl", "list", "devices", "-j"], env=env, timeout=15))
                found = [x for values in devices["devices"].values() for x in values if x["udid"].upper() == device]
                observed = found[0]["state"] if len(found) == 1 else "UNKNOWN"
                state["ownedSimulatorCleanup"] = {"device": device, "ownership": str(ownership),
                    "ownershipSHA256": digest(ownership), "exitCode": result.returncode,
                    "stdout": result.stdout, "stderr": result.stderr, "observedState": observed, "observedAt": h.utc()}
                if observed != "Shutdown":
                    cleanup.append("New owned simulator not confirmed Shutdown")
            else:
                state["ownedSimulatorCleanup"] = {"status": "NO_CHILD_OWNERSHIP_FILE", "ownership": str(ownership)}
        except Exception as failure:
            cleanup.append("Owned simulator cleanup: " + str(failure))
        state["cleanupErrors"] = cleanup
        if cleanup:
            state["status"] = "CLEANUP_INCOMPLETE"
        drift = []
        try:
            if h.run(["git", "rev-parse", "HEAD"], cwd=root) != SOURCE:
                drift.append("Git HEAD changed")
            replacements = {}
            producer_path = child_out / "fixture-production.json"
            if producer_path.is_file():
                producer = json.loads(producer_path.read_text())
                child_contract = module(child_path, "bound_focused_fixture_contract")
                assert producer["source"] == SOURCE and producer["SDKProducerSource"] == PRODUCER_SOURCE
                assert producer["producer"] == {"path": "Scripts/Expo/build-probe.mjs",
                    "sha256": required_map["Scripts/Expo/build-probe.mjs"]}
                assert producer["exitCode"] == 0 and producer["argv"] == ["node", "Scripts/Expo/build-probe.mjs"]
                assert producer["mutableRequiredFiles"] == MUTABLE_FIXTURES
                assert producer["declaredOutputs"] == child_contract.FIXTURE_OUTPUTS
                before = {row["path"]: row for row in producer["before"]}
                after = {row["path"]: row for row in producer["after"]}
                assert len(before) == len(after) == len(child_contract.FIXTURE_OUTPUTS)
                assert set(before) == set(after) == set(child_contract.FIXTURE_OUTPUTS)
                log_path = Path(producer["log"]["path"]).resolve()
                assert log_path == child_out / "paired-prefix/original-expo-probe.log"
                assert digest(log_path) == producer["log"]["sha256"]
                commands = [json.loads(line) for line in
                    (child_out / "paired-prefix/commands.jsonl").read_text().splitlines() if line]
                actual = [row for row in commands if row.get("log") == "original-expo-probe.log"]
                assert len(actual) == 1 and actual[0]["exit"] == 0 and actual[0]["argv"] == producer["argv"]
                assert actual[0]["sha256"] == producer["log"]["sha256"]
                fixture_command_events = [json.loads(line) for line in
                    (child_out / "paired-prefix/command-events.jsonl").read_text().splitlines() if line]
                completed = [row for row in fixture_command_events if row.get("log") == "original-expo-probe.log"
                             and row.get("completion_recorded")]
                assert len(completed) == 1 and completed[0]["exit"] == 0
                assert completed[0]["status"] == "completed" and completed[0]["argv"] == producer["argv"]
                for name, row in after.items():
                    path = h.relative(root, name)
                    assert path.stat().st_size == row["bytes"] and digest(path) == row["sha256"]
                    if name in MUTABLE_FIXTURES:
                        assert before[name]["sha256"] == required_map[name]
                        replacements[name] = row["sha256"]
                    elif name != "AI_HLYTests/Fixtures/HostServicesProbe.bundle/ExpoSwiftUIProbeA.hanlinExpo":
                        assert row["sha256"] == before[name]["sha256"]
                assert set(replacements) == set(MUTABLE_FIXTURES)
                state["verifiedOriginalFixtureProduction"] = {
                    "path": str(producer_path), "sha256": digest(producer_path),
                    "before": producer["before"], "after": producer["after"],
                    "requiredFileReplacements": replacements}
            for item in required:
                expected = replacements.get(item["path"], item["sha256"])
                if digest(h.relative(root, item["path"])) != expected:
                    drift.append("Canonical source/SDK input changed: " + item["path"])
            if digest(child_path) != CHILD_SHA or digest(helper_path) != HELPER_SHA:
                drift.append("Bound execution code changed")
            if digest(sdk_path) != d["sdk"]["manifestSHA256"]:
                drift.append("Prepared SDK manifest changed")
            for item in preserved + terminal_rows + [d["prefix"]] + PRIOR_RECORDS:
                if digest(h.relative(root, item["path"])) != item["sha256"]:
                    drift.append("Historical receipt/ledger changed: " + item["path"])
        except Exception as failure:
            drift.append("Final input observation: " + str(failure))
        state["sourceErrors"] = drift
        if drift:
            state["status"] = "INPUT_DRIFT"
        elapsed = time.monotonic() - start
        checkpoint("charge_ready", finishedAt=h.utc(), elapsedSeconds=elapsed, chargedSeconds=elapsed,
                   cumulativeActiveSeconds=baseline + elapsed,
                   cumulativeFocusedSeconds=PRIOR_CHARGE + elapsed,
                   allowanceExceededDuringCleanup=elapsed > allowance,
                   logBytes=log.stat().st_size if log.exists() else 0,
                   logSHA256=digest(log) if log.exists() else None)
        try:
            current = json.loads(primary_path.read_text())
            assert current["activeElapsedSeconds"] == baseline and current.get("controllerPID") == os.getpid()
            charge = {"id": ID, "source": SOURCE, "status": state["status"], "elapsedSeconds": elapsed,
                      "statePath": str(state_path), "decisionSHA256": state["decisionSHA256"],
                      "logSHA256": state["logSHA256"], "exitCode": exit_code,
                      "expectedGroups": {"FocusedManual1": 1, "FocusedRepair1": 1}}
            h.write(out / "ledger.json", {"schema": 1, "id": ID, "allowanceSeconds": ORIGINAL_ALLOWANCE,
                                         "continuationAllowanceSeconds": allowance,
                                         "continuationElapsedSeconds": elapsed,
                                         "activeElapsedSeconds": PRIOR_CHARGE + elapsed,
                                         "charges": old_ledger["charges"] + [charge],
                                         "originalLedger": PRIOR_RECORDS[9], "otherGrantsUnchanged": True})
            current["activeElapsedSeconds"] = baseline + elapsed
            current.setdefault("focusedCharges", []).append(charge)
            current.update(status=primary["status"], phase=primary.get("phase"),
                           controllerPID=None, finishedAt=state["finishedAt"])
            # Original52, earlier acceptance and all separate grants are preserved.
            h.write(primary_path, current)
            state["chargeCommitted"] = True
            state["focusedLedgerSHA256"] = digest(out / "ledger.json")
        except Exception as failure:
            state.update(status="LEDGER_RECONCILIATION_REQUIRED", ledgerError=str(failure),
                         uncommittedOrPartiallyCommittedChargeSeconds=elapsed)
        checkpoint("finalized", status=state["status"])
    return 0 if state["status"] == "FOCUSED_PASS" else 1

if __name__ == "__main__":
    raise SystemExit(main())
