#!/bin/bash
set -euo pipefail
run_bounded() {
  python3 - "$@" <<'PY'
import os,signal,subprocess,sys
p=subprocess.Popen(sys.argv[2:],start_new_session=True)
try:status=p.wait(timeout=int(sys.argv[1]))
except subprocess.TimeoutExpired:
    os.killpg(p.pid,signal.SIGINT)
    try:p.wait(timeout=30)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid,signal.SIGKILL);p.wait()
    print('Owned CI command exceeded its retention budget',file=sys.stderr)
    status=124
sys.exit(status)
PY
}
root="$(git rev-parse --show-toplevel)"
workflow_root="$root"
cd "$root"
evidence="$root/build/simulator-parity-ui-evidence"
mkdir -p "$evidence"
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/hanlin-parity-ui.XXXXXXXX")"
git rev-parse HEAD > "$evidence/workflow-commit.txt"
if [[ -n "${HANLIN_PARITY_FROZEN_SOURCE:-}" ]]; then
  test "$HANLIN_PARITY_FROZEN_SOURCE" = 2427aac90154834eb5f31c746d47f6dcd3129e8e
  test "${HANLIN_PARITY_VARIANT:-}" = iPad-he
  if ! git cat-file -e "$HANLIN_PARITY_FROZEN_SOURCE^{commit}" 2>/dev/null; then
    git fetch --no-tags --depth=1 origin "$HANLIN_PARITY_FROZEN_SOURCE"
  fi
  git worktree add --detach "$scratch/source" "$HANLIN_PARITY_FROZEN_SOURCE"
  root="$scratch/source"
  cd "$root"
  test "$(git rev-parse HEAD)" = "$HANLIN_PARITY_FROZEN_SOURCE"
fi
python3 - "$workflow_root" <<'PY' > "$evidence/workflow-sha256.json"
import hashlib,json,subprocess,sys
from pathlib import Path
root=Path(sys.argv[1]);paths=['.github/workflows/build-ios26-unsigned-ipa.yml','Scripts/CI/SimulatorAcceptance/run_parity.sh','Scripts/CI/SimulatorAcceptance/verify_parity.py','Scripts/CI/SimulatorAcceptance/gate.py','Scripts/CI/SimulatorAcceptance/record_parity_output.py']
records={}
for p in paths:
    raw=(root/p).read_bytes();assert raw==subprocess.check_output(['git','-C',str(root),'show','HEAD:'+p]),p
    records[p]=hashlib.sha256(raw).hexdigest()
print(json.dumps(records,indent=2))
PY
selected_xcode="$(python3 -c 'import glob,re; p=[p for p in glob.glob("/Applications/Xcode*.app") if re.search(r"/Xcode[_-]27(?:[._][0-9]+)*\.app$",p)]; p.sort(key=lambda x:tuple(map(int,re.findall(r"[0-9]+",x)))); print(p[-1] if p else "")')"
test -n "$selected_xcode"
export DEVELOPER_DIR="$selected_xcode/Contents/Developer"
xcodebuild -version > "$evidence/xcode.txt"
xcrun swift --version > "$evidence/swift.txt"
xcrun --sdk iphonesimulator --show-sdk-version > "$evidence/sdk.txt"
sw_vers > "$evidence/host.txt"
git rev-parse HEAD > "$evidence/source-commit.txt"
xcrun simctl list -j > "$evidence/simulators-before.json"
python3 Scripts/CI/SimulatorAcceptance/prepare_parity_project.py --repo "$root" --output "$scratch/project" > "$evidence/preparation.json"
cp "$scratch/project/source-inputs.json" "$evidence/wrapper-inputs.json"
cp "$scratch/project/Parity.xcodeproj/project.pbxproj" "$evidence/project.pbxproj"
python3 - <<'PY' > "$evidence/source-sha256.json"
import hashlib,json,subprocess
from pathlib import Path
paths=subprocess.check_output(['git','ls-files','Packages/HanlinParityMiniApp','Packages/HanlinPlatform','Scripts/CI/SimulatorAcceptance'],text=True).splitlines()
records={}
for path in paths:
    raw=Path(path).read_bytes()
    assert raw==subprocess.check_output(['git','show',f'HEAD:{path}']),path
    records[path]=hashlib.sha256(raw).hexdigest()
print(json.dumps(records,indent=2))
PY
retain_locks() {
  python3 - "$scratch" "$evidence" <<'PY'
import hashlib,json,sys
from pathlib import Path
scratch,evidence=map(Path,sys.argv[1:]);locks=[]
for p in scratch.rglob('Package.resolved'):
    if p.is_relative_to(scratch/'source'):continue
    if any(part in ['checkouts','.build'] for part in p.relative_to(scratch).parts):continue
    b=p.read_bytes();dest=evidence/'raw-locks'/f'{len(locks):02d}-Package.resolved';dest.parent.mkdir(exist_ok=True);dest.write_bytes(b)
    locks.append({'raw_file':str(dest.relative_to(evidence)),'sha256':hashlib.sha256(b).hexdigest(),'resolved':json.loads(b)})
(evidence/'resolution.json').write_text(json.dumps(locks,indent=2))
PY
}
finish() {
  local status="$?"
  retain_locks
  printf '{"exit_code":%s,"scope":"compiled-swift-parity-miniapp-ui-only","full_app_acceptance":false}\n' "$status" > "$evidence/process-status.json"
  python3 "$workflow_root/Scripts/CI/SimulatorAcceptance/verify_parity.py" "$evidence" > "$evidence/summary.json" || true
}
trap finish EXIT
trap 'exit 143' TERM
run_bounded 900 xcodebuild build-for-testing -project "$scratch/project/Parity.xcodeproj" -scheme HanlinParityUI \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$scratch/DerivedData" -resultBundlePath "$evidence/Build.xcresult" \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "$evidence/build.log"
retain_locks
for family in iPhone iPad; do
  for locale in en he; do
    if [[ -n "${HANLIN_PARITY_VARIANT:-}" && "$family-$locale" != "$HANLIN_PARITY_VARIANT" ]]; then continue; fi
    folder="$evidence/$family-$locale"
    mkdir -p "$folder"
    device="$(python3 - "$evidence/simulators-before.json" "$family" <<'PY'
import json,subprocess,sys
d=json.load(open(sys.argv[1]));runtime=next(r['identifier'] for r in d['runtimes'] if r.get('isAvailable') and r['version'].split('.')[0]=='27' and 'iOS' in r['identifier'])
types=[t for t in d['devicetypes'] if t['name'].startswith(sys.argv[2])]
available=[item for item in d['devices'].get(runtime,[]) if item.get('isAvailable') and item['name'].startswith(sys.argv[2])]
kind=next((item.get('deviceTypeIdentifier') or next(t['identifier'] for t in types if t['name']==item['name']) for item in available),types[-1]['identifier'])
print(subprocess.check_output(['xcrun','simctl','create','Hanlin-Parity-UI-'+sys.argv[2]+'-'+__import__('uuid').uuid4().hex[:8],kind,runtime],text=True).strip())
PY
)"
    printf '%s\n' "$device" > "$folder/created-simulator-udid.txt"
    printf '{"xcodebuild_exit_code":null,"family":"%s","locale":"%s","phase":"created_disposable_simulator"}\n' "$family" "$locale" > "$folder/context.json"
    xcrun simctl boot "$device"
    run_bounded 600 xcrun simctl bootstatus "$device" -b > "$folder/boot.log" 2>&1
    printf '{"xcodebuild_exit_code":null,"family":"%s","locale":"%s","phase":"test_command_running"}\n' "$family" "$locale" > "$folder/context.json"
    set +e
    TEST_RUNNER_HANLIN_SIM_ACCEPTANCE_LOCALE="$locale" run_bounded 900 xcodebuild test-without-building \
      -project "$scratch/project/Parity.xcodeproj" -scheme HanlinParityUI -configuration Release \
      -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
      -resultBundlePath "$folder/Tests.xcresult" -parallel-testing-enabled NO \
      -only-testing:HanlinParityUITests/ParityUITests CODE_SIGNING_ALLOWED=NO \
      2>&1 | python3 "$workflow_root/Scripts/CI/SimulatorAcceptance/record_parity_output.py" "$folder"
    test_status=${PIPESTATUS[0]}
    set -e
    printf '{"xcodebuild_exit_code":%s,"family":"%s","locale":"%s","phase":"test_command_completed"}\n' "$test_status" "$family" "$locale" > "$folder/context.json"
    xcrun simctl spawn "$device" log show --last 3m --style compact --predicate 'process == "HanlinParityUI"' > "$folder/app.log" 2>&1 || true
    if [[ -d "$folder/Tests.xcresult" ]]; then
      xcrun xcresulttool get test-results tests --path "$folder/Tests.xcresult" --format json > "$folder/tests.json" || true
      xcrun xcresulttool export attachments --path "$folder/Tests.xcresult" --output-path "$folder/screenshots" > "$folder/attachments-export.log" 2>&1 || true
    fi
    python3 "$workflow_root/Scripts/CI/SimulatorAcceptance/verify_parity.py" "$evidence" > "$evidence/summary.json" || true
    xcrun simctl shutdown "$device"
  done
done
python3 "$workflow_root/Scripts/CI/SimulatorAcceptance/verify_parity.py" "$evidence" | tee "$evidence/summary.json"
