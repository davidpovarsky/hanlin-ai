"""Run the real target on a new disposable simulator, retaining authentic evidence."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path(os.environ['SPLIT_EVIDENCE'])


def command(argv, name, timeout=60):
    result = subprocess.run(argv, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
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
        sources = sorted(set(ROOT.glob('Packages/**/*.swift')) | set(ROOT.glob('HanlinMiniAppsApp/**/*.swift'))
                         | set(ROOT.glob('AI_HLY/**/*.swift')) | set(ROOT.glob('HanlinMiniAppsUITests/**/*.swift')))
        inputs = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
        for name in ['AI_HLY.xcodeproj/project.pbxproj', 'RuntimeDependencies.lock.json',
                     'AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved']:
            p = ROOT / name
            inputs[name] = hashlib.sha256(p.read_bytes()).hexdigest()
        (EVIDENCE / 'source-inputs.json').write_text(json.dumps(inputs, indent=2)+'\n')
        state['impact'] = 'New app target, explicit shared host sources, authorization extraction and AI-only DI: no earlier app acceptance is reusable.'
        command(['xcodebuild', '-list', '-json', '-project', 'AI_HLY.xcodeproj'], 'schemes.json', timeout=600)
        runtimes = json.loads(command(['xcrun', 'simctl', 'list', 'runtimes', '-j'], 'runtimes.json'))['runtimes']
        runtime = next(r for r in runtimes if r.get('isAvailable') and r['identifier'].endswith('iOS-27-0'))
        types = json.loads(command(['xcrun', 'simctl', 'list', 'devicetypes', '-j'], 'devicetypes.json'))['devicetypes']
        device = next(t for t in reversed(types) if t.get('productFamily') == 'iPhone')
        simulator = command(['xcrun', 'simctl', 'create', 'HanlinSplit-'+os.environ.get('GITHUB_RUN_ID','local'),
                             device['identifier'], runtime['identifier']], 'created-simulator.txt').strip()
        state.update(simulator=simulator, runtime=runtime, device=device)
        command(['xcrun', 'simctl', 'boot', simulator], 'boot.log')
        command(['xcrun', 'simctl', 'bootstatus', simulator, '-b'], 'bootstatus.log', timeout=180)
        state['architecture'] = command(['xcrun', 'simctl', 'spawn', simulator, 'uname', '-m'], 'architecture.txt').strip()
        argv = ['xcodebuild', 'test', '-project', 'AI_HLY.xcodeproj', '-scheme', 'HanlinMiniApps',
                '-destination', 'platform=iOS Simulator,id='+simulator, '-parallel-testing-enabled', 'NO',
                '-derivedDataPath', str(Path(os.environ['RUNNER_TEMP'])/'HanlinSplitDerivedData'),
                '-resultBundlePath', str(EVIDENCE/'MiniApps.xcresult'),
                '-only-testing:HanlinMiniAppsUITests', 'CODE_SIGNING_ALLOWED=NO']
        state['command'] = argv
        (EVIDENCE/'command.json').write_text(json.dumps(argv,indent=2)+'\n')
        with (EVIDENCE/'xcodebuild.log').open('wb') as log:
            process = subprocess.run(argv, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=1200)
        result = EVIDENCE/'MiniApps.xcresult'
        state['xcresult'] = 'CREATED' if result.exists() else 'NOT_CREATED: xcodebuild stopped before result bundle creation'
        state['status'] = 'BUILD_FAILED' if process.returncode else 'NOT_RUN'
        if result.exists():
            raw = command(['xcrun','xcresulttool','get','test-results','summary','--path',str(result)], 'test-summary.json')
            summary = json.loads(raw)
            state['summary'] = summary
            passed, failed = summary.get('passedTests',0), summary.get('failedTests',0)
            if process.returncode == 0 and passed == 3 and failed == 0 and summary.get('skippedTests',0) == 0:
                state.update(status='EXECUTED_PASS',ui='EXECUTED_PASS')
            elif failed:
                state.update(status='TEST_FAILED',ui='TEST_FAILED')
            else:
                state.update(status='BUILD_FAILED',ui='NOT_RUN')
        else:
            state.update(status='BUILD_FAILED',ui='NOT_RUN')
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
        state['duration_seconds'] = time.time()-state['started_at']
        (EVIDENCE/'acceptance.json').write_text(json.dumps(state,indent=2)+'\n')
        if simulator:
            subprocess.run(['xcrun','simctl','shutdown',simulator],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)
        # No deletion/erase: preserve the dedicated device for failure diagnosis.
    return 0 if state['status'] == 'EXECUTED_PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
