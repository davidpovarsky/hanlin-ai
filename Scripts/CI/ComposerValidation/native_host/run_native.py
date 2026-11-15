"""One guarded native-project diagnostic. Manual CI only, after final source approval."""
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tarfile
import tempfile
import time
from datetime import datetime, timezone

sys.dont_write_bytecode = True
import prepare_native as native
from guards import (native_settings, environment, owned_boot, destination, observations, require,
                    simctl_list_contract, owned_devices_command, require_pretest)

XCODE = '/Applications/Xcode_27.2.app/Contents/Developer'
TEST_SECONDS = 900
RUN_SECONDS = 2100


def stamp():
    return datetime.now(timezone.utc).isoformat()


def command_plan(project_dir, sdk, device, scratch, evidence):
    base = ['xcodebuild', '-project', str(project_dir / native.PROJECT), '-scheme', native.SCHEME,
            '-configuration', 'Debug', '-sdk', sdk]
    owned = ['-destination', 'platform=iOS Simulator,id=' + device, '-arch', 'arm64']
    return {
        'settings': [*base, '-showBuildSettings', '-json', *owned, 'ONLY_ACTIVE_ARCH=YES'],
        'destinations': [*base, '-showdestinations'],
        'test': [*base, 'test', *owned, '-destination-timeout', '30',
                 '-parallel-testing-enabled', 'NO', '-maximum-concurrent-test-simulator-destinations', '1',
                 '-maximum-parallel-testing-workers', '1', '-derivedDataPath', str(scratch / 'DerivedData'),
                 '-resultBundlePath', str(evidence / 'ComposerNative.xcresult'),
                 '-only-testing:AI_HanlinTests/HanlinMorphComposerTests',
                 '-only-testing:AI_HanlinTests/NativeComposerLineSizingTests', 'ONLY_ACTIVE_ARCH=YES', 'CODE_SIGNING_ALLOWED=NO'],
    }


class Runner:
    def __init__(self, evidence):
        self.evidence = evidence
        self.env = dict(os.environ, DEVELOPER_DIR=XCODE, PYTHONDONTWRITEBYTECODE='1')
        self.deadline = time.monotonic() + RUN_SECONDS
        self.commands = []

    def save(self, name, value):
        (self.evidence / name).write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')

    def call(self, label, seconds, args, required=True):
        # A single process group is interrupted at its cap; no retry or fallback.
        remaining = int(self.deadline - time.monotonic())
        require(remaining > 5, 'runner wall budget exhausted before ' + label)
        budget = min(seconds, remaining)
        record = {'label': label, 'argv': args, 'DEVELOPER_DIR': XCODE,
                  'started_at_utc': stamp(), 'timeout_seconds': budget}
        start = time.monotonic()
        with (self.evidence / (label + '.stdout')).open('wb') as stdout, (self.evidence / (label + '.stderr')).open('wb') as stderr:
            process = subprocess.Popen(args, cwd=native.REPO, env=self.env, stdout=stdout, stderr=stderr, start_new_session=True)
            try:
                status = process.wait(timeout=max(1, budget - 5))
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGINT)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                status = 124
            except BaseException:
                os.killpg(process.pid, signal.SIGINT)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                raise
        record.update(exit_code=status, elapsed_seconds=round(time.monotonic() - start, 3), finished_at_utc=stamp())
        self.commands.append(record)
        self.save('commands.json', self.commands)
        if required:
            require(status == 0, label + ': command failed/timed out, status=' + str(status))
        return status

    def text(self, label):
        return (self.evidence / (label + '.stdout')).read_text(encoding='utf-8', errors='replace')

    def json(self, label):
        return json.loads(self.text(label))


def execute():
    require(sys.platform == 'darwin', 'remote Mac only; no local builds/staging')
    require(os.environ.get('GITHUB_EVENT_NAME') == 'workflow_dispatch' and
            os.environ.get('COMPOSER_NATIVE_HOST_DIAGNOSTIC') == '1', 'explicit isolated manual native job required')
    require(os.environ.get('GITHUB_RUN_ATTEMPT') == '1', 'rerun attempts prohibited; one fresh authorized diagnostic only')
    evidence = native.REPO / 'build/composer-native-host-evidence'
    evidence.mkdir(parents=True, exist_ok=False)
    runner = Runner(evidence)
    expected = json.loads((native.HERE / 'review/native-inputs.json').read_text(encoding='utf-8'))['expected_case_ids']
    state = {'scope': 'native-hosted Composer component diagnostic', 'full_app_acceptance': False,
             'started_at_utc': stamp(), 'status': 'PREPARING', 'test_commands': 0,
             'native_settings_confirmed': False, 'owned_sdk_destination_confirmed': False,
             'owned_query_help_confirmed': False, 'owned_boot_confirmed': False,
             'xcodebuild_test_exit_code': None, 'apple_pass_claim': False}
    runner.save('run-state.json', state)
    device, project_dir = None, None
    exit_code = 2
    try:
        expected_sha = os.environ.get('COMPOSER_EXPECTED_SHA', '')
        require(re.fullmatch('[0-9a-f]{40}', expected_sha) is not None, 'exact expected workflow commit required')
        runner.call('workflow-commit', 30, ['git', 'rev-parse', 'HEAD'])
        require(runner.text('workflow-commit').strip() == expected_sha, 'workflow commit mismatch')
        state['workflow_commit'] = expected_sha
        if runner.call('frozen-source-present', 30, ['git', 'cat-file', '-e', native.SOURCE + '^{commit}'], required=False):
            runner.call('fetch-frozen-source', 120, ['git', 'fetch', '--no-tags', '--depth=1', 'origin', native.SOURCE])
        runner.call('frozen-source-review-check', 120, [sys.executable, '-B', str(native.HERE / 'freeze_review.py'), '--check'])
        runner.call('final-guard-review-check', 120, [sys.executable, '-B', str(native.HERE / 'review_guard.py'), '--check'])
        require(Path(XCODE, 'usr/bin/xcodebuild').is_file(), 'exact installed Xcode missing; no selection/install fallback')
        runner.call('xcode-version', 30, ['xcodebuild', '-version'])
        require(runner.text('xcode-version').strip() == 'Xcode 27.2\nBuild version 27B52', 'installed Xcode version/build mismatch')
        runner.call('swift-version', 30, ['xcrun', 'swift', '--version'])
        require('Apple Swift version 6.4.2 ' in runner.text('swift-version'), 'installed compiler version mismatch')
        runner.call('sdk-version', 30, ['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'])
        runner.call('sdk-path', 30, ['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'])
        require(runner.text('sdk-version').strip() == '27.2', 'installed simulator SDK version mismatch')
        sdk = runner.text('sdk-path').strip()
        require(sdk.startswith(XCODE + '/') and sdk.endswith('/iPhoneSimulator27.2.sdk') and Path(sdk).is_dir(), 'explicit installed simulator SDK path mismatch')
        scratch = Path(tempfile.mkdtemp(prefix='hanlin-composer-native-', dir=os.environ.get('RUNNER_TEMP', '/tmp')))
        project_dir = scratch / 'NativeHost'
        runner.call('stage-native-project', 120, [sys.executable, '-B', str(native.HERE / 'prepare_native.py'), '--output', str(project_dir)])
        manifest = json.loads((project_dir / 'native-inputs.json').read_text(encoding='utf-8'))
        require(manifest['expected_case_ids'] == expected and manifest['full_app_acceptance'] is False, 'staged manifest mismatch')
        runner.save('native-inputs.json', manifest)
        # Retain whole original source and generated native inputs on the remote runner only.
        with tarfile.open(evidence / 'native-source-inputs.tar', 'w') as archive:
            archive.add(project_dir, arcname='NativeHost')
        workflow = native.REPO / '.github/workflows/build-ios26-unsigned-ipa.yml'
        harness = [*sorted(p for p in native.HERE.rglob('*') if p.is_file()), workflow]
        runner.save('harness-sha256.json', {p.relative_to(native.REPO).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in harness})
        runner.call('installed-simctl-list-help', 30, ['xcrun', 'simctl', 'help', 'list'])
        help_stdout = runner.text('installed-simctl-list-help')
        help_stderr = (evidence / 'installed-simctl-list-help.stderr').read_text(encoding='utf-8', errors='replace')
        help_contract = simctl_list_contract(help_stdout, help_stderr)
        help_receipt = dict(help_contract, raw_stream_sha256={stream: hashlib.sha256(
            (evidence / ('installed-simctl-list-help.' + stream)).read_bytes()).hexdigest() for stream in ['stdout', 'stderr']})
        runner.save('installed-simctl-list-help-guard.json', help_receipt)
        state['owned_query_help_confirmed'] = True
        runner.save('run-state.json', state)
        runner.call('simulators-before', 30, ['xcrun', 'simctl', 'list', '-j'])
        before = runner.json('simulators-before')
        runtime, model = environment(before)
        runner.save('installed-environment.json', {'runtime': runtime, 'device_type': model, 'sdk_path': sdk,
                                                  'Xcode': '27.2/27B52', 'DEVELOPER_DIR': XCODE})
        runner.call('create-owned-device', 30, ['xcrun', 'simctl', 'create', 'Hanlin-NativeComposer-' + os.environ['GITHUB_RUN_ID'], model['identifier'], runtime['identifier']])
        device = runner.text('create-owned-device').strip()
        require(re.fullmatch(r'[0-9A-Fa-f-]{36}', device) is not None and device not in
                {d['udid'] for devices in before['devices'].values() for d in devices}, 'invalid/nonfresh owned device')
        runner.save('owned-device.json', {'udid': device, 'created_at_utc': stamp(), 'runtime': runtime, 'device_type': model})
        owned_query = owned_devices_command(help_contract, device)
        runner.save('owned-device-state-query.json', {'argv': owned_query,
                    'help_receipt': 'installed-simctl-list-help-guard.json', 'timeout_seconds': 30,
                    'boot_state_confirmed': False})
        plan = command_plan(project_dir, sdk, device, scratch, evidence)
        runner.save('native-command-plan.json', plan)
        runner.call('native-target-build-settings', 120, plan['settings'])
        settings_receipt = native_settings(runner.json('native-target-build-settings'), sdk)
        runner.save('native-settings-guard.json', settings_receipt)
        state['native_settings_confirmed'] = True
        state['status'] = 'CREATED_SETTINGS_CONFIRMED_BOOT_NOT_VERIFIED'
        runner.save('run-state.json', state)
        runner.call('boot-owned-device', 30, ['xcrun', 'simctl', 'boot', device])
        runner.call('bootstatus-owned-device', 180, ['xcrun', 'simctl', 'bootstatus', device, '-b'])
        runner.call('owned-device-state-after-boot', 30, owned_query)
        actual = owned_boot(runner.json('owned-device-state-after-boot'), before, runtime, device)
        runner.save('owned-device-boot-confirmed.json', actual)
        state['owned_boot_confirmed'] = True
        state['status'] = 'SETTINGS_AND_FILTERED_BOOT_CONFIRMED'
        runner.save('run-state.json', state)
        runner.call('native-sdk-destinations', 120, plan['destinations'])
        eligibility = destination(runner.text('native-sdk-destinations'),
                                  (evidence / 'native-sdk-destinations.stderr').read_text(encoding='utf-8', errors='replace'), device)
        runner.save('owned-sdk-destination-guard.json', eligibility)
        state['owned_sdk_destination_confirmed'] = True
        require(runner.deadline - time.monotonic() >= TEST_SECONDS + 180, 'insufficient remaining test/export/owned-teardown budget; no test')
        require_pretest(state)
        state.update(test_commands=1, status='ONE_TEST_COMMAND_STARTED')
        runner.save('run-state.json', state)
        status = runner.call('native-test', TEST_SECONDS, plan['test'], required=False)
        state.update(xcodebuild_test_exit_code=status, status='TEST_COMMAND_FINISHED')
        runner.save('run-state.json', state)
        exit_code = status
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as error:
        state.update(status='STOPPED', stop_reason=str(error))
        exit_code = 2
    finally:
        result = {}
        result_state = 'NO_TEST_COMMAND' if state['test_commands'] == 0 else 'XCRESULT_NOT_PRODUCED'
        bundle = evidence / 'ComposerNative.xcresult'
        try:
            if state['test_commands'] == 1 and bundle.is_dir():
                result_state = 'EXPORT_NOT_CONFIRMED'
                export_status = runner.call('actual-tests-export', 120, ['xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', str(bundle), '--format', 'json'], required=False)
                if export_status == 0:
                    result = runner.json('actual-tests-export')
                    result_state = 'ACTUAL_XCRESULT_EXPORTED'
            log_path = evidence / 'native-test.stdout'
            stderr_path = evidence / 'native-test.stderr'
            trace_lines = []
            for path in [log_path, stderr_path]:
                if path.exists():
                    with path.open(encoding='utf-8', errors='replace') as stream:
                        trace_lines.extend(line for line in stream if 'signedDelta=' in line)
            actual_results = observations(result, expected, device, trace_lines)
            actual_results['raw_result_availability'] = result_state
            runner.save('case-observations.json', actual_results)
            state['apple_pass_claim'] = state['test_commands'] == 1 and exit_code == 0 and actual_results['all_12_unique_pass_on_owned_device']
            if state['test_commands'] and not state['apple_pass_claim'] and exit_code == 0:
                exit_code = 2
        except (ValueError, OSError, KeyError, json.JSONDecodeError) as error:
            unavailable = observations({}, expected, device)
            unavailable['raw_result_availability'] = 'EXPORT_OR_CLASSIFICATION_FAILED'
            runner.save('case-observations.json', unavailable)
            state['result_export_or_classification_error'] = str(error)
            exit_code = 2
        # Never erase/delete, reuse another phone, or mutate global Xcode selection.
        if device and re.fullmatch(r'[0-9A-Fa-f-]{36}', device) and (evidence / 'owned-device.json').is_file():
            try:
                state['owned_shutdown_exit_code'] = runner.call('shutdown-owned-device', 60, ['xcrun', 'simctl', 'shutdown', device], required=False)
            except (ValueError, OSError) as error:
                state['owned_shutdown_error'] = str(error)
        state.update(finished_at_utc=stamp(), runner_exit_code=exit_code)
        runner.save('run-state.json', state)
        print(json.dumps(state, indent=2))
    return exit_code


if __name__ == '__main__':
    def interrupted(signum, frame):
        raise InterruptedError('runner interrupted by signal ' + str(signum))
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        sys.exit(execute())
    except (ValueError, OSError) as error:
        sys.exit(str(error))
