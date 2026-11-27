"""One exact original HTTP selector, with unchanged native assertions and limits."""
import datetime, fcntl, hashlib, json, os, pathlib, re, signal, subprocess, sys, time, traceback
STAGE = pathlib.Path('/Users/m1/builds/hanlin-two-wave-root-20261126')
ROOT = STAGE / 'source'
SOURCE = 'b84d5ffb1c52361ac884a967f13e5500efe3d232'
STAGE_RECEIPT = STAGE / 'source-stage-b84d5ffb-r1.json'
EVIDENCE = STAGE / 'validation/original-http-b84d5ffb-r1'
HTTP_SOURCE = 'Packages/HanlinPlatform/Tests/HanlinScriptExtensionsTests/HanlinDualWidgetEnginesTests.swift'
HTTP_SHA256 = '519cb2c41cf1835b30d9e82da54703c3ca844668686b1d933cb49a1bc2f8f974'
SELECTOR = 'originalScriptWidgetHTTPUsesBoundedRealTransport'
COMMAND = ['/usr/bin/swift','test','--package-path','Packages/HanlinPlatform','--parallel','--filter',SELECTOR]

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def free():
    fs = os.statvfs('/System/Volumes/Data')
    return fs.f_bavail * fs.f_frsize

def git(*args):
    return subprocess.check_output(['/usr/bin/git', '-C', str(ROOT), *args], text=True, timeout=30).strip()

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

def owned_tree(parent_pid, rows=None):
    rows = process_snapshot() if rows is None else rows
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
        rows = process_snapshot()
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
    data['ownedProcessesAfterStop'] = [row for row in process_snapshot()
                                      if known_owned.get(row['pid']) == process_identity(row)]
    save()

known_owned = {}
assert not EVIDENCE.exists(), 'A prior diagnostic attempt must not be overwritten'
EVIDENCE.mkdir(parents=True)
RECEIPT = EVIDENCE / 'controller.json'
LOG = EVIDENCE / 'original-http-selector.log'
data = {
    'status': 'PREPARING_ONE_ORIGINAL_HTTP_SELECTOR_DIAGNOSTIC',
    'source': SOURCE, 'command': COMMAND, 'cwd': str(ROOT),
    'controllerPID': os.getpid(), 'controllerSHA256': digest(pathlib.Path(__file__)),
    'startedAt': now(), 'nativeCommandsStarted': 0,
    'scope': 'One original failing macOS HTTP selector; all tracked assertions and its original eight-second execution budget remain unchanged.',
    'boundary': 'Diagnostic evidence only. No full601, iOS79, Host188, app54/26 or OS acceptance claim.',
}

def save():
    temporary = RECEIPT.with_suffix('.pending')
    temporary.write_text(json.dumps(data, indent=2) + '\n')
    temporary.replace(RECEIPT)

native = open('/Users/m1/caches/hanlin-two-wave-native-app.lock', 'a+')
maintenance = open('/Users/m1/caches/.scaleway-cache-maintenance.lock', 'a+')
process = None
try:
    fcntl.flock(native, fcntl.LOCK_EX | fcntl.LOCK_NB)
    fcntl.flock(maintenance, fcntl.LOCK_SH | fcntl.LOCK_NB)
    assert digest(STAGE_RECEIPT) == '1efb166b17791ee1019f91cab6821242073b2da6a9c59c373071e257ad7d21e5'
    stage = json.loads(STAGE_RECEIPT.read_text())
    assert stage['source'] == SOURCE and stage['SDK392Matched'] == 392
    assert stage['status'] == 'EXACT_REVIEWED_SOURCE_STAGED_ALL_392_SDK_INPUTS_MATCH_HOST_PRESERVED'
    assert git('rev-parse', 'HEAD') == SOURCE and not git('status', '--porcelain=v1')
    assert git('rev-parse', 'HEAD:Packages/HanlinPlatform') == '67635c39682942321de5a4f0626ec4ec7b9f52b4'
    assert digest(ROOT / HTTP_SOURCE) == HTTP_SHA256
    for name, sha in stage['pins'].items():
        assert digest(ROOT / name) == sha
    declaration = git('grep', '-n', '-F', 'func ' + SELECTOR + '(', '--', 'Packages/HanlinPlatform/Tests')
    assert len(declaration.splitlines()) == 1 and declaration.startswith(HTTP_SOURCE + ':')
    data['exactSelectorDeclaration'] = declaration
    warm = ROOT / 'Packages/HanlinPlatform/.build'
    assert warm.is_dir() and warm.stat().st_ino == stage['warmBuildInode']
    capacity = {
        'measuredPriorTwoAffectedTestTargetsBytes': 99581952,
        'changedPackageFiles': [HTTP_SOURCE],
        'existingCompleteWarmBuildReused': True,
        'budgetComponentsBytes': {'incrementalCompileAndLink': 256*1024**2,
            'nativeFixtureTemporaryFiles': 16*1024**2, 'logsAndEvidence': 16*1024**2,
            'concurrentGrowthAllowance': 512*1024**2, 'osReserve': 768*1024**2},
        'rationale': 'One test file changes. Production, pins and all other package files match the warmed full601 build. The compilation allowance exceeds twice the measured combined outputs of the previously affected two targets. Actual free space and the OS reserve are monitored throughout this short diagnostic; no fixed global capacity target is used.',
    }
    admission = sum(capacity['budgetComponentsBytes'].values())
    reserve = capacity['budgetComponentsBytes']['osReserve']
    data['capacity'] = capacity
    data['freeAtAdmission'] = free()
    data['admissionBytes'] = admission
    data['diagnosticOuterBounds'] = {'buildSeconds': 600, 'testSeconds': 120, 'originalTrackedTestLimitsUnchanged': True}
    data['swiftVersion'] = subprocess.check_output(['/usr/bin/swift', '--version'], text=True, timeout=15).strip()
    data['xcodeVersion'] = subprocess.check_output(['/usr/bin/xcodebuild', '-version'], text=True, timeout=15).strip()
    data['stageReceiptSHA256'] = digest(STAGE_RECEIPT)
    data['sourceHTTPFileSHA256'] = HTTP_SHA256
    save()
    if data['freeAtAdmission'] < admission:
        data['status'] = 'NOT_RUN_MEASURED_INCREMENTAL_PHASE_DOES_NOT_FIT'
    else:
        env = os.environ.copy()
        env['PATH'] = str(STAGE / 'tool-bin') + ':/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin'
        env['HANLIN_WIDGET_EVIDENCE_DIR'] = str(EVIDENCE / 'native')
        (EVIDENCE / 'native').mkdir()
        data['HANLIN_WIDGET_EVIDENCE_DIR'] = env['HANLIN_WIDGET_EVIDENCE_DIR']
        with LOG.open('xb') as log:
            process = subprocess.Popen(COMMAND, cwd=ROOT, env=env, stdin=subprocess.DEVNULL,
                stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            data.update(status='RUNNING_ONE_ORIGINAL_HTTP_SELECTOR', nativeCommandsStarted=1,
                pid=process.pid, pgid=process.pid, commandStartedAt=now())
            save()
            start = time.monotonic()
            test_start = None
            while process.poll() is None:
                elapsed = time.monotonic() - start
                text = LOG.read_text(errors='replace')
                rows = owned_tree(process.pid)
                if test_start is None and ('Test ' + SELECTOR + '() started.') in text:
                    test_start = time.monotonic()
                    data['testStartObservedAt'] = now()
                    data['testStartProcessTree'] = rows
                data['lastObservation'] = {'at': now(), 'elapsedSeconds': elapsed,
                    'freeBytes': free(), 'logBytes': LOG.stat().st_size, 'ownedProcessTree': rows}
                if data['lastObservation']['freeBytes'] < reserve:
                    stop_owned_processes(process, 'MEASURED_OS_RESOURCE_RESERVE_REACHED')
                    break
                if (test_start is None and elapsed >= 600) or (test_start is not None and time.monotonic()-test_start >= 120):
                    stop_owned_processes(process, 'BOUNDED_SINGLE_SELECTOR_DIAGNOSTIC_ENVELOPE')
                    break
                save()
                time.sleep(1)
            data['exitCode'] = process.wait(timeout=10)
        text = LOG.read_text(errors='replace')
        method_starts = re.findall(r'^.*?Test ([A-Za-z_][A-Za-z_0-9]*\([^\n]*\)) started\.$', text, re.MULTILINE)
        method_terminals = re.findall(r'^.*?Test ([A-Za-z_][A-Za-z_0-9]*\([^\n]*\)) (passed|failed|skipped) after [^\n]*', text, re.MULTILINE)
        data['methodStarts'] = method_starts
        data['methodTerminals'] = method_terminals
        data['exactOneSelectorExecuted'] = method_starts == [SELECTOR+'()'] and len(method_terminals) == 1 and method_terminals[0][0] == SELECTOR+'()'
        data['nativeSummaryLines'] = [line for line in text.splitlines() if 'Test run with ' in line or 'recorded an issue' in line or ('Test '+SELECTOR) in line]
        data['diagnosticOriginalSelectorPassed'] = (not data.get('stopReason') and data['exitCode'] == 0
            and data['exactOneSelectorExecuted'] and method_terminals[0][1] == 'passed')
        data['status'] = ('ORIGINAL_HTTP_SELECTOR_DIAGNOSTIC_STOPPED' if data.get('stopReason') else
            'ORIGINAL_HTTP_SELECTOR_DIAGNOSTIC_PASSED' if data['diagnosticOriginalSelectorPassed'] else
            'ORIGINAL_HTTP_SELECTOR_DIAGNOSTIC_FAILED')
except BaseException as error:
    if process is not None and process.poll() is None:
        stop_owned_processes(process, 'SINGLE_SELECTOR_DIAGNOSTIC_CONTROLLER_EXCEPTION')
    data.update(status='HTTP_DIAGNOSTIC_CONTROLLER_FAILED', error=repr(error), traceback=traceback.format_exc())
finally:
    data['sourceUnchanged'] = (git('rev-parse', 'HEAD') == SOURCE and not git('status', '--porcelain=v1')
        and digest(ROOT / HTTP_SOURCE) == HTTP_SHA256)
    data['finishedAt'] = now()
    data['freeEnd'] = free()
    data['retainedEvidence'] = [{'path': str(p.relative_to(EVIDENCE)), 'bytes': p.stat().st_size, 'sha256': digest(p)}
        for p in sorted(EVIDENCE.rglob('*')) if p.is_file() and p != RECEIPT and p.suffix != '.pending']
    save()
    fcntl.flock(maintenance, fcntl.LOCK_UN)
    fcntl.flock(native, fcntl.LOCK_UN)
    print(json.dumps({key: data.get(key) for key in ['status','source','pid','exitCode','stopReason','error',
        'exactOneSelectorExecuted','diagnosticOriginalSelectorPassed','nativeSummaryLines','sourceUnchanged','finishedAt','freeEnd']}), flush=True)
if not data.get('diagnosticOriginalSelectorPassed'):
    raise SystemExit(1)
