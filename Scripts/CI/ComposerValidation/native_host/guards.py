"""Pure fail-closed predicates for actual native settings, devices and results."""
from collections import Counter
import posixpath
import hashlib
import json
import re


def require(condition, message):
    if not condition:
        raise ValueError(message)


def words(value):
    return value if isinstance(value, list) else str(value).split()


def native_settings(data, sdk_path):
    require(isinstance(data, list) and len(data) == 2, 'exactly two nonempty actual native target settings required')
    require(all(isinstance(entry, dict) for entry in data), 'actual settings entries must be objects')
    targets = {entry.get('target'): entry.get('buildSettings') for entry in data}
    require(set(targets) == {'AI_Hanlin', 'AI_HanlinTests'}, 'both actual app/unit targets required')
    for name, settings in targets.items():
        require(isinstance(settings, dict) and bool(settings), 'empty actual target: ' + name)
        for key, expected in {'TARGET_NAME': name, 'PRODUCT_MODULE_NAME': name,
                              'CONFIGURATION': 'Debug', 'PLATFORM_NAME': 'iphonesimulator',
                              'SDKROOT': sdk_path, 'SDK_NAME': 'iphonesimulator27.2',
                              'IPHONEOS_DEPLOYMENT_TARGET': '27.0', 'SWIFT_VERSION': '6.0',
                              'SWIFT_OPTIMIZATION_LEVEL': '-Onone', 'ENABLE_TESTABILITY': 'YES',
                              'CODE_SIGNING_ALLOWED': 'NO'}.items():
            require(settings.get(key) == expected, name + ': actual ' + key + ' mismatch/missing')
        require(set(words(settings.get('SUPPORTED_PLATFORMS', ''))) == {'iphonesimulator'}, name + ': simulator platform')
        require(words(settings.get('ARCHS', '')) == ['arm64'], name + ': concrete compatible arm64 architecture')
        require('arm64' not in words(settings.get('EXCLUDED_ARCHS', '')), name + ': arm64 excluded')
        require(set(words(settings.get('SWIFT_ACTIVE_COMPILATION_CONDITIONS', ''))) == {'DEBUG', 'Xcode'}, name + ': actual Swift conditions')
        require('DEBUG=1' in words(settings.get('GCC_PREPROCESSOR_DEFINITIONS', '')) and
                not any(flag in str(value) for flag in ['SWIFT_PACKAGE', 'SWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE'] for value in
                        [settings.get('OTHER_SWIFT_FLAGS', ''), settings.get('GCC_PREPROCESSOR_DEFINITIONS', '')]), name + ': actual compiler condition leakage')
        require(settings.get('SWIFT_DEFAULT_ACTOR_ISOLATION', '') in ['', 'nonisolated', 'Nonisolated'] and
                settings.get('SWIFT_APPROACHABLE_CONCURRENCY', 'NO') == 'NO', name + ': unreviewed concurrency override')
    app, unit = targets['AI_Hanlin'], targets['AI_HanlinTests']
    root = app.get('TARGET_BUILD_DIR', '')
    require(root.startswith('/') and '$' not in root and '..' not in root.split('/'), 'actual absolute host build directory')
    require(app.get('EXECUTABLE_PATH') == 'AI_Hanlin.app/AI_Hanlin' and
            app.get('FULL_PRODUCT_NAME') == 'AI_Hanlin.app' and
            unit.get('FULL_PRODUCT_NAME') == 'AI_HanlinTests.xctest', 'actual host/unit executable products')
    host = posixpath.join(root, app['EXECUTABLE_PATH'])
    require(unit.get('BUILT_PRODUCTS_DIR') == root and unit.get('TEST_HOST') == host and
            unit.get('BUNDLE_LOADER') == host, 'actual resolved unit TEST_HOST/BUNDLE_LOADER must match app executable')
    return {'status': 'ACTUAL_NATIVE_SETTINGS_CONFIRMED', 'actual_target_names': sorted(targets),
            'resolved_host_executable': host, 'sdk_path': sdk_path, 'architecture': 'arm64',
            'basis': 'raw -showBuildSettings JSON; not declarations or CLI headers'}


ENVIRONMENT_CONTRACT_VERSION = 'composer-runtime-27.2-v1-20261115'
RUNTIME_ID = 'com.apple.CoreSimulator.SimRuntime.iOS-27-2'
RUNTIME_VERSION = '27.2'
RUNTIME_BUILD = '24B8117'


def environment(inventory):
    runtimes = [r for r in inventory['runtimes'] if r.get('isAvailable') and r.get('version') == RUNTIME_VERSION
                and r.get('buildversion') == RUNTIME_BUILD and r.get('identifier') == RUNTIME_ID
                and r.get('platform') == 'iOS' and r.get('isInternal') is False
                and 'arm64' in r.get('supportedArchitectures', [])]
    types = [t for t in inventory['devicetypes'] if t.get('identifier') ==
             'com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro' and t.get('name') == 'iPhone 18 Pro']
    require(len(runtimes) == 1 and len(types) == 1, 'installed standard arm64 iOS27.2/24B8117 + iPhone18Pro required; no Duo/substitution/install')
    require(any(t.get('identifier') == types[0]['identifier'] for t in runtimes[0].get('supportedDeviceTypes', [])
                if isinstance(t, dict)), 'actual runtime must list iPhone18Pro as a supported device type')
    return runtimes[0], types[0]


def owned_uuid(udid):
    require(isinstance(udid, str) and re.fullmatch(r'[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}', udid) is not None,
            'invalid concrete owned simulator UUID')
    return udid


HELP_CAPTURE_SHA256 = '4c7f0c98a485121183a1bc0b5ae8549958692117107664b4ee1c3fbf0f3c4693'


def simctl_list_contract(stdout, stderr):
    """Validate the reviewed actual transcript; it documents search, not identity."""
    streams = [text for text in [stdout, stderr] if text]
    require(len(streams) == 1 and '\ufffd' not in streams[0], 'one intact actual installed help stream required')
    text = streams[0]
    require(hashlib.sha256(text.encode('utf-8')).hexdigest() == HELP_CAPTURE_SHA256,
            'installed simctl list help differs from reviewed actual transcript; no alternate grammar/query')
    lines = text.splitlines()
    usage = next(line for line in lines if line.startswith('Usage: simctl list '))
    json_doc = next(line for line in lines if line.startswith('-j     Print as JSON'))
    search_doc = next(line for line in lines if 'Search terms use a simple case-insensitive contains check' in line)
    return {'status': 'INSTALLED_HELP_REVIEWED_SEARCH_SYNTAX', 'transcript_sha256': HELP_CAPTURE_SHA256,
            'usage_line': usage, 'json_documentation': json_doc, 'search_documentation': search_doc,
            'identity_established_by_help': False,
            'identity_proof_basis': 'actual returned JSON matched to creation receipt, not help or declared name',
            'query_template': ['xcrun', 'simctl', 'list', '--json', 'devices', '{owned_unique_name}']}


def device_rows(groups):
    require(isinstance(groups, dict), 'actual devices must be runtime buckets')
    rows = []
    for runtime, devices in groups.items():
        require(isinstance(runtime, str) and re.fullmatch(r'com\.apple\.CoreSimulator\.SimRuntime\.[A-Za-z0-9.-]+', runtime) is not None and
                isinstance(devices, list), 'every runtime bucket must be a well-formed runtime key and real device list')
        for device in devices:
            require(isinstance(device, dict), 'every returned device must be an object')
            rows.append((runtime, device))
    return rows


def owned_name(before, run_id):
    require(isinstance(run_id, str) and re.fullmatch(r'[1-9][0-9]*', run_id) is not None, 'actual positive GitHub run ID required')
    name = 'Hanlin-NativeComposer-' + run_id
    for _, device in device_rows(before.get('devices')):
        require(isinstance(device.get('name'), str) and bool(device['name']), 'initial device name must be observable for uniqueness')
        owned_uuid(device.get('udid'))
        require(name.casefold() not in device['name'].casefold(), 'owned unique search name is already present in initial actual inventory')
    return name


def owned_devices_command(contract, name):
    require(isinstance(name, str) and re.fullmatch(r'Hanlin-NativeComposer-[1-9][0-9]*', name) is not None, 'one deterministic run-scoped owned name required')
    template = ['xcrun', 'simctl', 'list', '--json', 'devices', '{owned_unique_name}']
    require(contract.get('status') == 'INSTALLED_HELP_REVIEWED_SEARCH_SYNTAX' and contract.get('query_template') == template and
            contract.get('transcript_sha256') == HELP_CAPTURE_SHA256, 'reviewed actual help syntax required; no query fallback')
    return [*template[:-1], name]


def created_identity(before, runtime, model, name, udid, create_command):
    owned_uuid(udid)
    require(isinstance(name, str) and re.fullmatch(r'Hanlin-NativeComposer-[1-9][0-9]*', name) is not None, 'created unique name required')
    selected_runtime, selected_type = environment(before)
    require(runtime == selected_runtime and model == selected_type, 'creation must bind actual initially selected runtime/type')
    require(owned_name(before, name.removeprefix('Hanlin-NativeComposer-')) == name, 'fresh actual unique name required')
    require(udid.casefold() not in {d['udid'].casefold() for _, d in device_rows(before['devices'])}, 'created UUID was already present')
    require(isinstance(create_command, dict) and create_command.get('label') == 'create-owned-device' and create_command.get('exit_code') == 0 and
            create_command.get('argv') == ['xcrun', 'simctl', 'create', name, model['identifier'], runtime['identifier']],
            'actual successful create command must bind unique name, type and runtime to returned UUID')
    return {'udid': udid, 'name': name, 'actual_create_command': create_command,
            'create_uuid_origin': 'raw create-owned-device.stdout', 'initial_identity_inventory': 'simulators-before.stdout',
            'name_and_uuid_absent_from_initial_inventory': True,
            'initial_runtime_identifier': runtime['identifier'], 'initial_device_type_identifier': model['identifier']}


def owned_state_json(raw):
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, 'duplicate JSON key in actual filtered state')
            result[key] = value
        return result
    return json.loads(raw, object_pairs_hook=unique_object)


def owned_boot(inventory, before, runtime, creation):
    require(isinstance(creation, dict), 'actual creation receipt required')
    udid, name = creation.get('udid'), creation.get('name')
    # Revalidate the actual creation binding rather than accepting caller flags.
    selected_runtime, model = environment(before)
    require(runtime == selected_runtime, 'runtime context must be the actual selected initial inventory object')
    created_identity(before, runtime, model, name, udid, creation.get('actual_create_command', {}))
    require(isinstance(inventory, dict) and set(inventory) == {'devices'}, 'filtered response must contain devices only; no fabricated runtime/type arrays')
    rows = device_rows(inventory['devices'])
    require(len(rows) == 1, 'exactly one nonempty actual device globally required; missing/extra devices rejected')
    runtime_key, actual = rows[0]
    require(runtime_key == runtime['identifier'], 'actual owned device must be in exact selected runtime')
    require(actual.get('udid') == udid and actual.get('name') == name, 'actual returned UUID AND unique name must match creation')
    require(actual.get('state') == 'Booted' and actual.get('isAvailable') is True and
            actual.get('deviceTypeIdentifier') == model['identifier'], 'actual owned phone must be Booted/available/iPhone18Pro')
    return {'status': 'ACTUAL_FILTERED_OWNED_BOOT_CONFIRMED', 'actual_device': actual,
            'post_state_origin': 'raw one documented unique-name devices query; all buckets validated',
            'empty_other_runtime_buckets': sorted(key for key, values in inventory['devices'].items() if key != runtime['identifier'] and not values),
            'post_runtime_identifier': runtime_key,
            'runtime_context_origin': 'actual simulators-before.stdout, not a post-boot runtime measurement',
            'initial_runtime': {key: runtime[key] for key in ['identifier', 'version', 'buildversion', 'supportedArchitectures', 'isAvailable']},
            'device_type_context_origin': 'actual simulators-before.stdout; actual post deviceTypeIdentifier matched',
            'initial_device_type_identifier': model['identifier'], 'creation_receipt': 'owned-device.json',
            'identity_basis': 'actual JSON globally contains only the created UUID + unique name in the selected runtime'}


def require_pretest(state):
    required = ['owned_query_help_confirmed', 'native_settings_confirmed',
                'owned_boot_confirmed', 'owned_sdk_destination_confirmed']
    require(all(state.get(key) is True for key in required) and type(state.get('test_commands')) is int and state['test_commands'] == 0,
            'actual installed-help support, both native settings, filtered owned boot and SDK eligibility required before the only test')


def destination(stdout, stderr, udid):
    eligible, found, rejected = False, [], []
    for line in stdout.splitlines():
        if 'Ineligible destinations' in line:
            eligible = False
        elif 'Available destinations' in line or 'Destinations compatible' in line:
            eligible = True
        if re.search(r'\bid:\s*' + re.escape(udid) + r'(?:,|\s|})', line):
            (found if eligible and not re.search(r'\berror:', line, re.I) else rejected).append(line)
    require(not rejected and len(found) == 1, 'exact owned UDID absent/ambiguous/ineligible in explicit SDK native-project listing')
    line = found[0]
    for key, value in [('platform', 'iOS Simulator'), ('arch', 'arm64'), ('OS', RUNTIME_VERSION), ('name', None)]:
        match = re.search(r'\b' + key + r':\s*([^,}]+)', line)
        require(match is not None and (value is None or match[1].strip() == value), 'owned destination ' + key)
    require(not any(udid in line and re.search(r'ineligible|error:', line, re.I) for line in stderr.splitlines()), 'owned UDID error in listing stderr')
    return {'status': 'EXACT_OWNED_SDK_DESTINATION_CONFIRMED', 'owned_udid': udid, 'raw_destination_line': line}


def dictionaries(value):
    if isinstance(value, dict):
        yield value
        for item in value.values():
            yield from dictionaries(item)
    elif isinstance(value, list):
        for item in value:
            yield from dictionaries(item)


def observations(data, expected, udid, log_lines=()):
    require(len(expected) == len(set(expected)) == 12, 'exact 12 unique expected methods')
    cases = []
    for node in dictionaries(data):
        if node.get('nodeType') == 'Test Case':
            raw_id = node.get('nodeIdentifier') or node.get('nodeIdentifierURL', '')
            identity = '/'.join(raw_id.rstrip('/').split('/')[-2:]) if isinstance(raw_id, str) else 'UNPARSEABLE_ID'
            cases.append({'id': identity, 'raw_id': raw_id, 'result': node.get('result')})
    authored = [n for n in cases if n['id'] in expected]
    executed = [n for n in authored if n['result'] in ['Passed', 'Failed']]
    unexpected = [n for n in cases if n['id'] not in expected]
    counts = Counter(n['id'] for n in authored)
    records = []
    for identity in expected:
        values = [n['result'] for n in authored if n['id'] == identity]
        result = 'NOT_RUN' if not values else 'DUPLICATE' if len(values) != 1 else {'Passed': 'PASS', 'Failed': 'FAIL'}.get(values[0], 'OBSERVED_NONPASS')
        records.append({'id': identity, 'result': result, 'raw_results': values})
    devices = data.get('devices', []) if isinstance(data, dict) else []
    bound = isinstance(devices, list) and bool(devices) and bool(udid) and all(isinstance(d, dict) and d.get('deviceId') == udid and d.get('modelName') == 'iPhone 18 Pro'
            and d.get('osVersion') == RUNTIME_VERSION and d.get('osBuildNumber') == RUNTIME_BUILD and d.get('architecture') == 'arm64'
            and d.get('platform') == 'iOS Simulator' for d in devices)
    messages = [str(n.get('name', '')) for n in dictionaries(data) if n.get('nodeType') == 'Failure Message']
    def actual_trace(line):
        return re.search(r'signedDelta=-?\d+(?:\.\d+)?', line) is not None
    trace = [{'origin': 'xcresult Failure Message', 'raw_text': line} for line in messages if actual_trace(line)]
    trace += [{'origin': 'raw xcodebuild log', 'raw_text': line.rstrip()} for line in log_lines if actual_trace(line)]
    complete = len(authored) == 12 and len(counts) == 12 and not unexpected and all(n['result'] == 'PASS' for n in records) and bound
    return {'full_app_acceptance': False, 'cases': records, 'authored_unique_observed': len(counts),
            'unexpected_infrastructure_case_nodes': unexpected, 'raw_devices': devices,
            'execution_device_binding': 'VERIFIED' if authored and bound else 'MISMATCH' if authored else 'NOT_OBSERVED',
            'test_host_connection': 'authored_execution_on_bound_host_observed' if executed and bound else
                'authored_results_observed_without_device_binding' if executed else 'failed_before_connection' if
                any('hung before establishing connection' in m for m in messages) else 'not_observed',
            'raw_failure_messages': messages, 'signed_trace_raw_evidence': trace,
            'signed_metrics_inferred': False, 'all_12_unique_pass_on_owned_device': complete}


def focused_observations(data, authored, selected, udid, log_lines=()):
    require(isinstance(selected, str) and selected in authored, 'one selected frozen authored identity required')
    result = observations(data, authored, udid, log_lines)
    result.pop('all_12_unique_pass_on_owned_device')
    target = next(case for case in result['cases'] if case['id'] == selected)
    extra_authored = [case for case in result['cases'] if case['id'] != selected and case['raw_results']]
    matched = len(target['raw_results']) == 1 and result['authored_unique_observed'] == 1 and not extra_authored and not result['unexpected_infrastructure_case_nodes']
    result.update(selected_case_ids=[selected], selected_expected_count=1, preserved_authored_inventory_count=12,
                  selected_method_result=target['result'], unselected_authored_observations=extra_authored,
                  focused_selection_matched=matched,
                  all_selected_unique_pass_on_owned_device=matched and target['result'] == 'PASS' and result['execution_device_binding'] == 'VERIFIED',
                  product_composer_acceptance='OPEN')
    for case in result['cases']:
        case['selected_for_this_run'] = case['id'] == selected
    return result
