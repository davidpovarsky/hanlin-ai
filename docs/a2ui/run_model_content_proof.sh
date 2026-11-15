#!/bin/bash
# Focused SDK component execution. This does not claim app UI/device acceptance.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
evidence="$root/build/a2ui-model-content-evidence"
mkdir -p "$evidence"
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
python3 docs/a2ui/prepare_exact_pin_proof.py --output "$scratch/harness" > "$evidence/preparation.json"
cp "$scratch/harness/proof-inputs.json" "$scratch/harness/Package.swift" "$evidence/"
retain() {
  status="$?"
  if [[ -f "$scratch/harness/Package.resolved" ]]; then cp "$scratch/harness/Package.resolved" "$evidence/Package.resolved"; fi
  python3 - "$status" "$evidence/process-status.json" <<'PY'
import json,sys
from pathlib import Path
Path(sys.argv[2]).write_text(json.dumps({'exit_code':int(sys.argv[1]),'scope':'macOS exact-pin SDK component; UI NOT_RUN'}))
PY
}
trap retain EXIT
xcrun swift package --package-path "$scratch/harness" resolve 2>&1 | tee "$evidence/resolve.log"
python3 docs/a2ui/prepare_exact_pin_proof.py --verify-pin "$scratch/harness/Package.resolved" > "$evidence/pin-validation.json"
cp "$scratch/harness/Package.resolved" "$evidence/resolved-before.json"
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
python3 - "$scratch/harness/proof-inputs.json" <<'PY' > "$evidence/selected-cases.txt"
import json,sys
print('\n'.join(json.load(open(sys.argv[1]))['ownership_cases']))
PY
selectors=()
while IFS= read -r method; do selectors+=("-only-testing:AI_HLYTests/A2UISDKTests/$method()"); done < "$evidence/selected-cases.txt"
set +e
(
  cd "$scratch/harness"
  xcodebuild test -scheme "$scheme" -configuration Debug -destination 'platform=macOS' \
    -disableAutomaticPackageResolution -derivedDataPath "$scratch/DerivedData" \
    -resultBundlePath "$evidence/A2UI.xcresult" -skipPackagePluginValidation -skipMacroValidation \
    "${selectors[@]}" CODE_SIGNING_ALLOWED=NO
) 2>&1 | tee "$evidence/xcodebuild.log"
test_status=${PIPESTATUS[0]}
set -e
if [[ -d "$evidence/A2UI.xcresult" ]]; then
  xcrun xcresulttool get test-results tests --path "$evidence/A2UI.xcresult" --format json > "$evidence/tests.json" || true
fi
[[ "$test_status" == 0 ]] || exit "$test_status"
cmp "$evidence/resolved-before.json" "$scratch/harness/Package.resolved"
python3 docs/a2ui/prepare_exact_pin_proof.py --verify-xcresult "$evidence/tests.json" --suite ownership \
  --resolved "$scratch/harness/Package.resolved" --inputs "$scratch/harness/proof-inputs.json" \
  > "$evidence/result-validation.json"
