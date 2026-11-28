import datetime
import fcntl
import hashlib
import json
import os
import pathlib
import re
import signal
import subprocess
import time
import traceback

STAGE = pathlib.Path('/Users/m1/builds/hanlin-two-wave-root-20261126')
ROOT = STAGE / 'source'
SOURCE = 'd2902ba9a4b18d5dba92662430e7eda355744b0c'
EVIDENCE = STAGE / 'validation/telemetry-macos-d2902ba9-r1'
RECEIPT = STAGE / 'telemetry-macos-d2902ba9-r1.json'
COMMAND = ['/usr/bin/swift', 'test', '--package-path', 'Packages/HanlinPlatform', '--parallel', '--filter', 'HanlinOpenTelemetryTracerTests']
ADMISSION_BYTES = 6 * 1024**3
RESERVE_BYTES = 2684354560
BUILD_SECONDS = 600
TEST_SECONDS = 120
EXPECTED_TREES = {'Packages/HanlinPlatform': 'ee3dceff23aa4298982869933382bbed06ff6124', 'Packages/HanlinPlatform/Sources': '1586a7e95b6a3245bf0bb0ea60600c9b5086bc63', 'Packages/HanlinPlatform/Tests': 'c4683795c1a192855ca2de769546ee2ccf4f948d'}
LOCKS = {'Packages/HanlinPlatform/Package.resolved': '453087cb3345b7c6bb24c00a682f41ffa9708ebd328e60b583f6e04276bf789d', 'AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved': '56d19a4b8c677831fb91e1f8155a68e411b42fd4807ad618d6f169569e1bb5a4'}


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


assert not EVIDENCE.exists() and not RECEIPT.exists(), 'Unique diagnostic evidence already exists'
EVIDENCE.mkdir(parents=True)
data = {'status': 'PREPARING_DIAGNOSTIC', 'source': SOURCE, 'controllerPID': os.getpid(), 'controllerSHA256': digest(pathlib.Path(__file__)), 'startedAt': now(), 'command': COMMAND, 'cwd': str(ROOT), 'scratchPath': str(ROOT / 'Packages/HanlinPlatform/.build'), 'admissionBytes': ADMISSION_BYTES, 'continuousReserveBytes': RESERVE_BYTES, 'buildEnvelopeSeconds': BUILD_SECONDS, 'testDiagnosticEnvelopeSeconds': TEST_SECONDS, 'originalSuiteTimeLimit': 'Unmodified @Suite timeLimit(.minutes(1))', 'boundary': 'One parent-authorized original filtered macOS SwiftPM diagnostic. It neither replaces nor credits the unfiltered platform gate, selected iOS79, paired54, extra26 or app/OS/distribution acceptance.', 'nativeCommandsStarted': 0, 'samples': []}


def save():
    temporary = RECEIPT.with_suffix('.pending')
    temporary.write_text(json.dumps(data, indent=2) + '\n')
    temporary.replace(RECEIPT)


def owned_tree(parent_pid):
    result = subprocess.run(['/bin/ps', '-axo', 'pid=,ppid=,pgid=,stat=,etime=,comm='], capture_output=True, text=True, timeout=10, check=True)
    rows = []
    for line in result.stdout.splitlines():
        fields = line.strip().split(None, 5)
        if len(fields) != 6:
            continue
        rows.append({'pid': int(fields[0]), 'ppid': int(fields[1]), 'pgid': int(fields[2]), 'state': fields[3], 'elapsed': fields[4], 'executable': fields[5]})
    ids = {parent_pid}
    while True:
        added = {row['pid'] for row in rows if row['ppid'] in ids} - ids
        if not added:
            break
        ids.update(added)
    return [row for row in rows if row['pid'] in ids]


def test_processes(rows):
    candidates = []
    for row in rows:
        name = pathlib.Path(row['executable']).name
        if name == 'swiftpm-testing-helper' or name == 'xctest' or ('HanlinPlatform' in name and name.endswith('PackageTests')):
            candidates.append(row)
    return sorted(candidates, key=lambda row: ('swiftpm-testing' not in row['executable'], row['pid']))


def stop_owned_group(process, reason):
    data['stopReason'] = reason
    data['stopRequestedAt'] = now()
    data['stopProcessTree'] = owned_tree(process.pid)
    save()
    # Popen created this process group. No foreign process group is addressed.
    for sig, grace in [(signal.SIGINT, 3), (signal.SIGTERM, 3), (signal.SIGKILL, 3)]:
        if process.poll() is not None:
            return
        assert os.getpgid(process.pid) == process.pid
        os.killpg(process.pid, sig)
        try:
            process.wait(timeout=grace)
            return
        except subprocess.TimeoutExpired:
            pass


native = open('/Users/m1/caches/hanlin-two-wave-native-app.lock', 'a+')
maintenance = open('/Users/m1/caches/.scaleway-cache-maintenance.lock', 'a+')
process = None
samplers = []
log_path = EVIDENCE / 'original-swift-test.log'
try:
    fcntl.flock(native, fcntl.LOCK_EX | fcntl.LOCK_NB)
    fcntl.flock(maintenance, fcntl.LOCK_SH | fcntl.LOCK_NB)
    data['coordinationLocks'] = {'native': 'exclusive', 'maintenance': 'shared'}
    assert git('rev-parse', 'HEAD') == SOURCE and not git('status', '--porcelain=v1')
    assert not (ROOT / 'Packages/HanlinPlatform/.build').exists(), 'This first diagnostic expects the observed absent owned SwiftPM scratch'
    for rel, expected in EXPECTED_TREES.items():
        assert git('rev-parse', 'HEAD:' + rel) == expected, rel
    for rel, expected in LOCKS.items():
        assert digest(ROOT / rel) == expected, rel
    test_file = ROOT / 'Packages/HanlinPlatform/Tests/HanlinChatCoreTests/HanlinOpenTelemetryTracerTests.swift'
    adapter = ROOT / 'Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinOpenTelemetryTracer.swift'
    assert digest(test_file) == 'be9b6fe280dfe43c4791644a333e90bdfc142936c51c909f12d84173bb22d4b5'
    assert digest(adapter) == '3278fd5539dfb554b645180886aa31421b3d02096a67b45aa6ba26b21e442292'
    expected_cases = re.findall(r'@Test\s+func\s+(\w+)\(', test_file.read_text())
    assert expected_cases and '@Suite("Original OpenTelemetry bridge", .timeLimit(.minutes(1)))' in test_file.read_text()
    data['exactOriginalSource'] = {'packageTrees': EXPECTED_TREES, 'lockfiles': LOCKS, 'testFileSHA256': digest(test_file), 'adapterSHA256': digest(adapter), 'testMethods': expected_cases, 'testsUnmodified': True}
    data['swiftVersion'] = subprocess.check_output(['/usr/bin/swift', '--version'], text=True, timeout=20).strip()
    data['xcodeVersion'] = subprocess.check_output(['/usr/bin/xcodebuild', '-version'], text=True, timeout=20).strip()
    data['freeAtAdmission'] = free()
    if data['freeAtAdmission'] < ADMISSION_BYTES:
        data['status'] = 'NOT_RUN_RESOURCE_ADMISSION'
        save()
    else:
        environment = os.environ.copy()
        environment['PATH'] = str(STAGE / 'tool-bin') + ':/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin'
        with log_path.open('xb') as log:
            process = subprocess.Popen(COMMAND, cwd=ROOT, env=environment, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            data.update(status='RUNNING_ORIGINAL_DIAGNOSTIC_BUILD', nativeCommandsStarted=1, pid=process.pid, pgid=process.pid, commandStartedAt=now())
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
                    log_size = size
                    last_growth = current
                text = log_path.read_text(errors='replace')
                rows = owned_tree(process.pid)
                testers = test_processes(rows)
                if test_started is None and (testers or ('Suite "Original OpenTelemetry bridge" started' in text)):
                    test_started = current
                    data.update(status='RUNNING_ORIGINAL_FILTERED_TELEMETRY_DIAGNOSTIC', testExecutionObservedAt=now(), testStartProcessTree=rows, buildElapsedSeconds=current-started)
                observation = {'at': now(), 'elapsedSeconds': current-started, 'testElapsedSeconds': None if test_started is None else current-test_started, 'freeBytes': free(), 'logBytes': size, 'secondsSinceLogGrowth': current-last_growth, 'ownedProcessTree': rows}
                data['lastObservation'] = observation
                if observation['freeBytes'] < RESERVE_BYTES:
                    stop_owned_group(process, 'RESOURCE_RESERVE_2_5_GIB')
                    break
                if test_started is None and current-started >= BUILD_SECONDS:
                    stop_owned_group(process, 'BUILD_DIAGNOSTIC_600_SECOND_ENVELOPE')
                    break
                if test_started is not None and current-test_started >= TEST_SECONDS:
                    stop_owned_group(process, 'FILTERED_TEST_DIAGNOSTIC_120_SECOND_ENVELOPE')
                    break
                if test_started is not None and current-last_growth >= 5:
                    for threshold in [15, 45]:
                        if threshold in samples_taken or current-test_started < threshold or not testers:
                            continue
                        tree_path = EVIDENCE / ('test-process-tree-at-' + str(threshold) + 's.json')
                        tree_path.write_text(json.dumps(observation, indent=2) + '\n')
                        for target in testers[:2]:
                            sample_path = EVIDENCE / ('sample-' + str(threshold) + 's-pid-' + str(target['pid']) + '.txt')
                            capture_log = EVIDENCE / ('sample-' + str(threshold) + 's-pid-' + str(target['pid']) + '-command.log')
                            with capture_log.open('xb') as capture:
                                sampler = subprocess.Popen(['/usr/bin/sample', str(target['pid']), '3', '1', '-file', str(sample_path)], stdin=subprocess.DEVNULL, stdout=capture, stderr=subprocess.STDOUT)
                            record = {'thresholdSeconds': threshold, 'observedTestElapsedSeconds': current-test_started, 'actualOwnedTarget': target, 'samplerPID': sampler.pid, 'samplePath': str(sample_path), 'commandLog': str(capture_log), 'tree': str(tree_path)}
                            data['samples'].append(record)
                            samplers.append((sampler, record))
                        samples_taken.add(threshold)
                save()
                time.sleep(2)
            data['exitCode'] = process.wait(timeout=10)
        for sampler, record in samplers:
            try:
                record['exitCode'] = sampler.wait(timeout=8)
            except subprocess.TimeoutExpired:
                sampler.terminate()
                record['exitCode'] = sampler.wait(timeout=3)
            p = pathlib.Path(record['samplePath'])
            record['sampleSHA256'] = digest(p) if p.is_file() else None
        final_text = log_path.read_text(errors='replace')
        summaries = re.findall(r'Test run with (\d+) tests?[^\n]*(?:passed|failed)[^\n]*', final_text)
        passed = re.findall(r'Test run with (\d+) tests?[^\n]*passed[^\n]*', final_text)
        data['reportedTestRunCounts'] = [int(x) for x in summaries]
        data['originalFilteredSuitePassed'] = not data.get('stopReason') and data['exitCode'] == 0 and bool(passed) and int(passed[-1]) == len(expected_cases) and 'Original OpenTelemetry bridge' in final_text
        data['status'] = 'STOPPED_ORIGINAL_DIAGNOSTIC' if data.get('stopReason') else ('ORIGINAL_FILTERED_DIAGNOSTIC_COMPLETED' if data['exitCode'] == 0 else 'ORIGINAL_FILTERED_DIAGNOSTIC_FAILED')
        data['originalPackageSourceUnchanged'] = git('rev-parse', 'HEAD') == SOURCE and not git('status', '--porcelain=v1') and all(digest(ROOT/rel) == expected for rel, expected in LOCKS.items())
        assert data['originalPackageSourceUnchanged'], 'Original source or pinned lockfile changed during diagnostic'
        data['retainedOwnedScratchExists'] = (ROOT / 'Packages/HanlinPlatform/.build').is_dir()
except BaseException as error:
    if process is not None and process.poll() is None:
        stop_owned_group(process, 'DIAGNOSTIC_CONTROLLER_EXCEPTION')
    data.update(status='DIAGNOSTIC_CONTROLLER_FAILED', error=repr(error), traceback=traceback.format_exc())
finally:
    data['finishedAt'] = now()
    data['freeEnd'] = free()
    if log_path.is_file():
        data['log'] = {'path': str(log_path), 'bytes': log_path.stat().st_size, 'sha256': digest(log_path)}
    save()
    fcntl.flock(maintenance, fcntl.LOCK_UN)
    fcntl.flock(native, fcntl.LOCK_UN)
    print(json.dumps({key: data.get(key) for key in ['status', 'source', 'pid', 'exitCode', 'stopReason', 'originalFilteredSuitePassed', 'error', 'finishedAt', 'freeEnd', 'log']}), flush=True)
