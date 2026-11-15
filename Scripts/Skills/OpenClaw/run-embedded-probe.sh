#!/bin/bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
evidence="$root/build/openclaw-embedded-evidence"
mkdir -p "$evidence"
started=$SECONDS
finish_openclaw_probe() {
  local rc="$?"
  if [[ ! -s "$evidence/summary.json" && "$rc" == 0 ]]; then rc=1; fi
  printf '%s\n' "$((SECONDS-started))" > "$evidence/openclaw-probe-total-duration-seconds.txt"
  printf '{"cost_estimates":{"baseline_full_run_minutes":0,"estimated_duration_minutes":0,"estimated_saved_minutes":0}}\n' > "$evidence/performance-context.json"
  python3 Scripts/CI/generate_performance_report.py --log-dir "$evidence" \
    --validation-plan "$evidence/performance-context.json" --run-id "${GITHUB_RUN_ID:-local}" \
    --commit-sha "$(git rev-parse HEAD)" --event-name workflow_dispatch \
    --output-json "$evidence/ci-performance-report.json" \
    --step-summary "${GITHUB_STEP_SUMMARY:-$evidence/step-summary.md}" --require-complete || { if [[ "$rc" == 0 ]]; then rc=1; fi; }
  printf '{"exit":%s,"measured_total_seconds":%s}\n' "$rc" "$((SECONDS-started))" > "$evidence/process-exit.json"
  trap - EXIT
  exit "$rc"
}
trap finish_openclaw_probe EXIT
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/hanlin-openclaw.XXXXXXXX")"
git rev-parse HEAD > "$evidence/tested-source-commit.txt"
git archive HEAD Scripts/Skills/OpenClaw Scripts/Runtime RuntimeDependencies.lock.json > "$evidence/tested-source.tar"
python3 - "$evidence" <<'PY_SOURCE'
import hashlib,json,subprocess,sys
from pathlib import Path
out=Path(sys.argv[1]);paths=subprocess.check_output(['git','ls-files','Scripts/Skills/OpenClaw','Scripts/Runtime','RuntimeDependencies.lock.json'],text=True).splitlines()
records={}
for name in paths:
    raw=Path(name).read_bytes();assert raw==subprocess.check_output(['git','show','HEAD:'+name]),name
    records[name]=hashlib.sha256(raw).hexdigest()
(out/'tested-source-sha256.json').write_text(json.dumps(records,indent=2))
PY_SOURCE
selected_xcode="$(python3 -c 'import glob,re; p=[p for p in glob.glob("/Applications/Xcode*.app") if re.search(r"/Xcode[_-]27(?:[._][0-9]+)*\.app$",p)]; p.sort(key=lambda x:tuple(map(int,re.findall(r"[0-9]+",x)))); print(p[-1] if p else "")')"
test -n "$selected_xcode"
export DEVELOPER_DIR="$selected_xcode/Contents/Developer"
{ xcodebuild -version; xcrun swift --version; xcrun --sdk iphonesimulator --show-sdk-version; uname -m; sw_vers; node --version; } > "$evidence/toolchain.txt"
xcrun simctl list devices available -j > "$evidence/devices.json"
xcrun simctl list runtimes -j > "$evidence/runtimes.json"
python3 Scripts/Runtime/runtime_native_identity.py --repository "$root" --verify-reuse > "$evidence/native-input-identity.txt"
(cd Scripts/Skills/OpenClaw && npm ci --ignore-scripts --no-audit --no-fund --workspaces=false && npm run fetch && npm run build) > "$evidence/original-source-build.log" 2>&1
git diff --exit-code -- Scripts/Skills/OpenClaw/generated > "$evidence/reproducible-artifact.diff"
cp Scripts/Skills/OpenClaw/generated/provenance.json "$evidence/openclaw-artifact-provenance.json"
cp Scripts/Skills/OpenClaw/package-lock.json "$evidence/build-tools-package-lock.json"
python3 - "$root" "$scratch" "$evidence" <<'PY_RUNTIME'
import importlib.util,json,sys
from pathlib import Path
root,scratch,out=map(Path,sys.argv[1:]);pin=json.loads((root/'Scripts/Skills/OpenClaw/native-runtime.json').read_text());lock=json.loads((root/'RuntimeDependencies.lock.json').read_text())
assert pin['bundleSHA256']==lock['runtimeBundle']['sha256'] and pin['nodeXCFrameworkSHA256']==lock['node']['xcframeworkSha256']
assert pin['nativeInputSHA256']==lock['runtimeBundle']['nativeInputSHA256']==(out/'native-input-identity.txt').read_text().strip()
spec=importlib.util.spec_from_file_location('original_runtime_source',root/'Scripts/Runtime/runtime_bundle_source.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
download=scratch/'runtime-download';download.mkdir()
archive=module.download_candidate(lock['runtimeBundle']['releaseRepository'],str(pin['producerRunID']),lock['runtimeBundle']['artifactDependencyHash'],pin['bundleSHA256'],download)
(out/'runtime-archive-path.txt').write_text(str(archive))
(out/'native-runtime-pin.json').write_text(json.dumps(pin,indent=2))
PY_RUNTIME
runtime_archive="$(cat "$evidence/runtime-archive-path.txt")"
mkdir -p "$scratch/runtime"
ditto -x -k "$runtime_archive" "$scratch/runtime"
python3 - "$scratch/runtime" "$evidence" <<'PY_NATIVE_INPUT'
import hashlib,json,sys
from pathlib import Path
runtime,out=map(Path,sys.argv[1:]);pin=json.loads((out/'native-runtime-pin.json').read_text());provenance=json.loads((runtime/'RuntimeProvenance.json').read_text());smoke=json.loads((runtime/'NodeMobile-smoke.json').read_text())
lock=json.loads(Path('RuntimeDependencies.lock.json').read_text())
assert provenance['nodeXCFrameworkSha256']==pin['nodeXCFrameworkSHA256'] and provenance['nodeVersion']=='24.5.0'
assert provenance['nodeSourcePatches']==lock['node']['sourcePatches'] and provenance['nodeBuildConfiguration']==lock['node']['buildConfiguration']
assert smoke['ok'] and smoke['nodeVersion']=='24.5.0' and smoke.get('descriptorOwnership') and smoke.get('fdWarningCount')==0
(out/'original-native-provenance.json').write_text(json.dumps(provenance,indent=2))
(out/'original-node-smoke.json').write_text(json.dumps(smoke,indent=2))
binary=runtime/'NodeMobile.xcframework/ios-arm64-simulator/NodeMobile.framework/NodeMobile'
(out/'original-node-framework-sha256.txt').write_text(hashlib.sha256(binary.read_bytes()).hexdigest()+'\n')
PY_NATIVE_INPUT
bash Scripts/Runtime/prepare-node-source.sh "$scratch/node-source" > "$evidence/prepare-node-source.log" 2>&1
mkdir -p "$scratch/node-source/out_ios"
ditto "$scratch/runtime/NodeMobile.xcframework" "$scratch/node-source/out_ios/NodeMobile.xcframework"
python3 - "$scratch/node-source" "$root/Scripts/Skills/OpenClaw" "$evidence" <<'PY_FIXTURE'
import hashlib,json,shutil,sys
from pathlib import Path
source,probe,out=map(Path,sys.argv[1:]);test=(source/'test').resolve();test.relative_to(source.resolve())
shutil.rmtree(test);fixture=test/'fixtures/hanlin-openclaw';fixture.mkdir(parents=True)
files=['native-probe.mjs','generated/requirements.js','generated/upstream-requirements-tests.js','generated/native-contract.mjs','generated/provenance.json','generated/LICENSE.OpenClaw.txt']
records={}
for name in files:
    target=fixture/name;target.parent.mkdir(exist_ok=True,parents=True);shutil.copyfile(probe/name,target);records[name]=hashlib.sha256(target.read_bytes()).hexdigest()
(out/'fixture-sha256.json').write_text(json.dumps(records,indent=2))
PY_FIXTURE
python3 Scripts/Runtime/run-with-heartbeat.py --log "$evidence/sample-build.log" \
  --summary "$evidence/sample-build-heartbeat.log" --object-root "$scratch/DerivedData" --timeout 900 \
  -- xcodebuild -project "$scratch/node-source/tools/mobile-test/ios/testnode/testnode.xcodeproj" \
  -target testnode -configuration Release -sdk iphonesimulator -arch arm64 \
  SYMROOT="$scratch/DerivedData/Build/Products" IPHONEOS_DEPLOYMENT_TARGET=26.0 \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= build
app="$(find "$scratch/DerivedData/Build/Products" -path '*Release-iphonesimulator/testnode.app' -type d -print -quit)"
test -n "$app"
python3 - "$evidence" "$app" <<'PY_EXECUTE'
import hashlib,json,secrets,subprocess,sys,time
from pathlib import Path
out,app=map(Path,sys.argv[1:]);inventory=json.loads((out/'devices.json').read_text());runtimes={r['identifier']:r for r in json.loads((out/'runtimes.json').read_text())['runtimes']}
candidates=[(runtime,d) for runtime,devices in inventory['devices'].items() if runtime.startswith('com.apple.CoreSimulator.SimRuntime.iOS-27-') for d in devices if d.get('isAvailable') and d['name'].startswith('iPhone')]
assert candidates,'Actual allowed iOS27 runtime/device unavailable'
runtime,device=sorted(candidates,key=lambda item:(item[1].get('state')!='Booted',item[1]['name']))[0];udid=device['udid'];identifier='nodejsmobile.test'
def call(args,timeout=30):return subprocess.check_output(args,stderr=subprocess.STDOUT,text=True,timeout=timeout)
def terminate_owned():
    result=subprocess.run(['xcrun','simctl','terminate',udid,identifier],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=30)
    with (out/'owned-app-termination.log').open('a') as log:log.write(str(result.returncode)+' '+result.stdout+'\n')
with (out/'simulator-readiness.log').open('w') as log:
    if device['state']=='Shutdown':subprocess.run(['xcrun','simctl','boot',udid],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=120)
    subprocess.run(['xcrun','simctl','bootstatus',udid,'-b'],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=150)
call(['xcrun','simctl','install',udid,str(app)],timeout=180)
container=Path(call(['xcrun','simctl','get_app_container',udid,identifier,'data'],timeout=5).strip())
(out/'actual-destination.json').write_text(json.dumps({'device':device,'runtime':runtimes[runtime],'container':str(container)},indent=2))
call(['xcrun','simctl','launch',udid,identifier,'--copy-path-for-testing'])
fixture=container/'Documents/test/fixtures/hanlin-openclaw';deadline=time.monotonic()+30
expected=json.loads((out/'fixture-sha256.json').read_text())
while time.monotonic()<deadline:
    if all((fixture/name).is_file() for name in expected):break
    time.sleep(.1)
else:raise SystemExit('Owned sample app did not copy the exact probe payload')
for name,digest in expected.items():assert hashlib.sha256((fixture/name).read_bytes()).hexdigest()==digest,name
terminate_owned()
result=container/'Documents/hanlin-openclaw-probe.json'
result.resolve().relative_to(container.resolve())
if result.exists():result.unlink()
challenge=secrets.token_hex(16);(out/'execution-challenge.txt').write_text(challenge+'\n')
call(['xcrun','simctl','launch',udid,identifier,'--jitless','--wasm-jitless','./test/fixtures/hanlin-openclaw/native-probe.mjs',challenge])
deadline=time.monotonic()+60
while time.monotonic()<deadline:
    if result.is_file():
        try:report=json.loads(result.read_text());break
        except ValueError:pass
    time.sleep(.1)
else:raise SystemExit('Embedded probe did not produce a complete result within60s')
data=result.read_bytes();(out/'embedded-node-result.json').write_bytes(data)
terminate_owned()
assert report['ok'] and report['node']=='24.5.0' and '--jitless' in report['execArgv'] and '--wasm-jitless' in report['execArgv']
assert report['arch']=='arm64' and report['platform'] in ('ios','darwin')
assert report['challenge']==challenge
artifact=json.loads((out/'openclaw-artifact-provenance.json').read_text())
assert report['artifactIdentity']=={key:artifact[key] for key in ['revision','artifactSHA256','nativeContractArtifactSHA256']}
assert len(report['cases'])==6 and len({c['name'] for c in report['cases']})==6 and all(c['status']=='EXECUTED_PASS' for c in report['cases'])
assert report['skillExecution']=='NOT_RUN' and report['physicalIPadStartupAndRAM']=='NOT_RUN'
(out/'summary.json').write_text(json.dumps({'status':'EXECUTED_PASS','scope':'Original requirements subset only, actual existing embedded Node/JITless on iOS27; synthetic scoped facts, no Skills executed','cases':report['cases'],'upstreamOriginalTests':5,'upstreamOriginalAssertions':16,'resultSHA256':hashlib.sha256(data).hexdigest(),'not_run':['physical iPad startup/RAM','full Hanlin app','selection/disabled','install hints','tool visibility','Runtime05 integration']},indent=2))
PY_EXECUTE
