"""Freeze/check the final guard packet using synthetic data and source only."""
import argparse
import ast
import copy
import hashlib
import json
from pathlib import PurePosixPath
import sys

sys.dont_write_bytecode = True
import prepare_native as native
from guards import native_settings, environment, owned_boot, destination, observations, require
from run_native import command_plan, TEST_SECONDS, RUN_SECONDS
from freeze_review import review_files

BASE = '67642faaa8f16c89eb0e2330db56291c35c61c06'
BASE_WORKFLOW_SHA256 = '9276edf7542e6bf2e530dccc3e7f3f0819d1251db6d7e40f47d71630c4e5415d'
WORKFLOW = '.github/workflows/build-ios26-unsigned-ipa.yml'
MODE = 'composer_native_host_diagnostic'
SDK = '/Applications/Xcode_27.2.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator27.2.sdk'
UDI = '11111111-2222-3333-4444-555555555555'


def source_controls():
    passed, rejected = [], []

    def reject(label, function, *args):
        try:
            function(*args)
        except ValueError:
            rejected.append(label)
        else:
            raise ValueError('negative source control incorrectly accepted: ' + label)

    # Synthetic settings are predicate fixtures, never observed Apple output.
    data = []
    for name in ['AI_Hanlin', 'AI_HanlinTests']:
        settings = {'TARGET_NAME': name, 'PRODUCT_MODULE_NAME': name, 'CONFIGURATION': 'Debug',
                    'PLATFORM_NAME': 'iphonesimulator', 'SDKROOT': SDK, 'SDK_NAME': 'iphonesimulator27.2',
                    'SUPPORTED_PLATFORMS': 'iphonesimulator', 'IPHONEOS_DEPLOYMENT_TARGET': '27.0',
                    'SWIFT_VERSION': '6.0', 'SWIFT_OPTIMIZATION_LEVEL': '-Onone', 'ENABLE_TESTABILITY': 'YES',
                    'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG Xcode', 'GCC_PREPROCESSOR_DEFINITIONS': 'DEBUG=1',
                    'CODE_SIGNING_ALLOWED': 'NO', 'ARCHS': 'arm64', 'TARGET_BUILD_DIR': '/scratch/Debug-iphonesimulator',
                    'BUILT_PRODUCTS_DIR': '/scratch/Debug-iphonesimulator', 'FULL_PRODUCT_NAME': name + ('.app' if name == 'AI_Hanlin' else '.xctest')}
        settings.update({'EXECUTABLE_PATH': 'AI_Hanlin.app/AI_Hanlin'} if name == 'AI_Hanlin' else
                        {'TEST_HOST': '/scratch/Debug-iphonesimulator/AI_Hanlin.app/AI_Hanlin',
                         'BUNDLE_LOADER': '/scratch/Debug-iphonesimulator/AI_Hanlin.app/AI_Hanlin'})
        data.append({'target': name, 'buildSettings': settings})
    native_settings(data, SDK)
    passed.append('synthetic-positive-both-native-target-settings')
    reject('empty-settings-array', native_settings, [], SDK)
    reject('only-app-settings', native_settings, data[:1], SDK)
    for key, value in {'SDKROOT': 'iphonesimulator', 'SDK_NAME': 'iphoneos27.2', 'PLATFORM_NAME': 'iphoneos',
                       'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator', 'IPHONEOS_DEPLOYMENT_TARGET': '26.0',
                       'CONFIGURATION': 'Release', 'ARCHS': 'x86_64', 'EXCLUDED_ARCHS': 'arm64',
                       'SWIFT_VERSION': '5.0', 'SWIFT_OPTIMIZATION_LEVEL': '-O', 'ENABLE_TESTABILITY': 'NO',
                       'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG Xcode SWIFT_PACKAGE',
                       'OTHER_SWIFT_FLAGS': '-DSWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE',
                       'GCC_PREPROCESSOR_DEFINITIONS': '', 'BUNDLE_LOADER': '$(TEST_HOST)',
                       'TEST_HOST': '/wrong/AI_Hanlin.app/AI_Hanlin', 'SWIFT_DEFAULT_ACTOR_ISOLATION': 'MainActor',
                       'SWIFT_APPROACHABLE_CONCURRENCY': 'YES'}.items():
        changed = copy.deepcopy(data)
        changed[1]['buildSettings'][key] = value
        reject('unit-setting-' + key, native_settings, changed, SDK)
    changed = copy.deepcopy(data)
    del changed[0]['buildSettings']['SDKROOT']
    reject('missing-app-actual-SDKROOT', native_settings, changed, SDK)
    runtime = {'isAvailable': True, 'version': '27.0', 'buildversion': '24A434',
               'identifier': 'com.apple.CoreSimulator.SimRuntime.iOS-27-0', 'supportedArchitectures': ['arm64']}
    model = {'identifier': 'com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro', 'name': 'iPhone 18 Pro'}
    before = {'runtimes': [runtime], 'devicetypes': [model], 'devices': {runtime['identifier']: []}}
    environment(before)
    passed.append('synthetic-positive-exact-installed-runtime-model')
    for key, value in [('version', '27.2'), ('buildversion', 'other'), ('isAvailable', False), ('supportedArchitectures', ['x86_64'])]:
        changed = copy.deepcopy(before)
        changed['runtimes'][0][key] = value
        reject('runtime-' + key, environment, changed)
    actual = {'udid': UDI, 'state': 'Booted', 'isAvailable': True, 'deviceTypeIdentifier': model['identifier']}
    after = copy.deepcopy(before)
    after['devices'][runtime['identifier']] = [actual]
    owned_boot(after, before, runtime, UDI)
    passed.append('synthetic-positive-new-owned-booted-device')
    reject('device-already-existed', owned_boot, after, after, runtime, UDI)
    changed = copy.deepcopy(after)
    changed['devices'][runtime['identifier']][0]['state'] = 'Shutdown'
    reject('owned-device-not-booted', owned_boot, changed, before, runtime, UDI)
    heading = 'Available destinations for the "ComposerNativeHost" scheme:\n'
    line = '{ platform:iOS Simulator, arch:arm64, id:' + UDI + ', OS:27.0, name:Hanlin-NativeComposer-fixture }'
    destination(heading + line, '', UDI)
    passed.append('synthetic-positive-owned-explicit-SDK-destination')
    for name, stdout, stderr in [
        ('generic-only-listing', heading + '{ platform:iOS Simulator, id:dvtdevice-DVTiOSDeviceSimulatorPlaceholder-iphonesimulator:placeholder, name:Any iOS Simulator Device }', ''),
        ('wrong-UDI', heading + line.replace(UDI, 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'), ''),
        ('wrong-architecture', heading + line.replace('arm64', 'x86_64'), ''),
        ('wrong-OS', heading + line.replace('27.0', '27.2'), ''),
        ('no-eligible-heading', line, ''),
        ('ineligible-section', heading + line + '\nIneligible destinations:\n' + line, ''),
        ('explicit-UDI-stderr-error', heading + line, 'error: ' + UDI),
        ('duplicate-owned-destinations', heading + line + '\n' + line, '')]:
        reject(name, destination, stdout, stderr, UDI)
    expected = json.loads((native.HERE / 'review/native-inputs.json').read_text())['expected_case_ids']
    device = {'deviceId': UDI, 'modelName': 'iPhone 18 Pro', 'osVersion': '27.0', 'osBuildNumber': '24A434',
              'architecture': 'arm64', 'platform': 'iOS Simulator'}
    result = {'devices': [device], 'testNodes': [{'nodeType': 'Test Case', 'nodeIdentifier': x, 'result': 'Passed'} for x in expected]}
    require(observations(result, expected, UDI)['all_12_unique_pass_on_owned_device'], 'synthetic all12 classification')
    passed.append('synthetic-positive-12-unique-bound-case-classification')
    for name in ['empty-result', 'unexpected-infrastructure-only', 'all-skipped', 'failed-method', 'duplicate-method', 'missing-device-binding', 'wrong-device', 'missing-method', 'unexpected-extra-method']:
        changed = copy.deepcopy(result)
        if name == 'empty-result':
            changed = {}
        elif name == 'unexpected-infrastructure-only':
            changed['testNodes'] = [{'nodeType': 'Test Case', 'nodeIdentifier': 'xctest(1234)', 'result': 'Failed'}]
        elif name == 'all-skipped':
            for node in changed['testNodes']:
                node['result'] = 'Skipped'
        elif name == 'failed-method':
            changed['testNodes'][0]['result'] = 'Failed'
        elif name == 'duplicate-method':
            changed['testNodes'].append(changed['testNodes'][0])
        elif name == 'missing-device-binding':
            changed['devices'] = []
        elif name == 'wrong-device':
            changed['devices'][0]['deviceId'] = 'another-device'
        elif name == 'missing-method':
            changed['testNodes'].pop()
        elif name == 'unexpected-extra-method':
            changed['testNodes'].append({'nodeType': 'Test Case', 'nodeIdentifier': 'other/method()', 'result': 'Passed'})
        classified = observations(changed, expected, UDI)
        require(not classified['all_12_unique_pass_on_owned_device'], name + ' incorrectly classified pass')
        if name in ['empty-result', 'unexpected-infrastructure-only']:
            require(len(classified['cases']) == 12 and all(x['result'] == 'NOT_RUN' for x in classified['cases']), name + ': authored NOT_RUN classification')
        if name == 'unexpected-infrastructure-only':
            require(len(classified['unexpected_infrastructure_case_nodes']) == 1, 'separate unexpected framework node')
        if name == 'all-skipped':
            require(classified['test_host_connection'] == 'not_observed', 'skipped cases do not prove host connection')
        rejected.append('classification-' + name)
    trace = observations({}, expected, UDI, ['signedDelta=\\(height - sixLineHeight)', 'script=fixture signedDelta=-88.0'])
    require(len(trace['signed_trace_raw_evidence']) == 1 and not trace['signed_metrics_inferred'], 'actual numeric raw trace only')
    passed.append('synthetic-signed-trace-preserved-without-inference')
    plan = command_plan(PurePosixPath('/SOURCE_REVIEW_ONLY/NativeHost'), SDK, UDI, PurePosixPath('/SOURCE_REVIEW_ONLY'), PurePosixPath('/SOURCE_REVIEW_ONLY/evidence'))
    for command in plan.values():
        require(command[0] == 'xcodebuild' and command[command.index('-sdk') + 1] == SDK and
                command[command.index('-project') + 1].endswith('/' + native.PROJECT) and
                command[command.index('-scheme') + 1] == native.SCHEME and
                command[command.index('-configuration') + 1] == 'Debug', 'explicit native project/scheme/SDK/Debug command')
        require(not any(token in ' '.join(command) for token in ['Package.swift', 'ComposerValidation-Package', '-workspace', '-resolvePackageDependencies']), 'no package/synthesized-scheme command')
    require(plan['test'].count('test') == 1 and plan['test'][plan['test'].index('-parallel-testing-enabled') + 1] == 'NO' and
            plan['test'][plan['test'].index('-destination') + 1] == 'platform=iOS Simulator,id=' + UDI and TEST_SECONDS == 900 and RUN_SECONDS == 2100, 'one finite owned serial native test command')
    passed.append('actual-runner-pure-command-plan')
    return passed, rejected, plan


def workflow_controls():
    path = native.REPO / WORKFLOW
    current = path.read_text(encoding='utf-8')
    lines = current.splitlines(keepends=True)
    old_lines, native_lines = [], []
    in_native = False
    old_jobs = []
    for line in lines:
        if line.startswith('  composer-native-host-diagnostic:'):
            in_native = True
        elif in_native and line.startswith('  ') and not line.startswith('    ') and line.strip():
            in_native = False
        if in_native:
            native_lines.append(line)
        else:
            if line.startswith('    if: ${{ '):
                prefix = "    if: ${{ inputs.target_validation_group != '" + MODE + "' && ("
                require(line.startswith(prefix) and line.rstrip().endswith(') }}'), 'old job lacks native-mode exclusion')
                expression = line[len(prefix):].rstrip()[:-len(') }}')]
                old_jobs.append(expression)
                line = '    if: ${{ ' + expression + ' }}\n'
            old_lines.append(line)
    restored = ''.join(old_lines).replace(" || inputs.target_validation_group == '" + MODE + "') && inputs.target_validation_group", ") && inputs.target_validation_group")
    require(hashlib.sha256(restored.encode()).hexdigest() == BASE_WORKFLOW_SHA256 and len(old_jobs) == 19,
            'only new isolated job + 19 exclusion wrappers + concurrency mode allowed')
    block = ''.join(native_lines)
    require("if: ${{ github.event_name == 'workflow_dispatch' && inputs.target_validation_group == '" + MODE + "' && !inputs.testflight_upload }}" in block, 'manual-only native gate')
    require('runs-on: xcode-27' in block and 'timeout-minutes: 40' in block and 'timeout-minutes: 37' in block and
            'run: python3 -B Scripts/CI/ComposerValidation/native_host/run_native.py' in block and
            "COMPOSER_NATIVE_HOST_DIAGNOSTIC: '1'" in block and 'COMPOSER_EXPECTED_SHA:' in block and
            'if: always()' in block and 'retention-days: 14' in block and 'path: build/composer-native-host-evidence' in block,
            'native runner wiring/finite timeout/always retention')
    require(block.count('      - name:') == 2 and block.count('        run:') == 1, 'no additional native execution step')
    source = (native.HERE / 'run_native.py').read_text(encoding='utf-8')
    tree = ast.parse(source)
    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
             and node.func.attr == 'call' and node.args and isinstance(node.args[0], ast.Constant)]
    tests = [node for node in calls if node.args[0].value == 'native-test']
    require(len(tests) == 1, 'one runner test call site')
    test_line = tests[0].lineno
    require(next(node.lineno for node in calls if node.args[0].value == 'native-target-build-settings') <
            next(node.lineno for node in calls if node.args[0].value == 'native-sdk-destinations') < test_line, 'query ordering before only test')
    require("require(state['native_settings_confirmed'] and state['owned_sdk_destination_confirmed'] and state['test_commands'] == 0" in source and
            "os.environ.get('GITHUB_RUN_ATTEMPT') == '1'" in source, 'positive conjunction and no-rerun guards')
    require(not any(isinstance(node, (ast.For, ast.While)) and node.lineno < test_line <= node.end_lineno for node in ast.walk(tree)), 'test call cannot be inside retry loop')
    for path in native.HERE.glob('*.py'):
        compile(path.read_bytes(), str(path), 'exec')  # syntax only, no pyc, no Apple tool
    return {'old_jobs_explicitly_excluded': 19, 'new_native_jobs': 1, 'prior_workflow_sha256': BASE_WORKFLOW_SHA256,
            'prior_job_behavior_other_modes': 'byte-preserved after removing native-only wrappers',
            'manual_only': True, 'test_call_sites': 1, 'test_in_retry_loop': False, 'python_syntax': 'PASS_SOURCE_ONLY'}


def packet():
    # Preserve and revalidate the accepted generation packet, without rewriting it.
    for path, raw in review_files().items():
        require((native.HERE / 'review' / path).read_bytes() == raw, 'accepted generation packet drift: ' + path)
    positive, negative, plan = source_controls()
    workflow = workflow_controls()
    files = [p for p in native.HERE.rglob('*') if p.is_file() and p.name != 'final-guard-review.json']
    files.append(native.REPO / WORKFLOW)
    return {'status': 'FINAL_EXECUTION_WIRING_SOURCE_REVIEW_ONLY', 'dispatch_authorized_by_this_packet': False,
            'apple_build_test_or_device_action': 'NOT_RUN', 'full_app_acceptance': False,
            'accepted_generator_commit': BASE, 'source': native.SOURCE, 'owner': native.OWNER,
            'fixture_warning': 'All positive/negative guard data are synthetic Python source controls; no Apple PASS evidence.',
            'positive_source_controls': positive, 'negative_source_controls_rejected': negative,
            'workflow_controls': workflow, 'review_only_command_plan_not_executed': plan,
            'budgets_seconds': {'runner': RUN_SECONDS, 'version_inventory_create_boot': 30, 'bootstatus': 180,
                               'each_native_metadata_query': 120, 'only_test': TEST_SECONDS, 'export': 120, 'owned_shutdown': 60},
            'raw_retention': ['commands.json and separate stdout/stderr per command', 'native-inputs.json and native-source-inputs.tar',
                              'native settings JSON + exact SDK destinations + predicates', 'owned device provenance before/after boot',
                              'ComposerNative.xcresult when actually produced', 'actual tests export and per-method observations',
                              'unexpected framework nodes separate from authored 12', 'numeric signedDelta raw lines only, no inferred metrics'],
            'source_file_sha256': {p.relative_to(native.REPO).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                                   for p in sorted(files, key=lambda p: p.relative_to(native.REPO).as_posix())}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    value = packet()
    raw = (json.dumps(value, indent=2) + '\n').encode()
    dest = native.HERE / 'final-guard-review.json'
    if args.check:
        require(dest.read_bytes() == raw, 'final guard review packet drift')
    else:
        dest.write_bytes(raw)
    print(json.dumps({'status': 'FINAL_SOURCE_PACKET_MATCH' if args.check else 'FINAL_SOURCE_PACKET_FROZEN',
                      'packet_sha256': hashlib.sha256(raw).hexdigest(), 'positive_source_controls': len(value['positive_source_controls']),
                      'negative_source_controls_rejected': len(value['negative_source_controls_rejected']),
                      'apple_build_test_or_device_action': 'NOT_RUN', 'full_app_acceptance': False}, indent=2))


if __name__ == '__main__':
    main()
