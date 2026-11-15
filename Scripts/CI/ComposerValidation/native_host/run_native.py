"""One guarded native-project diagnostic. Manual CI only, after final source approval."""
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import shutil
import socket
import subprocess
import sys
import tarfile
import tempfile
import time
from datetime import datetime, timezone

sys.dont_write_bytecode = True
import prepare_native as native
from guards import (native_settings, environment, destination, require, require_pretest,
                    focused_observations, classify_execution_status)
from precreated_readiness import runner_instance, claim_precreated, readiness_help, CONTRACT, READINESS_SECONDS


XCODE = '/Applications/Xcode_27.2.app/Contents/Developer'
TEST_SECONDS = 900
RUN_SECONDS = 2100
FOCUSED_CASE = 'NativeComposerLineSizingTests/wrappedLinesAndScrolling()'
FOCUSED_SELECTOR = 'AI_HanlinTests/' + FOCUSED_CASE
REMAINING_NATIVE_CASES = (
    'NativeComposerLineSizingTests/editingKeepsDraftAndSelection()',
    'NativeComposerLineSizingTests/textKit2WrappedLinesKeepNativeLayout()',
    'NativeComposerLineSizingTests/textKit2ParagraphCoverageAndConservativeFallback()',
    'NativeComposerLineSizingTests/fontAndViewport()',
)


def selected_cases(raw):
    if not raw.strip():
        return (FOCUSED_CASE,)
    prefix = 'AI_HanlinTests/'
    requested = tuple(item.strip().removeprefix(prefix) for item in raw.split(','))
    require(requested in [(FOCUSED_CASE,), REMAINING_NATIVE_CASES],
            'only the failing method or its four remaining native regressions may be selected')
    return requested



def stamp():
    return datetime.now(timezone.utc).isoformat()


def command_plan(project_dir, sdk, device, scratch, evidence, selected=(FOCUSED_CASE,)):
    base = ['xcodebuild', '-project', str(project_dir / native.PROJECT), '-scheme', native.SCHEME,
            '-configuration', 'Debug', '-sdk', sdk, '-derivedDataPath', str(scratch / 'DerivedData')]
    # The concrete destination selects the architecture. Xcode rejects -arch
    # alongside -destination (run 43714792439, exit 64 before any test).
    owned = ['-destination', 'platform=iOS Simulator,id=' + device]
    return {
        'settings': [*base, 'test', '-showBuildSettings', '-json', *owned, 'ONLY_ACTIVE_ARCH=YES'],
        'destinations': [*base, '-showdestinations'],
        'test': [*base, 'test', *owned, '-showBuildTimingSummary', '-destination-timeout', '30',
                 '-parallel-testing-enabled', 'NO', '-maximum-concurrent-test-simulator-destinations', '1',
                 '-maximum-parallel-testing-workers', '1',
                 '-resultBundlePath', str(evidence / 'ComposerNative.xcresult'),
                 *['-only-testing:AI_HanlinTests/' + case for case in selected], 'ONLY_ACTIVE_ARCH=YES', 'CODE_SIGNING_ALLOWED=NO'],
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
    selected = selected_cases(os.environ.get('COMPOSER_NATIVE_SELECTORS', ''))
    selectors = ['AI_HanlinTests/' + case for case in selected]
    require(set(selected).issubset(expected) and len(set(expected)) == 12, 'selection must bind frozen authored identities')
    state = {'scope': 'native-hosted Composer previously failing method diagnostic' if len(selected) == 1 else 'remaining four native editor regressions', 'full_app_acceptance': False,
             'authored_inventory_count': 12, 'selected_case_ids': list(selected), 'xcodebuild_only_testing_selectors': selectors,
             'product_composer_acceptance': 'OPEN',
             'started_at_utc': stamp(), 'status': 'PREPARING', 'test_commands': 0,
             'native_settings_confirmed': False, 'owned_sdk_destination_confirmed': False,
             'owned_readiness_help_confirmed': False, 'owned_boot_confirmed': False,
             'precreated_instance_ownership_confirmed': False, 'owned_display_confirmed': False,
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
        if runner.call('pattern-source-present', 30, ['git', 'cat-file', '-e', native.PATTERN_SOURCE + ':Scripts/CI/SimulatorAcceptance/prepare_parity_project.py'], required=False):
            runner.call('fetch-pattern-source', 120, ['git', 'fetch', '--no-tags', '--depth=1', 'origin', native.PATTERN_SOURCE])
        runner.call('frozen-source-review-check', 120, [sys.executable, '-B', str(native.HERE / 'freeze_review.py'), '--check'])
        runner.call('final-guard-review-check', 120, [sys.executable, '-B', str(native.HERE / 'review_guard.py'), '--check'])
        require(Path(XCODE, 'usr/bin/xcodebuild').is_file(), 'exact installed Xcode missing; no selection/install fallback')
        free = shutil.disk_usage(native.REPO).free
        runner.save('disk-space.json', {'free_bytes': free, 'minimum_bytes': 5 * 1024**3})
        require(free >= 5 * 1024**3, 'insufficient Mac disk space for focused build')
        skill_dirs = [Path.home() / '.codex/skills/ios-simulator-skill', Path.home() / '.agents/skills/ios-simulator-skill']
        runner.save('supplemental-tools.json', {'idb': shutil.which('idb'), 'maestro': shutil.which('maestro'),
            'skill_scripts_present': [str(p) for p in skill_dirs if (p / 'scripts/sim_health_check.sh').is_file()],
            'missing_optional_tools_block_xctest': False})
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
        runner.save('focused-selection.json', {'authored_case_ids': expected, 'selected_case_ids': list(selected),
                    'xcodebuild_only_testing_selectors': selectors, 'selected_expected_count': len(selected),
                    'other_authored_cases_expected': 'NOT_RUN in this invocation; no reused passes',
                    'unselected_authored_count': len(expected) - len(selected),
                    'selector_matching_basis': 'frozen method identity; actual matching must be confirmed by xcresult, zero => BLOCKED without retry'})
        # Retain whole original source and generated native inputs on the remote runner only.
        with tarfile.open(evidence / 'native-source-inputs.tar', 'w') as archive:
            archive.add(project_dir, arcname='NativeHost')
        workflow = native.REPO / '.github/workflows/build-ios26-unsigned-ipa.yml'
        harness = [*sorted(p for p in native.HERE.rglob('*') if p.is_file()), workflow]
        runner.save('harness-sha256.json', {p.relative_to(native.REPO).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in harness})
        runner.call('installed-bootstatus-help', 30, ['xcrun', 'simctl', 'help', 'bootstatus'])
        runner.call('installed-io-help', 30, ['xcrun', 'simctl', 'help', 'io'])
        def help_text(label):
            return runner.text(label) + (evidence / (label + '.stderr')).read_text(encoding='utf-8', errors='replace')
        runner.save('installed-readiness-help-guard.json', readiness_help(help_text('installed-bootstatus-help'), help_text('installed-io-help')))
        state['owned_readiness_help_confirmed'] = True
        runner.call('host-boot-session', 15, ['sysctl', '-n', 'kern.bootsessionuuid'])
        runner.call('host-os-image-build', 15, ['sw_vers', '-buildVersion'])
        context = {key: os.environ.get(key) for key in ['GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT', 'GITHUB_JOB',
                    'RUNNER_ENVIRONMENT', 'RUNNER_OS', 'RUNNER_ARCH', 'RUNNER_NAME', 'ImageOS', 'ImageVersion']}
        instance = runner_instance(context, runner.text('host-boot-session').strip(),
                                   runner.text('host-os-image-build').strip(), socket.gethostname())
        runner.save('runner-instance.json', instance)
        runner.call('simulators-before', 30, ['xcrun', 'simctl', 'list', '-j'])
        before = runner.json('simulators-before')
        runtime, model = environment(before)
        ownership = claim_precreated(before, instance)
        device = ownership['udid']
        runner.save('owned-device.json', ownership)
        state['precreated_instance_ownership_confirmed'] = True
        runner.save('installed-environment.json', {'runtime': runtime, 'device_type': model, 'sdk_path': sdk,
                'Xcode': '27.2/27B52', 'DEVELOPER_DIR': XCODE, 'environment_contract': CONTRACT,
                'runtime27_0_acceptance': 'NOT_COVERED', 'prior_infra_run': '43723707247'})
        plan = command_plan(project_dir, sdk, device, scratch, evidence, selected)
        runner.save('native-command-plan.json', plan)
        runner.call('installed-xcodebuild-help', 30, ['xcodebuild', '-help'], required=False)
        runner.call('native-schemes', 30, ['xcodebuild', '-list', '-json', '-project', str(project_dir / native.PROJECT)])
        require(native.SCHEME in runner.json('native-schemes').get('project', {}).get('schemes', []), 'generated native scheme missing')
        runner.call('native-target-build-settings', 120, plan['settings'])
        settings_receipt = native_settings(runner.json('native-target-build-settings'), sdk)
        runner.save('native-settings-guard.json', settings_receipt)
        state['native_settings_confirmed'] = True
        state['status'] = 'PRECREATED_SETTINGS_CONFIRMED_NOT_READY'
        runner.save('run-state.json', state)
        readiness_start = time.monotonic()
        readiness_deadline = readiness_start + READINESS_SECONDS
        def ready_budget(reserve=0):
            remaining = int(readiness_deadline - time.monotonic()) - reserve
            require(remaining > 5, 'bounded precreated readiness budget exhausted; no test')
            return remaining
        runner.call('readiness-host-memory-before', 15, ['vm_stat'], required=False)
        if ownership['initial_state'] != 'Booted':
            runner.call('boot-owned-device', 30, ['xcrun', 'simctl', 'boot', device])
        # One event-based blocking boot, one display request, one eligibility
        # query share 600s. No sleeps, retry loop or repeated name enumeration.
        runner.call('bootstatus-owned-device', min(480, ready_budget(90)), ['xcrun', 'simctl', 'bootstatus', device, '-b'])
        state['owned_boot_confirmed'] = True
        runner.call('readiness-host-memory-after-boot', 15, ['vm_stat'], required=False)
        runner.call('owned-boot-screenshot', ready_budget(45), ['xcrun', 'simctl', 'io', device, 'screenshot', str(evidence / 'owned-boot.png')])
        require((evidence / 'owned-boot.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n'), 'actual owned display screenshot missing/invalid')
        state['owned_display_confirmed'] = True
        if shutil.which('idb'):
            runner.call('owned-accessibility-tree', min(30, ready_budget(30)), ['idb', 'ui', 'describe-all', '--udid', device, '--json'], required=False)
        runner.call('native-sdk-destinations', ready_budget(), plan['destinations'])
        eligibility = destination(runner.text('native-sdk-destinations'),
                                  (evidence / 'native-sdk-destinations.stderr').read_text(encoding='utf-8', errors='replace'), device)
        runner.save('owned-sdk-destination-guard.json', eligibility)
        state['owned_sdk_destination_confirmed'] = True
        runner.save('precreated-readiness.json', {'status': 'ACTUAL_OWNED_DISPLAY_AND_SDK_ELIGIBILITY_CONFIRMED',
            'contract': CONTRACT, 'ownership_instance_fingerprint': instance['instance_fingerprint'], 'device': device,
            'initial_state': ownership['initial_state'], 'elapsed_seconds': round(time.monotonic() - readiness_start, 3),
            'budget_seconds': READINESS_SECONDS, 'screenshot': 'owned-boot.png', 'AX_available': bool(shutil.which('idb')),
            'state_basis': 'actual exact-device blocking bootstatus + display PNG + native SDK destination',
            'no_readiness_claim_from_initial_available_flag': True})
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
        actual_results = {}
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
            actual_results = focused_observations(result, expected, selected, device, trace_lines)
            actual_results['raw_result_availability'] = result_state
            runner.save('case-observations.json', actual_results)
            state['apple_pass_claim'] = state['test_commands'] == 1 and exit_code == 0 and actual_results['all_selected_unique_pass_on_owned_device']
            if state['test_commands'] and not state['apple_pass_claim'] and exit_code == 0:
                exit_code = 2
        except (ValueError, OSError, KeyError, json.JSONDecodeError) as error:
            unavailable = focused_observations({}, expected, selected, device)
            unavailable['raw_result_availability'] = 'EXPORT_OR_CLASSIFICATION_FAILED'
            runner.save('case-observations.json', unavailable)
            state['result_export_or_classification_error'] = str(error)
            exit_code = 2
        if exit_code:
            try:
                runner.call('failure-host-memory', 15, ['vm_stat'], required=False)
                runner.call('failure-host-disk', 15, ['df', '-h'], required=False)
                runner.call('failure-host-processes', 15, ['ps', '-axo', 'pid,ppid,pcpu,pmem,stat,comm'], required=False)
                runner.call('failure-coresimulator-logs', 30, ['log', 'show', '--last', '2m', '--style', 'compact', '--predicate', 'process == "CoreSimulatorService" OR subsystem BEGINSWITH "com.apple.CoreSimulator"'], required=False)
            except (ValueError, OSError) as error:
                state['host_diagnostics_error'] = str(error)
        bootstatus_returned = any(command['label'] == 'bootstatus-owned-device' and command['exit_code'] == 0
                                  for command in runner.commands)
        # Even if the subsequent state query fails, try bounded diagnostics of
        # our run-instance-owned precreated UUID. This does not relax the pretest readiness predicate.
        if exit_code and device and bootstatus_returned:
            try:
                display_already_failed = any(c['label'] == 'owned-boot-screenshot' and c['exit_code'] != 0 for c in runner.commands)
                if not display_already_failed:
                    runner.call('failure-screenshot', 30, ['xcrun', 'simctl', 'io', device, 'screenshot', str(evidence / 'failure.png')], required=False)
                else:
                    state['failure_screenshot'] = 'NOT_AVAILABLE: bounded display request already failed; no identical retry'
                runner.call('failure-simulator-logs', 30, ['xcrun', 'simctl', 'spawn', device, 'log', 'show', '--last', '2m', '--style', 'compact', '--predicate', 'process == "AI_Hanlin"'], required=False)
                if shutil.which('idb'):
                    runner.call('failure-accessibility-tree', 30, ['idb', 'ui', 'describe-all', '--udid', device, '--json'], required=False)
                else:
                    state['failure_accessibility_tree'] = 'NOT_AVAILABLE: optional idb CLI absent; component test host has no production UI'
            except (ValueError, OSError) as error:
                state['failure_capture_error'] = str(error)
        build_log = ''.join((evidence / ('native-test.' + stream)).read_text(encoding='utf-8', errors='replace')
                            for stream in ['stdout', 'stderr'] if (evidence / ('native-test.' + stream)).is_file())
        state['execution_status'] = classify_execution_status(state['test_commands'], exit_code, actual_results, build_log)
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
