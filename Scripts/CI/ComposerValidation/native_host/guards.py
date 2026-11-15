"""Pure fail-closed predicates for actual native settings, devices and results."""
from collections import Counter
import posixpath
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


def environment(inventory):
    runtimes = [r for r in inventory['runtimes'] if r.get('isAvailable') and r.get('version') == '27.0'
                and r.get('buildversion') == '24A434' and 'iOS-' in r.get('identifier', '')
                and 'arm64' in r.get('supportedArchitectures', [])]
    types = [t for t in inventory['devicetypes'] if t.get('identifier') ==
             'com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro' and t.get('name') == 'iPhone 18 Pro']
    require(len(runtimes) == 1 and len(types) == 1, 'installed exact arm64 iOS27.0/24A434 + iPhone18Pro required; no substitution/install')
    return runtimes[0], types[0]


def owned_uuid(udid):
    require(isinstance(udid, str) and re.fullmatch(r'[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}', udid) is not None,
            'invalid concrete owned simulator UUID')
    return udid


def simctl_list_contract(stdout, stderr):
    """Recognize a narrow documented contract; never assume installed support.

    These accepted grammar/affirmation forms are parser contracts, not a captured
    Apple help transcript. Actual installed help must satisfy them before a query.
    """
    text = stdout + '\n' + stderr
    require('\ufffd' not in text, 'installed simctl list help must decode without replacements')
    lines = [' '.join(line.split()) for line in text.splitlines() if line.strip()]
    usage = [line for line in lines if line.startswith('Usage:')]
    grammar = r'Usage: (?:simctl )?list \[-j\s*\|\s*--json\](?: \[-v\])? \[devices\s*\|\s*devicetypes\s*\|\s*runtimes\s*\|\s*pairs\] \[<search term>\s*\|\s*available\]'
    require(len(usage) == 1 and re.fullmatch(grammar, usage[0]) is not None,
            'installed simctl help list lacks recognized JSON/category/search-term ordering; no query/fallback')
    json_lines = [line for line in lines if re.fullmatch(r'(?:-j|--json|-j\s*[,|]\s*--json)\s+(?:Print|Output|Emit)(?:s)?(?: the (?:list|output))? as JSON\.?', line, re.I)]
    require(bool(json_lines), 'installed help does not document machine-readable JSON output')
    # Accept only affirmative identity-field lists attached to the filter clause.
    # A generic search-term argument or name-only filter does not establish UDID support.
    field = r'(?:device\s+)?(?:names?|UDIDs?|UUIDs?|runtime identifiers?)'
    fields = field + r'(?:\s*(?:,\s*(?:and\s+|or\s+)?|\s+and\s+|\s+or\s+)' + field + r')*'
    forms = [
        r'(?:The )?search term (?:matches|filters devices by|is matched against) (?P<fields>' + fields + r')\.?',
        r'If a search term is (?:specified|provided), (?:the list is|devices are) filtered (?:by|based on) (?:their )?(?P<fields>' + fields + r')\.?',
        r'If a search term is (?:specified|provided), it is used to filter (?:the list of )?devices (?:by|based on) (?:their )?(?P<fields>' + fields + r')\.?',
    ]
    identity_lines = []
    for line in lines:
        for form in forms:
            match = re.fullmatch(form, line, re.I)
            if match and re.search(r'\b(?:UDIDs?|UUIDs?)\b', match['fields'], re.I):
                identity_lines.append(line)
                break
    require(len(identity_lines) == 1, 'installed help does not unambiguously document search-term matching of device UUID/UDID; no query/fallback')
    require(not any(re.search(r'\b(?:not|unsupported|except|excluding|only)\b|n.t\b', line, re.I)
                    and re.search(r'\b(?:UDIDs?|UUIDs?|search term)\b', line, re.I) for line in lines),
            'installed help contains a contradictory/restricted identity-filter statement')
    return {'status': 'INSTALLED_HELP_CONTRACT_RECOGNIZED', 'usage_line': usage[0],
            'json_documentation': json_lines, 'identity_filter_documentation': identity_lines[0],
            'query_template': ['xcrun', 'simctl', 'list', '--json', 'devices', '{owned_uuid}'],
            'actual_installed_support_basis': 'captured help stdout/stderr; no remote help captured during source preparation'}


def owned_devices_command(contract, udid):
    owned_uuid(udid)
    template = ['xcrun', 'simctl', 'list', '--json', 'devices', '{owned_uuid}']
    require(contract.get('status') == 'INSTALLED_HELP_CONTRACT_RECOGNIZED' and contract.get('query_template') == template,
            'recognized installed-help contract required for the one owned devices query')
    return [*template[:-1], udid]


def owned_boot(inventory, before, runtime, udid):
    owned_uuid(udid)
    selected_runtime, selected_type = environment(before)
    require(runtime == selected_runtime, 'runtime context must be the actual selected initial inventory object')
    require(udid not in {d['udid'] for devices in before['devices'].values() for d in devices}, 'device was not freshly created')
    require(isinstance(inventory, dict) and set(inventory) == {'devices'}, 'filtered post-state must contain devices only; no fabricated runtime/type inventory')
    groups = inventory['devices']
    require(isinstance(groups, dict) and set(groups) == {runtime['identifier']}, 'exact selected runtime only in filtered post-state')
    matches = groups[runtime['identifier']]
    require(isinstance(matches, list) and len(matches) == 1 and isinstance(matches[0], dict) and matches[0].get('udid') == udid,
            'exactly one actual owned UUID required; no missing/extra/wrong devices')
    actual = matches[0]
    require(actual.get('state') == 'Booted' and actual.get('isAvailable') is True and
            actual.get('deviceTypeIdentifier') == selected_type['identifier'], 'actual owned phone must be Booted/available/iPhone18Pro')
    return {'status': 'ACTUAL_FILTERED_OWNED_BOOT_CONFIRMED', 'actual_device': actual,
            'post_state_origin': 'raw installed-help-validated owned devices JSON',
            'post_runtime_identifier': runtime['identifier'],
            'runtime_context_origin': 'actual simulators-before.stdout, not a post-boot runtime measurement',
            'initial_runtime': {key: runtime[key] for key in ['identifier', 'version', 'buildversion', 'supportedArchitectures', 'isAvailable']},
            'device_type_context_origin': 'actual simulators-before.stdout; actual post deviceTypeIdentifier matched',
            'initial_device_type_identifier': selected_type['identifier'],
            'newness_basis': 'owned UUID absent from actual initial device inventory'}


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
    for key, value in [('platform', 'iOS Simulator'), ('arch', 'arm64'), ('OS', '27.0'), ('name', None)]:
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
            and d.get('osVersion') == '27.0' and d.get('osBuildNumber') == '24A434' and d.get('architecture') == 'arm64'
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
