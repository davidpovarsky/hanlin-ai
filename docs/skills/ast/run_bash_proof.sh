#!/bin/bash
# Fresh native parser proof. No app, engine, provider, signing or distribution operation.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
evidence="$root/build/skill-ast-bash-evidence"
mkdir -p "$evidence"
git rev-parse HEAD > "$evidence/source-sha.txt"
phase=preflight
started=$SECONDS
scratch=''
finish_phase() {
  printf '%s\n' "$((SECONDS-started))" > "$evidence/$phase-duration-seconds.txt"
  phase="$1"
  started=$SECONDS
}
retain() {
  code="$?"
  finish_phase diagnostics
  python3 - "$evidence" "$code" "$phase" <<'PY'
import json,sys
from pathlib import Path
e=Path(sys.argv[1]); code=int(sys.argv[2])
(e/'process-status.json').write_text(json.dumps({'exit_code':code,
    'status':'EXECUTED_PASS' if code==0 else 'FAILED',
    'scope':'Bash native parser POC; product/Python/TS/readiness NOT_RUN'},indent=2))
PY
  python3 Scripts/CI/generate_performance_report.py --log-dir "$evidence" \
    --run-id "${GITHUB_RUN_ID:-}" --commit-sha "$(git rev-parse HEAD)" --event-name workflow_dispatch \
    --output-json "$evidence/ci-performance-report.json" --step-summary "${GITHUB_STEP_SUMMARY:-$evidence/step-summary.md}"
  return "$code"
}
trap retain EXIT
selected_xcode="$(python3 - <<'PY'
import glob,re,shutil
assert shutil.disk_usage('.').free >= 10*1024**3
paths=[p for p in glob.glob('/Applications/Xcode*.app') if re.search(r'/Xcode[_-]27(?:[._][0-9]+)*\.app$',p)]
paths.sort(key=lambda p:tuple(map(int,re.findall(r'[0-9]+',p))))
print(paths[-1] if paths else '')
PY
)"
[[ -n "$selected_xcode" ]] || { echo 'INFRA_ERROR: no stable Xcode27'; exit 2; }
export DEVELOPER_DIR="$selected_xcode/Contents/Developer"
{ xcodebuild -version; xcrun swift --version; xcodebuild -showsdks; sw_vers; uname -m; } > "$evidence/preflight.txt"
xcrun simctl list runtimes -j > "$evidence/runtimes.json"
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/hanlin-skill-ast.XXXXXXXX")"
python3 docs/skills/ast/prepare_bash_proof.py --output "$scratch/proof" > "$evidence/preparation.json"
cp "$scratch/proof/Package.swift" "$scratch/proof/proof-inputs.json" "$evidence/"
tar -czf "$evidence/owned-sources.tar.gz" -C "$scratch/proof" Sources Tests Package.swift proof-inputs.json
finish_phase resolution
xcrun swift package --package-path "$scratch/proof" resolve 2>&1 | tee "$evidence/resolve.log"
cp "$scratch/proof/Package.resolved" "$evidence/resolved-before.json"
python3 docs/skills/ast/prepare_bash_proof.py --verify-pin "$scratch/proof/Package.resolved" > "$evidence/pin-validation.json"
python3 - "$scratch/proof" "$evidence" <<'PY'
import hashlib,json,subprocess,sys
from pathlib import Path
p=Path(sys.argv[1]); e=Path(sys.argv[2]); rows=[]
for checkout in sorted((p/'.build/checkouts').iterdir()):
    revision=subprocess.check_output(['git','-C',str(checkout),'rev-parse','HEAD'],text=True).strip()
    files=[x for x in [checkout/'Package.swift',checkout/'LICENSE',checkout/'LICENSE.md',checkout/'LICENSE.txt'] if x.exists()]
    rows.append({'directory':checkout.name,'revision':revision,
                 'files':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in files}})
(e/'upstream-source-audit.json').write_text(json.dumps(rows,indent=2))
PY
finish_phase mac-tests
cd "$scratch/proof"
xcodebuild -list -json -disableAutomaticPackageResolution > "$evidence/schemes.json"
scheme="$(python3 - "$evidence/schemes.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); s=d.get('workspace',{}).get('schemes',[])+d.get('project',{}).get('schemes',[])
print(next(x for x in ['HanlinSkillAnalysisProof-Package','HanlinSkillAnalysisProof'] if x in s))
PY
)"
printf '%s\n' "$scheme" > "$evidence/selected-scheme.txt"
xcodebuild test -scheme "$scheme" -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:BashSyntaxTests -resultBundlePath "$evidence/BashSyntax.xcresult" \
  -derivedDataPath "$scratch/DerivedData" -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "$evidence/mac-tests.log"
xcrun xcresulttool get test-results tests --path "$evidence/BashSyntax.xcresult" --format json > "$evidence/tests.json"
finish_phase simulator-compile
xcodebuild build -scheme "$scheme" -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$scratch/DerivedData" -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "$evidence/simulator-compile.log"
finish_phase device-compile
xcodebuild build -scheme "$scheme" -destination 'generic/platform=iOS' \
  -derivedDataPath "$scratch/DerivedData" -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "$evidence/device-compile.log"
finish_phase result-verification
cp Package.resolved "$evidence/Package.resolved"
cd "$root"
python3 - "$evidence" <<'PY'
import json,sys
from pathlib import Path
e=Path(sys.argv[1]); cases=[]
def visit(n):
    if isinstance(n,dict):
        if n.get('nodeType')=='Test Case':cases.append(n)
        for v in n.values():visit(v)
    elif isinstance(n,list):
        for v in n:visit(v)
visit(json.loads((e/'tests.json').read_text()))
expected=json.loads((e/'proof-inputs.json').read_text())['cases']
assert len(cases)==len(expected) and all(n.get('result')=='Passed' for n in cases),cases
assert {n['name'].removesuffix('()') for n in cases}==set(expected)
assert len({n['nodeIdentifier'] for n in cases})==len(expected)
assert (e/'Package.resolved').read_bytes()==(e/'resolved-before.json').read_bytes()
(e/'result-validation.json').write_text(json.dumps({'status':'RESULT_CONTENTS_VALID','methods':len(cases),
 'bash_fixtures':20,'macOS':'EXECUTED_PASS','iOS_simulator':'COMPILE_PASS','iOS_device':'UNSIGNED_COMPILE_PASS',
 'iOS_execution':'NOT_RUN','Python_TS_product':'NOT_RUN'},indent=2))
PY
finish_phase complete
