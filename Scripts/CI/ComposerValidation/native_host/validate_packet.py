"""Source-only controls for the generated native project; never invokes Xcode."""
import copy
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

import prepare_native as native


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate(generated, staged, manifest, originals):
    require(manifest['source'] == native.SOURCE and manifest['owner'] == native.OWNER, 'frozen identity')
    require(manifest['full_app_acceptance'] is False, 'component scope')
    require(manifest['original_reference_input_sha256'] ==
            {p: native.digest(raw) for p, raw in sorted(originals.items())}, '12 original hashes')
    require(len(originals) == 12 and len(manifest['expected_case_ids']) == 12 and
            len(set(manifest['expected_case_ids'])) == 12, '12 unique reference inputs/cases')
    expected_cases = []
    for path, suite in [(native.TEST_SOURCE, 'HanlinMorphComposerTests'),
                        (native.EDITOR_TEST_SOURCE, 'NativeComposerLineSizingTests')]:
        names = re.findall(r'@Test(?:\([^\n]*\))?\s+func\s+(\w+)\s*\(', originals[path].decode('utf-8-sig'))
        expected_cases.extend(suite + '/' + name + '()' for name in names)
    require(manifest['expected_case_ids'] == expected_cases, 'exact frozen case identities')
    expected_paths = {'Canonical/' + p for p in [*native.SOURCES, native.TEST_SOURCE, native.EDITOR_TEST_SOURCE]}
    require(set(staged) == expected_paths | {native.HOST_PATH}, 'exact whole-file staging inventory')
    for path in expected_paths:
        require(staged[path] == originals[path.removeprefix('Canonical/')], 'whole frozen bytes: ' + path)
    require(manifest['native_canonical_sources'] == [
        {'original': p, 'native': 'Canonical/' + p, 'sha256': native.digest(originals[p]),
         'target': 'AI_Hanlin' if p in native.SOURCES else 'AI_HanlinTests'}
        for p in [*native.SOURCES, native.TEST_SOURCE, native.EDITOR_TEST_SOURCE]], 'canonical target/hash ledger')
    require(manifest['reference_only_not_compiled'] == list(native.APP_INPUTS), 'reference-only APP inventory')
    require(manifest['native_infrastructure_sources'] == {native.HOST_PATH: native.digest(staged[native.HOST_PATH])}, 'host hash')
    require(manifest['generated_infrastructure_sha256'] ==
            {p: native.digest(raw) for p, raw in generated.items()}, 'generated hashes')
    graph = native.parse_project(generated[native.PROJECT + '/project.pbxproj'].decode())
    objects = graph['objects']
    require(all(re.fullmatch('[A-F0-9]{24}', key) for key in objects), '24-character object IDs')

    def references(value):
        if isinstance(value, dict):
            for item in value.values():
                yield from references(item)
        elif isinstance(value, list):
            for item in value:
                yield from references(item)
        elif isinstance(value, str) and re.fullmatch('[A-F0-9]{24}', value):
            yield value

    require(set(references(graph)) <= set(objects), 'no dangling object references')
    reachable, pending = set(), [graph['rootObject']]
    while pending:
        key = pending.pop()
        if key not in reachable:
            reachable.add(key)
            pending.extend(references(objects[key]))
    require(reachable == set(objects), 'no orphan graph objects')
    require(not any('Package' in obj['isa'] or obj.get('productRef') for obj in objects.values()), 'zero package objects/products')
    require(not any(obj.get('packageReferences') or obj.get('packageProductDependencies') for obj in objects.values()), 'zero package dependencies')
    require(all(not obj.get('baseConfigurationReference') for obj in objects.values()), 'no external xcconfig')
    targets = {obj['name']: (key, obj) for key, obj in objects.items() if obj['isa'] == 'PBXNativeTarget'}
    require(set(targets) == {'AI_Hanlin', 'AI_HanlinTests'}, 'two native targets only')
    app_id, app = targets['AI_Hanlin']
    unit_id, unit = targets['AI_HanlinTests']
    project = objects[graph['rootObject']]
    require(project['targets'] == [app_id, unit_id], 'project target membership')
    require(app['productType'] == 'com.apple.product-type.application' and
            unit['productType'] == 'com.apple.product-type.bundle.unit-test', 'real app/unit products')
    require(objects[app['productReference']]['path'] == 'AI_Hanlin.app' and
            objects[unit['productReference']]['path'] == 'AI_HanlinTests.xctest', 'product paths')
    require(len(unit['dependencies']) == 1 and not app['dependencies'], 'one real host dependency')
    dependency = objects[unit['dependencies'][0]]
    proxy = objects[dependency['targetProxy']]
    require(dependency['isa'] == 'PBXTargetDependency' and dependency['target'] == app_id and
            proxy['isa'] == 'PBXContainerItemProxy' and proxy['proxyType'] == '1' and
            proxy['remoteGlobalIDString'] == app_id and proxy['containerPortal'] == graph['rootObject'], 'host dependency/proxy graph')
    configs = {}
    for name, (target_id, target) in targets.items():
        config_list = objects[target['buildConfigurationList']]
        require(config_list['defaultConfigurationName'] == 'Debug' and len(config_list['buildConfigurations']) == 1, 'Debug-only target')
        config = objects[config_list['buildConfigurations'][0]]
        settings = config['buildSettings']
        configs[name] = settings
        require(config['name'] == 'Debug', 'Debug configuration')
        for key, expected in {'SDKROOT': 'iphonesimulator', 'SUPPORTED_PLATFORMS': 'iphonesimulator',
                              'IPHONEOS_DEPLOYMENT_TARGET': '27.0', 'SWIFT_VERSION': '6.0',
                              'SWIFT_OPTIMIZATION_LEVEL': '-Onone', 'ENABLE_TESTABILITY': 'YES',
                              'TARGETED_DEVICE_FAMILY': '1,2', 'CODE_SIGNING_ALLOWED': 'NO',
                              'CODE_SIGNING_REQUIRED': 'NO', 'GENERATE_INFOPLIST_FILE': 'YES',
                              'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG Xcode $(inherited)'}.items():
            require(settings.get(key) == expected, name + ': ' + key)
        require(not any(key in settings for key in ['SWIFT_DEFAULT_ACTOR_ISOLATION', 'SWIFT_APPROACHABLE_CONCURRENCY']), 'no app concurrency override')
        phases = [objects[key] for key in target['buildPhases']]
        require([phase['isa'] for phase in phases] == ['PBXSourcesBuildPhase', 'PBXFrameworksBuildPhase', 'PBXResourcesBuildPhase'], 'only standard phases')
        require(not phases[1]['files'] and not phases[2]['files'], 'no package/framework/resource inputs')
        members = phases[0]['files']
        require(len(members) == len(set(members)), 'no duplicate source members')
        paths = [objects[objects[key]['fileRef']]['path'] for key in members]
        expected = (['Canonical/' + p for p in native.SOURCES] + [native.HOST_PATH] if name == 'AI_Hanlin'
                    else ['Canonical/' + p for p in [native.TEST_SOURCE, native.EDITOR_TEST_SOURCE]])
        require(paths == expected, name + ': exact source membership')
    require(configs['AI_HanlinTests'].get('TEST_HOST') == '$(BUILT_PRODUCTS_DIR)/AI_Hanlin.app/AI_Hanlin' and
            configs['AI_HanlinTests'].get('BUNDLE_LOADER') == '$(TEST_HOST)', 'host loading settings')
    scheme = ET.fromstring(generated[native.PROJECT + '/xcshareddata/xcschemes/' + native.SCHEME + '.xcscheme'])
    build = scheme.find('BuildAction')
    require(build.get('parallelizeBuildables') == 'NO' and build.get('buildImplicitDependencies') == 'YES', 'serial dependency-aware scheme')
    require([x.get('BlueprintIdentifier') for x in build.findall('.//BuildableReference')] == [app_id, unit_id], 'scheme build targets')
    action = scheme.find('TestAction')
    require(action.get('buildConfiguration') == 'Debug', 'scheme Debug tests')
    testables = action.findall('Testables/TestableReference')
    require(len(testables) == 1 and testables[0].get('skipped') == 'NO' and testables[0].get('parallelizable') == 'NO' and
            testables[0].find('BuildableReference').get('BlueprintIdentifier') == unit_id, 'serial whole unit bundle')
    require(action.find('MacroExpansion/BuildableReference').get('BlueprintIdentifier') == app_id, 'app host macro expansion')
    return {'status': 'SOURCE_CONTROLS_PASS', 'apple_build_or_test': 'NOT_RUN', 'full_app_acceptance': False,
            'original_reference_files': 12, 'whole_canonical_files_compiled_by_future_project': 10,
            'new_infrastructure_swift_files': 1, 'expected_unique_cases': 12, 'package_objects': 0,
            'native_targets': sorted(targets), 'host_loading_graph': 'verified in source only'}


def controls(generated, staged, manifest, originals):
    """Adversarial source controls: representative corruptions must be rejected."""
    rejected = []
    for name in ['missing-host', 'changed-canonical-byte', 'missing-case', 'renamed-case', 'wrong-loader',
                 'package-injection', 'missing-source-member', 'missing-host-dependency', 'changed-condition']:
        g, s, m = copy.deepcopy((generated, staged, manifest))
        graph_path = native.PROJECT + '/project.pbxproj'
        graph = native.parse_project(g[graph_path].decode())
        objects = graph['objects']
        if name == 'missing-host':
            del s[native.HOST_PATH]
        elif name == 'changed-canonical-byte':
            s['Canonical/' + native.TEST_SOURCE] += b'\n'
        elif name == 'missing-case':
            m['expected_case_ids'].pop()
        elif name == 'renamed-case':
            m['expected_case_ids'][0] = 'SyntheticSuite/syntheticCase()'
        elif name == 'package-injection':
            objects[graph['rootObject']]['packageReferences'] = ['AAAAAAAAAAAAAAAAAAAAAAAA']
        else:
            target = objects[m['target_ids']['unit']]
            settings = objects[objects[target['buildConfigurationList']]['buildConfigurations'][0]]['buildSettings']
            if name == 'wrong-loader':
                settings['BUNDLE_LOADER'] = ''
            elif name == 'missing-source-member':
                objects[target['buildPhases'][0]]['files'].pop()
            elif name == 'missing-host-dependency':
                target['dependencies'] = []
            elif name == 'changed-condition':
                settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'SWIFT_PACKAGE'
        g[graph_path] = ('// !$*UTF8*$!\n' + native.render(graph) + '\n').encode()
        m['generated_infrastructure_sha256'] = {p: native.digest(raw) for p, raw in g.items()}
        try:
            validate(g, s, m, originals)
        except ValueError:
            rejected.append(name)
        else:
            raise ValueError('control incorrectly accepted: ' + name)
    return rejected


def main():
    originals = native.frozen_inputs(native.REPO)
    generated, staged, manifest = native.make_packet(originals, (native.HERE / 'ComposerNativeUnitHost.swift').read_bytes())
    receipt = validate(generated, staged, manifest, originals)
    receipt['rejected_mutations'] = controls(generated, staged, manifest, originals)
    print(json.dumps(receipt, indent=2))


if __name__ == '__main__':
    sys.dont_write_bytecode = True
    main()
