#!/bin/bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
evidence="$root/build/integration-validation-evidence"
mkdir -p "$evidence"
workflow_sha="$(git rev-parse HEAD)"
source_sha=fa810e87213ee45da76b465ef50e6b54edc74a86
[[ "${INTEGRATION_EXPECTED_SHA:-}" =~ ^[0-9a-f]{40}$ && "$workflow_sha" == "$INTEGRATION_EXPECTED_SHA" ]] || {
  echo 'Exact workflow checkout SHA mismatch' >&2; exit 2;
}
printf '%s\n' "$workflow_sha" > "$evidence/workflow-commit.txt"
printf '%s\n' "$source_sha" > "$evidence/tested-source-commit.txt"
if ! git cat-file -e "$source_sha^{commit}" 2>/dev/null; then
  git fetch --no-tags --depth=1 origin "$source_sha"
fi
git rev-parse "$source_sha^{tree}" > "$evidence/tested-source-tree.txt"
selected_xcode="$(python3 - <<'PY'
import glob,re
paths=[p for p in glob.glob('/Applications/Xcode*.app') if re.search(r'/Xcode[_-]27(?:[._][0-9]+)*\.app$',p)]
paths.sort(key=lambda p:tuple(map(int,re.findall(r'[0-9]+',p))))
print(paths[-1] if paths else '')
PY
)"
[[ -n "$selected_xcode" ]] || { echo 'No stable installed Xcode 27' >&2; exit 2; }
export DEVELOPER_DIR="$selected_xcode/Contents/Developer"
xcodebuild -version | tee "$evidence/xcode.txt"
xcrun swift --version | tee "$evidence/swift.txt"
xcrun --sdk macosx --show-sdk-version | tee "$evidence/sdk.txt"
sw_vers | tee "$evidence/os.txt"
python3 - "$evidence/sdk.txt" <<'PY'
import subprocess,sys
host=subprocess.check_output(['sw_vers','-productVersion'],text=True).strip()
assert int(host.split('.')[0])>=27, 'Recipe requires a macOS 27+ host, not merely an installed SDK'
assert int(open(sys.argv[1]).read().strip().split('.')[0])>=27, 'macOS SDK 27+ required'
PY
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/hanlin-a2ui-proof.XXXXXXXX")"
mkdir "$scratch/source"
git archive "$source_sha" \
  AI_HLY/Downstream/ChatPresentation/A2UI AI_HLYTests/A2UITests.swift AI_HLYTests/A2UIFixtures \
  docs/a2ui/prepare_exact_pin_proof.py docs/a2ui/EXACT_PIN_PROOF_ROUTE.md \
  > "$evidence/tested-source.tar"
tar -xf "$evidence/tested-source.tar" -C "$scratch/source"
python3 - "$source_sha" "$scratch/source" <<'PY' > "$evidence/tested-source-sha256.json"
import hashlib,json,subprocess,sys
from pathlib import Path
source=Path(sys.argv[2]);hashes={}
for path in sorted(p for p in source.rglob('*') if p.is_file()):
    relative=path.relative_to(source).as_posix();data=path.read_bytes()
    assert data==subprocess.check_output(['git','show',f'{sys.argv[1]}:{relative}']),relative
    hashes[relative]=hashlib.sha256(data).hexdigest()
print(json.dumps(hashes,indent=2))
PY
recipe="$scratch/source/docs/a2ui/prepare_exact_pin_proof.py"
python3 "$recipe" --output "$scratch/harness" | tee "$evidence/preparation.json"
cp "$scratch/harness/Package.swift" "$evidence/Harness-Package.swift"
cp "$scratch/harness/proof-inputs.json" "$evidence/proof-inputs.json"
python3 - <<'PY' > "$evidence/workflow-sha256.json"
import hashlib,json,subprocess
from pathlib import Path
paths=['.github/workflows/build-ios26-unsigned-ipa.yml']+subprocess.check_output(['git','ls-files','Scripts/CI/IntegrationValidation'],text=True).splitlines()
hashes={}
for path in paths:
    data=Path(path).read_bytes()
    assert data==subprocess.check_output(['git','show',f'HEAD:{path}']),path
    hashes[path]=hashlib.sha256(data).hexdigest()
print(json.dumps(hashes,indent=2))
PY
retain_locks() {
  local process_status="$1"
  python3 - "$scratch/harness" "$evidence" "$process_status" <<'PY'
import hashlib,json,os,sys
from pathlib import Path
records=[];evidence=Path(sys.argv[2]);folder=evidence/'raw-locks';folder.mkdir(exist_ok=True)
for directory,folders,files in os.walk(sys.argv[1]):
    folders[:]=[name for name in folders if name not in ['.build','.git']]
    if 'Package.resolved' not in files:continue
    path=Path(directory)/'Package.resolved';data=path.read_bytes()
    raw=folder/f'{len(records):02d}-Package.resolved';raw.write_bytes(data)
    records.append({'source_path':str(path),'raw_file':str(raw.relative_to(evidence)),
                    'sha256':hashlib.sha256(data).hexdigest(),'resolved':json.loads(data)})
(evidence/'resolution.json').write_text(json.dumps(records,indent=2))
(evidence/'process-status.json').write_text(json.dumps({'exit_code':int(sys.argv[3]),'scope':'official exact-pin macOS27 enabled A2UI consumer'}))
PY
}
trap 'retain_locks "$?"' EXIT
xcrun swift package --package-path "$scratch/harness" resolve 2>&1 | tee "$evidence/resolve.log"
cp "$scratch/harness/Package.resolved" "$evidence/resolved-before.json"
python3 "$recipe" --verify-pin "$scratch/harness/Package.resolved" | tee "$evidence/pin-validation.json"
(
  cd "$scratch/harness"
  xcodebuild -list -json -disableAutomaticPackageResolution > "$evidence/package-schemes.json"
)
scheme="$(python3 - "$evidence/package-schemes.json" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]));schemes=data.get('workspace',{}).get('schemes',[])+data.get('project',{}).get('schemes',[])
print(next(s for s in ['HanlinA2UIProof-Package','HanlinA2UIProof','AI_Hanlin'] if s in schemes))
PY
)"
printf '%s\n' "$scheme" > "$evidence/scheme.txt"
set +e
(
  cd "$scratch/harness"
  xcodebuild test -scheme "$scheme" -configuration Debug -destination 'platform=macOS' \
    -disableAutomaticPackageResolution -derivedDataPath "$scratch/DerivedData" \
    -resultBundlePath "$evidence/A2UI.xcresult" \
    -skipPackagePluginValidation -skipMacroValidation \
    -only-testing:AI_HLYTests/A2UIIngressTests -only-testing:AI_HLYTests/A2UISDKTests \
    CODE_SIGNING_ALLOWED=NO
) 2>&1 | tee "$evidence/xcodebuild.log"
test_status=${PIPESTATUS[0]}
set -e
if [[ -d "$evidence/A2UI.xcresult" ]]; then
  xcrun xcresulttool get test-results tests --path "$evidence/A2UI.xcresult" --format json > "$evidence/tests.json" || true
fi
[[ "$test_status" == 0 ]] || exit "$test_status"
cmp "$evidence/resolved-before.json" "$scratch/harness/Package.resolved"
python3 Scripts/CI/IntegrationValidation/xcresult_to_xunit.py "$evidence/tests.json" "$evidence/actual-results.xml" > "$evidence/actual-case-identities.json"
python3 "$recipe" --verify-results "$evidence/actual-results.xml" \
  --resolved "$scratch/harness/Package.resolved" --inputs "$scratch/harness/proof-inputs.json" \
  | tee "$evidence/result-validation.json"
retain_locks 0
for lock in "$evidence/"raw-locks/*-Package.resolved; do
  python3 "$recipe" --verify-pin "$lock"
done
