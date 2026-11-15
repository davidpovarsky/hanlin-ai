#!/bin/bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
evidence="$root/build/simulator-parity-ui-evidence"
mkdir -p "$evidence"
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/hanlin-parity-ui.XXXXXXXX")"
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
finish() {
  local status="$?"
  python3 - "$scratch" "$evidence" "$status" <<'PY'
import hashlib,json,sys
from pathlib import Path
scratch,evidence=map(Path,sys.argv[1:3]);locks=[]
for p in scratch.rglob('Package.resolved'):
    if any(part in ['checkouts','.build'] for part in p.relative_to(scratch).parts):continue
    b=p.read_bytes();dest=evidence/'raw-locks'/f'{len(locks):02d}-Package.resolved';dest.parent.mkdir(exist_ok=True);dest.write_bytes(b)
    locks.append({'raw_file':str(dest.relative_to(evidence)),'sha256':hashlib.sha256(b).hexdigest(),'resolved':json.loads(b)})
(evidence/'resolution.json').write_text(json.dumps(locks,indent=2))
(evidence/'process-status.json').write_text(json.dumps({'exit_code':int(sys.argv[3]),'scope':'compiled-swift-parity-miniapp-ui-only','full_app_acceptance':False}))
PY
  python3 Scripts/CI/SimulatorAcceptance/verify_parity.py "$evidence" > "$evidence/summary.json" || true
}
trap finish EXIT
xcodebuild build-for-testing -project "$scratch/project/Parity.xcodeproj" -scheme HanlinParityUI \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$scratch/DerivedData" -resultBundlePath "$evidence/Build.xcresult" \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "$evidence/build.log"
for family in iPhone iPad; do
  for locale in en he; do
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
    xcrun simctl boot "$device"
    xcrun simctl bootstatus "$device" -b > "$folder/boot.log" 2>&1
    set +e
    TEST_RUNNER_HANLIN_SIM_ACCEPTANCE_LOCALE="$locale" xcodebuild test-without-building \
      -project "$scratch/project/Parity.xcodeproj" -scheme HanlinParityUI -configuration Release \
      -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
      -resultBundlePath "$folder/Tests.xcresult" -parallel-testing-enabled NO \
      -only-testing:HanlinParityUITests/ParityUITests CODE_SIGNING_ALLOWED=NO \
      2>&1 | tee "$folder/test.log"
    test_status=${PIPESTATUS[0]}
    set -e
    printf '{"xcodebuild_exit_code":%s,"family":"%s","locale":"%s"}\n' "$test_status" "$family" "$locale" > "$folder/context.json"
    xcrun simctl spawn "$device" log show --last 3m --style compact --predicate 'process == "HanlinParityUI"' > "$folder/app.log" 2>&1 || true
    if [[ -d "$folder/Tests.xcresult" ]]; then
      xcrun xcresulttool get test-results tests --path "$folder/Tests.xcresult" --format json > "$folder/tests.json" || true
      xcrun xcresulttool export attachments --path "$folder/Tests.xcresult" --output-path "$folder/screenshots" > "$folder/attachments-export.log" 2>&1 || true
    fi
    xcrun simctl shutdown "$device"
  done
done
python3 Scripts/CI/SimulatorAcceptance/verify_parity.py "$evidence" | tee "$evidence/summary.json"
