"""Portable admission controls for the original standalone notification OS route.

These use ordinary temporary files and controlled child-process objects. They
are not XCTest, simulator, notification, or installed-engine acceptance.
"""
from pathlib import Path
import copy
import hashlib
import importlib.util
import io
import json
import os
import plistlib
import shutil
import sys
import tempfile
import time
import unittest
import uuid
from types import SimpleNamespace
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = ROOT / 'Scripts/ProductSplit'
# Loading the actual runner must not leak its command environment or helper
# import paths into the original shared CI discovery process.
with patch.dict(os.environ, {'SPLIT_EVIDENCE': '/unused-notification-controls'}), \
        patch.object(sys, 'path', [str(SCRIPTS), *sys.path]), patch.dict(sys.modules):
    spec = importlib.util.spec_from_file_location('notification_native_runner_controls', SCRIPTS / 'run_native_acceptance.py')
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)


class NotificationScopeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / 'source'
        self.evidence = self.root / 'evidence'
        self.evidence.mkdir()
        self.home = self.root / 'home'
        self.device = str(uuid.uuid4()).upper()
        self.sha = 'a' * 40
        self.derived = self.root / 'derived'
        self.active = {'version': 1, 'runID': str(uuid.uuid4()),
                       'challenge': 'notification-os-' + str(uuid.uuid4())}
        # Isolate wall-clock/mtime ordering from the host clock. Only this
        # runner module receives the fixture clock; the global time module and
        # the original monotonic deadline controls remain unchanged.
        self.wall_clock = 1_700_000_000.0
        clock_patch = patch.object(runner, 'time', SimpleNamespace(
            time=lambda: self.wall_clock, monotonic=time.monotonic, sleep=time.sleep))
        clock_patch.start()
        self.addCleanup(clock_patch.stop)
        self.started = self.wall_clock - 1
        self.state = {'sha': self.sha, 'simulator': self.device, 'build': 'EXECUTED_PASS',
                      'reused_passes': [],
                      'simulator_signing': 'ORIGINAL_ENTITLEMENTS_VERIFIED_AD_HOC_NOT_DISTRIBUTION_SIGNING'}
        self.argv = ['xcodebuild', '-parallel-testing-enabled', 'NO', 'test-without-building',
                     '-only-testing:' + runner.UI_PLANS['notification_os'][0][0]]
        root_patch = patch.object(runner, 'ROOT', self.source)
        evidence_patch = patch.object(runner, 'EVIDENCE', self.evidence)
        home_patch = patch.object(Path, 'home', return_value=self.home)
        env_patch = patch.dict(os.environ, {'SPLIT_REUSE_NATIVE_PROOF': '0'})
        for item in (root_patch, evidence_patch, home_patch, env_patch):
            item.start()
            self.addCleanup(item.stop)
        self.inputs = {}
        for name in [runner.NOTIFICATION_WORKER, 'Scripts/ProductSplit/run_native_acceptance.py',
                     'HanlinMiniAppsUITests/HanlinMiniAppsUITests.swift']:
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('bound source for ' + name)
            self.inputs[name] = runner.notification_file(path)['sha256']
        self.write(self.evidence / 'source-identity.json', {
            'commit': self.sha, 'tracked_file_sha256': self.inputs,
            'preparation_diff_sha256': hashlib.sha256(b'').hexdigest()})
        (self.evidence / 'created-simulator.txt').write_text(self.device + '\n')
        self.git = patch.object(runner.subprocess, 'check_output', side_effect=self.git_read)
        self.git.start()
        self.addCleanup(self.git.stop)
        products = self.derived / 'Build/Products/Debug-iphonesimulator'
        self.app = products / 'HanlinMiniApps.app'
        self.test_runner = products / 'HanlinMiniAppsUITests-Runner.app'
        self.make_bundle(self.app, runner.NOTIFICATION_APP, 'HanlinMiniApps', {
            'HanlinExtensionHost': {'StorageNamespace': 'HanlinMiniApps/v1',
                                   'AppGroupIdentifier': 'group.com.itorah.chavrusachat'}})
        self.make_bundle(self.test_runner, runner.NOTIFICATION_RUNNER, 'Runner')
        self.make_bundle(self.test_runner / 'PlugIns/HanlinMiniAppsUITests.xctest',
                         runner.NOTIFICATION_RUNNER.removesuffix('.xctrunner'), 'HanlinMiniAppsUITests')
        (self.app / 'HanlinMiniApps.debug.dylib').write_bytes(b'current application code')
        self.containers = self.home / 'Library/Developer/CoreSimulator/Devices' / self.device / 'data/Containers'
        self.paths = {}
        for role, identifier, kind in [('runnerData', runner.NOTIFICATION_RUNNER, 'Data/Application'),
                                       ('appData', runner.NOTIFICATION_APP, 'Data/Application'),
                                       ('appGroup', 'group.com.itorah.chavrusachat', 'Shared/AppGroup')]:
            path = self.containers / kind / str(uuid.uuid4()).upper()
            path.mkdir(parents=True)
            (path / '.com.apple.mobile_container_manager.metadata.plist').write_bytes(plistlib.dumps({
                'MCMMetadataIdentifier': identifier, 'MCMMetadataUUID': str(uuid.uuid4()).upper()}))
            self.paths[role] = path
        for role, source in [('app', self.app), ('runner', self.test_runner)]:
            destination = self.containers / 'Bundle/Application' / str(uuid.uuid4()).upper() / source.name
            shutil.copytree(source, destination)
            self.paths[role + 'Bundle'] = destination
        for relative in runner.NOTIFICATION_FIXTURES:
            original = self.source / relative
            original.parent.mkdir(parents=True, exist_ok=True)
            original.write_bytes(('ordinary input: ' + relative).encode())
            destination = self.paths['appData'] / 'Documents' / original.name
            destination.parent.mkdir(exist_ok=True)
            shutil.copyfile(original, destination)

    def write(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value, sort_keys=True, indent=2) + '\n')
        self.wall_clock += 1
        os.utime(path, (self.wall_clock, self.wall_clock))

    @staticmethod
    def make_bundle(path, identifier, executable, extra=None):
        path.mkdir(parents=True)
        (path / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': identifier, 'CFBundleExecutable': executable, **(extra or {})}))
        (path / executable).write_bytes(('original binary:' + identifier).encode())

    def git_read(self, argv, **unused):
        return (self.sha + '\n').encode() if argv[1] == 'rev-parse' else b''

    def probe(self, bundle, kind):
        if kind == 'data':
            return self.paths['runnerData' if bundle == runner.NOTIFICATION_RUNNER else 'appData']
        if kind == 'app':
            return self.paths['runnerBundle' if bundle == runner.NOTIFICATION_RUNNER else 'appBundle']
        self.assertEqual(kind, 'group.com.itorah.chavrusachat')
        return self.paths['appGroup']

    def roots(self):
        return runner.notification_containers(self.device, runner.notification_products(self.derived), self.probe)

    def exchange(self):
        path = self.paths['runnerData'] / 'Documents/HanlinNotificationOSProbe'
        self.write(path / 'active.json', self.active)
        return path

    def completion_fixture(self):
        output = self.evidence / 'notification-os'
        exchange = self.exchange()
        run_directory = exchange / self.active['runID']
        self.write(output / 'active.json', self.active)
        terminal = {**self.active, 'status': 'EXECUTED_PASS'}
        self.write(output / 'ui-finished.json', terminal)
        # The original Swift writer and Python worker intentionally use different
        # JSON whitespace; the unchanged payload must remain admissible.
        (run_directory).mkdir(parents=True, exist_ok=True)
        (run_directory / 'ui-finished.json').write_text(json.dumps(terminal, separators=(',', ':')))
        self.write(output / 'observation-result.json', {**terminal, 'requiresSeparateXCTestTerminalResult': True})
        for runtime, package, kinds in [('expo', 'Expo SwiftUI Probe A', ['success', 'duplicate', 'failure']),
                                        ('nativescript', 'HanlinScript Parity', ['success', 'duplicate'])]:
            self.write(output / (runtime + '.request.json'), {**self.active, 'runtime': runtime, 'packageName': package})
            rows = []
            event_id = str(uuid.uuid4())
            for kind in kinds:
                if kind == 'failure':
                    event_id = str(uuid.uuid4())
                receipt = {'invocationID': event_id, 'attempt': 1, 'cancellationRequested': False,
                           'status': 'failed' if kind == 'failure' else 'succeeded'}
                receipt.update({'failure': 'actionFailed'} if kind == 'failure' else {'value': {'type': 'null'}})
                record = {'id': event_id, 'receipt': receipt}
                path = self.paths['appGroup'] / 'HanlinMiniApps/v1/ScriptingExtensions/ResumeQueue/Receipts' / (event_id + '.json')
                self.write(path, record)
                prefix = output / runtime / kind
                raw = path.read_bytes()
                record_copy = prefix.with_name(kind + '-record.json')
                record_copy.parent.mkdir(parents=True, exist_ok=True)
                record_copy.write_bytes(raw)
                payload = prefix.with_suffix('.apns')
                self.write(payload, {'hanlin-miniapp-event': {'id': event_id}})
                push = {'command': ['xcrun', 'simctl', 'push', self.device, runner.NOTIFICATION_APP, str(payload)],
                        'returncode': 0, 'stdoutSHA256': hashlib.sha256(b'').hexdigest(),
                        'stderrSHA256': hashlib.sha256(b'').hexdigest()}
                for stream in ('stdout', 'stderr'):
                    prefix.with_name(kind + '-push.' + stream).write_bytes(b'')
                self.write(prefix.with_name(kind + '-push.json'), push)
                rows.append({'kind': kind, 'pushExitCode': 0, 'push': push,
                             'recordPath': str(path), 'recordSHA256': hashlib.sha256(raw).hexdigest(),
                             'record': record, 'duplicateCallbackIndependentlyObserved': False if kind == 'duplicate' else None})
            completion = {**self.active, 'runtime': runtime, 'transport': 'simctl_push',
                          'status': 'EXECUTED_PASS', 'observations': rows}
            self.write(output / (runtime + '.complete.json'), completion)
            self.write(run_directory / (runtime + '.complete.json'), completion)
        return {'status': 'PROCESSES_EXITED_ZERO_REQUIRES_XCTEST_AND_FIVE_OBSERVATIONS',
                'testExitCode': 0, 'workerExitCode': 0, 'stopReason': None,
                'device': self.device, 'active': self.active, 'startedAfter': self.started, 'containers': self.roots()}

    def test_missing_build_reuse_wrong_selector_and_parallelism_never_launch(self):
        cases = []
        for key, value in [('build', 'NOT_RUN'), ('reused_passes', ['previous']), ('simulator_signing', 'UNSIGNED')]:
            state = {**self.state, key: value}
            cases.append((self.argv, state))
        cases += [(self.argv[:-1], self.state), ([*self.argv, '-only-testing:Other/Test'], self.state),
                  ([value if value != 'NO' else 'YES' for value in self.argv], self.state)]
        for argv, state in cases:
            with self.subTest(argv=argv, state=state), patch.object(runner.subprocess, 'Popen') as launch:
                with self.assertRaises(RuntimeError):
                    runner.run_notification_test(argv, io.BytesIO(), state, self.derived, self.inputs)
                launch.assert_not_called()

    def test_wrong_source_missing_worker_or_changed_prepared_diff_never_launch(self):
        for mutation in ('commit', 'worker', 'diff'):
            with self.subTest(mutation=mutation), patch.object(runner.subprocess, 'Popen') as launch:
                inputs = dict(self.inputs)
                state = dict(self.state)
                if mutation == 'commit':
                    state['sha'] = 'b' * 40
                if mutation == 'worker':
                    inputs.pop(runner.NOTIFICATION_WORKER)
                side_effect = self.git_read if mutation != 'diff' else lambda argv, **kw: (self.sha + '\n').encode() if argv[1] == 'rev-parse' else b'changed fixture diff'
                with patch.object(runner.subprocess, 'check_output', side_effect=side_effect), self.assertRaises(RuntimeError):
                    runner.run_notification_test(self.argv, io.BytesIO(), state, self.derived, inputs)
                launch.assert_not_called()

    def test_wrong_created_device_or_prior_result_never_launch(self):
        with patch.object(runner.subprocess, 'Popen') as launch:
            (self.evidence / 'created-simulator.txt').write_text(str(uuid.uuid4()).upper())
            with self.assertRaises(RuntimeError):
                runner.run_notification_test(self.argv, io.BytesIO(), self.state, self.derived, self.inputs)
            (self.evidence / 'created-simulator.txt').write_text(self.device)
            (self.evidence / 'MiniApps.xcresult').mkdir()
            with self.assertRaises(RuntimeError):
                runner.run_notification_test(self.argv, io.BytesIO(), self.state, self.derived, self.inputs)
            launch.assert_not_called()

    def test_current_metadata_binds_both_containers_without_equating_directory_and_metadata_uuid(self):
        roots = self.roots()
        self.assertNotEqual(Path(roots['runnerData']['path']).name.lower(), roots['runnerData']['metadataUUID'])
        metadata = self.paths['runnerData'] / '.com.apple.mobile_container_manager.metadata.plist'
        original = metadata.read_bytes()
        value = plistlib.loads(original)
        value['MCMMetadataIdentifier'] = runner.NOTIFICATION_APP
        metadata.write_bytes(plistlib.dumps(value))
        with self.assertRaises(RuntimeError):
            self.roots()
        metadata.write_bytes(original)
        with patch.object(Path, 'home', return_value=self.root / 'other-owner'), self.assertRaises(RuntimeError):
            self.roots()

    def test_installed_debug_code_test_binary_and_post_xctest_fixture_must_match(self):
        paths = [self.paths['appBundle'] / 'HanlinMiniApps.debug.dylib',
                 self.paths['runnerBundle'] / 'PlugIns/HanlinMiniAppsUITests.xctest/HanlinMiniAppsUITests',
                 self.paths['appData'] / 'Documents/ExpoSwiftUIProbeA.hanlinExpo']
        for path in paths:
            old = path.read_bytes()
            path.write_bytes(b'wrong current input')
            with self.subTest(path=path), self.assertRaises(RuntimeError):
                self.roots()
            path.write_bytes(old)

    def test_stale_future_nonfinite_or_coerced_active_identity_is_rejected(self):
        path = self.exchange() / 'active.json'
        for start in (float('nan'), float('inf'), -1, time.time() + 60):
            with self.subTest(start=start), self.assertRaises(RuntimeError):
                runner.notification_active(path, start)
        os.utime(path, (self.started - 10, self.started - 10))
        with self.assertRaises(RuntimeError):
            runner.notification_active(path, self.started)
        for value in ({**self.active, 'version': True}, {**self.active, 'runID': self.active['runID'].upper()},
                      {**self.active, 'challenge': 'notification-os-not-a-uuid'}):
            self.write(path, value)
            with self.subTest(value=value), self.assertRaises(RuntimeError):
                runner.notification_active(path, self.started)

    def test_complete_original_five_observations_require_both_actual_process_results(self):
        controller = self.completion_fixture()
        result = runner.validate_notification_observations(controller)
        self.assertEqual((result['originalXCTestCases'], result['pushObservations'], result['uniqueNativeEvents']), (1, 5, 3))
        for key, value in [('testExitCode', 1), ('workerExitCode', 1), ('workerExitCode', False),
                           ('stopReason', 'ORIGINAL_DEADLINE_EXCEEDED'), ('status', 'RUNNING')]:
            with self.subTest(key=key, value=value), self.assertRaises(RuntimeError):
                runner.validate_notification_observations({**controller, key: value})

    def test_foreign_run_missing_observation_and_bool_version_cannot_pass(self):
        controller = self.completion_fixture()
        path = self.evidence / 'notification-os/expo.complete.json'
        exchange = self.paths['runnerData'] / 'Documents/HanlinNotificationOSProbe' / self.active['runID'] / 'expo.complete.json'
        original = json.loads(path.read_bytes())
        for change in ({'runID': str(uuid.uuid4())}, {'version': True}, {'observations': original['observations'][:-1]}):
            value = {**original, **change}
            self.write(path, value)
            self.write(exchange, value)
            with self.subTest(change=change), self.assertRaises(RuntimeError):
                runner.validate_notification_observations(controller)
        self.write(path, original)
        self.write(exchange, original)
        actual = self.paths['runnerData'] / 'Documents/HanlinNotificationOSProbe/active.json'
        self.write(actual, {**self.active, 'runID': str(uuid.uuid4())})
        with self.assertRaises(RuntimeError):
            runner.validate_notification_observations(controller)

    def test_changed_durable_receipt_or_wrong_product_store_cannot_pass(self):
        controller = self.completion_fixture()
        completion = json.loads((self.evidence / 'notification-os/expo.complete.json').read_bytes())
        path = Path(completion['observations'][0]['recordPath'])
        original = path.read_bytes()
        path.write_bytes(original + b' ')
        with self.assertRaises(RuntimeError):
            runner.validate_notification_observations(controller)
        path.write_bytes(original)
        wrong = copy.deepcopy(controller)
        wrong['containers']['appGroup']['path'] = str(self.root / 'other-product')
        with self.assertRaises(RuntimeError):
            runner.validate_notification_observations(wrong)

    def test_push_command_and_raw_output_are_bound_to_the_owned_device(self):
        controller = self.completion_fixture()
        path = self.evidence / 'notification-os/expo/success-push.stdout'
        path.write_bytes(b'changed retained command output')
        with self.assertRaises(RuntimeError):
            runner.validate_notification_observations(controller)
        path.write_bytes(b'')
        wrong = {**controller, 'device': str(uuid.uuid4()).upper()}
        with self.assertRaises(RuntimeError):
            runner.validate_notification_observations(wrong)

    def test_actual_failed_result_and_duplicate_semantics_cannot_be_relabelled(self):
        controller = self.completion_fixture()
        output = self.evidence / 'notification-os'
        path = output / 'expo.complete.json'
        exchange = self.paths['runnerData'] / 'Documents/HanlinNotificationOSProbe' / self.active['runID'] / 'expo.complete.json'
        original = json.loads(path.read_bytes())
        changed = copy.deepcopy(original)
        changed['observations'][1]['duplicateCallbackIndependentlyObserved'] = True
        self.write(path, changed)
        self.write(exchange, changed)
        with self.assertRaises(RuntimeError):
            runner.validate_notification_observations(controller)
        changed = copy.deepcopy(original)
        row = changed['observations'][2]
        row['record']['receipt'].update(status='succeeded', value={'type': 'null'})
        self.write(Path(row['recordPath']), row['record'])
        raw = Path(row['recordPath']).read_bytes()
        (output / 'expo/failure-record.json').write_bytes(raw)
        row['recordSHA256'] = hashlib.sha256(raw).hexdigest()
        self.write(path, changed)
        self.write(exchange, changed)
        with self.assertRaises(RuntimeError):
            runner.validate_notification_observations(controller)

    def test_worker_starts_only_after_actual_fresh_ui_exchange_and_uses_original_budgets(self):
        children = []

        class Child:
            def __init__(self, pid):
                self.pid = pid
                self.returncode = None

            def poll(self):
                return self.returncode

        def launch(argv, **kwargs):
            self.assertTrue(kwargs['start_new_session'])
            child = Child(100 + len(children))
            children.append((argv, child))
            if len(children) == 1:
                self.assertEqual(argv, self.argv)
                self.exchange()  # Controlled stand-in for the actual UI writer.
            else:
                self.assertEqual(argv[1], str(self.source / runner.NOTIFICATION_WORKER))
                self.assertEqual(argv[argv.index('--runner-data') + 1], str(self.paths['runnerData']))
                self.assertEqual(argv[argv.index('--app-data') + 1], str(self.paths['appData']))
                self.assertEqual(argv[-2:], ['--timeout', '650'])
                child.returncode = 0
                children[0][1].returncode = 0
            return child

        def command(argv, name, timeout):
            self.assertEqual(timeout, 5)
            return str(self.probe(argv[-2], argv[-1])) + '\n'

        with patch.object(runner.subprocess, 'Popen', side_effect=launch), \
                patch.object(runner, 'command', side_effect=command), patch.object(runner.time, 'sleep'):
            result = runner.run_notification_test(self.argv, io.BytesIO(), self.state, self.derived, self.inputs)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(len(children), 2)
        controller = self.state['notification_os_controller']
        self.assertEqual((controller['testAllowanceSeconds'], controller['workerTimeoutSeconds'],
                          controller['testCommandTimeoutSeconds']), (600, 650, 1200))
        self.assertNotEqual(controller['status'], 'EXECUTED_PASS')


    def test_worker_deadline_stops_only_its_owned_children_and_zero_exit_cannot_pass(self):
        clock = [0.0]
        children = []
        stopped = []

        class Child:
            def __init__(self, pid):
                self.pid = pid
                self.returncode = None

            def poll(self):
                return self.returncode

            def wait(self, timeout):
                return self.returncode

        def launch(argv, **kwargs):
            self.assertTrue(kwargs['start_new_session'])
            child = Child(200 + len(children))
            children.append(child)
            if len(children) == 1:
                self.exchange()
            return child

        def stop(pid, sig):
            stopped.append((pid, sig))
            next(child for child in children if child.pid == pid).returncode = 0

        def advance(seconds):
            clock[0] += 651

        with patch.object(runner.subprocess, 'Popen', side_effect=launch), \
                patch.object(runner, 'command', side_effect=lambda argv, name, timeout: str(self.probe(argv[-2], argv[-1]))), \
                patch.object(runner.time, 'monotonic', side_effect=lambda: clock[0]), \
                patch.object(runner.time, 'sleep', side_effect=advance), patch.object(runner.os, 'killpg', side_effect=stop):
            runner.run_notification_test(self.argv, io.BytesIO(), self.state, self.derived, self.inputs)
        self.assertEqual([pid for pid, sig in stopped], [201, 200])
        self.assertTrue(all(sig == runner.signal.SIGTERM for pid, sig in stopped))
        controller = self.state['notification_os_controller']
        self.assertEqual(controller['stopReason'], 'ORIGINAL_DEADLINE_EXCEEDED')
        self.assertEqual((controller['testExitCode'], controller['workerExitCode']), (0, 0))
        with self.assertRaises(RuntimeError):
            runner.validate_notification_observations(controller)


    def test_exited_child_race_or_one_cleanup_error_still_stops_other_child_and_persists_receipt(self):
        for mode in ('exited-between-poll-and-signal', 'one-cleanup-error'):
            with self.subTest(mode=mode):
                clock = [0.0]
                children = []
                stopped = []
                receipt_path = self.evidence / 'notification-controller.json'
                receipt_path.unlink(missing_ok=True)

                class Child:
                    def __init__(self, pid):
                        self.pid = pid
                        self.returncode = None

                    def poll(self):
                        return self.returncode

                    def wait(self, timeout):
                        return self.returncode

                def launch(argv, **kwargs):
                    self.assertTrue(kwargs['start_new_session'])
                    child = Child(300 + len(children))
                    children.append(child)
                    if len(children) == 1:
                        self.exchange()
                    return child

                def stop(pid, sig):
                    stopped.append(pid)
                    child = next(item for item in children if item.pid == pid)
                    if pid == 301 and mode == 'one-cleanup-error':
                        raise PermissionError('controlled failure stopping the already-owned worker')
                    child.returncode = 0
                    if pid == 301:
                        raise ProcessLookupError('owned child exited after poll')

                def advance(seconds):
                    clock[0] += 651

                with patch.object(runner.subprocess, 'Popen', side_effect=launch), \
                        patch.object(runner, 'command', side_effect=lambda argv, name, timeout: str(self.probe(argv[-2], argv[-1]))), \
                        patch.object(runner.time, 'monotonic', side_effect=lambda: clock[0]), \
                        patch.object(runner.time, 'sleep', side_effect=advance), patch.object(runner.os, 'killpg', side_effect=stop):
                    runner.run_notification_test(self.argv, io.BytesIO(), dict(self.state), self.derived, self.inputs)
                self.assertEqual(stopped, [301, 300])
                receipt = json.loads(receipt_path.read_bytes())
                self.assertEqual(receipt['testExitCode'], 0)
                self.assertEqual(receipt['stopReason'], 'ORIGINAL_DEADLINE_EXCEEDED')
                if mode == 'one-cleanup-error':
                    self.assertEqual([row['child'] for row in receipt['cleanupErrors']], ['worker'])
                    self.assertIsNone(receipt['workerExitCode'])
                else:
                    self.assertNotIn('cleanupErrors', receipt)
                    self.assertEqual(receipt['workerExitCode'], 0)
                with self.assertRaises(RuntimeError):
                    runner.validate_notification_observations(receipt)


if __name__ == '__main__':
    unittest.main()
