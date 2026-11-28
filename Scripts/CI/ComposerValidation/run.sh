#!/bin/bash
set -euo pipefail
run_bounded() {
  python3 - "$@" <<'PY'
import os,signal,subprocess,sys
p=subprocess.Popen(sys.argv[2:],start_new_session=True)
try:status=p.wait(timeout=max(1,int(sys.argv[1])-5))
except subprocess.TimeoutExpired:
    os.killpg(p.pid,signal.SIGINT)
    try:p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid,signal.SIGKILL);p.wait()
    print('Owned Composer CI command exceeded its retention budget',file=sys.stderr)
    status=124
sys.exit(status)
PY
}

root="$(git rev-parse --show-toplevel)"
cd "$root"
evidence="$root/build/composer-validation-evidence"
mkdir -p "$evidence"
actual_sha="$(git rev-parse HEAD)"
diagnostic="${COMPOSER_SDK_ELIGIBILITY_DIAGNOSTIC:-0}"
[[ "${COMPOSER_EXPECTED_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || { echo 'Exact 40-character COMPOSER_EXPECTED_SHA is required' >&2; exit 2; }
[[ "$actual_sha" == "$COMPOSER_EXPECTED_SHA" ]] || { echo "Commit mismatch: $actual_sha" >&2; exit 2; }
component_sha="$actual_sha"
if [[ "$diagnostic" == 1 ]]; then
  component_sha=e8ccd81452843609285a0cd7e017a759bda6a6ef
  if ! git cat-file -e "$component_sha^{commit}" 2>/dev/null; then
    run_bounded 120 git fetch --no-tags --depth=1 origin "$component_sha"
  fi
  python3 - "$component_sha" <<'PY'
from pathlib import Path
import subprocess,sys
for path in ['Scripts/CI/ComposerValidation/Package.swift','Scripts/CI/ComposerValidation/prepare_capability_proof.py']:
    assert Path(path).read_bytes()==subprocess.check_output(['git','show',sys.argv[1]+':'+path]),path
PY
fi
printf '%s\n' "$actual_sha" > "$evidence/workflow-commit.txt"

if [[ "$diagnostic" == 1 ]]; then
  selected_xcode=/Applications/Xcode_27.2.app
  [[ -x "$selected_xcode/Contents/Developer/usr/bin/xcodebuild" ]] || exit 2
else
  selected_xcode="$(python3 -c 'import glob,re; paths=[p for p in glob.glob("/Applications/Xcode*.app") if re.search(r"/Xcode[_-]27(?:[._][0-9]+)*\.app$",p)]; paths.sort(key=lambda p: tuple(map(int, re.findall(r"[0-9]+", p)))); print(paths[-1] if paths else "")')"
fi
[[ -n "$selected_xcode" ]] || { echo 'No stable installed Xcode found' >&2; exit 2; }
export DEVELOPER_DIR="$selected_xcode/Contents/Developer"
xcodebuild -version | tee "$evidence/xcode-version.txt"
xcrun swift --version | tee "$evidence/swift-version.txt"
sw_vers > "$evidence/host-version.txt"
sdk_version="$(xcrun --sdk iphonesimulator --show-sdk-version)"
printf '%s\n' "$sdk_version" | tee "$evidence/ios-simulator-sdk-version.txt"
ios_major="${sdk_version%%.*}"
[[ "$ios_major" == 27 ]] || { echo 'Actual iOS Simulator SDK 27 required' >&2; exit 2; }
if [[ "$diagnostic" == 1 ]]; then
  python3 - "$evidence" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
assert (root/'xcode-version.txt').read_text().strip()=='Xcode 27.2\nBuild version 27B52'
assert 'Apple Swift version 6.4.2 ' in (root/'swift-version.txt').read_text()
assert (root/'ios-simulator-sdk-version.txt').read_text().strip()=='27.2'
PY
fi

scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/composer-proof.XXXXXXXX")"
package_dir="$scratch/ComposerValidation"
device=""
record_connection() {
  python3 - "$evidence" <<'PY'
import json,os,sys
from pathlib import Path
root=Path(sys.argv[1]);expected=set(json.loads((root/'proof-inputs.json').read_text())['expected_case_ids'])
def nodes(x):
    if isinstance(x,dict):
        yield x
        for v in x.values():yield from nodes(v)
    elif isinstance(x,list):
        for v in x:yield from nodes(v)
try:data=json.loads((root/'tests.json').read_text())
except (OSError,ValueError):data={}
cases=[n for n in nodes(data) if n.get('nodeType')=='Test Case'];authored=[n.get('nodeIdentifier') for n in cases if n.get('nodeIdentifier') in expected]
messages=[n.get('name','') for n in nodes(data) if n.get('nodeType')=='Failure Message']
state='established_with_authored_cases' if authored else 'failed_before_connection' if any('hung before establishing connection' in m for m in messages) else 'not_observed'
(root/'test-host-connection.json').write_text(json.dumps({'state':state,'basis':'actual xcresult export, not inferred from process exit','authored_cases':authored,'unexpected_case_nodes':[{'id':n.get('nodeIdentifier'),'result':n.get('result')} for n in cases if n.get('nodeIdentifier') not in expected],'failure_messages':messages},indent=2))
observed={n.get('nodeIdentifier'):n.get('result') for n in cases if n.get('nodeIdentifier') in expected}
(root/'case-observations.json').write_text(json.dumps({'scope':'diagnostic component only','cases':[{'id':name,'result':observed.get(name,'NOT_RUN')} for name in sorted(expected)],'unexpected_case_nodes':[{'id':n.get('nodeIdentifier'),'result':n.get('result')} for n in cases if n.get('nodeIdentifier') not in expected],'raw_devices':data.get('devices',[]),'metadata_target_settings':'UNAVAILABLE; prior explicit-SDK build settings returned []'},indent=2))
if os.environ.get('COMPOSER_SDK_ELIGIBILITY_DIAGNOSTIC')=='1':
    owned=(root/'simulator-udid.txt').read_text().strip() if (root/'simulator-udid.txt').exists() else None
    devices=data.get('devices',[])
    matched=bool(devices) and all(d.get('deviceId')==owned and d.get('modelName')=='iPhone 18 Pro' and d.get('osVersion')=='27.0' and d.get('osBuildNumber')=='24A434' and d.get('architecture')=='arm64' and d.get('platform')=='iOS Simulator' for d in devices)
    status='VERIFIED' if authored and matched else 'MISMATCH' if authored else 'NOT_OBSERVED'
    (root/'device-execution-binding.json').write_text(json.dumps({'status':status,'owned_udid':owned,'actual_devices':devices,'basis':'actual xcresult export','metadata_target_settings':'still unavailable'},indent=2))
    if authored and not matched:raise SystemExit('Authored cases ran on an unconfirmed execution context')
PY
}
finish() {
  local code="$?"
  set +e
  if [[ ! -s "$evidence/process-status.json" ]]; then
    printf '{"preparation_exit_code":%s,"xcodebuild_exit_code":null}\n' "$code" > "$evidence/process-status.json"
  fi
  if [[ -d "$evidence/Composer.xcresult" && ! -s "$evidence/tests.json" ]]; then
    run_bounded 120 xcrun xcresulttool get test-results tests --path "$evidence/Composer.xcresult" --format json > "$evidence/tests.json"
  fi
  if [[ -s "$evidence/proof-inputs.json" ]]; then record_connection; fi
  if [[ -n "$device" ]]; then run_bounded 60 xcrun simctl shutdown "$device" > "$evidence/owned-device-shutdown.log" 2>&1; fi
}
trap finish EXIT
trap 'exit 143' TERM
python3 Scripts/CI/ComposerValidation/prepare_capability_proof.py \
  --repo "$root" --source-sha "$component_sha" --output "$package_dir" --with-editor-tests \
  | tee "$evidence/preparation.json"
cp "$package_dir/proof-inputs.json" "$evidence/proof-inputs.json"
cp "$package_dir/Package.swift" "$evidence/Harness-Package.swift"
python3 - "$root" "$evidence/proof-inputs.json" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
inputs = json.loads(pathlib.Path(sys.argv[2]).read_text())
for path, digest in inputs['input_sha256'].items():
    if hashlib.sha256((root / path).read_bytes()).hexdigest() != digest:
        raise SystemExit(f'Git/checkout input mismatch: {path}')
PY
tar -C "$package_dir" -cf "$evidence/source-inputs.tar" Package.swift Sources Tests proof-inputs.json
printf '%s\n' "$component_sha" > "$evidence/source-commit.txt"
shasum -a 256 .github/workflows/build-ios26-unsigned-ipa.yml Scripts/CI/ComposerValidation/Package.swift Scripts/CI/ComposerValidation/run.sh Scripts/CI/ComposerValidation/verify_results.py Scripts/CI/ComposerValidation/prepare_capability_proof.py > "$evidence/harness-sha256.txt"
printf '%s\n' 'Scope: eight whole production component files; every declared Morph and UIKit editor case from the two complete owner test files, with exact identities in proof-inputs.json.' \
  'NOT covered: parity/session/manual dock resize, ChatViewBottom, popup live consumers, production app UI, physical device or reference parity.' > "$evidence/scope.txt"

xcrun simctl list -j > "$evidence/available-simulators.json"
device="$(python3 - "$evidence" <<'PY'
from datetime import datetime,timezone
import json,os,subprocess,sys,uuid
from pathlib import Path
evidence=Path(sys.argv[1]);data=json.loads((evidence/'available-simulators.json').read_text())
types=[t for t in data['devicetypes'] if t['name'].startswith('iPhone')]
if os.environ.get('COMPOSER_SDK_ELIGIBILITY_DIAGNOSTIC')=='1':
    runtimes=[r for r in data['runtimes'] if r.get('isAvailable') and r.get('version')=='27.0' and r.get('buildversion')=='24A434' and 'iOS-' in r['identifier']]
    models=[t for t in types if t['identifier']=='com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro']
    if not runtimes or not models:raise SystemExit('Required iOS27.0/24A434 + iPhone18Pro unavailable; no substitute/device created')
    runtime=runtimes[0];kind=models[0]['identifier']
    assert 'arm64' in runtime.get('supportedArchitectures',[]),runtime
else:
    runtime=next(r for r in data['runtimes'] if r.get('isAvailable') and r['version'].split('.')[0]=='27' and 'iOS-' in r['identifier'])
    available=[d for d in data['devices'].get(runtime['identifier'],[]) if d.get('isAvailable') and d['name'].startswith('iPhone')]
    kind=next((d.get('deviceTypeIdentifier') or next(t['identifier'] for t in types if t['name']==d['name']) for d in available),types[-1]['identifier'])
device=subprocess.check_output(['xcrun','simctl','create','Hanlin-Composer-'+uuid.uuid4().hex[:8],kind,runtime['identifier']],text=True,timeout=30).strip()
assert device not in {d['udid'] for values in data['devices'].values() for d in values}
context={'phase':'created','created_at_utc':datetime.now(timezone.utc).isoformat(),'device_id':device,'device_type':kind,'model':next(t['name'] for t in types if t['identifier']==kind),'runtime':runtime,'metadata_target_settings':'UNAVAILABLE; not inferred from CLI SDK or runtime'}
(evidence/'device-preflight.json').write_text(json.dumps(context,indent=2));print(device)
PY
)"
printf '%s\n' "$device" > "$evidence/simulator-udid.txt"
xcrun simctl boot "$device"
run_bounded 600 xcrun simctl bootstatus "$device" -b > "$evidence/owned-device-boot.log" 2>&1
xcrun simctl list -j > "$evidence/simulators-after-boot.json"
if [[ "$diagnostic" == 1 ]]; then
  scheme=ComposerValidation
  printf '{"scheme":"ComposerValidation","basis":"retained frozen prior scheme; no new list query"}\n' > "$evidence/scheme-reference.json"
else
  (
    cd "$package_dir"
    run_bounded 120 xcodebuild -list -json > "$evidence/schemes.json"
  )
  scheme="$(python3 - "$evidence/schemes.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
schemes = data.get("workspace", {}).get("schemes", []) + data.get("project", {}).get("schemes", [])
for candidate in ("ComposerValidation-Package", "ComposerValidation", "AI_Hanlin"):
    if candidate in schemes:
        print(candidate)
        break
else:
    raise SystemExit(f"No known Composer package test scheme; discovered {schemes}")
PY
)"
fi
printf '%s\n' "$scheme" > "$evidence/scheme.txt"
if [[ "$diagnostic" == 1 ]]; then
  set +e
  (cd "$package_dir" && run_bounded 120 xcodebuild -showdestinations -scheme "$scheme" -sdk iphonesimulator) > "$evidence/destinations.txt" 2> "$evidence/destinations.stderr"
  eligibility_status=$?
  set -e
  printf '{"exit_code":%s,"timeout_seconds":120,"SDK":"iphonesimulator","scheme":"ComposerValidation","action":"showdestinations","no_default_query":true}\n' "$eligibility_status" > "$evidence/eligibility-query.json"
  [[ "$eligibility_status" == 0 ]] || exit "$eligibility_status"
else
  (cd "$package_dir" && run_bounded 120 xcodebuild -showdestinations -scheme "$scheme") > "$evidence/destinations.txt" 2>&1
fi
python3 - "$evidence" <<'PY'
from datetime import datetime,timezone
import json,os,re,sys
from pathlib import Path
evidence=Path(sys.argv[1]);context=json.loads((evidence/'device-preflight.json').read_text());device=context['device_id']
after=json.loads((evidence/'simulators-after-boot.json').read_text())
actual=next(d for d in after['devices'][context['runtime']['identifier']] if d['udid']==device)
assert actual['state']=='Booted' and actual.get('isAvailable'),actual
context.update(phase='booted_destination_unconfirmed',boot_confirmed_at_utc=datetime.now(timezone.utc).isoformat(),actual_device=actual)
(evidence/'device-preflight.json').write_text(json.dumps(context,indent=2))
eligible=True;candidates=[];ineligible=[]
for line in (evidence/'destinations.txt').read_text().splitlines():
    if 'Ineligible destinations' in line:eligible=False
    if 'Destinations compatible' in line or 'Available destinations' in line:eligible=True
    if re.search(r'\bid:\s*'+re.escape(device)+r'(?:,|\s|})',line):
        if not eligible or re.search(r'\berror:',line,re.I):ineligible.append(line)
        else:candidates.append(line)
if ineligible:raise SystemExit('Owned simulator explicitly ineligible: '+str(ineligible))
if not candidates:
    raise SystemExit('Preflight cannot confirm the owned simulator in scheme destinations; no test command executed')
line=candidates[0]
arch=re.search(r'arch:([^,}]+)',line);os_version=re.search(r'OS:([^,}]+)',line)
assert re.search(r'platform:\s*iOS Simulator',line) and arch and arch[1].strip() in ['arm64','x86_64'] and os_version and os_version[1].strip().startswith('27.'),line
if os.environ.get('COMPOSER_SDK_ELIGIBILITY_DIAGNOSTIC')=='1':
    assert arch[1].strip()=='arm64' and os_version[1].strip()=='27.0',line
    assert context['runtime']['version']=='27.0' and context['runtime']['buildversion']=='24A434'
    assert context['device_type']=='com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro'
    assert not any(device in message and re.search(r'ineligible|error:',message,re.I) for message in (evidence/'destinations.stderr').read_text().splitlines())
context.update(phase='ready',ready_at_utc=datetime.now(timezone.utc).isoformat(),architecture=arch[1].strip(),os_version=os_version[1].strip(),destination=line,actual_device=actual)
(evidence/'device-preflight.json').write_text(json.dumps(context,indent=2))
PY

set +e
sdk_args=()
if [[ "$diagnostic" == 1 ]]; then sdk_args=(-sdk iphonesimulator -parallel-testing-enabled NO); fi
(
  cd "$package_dir"
  run_bounded 900 xcodebuild test -scheme "$scheme" "${sdk_args[@]}" \
    -destination "platform=iOS Simulator,id=$device" \
    -derivedDataPath "$scratch/DerivedData" \
    -resultBundlePath "$evidence/Composer.xcresult" \
    -only-testing:AI_HanlinTests/HanlinMorphComposerTests \
    -only-testing:AI_HanlinTests/NativeComposerLineSizingTests
) 2>&1 | tee "$evidence/xcodebuild.log"
build_status=${PIPESTATUS[0]}
set -e
printf '{"xcodebuild_exit_code":%s}\n' "$build_status" > "$evidence/process-status.json"
run_bounded 120 xcrun xcresulttool get test-results tests --path "$evidence/Composer.xcresult" --format json > "$evidence/tests.json"
record_connection
[[ "$build_status" == 0 ]] || exit "$build_status"
python3 Scripts/CI/ComposerValidation/verify_results.py "$evidence/tests.json" \
  --inputs "$evidence/proof-inputs.json" | tee "$evidence/verified-cases.txt"
