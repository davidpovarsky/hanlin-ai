#!/bin/bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
source_sha=08b5d6f31153063c31be321fbd35c7301f302fc1
evidence="$root/build/agent-sdk-validation-evidence"
mkdir -p "$evidence"
git rev-parse HEAD > "$evidence/workflow-commit.txt"
printf '%s\n' "$source_sha" > "$evidence/tested-source-commit.txt"
if ! git cat-file -e "$source_sha^{commit}" 2>/dev/null; then git fetch --no-tags --depth=1 origin "$source_sha"; fi
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/hanlin-agent-sdk.XXXXXXXX")"
git archive "$source_sha" Packages/HanlinAgentSDK Packages/HanlinPlatform docs/agent-sdk > "$evidence/tested-source.tar"
tar -xf "$evidence/tested-source.tar" -C "$scratch"
selected_xcode="$(python3 -c 'import glob,re; p=[p for p in glob.glob("/Applications/Xcode*.app") if re.search(r"/Xcode[_-]27(?:[._][0-9]+)*\.app$",p)]; p.sort(key=lambda x:tuple(map(int,re.findall(r"[0-9]+",x)))); print(p[-1] if p else "")')"
test -n "$selected_xcode"
export DEVELOPER_DIR="$selected_xcode/Contents/Developer"
xcodebuild -version > "$evidence/xcode.txt"
xcrun swift --version > "$evidence/swift.txt"
xcrun --sdk macosx --show-sdk-version > "$evidence/macos-sdk.txt"
xcrun --sdk iphonesimulator --show-sdk-version > "$evidence/ios-sdk.txt"
sw_vers > "$evidence/os.txt"
python3 - "$source_sha" "$scratch" <<'PY' > "$evidence/tested-source-sha256.json"
import hashlib,json,subprocess,sys
from pathlib import Path
root=Path(sys.argv[2]);records={}
for p in sorted(root.rglob('*')):
    if not p.is_file():continue
    relative=p.relative_to(root).as_posix();raw=p.read_bytes()
    assert raw==subprocess.check_output(['git','show',f'{sys.argv[1]}:{relative}']),relative
    records[relative]=hashlib.sha256(raw).hexdigest()
print(json.dumps(records,indent=2))
PY
python3 - <<'PY' > "$evidence/workflow-sha256.json"
import hashlib,json,subprocess
from pathlib import Path
paths=['.github/workflows/build-ios26-unsigned-ipa.yml','Scripts/CI/IntegrationValidation/run_agent_sdk.sh','Scripts/CI/IntegrationValidation/verify_agent_sdk.py']
for path in paths:assert Path(path).read_bytes()==subprocess.check_output(['git','show',f'HEAD:{path}'])
print(json.dumps({p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in paths},indent=2))
PY
sdk="$scratch/Packages/HanlinAgentSDK"
core="$scratch/Packages/HanlinPlatform"
retain_locks() {
  python3 - "$scratch" "$evidence" <<'PY'
import hashlib,json,sys
from pathlib import Path
root,evidence=map(Path,sys.argv[1:]);records=[];folder=evidence/'raw-locks';folder.mkdir(exist_ok=True)
for p in root.rglob('Package.resolved'):
    if any(s in ['checkouts','.build','DerivedData'] for s in p.relative_to(root).parts):continue
    b=p.read_bytes();data=json.loads(b);pins=[x for x in data['pins'] if x['identity']=='swift-ai-sdk']
    assert len(pins)==1 and pins[0]['state']['revision']=='43ebcfaae67ca2c47ea1ce940d66b581e60ca7f6',str(p)
    dest=folder/f'{len(records):02d}-Package.resolved';dest.write_bytes(b)
    records.append({'source_path':str(p),'raw_file':str(dest.relative_to(evidence)),'sha256':hashlib.sha256(b).hexdigest(),'resolved':data})
(evidence/'resolution.json').write_text(json.dumps(records,indent=2))
PY
}
finish() {
  local code="$?"
  if [[ ! -f "$evidence/process-status.json" ]]; then
    printf '{"preparation_exit":%s,"sdk_test_exit":null,"core_test_exit":null,"ios_build_exit":null}\n' "$code" > "$evidence/process-status.json"
  fi
  retain_locks
  python3 Scripts/CI/IntegrationValidation/verify_agent_sdk.py "$evidence" > "$evidence/summary.json" || true
}
trap finish EXIT
python3 - "$scratch" <<'PY' > "$evidence/expected-tests.json"
import json,re,sys
from pathlib import Path
root=Path(sys.argv[1]);wanted={'AgentSessionTests','ContextTests','StoreTests','HanlinInjectedProviderTests','HanlinAISDKProviderFactoryTests','HanlinAISDKAgentEngineTests'};result={}
paths=list((root/'Packages/HanlinAgentSDK/Tests').rglob('*.swift'))+[root/'Packages/HanlinPlatform/Tests/HanlinChatCoreTests/HanlinAISDKTests.swift',root/'Packages/HanlinPlatform/Tests/HanlinChatCoreTests/HanlinInjectedProviderTests.swift']
for path in paths:
    suite=None;pending=False
    for line in path.read_text().splitlines():
        decl=re.search(r'^(?:@Suite(?:\([^\n]*\))?\s+)?(?:private\s+)?(?:struct|actor|class|enum)\s+(\w+)',line)
        if decl:suite=decl[1] if decl[1] in wanted else None;pending=False
        if re.search(r'^\s*(?:@MainActor\s+)?@Test\b',line):pending=True
        method=re.search(r'\bfunc\s+(\w+)\s*\(',line)
        if pending and method:
            if suite:result.setdefault(suite,[]).append(method[1])
            pending=False
assert set(result)==wanted and all(result.values()),result
print(json.dumps(result,indent=2))
PY
xcrun swift package --package-path "$sdk" resolve > "$evidence/sdk-resolve.log" 2>&1
xcrun swift package --package-path "$core" resolve > "$evidence/core-resolve.log" 2>&1
(cd "$sdk" && xcodebuild -list -json) > "$evidence/sdk-schemes.json"
(cd "$core" && xcodebuild -list -json) > "$evidence/core-schemes.json"
schemes="$(python3 - "$evidence/sdk-schemes.json" "$evidence/core-schemes.json" <<'PY'
import json,sys
for path,candidates in [(sys.argv[1],['HanlinAgentSDK-Package','HanlinAgentSDK']), (sys.argv[2],['HanlinPlatform-Package','HanlinPlatform'])]:
    d=json.load(open(path));names=d.get('workspace',{}).get('schemes',[])+d.get('project',{}).get('schemes',[])
    print(next(x for x in candidates if x in names))
PY
)"
sdk_scheme="$(printf '%s\n' "$schemes" | sed -n '1p')"
core_scheme="$(printf '%s\n' "$schemes" | sed -n '2p')"
set +e
(cd "$sdk" && xcodebuild test -scheme "$sdk_scheme" -destination 'platform=macOS' \
  -derivedDataPath "$scratch/SDKDerivedData" -resultBundlePath "$evidence/SDKTests.xcresult" \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO \
  -only-testing:HanlinAgentCoreTests/AgentSessionTests \
  -only-testing:HanlinHostContractsTests/ContextTests \
  -only-testing:HanlinPersistenceAdaptersTests/StoreTests) > "$evidence/sdk-tests.log" 2>&1
sdk_status=$?
(cd "$core" && xcodebuild test -scheme "$core_scheme" -destination 'platform=macOS' \
  -derivedDataPath "$scratch/CoreDerivedData" -resultBundlePath "$evidence/CoreTests.xcresult" \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO \
  -only-testing:HanlinChatCoreTests/HanlinInjectedProviderTests \
  -only-testing:HanlinChatCoreTests/HanlinAISDKProviderFactoryTests \
  -only-testing:HanlinChatCoreTests/HanlinAISDKAgentEngineTests) > "$evidence/core-tests.log" 2>&1
core_status=$?
(cd "$sdk" && xcodebuild build -scheme HanlinAgentCore -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$scratch/IOSDerivedData" -resultBundlePath "$evidence/IOSBuild.xcresult" \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO) > "$evidence/ios-build.log" 2>&1
ios_status=$?
set -e
printf '{"sdk_test_exit":%s,"core_test_exit":%s,"ios_build_exit":%s}\n' "$sdk_status" "$core_status" "$ios_status" > "$evidence/process-status.json"
for item in SDKTests CoreTests; do
  if [[ -d "$evidence/$item.xcresult" ]]; then
    xcrun xcresulttool get test-results tests --path "$evidence/$item.xcresult" --format json > "$evidence/$item.json" || true
  fi
done
retain_locks
python3 Scripts/CI/IntegrationValidation/verify_agent_sdk.py "$evidence" | tee "$evidence/summary.json"
