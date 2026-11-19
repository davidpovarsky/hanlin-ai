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
destination_timeout=60
run_bounded_cmd(){
  local timeout_s="$1"; shift
  python3 - "$timeout_s" "$@" <<'PY'
import json, os, shlex, signal, subprocess, sys, time
from pathlib import Path

timeout = int(sys.argv[1])
cmd = sys.argv[2:]
receipt_path = os.environ.get("HANLIN_BOUNDED_RECEIPT")
started = time.monotonic()
proc = subprocess.Popen(cmd, start_new_session=True)
signals_sent = []
pgid_empty = False
timed_out = False

def wait_pg(pgid, wait_s):
    deadline = time.monotonic() + wait_s
    while True:
        proc_running = proc.poll() is None
        if proc_running:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return False
            try:
                proc.wait(timeout=min(0.25, remaining))
            except subprocess.TimeoutExpired:
                pass
        try:
            os.killpg(pgid, 0)
        except ProcessLookupError:
            return True
        except PermissionError:
            return False
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return False
        if not proc_running:
            time.sleep(min(0.2, remaining))

def write_receipt(rc):
    if not receipt_path:
        return
    payload = {
        "schema_version": 1,
        "command": cmd,
        "timeout_seconds": timeout,
        "elapsed_seconds": round(time.monotonic() - started, 3),
        "timed_out": timed_out,
        "return_code": rc,
        "signals_sent": signals_sent,
        "pgid_emptied": pgid_empty,
    }
    Path(receipt_path).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

try:
    rc = proc.wait(timeout=timeout)
    final_rc = 128 + (-rc) if rc < 0 else rc
    write_receipt(final_rc)
    raise SystemExit(final_rc)
except subprocess.TimeoutExpired:
    timed_out = True
    print(f"[bounded-runner] Timed out after {timeout}s: {shlex.join(cmd)}", file=sys.stderr, flush=True)
    for sig, sig_name, wait_s in (
        (signal.SIGINT, "SIGINT", 20),
        (signal.SIGTERM, "SIGTERM", 5),
        (signal.SIGKILL, "SIGKILL", 5),
    ):
        proc.poll()
        try:
            os.killpg(proc.pid, sig)
            signals_sent.append(sig_name)
        except ProcessLookupError:
            pgid_empty = True
            break
        if wait_pg(proc.pid, wait_s):
            pgid_empty = True
            break
    proc.poll()
    write_receipt(124)
    raise SystemExit(124)
PY
}
if [[ "$device_strategy" == xcodebuild-owned ]]; then
  destination_timeout="${HANLIN_MOTION_DESTINATION_TIMEOUT:-180}"
  build_timeout="${HANLIN_MOTION_BUILD_TIMEOUT:-300}"
  test_outer_timeout="${HANLIN_MOTION_TEST_TIMEOUT:-960}"
  python3 - "$destination_timeout" "$build_timeout" "$test_outer_timeout" <<'PY'
import sys
dest, bld, tst = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
if not (1 <= dest <= 300):
    raise SystemExit(f"Invalid bounded destination timeout: {dest}")
if not (1 <= bld <= 600):
    raise SystemExit(f"Invalid bounded build timeout: {bld}")
if not (1 <= tst <= 1200):
    raise SystemExit(f"Invalid bounded test timeout: {tst}")
PY
fi
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
    if [[ "$device_strategy" == xcodebuild-owned ]]; then
      HANLIN_BOUNDED_RECEIPT="$evidence/build-bounded-status.json" \
      run_bounded_cmd "$build_timeout" \
        xcodebuild build-for-testing -project ChatMotionProof.xcodeproj -scheme ChatMotionProof \
        -destination "generic/platform=iOS Simulator" \
        -derivedDataPath "$scratch/DerivedData" \
        ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO
    else
      xcodebuild build-for-testing -project ChatMotionProof.xcodeproj -scheme ChatMotionProof \
        -destination "generic/platform=iOS Simulator" \
        -derivedDataPath "$scratch/DerivedData" \
        ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO
    fi
    printf '[%s] Finished generic build-for-testing\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } 2>&1 | tee "$evidence/build.log"
  if [[ "$device_strategy" == xcodebuild-owned ]]; then
    finish_phase simulator-create
  else
    finish_phase simulator-boot
  fi
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
  if [[ "$device_strategy" == xcodebuild-owned ]]; then
    python3 - "$support_root" "$support_dir" "$evidence" "$device" "$required_sdk" "$owned_name" "${HANLIN_MOTION_DEVICE_TYPE:-}" "$destination_timeout" "$build_timeout" "$test_outer_timeout" <<'PY'
import datetime, hashlib, json, os, subprocess, sys
from pathlib import Path

support_root = Path(sys.argv[1])
support_dir = Path(sys.argv[2])
evidence_dir = Path(sys.argv[3])
simulator = sys.argv[4]
required_sdk = sys.argv[5]
owned_name = sys.argv[6]
expected_device_type = sys.argv[7]
destination_timeout = int(sys.argv[8])
build_timeout = int(sys.argv[9])
test_outer_timeout = int(sys.argv[10])
if destination_timeout < 1 or destination_timeout > 300:
    raise SystemExit(f"Invalid bounded destination timeout: {destination_timeout}")
if build_timeout < 1 or build_timeout > 600:
    raise SystemExit(f"Invalid bounded build timeout: {build_timeout}")
if test_outer_timeout < 1 or test_outer_timeout > 1200:
    raise SystemExit(f"Invalid bounded test timeout: {test_outer_timeout}")

sys.path.insert(0, str(support_root))
from Scripts.CI.owned_simulator_receipts import _created_selection, _job, _uuid

device_uuid = _uuid(simulator)
run_id = os.environ.get("GITHUB_RUN_ID")
run_attempt = os.environ.get("GITHUB_RUN_ATTEMPT")
if os.environ.get("GITHUB_ACTIONS") == "true":
    expected_job_name = _job(run_id, run_attempt)
    if owned_name != expected_job_name:
        raise SystemExit(f"Owned simulator name mismatch: got {owned_name}, expected {expected_job_name}")

selection_path = support_dir / "verified-simulator-environment.json"
evidence_selection = evidence_dir / "verified-environment.json"
selection, selection_sha = _created_selection(selection_path, device_uuid, run_id, run_attempt, owned_name)
if hashlib.sha256(evidence_selection.read_bytes()).hexdigest() != selection_sha:
    raise SystemExit("Evidence verified-environment.json does not match support selection receipt")
if (support_dir / "prepared-device-udid.txt").read_text(encoding="utf-8").strip() != device_uuid:
    raise SystemExit("prepared-device-udid.txt does not match verified owned UUID")
if (evidence_dir / "selected-device.txt").read_text(encoding="utf-8").strip() != device_uuid:
    raise SystemExit("selected-device.txt does not match verified owned UUID")

runtime = selection.get("runtime", {})
device_info = selection.get("device", {})
if selection.get("sdk") != required_sdk or runtime.get("version") != required_sdk or runtime.get("isAvailable") is not True:
    raise SystemExit(
        f"Runtime/SDK mismatch: sdk={selection.get('sdk')} runtime={runtime.get('version')} "
        f"available={runtime.get('isAvailable')} required={required_sdk}"
    )
if expected_device_type and device_info.get("deviceTypeIdentifier") != expected_device_type:
    raise SystemExit(
        f"Device type mismatch: got {device_info.get('deviceTypeIdentifier')}, expected {expected_device_type}"
    )

def read_cmd(cmd):
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=10, check=True)
    return res.stdout.strip()

xcode_lines = read_cmd(["xcodebuild", "-version"]).splitlines()
xcode_version = xcode_lines[0].removeprefix("Xcode ").strip() if xcode_lines else ""
xcode_build = xcode_lines[1].removeprefix("Build version ").strip() if len(xcode_lines) > 1 else ""
xcode_select_path = read_cmd(["xcode-select", "-p"])
macos_version = read_cmd(["sw_vers", "-productVersion"])
macos_build = read_cmd(["sw_vers", "-buildVersion"])
arch = read_cmd(["uname", "-m"])
created_at = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

(support_dir / "verified-selection.sha256").write_text(selection_sha + "\n", encoding="utf-8")

receipt = {
    "schema_version": 1,
    "status": "CREATED_AWAITING_XCODEBUILD_TEST",
    "ready_claimed": False,
    "verified_by_xctest_evidence": False,
    "boot_owner": "xcodebuild test-without-building",
    "preboot_simctl_invoked": False,
    "device_strategy": "xcodebuild-owned",
    "simulator": device_uuid,
    "owned_name": owned_name,
    "run_id": run_id,
    "run_attempt": run_attempt,
    "selection_sha256": selection_sha,
    "device_type": device_info.get("deviceTypeIdentifier"),
    "runtime_identifier": runtime.get("identifier"),
    "runtime_version": runtime.get("version"),
    "sdk": selection.get("sdk"),
    "required_sdk": required_sdk,
    "destination_timeout_seconds": destination_timeout,
    "build_timeout_seconds": build_timeout,
    "test_outer_timeout_seconds": test_outer_timeout,
    "xcode_version": xcode_version,
    "xcode_build": xcode_build,
    "xcode_select_path": xcode_select_path,
    "macos_version": macos_version,
    "macos_build": macos_build,
    "arch": arch,
    "created_at_utc": created_at,
    "scope": "Fresh owned simulator created only; competing simctl boot/bootstatus skipped; XCTest NOT_RUN",
}
payload = json.dumps(receipt, indent=2) + "\n"
(support_dir / "xcodebuild-owned-simulator.json").write_text(payload, encoding="utf-8")
(evidence_dir / "xcodebuild-owned-simulator.json").write_text(payload, encoding="utf-8")

log_text = (
    f"[{created_at}] Owned simulator created: {device_uuid} name={owned_name} "
    f"deviceType={device_info.get('deviceTypeIdentifier')} "
    f"runtime={runtime.get('identifier')} ({runtime.get('version')}) "
    f"selection_sha256={selection_sha}\n"
    f"[{created_at}] Host: macOS {macos_version} ({macos_build}) {arch}; "
    f"Xcode {xcode_version} ({xcode_build}) at {xcode_select_path}\n"
    f"[{created_at}] Skipping competing simctl boot and simctl bootstatus; "
    f"delegating simulator boot to xcodebuild test-without-building "
    f"(destination_timeout={destination_timeout}s; build_timeout={build_timeout}s; test_outer_timeout={test_outer_timeout}s; ready_claimed=false)\n"
)
(support_dir / "08-boot-delegation.log").write_text(log_text, encoding="utf-8")
(evidence_dir / "boot-delegation.log").write_text(log_text, encoding="utf-8")
print(log_text, end="", flush=True)
PY
  else
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
  fi
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
if [[ "$device_strategy" == xcodebuild-owned ]]; then
  HANLIN_BOUNDED_RECEIPT="$evidence/test-bounded-status.json" \
  run_bounded_cmd "$test_outer_timeout" \
    python3 "$support_root/docs/chat-motion/record_ui_run.py" --device "$device" --evidence "$evidence" -- \
    xcodebuild test-without-building -project ChatMotionProof.xcodeproj -scheme ChatMotionProof \
    -destination "platform=iOS Simulator,id=$device" -destination-timeout "$destination_timeout" \
    -derivedDataPath "$scratch/DerivedData" -resultBundlePath "$scratch/Motion.xcresult" \
    -parallel-testing-enabled NO -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 600 -maximum-test-execution-time-allowance 720 \
    CODE_SIGNING_ALLOWED=NO "${selected_tests[@]}" 2>&1 | tee "$evidence/test.log"
  test_code=${PIPESTATUS[0]}
else
  python3 "$support_root/docs/chat-motion/record_ui_run.py" --device "$device" --evidence "$evidence" -- \
    xcodebuild test-without-building -project ChatMotionProof.xcodeproj -scheme ChatMotionProof \
    -destination "platform=iOS Simulator,id=$device" -destination-timeout "$destination_timeout" \
    -derivedDataPath "$scratch/DerivedData" -resultBundlePath "$scratch/Motion.xcresult" \
    -parallel-testing-enabled NO -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 600 -maximum-test-execution-time-allowance 720 \
    CODE_SIGNING_ALLOWED=NO "${selected_tests[@]}" 2>&1 | tee "$evidence/test.log"
  test_code=${PIPESTATUS[0]}
fi
set -e
finish_phase results
python3 "$support_root/docs/chat-motion/collect_motion_result.py" "$scratch/Motion.xcresult" "$device" "$evidence" "$test_code"
if [[ "$device_strategy" == xcodebuild-owned ]]; then
  python3 - "$support_dir" "$evidence" "$test_code" <<'PY'
import datetime, json, sys
from pathlib import Path

support_dir = Path(sys.argv[1])
evidence_dir = Path(sys.argv[2])
test_code = int(sys.argv[3])

def load_optional(path):
    if path.is_file():
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
    return None

bounded = load_optional(evidence_dir / "test-bounded-status.json") or {}
raw_result = load_optional(evidence_dir / "raw-result-status.json") or {}
video_status = load_optional(evidence_dir / "video-status.json") or {}
timed_out = bool(bounded.get("timed_out")) if "timed_out" in bounded else (test_code == 124)

if timed_out:
    status = "XCODEBUILD_TIMED_OUT"
    scope = "Fresh owned simulator created; xcodebuild test-without-building timed out"
elif test_code == 0:
    status = "XCODEBUILD_PASSED"
    scope = "Fresh owned simulator created; xcodebuild test-without-building exited 0"
else:
    status = "XCODEBUILD_FAILED"
    scope = f"Fresh owned simulator created; xcodebuild test-without-building exited {test_code}"

completed_at = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
receipt_paths = [support_dir / "xcodebuild-owned-simulator.json", evidence_dir / "xcodebuild-owned-simulator.json"]
receipt = json.loads(receipt_paths[0].read_text(encoding="utf-8"))
receipt.update({
    "status": status,
    "test_exit_code": test_code,
    "timed_out": timed_out,
    "test_elapsed_seconds": bounded.get("elapsed_seconds"),
    "signals_sent": bounded.get("signals_sent", []),
    "pgid_emptied": bounded.get("pgid_emptied"),
    "raw_result_status": raw_result.get("status"),
    "result_readability": raw_result.get("readability"),
    "video_status": video_status.get("status"),
    "video_stop_reason": video_status.get("stop_reason"),
    "verified_by_xctest_evidence": (
        test_code == 0
        and not timed_out
        and raw_result.get("status") == "FINALIZED_READABLE_ARCHIVED"
    ),
    "completed_at_utc": completed_at,
    "scope": scope,
})
payload = json.dumps(receipt, indent=2) + "\n"
for path in receipt_paths:
    path.write_text(payload, encoding="utf-8")

completion_line = (
    f"[{completed_at}] Post-run xcodebuild-owned status={status} test_exit_code={test_code} "
    f"timed_out={timed_out} elapsed_seconds={bounded.get('elapsed_seconds')} "
    f"raw_result_status={raw_result.get('status')} video_stop_reason={video_status.get('stop_reason')}\n"
)
for log_path in (support_dir / "08-boot-delegation.log", evidence_dir / "boot-delegation.log"):
    if log_path.is_file():
        with log_path.open("a", encoding="utf-8") as fh:
            fh.write(completion_line)
PY
fi
if [[ "$test_code" != 0 && "$device_strategy" == xcodebuild-owned ]]; then
  python3 - "$support_root" "$support_dir" <<'PY' || true
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1])))
from Scripts.CI.boot_motion_simulator import retain_failure_observations
retain_failure_observations(Path(sys.argv[2]))
PY
fi
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
