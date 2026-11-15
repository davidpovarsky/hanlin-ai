#!/bin/bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
evidence="$root/build/agent-sdk-validation-evidence"
mkdir -p "$evidence"
started=$SECONDS
finish_host_schema() {
  local rc="$?"
  if [[ ! -s "$evidence/summary.json" || ! -d "$evidence/HostSchemaTests.xcresult" || ! -d "$evidence/HostSchemaIOS.xcresult" ]]; then
    if [[ "$rc" == 0 ]]; then rc=1; fi
  fi
  printf '{"exit":%s,"total_seconds":%s}\n' "$rc" "$((SECONDS-started))" > "$evidence/process-exit.json"
  for log in host-schema-tests ios-build; do
    if [[ -f "$evidence/$log.log" ]]; then grep -E 'error:|recorded an issue' "$evidence/$log.log" | head -n 20 >&2 || true; fi
  done
  trap - EXIT
  exit "$rc"
}
trap finish_host_schema EXIT
git rev-parse HEAD > "$evidence/tested-source-commit.txt"
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/hanlin-host-schema.XXXXXXXX")"
python3 - "$scratch" <<'PY_DISK'
import shutil,sys
assert shutil.disk_usage(sys.argv[1]).free >= 8*1024**3
PY_DISK
git archive HEAD Packages/HanlinAgentSDK Packages/HanlinPlatform > "$evidence/tested-source.tar"
tar -xf "$evidence/tested-source.tar" -C "$scratch"
python3 - "$scratch" "$evidence" <<'PY_SOURCE'
import hashlib,json,os,re,subprocess,sys
from pathlib import Path
scratch,evidence=map(Path,sys.argv[1:])
paths=subprocess.check_output(['git','ls-files','Packages/HanlinAgentSDK','Packages/HanlinPlatform'],text=True).splitlines()
(evidence/'tested-source-sha256.json').write_text(json.dumps({p:hashlib.sha256((scratch/p).read_bytes()).hexdigest() for p in paths},indent=2))
expected=[]
for rel,suite in [('HanlinAgentCoreTests/HostSchemaValidationTests.swift','HostSchemaValidationTests'),('HanlinAgentCoreTests/AgentSessionTests.swift','AgentSessionTests'),('HanlinHostContractsTests/ContextTests.swift','ContextTests')]:
    source=(scratch/'Packages/HanlinAgentSDK/Tests'/rel).read_text();pending=False;current=None
    for line in source.splitlines():
        decl=re.search(r'^(?:@Suite\s+)?(?:private\s+)?(?:struct|actor|class)\s+(\w+)',line)
        if decl:current=decl[1];pending=False
        if current!=suite:continue
        if re.search(r'^\s*(?:@MainActor\s+)?@Test\b',line):pending=True
        method=re.search(r'\bfunc\s+(\w+)\s*\(',line)
        if pending and method:expected.append(suite+'/'+method[1]+'()');pending=False
assert len([x for x in expected if x.startswith('HostSchemaValidationTests/')])==9
assert len(expected)==len(set(expected)) and len(expected)>=33
if os.environ.get('HANLIN_SDK_ASSOCIATION_ONLY')=='1':
    expected=[x for x in expected if not x.startswith('HostSchemaValidationTests/') or x=='HostSchemaValidationTests/dispatcherRetainsOriginalBytesAndNeverReplaysAChangedRoundedValue()']
(evidence/'expected-tests.json').write_text(json.dumps(expected,indent=2))
PY_SOURCE
selected_xcode="$(python3 -c 'import glob,re; p=[p for p in glob.glob("/Applications/Xcode*.app") if re.search(r"/Xcode[_-]27(?:[._][0-9]+)*\.app$",p)]; p.sort(key=lambda x:tuple(map(int,re.findall(r"[0-9]+",x)))); print(p[-1] if p else "")')"
test -n "$selected_xcode"
export DEVELOPER_DIR="$selected_xcode/Contents/Developer"
{ xcodebuild -version; xcrun swift --version; xcrun --sdk macosx --show-sdk-version; xcrun --sdk iphonesimulator --show-sdk-version; uname -m; sw_vers; } > "$evidence/toolchain.txt"
sdk="$scratch/Packages/HanlinAgentSDK"
xcrun swift package --package-path "$sdk" resolve > "$evidence/resolve.log" 2>&1
python3 - "$scratch" "$evidence" <<'PY_DEPS'
import hashlib,json,subprocess,sys
from pathlib import Path
scratch,evidence=map(Path,sys.argv[1:]);records=[]
for p in scratch.rglob('Package.resolved'):
    if any(s in ['checkouts','repositories'] for s in p.relative_to(scratch).parts):continue
    raw=p.read_bytes();name='raw-'+str(len(records))+'-Package.resolved';(evidence/name).write_bytes(raw)
    records.append({'path':str(p.relative_to(scratch)),'raw_file':name,'sha256':hashlib.sha256(raw).hexdigest(),'resolved':json.loads(raw)})
(evidence/'resolution.json').write_text(json.dumps(records,indent=2))
pins=json.loads((scratch/'Packages/HanlinAgentSDK/Package.resolved').read_text())['pins']
assert next(p for p in pins if p['identity']=='swift-json')['state']['revision']=='f2a0d12da7028edfbcb0cb307f19a921a3a12d03'
assert next(p for p in pins if p['identity']=='swift-ai-sdk')['state']['revision']=='e7bf34111e603ca977becd007dd4e5bb109af857'
checkout=scratch/'Packages/HanlinAgentSDK/.build/checkouts/Swift-JSON'
if not checkout.exists():checkout=scratch/'Packages/HanlinAgentSDK/.build/checkouts/swift-json'
sha=subprocess.check_output(['git','-C',str(checkout),'rev-parse','HEAD'],text=True).strip();assert sha=='f2a0d12da7028edfbcb0cb307f19a921a3a12d03'
(evidence/'validator-source.tar').write_bytes(subprocess.check_output(['git','-C',str(checkout),'archive','HEAD']))
(evidence/'validator-source-commit.txt').write_text(sha+'\n')
PY_DEPS
(cd "$sdk" && xcodebuild -list -json) > "$evidence/schemes.json"
scheme="$(python3 - "$evidence/schemes.json" <<'PY_SCHEME'
import json,sys
d=json.load(open(sys.argv[1]));names=d.get('workspace',{}).get('schemes',[])+d.get('project',{}).get('schemes',[])
print(next(x for x in ['HanlinAgentSDK-Package','HanlinAgentSDK'] if x in names))
PY_SCHEME
)"
schema_tests=(-only-testing:HanlinAgentCoreTests/HostSchemaValidationTests)
if [[ "${HANLIN_SDK_ASSOCIATION_ONLY:-0}" == 1 ]]; then
  schema_tests=('-only-testing:HanlinAgentCoreTests/HostSchemaValidationTests/dispatcherRetainsOriginalBytesAndNeverReplaysAChangedRoundedValue()')
fi
set +e
(cd "$sdk" && xcodebuild test -scheme "$scheme" -destination 'platform=macOS' \
  -derivedDataPath "$scratch/DerivedData" -resultBundlePath "$evidence/HostSchemaTests.xcresult" \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO \
  "${schema_tests[@]}" \
  -only-testing:HanlinAgentCoreTests/AgentSessionTests \
  -only-testing:HanlinHostContractsTests/ContextTests) > "$evidence/host-schema-tests.log" 2>&1
test_status=$?
(cd "$sdk" && xcodebuild build -scheme HanlinAgentCore -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$scratch/IOSDerivedData" -resultBundlePath "$evidence/HostSchemaIOS.xcresult" \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO) > "$evidence/ios-build.log" 2>&1
ios_status=$?
set -e
printf '{"test_exit":%s,"ios_build_exit":%s}\n' "$test_status" "$ios_status" > "$evidence/process-status.json"
if [[ -d "$evidence/HostSchemaTests.xcresult" ]]; then
  xcrun xcresulttool get test-results tests --path "$evidence/HostSchemaTests.xcresult" --format json > "$evidence/HostSchemaTests.json" || true
fi
python3 - "$evidence" <<'PY_RESULTS' | tee "$evidence/summary.json"
import json,sys
from pathlib import Path
sys.path.insert(0,'Scripts/CI/IntegrationValidation')
from xcresult_to_xunit import nodes
root=Path(sys.argv[1]);status=json.loads((root/'process-status.json').read_text())
try:cases=[n for n in nodes(json.loads((root/'HostSchemaTests.json').read_text())) if n.get('nodeType')=='Test Case']
except (OSError,ValueError):cases=[]
expected=set(json.loads((root/'expected-tests.json').read_text()))
actual=['/'.join(c.get('nodeIdentifier','').split('/')[-2:]) for c in cases]
passed=status['test_exit']==0 and status['ios_build_exit']==0 and set(actual)==expected and len(actual)==len(expected) and all(c.get('result')=='Passed' for c in cases)
classification='EXECUTED_PASS' if passed else 'TEST_FAILED' if any(c.get('result')=='Failed' for c in cases) else 'BUILD_FAILED' if status['test_exit'] or status['ios_build_exit'] else 'INFRA_ERROR'
print(json.dumps({'status':classification,'scope':'exact SDK Host schema/raw boundary, affected Session/Context cases and iOS package compile; actual app NOT_RUN','process_status':status,'cases':cases},indent=2))
sys.exit(0 if passed else 1)
PY_RESULTS
