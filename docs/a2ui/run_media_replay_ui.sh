#!/bin/bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
evidence="$root/build/a2ui-media-replay-ui-evidence"
mkdir -p "$evidence"
git rev-parse HEAD > "$evidence/source-sha.txt"
phase=preflight
phase_started=$SECONDS
scratch=''
finish_phase() {
  printf '%s\n' "$((SECONDS-phase_started))" > "$evidence/$phase-duration-seconds.txt"
  phase="$1"
  phase_started=$SECONDS
}
retain() {
  code="$?"
  finish_phase diagnostics
  python3 - "$evidence" "$code" <<'PY'
import json, subprocess, sys
from pathlib import Path
e=Path(sys.argv[1]); code=int(sys.argv[2]); cases=[]
def visit(n):
    if isinstance(n,dict):
        if n.get('nodeType')=='Test Case': cases.append(n)
        for v in n.values(): visit(v)
    elif isinstance(n,list):
        for v in n: visit(v)
if (e/'tests.json').exists(): visit(json.loads((e/'tests.json').read_text()))
log=(e/'xcodebuild.log').read_text(errors='replace') if (e/'xcodebuild.log').exists() else ''
status='EXECUTED_PASS' if code==0 else 'TEST_FAILED' if cases else 'BUILD_FAILED' if 'error:' in log else 'INFRA_ERROR'
(e/'process-status.json').write_text(json.dumps({'status':status,'exit_code':code,'executed_cases':len(cases),
    'xcresult_exists':(e/'MediaReplay.xcresult').exists(),
    'scope':'actual SwiftUI component UI; full app/provider/playback/physical NOT_RUN'},indent=2))
if (e/'selected-device.txt').exists():
    device=(e/'selected-device.txt').read_text().strip()
    try:
        subprocess.run(['xcrun','simctl','io',device,'screenshot',str(e/'final.png')],check=False,timeout=5,capture_output=True)
    except (OSError,subprocess.TimeoutExpired): pass
PY
  finish_phase complete
  python3 Scripts/CI/generate_performance_report.py --log-dir "$evidence" \
    --run-id "${GITHUB_RUN_ID:-}" --commit-sha "$(git rev-parse HEAD)" --event-name workflow_dispatch \
    --output-json "$evidence/ci-performance-report.json" --step-summary "${GITHUB_STEP_SUMMARY:-$evidence/step-summary.md}"
  return "$code"
}
trap retain EXIT
df -h . > "$evidence/disk.txt"
selected_xcode="$(python3 - <<'PY'
import glob,re,shutil
assert shutil.disk_usage('.').free >= 10*1024**3
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
  sw_vers
  uname -m
} > "$evidence/preflight.txt"
if ! command -v xcodegen >/dev/null; then brew install xcodegen > "$evidence/xcodegen-install.log" 2>&1; fi
xcodegen --version > "$evidence/xcodegen-version.txt"
xcrun simctl list runtimes -j > "$evidence/runtimes.json"
xcrun simctl list devices available -j > "$evidence/devices.json"
python3 - "$evidence/devices.json" <<'PY' > "$evidence/selected-device.txt"
import json,sys
d=json.load(open(sys.argv[1]))['devices']
eligible=[x for runtime,rows in d.items() if '.iOS-27-' in runtime for x in rows if x.get('isAvailable') and x['name'].startswith('iPhone')]
assert eligible,'No iPhone/iOS27 simulator'
print(eligible[0]['udid'])
PY
device="$(cat "$evidence/selected-device.txt")"
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/a2ui-media-ui.XXXXXXXX")"
python3 docs/a2ui/prepare_media_replay_ui.py --output "$scratch/host" > "$evidence/preparation.json"
cp "$scratch/host/proof-inputs.json" "$scratch/host/project.json" "$evidence/"
xcodegen generate --spec "$scratch/host/project.json" --project "$scratch/host" > "$evidence/xcodegen.log"
project="$scratch/host/MediaReplay.xcodeproj"
finish_phase resolution
xcodebuild -resolvePackageDependencies -project "$project" -scheme MediaReplay > "$evidence/resolve.log" 2>&1
lock="$project/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
cp "$lock" "$evidence/resolved-before.json"
python3 - "$lock" <<'PY' > "$evidence/pin-validation.json"
import json,sys
sys.path.insert(0,'docs/a2ui')
from prepare_exact_pin_proof import verify_pin
verify_pin(json.load(open(sys.argv[1])))
print('{"status":"EXACT_PIN_VERIFIED"}')
PY
xcodebuild -list -json -project "$project" > "$evidence/schemes.json"
finish_phase build-and-test
set +e
xcodebuild test -project "$project" -scheme MediaReplay -configuration Debug \
  -destination "platform=iOS Simulator,id=$device" -parallel-testing-enabled NO \
  -derivedDataPath "$scratch/DerivedData" -resultBundlePath "$evidence/MediaReplay.xcresult" \
  -only-testing:MediaReplayUITests/MediaReplayUITests -disableAutomaticPackageResolution \
  -skipPackagePluginValidation -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$evidence/xcodebuild.log"
test_code=${PIPESTATUS[0]}
set -e
finish_phase result-verification
cp "$lock" "$evidence/Package.resolved"
if [[ -d "$evidence/MediaReplay.xcresult" ]]; then
  xcrun xcresulttool get test-results tests --path "$evidence/MediaReplay.xcresult" --format json > "$evidence/tests.json" || true
  xcrun xcresulttool export attachments --path "$evidence/MediaReplay.xcresult" --output-path "$evidence/attachments" > "$evidence/attachment-export.log" 2>&1 || true
fi
[[ "$test_code" == 0 ]] || exit "$test_code"
python3 - "$evidence" <<'PY'
import json,sys
from pathlib import Path
e=Path(sys.argv[1]); p=json.loads((e/'proof-inputs.json').read_text()); found=[]
def visit(n):
    if isinstance(n,dict):
        if n.get('nodeType')=='Test Case': found.append(n)
        for v in n.values(): visit(v)
    elif isinstance(n,list):
        for v in n: visit(v)
visit(json.loads((e/'tests.json').read_text()))
assert len(found)==len(p['cases'])==7
assert all(n.get('result')=='Passed' for n in found),found
assert {n['name'].removesuffix('()') for n in found}==set(p['cases'])
assert len({n['nodeIdentifier'] for n in found})==7
assert (e/'Package.resolved').read_bytes()==(e/'resolved-before.json').read_bytes()
assert list((e/'attachments').glob('**/*.png')), 'Missing actual UI screenshots'
(e/'result-validation.json').write_text(json.dumps({'status':'RESULT_CONTENTS_VALID','cases':7,'scope':p['scope']}))
PY
