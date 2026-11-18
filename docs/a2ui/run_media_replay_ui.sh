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
raw_nodes=len(cases)
expected=json.loads((e/'selection.json').read_text())['selected_cases'] if (e/'selection.json').exists() else []
cases=[n for n in cases if n.get('name','').removesuffix('()') in expected]
log=(e/'xcodebuild.log').read_text(errors='replace') if (e/'xcodebuild.log').exists() else ''
status='EXECUTED_PASS' if code==0 else 'TEST_FAILED' if cases else 'BUILD_FAILED' if 'error:' in log else 'INFRA_ERROR'
(e/'process-status.json').write_text(json.dumps({'status':status,'exit_code':code,'executed_cases':len(cases),
    'system_failure_nodes':raw_nodes-len(cases),
    'xcresult_archive_exists':(e/'MediaReplay.xcresult.tar.gz').exists(),
    'scope':'actual SwiftUI component UI; full app/provider/playback/physical NOT_RUN'},indent=2))
if (e/'selected-device.txt').exists():
    device=(e/'selected-device.txt').read_text().strip()
    try:
        subprocess.run(['xcrun','simctl','io',device,'screenshot',str(e/'final.png')],check=False,timeout=5,capture_output=True)
    except (OSError,subprocess.TimeoutExpired): pass
    if (e/'owned-device.txt').exists() and (e/'owned-device.txt').read_text().strip()==device:
        try:
            subprocess.run(['xcrun','simctl','shutdown',device],check=False,timeout=30,capture_output=True)
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
python3 - "$evidence" <<'PY' > "$evidence/selected-device.txt"
import json,os,subprocess,sys
from pathlib import Path
e=Path(sys.argv[1])
sdk=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-version'],text=True).strip()
assert int(sdk.split('.')[0])==27,sdk
runtime=next(r for r in json.loads((e/'runtimes.json').read_text())['runtimes']
    if r.get('isAvailable') and not r.get('isInternal') and r['identifier'].endswith('iOS-'+sdk.replace('.','-')))
types=json.loads(subprocess.check_output(['xcrun','simctl','list','devicetypes','-j']))
supported={t['identifier'] for t in runtime['supportedDeviceTypes']}
device=next(t for t in types['devicetypes'] if t.get('productFamily')=='iPhone' and t['identifier'] in supported)
udid=subprocess.check_output(['xcrun','simctl','create','HanlinMedia-'+os.environ.get('GITHUB_RUN_ID','local'),
    device['identifier'],runtime['identifier']],text=True).strip()
(e/'owned-device.txt').write_text(udid+'\n')
(e/'verified-environment.json').write_text(json.dumps({'sdk':sdk,'runtime':runtime,'device':device,'udid':udid},indent=2))
print(udid)
PY
device="$(cat "$evidence/selected-device.txt")"
finish_phase preparation
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/a2ui-media-ui.XXXXXXXX")"
python3 docs/a2ui/prepare_media_replay_ui.py --output "$scratch/host" > "$evidence/preparation.json"
cp "$scratch/host/proof-inputs.json" "$scratch/host/project.json" "$evidence/"
python3 - "$evidence" <<'PY'
import json,os,re,sys
from pathlib import Path
e=Path(sys.argv[1]); all_cases=json.loads((e/'proof-inputs.json').read_text())['cases']
raw=os.environ.get('A2UI_MEDIA_UI_TESTS','').strip()
selected=[x.removeprefix('MediaReplayUITests/MediaReplayUITests/').removesuffix('()')
          for x in re.split(r'[,\s]+',raw)] if raw else all_cases
assert selected and len(set(selected))==len(selected) and set(selected)<=set(all_cases),selected
(e/'selected-cases.txt').write_text('\n'.join(selected)+'\n')
(e/'selection.json').write_text(json.dumps({'selected_cases':selected,'all_fixture_cases':all_cases},indent=2))
PY
xcodegen generate --spec "$scratch/host/project.json" --project "$scratch/host" > "$evidence/xcodegen.log"
project="$scratch/host/MediaReplay.xcodeproj"
finish_phase resolution
xcodebuild -resolvePackageDependencies -project "$project" -scheme MediaReplay > "$evidence/resolve.log" 2>&1
lock="$project/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
cp "$lock" "$evidence/resolved-before.json"
python3 - "$lock" <<'PY' > "$evidence/pin-validation.json"
import json,sys
sys.path.insert(0,'docs/a2ui')
from prepare_media_replay_ui import verify_media_pins
verify_media_pins(json.load(open(sys.argv[1])))
print('{"status":"EXACT_PIN_VERIFIED"}')
PY
finish_phase build-and-test
selectors=(CODE_SIGNING_ALLOWED=NO)
while IFS= read -r name; do selectors+=("-only-testing:MediaReplayUITests/MediaReplayUITests/$name"); done < "$evidence/selected-cases.txt"
set +e
xcodebuild test -project "$project" -scheme MediaReplay -configuration Debug \
  -destination "platform=iOS Simulator,id=$device" -parallel-testing-enabled NO \
  -destination-timeout 60 -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 240 \
  -derivedDataPath "$scratch/DerivedData" -resultBundlePath "$scratch/MediaReplay.xcresult" \
  -disableAutomaticPackageResolution \
  -skipPackagePluginValidation -skipMacroValidation \
  "${selectors[@]}" 2>&1 | tee "$evidence/xcodebuild.log"
test_code=${PIPESTATUS[0]}
set -e
finish_phase result-verification
cp "$lock" "$evidence/Package.resolved"
if [[ -d "$scratch/MediaReplay.xcresult" ]]; then
  # The owned xcodebuild operation has exited. Require bounded readable final results
  # before archiving; never expose a still-changing Staging directory to upload.
  python3 - "$scratch/MediaReplay.xcresult" "$evidence" <<'PY'
import json,subprocess,sys
from pathlib import Path
bundle=Path(sys.argv[1]); e=Path(sys.argv[2])
try:
    result=subprocess.run(['xcrun','xcresulttool','get','test-results','tests','--path',str(bundle),'--format','json'],
                          capture_output=True,text=True,timeout=30,check=True)
    json.loads(result.stdout)
    (e/'tests.json').write_text(result.stdout)
    subprocess.run(['tar','-czf',str(e/'MediaReplay.xcresult.tar.gz'),'-C',str(bundle.parent),bundle.name],
                   capture_output=True,timeout=90,check=True)
    with (e/'attachment-export.log').open('w') as log:
        subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(bundle),'--output-path',str(e/'attachments')],
                       stdout=log,stderr=subprocess.STDOUT,timeout=60,check=True)
    (e/'raw-result-status.json').write_text(json.dumps({'status':'FINALIZED_READABLE_ARCHIVED'}))
except (OSError,ValueError,subprocess.SubprocessError) as error:
    # Only immutable finalized archives qualify as raw evidence. Stable small logs
    # and source/commands/selection survive even when finalization is unavailable.
    (e/'MediaReplay.xcresult.tar.gz').unlink(missing_ok=True)
    (e/'raw-result-status.json').write_text(json.dumps({'status':'RAW_RESULT_UNAVAILABLE','reason':type(error).__name__}))
    raise
PY
fi
[[ "$test_code" == 0 ]] || exit "$test_code"
python3 - "$evidence" <<'PY'
import json,sys
from pathlib import Path
e=Path(sys.argv[1]); p=json.loads((e/'proof-inputs.json').read_text()); found=[]
expected=json.loads((e/'selection.json').read_text())['selected_cases']
def visit(n):
    if isinstance(n,dict):
        if n.get('nodeType')=='Test Case': found.append(n)
        for v in n.values(): visit(v)
    elif isinstance(n,list):
        for v in n: visit(v)
visit(json.loads((e/'tests.json').read_text()))
assert len(found)==len(expected)
assert all(n.get('result')=='Passed' for n in found),found
assert {n['name'].removesuffix('()') for n in found}==set(expected)
assert len({n['nodeIdentifier'] for n in found})==len(expected)
assert (e/'Package.resolved').read_bytes()==(e/'resolved-before.json').read_bytes()
assert list((e/'attachments').glob('**/*.png')), 'Missing actual UI screenshots'
(e/'result-validation.json').write_text(json.dumps({'status':'RESULT_CONTENTS_VALID','cases':len(expected),'scope':p['scope']}))
PY
