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


def owned_boot(inventory, before, runtime, udid):
    require(re.fullmatch(r'[0-9A-Fa-f-]{36}', udid) is not None, 'invalid owned simulator UUID')
    require(udid not in {d['udid'] for devices in before['devices'].values() for d in devices}, 'device was not freshly created')
    matches = [d for d in inventory['devices'].get(runtime['identifier'], []) if d.get('udid') == udid]
    require(len(matches) == 1 and matches[0].get('state') == 'Booted' and matches[0].get('isAvailable') and
            matches[0].get('deviceTypeIdentifier') == 'com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro', 'exact fresh owned phone must be booted/available')
    return matches[0]


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
