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
import time

from simulator_entitlements import read_simulator_entitlements

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path(os.environ['SPLIT_EVIDENCE'])

TEST_SCOPE = os.environ.get('SPLIT_NATIVE_TEST_SCOPE', 'baseline')
UI_PLANS = {
    'baseline': (['HanlinMiniAppsUITests/HanlinMiniAppsUITests',
                  'HanlinMiniAppsUITests/MiniAppsProviderUITests'], 9),
    'production_runtimes': ([
        'HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneNativeScriptUsesRealRuntimesAndSurvivesRelaunch',
        'HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneExpoRendersNativeControlsAndRunsReactEvents'], 2),
}


def command(argv, name, timeout=60):
    started = time.monotonic()
    code = None
    output = b''
    try:
        result = subprocess.run(argv, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
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
             'scope': 'production MiniApps target; actual private storage/mailbox/bootstrap and focused catalog and launch controls; two-process/signed/device acceptance separate',
             'reused_passes': [], 'started_at': time.time()}
    simulator = None
    try:
        if TEST_SCOPE not in UI_PLANS:
            raise RuntimeError('Unknown standalone native acceptance scope')
        selectors, expected_tests = UI_PLANS[TEST_SCOPE]
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
        state['impact'] = 'Integrated preserved production transport and namespace into current provider/bootstrap. Only affected or previously unexecuted native cases selected; no prior Host proof counted as fresh UI evidence.'
        package_arguments = ['-clonedSourcePackagesDirPath', str(ROOT/'build/SourcePackages')]
        # The actual build-for-testing below resolves and verifies this scheme.
        # Do not launch an additional whole-project package resolution merely to
        # list schemes; that query hung without output in run 44219206846.
        scheme = ROOT/'AI_HLY.xcodeproj/xcshareddata/xcschemes/HanlinMiniApps.xcscheme'
        shutil.copy2(scheme, EVIDENCE/'HanlinMiniApps.xcscheme')
        resolved = ROOT/'AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
        (EVIDENCE/'Package.resolved').write_bytes(resolved.read_bytes())
        runtimes = json.loads(command(['xcrun', 'simctl', 'list', 'runtimes', '-j'], 'runtimes.json'))['runtimes']
        sdk = command(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'], 'simulator-sdk.txt').strip()
        runtime = next(r for r in runtimes if r.get('isAvailable') and not r.get('isInternal')
                       and r['identifier'].endswith('iOS-'+sdk.replace('.', '-')))
        types = json.loads(command(['xcrun', 'simctl', 'list', 'devicetypes', '-j'], 'devicetypes.json'))['devicetypes']
        supported = {t['identifier'] for t in runtime['supportedDeviceTypes']}
        family = 'iPad' if TEST_SCOPE == 'production_runtimes' else 'iPhone'
        device = next(t for t in types if t.get('productFamily') == family and t['identifier'] in supported)
        simulator = command(['xcrun', 'simctl', 'create', 'HanlinSplit-'+os.environ.get('GITHUB_RUN_ID','local'),
                             device['identifier'], runtime['identifier']], 'created-simulator.txt').strip()
        state.update(simulator=simulator, runtime=runtime, device=device)
        destinations = command(['xcodebuild', '-project', 'AI_HLY.xcodeproj', '-scheme', 'HanlinMiniApps',
                                '-showdestinations', *package_arguments], 'destinations.log', timeout=120)
        destination = next(line for line in destinations.splitlines() if simulator.lower() in line.lower())
        state['architecture'] = re.search(r'arch:\s*(\w+)', destination).group(1)
        if state['architecture'] not in runtime['supportedArchitectures']:
            raise RuntimeError('Xcode destination architecture is unsupported by selected runtime')
        state['architecture_evidence'] = destination.strip()
        # Run 44248480774 compiled successfully, but its immediate cold-boot install,
        # screenshot and simulator log all timed out before either selected UI case.
        # Start only this owned device before compilation so its first-boot services
        # can settle during the real build; retain host/command timing for diagnosis.
        command(['sysctl', 'hw.memsize', 'hw.ncpu'], 'before-boot-host-resources.txt')
        command(['vm_stat'], 'before-boot-memory.txt')
        command(['ps', '-axo', 'pid,ppid,%cpu,%mem,state,etime,comm'], 'before-boot-processes.txt')
        command(['xcrun', 'simctl', 'boot', simulator], 'boot.log')
        command(['xcrun', 'simctl', 'bootstatus', simulator, '-b'], 'bootstatus.log', timeout=300)
        derived = Path(os.environ['SPLIT_DERIVED_DATA'])
        base = ['xcodebuild', '-project', 'AI_HLY.xcodeproj', '-scheme', 'HanlinMiniApps',
                '-destination', 'platform=iOS Simulator,id='+simulator, '-parallel-testing-enabled', 'NO',
                '-derivedDataPath', str(derived), *package_arguments,
                # Preserve the original target's simulator entitlements. An
                # unsigned build cannot exercise widget/package publication.
                'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGNING_REQUIRED=YES', 'CODE_SIGN_IDENTITY=-']
        build = base + ['build-for-testing', '-resultBundlePath', str(EVIDENCE/'Build.xcresult')]
        state['build_command'] = build
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
            fixtures = [
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
            passed, failed = summary.get('passedTests',0), summary.get('failedTests',0)
            command(['xcrun', 'xcresulttool', 'get', 'test-results', 'tests',
                '--path', str(result)], 'test-nodes.json')
            command([sys.executable, 'Scripts/CI/verify_selected_tests.py',
                '--results', str(EVIDENCE/'test-nodes.json'), '--selectors', ','.join(selectors)],
                'requested-tests.log')
            if process.returncode == 0 and passed == expected_tests and failed == 0 and summary.get('skippedTests',0) == 0:
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
        # No deletion/erase: preserve the dedicated device for failure diagnosis.
    return 0 if state['status'] == 'EXECUTED_PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
