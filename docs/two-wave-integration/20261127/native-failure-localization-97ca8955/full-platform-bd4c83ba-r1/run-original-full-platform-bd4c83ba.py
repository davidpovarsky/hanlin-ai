"""Run the unchanged original full macOS Swift gate; samples are diagnostic only."""
import collections
import datetime
import fcntl
import hashlib
import json
import os
import pathlib
import re
import signal
import subprocess
import sys
import time
import traceback

STAGE = pathlib.Path('/Users/m1/builds/hanlin-two-wave-root-20261126')
ROOT = STAGE / 'source'
SOURCE = 'bd4c83baff2ed049a5a98aa0e0608f56f5a5cbcb'
ATTEMPT = 'r1'
EVIDENCE = STAGE / ('validation/full-platform-' + SOURCE[:8] + '-' + ATTEMPT)
RECEIPT = STAGE / ('full-platform-' + SOURCE[:8] + '-' + ATTEMPT + '.json')
COMMAND = ['/usr/bin/swift', 'test', '--package-path', 'Packages/HanlinPlatform', '--parallel']
ORIGINAL_PHASE_SECONDS = 3600
STAGE_RECEIPT = STAGE / 'source-stage-bd4c83ba-r2.json'
STAGE_RECEIPT_SHA256 = '089d26ee0a4413d54431c525d9c8afaf4f058fea2ee22842a2facd6e873a3f2f'
EXPECTED_TREES = {
    'Packages/HanlinPlatform': 'e7aefdeaff2434b3c6ab8c0e42bb6c3d26b3ac6f',
    'Packages/HanlinPlatform/Sources': '1586a7e95b6a3245bf0bb0ea60600c9b5086bc63',
    'Packages/HanlinPlatform/Tests': 'c88f6823845d9f6dc6aa93beb3a3bd0af6b1270a',
    'Fixtures/Widgets': 'a0b7b0b1cb9e1ce756ccff40593a325ffffa73d6',
}
LOCKS = {
    'Packages/HanlinPlatform/Package.resolved': '453087cb3345b7c6bb24c00a682f41ffa9708ebd328e60b583f6e04276bf789d',
    'AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved': '56d19a4b8c677831fb91e1f8155a68e411b42fd4807ad618d6f169569e1bb5a4',
}
CAPACITY = STAGE / 'full-platform-bd4c83ba-capacity-plan.json'
assert len(sys.argv) == 2 and re.fullmatch(r'[0-9a-f]{64}', sys.argv[1])
CAPACITY_SHA256 = sys.argv[1]


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


assert not EVIDENCE.exists() and not RECEIPT.exists(), 'Unique original gate evidence already exists'
EVIDENCE.mkdir(parents=True)
data = {
    'status': 'PREPARING_ORIGINAL_UNFILTERED_GATE', 'source': SOURCE,
    'controllerPID': os.getpid(), 'controllerSHA256': digest(pathlib.Path(__file__)),
    'startedAt': now(), 'command': COMMAND, 'cwd': str(ROOT),
    'scratchPath': str(ROOT / 'Packages/HanlinPlatform/.build'),
    'originalPhaseDeadlineSeconds': ORIGINAL_PHASE_SECONDS,
    'originalPerTestAndSuiteLimits': 'All tracked original declarations remain unchanged by this controller.',
    'boundary': 'Original unfiltered macOS Swift package suite only. This does not replace generic platform builds, selected iOS79, paired54, extra26, or app/OS/distribution acceptance.',
    'nativeCommandsStarted': 0, 'samples': [],
    'samplingPolicy': {'stallThresholdsSeconds': [15, 45], 'maximumTargetsPerRound': 2,
                       'sampleSeconds': 3, 'extendsOriginalDeadline': False,
                       'stalledExecutionIsNotItselfAPassOrEarlyStop': True},
}


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


known_owned = {}


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


def test_processes(rows):
    candidates = []
    for row in rows:
        name = pathlib.Path(row['executable']).name
        native_test = row['executable'].startswith(str(ROOT / 'Packages/HanlinPlatform/.build') + '/') and name.endswith('Tests')
        if name in {'swiftpm-testing-helper', 'xctest'} or native_test:
            candidates.append(row)
    return sorted(candidates, key=lambda row: ('swiftpm-testing' not in row['executable'], row['pid']))


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


native = open('/Users/m1/caches/hanlin-two-wave-native-app.lock', 'a+')
maintenance = open('/Users/m1/caches/.scaleway-cache-maintenance.lock', 'a+')
process = None
samplers = []
log_path = EVIDENCE / 'original-swift-test.log'
try:
    fcntl.flock(native, fcntl.LOCK_EX | fcntl.LOCK_NB)
    fcntl.flock(maintenance, fcntl.LOCK_SH | fcntl.LOCK_NB)
    data['coordinationLocks'] = {'native': 'exclusive', 'maintenance': 'shared'}
    assert digest(STAGE_RECEIPT) == STAGE_RECEIPT_SHA256
    stage_proof = json.loads(STAGE_RECEIPT.read_text())
    assert stage_proof['status'] == 'EXACT_REVIEWED_SOURCE_STAGED_ALL_392_SDK_INPUTS_MATCH_HOST_PRESERVED'
    assert stage_proof['source'] == SOURCE and stage_proof['sourceClean'] is True
    assert git('rev-parse', 'HEAD') == SOURCE and not git('status', '--porcelain=v1')
    assert (ROOT / 'Packages/HanlinPlatform/.build').is_dir(), 'Measured existing warm scratch must remain present'
    for rel, expected in EXPECTED_TREES.items():
        assert git('rev-parse', 'HEAD:' + rel) == expected, rel
    for rel, expected in LOCKS.items():
        assert digest(ROOT / rel) == expected, rel
    assert digest(CAPACITY) == CAPACITY_SHA256
    capacity = json.loads(CAPACITY.read_text())
    assert capacity['status'] == 'MEASURED_WARM_ORIGINAL_PHASE_CAPACITY_PLAN'
    assert capacity['source'] == SOURCE and capacity['command'] == COMMAND
    assert capacity['originalPhaseDeadlineSeconds'] == ORIGINAL_PHASE_SECONDS
    assert capacity['stageReceiptSHA256'] == STAGE_RECEIPT_SHA256
    components = capacity['budgetComponentsBytes']
    admission_bytes = sum(components.values())
    reserve_bytes = components['osReserve']
    assert admission_bytes == capacity['admissionBytes'] and reserve_bytes == capacity['continuousReserveBytes']
    assert reserve_bytes > 0 and admission_bytes > reserve_bytes
    assert components['incrementalCompileAndLink'] >= 2 * capacity['measuredAffectedOutputsBytes']
    data['capacityPlan'] = {'path': str(CAPACITY), 'sha256': CAPACITY_SHA256, 'contents': capacity}
    data['exactOriginalSource'] = {'packageTrees': EXPECTED_TREES, 'lockfiles': LOCKS,
                                   'stageReceiptSHA256': STAGE_RECEIPT_SHA256,
                                   'fullSourceHeadPinned': True, 'selectorsOrAssertionsChangedByController': False}
    data['swiftVersion'] = subprocess.check_output(['/usr/bin/swift', '--version'], text=True, timeout=20).strip()
    data['xcodeVersion'] = subprocess.check_output(['/usr/bin/xcodebuild', '-version'], text=True, timeout=20).strip()
    data['freeAtAdmission'] = free()
    if data['freeAtAdmission'] < admission_bytes:
        data['status'] = 'NOT_RUN_MEASURED_PHASE_CAPACITY'
        save()
    else:
        environment = os.environ.copy()
        environment['PATH'] = str(STAGE / 'tool-bin') + ':/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin'
        with log_path.open('xb') as log:
            process = subprocess.Popen(COMMAND, cwd=ROOT, env=environment, stdin=subprocess.DEVNULL,
                                       stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            data.update(status='RUNNING_ORIGINAL_UNFILTERED_BUILD', nativeCommandsStarted=1,
                        pid=process.pid, pgid=process.pid, commandStartedAt=now())
            save()
            started = time.monotonic()
            test_started = None
            log_size = 0
            last_growth = started
            samples_taken = set()
            while process.poll() is None:
                current = time.monotonic()
                size = log_path.stat().st_size
                if size != log_size:
                    log_size, last_growth = size, current
                text = log_path.read_text(errors='replace')
                rows = owned_tree(process.pid)
                testers = test_processes(rows)
                if test_started is None and (testers or 'Test run started.' in text):
                    test_started = current
                    data.update(status='RUNNING_ORIGINAL_UNFILTERED_TESTS', testExecutionObservedAt=now(),
                                testStartProcessTree=rows, buildElapsedSeconds=current-started)
                observation = {'at': now(), 'elapsedSeconds': current-started,
                               'testElapsedSeconds': None if test_started is None else current-test_started,
                               'freeBytes': free(), 'logBytes': size,
                               'secondsSinceLogGrowth': current-last_growth, 'ownedProcessTree': rows}
                data['lastObservation'] = observation
                if observation['freeBytes'] < reserve_bytes:
                    stop_owned_processes(process, 'MEASURED_OS_RESOURCE_RESERVE_REACHED')
                    break
                if current-started >= ORIGINAL_PHASE_SECONDS:
                    stop_owned_processes(process, 'ORIGINAL_UNFILTERED_PHASE_3600_SECOND_DEADLINE')
                    break
                if test_started is not None:
                    for threshold in [15, 45]:
                        if threshold in samples_taken or current-last_growth < threshold or not testers:
                            continue
                        tree_path = EVIDENCE / ('stalled-test-process-tree-' + str(threshold) + 's.json')
                        tree_path.write_text(json.dumps(observation, indent=2) + '\n')
                        for target in testers[:2]:
                            fresh = {row['pid']: row for row in process_snapshot()}
                            if target['pid'] not in fresh or process_identity(fresh[target['pid']]) != process_identity(target):
                                continue
                            sample_path = EVIDENCE / ('sample-stall-' + str(threshold) + 's-pid-' + str(target['pid']) + '.txt')
                            capture_log = sample_path.with_suffix('.command.log')
                            with capture_log.open('xb') as capture:
                                sampler = subprocess.Popen(['/usr/bin/sample', str(target['pid']), '3', '1', '-file', str(sample_path)],
                                                           stdin=subprocess.DEVNULL, stdout=capture, stderr=subprocess.STDOUT,
                                                           start_new_session=True)
                            record = {'stallThresholdSeconds': threshold, 'actualOwnedTarget': target,
                                      'samplerPID': sampler.pid, 'samplePath': str(sample_path),
                                      'commandLog': str(capture_log), 'tree': str(tree_path)}
                            data['samples'].append(record)
                            samplers.append((sampler, record, time.monotonic()))
                        samples_taken.add(threshold)
                for sampler, record, sample_started in samplers:
                    if 'exitCode' in record:
                        continue
                    if sampler.poll() is None and time.monotonic()-sample_started > 10:
                        sampler.terminate()
                        try:
                            sampler.wait(timeout=3)
                        except subprocess.TimeoutExpired:
                            sampler.kill()
                            sampler.wait(timeout=3)
                        record['samplerStopReason'] = 'DIAGNOSTIC_CAPTURE_10_SECOND_LIMIT'
                    if sampler.poll() is not None:
                        record['exitCode'] = sampler.returncode
                        sample_path = pathlib.Path(record['samplePath'])
                        record['sampleSHA256'] = digest(sample_path) if sample_path.is_file() else None
                save()
                time.sleep(2)
            data['exitCode'] = process.wait(timeout=10)
        final_text = log_path.read_text(errors='replace')
        summary_lines = re.findall(r'Test run with \d+ tests?[^\n]*(?:passed|failed)[^\n]*', final_text)
        passed_counts = re.findall(r'Test run with (\d+) tests?[^\n]*passed[^\n]*', final_text)
        starts = collections.Counter(re.findall(r'^.*?\bTest (.+?) started\.$', final_text, re.MULTILINE))
        terminals = collections.Counter(re.findall(r'^.*?\bTest (.+?) (?:passed|failed|skipped) after ', final_text, re.MULTILINE))
        data['originalTestRunSummaryLines'] = summary_lines
        data['reportedPassedTestRunCounts'] = [int(value) for value in passed_counts]
        data['observedMethodStarts'] = sum(starts.values())
        data['observedMethodTerminals'] = sum(terminals.values())
        data['unmatchedStartedMethodsDiagnosticOnly'] = dict(starts-terminals)
        data['skipLogLines'] = [line for line in final_text.splitlines() if ' skipped ' in line and ('Test ' in line or 'Suite ' in line)]
        data['originalFullSuitePassed'] = (not data.get('stopReason') and data['exitCode'] == 0
                                           and bool(passed_counts) and int(passed_counts[-1]) > 0)
        data['originalSourceUnchanged'] = (git('rev-parse', 'HEAD') == SOURCE
                                            and not git('status', '--porcelain=v1')
                                            and all(digest(ROOT/rel) == expected for rel, expected in LOCKS.items()))
        assert data['originalSourceUnchanged'], 'Source or pinned lockfile changed during the original full gate'
        data['retainedOwnedScratchExists'] = (ROOT / 'Packages/HanlinPlatform/.build').is_dir()
        data['status'] = ('ORIGINAL_FULL_SUITE_STOPPED' if data.get('stopReason') else
                          'ORIGINAL_UNFILTERED_MACOS_SWIFT_SUITE_PASSED' if data['originalFullSuitePassed'] else
                          'ORIGINAL_UNFILTERED_MACOS_SWIFT_SUITE_FAILED')
except BaseException as error:
    if process is not None and process.poll() is None:
        stop_owned_processes(process, 'FULL_GATE_CONTROLLER_EXCEPTION')
    data.update(status='FULL_GATE_CONTROLLER_FAILED', error=repr(error), traceback=traceback.format_exc())
finally:
    for sampler, record, sample_started in samplers:
        if sampler.poll() is None:
            try:
                sampler.wait(timeout=8)
            except subprocess.TimeoutExpired:
                sampler.terminate()
                try:
                    sampler.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    sampler.kill()
                    sampler.wait(timeout=3)
        record['exitCode'] = sampler.returncode
        sample_path = pathlib.Path(record['samplePath'])
        record['sampleSHA256'] = digest(sample_path) if sample_path.is_file() else None
    data['finishedAt'] = now()
    data['freeEnd'] = free()
    if log_path.is_file():
        data['log'] = {'path': str(log_path), 'bytes': log_path.stat().st_size, 'sha256': digest(log_path)}
    save()
    fcntl.flock(maintenance, fcntl.LOCK_UN)
    fcntl.flock(native, fcntl.LOCK_UN)
    print(json.dumps({key: data.get(key) for key in ['status', 'source', 'pid', 'exitCode', 'stopReason',
                                                   'originalFullSuitePassed', 'error', 'finishedAt', 'freeEnd', 'log']}), flush=True)
if data.get('status') != 'ORIGINAL_UNFILTERED_MACOS_SWIFT_SUITE_PASSED':
    raise SystemExit(1)
