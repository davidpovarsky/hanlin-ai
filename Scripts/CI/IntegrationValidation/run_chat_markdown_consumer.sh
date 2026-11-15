#!/bin/bash
# Original six consumer methods, using the app-resolved runtime dependency states.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
evidence="$root/build/markdown-evidence"
renderer="$root/build/MarkdownRenderer"
mkdir -p "$evidence"
phase=resolution
phase_started=$SECONDS
finish_phase() {
  printf '%s\n' "$((SECONDS-phase_started))" > "$evidence/$phase-duration-seconds.txt"
  phase="$1"
  phase_started=$SECONDS
}
retain() {
  code="$?"
  finish_phase diagnostics
  if [[ -f "$renderer/Package.resolved" ]]; then cp "$renderer/Package.resolved" "$evidence/actual-Package.resolved"; fi
  python3 - "$evidence" "$code" <<'PY'
import json,sys
from pathlib import Path
e=Path(sys.argv[1]); code=int(sys.argv[2]); nodes=[]
def visit(n):
    if isinstance(n,dict):
        if n.get('nodeType')=='Test Case':nodes.append(n)
        for v in n.values():visit(v)
    elif isinstance(n,list):
        for v in n:visit(v)
if (e/'tests.json').exists():visit(json.loads((e/'tests.json').read_text()))
actual=[x for x in nodes if x.get('nodeIdentifier','').startswith(('CodeBlockRendererTests/','CodeBlockConfigTests/'))]
log=(e/'xcodebuild.log').read_text(errors='replace') if (e/'xcodebuild.log').exists() else ''
status='EXECUTED_PASS' if code==0 else 'TEST_FAILED' if actual else 'BUILD_FAILED' if ': error:' in log else 'INFRA_ERROR'
(e/'process-status.json').write_text(json.dumps({'status':status,'exit_code':code,'executed_cases':len(actual),
 'system_failure_nodes':len(nodes)-len(actual),'scope':'original six renderer consumer methods; app/UI/playback NOT_RUN'},indent=2))
PY
  cd "$root"
  python3 Scripts/CI/generate_performance_report.py --log-dir "$evidence" \
    --run-id "${GITHUB_RUN_ID:-}" --commit-sha "$(git rev-parse HEAD)" --event-name workflow_dispatch \
    --output-json "$evidence/ci-performance-report.json" --step-summary "${GITHUB_STEP_SUMMARY:-$evidence/step-summary.md}"
  return "$code"
}
trap retain EXIT
cd "$renderer"
xcodebuild -resolvePackageDependencies -scheme SwiftStreamingMarkdown \
  -clonedSourcePackagesDirPath "$root/build/MarkdownSourcePackages" \
  2>&1 | tee "$evidence/resolve.log"
python3 "$root/Scripts/CI/prepare_markdown_consumer_closure.py" --verify-lock Package.resolved > "$evidence/resolution-validation.json"
cp Package.resolved "$evidence/resolved-before-tests.json"
python3 - "$root/build/MarkdownSourcePackages/checkouts" "$evidence" "$root" <<'PY'
import hashlib,json,subprocess,sys
from pathlib import Path
root=Path(sys.argv[1]); evidence=Path(sys.argv[2]); rows=[]
for p in sorted(root.iterdir()):
    if not p.is_dir():continue
    revision=subprocess.check_output(['git','-C',str(p),'rev-parse','HEAD'],text=True).strip()
    files=[x for x in [p/'Package.swift',p/'LICENSE',p/'LICENSE.md',p/'LICENSE.txt'] if x.exists()]
    rows.append({'directory':p.name,'revision':revision,'files':{x.name:hashlib.sha256(x.read_bytes()).hexdigest() for x in files}})
(evidence/'dependency-source-audit.json').write_text(json.dumps(rows,indent=2))
sys.path.insert(0,str(Path(sys.argv[3])/'Scripts/CI'))
from prepare_markdown_consumer_closure import verify_checkouts
verify_checkouts(rows,json.loads((evidence/'closure-contract.json').read_text()))
(evidence/'actual-checkouts-validation.json').write_text(json.dumps({'status':'ALL_10_ACTUAL_GIT_REVISIONS_MATCH'}))
PY
finish_phase build-and-test
set +e
xcodebuild test -scheme SwiftStreamingMarkdown \
  -destination "platform=iOS Simulator,id=$MARKDOWN_DEVICE" \
  -destination-timeout 60 -parallel-testing-enabled NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 180 \
  -clonedSourcePackagesDirPath "$root/build/MarkdownSourcePackages" \
  -derivedDataPath "$RUNNER_TEMP/MarkdownDerivedData" \
  -resultBundlePath "$RUNNER_TEMP/MarkdownConsumer.xcresult" \
  -only-testing:SwiftStreamingMarkdownTests/CodeBlockRendererTests \
  -only-testing:SwiftStreamingMarkdownTests/CodeBlockConfigTests \
  -disableAutomaticPackageResolution -skipMacroValidation CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "$evidence/xcodebuild.log"
test_code=${PIPESTATUS[0]}
set -e
finish_phase results
if [[ -d "$RUNNER_TEMP/MarkdownConsumer.xcresult" ]]; then
  python3 - "$RUNNER_TEMP/MarkdownConsumer.xcresult" "$evidence" <<'PY'
import json,subprocess,sys
from pathlib import Path
bundle=Path(sys.argv[1]);e=Path(sys.argv[2])
try:
    result=subprocess.run(['xcrun','xcresulttool','get','test-results','tests','--path',str(bundle),'--format','json'],
                          capture_output=True,text=True,timeout=30,check=True)
    json.loads(result.stdout);(e/'tests.json').write_text(result.stdout)
    subprocess.run(['tar','-czf',str(e/'CodeBlocks.xcresult.tar.gz'),'-C',str(bundle.parent),bundle.name],
                   capture_output=True,timeout=90,check=True)
    (e/'raw-result-status.json').write_text(json.dumps({'status':'FINALIZED_READABLE_ARCHIVED'}))
except (OSError,ValueError,subprocess.SubprocessError) as error:
    (e/'CodeBlocks.xcresult.tar.gz').unlink(missing_ok=True)
    (e/'raw-result-status.json').write_text(json.dumps({'status':'RAW_RESULT_UNAVAILABLE','reason':type(error).__name__}))
    raise
PY
fi
[[ "$test_code" == 0 ]] || exit "$test_code"
python3 "$root/Scripts/CI/prepare_markdown_consumer_closure.py" --verify-lock Package.resolved > "$evidence/final-pin-validation.json"
python3 - "$evidence" "$renderer" <<'PY'
import hashlib,json,subprocess,sys
from pathlib import Path
e=Path(sys.argv[1]); renderer=Path(sys.argv[2]); c=json.loads((e/'closure-contract.json').read_text()); found=[]
def visit(n):
    if isinstance(n,dict):
        if n.get('nodeType')=='Test Case':found.append(n)
        for v in n.values():visit(v)
    elif isinstance(n,list):
        for v in n:visit(v)
visit(json.loads((e/'tests.json').read_text()))
expected={suite+'/'+name+'()' for suite,names in c['expected_cases'].items() for name in names}
assert len(found)==len(expected)==6 and all(n.get('result')=='Passed' for n in found)
assert {n['nodeIdentifier'] for n in found}==expected
assert (renderer/'Package.resolved').read_bytes()==(e/'resolved-before-tests.json').read_bytes()
assert (renderer/'Package.swift').read_bytes()==(e/'renderer-Package.swift').read_bytes()
assert subprocess.check_output(['git','-C',str(renderer),'diff','--name-only']).decode().splitlines()==['Package.resolved']
(e/'result-validation.json').write_text(json.dumps({'status':'RESULT_CONTENTS_VALID','exact_methods':6,
 'actual_runtime_pins':'MATCH_AUTHENTICATED_APP_CLOSURE','renderer_source_changes':False,'app_OR_UI':'NOT_RUN'},indent=2))
PY
finish_phase complete
