#!/bin/bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
evidence="$root/build/agent-sdk-validation-evidence"
mkdir -p "$evidence"
producer_sha=febe93e2717a9a647ae85feccb97117e72d6e176
started=$SECONDS
finish_producer_schema() {
  local rc="$?"
  if [[ ! -s "$evidence/summary.json" || ! -d "$evidence/ProducerSchemaTests.xcresult" ]]; then
    if [[ "$rc" == 0 ]]; then rc=1; fi
  fi
  printf '{"exit":%s,"total_seconds":%s}\n' "$rc" "$((SECONDS-started))" > "$evidence/process-exit.json"
  if [[ -f "$evidence/producer-schema-tests.log" ]]; then
    grep -E 'error:|recorded an issue' "$evidence/producer-schema-tests.log" | head -n 15 >&2 || true
  fi
  trap - EXIT
  exit "$rc"
}
trap finish_producer_schema EXIT
git rev-parse HEAD > "$evidence/workflow-source-commit.txt"
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/hanlin-producer-schema.XXXXXXXX")"
python3 - "$scratch" <<'PY_DISK'
import shutil,sys
assert shutil.disk_usage(sys.argv[1]).free >= 8*1024**3
PY_DISK
producer="$scratch/Producer"
git clone --no-checkout --filter=blob:none --single-branch --branch codex/hanlin-raw-tool-input-20261115 \
  https://github.com/davidpovarsky/swift-ai-sdk.git "$producer" > "$evidence/producer-clone.log" 2>&1
git -C "$producer" checkout --detach "$producer_sha" >> "$evidence/producer-clone.log" 2>&1
test "$(git -C "$producer" rev-parse HEAD)" = "$producer_sha"
printf '%s\n' "$producer_sha" > "$evidence/producer-source-commit.txt"
git -C "$producer" archive HEAD Package.swift Sources Tests > "$evidence/producer-source.tar"
python3 - "$producer" "$evidence" <<'PY_SOURCE'
import hashlib,json,re,subprocess,sys
from pathlib import Path
producer,evidence=map(Path,sys.argv[1:])
paths=subprocess.check_output(['git','-C',str(producer),'ls-files','Package.swift','Package.resolved','Sources','Tests'],text=True).splitlines()
(evidence/'producer-source-sha256.json').write_text(json.dumps({p:hashlib.sha256((producer/p).read_bytes()).hexdigest() for p in paths},indent=2))
source=(producer/'Tests/AISDKProviderUtilsTests/JSONSchemaValidatorTests.swift').read_text()
expected=[];pending=False
for line in source.splitlines():
    if re.search(r'^\s*@Test\b',line):pending=True
    method=re.search(r'\bfunc\s+(\w+)\s*\(',line)
    if pending and method:expected.append(method[1]);pending=False
assert len(expected)==25 and len(set(expected))==25
assert {'booleanSchemasRejectAtRootAndNestedLocations','unicodeScalarLengthsDoNotCountUTF16UnitsOrGraphemeClusters','publicFacadeEnforcesFalseSchemaAndUnicodeScalarLength'} <= set(expected)
(evidence/'expected-tests.json').write_text(json.dumps(expected,indent=2))
PY_SOURCE
selected_xcode="$(python3 -c 'import glob,re; p=[p for p in glob.glob("/Applications/Xcode*.app") if re.search(r"/Xcode[_-]27(?:[._][0-9]+)*\.app$",p)]; p.sort(key=lambda x:tuple(map(int,re.findall(r"[0-9]+",x)))); print(p[-1] if p else "")')"
test -n "$selected_xcode"
export DEVELOPER_DIR="$selected_xcode/Contents/Developer"
{ xcodebuild -version; xcrun swift --version; xcrun --sdk macosx --show-sdk-version; uname -m; sw_vers; } > "$evidence/toolchain.txt"
(cd "$producer" && xcodebuild -list -json) > "$evidence/schemes.json"
scheme="$(python3 - "$evidence/schemes.json" <<'PY_SCHEME'
import json,sys
d=json.load(open(sys.argv[1]));names=d.get('workspace',{}).get('schemes',[])+d.get('project',{}).get('schemes',[])
print(next(x for x in ['SwiftAISDK-Package','SwiftAISDK'] if x in names))
PY_SCHEME
)"
set +e
(cd "$producer" && AGENT=1 xcodebuild test -scheme "$scheme" -destination 'platform=macOS' \
  -derivedDataPath "$scratch/DerivedData" -resultBundlePath "$evidence/ProducerSchemaTests.xcresult" \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO \
  -only-testing:AISDKProviderUtilsTests/JSONSchemaValidatorTests) > "$evidence/producer-schema-tests.log" 2>&1
test_status=$?
set -e
printf '{"test_exit":%s}\n' "$test_status" > "$evidence/process-status.json"
if [[ -d "$evidence/ProducerSchemaTests.xcresult" ]]; then
  xcrun xcresulttool get test-results tests --path "$evidence/ProducerSchemaTests.xcresult" --format json > "$evidence/ProducerSchemaTests.json" || true
fi
python3 - "$evidence" <<'PY_RESULTS' | tee "$evidence/summary.json"
import json,sys
from pathlib import Path
sys.path.insert(0,'Scripts/CI/IntegrationValidation')
from xcresult_to_xunit import nodes
root=Path(sys.argv[1]);status=json.loads((root/'process-status.json').read_text())
try:cases=[n for n in nodes(json.loads((root/'ProducerSchemaTests.json').read_text())) if n.get('nodeType')=='Test Case']
except (OSError,ValueError):cases=[]
expected=set(json.loads((root/'expected-tests.json').read_text()))
actual=[c.get('nodeIdentifier','').split('/')[-1].split('(')[0] for c in cases]
passed=status['test_exit']==0 and set(actual)==expected and len(actual)==len(expected) and all(c.get('result')=='Passed' for c in cases)
classification='EXECUTED_PASS' if passed else 'TEST_FAILED' if any(c.get('result')=='Failed' for c in cases) else 'BUILD_FAILED' if status['test_exit'] else 'INFRA_ERROR'
print(json.dumps({'status':classification,'scope':'exact producer shared JSON Schema validator; actual root manifest/Xcode25 focused cases; no full SDK/app/UI claim','process_status':status,'cases':cases},indent=2))
sys.exit(0 if passed else 1)
PY_RESULTS
