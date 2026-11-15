#!/bin/bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)";cd "$root"
evidence="$root/build/chat-motion-ui-evidence";mkdir -p "$evidence"
phase=preflight;phase_started=$SECONDS
finish_phase(){ printf '%s\n' "$((SECONDS-phase_started))" > "$evidence/$phase-duration-seconds.txt";phase="$1";phase_started=$SECONDS; }
retain(){
  code=$?;last_phase="$phase";finish_phase diagnostics
  printf 'exit_code=%s\nphase=%s\n' "$code" "$last_phase" > "$evidence/process-status.txt"
  python3 "$root/Scripts/CI/generate_performance_report.py" --log-dir "$evidence" \
    --run-id "${GITHUB_RUN_ID:-}" --commit-sha "$(git -C "$root" rev-parse HEAD)" --event-name workflow_dispatch \
    --output-json "$evidence/ci-performance-report.json" --step-summary "${GITHUB_STEP_SUMMARY:-$evidence/step-summary.md}"
  return "$code"
}
trap retain EXIT
git rev-parse HEAD > "$evidence/source-sha.txt"
selected_xcode="$(python3 - <<'PY'
import glob,re,shutil
assert shutil.disk_usage('.').free>=10*1024**3
p=[x for x in glob.glob('/Applications/Xcode*.app') if re.search(r'/Xcode[_-]27(?:[._][0-9]+)*\.app$',x)]
p.sort(key=lambda x:tuple(map(int,re.findall(r'[0-9]+',x))));print(p[-1] if p else '')
PY
)"
[[ -n "$selected_xcode" ]] || { echo 'INFRA_ERROR no stable Xcode27';exit 2; }
export DEVELOPER_DIR="$selected_xcode/Contents/Developer"
if ! command -v xcodegen >/dev/null; then brew install xcodegen > "$evidence/xcodegen-install.log" 2>&1; fi
{ xcodebuild -version;xcrun swift --version;xcodebuild -showsdks;sw_vers;uname -m;xcodegen --version; } > "$evidence/preflight.txt"
xcrun simctl list devices available -j > "$evidence/devices.json"
xcrun simctl list runtimes -j > "$evidence/runtimes.json"
device="$(python3 - "$evidence/devices.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]));pairs=[(runtime,x) for runtime,devices in sorted(d['devices'].items()) if 'iOS-27' in runtime for x in devices if 'iPad' in x['name'] and x['isAvailable']]
assert pairs,'INFRA_ERROR no available iPad27 simulator';print(pairs[0][1]['udid'])
PY
)"
echo "$device" > "$evidence/selected-device.txt"
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/hanlin-motion-ui.XXXXXXXX")"
python3 docs/chat-motion/prepare_motion_ui.py --output "$scratch/proof" > "$evidence/preparation.json"
cp "$scratch/proof/project.json" "$scratch/proof/proof-inputs.json" "$evidence/"
tar -czf "$evidence/owned-sources.tar.gz" -C "$scratch/proof" Production App UITests project.json
cd "$scratch/proof";xcodegen generate --spec project.json > "$evidence/xcodegen.log"
cp ChatMotionProof.xcodeproj/project.pbxproj "$evidence/generated-project.pbxproj"
python3 - "$evidence" <<'PY'
import json,subprocess,sys
from pathlib import Path
e=Path(sys.argv[1]);result=subprocess.run(['plutil','-convert','json','-o','-',str(e/'generated-project.pbxproj')],capture_output=True,text=True,timeout=5,check=True)
objects=json.loads(result.stdout)['objects']
target=next(x for x in objects.values() if x.get('isa')=='PBXNativeTarget' and x.get('name')=='ChatMotionProof')
configs=[objects[key] for key in objects[target['buildConfigurationList']]['buildConfigurations']]
assert all(x['buildSettings'].get('ASSETCATALOG_COMPILER_APPICON_NAME')=='' for x in configs),'Target app icon preset must be overridden, project-only override is insufficient'
(e/'generated-target-settings.json').write_text(json.dumps(configs,indent=2))
PY
finish_phase build
xcodebuild build-for-testing -project ChatMotionProof.xcodeproj -scheme ChatMotionProof \
  -destination "platform=iOS Simulator,id=$device" -destination-timeout 90 \
  -derivedDataPath "$scratch/DerivedData" CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "$evidence/build.log"
finish_phase boot
python3 - "$device" <<'PY'
import subprocess,sys
subprocess.run(['xcrun','simctl','boot',sys.argv[1]],capture_output=True,timeout=20)
subprocess.run(['xcrun','simctl','bootstatus',sys.argv[1],'-b'],timeout=90,check=True)
PY
finish_phase test
set +e
python3 "$root/docs/chat-motion/record_ui_run.py" --device "$device" --evidence "$evidence" -- \
  xcodebuild test-without-building -project ChatMotionProof.xcodeproj -scheme ChatMotionProof \
  -destination "platform=iOS Simulator,id=$device" -destination-timeout 60 \
  -derivedDataPath "$scratch/DerivedData" -resultBundlePath "$scratch/Motion.xcresult" \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 600 -maximum-test-execution-time-allowance 720 \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$evidence/test.log"
test_code=${PIPESTATUS[0]};set -e
finish_phase results
python3 - "$scratch/Motion.xcresult" "$device" "$evidence" <<'PY'
import json,shutil,subprocess,sys
from pathlib import Path
bundle=Path(sys.argv[1]);e=Path(sys.argv[3])
if bundle.exists():
    result=subprocess.run(['xcrun','xcresulttool','get','test-results','tests','--path',str(bundle),'--format','json'],capture_output=True,text=True,timeout=30,check=True)
    (e/'tests.json').write_text(result.stdout)
    subprocess.run(['tar','-czf',str(e/'Motion.xcresult.tar.gz'),'-C',str(bundle.parent),bundle.name],timeout=90,check=True)
    (e/'raw-result-status.json').write_text(json.dumps({'status':'FINALIZED_READABLE_ARCHIVED'}))
try:
    result=subprocess.run(['xcrun','simctl','get_app_container',sys.argv[2],'ai.hanlin.motion-proof','data'],capture_output=True,text=True,timeout=5,check=True)
    timeline=Path(result.stdout.strip())/'Documents/motion-geometry-timeline.json'
    if timeline.exists():shutil.copyfile(timeline,e/timeline.name)
except (OSError,subprocess.SubprocessError):pass
PY
[[ "$test_code" == 0 ]] || exit "$test_code"
python3 - "$evidence" <<'PY'
import json,sys
from pathlib import Path
e=Path(sys.argv[1]);found=[]
def visit(n):
    if isinstance(n,dict):
        if n.get('nodeType')=='Test Case':found.append(n)
        for v in n.values():visit(v)
    elif isinstance(n,list):
        for v in n:visit(v)
visit(json.loads((e/'tests.json').read_text()))
expected={'MotionUITests/'+name+'()' for name in ['testAAllFivePresetsTwentyCompleteCyclesEach','testBRapidReversalPresetSwitchAndPersistence','testCReadableLongContentRTLTypeOrientationAndCompletion']}
assert len(found)==3 and {n['nodeIdentifier'] for n in found}==expected and all(n['result']=='Passed' for n in found)
timeline=json.loads((e/'motion-geometry-timeline.json').read_text());assert {n['preset'] for n in timeline}=={'v1.relaxed','v1.height-reveal','v1.gentle-squeeze','v1.quiet-fade','v1.none'}
assert json.loads((e/'video-status.json').read_text())['exit_code']==0 and (e/'motion-first120s.mp4').stat().st_size>1024
(e/'result-validation.json').write_text(json.dumps({'status':'EXECUTED_PASS','methods':3,'cycles_per_preset':20,'scope':'native components; original app/renderer/scroll/iPad26/physical NOT_RUN'}))
PY
finish_phase complete
