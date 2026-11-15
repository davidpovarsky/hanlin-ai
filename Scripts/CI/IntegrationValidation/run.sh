#!/bin/bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
evidence="$root/build/integration-validation-evidence"
mkdir -p "$evidence"
actual_sha="$(git rev-parse HEAD)"
[[ "${INTEGRATION_EXPECTED_SHA:-}" =~ ^[0-9a-f]{40}$ && "$actual_sha" == "$INTEGRATION_EXPECTED_SHA" ]] || {
  echo 'Exact integration checkout SHA mismatch' >&2; exit 2;
}
printf '%s\n' "$actual_sha" > "$evidence/source-commit.txt"
# Actions checks out one commit. Fetch only the frozen comparison object;
# the integration branch and every source byte remain at the dispatched SHA.
baseline=dd700c03e9fe9d22e95a031d4684275512ee6e6f
if ! git cat-file -e "$baseline^{commit}" 2>/dev/null; then
  git fetch --no-tags --depth=1 origin "$baseline"
fi
python3 Scripts/CI/IntegrationValidation/validate.py > "$evidence/graph.json"
python3 -m unittest discover -s Scripts/CI/IntegrationValidation -p 'test_*.py' -v 2>&1 | tee "$evidence/validator-tests.log"
python3 - <<'PY' > "$evidence/source-sha256.json"
import hashlib,json,subprocess
from pathlib import Path
paths=['AI_HLY.xcodeproj/project.pbxproj','AI_HLY.xcodeproj/xcshareddata/xcschemes/HanlinMiniApps.xcscheme',
       '.github/workflows/build-ios26-unsigned-ipa.yml']
for prefix in ['HanlinMiniAppsApp','Packages/HanlinProductSplit','Packages/HanlinPlatform','Scripts/CI/IntegrationValidation']:
    paths += subprocess.check_output(['git','ls-files',prefix],text=True).splitlines()
hashes={}
for path in sorted(set(paths)):
    data=Path(path).read_bytes()
    assert data==subprocess.check_output(['git','show',f'HEAD:{path}']),f'Non-committed bytes: {path}'
    hashes[path]=hashlib.sha256(data).hexdigest()
print(json.dumps(hashes,indent=2))
PY
selected_xcode="$(python3 - <<'PY'
import glob,re
paths=[p for p in glob.glob('/Applications/Xcode*.app') if re.search(r'/Xcode[_-]27(?:[._][0-9]+)*\.app$',p)]
paths.sort(key=lambda p:tuple(map(int,re.findall(r'[0-9]+',p))))
print(paths[-1] if paths else '')
PY
)"
[[ -n "$selected_xcode" ]] || { echo 'BLOCKED: no stable Xcode 27; SDK 26 cannot prove this target' >&2; exit 2; }
export DEVELOPER_DIR="$selected_xcode/Contents/Developer"
xcodebuild -version | tee "$evidence/xcode.txt"
xcrun swift --version | tee "$evidence/swift.txt"
xcrun --sdk iphonesimulator --show-sdk-version | tee "$evidence/sdk.txt"
python3 - "$evidence/sdk.txt" <<'PY'
import sys
assert int(open(sys.argv[1]).read().strip().split('.')[0]) >= 27, 'iOS Simulator SDK 27 required'
PY
sw_vers > "$evidence/os.txt"
xcrun simctl list devices available -j > "$evidence/simulators.json"
device="$(python3 - "$evidence/simulators.json" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]))
devices=[d for runtime,ds in data['devices'].items() if 'iOS-27' in runtime for d in ds if d['isAvailable'] and d['name'].startswith('iPhone')]
assert devices, 'Available iOS 27 phone simulator required'
print(devices[0]['udid'])
PY
)"
printf '%s\n' "$device" > "$evidence/simulator-udid.txt"
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/hanlin-integration.XXXXXXXX")"
retain_resolution() {
  local process_status="$1"
  python3 - "$scratch" "$evidence" "$process_status" <<'PY'
import hashlib,json,os,sys
from pathlib import Path
locks={}
for root in [Path(sys.argv[1])/'AI_HLY.xcodeproj',Path('Packages/HanlinProductSplit')]:
    for directory,folders,files in os.walk(root):
        folders[:]=[name for name in folders if name not in ['.build','.git']]
        if 'Package.resolved' not in files:continue
        path=Path(directory)/'Package.resolved'
        data=path.read_bytes()
        locks[str(path)]={'sha256':hashlib.sha256(data).hexdigest(),'resolved':json.loads(data)}
(Path(sys.argv[2])/'resolution.json').write_text(json.dumps(locks,indent=2))
(Path(sys.argv[2])/'process-status.json').write_text(json.dumps({'exit_code':int(sys.argv[3]),'scope':'extracted target and registered leaf tests'}))
PY
}
trap 'retain_resolution "$?"' EXIT
# Extract only the registered target to avoid resolving unrelated local Runtime
# binary inputs. No source bytes, target settings or canonical products change.
python3 Scripts/CI/IntegrationValidation/extract_target.py --output "$scratch/AI_HLY.xcodeproj" > "$evidence/extraction.json"
cp "$scratch/AI_HLY.xcodeproj/project.pbxproj" "$evidence/extracted-project.pbxproj"
cp "$scratch/Config.xcconfig" "$evidence/CI-Config.xcconfig"
plutil -lint "$scratch/AI_HLY.xcodeproj/project.pbxproj" | tee "$evidence/plutil.txt"
xcodebuild -project "$scratch/AI_HLY.xcodeproj" -scheme HanlinMiniApps \
  -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/AppDerivedData" \
  -resultBundlePath "$evidence/MiniAppsBuild.xcresult" CODE_SIGNING_ALLOWED=NO build \
  2>&1 | tee "$evidence/miniapps-build.log"
app="$scratch/AppDerivedData/Build/Products/Debug-iphonesimulator/HanlinMiniApps.app"
test -d "$app"
plutil -p "$app/Info.plist" > "$evidence/miniapps-info.txt"
# This launches the deliberately unavailable shell, not a live MiniApps provider.
state="$(xcrun simctl list devices -j | python3 -c 'import json,sys; data=json.load(sys.stdin); print(next(d["state"] for ds in data["devices"].values() for d in ds if d["udid"]==sys.argv[1]))' "$device")"
if [[ "$state" != Booted ]]; then xcrun simctl boot "$device"; fi
xcrun simctl bootstatus "$device" -b
xcrun simctl install "$device" "$app"
xcrun simctl launch "$device" com.itorah.hanlinminiapps.integration | tee "$evidence/miniapps-launch.txt"
(
  cd Packages/HanlinProductSplit
  xcodebuild -list -json > "$evidence/package-schemes.json"
)
scheme="$(python3 - "$evidence/package-schemes.json" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]))
schemes=data.get('workspace',{}).get('schemes',[])+data.get('project',{}).get('schemes',[])
print(next(s for s in ['HanlinProductSplit-Package','HanlinProductSplit'] if s in schemes))
PY
)"
(
  cd Packages/HanlinProductSplit
  xcodebuild test -scheme "$scheme" -destination "platform=iOS Simulator,id=$device" \
    -derivedDataPath "$scratch/PackageDerivedData" -resultBundlePath "$evidence/SplitTests.xcresult" \
    -only-testing:RegisteredIntegrationTests/RegisteredSplitIntegrationTests CODE_SIGNING_ALLOWED=NO
) 2>&1 | tee "$evidence/package-tests.log"
xcrun xcresulttool get test-results tests --path "$evidence/SplitTests.xcresult" --format json > "$evidence/tests.json"
python3 Scripts/CI/IntegrationValidation/verify_results.py "$evidence/tests.json" | tee "$evidence/verified-cases.json"
retain_resolution 0
python3 - "$evidence/resolution.json" <<'PY'
import json,sys
assert json.load(open(sys.argv[1])), 'Actual package resolution evidence required'
PY
