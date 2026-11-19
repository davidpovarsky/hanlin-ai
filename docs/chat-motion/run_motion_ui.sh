#!/bin/bash
set -euo pipefail
support_root="${HANLIN_MOTION_SUPPORT_ROOT:-$(git rev-parse --show-toplevel)}"
root="${HANLIN_MOTION_PRODUCT_ROOT:-$(git rev-parse --show-toplevel)}";cd "$root"
evidence="$root/build/chat-motion-ui-evidence";mkdir -p "$evidence"
support_dir="$evidence/support-readiness"
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
git -C "$root" rev-parse HEAD > "$evidence/source-sha.txt"
printf '%s\n' "${HANLIN_MOTION_SCOPE:-affected}" > "$evidence/requested-scope.txt"
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  selected_xcode="$(python3 "$root/Scripts/CI/select_stable_xcode.py")"
  export DEVELOPER_DIR="$selected_xcode/Contents/Developer"
fi
if ! command -v xcodegen >/dev/null; then brew install xcodegen > "$evidence/xcodegen-install.log" 2>&1; fi
{ xcode-select -p;xcodebuild -version;xcrun swift --version;xcodebuild -showsdks;sw_vers;uname -m;xcodegen --version; } > "$evidence/preflight.txt"
device_strategy="${HANLIN_MOTION_DEVICE_STRATEGY:-ready}"
if [[ "${HANLIN_MOTION_BUILD_BEFORE_BOOT:-0}" == 1 ]]; then
  scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/hanlin-motion-ui.XXXXXXXX")"
  python3 "$root/docs/chat-motion/prepare_motion_ui.py" --output "$scratch/proof" > "$evidence/preparation.json"
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
  {
    printf '[%s] Starting generic build-for-testing (DEVELOPER_DIR=%s)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$DEVELOPER_DIR"
    xcodebuild build-for-testing -project ChatMotionProof.xcodeproj -scheme ChatMotionProof \
      -destination "generic/platform=iOS Simulator" \
      -derivedDataPath "$scratch/DerivedData" \
      ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO
    printf '[%s] Finished generic build-for-testing\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } 2>&1 | tee "$evidence/build.log"
  finish_phase simulator-boot
  required_sdk="${HANLIN_MOTION_REQUIRED_SDK:-27.2}"
  sim_sdk="$(xcrun --sdk iphonesimulator --show-sdk-version)"
  if [[ "$sim_sdk" != "$required_sdk" ]]; then
    echo "ERROR: Simulator SDK mismatch: got $sim_sdk, expected $required_sdk" >&2
    exit 1
  fi
  xcrun simctl list devices available -j > "$evidence/devices.json"
  xcrun simctl list runtimes -j > "$evidence/runtimes.json"
  mkdir -p "$support_dir"
  owned_name="Hanlin-Phase2-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
  device_type_args=()
  if [[ -n "${HANLIN_MOTION_DEVICE_TYPE:-}" ]]; then
    device_type_args=(--device-type "$HANLIN_MOTION_DEVICE_TYPE")
  fi
  device="$(python3 "$support_root/Scripts/CI/select_installed_simulator.py" \
    --output "$support_dir/verified-simulator-environment.json" \
    "${device_type_args[@]+"${device_type_args[@]}"}" \
    --create-owned "$owned_name")"
  cp "$support_dir/verified-simulator-environment.json" "$evidence/verified-environment.json"
  printf '%s\n' "$device" > "$support_dir/prepared-device-udid.txt"
  printf '%s\n' "$device" > "$evidence/selected-device.txt"
  printf '%s\n' "$device_strategy" > "$evidence/device-strategy.txt"
  python3 - "$support_root" "$support_dir" "$evidence" "$device" "$required_sdk" <<'PY'
import datetime, json, sys, time
from pathlib import Path

support_root = Path(sys.argv[1])
support_dir = Path(sys.argv[2])
evidence_dir = Path(sys.argv[3])
simulator = sys.argv[4]
required_sdk = sys.argv[5]

sys.path.insert(0, str(support_root))
from Scripts.CI.stage_simulator_fixtures import BOOT_TIMEOUT_SECONDS, run_bounded
from Scripts.CI.owned_simulator_receipts import record_owned_boot
from Scripts.CI.boot_motion_simulator import retain_failure_observations

selection = json.loads((support_dir / "verified-simulator-environment.json").read_text(encoding="utf-8"))
runtime = selection.get("runtime", {})
if selection.get("sdk") != required_sdk or runtime.get("version") != required_sdk:
    raise SystemExit(
        f"Runtime/SDK mismatch: sdk={selection.get('sdk')} runtime={runtime.get('version')} required={required_sdk}"
    )

def ts():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

log_lines = [
    f"[{ts()}] Owned simulator: {simulator} name={selection['device'].get('name')} "
    f"deviceType={selection['device'].get('deviceTypeIdentifier')} "
    f"runtime={runtime.get('identifier')} ({runtime.get('version')})",
    f"[{ts()}] Starting simctl boot (timeout=15.0s)",
]
t0 = time.monotonic()
boot_res = run_bounded(["xcrun", "simctl", "boot", simulator], timeout_seconds=15.0)
log_lines.append(f"[{ts()}] simctl boot exit={boot_res.returncode} elapsed={round(time.monotonic() - t0, 3)}s")
if boot_res.stdout or boot_res.stderr:
    log_lines.append((boot_res.stdout + boot_res.stderr).rstrip())

log_lines.append(f"[{ts()}] Starting simctl bootstatus -b (timeout={BOOT_TIMEOUT_SECONDS}s)")
t1 = time.monotonic()
result = run_bounded(["xcrun", "simctl", "bootstatus", simulator, "-b"], timeout_seconds=BOOT_TIMEOUT_SECONDS)
log_lines.append(f"[{ts()}] simctl bootstatus exit={result.returncode} elapsed={round(time.monotonic() - t1, 3)}s")
output = result.stdout + result.stderr
if output:
    log_lines.append(output.rstrip())

log_text = "\n".join(log_lines) + "\n"
(support_dir / "08-bootstatus.log").write_text(log_text, encoding="utf-8")
(evidence_dir / "bootstatus.log").write_text(log_text, encoding="utf-8")
print(log_text, end="", flush=True)

if result.returncode != 0:
    retain_failure_observations(support_dir)
    raise SystemExit(f"Simulator boot failed or timed out: {result.returncode}")

record_owned_boot(support_dir, simulator, result)
PY
else
  xcrun simctl list devices available -j > "$evidence/devices.json"
  xcrun simctl list runtimes -j > "$evidence/runtimes.json"
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
  python3 "$root/Scripts/CI/boot_motion_simulator.py" \
    --device "$device" --selection "$evidence/verified-environment.json" --strategy "$device_strategy"
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
fi
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
