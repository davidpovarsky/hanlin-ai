#!/bin/bash
# Resolve the existing six dependent package graphs on Apple, without builds/tests.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
evidence="$root/build/agent-sdk-lock-evidence"
mkdir -p "$evidence"
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/hanlin-sdk-locks.XXXXXXXX")"
selected_xcode="$(python3 -c 'import glob,re; p=[p for p in glob.glob("/Applications/Xcode*.app") if re.search(r"/Xcode[_-]27(?:[._][0-9]+)*\.app$",p)]; p.sort(key=lambda x:tuple(map(int,re.findall(r"[0-9]+",x)))); print(p[-1] if p else "")')"
test -n "$selected_xcode"
export DEVELOPER_DIR="$selected_xcode/Contents/Developer"
xcodebuild -version > "$evidence/xcode.txt"
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
for rel in ['.github/workflows/build-ios26-unsigned-ipa.yml','Scripts/CI/IntegrationValidation/resolve_agent_sdk_locks.sh']:
    raw=Path(rel).read_bytes();assert raw==subprocess.check_output(['git','show','HEAD:'+rel]),rel
    records[rel]=hashlib.sha256(raw).hexdigest()
print(json.dumps(records,indent=2))
PY
for package in "${packages[@]}"; do
  xcrun swift package --package-path "$scratch/Packages/$package" resolve > "$evidence/$package-resolve.log" 2>&1
done
python3 - "$scratch" "$evidence" <<'PY'
import hashlib,json,subprocess,sys
from pathlib import Path
root,evidence=map(Path,sys.argv[1:]);records=[]
for rel,digest in json.loads((evidence/'input-sha256.json').read_text()).items():
    if rel.endswith('/Package.resolved'):continue
    path=root/rel if rel.startswith('Packages/') else Path(rel)
    assert hashlib.sha256(path.read_bytes()).hexdigest()==digest,rel
for name in ['HanlinPlatform','HanlinAgentSDK','HanlinParityMiniApp','HanlinTextStudioMiniApp','HanlinSefariaMiniApp','HanlinWikipediaMiniApp']:
    rel=f'Packages/{name}/Package.resolved';raw=(root/rel).read_bytes();new=json.loads(raw)
    old=json.loads(subprocess.check_output(['git','show','HEAD:'+rel]))
    before={p['identity']:p for p in old['pins']};after={p['identity']:p for p in new['pins']}
    assert set(before)==set(after),(name,'dependency identities changed')
    for identity,pin in after.items():
        if identity=='swift-ai-sdk':
            assert pin['state']['revision']=='e7bf34111e603ca977becd007dd4e5bb109af857'
            assert pin['kind']==before[identity]['kind'] and pin['location']==before[identity]['location']
        else:assert pin==before[identity],(name,'unrelated pin changed',identity)
    dest=evidence/rel;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(raw)
    records.append({'source_path':rel,'raw_file':rel,'sha256':hashlib.sha256(raw).hexdigest(),'resolved':new})
(evidence/'resolution.json').write_text(json.dumps(records,indent=2))
(evidence/'summary.json').write_text(json.dumps({'status':'RESOLUTION_PASS','graphs':len(records),'builds':0,'tests':0,'producer':'e7bf34111e603ca977becd007dd4e5bb109af857','unrelated_pins_changed':False},indent=2))
PY
