#!/bin/bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)";cd "$root"
evidence="$root/build/chat-motion-ui-evidence";mkdir -p "$evidence"
phase=preflight;phase_started=$SECONDS
finish_phase(){ printf '%s\n' "$((SECONDS-phase_started))" > "$evidence/$phase-duration-seconds.txt";phase="$1";phase_started=$SECONDS; }
retain(){
  code=$?;last_phase="$phase";finish_phase diagnostics
  if [[ "${device_strategy:-}" == fresh && -n "${device:-}" ]]; then
    cleanup_code=0
    python3 - "$device" "$evidence/verified-environment.json" "Hanlin-Phase2-Motion-${GITHUB_RUN_ID:-local}" > "$evidence/owned-simulator-cleanup.log" 2>&1 <<'PY' || cleanup_code=$?
import json,subprocess,sys
from pathlib import Path
selected=json.loads(Path(sys.argv[2]).read_text())['device']
assert selected['udid']==sys.argv[1] and selected['name']==sys.argv[3], 'Only this run-owned simulator can be removed'
subprocess.run(['xcrun','simctl','shutdown',selected['udid']],check=False,timeout=20)
subprocess.run(['xcrun','simctl','delete',selected['udid']],check=True,timeout=20)
print(json.dumps({'status':'OWNED_SIMULATOR_REMOVED','device':selected['udid']}))
PY
    if [[ "$code" == 0 && "$cleanup_code" != 0 ]]; then code="$cleanup_code"; fi
  fi
  printf 'exit_code=%s\nphase=%s\n' "$code" "$last_phase" > "$evidence/process-status.txt"
  python3 "$root/Scripts/CI/generate_performance_report.py" --log-dir "$evidence" \
    --run-id "${GITHUB_RUN_ID:-}" --commit-sha "$(git -C "$root" rev-parse HEAD)" --event-name workflow_dispatch \
    --output-json "$evidence/ci-performance-report.json" --step-summary "${GITHUB_STEP_SUMMARY:-$evidence/step-summary.md}"
  return "$code"
}
trap retain EXIT
git rev-parse HEAD > "$evidence/source-sha.txt"
selected_xcode="$(python3 Scripts/CI/select_stable_xcode.py)"
export DEVELOPER_DIR="$selected_xcode/Contents/Developer"
if ! command -v xcodegen >/dev/null; then brew install xcodegen > "$evidence/xcodegen-install.log" 2>&1; fi
{ xcodebuild -version;xcrun swift --version;xcodebuild -showsdks;sw_vers;uname -m;xcodegen --version; } > "$evidence/preflight.txt"
xcrun simctl list devices available -j > "$evidence/devices.json"
xcrun simctl list runtimes -j > "$evidence/runtimes.json"
device_strategy="${HANLIN_MOTION_DEVICE_STRATEGY:-ready}"
if [[ "$device_strategy" == fresh ]]; then
  device="$(python3 Scripts/CI/select_installed_simulator.py --output "$evidence/verified-environment.json" --create-owned "Hanlin-Phase2-Motion-${GITHUB_RUN_ID:-local}")"
else
  [[ "$device_strategy" == ready ]]
  selected_device_args=()
  if [[ -n "${HANLIN_MOTION_PREPARED_DEVICE_FILE:-}" ]]; then
    test -f "$HANLIN_MOTION_PREPARED_DEVICE_FILE"
    prepared_device="$(tr -d '\r\n' < "$HANLIN_MOTION_PREPARED_DEVICE_FILE")"
    test -n "$prepared_device"
    selected_device_args=(--udid "$prepared_device")
  fi
  device="$(python3 Scripts/CI/select_installed_simulator.py --output "$evidence/verified-environment.json" "${selected_device_args[@]+"${selected_device_args[@]}"}")"
fi
printf '%s\n' "$device_strategy" > "$evidence/device-strategy.txt"
python3 - "$device" "$evidence/verified-environment.json" "$device_strategy" <<'PY'
import json,subprocess,sys
selected=json.load(open(sys.argv[2]))
if sys.argv[3]=='ready' and selected['device']['state']!='Booted':
    raise SystemExit('BLOCKED_ENVIRONMENT: no already-booted SDK-matching iPad; no cold-boot retry was performed')
if selected['device']['state']!='Booted':subprocess.run(['xcrun','simctl','boot',sys.argv[1]],check=True,timeout=15)
from pathlib import Path
out=Path(sys.argv[2]).parent
try:
    with (out/'bootstatus.log').open('w') as log:
        subprocess.run(['xcrun','simctl','bootstatus',sys.argv[1],'-b'],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
except (subprocess.TimeoutExpired,subprocess.CalledProcessError):
    for name,command in [('devices-after',['xcrun','simctl','list','devices','-j']),('core-simulator-log',['log','show','--last','3m','--style','compact','--predicate','process == "CoreSimulatorService"'])]:
        try:
            result=subprocess.run(command,capture_output=True,timeout=15)
            (out/(name+'.stdout')).write_bytes(result.stdout);(out/(name+'.stderr')).write_bytes(result.stderr)
        except subprocess.TimeoutExpired:(out/(name+'.timeout')).write_text('15s observation deadline')
    raise
PY
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
finish_phase test
motion_scope="${HANLIN_MOTION_SCOPE:-affected}"
if [[ "$motion_scope" == cycles ]]; then
  selected_tests=(-only-testing:ChatMotionProofUITests/MotionUITests/testAAllFivePresetsTwentyCompleteCyclesEach)
elif [[ "$motion_scope" == input-diagnostic ]]; then
  selected_tests=(-only-testing:ChatMotionProofUITests/MotionUITests/testDRapidInputDiagnosticOnly)
else
  [[ "$motion_scope" == affected ]]
  selected_tests=(-only-testing:ChatMotionProofUITests/MotionUITests/testBRapidReversalPresetSwitchAndPersistence
    -only-testing:ChatMotionProofUITests/MotionUITests/testCReadableLongContentRTLTypeOrientationAndCompletion)
fi
printf '%s\n' "$motion_scope" > "$evidence/selected-scope.txt"
set +e
python3 "$root/docs/chat-motion/record_ui_run.py" --device "$device" --evidence "$evidence" -- \
  xcodebuild test-without-building -project ChatMotionProof.xcodeproj -scheme ChatMotionProof \
  -destination "platform=iOS Simulator,id=$device" -destination-timeout 60 \
  -derivedDataPath "$scratch/DerivedData" -resultBundlePath "$scratch/Motion.xcresult" \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 600 -maximum-test-execution-time-allowance 720 \
  CODE_SIGNING_ALLOWED=NO "${selected_tests[@]}" 2>&1 | tee "$evidence/test.log"
test_code=${PIPESTATUS[0]};set -e
finish_phase results
python3 "$root/docs/chat-motion/collect_motion_result.py" "$scratch/Motion.xcresult" "$device" "$evidence" "$test_code"
[[ "$test_code" == 0 ]] || exit "$test_code"
python3 - "$evidence" <<'PY'
import json,sys
from pathlib import Path
e=Path(sys.argv[1]);found=[]
assert json.loads((e/'raw-result-status.json').read_text())['status']=='FINALIZED_READABLE_ARCHIVED'
def visit(n):
    if isinstance(n,dict):
        if n.get('nodeType')=='Test Case':found.append(n)
        for v in n.values():visit(v)
    elif isinstance(n,list):
        for v in n:visit(v)
visit(json.loads((e/'tests.json').read_text()))
scope=(e/'selected-scope.txt').read_text().strip()
names=['testAAllFivePresetsTwentyCompleteCyclesEach'] if scope=='cycles' else ['testDRapidInputDiagnosticOnly'] if scope=='input-diagnostic' else ['testBRapidReversalPresetSwitchAndPersistence','testCReadableLongContentRTLTypeOrientationAndCompletion']
expected={'MotionUITests/'+name+'()' for name in names}
assert len(found)==len(expected) and {n['nodeIdentifier'] for n in found}==expected and all(n['result']=='Passed' for n in found)
if scope=='cycles':
    timeline=json.loads((e/'motion-geometry-timeline.json').read_text());assert {n['preset'] for n in timeline}=={'v1.relaxed','v1.height-reveal','v1.gentle-squeeze','v1.quiet-fade','v1.none'}
assert json.loads((e/'video-status.json').read_text())['exit_code']==0 and (e/'motion-first120s.mp4').stat().st_size>1024
(e/'result-validation.json').write_text(json.dumps({'status':'DIAGNOSTIC_CAPTURED' if scope=='input-diagnostic' else 'EXECUTED_PASS','methods':len(found),'selected_scope':scope,'cycles_per_preset':20 if scope=='cycles' else None,'scope':'input observations only; Motion acceptance A/B/C NOT_RUN' if scope=='input-diagnostic' else 'native components; original app/renderer/scroll/iPad26/physical NOT_RUN'}))
PY
finish_phase complete
