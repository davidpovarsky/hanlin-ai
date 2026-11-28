#!/bin/bash
# Resolve the existing six dependent package graphs on Apple, without builds/tests.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
producer_sha="$(python3 Scripts/CI/IntegrationValidation/swift_ai_sdk_pin.py "$root")"
evidence="$root/build/agent-sdk-lock-evidence"
mkdir -p "$evidence"
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/hanlin-sdk-locks.XXXXXXXX")"
# Honor the caller's validated Apple toolchain, including /Applications/Xcode.app.
# Discovery is a fallback only; never mutate the machine's global xcode-select.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  selected_xcode="$(python3 -c 'import glob,re; p=[p for p in glob.glob("/Applications/Xcode*.app") if re.search(r"/Xcode[_-]27(?:[._][0-9]+)*\.app$",p)]; p.sort(key=lambda x:tuple(map(int,re.findall(r"[0-9]+",x)))); print(p[-1] if p else "")')"
  if [[ -n "$selected_xcode" ]]; then
    export DEVELOPER_DIR="$selected_xcode/Contents/Developer"
  else
    export DEVELOPER_DIR="$(xcode-select -p)"
  fi
fi
test -d "$DEVELOPER_DIR"
xcodebuild -version > "$evidence/xcode.txt"
python3 - "$evidence/xcode.txt" <<'PY'
import re,sys
from pathlib import Path
actual=Path(sys.argv[1]).read_text()
assert re.fullmatch(r'Xcode 27(?:\.[0-9]+)*\nBuild version [A-Za-z0-9]+\n?',actual),(actual,'requires actual Xcode 27 toolchain')
PY
xcrun swift --version > "$evidence/swift.txt"
git rev-parse HEAD > "$evidence/source-commit.txt"
packages=(HanlinPlatform HanlinAgentSDK HanlinParityMiniApp HanlinTextStudioMiniApp HanlinSefariaMiniApp HanlinWikipediaMiniApp)
paths=()
for package in "${packages[@]}"; do paths+=("Packages/$package"); done
git archive HEAD "${paths[@]}" | tar -xf - -C "$scratch"
python3 - "$scratch" <<'PY' > "$evidence/input-sha256.json"
import hashlib,json,subprocess,sys
from pathlib import Path
root=Path(sys.argv[1]);records={}
for path in sorted(root.rglob('*')):
    if not path.is_file():continue
    rel=path.relative_to(root).as_posix();raw=path.read_bytes()
    assert raw==subprocess.check_output(['git','show','HEAD:'+rel]),rel
    records[rel]=hashlib.sha256(raw).hexdigest()
for rel in ['.github/workflows/build-ios26-unsigned-ipa.yml','Scripts/CI/IntegrationValidation/resolve_agent_sdk_locks.sh','Scripts/CI/IntegrationValidation/swift_ai_sdk_pin.py','AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved']:
    raw=Path(rel).read_bytes();assert raw==subprocess.check_output(['git','show','HEAD:'+rel]),rel
    records[rel]=hashlib.sha256(raw).hexdigest()
print(json.dumps(records,indent=2))
PY
for package in "${packages[@]}"; do
  xcrun swift package --package-path "$scratch/Packages/$package" resolve > "$evidence/$package-resolve.log" 2>&1
done
python3 - "$scratch" "$evidence" "$producer_sha" <<'PY'
import hashlib,json,subprocess,sys
from pathlib import Path
root,evidence=map(Path,sys.argv[1:3]);producer_sha=sys.argv[3];records=[]
names=['HanlinPlatform','HanlinAgentSDK','HanlinParityMiniApp','HanlinTextStudioMiniApp','HanlinSefariaMiniApp','HanlinWikipediaMiniApp']
for name in names:
    rel=f'Packages/{name}/Package.resolved';dest=evidence/rel
    dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes((root/rel).read_bytes())
platform={p['identity']:p for p in json.loads((root/'Packages/HanlinPlatform/Package.resolved').read_text())['pins']}
# These two dependencies are already required by the original Platform manifest
# and its OTel SDK. Bind newly resolved pins to the accepted canonical app graph.
canonical_raw=Path('AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_bytes()
canonical={p['identity']:p for p in json.loads(canonical_raw)['pins']}
cache_dependencies={
    'opentelemetry-swift-core':('https://github.com/open-telemetry/opentelemetry-swift-core.git','2.6.0'),
    'swift-atomics':('https://github.com/apple/swift-atomics.git','1.3.1'),
}
approved_cache_pins={}
for identity,(location,version) in cache_dependencies.items():
    pin=canonical[identity]
    assert pin['kind']=='remoteSourceControl' and pin['location']==location,(identity,'canonical cache dependency origin mismatch')
    assert pin['state'].get('version')==version,(identity,'canonical cache dependency version mismatch')
    revision=pin['state'].get('revision','')
    assert len(revision)==40 and all(c in '0123456789abcdef' for c in revision),(identity,'canonical cache dependency revision missing')
    approved_cache_pins[identity]=pin
(evidence/'canonical-app-Package.resolved').write_bytes(canonical_raw)
for rel,digest in json.loads((evidence/'input-sha256.json').read_text()).items():
    if rel.startswith('Packages/') and rel.endswith('/Package.resolved'):continue
    path=root/rel if rel.startswith('Packages/') else Path(rel)
    assert hashlib.sha256(path.read_bytes()).hexdigest()==digest,rel
for name in names:
    rel=f'Packages/{name}/Package.resolved';raw=(root/rel).read_bytes();new=json.loads(raw)
    old=json.loads(subprocess.check_output(['git','show','HEAD:'+rel]))
    before={p['identity']:p for p in old['pins']};after={p['identity']:p for p in new['pins']}
    assert set(after)==set(platform),(name,'graph differs from existing Platform dependencies')
    assert set(before)<=set(after),(name,'dependency removed')
    added=set(after)-set(before)
    allowed_additions=set(approved_cache_pins) | ({'swiftyjson'} if name.endswith('MiniApp') else set())
    assert added<=allowed_additions,(name,'unexpected identity addition',added)
    assert set(approved_cache_pins)<=set(after),(name,'required cache dependency missing')
    for identity,expected in approved_cache_pins.items():
        assert after[identity]==expected,(name,'cache dependency differs from canonical app lock',identity)
    for identity,pin in after.items():
        if identity=='swift-ai-sdk':
            assert pin['state']['revision']==producer_sha
            assert pin['kind']==before[identity]['kind'] and pin['location']==before[identity]['location']
        elif identity in before:assert pin==before[identity],(name,'unrelated pin changed',identity)
        elif identity in approved_cache_pins:
            assert pin==approved_cache_pins[identity],(name,'unapproved cache dependency pin',identity)
        else:assert pin==platform[identity] and pin['state']['version']=='5.0.1',(name,'inherited existing SwiftyJSON pin mismatch')
    dest=evidence/rel;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(raw)
    records.append({'source_path':rel,'raw_file':rel,'sha256':hashlib.sha256(raw).hexdigest(),'resolved':new,'previously_unlocked_existing_dependencies':sorted(added)})
(evidence/'resolution.json').write_text(json.dumps(records,indent=2))
(evidence/'summary.json').write_text(json.dumps({'status':'RESOLUTION_PASS','graphs':len(records),'builds':0,'tests':0,'producer':producer_sha,'cache_dependency_pins':approved_cache_pins,'canonical_app_lock_sha256':hashlib.sha256(canonical_raw).hexdigest(),'unrelated_pins_changed':False},indent=2))
PY
