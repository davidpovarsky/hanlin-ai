#!/bin/bash
# Focused SDK component execution. This does not claim app UI/device acceptance.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
platform="${A2UI_PROOF_PLATFORM:-macos}"
[[ "$platform" == ios || "$platform" == macos ]] || { echo 'Unsupported proof platform'; exit 2; }
proof=(python3 docs/a2ui/prepare_exact_pin_proof.py --platform "$platform")
if [[ "${A2UI_PROOF_SUITE:-ownership}" == consumer || "${A2UI_PROOF_SUITE:-ownership}" == app ]]; then proof+=(--sdk-consumer); fi
if [[ "${A2UI_PROOF_SUITE:-ownership}" == app ]]; then proof+=(--app-consumer); fi
evidence="$root/build/a2ui-model-content-evidence"
mkdir -p "$evidence"
proof_phase=preflight
proof_phase_started=$SECONDS
finish_phase() {
  printf '%s\n' "$((SECONDS-proof_phase_started))" > "$evidence/$proof_phase-duration-seconds.txt"
  proof_phase="$1"
  proof_phase_started=$SECONDS
}
phase=preflight
scratch=''
retain() {
  status="$?"
  finish_phase diagnostics
  if [[ -n "$scratch" && -f "$scratch/harness/Package.resolved" ]]; then cp "$scratch/harness/Package.resolved" "$evidence/Package.resolved"; fi
  python3 - "$status" "$phase" "$evidence" "$platform" "${A2UI_PROOF_SUITE:-ownership}" <<'PY'
import json,subprocess,sys
from pathlib import Path
e=Path(sys.argv[3]);code=int(sys.argv[1]);phase=sys.argv[2];cases=[]
def visit(n):
    if isinstance(n,dict):
        if n.get('nodeType')=='Test Case':cases.append(n)
        for v in n.values():visit(v)
    elif isinstance(n,list):
        for v in n:visit(v)
if (e/'tests.json').exists():
    try:visit(json.loads((e/'tests.json').read_text()))
    except (OSError,ValueError):pass
log=(e/'xcodebuild.log').read_text(errors='replace') if (e/'xcodebuild.log').exists() else ''
status=('COMPILE_PASS' if sys.argv[5]=='compile' else 'EXECUTED_PASS') if code==0 else ('TEST_FAILED' if cases else 'BUILD_FAILED' if phase!='preflight' and 'error:' in log else 'INFRA_ERROR')
if code and (e/'selected-device.txt').exists():
    device=(e/'selected-device.txt').read_text().strip();diagnostics={}
    for name,args in [('screenshot',['xcrun','simctl','io',device,'screenshot',str(e/'failure.png')]),
                      ('simulator-log',['xcrun','simctl','spawn',device,'log','show','--last','2m','--style','compact'])]:
        try:
            r=subprocess.run(args,capture_output=True,text=True,timeout=5)
            diagnostics[name]={'exit_code':r.returncode};(e/(name+'.txt')).write_text(r.stdout+r.stderr)
        except (subprocess.TimeoutExpired,OSError) as err:diagnostics[name]={'unavailable':type(err).__name__}
    diagnostics['accessibility']='NOT_AVAILABLE: component SDK runner has no original app XCUITest hierarchy'
    (e/'failure-diagnostics.json').write_text(json.dumps(diagnostics,indent=2))
(e/'process-status.json').write_text(json.dumps({'exit_code':code,'status':status,'phase':phase,'executed_cases':len(cases),
    'platform':sys.argv[4],'suite':sys.argv[5],'xcresult_exists':(e/'A2UI.xcresult').exists(),'scope':'official exact-pin SDK component; app UI NOT_RUN'},indent=2))
PY
  finish_phase complete
  python3 Scripts/CI/generate_performance_report.py --log-dir "$evidence" \
    --run-id "${GITHUB_RUN_ID:-}" --commit-sha "$(git rev-parse HEAD)" \
    --event-name "${GITHUB_EVENT_NAME:-workflow_dispatch}" \
    --output-json "$evidence/ci-performance-report.json" --step-summary "${GITHUB_STEP_SUMMARY:-$evidence/step-summary.md}"
  return "$status"
}
trap retain EXIT
git rev-parse HEAD > "$evidence/source-sha.txt"
df -h . > "$evidence/disk.txt"
selected_xcode="$(python3 - <<'PY'
import glob,re
paths=[p for p in glob.glob('/Applications/Xcode*.app') if re.search(r'/Xcode[_-]27(?:[._][0-9]+)*\.app$',p)]
paths.sort(key=lambda p:tuple(map(int,re.findall(r'[0-9]+',p))))
print(paths[-1] if paths else '')
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
  for cli in python3 idb maestro; do command -v "$cli" || true; done
} > "$evidence/preflight.txt"
xcrun simctl list runtimes -j > "$evidence/runtimes.json"
destination='platform=macOS'
if [[ "$platform" == ios ]]; then
  xcrun simctl list devices available -j > "$evidence/devices.json"
  python3 - "$evidence/devices.json" <<'PY' > "$evidence/selected-device.txt"
import json,sys
d=json.load(open(sys.argv[1]))['devices']
eligible=[x for runtime,rows in d.items() if '.iOS-27-' in runtime for x in rows
          if x.get('isAvailable') and x['name'].startswith('iPhone')]
assert eligible,'No actual available iPhone/iOS27 runtime'
print(eligible[0]['udid'])
PY
  destination="platform=iOS Simulator,id=$(cat "$evidence/selected-device.txt")"
fi
skill="$HOME/.codex/skills/ios-simulator-skill/scripts/sim_health_check.sh"
if [[ -f "$skill" ]]; then
  bash "$skill" > "$evidence/skill-health.txt" 2>&1 || true
else
  echo 'NOT_AVAILABLE on runner; component tests use xcodebuild, not idb/Maestro.' > "$evidence/skill-health.txt"
fi
python3 - <<'PY'
import shutil,subprocess
assert int(subprocess.check_output(['sw_vers','-productVersion'],text=True).split('.')[0])>=27
assert int(subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-version'],text=True).split('.')[0])>=27
assert shutil.disk_usage('.').free>=10*1024**3, 'INFRA_ERROR: less than10GiB free'
PY
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/a2ui-model-content.XXXXXXXX")"
if [[ "${A2UI_PROOF_SUITE:-ownership}" == consumer || "${A2UI_PROOF_SUITE:-ownership}" == app ]]; then
  sdk_source=18813519eada1db152bd206d5c7bd922ddc987ee
  if [[ "${A2UI_PROOF_SUITE:-ownership}" == app ]]; then sdk_source=d1eedf9ed73b4f6c7c64f488caf92494602db865; fi
  # Read an immutable SDK sibling snapshot; no checkout, copied engine implementation or product pin change.
  git fetch --no-tags --depth=1 https://github.com/davidpovarsky/hanlin-ai.git \
    "$sdk_source" 2>&1 | tee "$evidence/sdk-fetch.log"
fi
"${proof[@]}" --output "$scratch/harness" > "$evidence/preparation.json"
cp "$scratch/harness/proof-inputs.json" "$scratch/harness/Package.swift" "$evidence/"
finish_phase resolution
xcrun swift package --package-path "$scratch/harness" resolve 2>&1 | tee "$evidence/resolve.log"
"${proof[@]}" --verify-pin "$scratch/harness/Package.resolved" > "$evidence/pin-validation.json"
cp "$scratch/harness/Package.resolved" "$evidence/resolved-before.json"
finish_phase scheme-preflight
(
  cd "$scratch/harness"
  xcodebuild -list -json -disableAutomaticPackageResolution
) > "$evidence/schemes.json"
scheme="$(python3 - "$evidence/schemes.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]));s=d.get('workspace',{}).get('schemes',[])+d.get('project',{}).get('schemes',[])
print(next(x for x in ['HanlinA2UIProof-Package','HanlinA2UIProof','AI_Hanlin'] if x in s))
PY
)"
printf '%s\n' "$scheme" > "$evidence/selected-scheme.txt"
if [[ "$platform" == ios ]]; then
  (cd "$scratch/harness"; xcodebuild -scheme "$scheme" -showdestinations) > "$evidence/destinations.txt"
  grep -q "$(cat "$evidence/selected-device.txt")" "$evidence/destinations.txt" || { echo 'INFRA_ERROR: unsupported actual destination'; exit 2; }
fi
suite="${A2UI_PROOF_SUITE:-ownership}"
[[ "$suite" == all || "$suite" == ownership || "$suite" == media || "$suite" == consumer || "$suite" == compile || "$suite" == app ]] || { echo 'Unsupported focused proof suite'; exit 2; }
python3 - "$scratch/harness/proof-inputs.json" "$suite" <<'PY' > "$evidence/selected-cases.txt"
import json,sys
p=json.load(open(sys.argv[1]))
if sys.argv[2]=='app':
    names=(['HanlinA2UIAppPresentationTests/'+x+'()' for x in p['app_cases']]
           +['HanlinA2UIAgentPresentationTests/'+x+'()' for x in p['consumer_cases']]
           +['A2UISDKTests/'+x+'()' for x in p['projection_cases']])
elif sys.argv[2]=='compile':
    names=[]
elif sys.argv[2]=='consumer':
    names=(['HanlinA2UIAgentPresentationTests/'+x+'()' for x in p['consumer_cases']]
           +['A2UISDKTests/'+x+'()' for x in p['ownership_cases']]
           +['HanlinA2UICompleteBatchValidatorTests/'+x+'()' for x in p['validator_cases']])
elif sys.argv[2]=='all':
    names=['A2UIIngressTests/'+x+'()' for x in p['portable_cases']]+['A2UISDKTests/'+x+'()' for x in p['sdk_cases']]
else:
    field='media_cases' if sys.argv[2]=='media' else 'ownership_cases'
    names=[('A2UISDKTests/' if x in p['sdk_cases'] else 'HanlinRemoteMediaURLTests/')+x+'()' for x in p[field]]
print('\n'.join(names))
PY
selectors=(CODE_SIGNING_ALLOWED=NO) # Bash3.2 treats expansion of an empty array as unbound under set -u.
while IFS= read -r method; do [[ -z "$method" ]] || selectors+=("-only-testing:AI_HLYTests/$method"); done < "$evidence/selected-cases.txt"
action=test
if [[ "$suite" == compile ]]; then action=build; fi
phase=build-and-test
if [[ "$action" == build ]]; then phase=build-only; fi
finish_phase "$phase"
set +e
(
  cd "$scratch/harness"
  xcodebuild "$action" -scheme "$scheme" -configuration Debug -destination "$destination" \
    -parallel-testing-enabled NO -destination-timeout 60 \
    -disableAutomaticPackageResolution -derivedDataPath "$scratch/DerivedData" \
    -resultBundlePath "$evidence/A2UI.xcresult" -skipPackagePluginValidation -skipMacroValidation \
    "${selectors[@]}"
) 2>&1 | tee "$evidence/xcodebuild.log"
test_status=${PIPESTATUS[0]}
set -e
finish_phase result-verification
if [[ -d "$evidence/A2UI.xcresult" && "$suite" != compile ]]; then
  xcrun xcresulttool get test-results tests --path "$evidence/A2UI.xcresult" --format json > "$evidence/tests.json" || true
fi
[[ "$test_status" == 0 ]] || exit "$test_status"
cmp "$evidence/resolved-before.json" "$scratch/harness/Package.resolved"
if [[ "$suite" == compile ]]; then
  printf '%s\n' '{"status":"COMPILE_PASS","executed_cases":0,"ui_behavior":"NOT_RUN"}' > "$evidence/result-validation.json"
  exit 0
fi
"${proof[@]}" --verify-xcresult "$evidence/tests.json" --suite "$suite" \
  --resolved "$scratch/harness/Package.resolved" --inputs "$scratch/harness/proof-inputs.json" \
  > "$evidence/result-validation.json"
