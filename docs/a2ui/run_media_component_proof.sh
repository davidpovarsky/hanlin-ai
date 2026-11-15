#!/bin/bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
evidence="$root/build/chat-media-component-evidence"
mkdir -p "$evidence"
proof_phase=preflight
proof_phase_started=$SECONDS
finish_phase() {
  printf '%s\n' "$((SECONDS-proof_phase_started))" > "$evidence/$proof_phase-duration-seconds.txt"
  proof_phase="$1"
  proof_phase_started=$SECONDS
}
git rev-parse HEAD > "$evidence/source-sha.txt"
phase=preflight
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/hanlin-media-proof.XXXXXXXX")"
retain() {
  status="$?"
  finish_phase diagnostics
  python3 - "$status" "$phase" "$evidence" <<'PY'
import json,subprocess,sys
from pathlib import Path
e=Path(sys.argv[3]);status=int(sys.argv[1]);phase=sys.argv[2]
result='EXECUTED_PASS' if status==0 else ('INFRA_ERROR' if phase=='preflight' else 'BUILD_OR_TEST_FAILED')
tests=e/'tests.json';nodes=[]
def visit(n):
    if isinstance(n,dict):
        if n.get('nodeType')=='Test Case':nodes.append(n)
        for v in n.values():visit(v)
    elif isinstance(n,list):
        for v in n:visit(v)
if tests.exists():
    try:visit(json.loads(tests.read_text()))
    except (ValueError,OSError):pass
if status and phase!='preflight':
    log=(e/'xcodebuild.log').read_text(errors='replace') if (e/'xcodebuild.log').exists() else ''
    result='TEST_FAILED' if nodes else ('BUILD_FAILED' if 'error:' in log else 'INFRA_ERROR')
if status and (e/'selected-device.txt').exists():
    device=(e/'selected-device.txt').read_text().strip()
    diagnostics={}
    for name,args in [('screenshot',['xcrun','simctl','io',device,'screenshot',str(e/'failure.png')]),
                      ('simulator-log',['xcrun','simctl','spawn',device,'log','show','--last','2m','--style','compact'])]:
        try:
            r=subprocess.run(args,capture_output=True,text=True,timeout=5)
            diagnostics[name]={'exit_code':r.returncode}
            (e/(name+'.txt')).write_text(r.stdout+r.stderr)
        except (subprocess.TimeoutExpired,OSError) as err:diagnostics[name]={'unavailable':type(err).__name__}
    diagnostics['accessibility']='NOT_AVAILABLE: component unit runner has no app UI/XCUITest hierarchy'
    (e/'failure-diagnostics.json').write_text(json.dumps(diagnostics,indent=2))
(e/'process-status.json').write_text(json.dumps({'exit_code':status,'status':result,'phase':phase,
    'executed_cases':len(nodes),'xcresult_exists':(e/'Media.xcresult').exists(),
    'scope':'native SDK component only; playback/full-app XCUITest NOT_RUN'},indent=2))
PY
  finish_phase complete
  python3 Scripts/CI/generate_performance_report.py --log-dir "$evidence" \
    --run-id "${GITHUB_RUN_ID:-}" --commit-sha "$(git rev-parse HEAD)" \
    --event-name "${GITHUB_EVENT_NAME:-workflow_dispatch}" \
    --output-json "$evidence/ci-performance-report.json" --step-summary "${GITHUB_STEP_SUMMARY:-$evidence/step-summary.md}"
  return "$status"
}
trap retain EXIT
df -h . > "$evidence/disk.txt"
selected_xcode="$(python3 - <<'PY'
import glob,re
p=[x for x in glob.glob('/Applications/Xcode*.app') if re.search(r'/Xcode[_-]27(?:[._][0-9]+)*\.app$',x)]
p.sort(key=lambda x:tuple(map(int,re.findall(r'[0-9]+',x))))
print(p[-1] if p else '')
PY
)"
[[ -n "$selected_xcode" ]] || { echo 'INFRA_ERROR: stable Xcode27 unavailable'; exit 2; }
export DEVELOPER_DIR="$selected_xcode/Contents/Developer"
{
  xcodebuild -version
  xcrun swift --version
  xcodebuild -showsdks
  uname -m
  for cli in python3 maestro idb; do command -v "$cli" || true; done
} > "$evidence/preflight.txt"
skill="$HOME/.codex/skills/ios-simulator-skill/scripts/sim_health_check.sh"
if [[ -f "$skill" ]]; then bash "$skill" > "$evidence/skill-health.txt" 2>&1 || true
else echo 'NOT_AVAILABLE on runner; Xcode simulator tests do not require idb/Maestro.' > "$evidence/skill-health.txt"; fi
xcrun simctl list runtimes -j > "$evidence/runtimes.json"
xcrun simctl list devices available -j > "$evidence/devices.json"
python3 - "$evidence/devices.json" <<'PY' > "$evidence/selected-device.txt"
import json,shutil,subprocess,sys
assert shutil.disk_usage('.').free>=10*1024**3,'Less than10GiB free'
sdk=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-version'],text=True).strip()
assert int(sdk.split('.')[0])>=27
devices=json.load(open(sys.argv[1]))['devices']
eligible=[d for runtime,rows in devices.items() if '.iOS-27-' in runtime for d in rows
          if d.get('isAvailable') and d['name'].startswith('iPhone')]
assert eligible,'No actual available iPhone/iOS27 runtime'
print(eligible[0]['udid'])
PY
device="$(cat "$evidence/selected-device.txt")"
python3 docs/a2ui/prepare_media_proof.py --output "$scratch/harness" > "$evidence/preparation.json"
cp "$scratch/harness/Package.swift" "$scratch/harness/proof-inputs.json" "$evidence/"
(
  cd "$scratch/harness"
  xcodebuild -list -json
) > "$evidence/schemes.json"
scheme="$(python3 - "$evidence/schemes.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]));s=d.get('workspace',{}).get('schemes',[])+d.get('project',{}).get('schemes',[])
print(next(x for x in ['HanlinChatMediaProof-Package','HanlinChatMediaProof'] if x in s))
PY
)"
printf '%s\n' "$scheme" > "$evidence/selected-scheme.txt"
(cd "$scratch/harness"; xcodebuild -scheme "$scheme" -showdestinations) > "$evidence/destinations.txt"
grep -q "$device" "$evidence/destinations.txt" || { echo 'INFRA_ERROR: destination not supported by actual scheme'; exit 2; }
phase=build-and-test
finish_phase build-and-test
set +e
(
  cd "$scratch/harness"
  xcodebuild test -scheme "$scheme" -configuration Debug -destination "platform=iOS Simulator,id=$device" \
    -parallel-testing-enabled NO -derivedDataPath "$scratch/DerivedData" \
    -resultBundlePath "$evidence/Media.xcresult" -only-testing:HanlinChatMediaProofTests/HanlinYouTubeTests \
    CODE_SIGNING_ALLOWED=NO
) 2>&1 | tee "$evidence/xcodebuild.log"
test_status=${PIPESTATUS[0]}
set -e
finish_phase result-verification
if [[ -d "$evidence/Media.xcresult" ]]; then
  xcrun xcresulttool get test-results tests --path "$evidence/Media.xcresult" --format json > "$evidence/tests.json" || true
fi
[[ "$test_status" == 0 ]] || exit "$test_status"
python3 - "$evidence" <<'PY'
import json,sys
from pathlib import Path
e=Path(sys.argv[1]);expected=json.loads((e/'proof-inputs.json').read_text())['cases'];found={}
def visit(n):
    if isinstance(n,dict):
        if n.get('nodeType')=='Test Case':found.setdefault(n.get('name','').removesuffix('()'),[]).append(n.get('result'))
        for v in n.values():visit(v)
    elif isinstance(n,list):
        for v in n:visit(v)
visit(json.loads((e/'tests.json').read_text()))
assert set(found)==set(expected) and all(x==['Passed'] for x in found.values()),found
(e/'result-validation.json').write_text(json.dumps({'status':'EXECUTED_PASS','cases':len(found),'scope':'identity/document and iOS source compilation; playback/UI NOT_RUN'}))
PY
