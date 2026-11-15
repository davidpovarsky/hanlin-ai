"""Run the real target on a new disposable simulator, retaining authentic evidence."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path(os.environ['SPLIT_EVIDENCE'])


def command(argv, name, timeout=60):
    try:
        result = subprocess.run(argv, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        (EVIDENCE / name).write_bytes(error.stdout or b'No output before subprocess timeout.')
        raise
    (EVIDENCE / name).write_bytes(result.stdout)
    if result.returncode:
        raise RuntimeError(f'{argv[0]} exit {result.returncode}; see {name}')
    return result.stdout.decode()


def main():
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    state = {'status': 'INFRA_ERROR', 'ui': 'NOT_RUN', 'xcresult': 'NOT_CREATED',
             'scope': 'standalone MiniApps target only; two-app migration/transport/device acceptance OPEN',
             'reused_passes': [], 'started_at': time.time()}
    simulator = None
    try:
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
        state['impact'] = 'New app target, explicit shared host sources, authorization extraction and AI-only DI: no earlier app acceptance is reusable.'
        command(['xcodebuild', '-list', '-json', '-project', 'AI_HLY.xcodeproj'], 'schemes.json', timeout=600)
        resolved = ROOT/'AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
        (EVIDENCE/'Package.resolved').write_bytes(resolved.read_bytes())
        runtimes = json.loads(command(['xcrun', 'simctl', 'list', 'runtimes', '-j'], 'runtimes.json'))['runtimes']
        sdk = command(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'], 'simulator-sdk.txt').strip()
        runtime = next(r for r in runtimes if r.get('isAvailable') and not r.get('isInternal')
                       and r['identifier'].endswith('iOS-'+sdk.replace('.', '-')))
        types = json.loads(command(['xcrun', 'simctl', 'list', 'devicetypes', '-j'], 'devicetypes.json'))['devicetypes']
        supported = {t['identifier'] for t in runtime['supportedDeviceTypes']}
        device = next(t for t in types if t.get('productFamily') == 'iPhone' and t['identifier'] in supported)
        simulator = command(['xcrun', 'simctl', 'create', 'HanlinSplit-'+os.environ.get('GITHUB_RUN_ID','local'),
                             device['identifier'], runtime['identifier']], 'created-simulator.txt').strip()
        state.update(simulator=simulator, runtime=runtime, device=device)
        destinations = command(['xcodebuild', '-project', 'AI_HLY.xcodeproj', '-scheme', 'HanlinMiniApps',
                                '-showdestinations'], 'destinations.log', timeout=120)
        destination = next(line for line in destinations.splitlines() if simulator.lower() in line.lower())
        state['architecture'] = re.search(r'arch:\s*(\w+)', destination).group(1)
        if state['architecture'] not in runtime['supportedArchitectures']:
            raise RuntimeError('Xcode destination architecture is unsupported by selected runtime')
        state['architecture_evidence'] = destination.strip()
        derived = Path(os.environ['RUNNER_TEMP'])/'HanlinSplitDerivedData'
        base = ['xcodebuild', '-project', 'AI_HLY.xcodeproj', '-scheme', 'HanlinMiniApps',
                '-destination', 'platform=iOS Simulator,id='+simulator, '-parallel-testing-enabled', 'NO',
                '-derivedDataPath', str(derived), 'CODE_SIGNING_ALLOWED=NO']
        build = base + ['build-for-testing', '-resultBundlePath', str(EVIDENCE/'Build.xcresult')]
        state['build_command'] = build
        state['status'] = 'BUILD_FAILED'
        command(build, 'build.log', timeout=1200)
        state['build'] = 'EXECUTED_PASS'
        state['status'] = 'BUILD_FAILED'
        app_product = derived/'Build/Products/Debug-iphonesimulator/HanlinMiniApps.app'
        membership = json.loads((ROOT/'docs/product-split/target-membership.json').read_text())
        for resource in membership.get('shared_resources', []):
            source = ROOT/resource
            if source.suffix == '.xcstrings':
                continue  # Xcode compiles string catalogs into localized resources.
            destination = app_product/source.name
            if not destination.is_file() or hashlib.sha256(destination.read_bytes()).digest() != hashlib.sha256(source.read_bytes()).digest():
                raise RuntimeError('Built app is missing or changed an existing Runtime resource: '+resource)
        state['status'] = 'INFRA_ERROR'
        devices = json.loads(command(['xcrun','simctl','list','devices','-j'], 'device-state.json'))['devices']
        device_state = next(d for group in devices.values() for d in group if d['udid'] == simulator)['state']
        if device_state != 'Booted':
            command(['xcrun', 'simctl', 'boot', simulator], 'boot.log')
        command(['xcrun', 'simctl', 'bootstatus', simulator, '-b'], 'bootstatus.log', timeout=180)
        command([sys.executable, 'Scripts/CI/stage_scriptui_fixtures.py',
                 '--simulator-udid', simulator,
                 '--app-path', str(app_product),
                 '--bundle-id', 'com.itorah.hanlinminiapps',
                 '--fixtures-dir', str(EVIDENCE/'fixtures'),
                 '--log-file', str(EVIDENCE/'fixture-provenance.log')], 'fixture-staging.log', timeout=240)
        argv = base + ['test-without-building',
                '-resultBundlePath', str(EVIDENCE/'MiniApps.xcresult'),
                '-only-testing:HanlinMiniAppsUITests']
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
            if process.returncode == 0 and passed == 4 and failed == 0 and summary.get('skippedTests',0) == 0:
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
        if simulator:
            for argv,name in [(['xcrun','simctl','io',simulator,'screenshot',str(EVIDENCE/'failure.png')],'screenshot.log'),
                              (['xcrun','simctl','spawn',simulator,'log','show','--last','3m','--style','compact','--predicate','process == "HanlinMiniApps"'],'simulator.log')]:
                try: command(argv,name,timeout=30)
                except Exception as capture: state.setdefault('capture_errors',[]).append(str(capture))
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
