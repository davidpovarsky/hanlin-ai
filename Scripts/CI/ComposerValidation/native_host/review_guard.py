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
from guards import (native_settings, environment, owned_boot, destination, observations, require,
                    simctl_list_contract, owned_devices_command, require_pretest, owned_name,
                    created_identity, owned_state_json, focused_observations, HELP_CAPTURE_SHA256)
from run_native import command_plan, TEST_SECONDS, RUN_SECONDS, FOCUSED_CASE, FOCUSED_SELECTOR
from freeze_review import review_files

BASE = '67642faaa8f16c89eb0e2330db56291c35c61c06'
BASE_WORKFLOW_SHA256 = '9276edf7542e6bf2e530dccc3e7f3f0819d1251db6d7e40f47d71630c4e5415d'
FROZEN_WORKFLOW_SHA256 = '2ce53bb63b1e8c350745f90f18f41ba5855603ec8baf6827446b3bc120e3bdb4'
# Source-segment bytes avoid version-dependent ast.dump output (Windows3.12/Mac3.15).
UNCHANGED_FUNCTION_SOURCE_SHA256 = {
    'guards.py': {'native_settings': '97b5edb2266010467b6335845604411cf663c95299d5610ca722f9e0e9a5df40',
                  'environment': '5dbee4131bf0ffb2ad0bb3185fc6fcf2df84bacf3fe1a2eb0293fc9c83ec41a9',
                  'destination': '1c7dcefcb6129250196822049c7543f7f49099dca01c96c58a054d54c68100ad',
                  'observations': 'a0b68d6c932d4e6075a1da391aea1c9af7f906b2a09a7f8852db687b6998e5a9'},
}
WORKFLOW = '.github/workflows/build-ios26-unsigned-ipa.yml'
MODE = 'composer_native_host_diagnostic'
SDK = '/Applications/Xcode_27.2.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator27.2.sdk'
UDI = '11111111-2222-3333-4444-555555555555'
HELP_CAPTURE_TEXT = (native.HERE / 'simctl-list-help-43711740465.txt').read_text(encoding='utf-8')
require(hashlib.sha256(HELP_CAPTURE_TEXT.encode()).hexdigest() == HELP_CAPTURE_SHA256, 'retained actual documentation bytes')


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
    name = owned_name(before, '1234567890')
    create_call = {'label': 'create-owned-device', 'exit_code': 0,
                   'argv': ['xcrun', 'simctl', 'create', name, model['identifier'], runtime['identifier']]}
    creation = created_identity(before, runtime, model, name, UDI, create_call)
    passed.append('synthetic-positive-unique-name-and-UUID-creation-binding')
    actual = {'udid': UDI, 'name': name, 'state': 'Booted', 'isAvailable': True, 'deviceTypeIdentifier': model['identifier']}
    other_runtime = 'com.apple.CoreSimulator.SimRuntime.iOS-27-2'
    after = {'devices': {runtime['identifier']: [actual], other_runtime: []}}
    receipt = owned_boot(after, before, runtime, creation)
    require(receipt['empty_other_runtime_buckets'] == [other_runtime] and
            receipt['runtime_context_origin'].startswith('actual simulators-before.stdout') and 'runtimes' not in after,
            'well-formed empty buckets are allowed; initial context is not post measurement')
    passed.append('synthetic-positive-one-owned-device-with-empty-other-runtime')
    reject('created-name-alias', owned_devices_command, simctl_list_contract(HELP_CAPTURE_TEXT, ''), 'booted')
    reject('query-UUID-assumption', owned_devices_command, simctl_list_contract(HELP_CAPTURE_TEXT, ''), UDI)
    existing = copy.deepcopy(before)
    existing['devices'][runtime['identifier']] = [actual]
    reject('name-already-present', owned_name, existing, '1234567890')
    existing['devices'][runtime['identifier']][0] = dict(actual, name='unrelated')
    reject('UUID-already-present', created_identity, existing, runtime, model, name, UDI, create_call)
    reject('create-command-name-mismatch', created_identity, before, runtime, model, name, UDI,
           dict(create_call, argv=['xcrun', 'simctl', 'create', 'wrong-name', model['identifier'], runtime['identifier']]))
    reject('create-command-failed', created_identity, before, runtime, model, name, UDI, dict(create_call, exit_code=1))
    reject('create-command-missing', created_identity, before, runtime, model, name, UDI, None)
    for label in ['missing-devices-key', 'missing-device', 'wrong-UUID', 'wrong-name', 'missing-name', 'missing-UUID',
                  'wrong-runtime', 'extra-UUID', 'duplicate-owned-device', 'extra-other-runtime-device', 'missing-state',
                  'Shutdown-state', 'unavailable', 'string-availability', 'wrong-type', 'missing-type',
                  'malformed-empty-bucket', 'nonobject-other-bucket', 'nonobject-selected-device', 'malformed-runtime-key',
                  'fabricated-post-runtimes', 'fabricated-post-types']:
        changed = copy.deepcopy(after)
        device = changed['devices'][runtime['identifier']][0]
        if label == 'missing-devices-key': changed = {}
        elif label == 'missing-device': changed['devices'][runtime['identifier']] = []
        elif label == 'wrong-UUID': device['udid'] = 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'
        elif label == 'wrong-name': device['name'] = 'Hanlin-NativeComposer-999'
        elif label == 'missing-name': del device['name']
        elif label == 'missing-UUID': del device['udid']
        elif label == 'wrong-runtime': changed['devices'] = {runtime['identifier']: [], other_runtime: [device]}
        elif label in ['extra-UUID', 'duplicate-owned-device']:
            changed['devices'][runtime['identifier']].append(dict(device, udid='AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE') if label == 'extra-UUID' else dict(device))
        elif label == 'extra-other-runtime-device': changed['devices'][other_runtime] = [dict(device)]
        elif label == 'missing-state': del device['state']
        elif label == 'Shutdown-state': device['state'] = 'Shutdown'
        elif label == 'unavailable': device['isAvailable'] = False
        elif label == 'string-availability': device['isAvailable'] = 'true'
        elif label == 'wrong-type': device['deviceTypeIdentifier'] = 'com.apple.CoreSimulator.SimDeviceType.iPhone-18'
        elif label == 'missing-type': del device['deviceTypeIdentifier']
        elif label == 'malformed-empty-bucket': changed['devices'][other_runtime] = {}
        elif label == 'nonobject-other-bucket': changed['devices'][other_runtime] = [None]
        elif label == 'nonobject-selected-device': changed['devices'][runtime['identifier']] = [None]
        elif label == 'malformed-runtime-key': changed['devices']['not-a-runtime'] = []
        elif label == 'fabricated-post-runtimes': changed['runtimes'] = [runtime]
        elif label == 'fabricated-post-types': changed['devicetypes'] = [model]
        reject('filtered-state-' + label, owned_boot, changed, before, runtime, creation)
    reject('unbound-runtime-context', owned_boot, after, before, dict(runtime, buildversion='other'), creation)
    reject('duplicate-JSON-runtime-key', owned_state_json, '{"devices":{"same":[],"same":[]}}')
    reject('malformed-JSON', owned_state_json, '{')
    contract = simctl_list_contract(HELP_CAPTURE_TEXT, '')
    require(contract['identity_established_by_help'] is False, 'help cannot establish UUID/name identity')
    query = owned_devices_command(contract, name)
    require(query == ['xcrun', 'simctl', 'list', '--json', 'devices', name], 'exact single deterministic name-search command')
    passed.append('captured-actual-help-syntax-only-and-unique-name-query')
    require(simctl_list_contract('', HELP_CAPTURE_TEXT) == contract, 'captured actual help can be on stderr')
    for label, text in [('missing', ''), ('changed-grammar', HELP_CAPTURE_TEXT.replace('--json-fd', '--unknown-fd')),
                        ('synthetic-UUID-prose', HELP_CAPTURE_TEXT + 'Search terms match UUIDs.\n'),
                        ('truncated', HELP_CAPTURE_TEXT[:-1]), ('invalid-decoding', HELP_CAPTURE_TEXT + '\ufffd')]:
        reject('help-' + label, simctl_list_contract, text, '')
    reject('ambiguous-help-streams', simctl_list_contract, HELP_CAPTURE_TEXT, HELP_CAPTURE_TEXT)
    reject('query-without-reviewed-documentation', owned_devices_command, {}, name)
    altered = copy.deepcopy(contract)
    altered['query_template'] = ['xcrun', 'simctl', 'list', '-j']
    reject('query-global-fallback-template', owned_devices_command, altered, name)
    ready = {key: True for key in ['owned_query_help_confirmed', 'native_settings_confirmed', 'owned_boot_confirmed', 'owned_sdk_destination_confirmed']}
    ready['test_commands'] = 0
    require_pretest(ready)
    passed.append('synthetic-positive-all-actual-pretest-predicates')
    for key in [k for k in ready if k != 'test_commands']:
        for value in [False, None, 'true']:
            reject('pretest-' + key + '-' + str(value), require_pretest, dict(ready, **{key: value}))
    reject('pretest-previous-test-command', require_pretest, dict(ready, test_commands=1))
    reject('created-settings-are-not-boot-readiness', require_pretest, dict(ready, owned_boot_confirmed=False, owned_sdk_destination_confirmed=False))
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
    focused = {'devices': [device], 'testNodes': [{'nodeType': 'Test Case', 'nodeIdentifier': FOCUSED_CASE, 'result': 'Passed'}]}
    classified = focused_observations(focused, expected, FOCUSED_CASE, UDI)
    require(classified['all_selected_unique_pass_on_owned_device'] and classified['selected_expected_count'] == 1 and
            sum(case['result'] == 'NOT_RUN' for case in classified['cases']) == 11 and len(classified['cases']) == 12,
            'exact one selected PASS with eleven NOT_RUN; no reused source-suite passes')
    passed.append('synthetic-positive-one-focused-case-eleven-not-run')
    for label in ['zero-selected', 'failed-selected', 'duplicate-selected', 'skipped-selected', 'other-authored-only',
                  'extra-authored', 'all-twelve', 'wrong-device', 'unexpected-infrastructure']:
        changed = copy.deepcopy(focused)
        if label == 'zero-selected': changed = {}
        elif label == 'failed-selected': changed['testNodes'][0]['result'] = 'Failed'
        elif label == 'duplicate-selected': changed['testNodes'].append(dict(changed['testNodes'][0]))
        elif label == 'skipped-selected': changed['testNodes'][0]['result'] = 'Skipped'
        elif label == 'other-authored-only': changed['testNodes'][0]['nodeIdentifier'] = expected[0]
        elif label == 'extra-authored': changed['testNodes'].append({'nodeType': 'Test Case', 'nodeIdentifier': expected[0], 'result': 'Passed'})
        elif label == 'all-twelve': changed = copy.deepcopy(result)
        elif label == 'wrong-device': changed['devices'][0]['deviceId'] = 'other-device'
        elif label == 'unexpected-infrastructure': changed['testNodes'].append({'nodeType': 'Test Case', 'nodeIdentifier': 'xctest(1234)', 'result': 'Failed'})
        actual_focus = focused_observations(changed, expected, FOCUSED_CASE, UDI)
        require(not actual_focus['all_selected_unique_pass_on_owned_device'], 'false focused pass: ' + label)
        rejected.append('focused-' + label)
    plan = command_plan(PurePosixPath('/SOURCE_REVIEW_ONLY/NativeHost'), SDK, UDI, PurePosixPath('/SOURCE_REVIEW_ONLY'), PurePosixPath('/SOURCE_REVIEW_ONLY/evidence'))
    for command in plan.values():
        require(command[0] == 'xcodebuild' and command[command.index('-sdk') + 1] == SDK and
                command[command.index('-project') + 1].endswith('/' + native.PROJECT) and
                command[command.index('-scheme') + 1] == native.SCHEME and
                command[command.index('-configuration') + 1] == 'Debug', 'explicit native project/scheme/SDK/Debug command')
        require(command.count('-derivedDataPath') == 1 and command[command.index('-derivedDataPath') + 1] == '/SOURCE_REVIEW_ONLY/DerivedData',
                'settings, listing and test must share the same fresh owned products directory')
        require(not any(token in ' '.join(command) for token in ['Package.swift', 'ComposerValidation-Package', '-workspace', '-resolvePackageDependencies']), 'no package/synthesized-scheme command')
    require(plan['test'].count('test') == 1 and plan['test'][plan['test'].index('-parallel-testing-enabled') + 1] == 'NO' and
            plan['test'][plan['test'].index('-destination') + 1] == 'platform=iOS Simulator,id=' + UDI and TEST_SECONDS == 900 and RUN_SECONDS == 2100, 'one finite owned serial native test command')
    for label in ['settings', 'test']:
        require('-destination' in plan[label] and '-arch' not in plan[label] and '--arch' not in plan[label],
                'concrete destination must select architecture without conflicting CLI flags')
    require(plan['settings'].count('test') == 1 and '-showBuildSettings' in plan['settings'],
            'settings must inspect test action so the hosted unit target is included')
    passed.append('test-action-settings-before-build-and-test')
    passed.append('concrete-destination-without-conflicting-architecture-flags')
    passed.append('actual-runner-pure-command-plan')
    require([item for item in plan['test'] if item.startswith('-only-testing:')] == ['-only-testing:' + FOCUSED_SELECTOR] and
            FOCUSED_SELECTOR == 'AI_HanlinTests/' + FOCUSED_CASE and FOCUSED_CASE in expected,
            'one exact module/suite/frozen-function selector; no suite-wide or alternate selection')
    return passed, rejected, plan


def runner_flow(source):
    tree = ast.parse(source)
    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
             and node.func.attr == 'call' and node.args and isinstance(node.args[0], ast.Constant)]
    labels = {label: [n for n in calls if n.args[0].value == label] for label in [
        'installed-simctl-list-help', 'simulators-before', 'create-owned-device', 'native-target-build-settings',
        'boot-owned-device', 'bootstatus-owned-device', 'owned-device-state-after-boot', 'native-sdk-destinations', 'native-test']}
    require(all(len(nodes) == 1 for nodes in labels.values()), 'one call site per preflight phase/test, no alternate query')
    ordered = [nodes[0].lineno for nodes in labels.values()]
    require(ordered == sorted(ordered), 'required help/create/settings-before-boot/filtered-state/eligibility/test ordering')
    cap_map = {'installed-simctl-list-help': 30, 'simulators-before': 30, 'create-owned-device': 30,
               'native-target-build-settings': 120, 'boot-owned-device': 30, 'bootstatus-owned-device': 180,
               'owned-device-state-after-boot': 30, 'native-sdk-destinations': 120,
               'actual-tests-export': 120, 'shutdown-owned-device': 60}
    for label, cap in cap_map.items():
        matching = [n for n in calls if n.args[0].value == label]
        require(len(matching) == 1 and isinstance(matching[0].args[1], ast.Constant) and matching[0].args[1].value == cap,
                'unchanged bounded command: ' + label)
    test = labels['native-test'][0]
    require(isinstance(test.args[1], ast.Name) and test.args[1].id == 'TEST_SECONDS' and TEST_SECONDS == 900 and RUN_SECONDS == 2100,
            'unchanged single test/runner caps')
    global_lists = [n for n in calls if isinstance(n.args[2], ast.List) and all(isinstance(x, ast.Constant) for x in n.args[2].elts) and
                    ast.literal_eval(n.args[2]) == ['xcrun', 'simctl', 'list', '-j']]
    require(len(global_lists) == 1 and global_lists[0].args[0].value == 'simulators-before', 'only initial global inventory; no post-boot/global fallback')
    help_call = labels['installed-simctl-list-help'][0]
    require(ast.literal_eval(help_call.args[2]) == ['xcrun', 'simctl', 'help', 'list'], 'actual installed help must be captured')
    filtered_call = labels['owned-device-state-after-boot'][0]
    require(isinstance(filtered_call.args[2], ast.Name) and filtered_call.args[2].id == 'owned_query', 'post-state must use installed-help-derived owned query')
    named_calls = lambda name: [n for n in ast.walk(tree) if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id == name]
    for name, lower, upper in [('simctl_list_contract', help_call.lineno, labels['create-owned-device'][0].lineno),
                               ('owned_name', labels['simulators-before'][0].lineno, labels['create-owned-device'][0].lineno),
                               ('created_identity', labels['create-owned-device'][0].lineno, labels['native-target-build-settings'][0].lineno),
                               ('native_settings', labels['native-target-build-settings'][0].lineno, labels['boot-owned-device'][0].lineno),
                               ('owned_boot', filtered_call.lineno, labels['native-sdk-destinations'][0].lineno),
                               ('destination', labels['native-sdk-destinations'][0].lineno, test.lineno),
                               ('require_pretest', labels['native-sdk-destinations'][0].lineno, test.lineno)]:
        matches = named_calls(name)
        require(len(matches) == 1 and lower < matches[0].lineno < upper, 'actual predicate ordering: ' + name)
    initial = [n for n in ast.walk(tree) if isinstance(n, ast.Dict) and any(isinstance(k, ast.Constant) and k.value == 'owned_boot_confirmed' for k in n.keys)]
    require(len(initial) == 1, 'initial preflight state')
    flags = {k.value: v.value for k, v in zip(initial[0].keys, initial[0].values) if isinstance(k, ast.Constant) and isinstance(v, ast.Constant)}
    require(flags['owned_boot_confirmed'] is False and flags['owned_sdk_destination_confirmed'] is False, 'created/settings phase cannot declare readiness')
    boot_assignments = [n for n in ast.walk(tree) if isinstance(n, ast.Assign) and any(isinstance(t, ast.Subscript) and isinstance(t.slice, ast.Constant)
                        and t.slice.value == 'owned_boot_confirmed' for t in n.targets)]
    require(len(boot_assignments) == 1 and named_calls('owned_boot')[0].lineno < boot_assignments[0].lineno < named_calls('destination')[0].lineno,
            'boot-positive state only after actual filtered proof')
    require(not any(isinstance(n, (ast.For, ast.While)) and any(n.lineno < call.lineno <= n.end_lineno for nodes in labels.values() for call in nodes)
                    for n in ast.walk(tree)), 'no retry/query/device/test loops')
    return {'phase_order': list(labels), 'settings_before_boot': True, 'global_post_boot_queries': 0,
            'owned_post_boot_query_calls': 1, 'test_call_sites': 1, 'readiness_requires_actual_filtered_state': True}


def flow_negative_controls(source):
    mutations = {
        'missing-all-predicates-gate': source.replace('require_pretest(state)', 'pass'),
        'premature-boot-ready': source.replace("'owned_boot_confirmed': False", "'owned_boot_confirmed': True"),
        'missing-actual-post-state-proof': source.replace("actual = owned_boot(owned_state_json(runner.text('owned-device-state-after-boot')), before, runtime, creation)", 'actual = {}'),
        'post-boot-global-fallback': source.replace("30, owned_query)", "30, ['xcrun', 'simctl', 'list', '-j'])"),
        'extended-post-query-cap': source.replace("'owned-device-state-after-boot', 30", "'owned-device-state-after-boot', 60"),
        'test-retry-loop': source.replace("        status = runner.call('native-test'", "        for _ in range(2):\n            status = runner.call('native-test'"),
    }
    tree = ast.parse(source)
    execute = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'execute')
    block = next(n for n in execute.body if isinstance(n, ast.Try))
    def is_call(node, label):
        return isinstance(node, ast.Expr) and isinstance(node.value, ast.Call) and node.value.args and isinstance(node.value.args[0], ast.Constant) and node.value.args[0].value == label
    settings = next(n for n in block.body if is_call(n, 'native-target-build-settings'))
    block.body.remove(settings)
    boot_index = next(i for i, n in enumerate(block.body) if is_call(n, 'boot-owned-device'))
    block.body.insert(boot_index + 1, settings)
    mutations['settings-after-boot'] = ast.unparse(tree)
    rejected = []
    for name, mutated in mutations.items():
        require(mutated != source, 'source-flow mutation did not apply: ' + name)
        try:
            runner_flow(mutated)
        except ValueError:
            rejected.append(name)
        else:
            raise ValueError('incorrectly accepted source control flow: ' + name)
    return rejected


def workflow_controls():
    current = (native.REPO / WORKFLOW).read_bytes()
    require(hashlib.sha256(current).hexdigest() == FROZEN_WORKFLOW_SHA256,
            'scoped existing Composer job wiring drift')
    text = current.decode()
    start, end = '  focused-composer-tests:', '  focused-nativescript-metadata-tests:'
    # Baseline OWNER prefix/suffix fingerprints avoid an unfetched ancestor tree
    # in shallow Actions checkouts; all triggers and other jobs remain guarded.
    require(hashlib.sha256(text[:text.index(start)].encode()).hexdigest() == 'fb0632ded2c2cb3a06e5c14764931df883d2437df69faa69f95d7f49952d150b' and
            hashlib.sha256(text[text.index(end):].encode()).hexdigest() == '77e4d0d975368532712d8a96c617de5cd76170c419585010c78748cf1eb1efef',
            'only existing focused Composer job may change; triggers and other jobs preserved')
    block = text[text.index(start):text.index(end)]
    require("inputs.composer_validation_only && !inputs.testflight_upload" in block and
            "inputs.target_validation_group == 'composer_native_host_diagnostic'" in block and
            "'xcode-27' || 'macos-26'" in block and
            "COMPOSER_NATIVE_HOST_DIAGNOSTIC: '1'" in block and
            'run: python3 -B Scripts/CI/ComposerValidation/native_host/run_native.py' in block and
            'if: always()' in block and 'retention-days: 14' in block and
            'build/composer-native-host-evidence' in block,
            'existing isolated job must retain diagnostic runner and artifacts')
    source = (native.HERE / 'run_native.py').read_text(encoding='utf-8')
    flow = runner_flow(source)
    rejected_flow = flow_negative_controls(source)
    require("os.environ.get('GITHUB_RUN_ATTEMPT') == '1'" in source, 'no-rerun guard unchanged')
    for file, expected in UNCHANGED_FUNCTION_SOURCE_SHA256.items():
        value = (native.HERE / file).read_text(encoding='utf-8')
        functions = {n.name: n for n in ast.parse(value).body if isinstance(n, ast.FunctionDef)}
        require(all(hashlib.sha256(ast.get_source_segment(value, functions[name]).encode()).hexdigest() == sha
                    for name, sha in expected.items()), 'native predicates changed: ' + file)
    for path in native.HERE.glob('*.py'):
        compile(path.read_bytes(), str(path), 'exec')
    return {'existing_focused_job_reused': True, 'other_jobs_and_triggers': 'content-preserved; normalized LF',
            'manual_only': True, 'test_call_sites': 1, 'python_syntax': 'PASS_SOURCE_ONLY',
            'repair_flow': flow, 'rejected_flow_mutations': rejected_flow,
            'unchanged_e778_function_source_sha256': UNCHANGED_FUNCTION_SOURCE_SHA256}


def packet():
    # Preserve and revalidate the accepted generation packet, without rewriting it.
    for path, raw in review_files().items():
        require((native.HERE / 'review' / path).read_bytes() == raw, 'accepted generation packet drift: ' + path)
    positive, negative, plan = source_controls()
    workflow = workflow_controls()
    files = [p for p in native.HERE.rglob('*') if p.is_file() and p.name != 'final-guard-review.json']
    files.append(native.REPO / WORKFLOW)
    return {'status': 'FILTERED_OWNED_PREFLIGHT_REPAIR_SOURCE_REVIEW_ONLY', 'dispatch_authorized_by_this_packet': False,
            'standing_execution_quality_gate': 'single Composer owner validates and executes under explicit 2026-11-15 activation',
            'apple_build_test_or_device_action': 'NOT_RUN', 'full_app_acceptance': False,
            'accepted_generator_commit': BASE, 'source': native.SOURCE, 'owner': native.OWNER,
            'prior_closed_attempt': {'run': '43711740465', 'head': '70a74580115982ed5810cf93aed9700a0e3537c9',
                                     'artifact': '14160935813', 'artifact_bytes': 42397,
                                     'verified_full_zip_sha256': '653531d1ce1da284d9eea93e8a9d0d3311189633b02056d21a2be6fd6250a174',
                                     'block': 'actual help succeeded; reviewed parser rejected grammar before inventory/device/settings/test'},
            'reviewed_documentation_capture': {'path': 'simctl-list-help-43711740465.txt', 'bytes': 750,
                'sha256': HELP_CAPTURE_SHA256, 'raw_artifact_entry': 'installed-simctl-list-help.stderr',
                'command': ['xcrun', 'simctl', 'help', 'list'], 'exit': 0,
                'full_zip_audit_attribution': 'completed Tomer and Roni RAM audits; Root verified run metadata only, ZIP transfer cancelled',
                'identity_established_by_help': False},
            'new_attempt_installed_help_and_owned_name_output': 'NOT_RUN; actual returned identity/state required',
            'focused_selection': {'selected_case_ids': [FOCUSED_CASE], 'xcodebuild_selector': FOCUSED_SELECTOR,
                                 'required_executed_unique_count': 1, 'other_authored_count': 11,
                                 'other_authored_expected': 'NOT_RUN; no reused passes', 'zero_selected': 'BLOCKED; no selector retry'},
            'fixture_warning': 'Python identity/result controls are synthetic. Help text is retained actual documentation. Neither proves a new Apple execution.',
            'positive_source_controls': positive, 'negative_source_controls_rejected': negative,
            'workflow_controls': workflow, 'review_only_command_plan_not_executed': plan,
            'review_only_owned_query_not_executed': owned_devices_command(simctl_list_contract(HELP_CAPTURE_TEXT, ''), 'Hanlin-NativeComposer-1234567890'),
            'budgets_seconds': {'runner': RUN_SECONDS, 'version_inventory_create_boot': 30, 'bootstatus': 180,
                               'each_native_metadata_query': 120, 'only_test': TEST_SECONDS, 'export': 120, 'owned_shutdown': 60},
            'raw_retention': ['commands.json and separate stdout/stderr per command', 'native-inputs.json and native-source-inputs.tar',
                              'actual installed simctl help list stdout/stderr + raw hashes + recognized contract',
                              'one exact owned-UUID filtered devices query + raw post-state; initial runtime/type origins explicit',
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
