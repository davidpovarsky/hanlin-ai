"""Run only the original eleven MCP wire tests through the existing AgentSDK CI route."""
import collections, datetime, fcntl, hashlib, json, os, pathlib, re, signal, subprocess, sys, tempfile, time, traceback

REVIEWED_SOURCE = "f57dfcc2292c0830f454e28d87293e85fe426a44"
COMMAND = ['/usr/bin/swift', 'test', '--package-path', 'Packages/HanlinAgentSDK', '--filter', 'HostMCPWireComparisonTests', '--jobs', '2']
ORIGINAL_PHASE_SECONDS = 3600
EXPECTED_METHODS = ['largeOriginalUTF8SurvivesOrderAndEscapeProjection', 'largeOriginalUTF8RejectsAMutationAtTheTextTail', 'metadataIsPartOfTheExactWireValue', 'exactDecimalsAndJSONKindsSurviveWithoutBinary64Rounding', 'scalarKeysAndStringsDoNotUseSwiftCanonicalEquivalence', 'strictSyntaxAndDuplicateDecodedKeysStillFail', 'depthKeyAndNumericLimitsRemainTheOriginalPolicy', 'cancellationProducesNoComparisonVerdict', 'existingSchemaConsentAndProjectionAdmissionRemainBounded', 'finitePoliciesChangeOnlyTheirDeclaredByteAndWorkMetrics', 'checkedPolicyArithmeticRejectsUnrepresentableBudgetsWithoutAllocation']
EXPECTED_PACKAGE_TREES = {'Packages/HanlinAgentSDK': '40d655a4afe6469ca00c44675725fad2dcd53202', 'Packages/HanlinAgentSDK/Sources': 'deb8dc91c2de361423ee3e02b928cdf020c1ef4f', 'Packages/HanlinAgentSDK/Tests': 'ee4195fa52d0e937660cec16a7cafc6d5ce41181', 'Packages/HanlinPlatform': 'b1e54c6d1aa3c4ef2dd761e15b7b6df9d946a29a', 'Packages/HanlinPlatform/Sources': '182cad448c545daa956db88dc251e318022e748a', 'Packages/HanlinPlatform/Tests': '72b192559666a54e970578985f1ef091d87090d7'}
EXPECTED_SOURCE_AND_PINS = {'Packages/HanlinAgentSDK/Sources/HanlinAgentCore/HanlinHostSchemaValidation.swift': '622c7380bb066002a48bb46e6c76a6f919c41060392d891ac17c34f411b1a040', 'Packages/HanlinAgentSDK/Tests/HanlinAgentCoreTests/HostMCPWireComparisonTests.swift': 'bbcae5565bdcbc7eba72c7d5c272eac5227af9106f00c50589901013f22830c7', 'AI_HLY/Downstream/MCP/Runtime/MCPClientSession.swift': '3b331e200237598147def7fed0875b3b5ae62a5581ba85da09a4d6c4b058fc13', 'Packages/HanlinAgentSDK/Package.resolved': '543da4b8e9fe589c8d071fa3599d30034cb39bd57e839ba6130f754cdad701ca', 'Packages/HanlinPlatform/Package.resolved': '453087cb3345b7c6bb24c00a682f41ffa9708ebd328e60b583f6e04276bf789d', 'AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved': '56d19a4b8c677831fb91e1f8155a68e411b42fd4807ad618d6f169569e1bb5a4'}
COLD_CAPACITY_COMPONENTS = {'retainedFullPlatformBuildBaselineBytes': 2297167872, 'newAgentSDKAndSwiftAICodegenAllowanceBytes': 2147483648, 'pinnedSwiftAICheckoutWorkingAllowanceBytes': 36451492, 'otherPinnedCheckoutWorkingAllowanceBytes': 268435456, 'sharedHostGrowthAllowanceBytes': 1073741824, 'osReserveBytes': 750000000}
known_owned = {}

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()

def free():
    fs = os.statvfs(ROOT)
    return fs.f_bavail * fs.f_frsize

def git(*args):
    return subprocess.check_output(['/usr/bin/git', '-C', str(ROOT), *args], text=True, timeout=30).strip()

def save():
    temporary = RECEIPT.with_suffix('.pending')
    temporary.write_text(json.dumps(data, indent=2) + '\n')
    temporary.replace(RECEIPT)

def process_snapshot():
    result = subprocess.run(['/bin/ps', '-axo', 'pid=,ppid=,pgid=,stat=,lstart=,comm='],
                            capture_output=True, text=True, timeout=10, check=True)
    rows = []
    for line in result.stdout.splitlines():
        fields = line.strip().split(None, 9)
        if len(fields) != 10:
            continue
        rows.append({'pid': int(fields[0]), 'ppid': int(fields[1]), 'pgid': int(fields[2]),
                     'state': fields[3], 'processStarted': ' '.join(fields[4:9]),
                     'executable': fields[9]})
    return rows

def process_identity(row):
    return row['processStarted'], row['executable']

def scoped_ps_query(arguments, deadline, identities):
    """Use the remaining shared 10-second budget; never silently omit a row."""
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise subprocess.TimeoutExpired("owned process snapshot", 10)
    try:
        result = subprocess.run(arguments, capture_output=True, text=True,
                                timeout=remaining, check=False)
    except subprocess.TimeoutExpired as error:
        failures = data.setdefault("failedScopedProcessQueries", [])
        failure = {"at": now(), "argv": arguments, "deadlineSeconds": 10,
                   "error": repr(error)}
        failures.append(failure)
        data["failedScopedProcessQuery"] = failure
        for field, value in [("stdout", error.stdout), ("stderr", error.stderr)]:
            if value:
                path = EVIDENCE / ("failed-scoped-process-query-%03d." % len(failures) + field)
                assert not path.exists(), "Preserve the original query failure evidence"
                path.write_bytes(value if isinstance(value, bytes) else value.encode())
                failure[field] = {
                    "path": str(path), "bytes": path.stat().st_size, "sha256": digest(path)}
        save()
        raise
    if result.returncode != 0:
        # ps reports 1 when every explicitly selected PID has already exited.
        if not (identities and result.returncode == 1
                and not result.stdout.strip() and not result.stderr.strip()):
            raise subprocess.CalledProcessError(result.returncode, arguments,
                                                result.stdout, result.stderr)
    rows = {}
    for line in result.stdout.splitlines():
        if not line.strip():
            continue
        fields = line.strip().split(None, 9 if identities else 8)
        if len(fields) != (10 if identities else 9):
            raise RuntimeError("Unparseable mandatory process snapshot row")
        row = {"pid": int(fields[0]), "ppid": int(fields[1]), "pgid": int(fields[2]),
               "state": fields[3], "processStarted": " ".join(fields[4:9]),
               "executable": fields[9] if identities else None}
        if row["pid"] in rows:
            raise RuntimeError("Duplicate process ID in mandatory snapshot")
        rows[row["pid"]] = row
    return rows

def process_topology(deadline):
    return scoped_ps_query(
        ["/bin/ps", "-axo", "pid=,ppid=,pgid=,stat=,lstart="], deadline, False)

def process_descendants(parent_pid, rows):
    ids = {parent_pid}
    while True:
        added = {row["pid"] for row in rows.values() if row["ppid"] in ids} - ids
        if not added:
            return ids.intersection(rows)
        ids.update(added)

def owned_process_snapshot(parent_pid):
    """Complete topology plus only owned executable identities, within 10s total."""
    began = time.monotonic()
    deadline = began + 10
    rows = process_topology(deadline)
    rounds = 0
    while True:
        if time.monotonic() >= deadline:
            raise subprocess.TimeoutExpired("owned process snapshot", 10)
        root = rows.get(parent_pid)
        if root is not None:
            if root["ppid"] != os.getpid() or root["pgid"] != parent_pid:
                raise RuntimeError("Original start_new_session root ownership changed")
            previous = known_owned.get(parent_pid)
            if previous and previous[0] != root["processStarted"]:
                raise RuntimeError("Original owned root PID was recycled")
        descendants = process_descendants(parent_pid, rows)
        retained = {pid for pid, identity in known_owned.items()
                    if pid in rows and rows[pid]["processStarted"] == identity[0]}
        candidates = descendants | retained
        exact = scoped_ps_query(
            ["/bin/ps", "-p", ",".join(map(str, sorted(candidates))),
             "-o", "pid=,ppid=,pgid=,stat=,lstart=,comm="],
            deadline, True) if candidates else {}
        if not set(exact).issubset(candidates):
            raise RuntimeError("Scoped process query returned an unrequested PID")
        same_record = lambda first, second: all(
            first[key] == second[key] for key in ("pid", "ppid", "pgid", "processStarted"))
        # Preserve an actually observed descendant even if it reparents or starts
        # a separate group before the following mandatory topology observation.
        for pid, row in exact.items():
            if pid in descendants and same_record(rows[pid], row):
                known_owned[pid] = process_identity(row)
        fresh = process_topology(deadline)
        fresh_descendants = process_descendants(parent_pid, fresh)
        fresh_retained = {pid for pid, identity in known_owned.items()
                          if pid in fresh and fresh[pid]["processStarted"] == identity[0]}
        fresh_candidates = fresh_descendants | fresh_retained
        rounds += 1
        if time.monotonic() >= deadline:
            raise subprocess.TimeoutExpired("owned process snapshot", 10)
        if all(pid in rows and pid in exact
               and same_record(rows[pid], exact[pid])
               and same_record(exact[pid], fresh[pid])
               for pid in fresh_candidates):
            for pid in fresh_candidates:
                fresh[pid]["executable"] = exact[pid]["executable"]
            data["latestScopedProcessSnapshot"] = {
                "at": now(), "deadlineSeconds": 10,
                "elapsedSeconds": time.monotonic() - began, "rounds": rounds,
                "completeTopologyRows": len(fresh),
                "scopedExecutableRows": len(fresh_candidates),
                "unknownForeignExecutablesRetainedAsUnowned": True}
            return list(fresh.values())
        # A child appeared, exited, reparented or changed group during observation.
        # Reconcile against the newest complete topology within the SAME deadline.
        rows = fresh

def owned_tree(parent_pid, rows=None):
    rows = owned_process_snapshot(parent_pid) if rows is None else rows
    ids = {parent_pid}
    while True:
        added = {row['pid'] for row in rows if row['ppid'] in ids} - ids
        if not added:
            break
        ids.update(added)
    owned = [row for row in rows if row['pid'] in ids]
    for row in owned:
        known_owned[row['pid']] = process_identity(row)
    return owned

def stop_owned_processes(process, reason):
    data['stopReason'] = reason
    data['stopRequestedAt'] = now()
    data['stopProcessTree'] = owned_tree(process.pid)
    data['stopSignals'] = []
    save()
    # SwiftPM may create separate child groups. Retain observed identities and
    # address only the same owned processes, including any just-reparented child.
    for sig, grace in [(signal.SIGINT, 3), (signal.SIGTERM, 3), (signal.SIGKILL, 3)]:
        rows = owned_process_snapshot(process.pid)
        if process.poll() is None:
            owned_tree(process.pid, rows)
        owned = [row for row in rows if known_owned.get(row['pid']) == process_identity(row)]
        owned_ids = {row['pid'] for row in owned}
        if not owned:
            break
        groups = {row['pgid'] for row in owned if row['pgid'] > 1 and row['pgid'] != os.getpgrp()}
        group_members = {group: [row for row in rows if row['pgid'] == group] for group in groups}
        exclusive_groups = {group for group, members in group_members.items()
                            if members and all(row['pid'] in owned_ids for row in members)}
        for group in sorted(exclusive_groups):
            try:
                os.killpg(group, sig)
                data['stopSignals'].append({'signal': sig.name, 'ownedPGID': group})
            except ProcessLookupError:
                pass
        for row in owned:
            if row['pgid'] in exclusive_groups:
                continue
            try:
                # A shared group is never signalled: only its verified owned PID.
                os.kill(row['pid'], sig)
                data['stopSignals'].append({'signal': sig.name, 'ownedPID': row['pid']})
            except ProcessLookupError:
                pass
        save()
        until = time.monotonic() + grace
        while time.monotonic() < until:
            process.poll()
            time.sleep(0.25)
    data['ownedProcessesAfterStop'] = [row for row in owned_process_snapshot(process.pid)
                                      if known_owned.get(row['pid']) == process_identity(row)]
    save()

def run_prepared_original_gate():
    native=open(LOCKS/"hanlin-two-wave-native-app.lock","a+")
    maintenance=open(LOCKS/".scaleway-cache-maintenance.lock","a+")
    process=None
    log_path=EVIDENCE/"original-swift-test.log"
    try:
        fcntl.flock(native,fcntl.LOCK_EX|fcntl.LOCK_NB)
        fcntl.flock(maintenance,fcntl.LOCK_SH|fcntl.LOCK_NB)
        data["coordinationLocks"]={"native":"exclusive","maintenance":"shared"}
        assert git("rev-parse","HEAD")==SOURCE and not git("status","--porcelain=v1")
        for rel,sha in BINDING["packageTrees"].items():
            assert git("rev-parse","HEAD:"+rel)==sha
        for rel,sha in BINDING["sourceAndPinHashes"].items():
            assert digest(ROOT/rel)==sha,rel
        test_path=ROOT/"Packages/HanlinAgentSDK/Tests/HanlinAgentCoreTests/HostMCPWireComparisonTests.swift"
        test_text=test_path.read_text()
        assert digest(test_path)=="bbcae5565bdcbc7eba72c7d5c272eac5227af9106f00c50589901013f22830c7"
        actual_names=re.findall(r"@Test[\s\S]*?func\s+([A-Za-z_0-9]+)\(",test_text)
        assert actual_names==EXPECTED_METHODS and test_text.count("@Test(.timeLimit(.minutes(2)))")==2
        assert "@Suite(.serialized)" in test_text
        data["sourceBefore"]={"head":SOURCE,"packageTrees":BINDING["packageTrees"],"sourceAndPinHashes":BINDING["sourceAndPinHashes"]}
        data["admission"]=BINDING["capacity"]
        data["freeBeforeCommand"]=free()
        assert free()>=BINDING["capacity"]["requiredBytes"],data["admission"]
        before=process_snapshot()
        data["initialProcessSnapshotCount"]=len(before)
        data["toolchain"]={}
        for name,args in [("swift",["/usr/bin/swift","--version"]),("xcode",["/usr/bin/xcodebuild","-version"])]:
            result=subprocess.run(args,cwd=ROOT,capture_output=True,text=True,timeout=15,check=True)
            data["toolchain"][name]=result.stdout.strip()
        env=os.environ.copy()
        assert not env.get("SWIFT_EXEC") and not env.get("SWIFTPM_BUILD_DIR")
        data["commandStartedAt"]=now()
        save()
        with log_path.open("w") as log_stream:
            process=subprocess.Popen(COMMAND,cwd=ROOT,env=env,stdout=log_stream,stderr=subprocess.STDOUT,start_new_session=True)
            data["pid"]=process.pid;data["pgid"]=os.getpgid(process.pid);data["nativeCommandsStarted"]=1
            data["status"]="RUNNING_FOCUSED_ORIGINAL_MCP_WIRE_TESTS"
            save()
            began=time.monotonic();next_snapshot=0.0
            while process.poll() is None:
                elapsed=time.monotonic()-began
                if elapsed>=next_snapshot:
                    owned=owned_tree(process.pid)
                    data["latestOwnedProcesses"]=[{k:r[k] for k in ("pid","ppid","pgid","state","executable")} for r in owned]
                    next_snapshot=elapsed+10
                available=free()
                data["latestProgress"]={"at":now(),"elapsedSeconds":elapsed,"freeBytes":available,"logBytes":log_path.stat().st_size}
                save()
                if available<BINDING["capacity"]["reserveBytes"]:
                    stop_owned_processes(process,"MEASURED_DISK_RESERVE_REACHED");break
                if elapsed>ORIGINAL_PHASE_SECONDS:
                    stop_owned_processes(process,"ORIGINAL_3600_SECOND_SWIFT_PHASE_DEADLINE");break
                time.sleep(2)
            data["exitCode"]=process.wait(timeout=10)
        final_text=log_path.read_text(errors="replace")
        starts=collections.Counter(re.findall(r"^.*?\bTest (.+?) started\.$",final_text,re.MULTILINE))
        terminal_rows=re.findall(r"^.*?\bTest (.+?) (passed|failed|skipped) after ",final_text,re.MULTILINE)
        terminals=collections.Counter(name for name,state in terminal_rows)
        normalize=lambda name:name[:-2] if name.endswith("()") else name
        names_started=collections.Counter({normalize(k):v for k,v in starts.items()})
        names_ended=collections.Counter({normalize(k):v for k,v in terminals.items()})
        expected=collections.Counter(EXPECTED_METHODS)
        states=dict(collections.Counter(state for _,state in terminal_rows))
        summaries=re.findall(r"Test run with (\d+) tests?[^\n]*(passed|failed)[^\n]*",final_text)
        data["reconciliation"]={"starts":dict(starts),"terminals":dict(terminals),"states":states,
           "expectedMethodNames":EXPECTED_METHODS,"namesExactlyMatch":names_started==names_ended==expected,
           "methodStarts":sum(starts.values()),"methodTerminals":sum(terminals.values()),
           "summaryRows":summaries,"reportedPassedCount":sum(int(n) for n,state in summaries if state=="passed"),
           "skippedLogLines":[l for l in final_text.splitlines() if " skipped " in l and ("Test " in l or "Suite " in l)]}
        source_unchanged=(git("rev-parse","HEAD")==SOURCE and not git("status","--porcelain=v1")
            and all(git("rev-parse","HEAD:"+p)==sha for p,sha in BINDING["packageTrees"].items())
            and all(digest(ROOT/p)==sha for p,sha in BINDING["sourceAndPinHashes"].items()))
        data["sourceUnchanged"]=source_unchanged
        assert source_unchanged,"Source or pinned package inputs changed during focused gate"
        passed=(not data.get("stopReason") and data["exitCode"]==0 and names_started==names_ended==expected
            and states=={"passed":11} and data["reconciliation"]["reportedPassedCount"]==11
            and not data["reconciliation"]["skippedLogLines"] and not any(state=="failed" for _,state in summaries))
        data["focused11Passed"]=passed
        data["status"]=("FOCUSED_ORIGINAL_MCP_WIRE_STOPPED" if data.get("stopReason")
            else "FOCUSED_ORIGINAL_MCP_WIRE_11_PASSED" if passed else "FOCUSED_ORIGINAL_MCP_WIRE_FAILED")
    except BaseException as error:
        if process is not None and process.poll() is None:
            stop_owned_processes(process,"FOCUSED_GATE_CONTROLLER_EXCEPTION")
        data.update(status="FOCUSED_GATE_CONTROLLER_FAILED",error=repr(error),traceback=traceback.format_exc())
    finally:
        data["finishedAt"]=now();data["freeEnd"]=free()
        if log_path.is_file():data["log"]={"path":str(log_path),"bytes":log_path.stat().st_size,"sha256":digest(log_path)}
        save()
        fcntl.flock(maintenance,fcntl.LOCK_UN);fcntl.flock(native,fcntl.LOCK_UN)
        print(json.dumps({k:data.get(k) for k in ("status","source","pid","exitCode","stopReason","focused11Passed","error","finishedAt","freeEnd","log")}),flush=True)
    if data.get("status")!="FOCUSED_ORIGINAL_MCP_WIRE_11_PASSED":raise SystemExit(1)


def main():
    global ROOT, STAGE, EVIDENCE, RECEIPT, BINDING_PATH, BINDING, SOURCE, data, LOCKS
    ROOT = pathlib.Path(subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"], text=True, timeout=10).strip()).resolve()
    STAGE = ROOT / "build/agent-sdk-validation-evidence"
    STAGE.mkdir(parents=True, exist_ok=True)
    EVIDENCE = STAGE / "mcp-wire-original11"
    RECEIPT = STAGE / "mcp-wire-original11.json"
    BINDING_PATH = STAGE / "mcp-wire-source-capacity-binding.json"
    LOCKS = pathlib.Path(tempfile.gettempdir()) / "hanlin-mcp-wire-supervision-locks"
    LOCKS.mkdir(parents=True, exist_ok=True)
    assert not EVIDENCE.exists() and not RECEIPT.exists() and not BINDING_PATH.exists()
    EVIDENCE.mkdir()
    SOURCE = git("rev-parse", "HEAD")
    preparation = {"at": now(), "source": SOURCE, "reviewedPackageSource": REVIEWED_SOURCE,
                   "command": COMMAND, "nativeCommandsStarted": 0}
    preparation_path = EVIDENCE / "preparation.json"
    preparation_path.write_text(json.dumps(preparation, indent=2) + "\n")
    try:
        assert os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch"
        assert os.environ.get("GITHUB_REPOSITORY") == "davidpovarsky/hanlin-ai"
        assert os.environ.get("GITHUB_SHA") == SOURCE
        assert pathlib.Path(os.environ["GITHUB_WORKSPACE"]).resolve() == ROOT
        inputs = json.loads(pathlib.Path(os.environ["GITHUB_EVENT_PATH"]).read_text()).get("inputs", {})
        assert inputs.get("target_validation_group") == "agent_sdk_exact_source_proof"
        assert inputs.get("exact_test_selector") == "HostMCPWireComparisonTests"
        for flag in ["composer_validation_only", "testflight_upload", "runtime_bundle_only",
                     "full_validation", "nativescript_metadata_validation_only",
                     "runtime_job_foundation_only", "markdown_renderer_validation_only",
                     "code_fence_webkit_validation_only", "diagnostics_capture_validation_only"]:
            assert str(inputs.get(flag, False)).lower() in {"false", "0", ""}, flag
        assert not git("status", "--porcelain=v1")
        for rel, expected in EXPECTED_PACKAGE_TREES.items():
            assert git("rev-parse", "HEAD:" + rel) == expected, rel
        for rel, expected in EXPECTED_SOURCE_AND_PINS.items():
            assert digest(ROOT / rel) == expected, rel
        support_paths = [
            "Scripts/CI/IntegrationValidation/run_host_mcp_wire_comparison.py",
            "Scripts/CI/IntegrationValidation/run_agent_sdk.sh",
            "Scripts/CI/select_stable_xcode.py", "Scripts/CI/verify_exact_json_vendor.py",
            ".github/workflows/build-ios26-unsigned-ipa.yml"]
        support = {}
        for rel in support_paths:
            raw = (ROOT / rel).read_bytes()
            assert raw == subprocess.check_output(["git", "-C", str(ROOT), "show", "HEAD:" + rel], timeout=10)
            support[rel] = hashlib.sha256(raw).hexdigest()
        selected = subprocess.run(
            [sys.executable, str(ROOT / "Scripts/CI/select_stable_xcode.py")],
            cwd=ROOT, capture_output=True, text=True, timeout=30, check=True)
        selected_path = pathlib.Path(selected.stdout.strip())
        assert selected_path.is_dir()
        os.environ["DEVELOPER_DIR"] = str(selected_path / "Contents/Developer")
        vendor = subprocess.run(
            [sys.executable, str(ROOT / "Scripts/CI/verify_exact_json_vendor.py")],
            cwd=ROOT, capture_output=True, text=True, timeout=60)
        (EVIDENCE / "original-vendor-verification.log").write_text(vendor.stdout + vendor.stderr)
        assert vendor.returncode == 0
        required = sum(COLD_CAPACITY_COMPONENTS.values())
        assert required == 6573280292
        BINDING = {
            "actualSource": SOURCE, "reviewedSource": REVIEWED_SOURCE,
            "historicalMacSource": "78ec8f97a607f5e1f8c01de5109ae850791b9e04",
            "packageTrees": EXPECTED_PACKAGE_TREES, "sourceAndPinHashes": EXPECTED_SOURCE_AND_PINS,
            "supportSourceHashes": support, "controllerSHA256": digest(pathlib.Path(__file__)),
            "capacity": {"at": now(), "freeBytes": free(), "components": COLD_CAPACITY_COMPONENTS,
                         "requiredBytes": required, "reserveBytes": 750000000, "compilerJobs": 2,
                         "rationale": "Same original measured cold package plan; no warm-cache capacity credit."},
            "route": {"existingJob": "agent-sdk-proof", "runnerLabel": "xcode-27",
                      "actualRunner": os.environ.get("RUNNER_NAME"),
                      "actualRunnerOS": os.environ.get("RUNNER_OS"),
                      "actualRunnerArch": os.environ.get("RUNNER_ARCH"),
                      "runID": os.environ.get("GITHUB_RUN_ID"),
                      "runAttempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
                      "jobCeilingMinutes": 60, "phaseCeilingSeconds": 3600,
                      "note": "The existing60-minute job includes preparation; no extra phase budget beyond it."},
            "cleanupObservationLimitation": "If owned stop observation fails, cleanup is unqualified until actual liveness is resolved."
        }
        BINDING_PATH.write_text(json.dumps(BINDING, indent=2) + "\n")
        data = {
            "status": "PREPARING_FOCUSED_ORIGINAL_MCP_WIRE_TESTS", "source": SOURCE,
            "reviewedSource": REVIEWED_SOURCE, "controllerPID": os.getpid(),
            "controllerSHA256": digest(pathlib.Path(__file__)), "bindingSHA256": digest(BINDING_PATH),
            "startedAt": now(), "command": COMMAND, "cwd": str(ROOT),
            "scratchPath": str(ROOT / "Packages/HanlinAgentSDK/.build"),
            "phaseDeadlineSeconds": ORIGINAL_PHASE_SECONDS,
            "expectedMethodNames": EXPECTED_METHODS, "expectedMethodCount": 11,
            "nativeCommandsStarted": 0,
            "compilerScheduling": "Original supported --jobs2; serialized suite and both120-second cases unchanged.",
            "boundary": "Original11 package comparator methods only; actual >8MiB app transport/render/store remains separate.",
            "existingCIJobCeilingMinutes": 60
        }
        run_prepared_original_gate()
    except BaseException as error:
        # Retain a separate error even when cleanup observation prevents the
        # original inner controller from completing its own status update.
        failure = {"at": now(), "source": SOURCE, "error": repr(error),
                   "traceback": traceback.format_exc(), "nativeAcceptance": False}
        (EVIDENCE / "outer-preparation-or-supervisor-error.json").write_text(
            json.dumps(failure, indent=2) + "\n")
        raise


if __name__ == "__main__":
    main()
