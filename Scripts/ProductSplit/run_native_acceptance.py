"""Run the real target on a new disposable simulator, retaining authentic evidence."""
from pathlib import Path
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time

from simulator_entitlements import read_simulator_entitlements
from verify_targets import native_ui_typecheck_command, validate_native_test_membership

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path(os.environ['SPLIT_EVIDENCE'])

TEST_SCOPE = os.environ.get('SPLIT_NATIVE_TEST_SCOPE', 'baseline')
UI_PLANS = {
    'cross_app': (['HanlinMiniAppsTests/CrossAppInvocationTests',
                  'HanlinMiniAppsUITests/MiniAppsCrossAppPreferencesUITests',
                  'HanlinMiniAppsUITests/MiniAppsExternalModalLifetimeUITests',
                  'HanlinMiniAppsTests/NativeScriptWindowOwnershipTests',
                  'HanlinMiniAppsTests/NativeScriptHostServicesLifetimeTests',
                  'HanlinMiniAppsUITests/MiniAppsNativeScriptWindowUITests',
                  'HanlinMiniAppsUITests/MiniAppsNativeScriptPackageWindowUITests'], 22),
    'baseline': (['HanlinMiniAppsUITests/HanlinMiniAppsUITests',
                  'HanlinMiniAppsUITests/MiniAppsProviderUITests'], 7),
    # The complete affected scope includes the original producer cases plus
    # actual per-window NativeScript UI/lifetime. Authenticate and retain the
    # unchanged individual native passes before selecting only remaining cases.
    'production_runtimes': ([
        'HanlinMiniAppsTests/CrossAppInvocationTests',
        'HanlinMiniAppsUITests/MiniAppsCrossAppPreferencesUITests',
        'HanlinMiniAppsUITests/MiniAppsExternalModalLifetimeUITests',
        'HanlinMiniAppsTests/NativeScriptWindowOwnershipTests',
        'HanlinMiniAppsTests/NativeScriptHostServicesLifetimeTests',
        'HanlinMiniAppsUITests/MiniAppsNativeScriptWindowUITests',
        'HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneNativeScriptUsesRealRuntimesAndSurvivesRelaunch',
        'HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneExpoRendersNativeControlsAndRunsReactEvents',
        'HanlinMiniAppsUITests/MiniAppsNativeScriptPackageWindowUITests'], 24),
}


def command(argv, name, timeout=60, env=None):
    started = time.monotonic()
    code = None
    output = b''
    try:
        result = subprocess.run(argv, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout, env=env)
        code, output = result.returncode, result.stdout
    except subprocess.TimeoutExpired as error:
        code, output = -1, error.stdout or b'No output before subprocess timeout.'
        raise
    finally:
        (EVIDENCE / name).write_bytes(output)
        with (EVIDENCE / 'commands.jsonl').open('a', encoding='utf-8') as log:
            log.write(json.dumps({'argv': argv, 'exit': code, 'seconds': time.monotonic()-started,
                'log': name, 'sha256': hashlib.sha256(output).hexdigest()})+'\n')
    if code:
        raise RuntimeError(f'{argv[0]} exit {code}; see {name}')
    return output.decode()


def main():
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    state = {'status': 'INFRA_ERROR', 'ui': 'NOT_RUN', 'storage_boundary': 'NOT_RUN', 'xcresult': 'NOT_CREATED',
             'scope': 'production MiniApps target; actual private storage/mailbox/bootstrap and seven UI controls; two-process/signed/device acceptance separate',
             'reused_passes': [], 'started_at': time.time()}
    simulator = None
    try:
        if TEST_SCOPE not in UI_PLANS:
            raise RuntimeError('Unknown standalone native acceptance scope')
        selectors, expected_tests = UI_PLANS[TEST_SCOPE]
        state['ui_target_sources'] = validate_native_test_membership()
        state['test_scope'] = TEST_SCOPE
        state['selectors'] = selectors
        state['scope'] = 'Actual standalone MiniApps target: ' + TEST_SCOPE + '; paired/signing/device acceptance separate'
        state['sha'] = command(['git', 'rev-parse', 'HEAD'], 'source-sha.txt').strip()
        tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
        sources = sorted(ROOT/p for p in tracked if p and Path(p).suffix in {
            '.swift', '.mm', '.m', '.h', '.hpp', '.cpp', '.json', '.plist', '.entitlements', '.xcconfig', '.xcscheme',
            '.mjs', '.js', '.cjs', '.sh', '.py', '.yml', '.yaml', '.tsx', '.ts'
        } and (ROOT/p).is_file())
        inputs = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
        for name in ['AI_HLY.xcodeproj/project.pbxproj', 'RuntimeDependencies.lock.json',
                     'AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved']:
            p = ROOT / name
            inputs[name] = hashlib.sha256(p.read_bytes()).hexdigest()
        (EVIDENCE / 'source-inputs.json').write_text(json.dumps(inputs, indent=2)+'\n')
        source_identity = {
            'commit': state['sha'],
            'tree': command(['git', 'rev-parse', 'HEAD^{tree}'], 'source-tree.txt').strip(),
            'git_status_porcelain': command(['git', 'status', '--porcelain=v1', '--untracked-files=no'],
                                             'source-status.txt'),
            'tracked_file_sha256': inputs,
        }
        prepared_diff = command(['git', 'diff', '--binary', 'HEAD'], 'source-preparation.diff')
        source_identity['preparation_diff_name'] = 'source-preparation.diff'
        source_identity['preparation_diff_sha256'] = hashlib.sha256(prepared_diff.encode()).hexdigest()
        # Reconstruct the prepared source tree in an isolated index. Do not
        # alter the worktree/index or claim generated preparation was committed.
        with tempfile.TemporaryDirectory(prefix='hanlin-producer-source-') as temporary:
            index_environment = dict(os.environ, GIT_INDEX_FILE=str(Path(temporary)/'index'))
            command(['git', 'read-tree', state['sha']], 'prepared-source-read-tree.log', env=index_environment)
            if prepared_diff:
                command(['git', 'apply', '--cached', '--binary', str(EVIDENCE/'source-preparation.diff')],
                        'prepared-source-apply.log', env=index_environment)
            source_identity['prepared_tree'] = command(
                ['git', 'write-tree'], 'prepared-source-tree.txt', env=index_environment).strip()
        (EVIDENCE/'source-identity.json').write_text(json.dumps(source_identity, indent=2)+'\n')
        state['source_identity_sha256'] = hashlib.sha256((EVIDENCE/'source-identity.json').read_bytes()).hexdigest()

        state['impact'] = 'Integrated preserved production transport and namespace into current provider/bootstrap. Only affected or previously unexecuted native cases selected; no prior Host proof counted as fresh UI evidence.'
        package_arguments = ['-clonedSourcePackagesDirPath', str(ROOT/'build/SourcePackages')]
        # The actual build-for-testing below resolves and verifies this scheme.
        # Do not launch an additional whole-project package resolution merely to
        # list schemes; that query hung without output in run 44219206846.
        scheme = ROOT/'AI_HLY.xcodeproj/xcshareddata/xcschemes/HanlinMiniApps.xcscheme'
        shutil.copy2(scheme, EVIDENCE/'HanlinMiniApps.xcscheme')
        resolved = ROOT/'AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
        (EVIDENCE/'Package.resolved').write_bytes(resolved.read_bytes())
        # Match the existing paired/original-app CI policy for this already
        # pinned upstream generator. The standalone helper omitted these
        # command-local noninteractive flags in run 45285438881.
        a2ui_pin = next(pin for pin in json.loads(resolved.read_bytes())['pins']
                        if pin['identity'] == 'a2ui')
        if a2ui_pin['location'] != 'https://github.com/a2ui-project/a2ui' or \
                a2ui_pin['state']['revision'] != '3ed9601862ecc78027e20ac80ad8b1b98a5d9079':
            raise RuntimeError('The qualified A2UI generator pin changed; update its build evidence')
        state['headless_package_policy'] = {
            'source': 'Scripts/ProductSplit/run_paired_acceptance.py',
            'source_sha256': hashlib.sha256((ROOT/'Scripts/ProductSplit/run_paired_acceptance.py').read_bytes()).hexdigest(),
            'a2ui': a2ui_pin,
            'scope': 'CURRENT_XCODEBUILD_COMMAND_ONLY_NO_GLOBAL_PREFERENCES_CHANGED',
        }
        runtimes = json.loads(command(['xcrun', 'simctl', 'list', 'runtimes', '-j'], 'runtimes.json'))['runtimes']
        sdk = command(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'], 'simulator-sdk.txt').strip()
        runtime = next(r for r in runtimes if r.get('isAvailable') and not r.get('isInternal')
                       and r['identifier'].endswith('iOS-'+sdk.replace('.', '-')))
        types = json.loads(command(['xcrun', 'simctl', 'list', 'devicetypes', '-j'], 'devicetypes.json'))['devicetypes']
        supported = {t['identifier'] for t in runtime['supportedDeviceTypes']}
        family = 'iPad' if TEST_SCOPE in {'production_runtimes', 'cross_app'} else 'iPhone'
        device = next(t for t in types if t.get('productFamily') == family and t['identifier'] in supported)
        simulator = command(['xcrun', 'simctl', 'create', 'HanlinSplit-'+os.environ.get('GITHUB_RUN_ID','local'),
                             device['identifier'], runtime['identifier']], 'created-simulator.txt').strip()
        state.update(simulator=simulator, runtime=runtime, device=device)
        # -showdestinations unexpectedly resolves the entire package graph.
        # Run 45279691350 timed out while fetching packages before any app build.
        # Select the native host architecture from actual runtime metadata, let
        # the real build validate this explicit destination, and verify its
        # Mach-O output below instead of launching a second dependency resolver.
        architecture = command(['uname', '-m'], 'host-architecture.txt').strip()
        if architecture not in runtime['supportedArchitectures']:
            raise RuntimeError('Native host architecture is unsupported by the selected simulator runtime')
        state['architecture'] = architecture
        state['architecture_evidence'] = {
            'status': 'NATIVE_HOST_AND_RUNTIME_CONFIRMED_BUILD_PENDING',
            'host': architecture,
            'runtime_supported': runtime['supportedArchitectures'],
        }
        derived = Path(os.environ['SPLIT_DERIVED_DATA'])
        base = ['xcodebuild', '-project', 'AI_HLY.xcodeproj', '-scheme', 'HanlinMiniApps',
                '-destination', 'platform=iOS Simulator,id='+simulator+',arch='+architecture,
                '-parallel-testing-enabled', 'NO',
                '-derivedDataPath', str(derived), *package_arguments,
                # Same pinned build-plugin and macro policy used by the
                # existing original-app and paired-product CI commands.
                '-skipPackagePluginValidation', '-skipMacroValidation',
                # Preserve the original target's simulator entitlements. An
                # unsigned build cannot exercise widget/package publication.
                'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGNING_REQUIRED=YES', 'CODE_SIGN_IDENTITY=-']
        build = base + ['build-for-testing', '-resultBundlePath', str(EVIDENCE/'Build.xcresult')]
        state['build_command'] = build
        if TEST_SCOPE in {'cross_app', 'production_runtimes'} and os.environ.get('SPLIT_REUSE_NATIVE_PROOF') == '1':
            from reuse_cross_app_native_proof import (
                capture_current_environment, download_origin, plan_reuse)
            origin = download_origin(ROOT, ROOT/'build/miniapps-native-proof-cache')
            current_environment = capture_current_environment(runtime, device, architecture, build)
            previous = plan_reuse(ROOT, origin, current_environment)
            (EVIDENCE/'previous-native-proof.json').write_text(json.dumps(previous, indent=2)+'\n')
            original_count = expected_tests
            selectors = [selector for selector in selectors
                         if selector != 'HanlinMiniAppsTests/CrossAppInvocationTests']
            selectors += previous['rerun_selectors']
            expected_tests -= len(previous['reusable_selectors'])
            state['previous_native_proof'] = previous
            state['reused_passes'] = previous['reusable_selectors']
            state['selectors'] = selectors
            state['native_proof_coverage'] = {
                'full_affected_scope': original_count,
                'fresh_execution_required': expected_tests,
                'authenticated_previous_passes': len(previous['reusable_selectors']),
                'previous_run_overall_status': 'failure',
            }
        else:
            state['native_proof_coverage'] = {
                'full_affected_scope': expected_tests, 'fresh_execution_required': expected_tests,
                'authenticated_previous_passes': 0,
                'reason': 'Current integrated runtime, SDK and toolchain require fresh execution.',
            }
        # A real Swift 6 XCTest isolation error in run 45316423267 appeared only
        # after 26 minutes of app compilation. Check the same XCTest-only source
        # target with the actual Apple compiler before starting the owned device.
        state['status'] = 'UI_SOURCE_TYPECHECK_FAILED'
        sdk_path = command(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'],
                           'ui-source-sdk-path.txt').strip()
        platform_path = command(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-platform-path'],
                                'ui-source-platform-path.txt').strip()
        ui_compile = native_ui_typecheck_command(architecture, sdk_path, platform_path,
                                                 state['ui_target_sources'])
        state['ui_source_typecheck_command'] = ui_compile
        command(ui_compile, 'ui-source-typecheck.log', timeout=120)
        state['ui_source_typecheck'] = 'EXECUTED_PASS'
        state['status'] = 'INFRA_ERROR'
        # Authenticate prior proof and capture its environment before booting.
        # Run 45313324655 exhausted the metadata transport deadline after boot;
        # even ps and a screenshot then timed out under observed memory pressure.
        # Start only this owned device before compilation so its first-boot
        # services can settle during the real build (see run 44248480774).
        command(['sysctl', 'hw.memsize', 'hw.ncpu'], 'before-boot-host-resources.txt')
        command(['vm_stat'], 'before-boot-memory.txt')
        command(['ps', '-axo', 'pid,ppid,%cpu,%mem,state,etime,comm'], 'before-boot-processes.txt')
        command(['xcrun', 'simctl', 'boot', simulator], 'boot.log')
        command(['xcrun', 'simctl', 'bootstatus', simulator, '-b'], 'bootstatus.log', timeout=300)
        state['status'] = 'BUILD_FAILED'
        # Run 44270714044 exhausted the 20-minute cold compilation budget while
        # Swift package compilation still progressed on a 3-core/7-GiB runner.
        # Bound build preparation separately; UI/startup deadlines stay unchanged.
        command(build, 'build.log', timeout=2400)
        state['build'] = 'EXECUTED_PASS'
        state['status'] = 'PACKAGING_FAILED'
        app_product = derived/'Build/Products/Debug-iphonesimulator/HanlinMiniApps.app'
        info = plistlib.loads((app_product/'Info.plist').read_bytes())
        if info['CFBundleIdentifier'] != 'com.itorah.hanlinminiapps' or info.get('CFBundleDisplayName') != 'Hanlin MiniApps':
            raise RuntimeError('Built product identity differs from the original companion target')
        icon = info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {})
        assets = app_product / 'Assets.car'
        if icon.get('CFBundleIconName') != 'AppIcon' or not assets.is_file() or assets.stat().st_size == 0:
            raise RuntimeError('Built MiniApps must contain its compiled original Hanlin app icon')
        state['app_icon'] = {'name': icon['CFBundleIconName'],
                             'compiled_catalog_sha256': hashlib.sha256(assets.read_bytes()).hexdigest()}
        executable_name = info['CFBundleExecutable']
        if Path(executable_name).name != executable_name:
            raise RuntimeError('Built executable must remain inside its original app bundle')
        binary_architectures = command(
            ['xcrun', 'lipo', '-archs', str(app_product/executable_name)],
            'simulator-executable-architectures.txt').strip().split()
        if architecture not in binary_architectures:
            raise RuntimeError('Actual built executable omits the selected native simulator architecture')
        state['architecture_evidence'].update(
            status='BUILT_MACH_O_ARCHITECTURE_VERIFIED',
            built=binary_architectures,
            executable=executable_name,
        )
        command(['codesign', '--verify', '--deep', '--strict', str(app_product)], 'simulator-signature.log')
        entitlement_source = ROOT/'HanlinMiniAppsApp/HanlinMiniApps.entitlements'
        required_groups = plistlib.loads(entitlement_source.read_bytes())['com.apple.security.application-groups']
        proof = read_simulator_entitlements(app_product/executable_name)
        actual_groups = proof['entitlements'].get('com.apple.security.application-groups', [])
        if not required_groups or set(required_groups) != set(actual_groups):
            raise RuntimeError('Built simulator executable does not preserve the original App Groups')
        proof['source_entitlements_sha256'] = hashlib.sha256(entitlement_source.read_bytes()).hexdigest()
        (EVIDENCE/'simulator-embedded-entitlements.json').write_text(json.dumps(proof, indent=2)+'\n')
        state['simulator_signing'] = 'ORIGINAL_ENTITLEMENTS_VERIFIED_AD_HOC_NOT_DISTRIBUTION_SIGNING'
        # Verify the actual Mach-O loader paths, not only project-file intent.
        # XCTest's environment must not hide missing bundled-framework paths.
        load_commands = command(['xcrun', 'otool', '-l', str(app_product / executable_name)],
                                'simulator-executable-load-commands.txt')
        required_rpaths = {'@executable_path/Frameworks', '@loader_path/Frameworks'}
        rpaths = set(re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (\S+) \(offset', load_commands))
        if not required_rpaths.issubset(rpaths):
            raise RuntimeError('Standalone MiniApps executable is missing its bundled Frameworks runpaths')
        state['bundled_framework_runpaths'] = sorted(rpaths)
        for binary in [app_product / executable_name, app_product / (executable_name + '.debug.dylib')]:
            if binary.is_file():
                command(['xcrun', 'otool', '-L', str(binary)], binary.name + '-dependencies.txt')

        membership = json.loads((ROOT/'docs/product-split/target-membership.json').read_text())
        for resource in membership.get('shared_resources', []):
            source = ROOT/resource
            if source.suffix in {'.xcstrings', '.xcassets'}:
                continue  # Xcode compiles catalogs; the app icon/Assets.car are verified above.
            destination = app_product/source.name
            if not destination.is_file() or hashlib.sha256(destination.read_bytes()).digest() != hashlib.sha256(source.read_bytes()).digest():
                raise RuntimeError('Built app is missing or changed an existing Runtime resource: '+resource)
        if TEST_SCOPE in {'cross_app', 'production_runtimes'}:
            # Publish only the already verified original build, never a native UI
            # pass. Consumers may start their own acceptance while this gate runs.
            # The separate evidence directory is immutable once its manifest hashes
            # the frozen receipt; later updates to acceptance.json cannot alter it.
            state['status'] = 'NATIVE_ACCEPTANCE_RUNNING'
            checkpoint = EVIDENCE/'build-checkpoint.json'
            with checkpoint.open('x', encoding='utf-8') as output:
                output.write(json.dumps(state, indent=2)+'\n')
            consumer_evidence = EVIDENCE/'consumer-build'
            try:
                consumer_evidence.mkdir()
                shutil.copy2(checkpoint, consumer_evidence/'acceptance.json')
                for filename in ('commands.jsonl', 'build.log', 'source-identity.json',
                                 'source-preparation.diff', 'simulator-embedded-entitlements.json'):
                    shutil.copy2(EVIDENCE/filename, consumer_evidence/filename)
                export_environment = dict(os.environ, SPLIT_EVIDENCE=str(consumer_evidence))
                command([sys.executable, 'Scripts/ProductSplit/export_cross_app_simulator.py'],
                        'consumer-build-export.log', timeout=300, env=export_environment)
                state['consumer_build_export'] = 'EXECUTED_PASS_BUILD_ONLY_NATIVE_ACCEPTANCE_RUNNING'
            except Exception as export_error:
                # A delivery failure must not cancel the independent native cases.
                # The final exporter still has to pass before this gate can close.
                state['consumer_build_export'] = 'FAILED'
                state['consumer_build_export_error'] = str(export_error)
        state['status'] = 'INFRA_ERROR'
        devices = json.loads(command(['xcrun','simctl','list','devices','-j'], 'device-state.json'))['devices']
        device_state = next(d for group in devices.values() for d in group if d['udid'] == simulator)['state']
        if device_state != 'Booted':
            raise RuntimeError('The exact prepared simulator stopped during compilation')
        command(['xcrun', 'simctl', 'listapps', simulator], 'before-install-app-services.plist', timeout=60)
        if TEST_SCOPE == 'baseline':
            storage = base + ['test-without-building', '-resultBundlePath', str(EVIDENCE/'Storage.xcresult'),
                              '-only-testing:HanlinMiniAppsTests/SplitAppStorageLayoutTests',
                              '-only-testing:HanlinMiniAppsTests/SplitMailboxTests',
                              '-only-testing:HanlinMiniAppsBootstrapTests']
            state['storage_command'] = storage
            state['storage_boundary'] = 'INFRA_ERROR'
            storage_result = subprocess.run(storage, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=900)
            (EVIDENCE/'storage-tests.log').write_bytes(storage_result.stdout)
            if (EVIDENCE/'Storage.xcresult').exists():
                storage_summary = json.loads(command(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                    '--path', str(EVIDENCE/'Storage.xcresult')], 'storage-summary.json'))
                state['storage_summary'] = storage_summary
                if storage_result.returncode == 0 and storage_summary.get('passedTests') == 20 \
                        and storage_summary.get('failedTests', 0) == 0 and storage_summary.get('skippedTests', 0) == 0:
                    state['storage_boundary'] = 'EXECUTED_PASS'
                elif storage_summary.get('failedTests', 0):
                    state['storage_boundary'] = 'TEST_FAILED'
            if state['storage_boundary'] != 'EXECUTED_PASS':
                state['status'] = state['storage_boundary']
                raise RuntimeError('Storage boundary acceptance did not pass; see original Storage.xcresult/log')
            command([sys.executable, 'Scripts/CI/stage_scriptui_fixtures.py',
                     '--simulator-udid', simulator,
                     '--app-path', str(app_product),
                     '--bundle-id', 'com.itorah.hanlinminiapps',
                     '--fixtures-dir', str(EVIDENCE/'fixtures'),
                     '--log-file', str(EVIDENCE/'fixture-provenance.log')], 'fixture-staging.log', timeout=240)
            ordinary = EVIDENCE/'fixtures/MiniApps-Ordinary-ScriptUI.zip'
            command([sys.executable, 'Scripts/CI/IntegrationValidation/prepare_ordinary_scriptui.py', str(ordinary)],
                    'ordinary-fixture-source.json')
            container = Path(command(['xcrun', 'simctl', 'get_app_container', simulator,
                                      'com.itorah.hanlinminiapps', 'data'], 'miniapps-data-container.txt').strip())
            documents = container/'Documents'
            documents.mkdir(exist_ok=True)
            destination = documents/ordinary.name
            if destination.exists() and destination.read_bytes() != ordinary.read_bytes():
                raise RuntimeError('Owned fixture destination unexpectedly contains different bytes')
            shutil.copy2(ordinary, destination)
        else:
            state['storage_boundary'] = 'NOT_SELECTED_PREVIOUS_20_NATIVE_PROOF_RECORDED_SEPARATELY'
            # A measured original-product cold install took 176.55s in the paired
            # gate. Use its bounded 300s install allowance, once; never retry a
            # transport-uncertain mutation or count an unexecuted test as a pass.
            command(['xcrun', 'simctl', 'install', simulator, str(app_product)], 'runtime-install.log', timeout=300)
            # Ask the shipping bootstrap and CoreSimulator for their own real
            # containers. Do not synthesize directories or substitute storage.
            command(['xcrun', 'simctl', 'launch', simulator, 'com.itorah.hanlinminiapps',
                     '-AppleLanguages', '(en)', '-AppleLocale', 'en_US'], 'runtime-first-launch.log', timeout=120)
            group_containers = {}
            for group in required_groups:
                raw = command(['xcrun', 'simctl', 'get_app_container', simulator,
                    'com.itorah.hanlinminiapps', group], group+'-container.txt', timeout=180)
                group_path = Path(raw.strip()).resolve(strict=True)
                if not group_path.is_dir():
                    raise RuntimeError('The OS did not provide the original shared container: '+group)
                group_containers[group] = str(group_path)
            command(['xcrun', 'simctl', 'terminate', simulator, 'com.itorah.hanlinminiapps'],
                    'runtime-first-launch-terminate.log')
            state['app_groups'] = {'status': 'OS_CONTAINERS_VERIFIED', 'containers': group_containers}
            container = Path(command(['xcrun', 'simctl', 'get_app_container', simulator,
                'com.itorah.hanlinminiapps', 'data'], 'runtime-data-container.txt').strip())
            documents = container/'Documents'
            documents.mkdir(exist_ok=True)
            fixtures = [] if TEST_SCOPE == 'cross_app' else [
                ROOT/'DemoMiniApps/hanlin-script-parity.hanlinNativeScript',
                ROOT/'AI_HLYUITests/Fixtures/ExpoSwiftUIProbeA.hanlinExpo',
            ]
            provenance = []
            for source in fixtures:
                if not source.is_file():
                    raise RuntimeError('Missing original production runtime fixture: ' + str(source))
                destination = documents/source.name
                if destination.exists():
                    raise RuntimeError('Fresh owned simulator unexpectedly already contains runtime fixture input')
                shutil.copy2(source, destination)
                digest = hashlib.sha256(source.read_bytes()).hexdigest()
                if hashlib.sha256(destination.read_bytes()).hexdigest() != digest:
                    raise RuntimeError('Staged original runtime package bytes changed')
                provenance.append({'source': source.relative_to(ROOT).as_posix(), 'sha256': digest,
                                   'destination': str(destination), 'bytes': source.stat().st_size})
            (EVIDENCE/'runtime-fixtures.json').write_text(json.dumps(provenance, indent=2)+'\n')
        if TEST_SCOPE in {'cross_app', 'production_runtimes'}:
            command([sys.executable, 'Scripts/ProductSplit/stage_external_modal_fixture.py',
                     '--simulator-udid', simulator, '--app-path', str(app_product),
                     '--evidence', str(EVIDENCE/'external-modal')],
                    'external-modal-staging.log', timeout=180)
            command([sys.executable, 'Scripts/ProductSplit/stage_nativescript_window_fixture.py',
                     '--simulator-udid', simulator, '--app-path', str(app_product),
                     '--evidence', str(EVIDENCE/'nativescript-windows')],
                    'nativescript-window-staging.log', timeout=180)
            command([sys.executable, 'Scripts/ProductSplit/stage_nativescript_window_fixture.py',
                     '--simulator-udid', simulator, '--app-path', str(app_product),
                     '--evidence', str(EVIDENCE/'nativescript-package-windows'), '--package-windows'],
                    'nativescript-package-window-staging.log', timeout=180)
        argv = base + ['test-without-building',
                '-resultBundlePath', str(EVIDENCE/'MiniApps.xcresult')]
        argv += ['-only-testing:' + selector for selector in selectors]
        state['command'] = argv
        (EVIDENCE/'command.json').write_text(json.dumps(argv,indent=2)+'\n')
        with (EVIDENCE/'xcodebuild.log').open('wb') as log:
            process = subprocess.run(argv, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=1200)
        result = EVIDENCE/'MiniApps.xcresult'
        state['xcresult'] = 'CREATED' if result.exists() else 'NOT_CREATED: xcodebuild stopped before result bundle creation'
        state['status'] = 'INFRA_ERROR' if process.returncode else 'NOT_RUN'
        if result.exists():
            raw = command(['xcrun','xcresulttool','get','test-results','summary','--path',str(result)], 'test-summary.json')
            summary = json.loads(raw)
            state['summary'] = summary
            try:
                command(['xcrun', 'xcresulttool', 'export', 'attachments',
                         '--path', str(result), '--output-path', str(EVIDENCE/'ui-attachments')],
                        'ui-attachment-export.log', timeout=180)
                state['ui_attachments'] = 'EXPORTED_FROM_ACTUAL_XCRESULT'
            except Exception as export_error:
                # The raw xcresult remains available for read-only export.
                state['ui_attachment_export_error'] = str(export_error)
            passed, failed = summary.get('passedTests',0), summary.get('failedTests',0)
            command(['xcrun', 'xcresulttool', 'get', 'test-results', 'tests',
                '--path', str(result)], 'test-nodes.json')
            # Preserve actual failures even if a separately requested case was
            # omitted from the test bundle. That is incomplete execution, never
            # NOT_RUN for the cases present in the authentic xcresult.
            state.update(status='INCOMPLETE_TEST_SELECTION',
                         ui='TEST_FAILED' if failed else 'AWAITING_SELECTION_VERIFICATION')
            command([sys.executable, 'Scripts/CI/verify_selected_tests.py',
                '--results', str(EVIDENCE/'test-nodes.json'), '--selectors', ','.join(selectors)],
                'requested-tests.log')
            if process.returncode == 0 and passed == expected_tests and failed == 0 and summary.get('skippedTests',0) == 0:
                if TEST_SCOPE in {'cross_app', 'production_runtimes'}:
                    state.update(status='RUNTIME_RESULT_VALIDATION_FAILED', ui='EXECUTED_PASS')
                    staging = json.loads((EVIDENCE/'external-modal/staging.json').read_text())
                    command(staging['verify_command'], 'external-modal-actual-result.json')
                    state['external_modal_result'] = 'ACTUAL_RUNTIME_RESULT_VERIFIED'
                    window_staging = json.loads((EVIDENCE/'nativescript-windows/staging.json').read_text())
                    command(window_staging['verify_command'], 'nativescript-window-actual-results.json')
                    state['nativescript_window_results'] = 'ACTUAL_RUNTIME_RESULTS_VERIFIED'
                    package_staging = json.loads((EVIDENCE/'nativescript-package-windows/staging.json').read_text())
                    command(package_staging['verify_command'], 'nativescript-package-window-actual-results.json')
                    state['nativescript_package_window_results'] = 'ACTUAL_RUNTIME_RESULTS_VERIFIED'
                state.update(status='EXECUTED_PASS',ui='EXECUTED_PASS')
            elif failed:
                state.update(status='TEST_FAILED',ui='TEST_FAILED')
            else:
                state.update(status='INFRA_ERROR' if process.returncode else 'NOT_RUN',ui='NOT_RUN')
        else:
            state.update(status='INFRA_ERROR',ui='NOT_RUN')
        if state['status'] != 'EXECUTED_PASS':
            raise RuntimeError('Native acceptance did not pass; see original result and build log')
    except Exception as error:
        state['error'] = str(error)
        for argv, name in [(['vm_stat'], 'failure-memory.txt'),
                           (['ps', '-axo', 'pid,ppid,%cpu,%mem,state,etime,comm'], 'failure-processes.txt')]:
            try: command(argv, name, timeout=15)
            except Exception as capture: state.setdefault('capture_errors', []).append(str(capture))
        if simulator:
            for argv,name in [(['xcrun','simctl','io',simulator,'screenshot',str(EVIDENCE/'failure.png')],'screenshot.log'),
                              (['xcrun','simctl','spawn',simulator,'log','show','--last','3m','--style','compact','--predicate',
                                'process == "HanlinMiniApps" OR process == "runningboardd" OR process == "SpringBoard" OR process == "launchd_sim" OR eventMessage CONTAINS[c] "com.itorah.hanlinminiapps"'],
                               'simulator.log')]:
                try: command(argv,name,timeout=30)
                except Exception as capture: state.setdefault('capture_errors',[]).append(str(capture))
        # Keep only crash reports belonging to this disposable MiniApps run.
        # A launch rejected before app logging may be explained only by dyld/RBS.
        crash_roots = [Path.home() / 'Library/Logs/DiagnosticReports']
        if simulator:
            crash_roots.append(Path.home() / 'Library/Developer/CoreSimulator/Devices' / simulator / 'data/Library/Logs/CrashReporter')
        captured = []
        for crash_root in crash_roots:
            if not crash_root.is_dir():
                continue
            for crash in sorted(crash_root.glob('HanlinMiniApps*')):
                try:
                    if not crash.is_file() or crash.suffix not in {'.ips', '.crash'} or crash.stat().st_mtime < state['started_at']:
                        continue
                    if len(captured) >= 12 or crash.stat().st_size > 10 * 1024 * 1024:
                        continue
                    data = crash.read_bytes()
                    target = EVIDENCE / 'launch-crashes' / (str(len(captured)) + '-' + crash.name)
                    target.parent.mkdir(exist_ok=True)
                    target.write_bytes(data)
                    captured.append({'file': target.relative_to(EVIDENCE).as_posix(),
                                     'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)})
                except OSError as capture:
                    state.setdefault('capture_errors', []).append(str(capture))
        state['launch_crash_reports'] = captured
        print(str(error), file=sys.stderr)
    finally:
        state['result_bundles'] = [p.name for p in EVIDENCE.glob('*.xcresult')]
        if state['result_bundles']:
            state['xcresult'] = 'CREATED: '+', '.join(state['result_bundles'])
        if simulator:
            try:
                subprocess.run(['xcrun','simctl','shutdown',simulator],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)
            except subprocess.TimeoutExpired:
                state['cleanup'] = 'Dedicated simulator shutdown timed out; no erase/delete attempted'
        state['duration_seconds'] = time.time()-state['started_at']
        (EVIDENCE/'native-acceptance-duration-seconds.txt').write_text(str(int(state['duration_seconds']))+'\n')
        (EVIDENCE/'acceptance.json').write_text(json.dumps(state,indent=2)+'\n')
        if TEST_SCOPE in {'cross_app', 'production_runtimes'} and state.get('build') == 'EXECUTED_PASS':
            # Consumers require the actual built app. Preserve genuine UI/build
            # passes, but an absent export must not leave the delivery gate green.
            try:
                command([sys.executable, 'Scripts/ProductSplit/export_cross_app_simulator.py'],
                        'producer-export.log', timeout=300)
                state['producer_export'] = 'EXECUTED_PASS'
            except Exception as export_error:
                state['producer_export'] = 'FAILED'
                state['producer_export_error'] = str(export_error)
                if state['status'] == 'EXECUTED_PASS':
                    state['status'] = 'PRODUCER_EXPORT_FAILED'
            (EVIDENCE/'acceptance.json').write_text(json.dumps(state,indent=2)+'\n')
        # No deletion/erase: preserve the dedicated device for failure diagnosis.
    return 0 if state['status'] == 'EXECUTED_PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
