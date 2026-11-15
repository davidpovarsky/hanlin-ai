#!/bin/bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
evidence="$root/build/agent-sdk-validation-evidence"
mkdir -p "$evidence"
started=$SECONDS
finish_skill_format() {
  local rc="$?"
  if [[ ! -s "$evidence/summary.json" ]]; then
    if [[ "$rc" == 0 ]]; then rc=1; fi
  fi
  printf '{"exit":%s,"total_seconds":%s}\n' "$rc" "$((SECONDS-started))" > "$evidence/process-exit.json"
  trap - EXIT
  exit "$rc"
}
trap finish_skill_format EXIT
git rev-parse HEAD > "$evidence/tested-source-commit.txt"
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/hanlin-skill-format.XXXXXXXX")"
git archive HEAD Packages/HanlinSkillFormat > "$evidence/tested-source.tar"
tar -xf "$evidence/tested-source.tar" -C "$scratch"
python3 - "$scratch" "$evidence" <<'PY_SOURCE'
import hashlib,json,re,shutil,subprocess,sys
from pathlib import Path
scratch,evidence=map(Path,sys.argv[1:])
assert shutil.disk_usage(scratch).free >= 4*1024**3
paths=subprocess.check_output(['git','ls-files','Packages/HanlinSkillFormat'],text=True).splitlines()
records={}
for p in paths:
    raw=(scratch/p).read_bytes()
    assert raw==subprocess.check_output(['git','show','HEAD:'+p]),p
    records[p]=hashlib.sha256(raw).hexdigest()
(evidence/'tested-source-sha256.json').write_text(json.dumps(records,indent=2))
source=(scratch/'Packages/HanlinSkillFormat/Tests/HanlinSkillFormatTests/SkillDocumentTests.swift').read_text()
expected=re.findall(r'^\s+func (\w+)\(',source,re.M)
expected=[x for x in expected if not x.startswith(('document','fixture','expectFailure'))]
assert len(expected)>=20 and len(expected)==len(set(expected))
(evidence/'expected-tests.json').write_text(json.dumps(expected,indent=2))
workflow=['.github/workflows/build-ios26-unsigned-ipa.yml','Scripts/CI/IntegrationValidation/run_skill_format.sh','Scripts/CI/IntegrationValidation/xcresult_to_xunit.py']
(evidence/'workflow-sha256.json').write_text(json.dumps({p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in workflow},indent=2))
PY_SOURCE
selected_xcode="$(python3 -c 'import glob,re; p=[p for p in glob.glob("/Applications/Xcode*.app") if re.search(r"/Xcode[_-]27(?:[._][0-9]+)*\.app$",p)]; p.sort(key=lambda x:tuple(map(int,re.findall(r"[0-9]+",x)))); print(p[-1] if p else "")')"
test -n "$selected_xcode"
export DEVELOPER_DIR="$selected_xcode/Contents/Developer"
{ xcodebuild -version; xcrun swift --version; xcrun --sdk macosx --show-sdk-version; xcrun --sdk iphonesimulator --show-sdk-version; uname -m; sw_vers; } > "$evidence/toolchain.txt"
xcrun simctl list devices available -j > "$evidence/devices.json"
xcrun simctl list runtimes -j > "$evidence/runtimes.json"
sdk="$scratch/Packages/HanlinSkillFormat"
xcrun swift package --package-path "$sdk" resolve > "$evidence/resolve.log" 2>&1
cp "$sdk/Package.resolved" "$evidence/raw-Package.resolved"
python3 - "$sdk" "$evidence" <<'PY_DEPS'
import hashlib,json,subprocess,sys
from pathlib import Path
sdk,evidence=map(Path,sys.argv[1:]);raw=(sdk/'Package.resolved').read_bytes();pins=json.loads(raw)['pins']
assert len(pins)==1 and pins[0]['identity']=='yams' and pins[0]['state']['revision']=='a27b21e0c81c5bf42049b897a62aaf387e80f279'
checkout=next(p for p in (sdk/'.build/checkouts').iterdir() if p.name.lower()=='yams')
revision=subprocess.check_output(['git','-C',str(checkout),'rev-parse','HEAD'],text=True).strip()
assert revision==pins[0]['state']['revision']
(evidence/'upstream-source.tar').write_bytes(subprocess.check_output(['git','-C',str(checkout),'archive','HEAD']))
(evidence/'resolution.json').write_text(json.dumps({'sha256':hashlib.sha256(raw).hexdigest(),'resolved':json.loads(raw),'checkout_commit':revision},indent=2))
PY_DEPS
(cd "$sdk" && xcodebuild -list -json) > "$evidence/schemes.json"
scheme="$(python3 - "$evidence/schemes.json" <<'PY_SCHEME'
import json,sys
d=json.load(open(sys.argv[1]));names=d.get('workspace',{}).get('schemes',[])+d.get('project',{}).get('schemes',[])
print(next(x for x in ['HanlinSkillFormat-Package','HanlinSkillFormat'] if x in names))
PY_SCHEME
)"
printf '[]\n' > "$evidence/process-status.json"
for platform in macOS iOS26 iOS27; do
  destination='platform=macOS'
  if [[ "$platform" != macOS ]]; then
    set +e
    destination="$(python3 - "$evidence/devices.json" "${platform#iOS}" <<'PY_DEVICE'
import json,sys
data=json.load(open(sys.argv[1]));version=sys.argv[2]
candidates=[d for runtime,devices in data['devices'].items() if runtime.startswith('com.apple.CoreSimulator.SimRuntime.iOS-'+version+'-') for d in devices if d.get('isAvailable') and d['name'].startswith('iPhone')]
if not candidates:raise SystemExit('Required iOS '+version+' simulator runtime/device is unavailable')
print('platform=iOS Simulator,id='+sorted(candidates,key=lambda d:d['name'])[0]['udid'])
PY_DEVICE
)"
    destination_status=$?
    set -e
    if [[ "$destination_status" != 0 ]]; then
      python3 - "$evidence/process-status.json" "$platform" <<'PY_UNAVAILABLE'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]);data=json.loads(p.read_text());data.append({'platform':sys.argv[2],'exit':None,'destination':None,'blocked':'Required installed simulator runtime/device unavailable'});p.write_text(json.dumps(data,indent=2))
PY_UNAVAILABLE
      continue
    fi
  fi
  set +e
  (cd "$sdk" && xcodebuild test -scheme "$scheme" -destination "$destination" -destination-timeout 90 \
    -derivedDataPath "$scratch/DerivedData-$platform" -resultBundlePath "$evidence/$platform.xcresult" \
    -only-testing:HanlinSkillFormatTests -skipPackagePluginValidation -skipMacroValidation \
    CODE_SIGNING_ALLOWED=NO SWIFT_VERSION=6) > "$evidence/$platform.log" 2>&1
  status=$?
  set -e
  python3 - "$evidence/process-status.json" "$platform" "$status" "$destination" <<'PY_STATUS'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]);data=json.loads(p.read_text());data.append({'platform':sys.argv[2],'exit':int(sys.argv[3]),'destination':sys.argv[4]});p.write_text(json.dumps(data,indent=2))
PY_STATUS
  if [[ -d "$evidence/$platform.xcresult" ]]; then
    xcrun xcresulttool get test-results tests --path "$evidence/$platform.xcresult" --format json > "$evidence/$platform-tests.json" || true
  fi
done
python3 - "$evidence" <<'PY_RESULTS' | tee "$evidence/summary.json"
import json,re,sys
from pathlib import Path
sys.path.insert(0,'Scripts/CI/IntegrationValidation')
from xcresult_to_xunit import nodes
root=Path(sys.argv[1]);statuses=json.loads((root/'process-status.json').read_text());expected=set(json.loads((root/'expected-tests.json').read_text()))
results=[]
for status in statuses:
    try:cases=[n for n in nodes(json.loads((root/(status['platform']+'-tests.json')).read_text())) if n.get('nodeType')=='Test Case']
    except (OSError,ValueError):cases=[]
    actual=[]
    for case in cases:
        match=re.search(r'(\w+)\(',case.get('nodeIdentifier','').split('/')[-1])
        actual.append(match[1] if match else '')
    passed=status['exit']==0 and set(actual)==expected and len(actual)==len(expected) and all(c.get('result')=='Passed' for c in cases)
    results.append(dict(status,classification='EXECUTED_PASS' if passed else 'BLOCKED' if status.get('blocked') else 'FAILED',cases=cases))
passed=len(results)==3 and all(x['classification']=='EXECUTED_PASS' for x in results)
print(json.dumps({'status':'EXECUTED_PASS' if passed else 'FAILED','scope':'Original Yams Skill format package only; actual app, ZIP/Store/UI tests NOT_RUN','platforms':results},indent=2))
sys.exit(0 if passed else 1)
PY_RESULTS
