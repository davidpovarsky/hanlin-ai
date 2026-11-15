#!/bin/bash
# Resolve the actual app graph only; no build, test, simulator boot or signing.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
evidence="$PWD/build/skill-format-app-resolution"
mkdir -p "$evidence"
git rev-parse HEAD > "$evidence/source-commit.txt"
selected_xcode="$(python3 -c 'import glob,re; p=[p for p in glob.glob("/Applications/Xcode*.app") if re.search(r"/Xcode[_-]27(?:[._][0-9]+)*\.app$",p)]; p.sort(key=lambda x:tuple(map(int,re.findall(r"[0-9]+",x)))); print(p[-1] if p else "")')"
test -n "$selected_xcode"
export DEVELOPER_DIR="$selected_xcode/Contents/Developer"
SECONDS=0
{ xcodebuild -version; xcrun swift --version; xcrun --sdk iphonesimulator --show-sdk-version; sw_vers; uname -m; df -h .; } > "$evidence/preflight.log"
printf '%s\n' "$SECONDS" > "$evidence/preflight-duration-seconds.txt"
git archive HEAD AI_HLY.xcodeproj Packages Scripts/CI/IntegrationValidation/resolve_skill_format_app.sh > "$evidence/tested-source.tar"
python3 - "$evidence" <<'PY'
import hashlib,json,os,pathlib,subprocess,sys,time
out=pathlib.Path(sys.argv[1]); root=pathlib.Path.cwd()
lock=root/'AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
before=lock.read_bytes(); (out/'before-Package.resolved').write_bytes(before)
inputs=subprocess.check_output(['git','ls-files','AI_HLY.xcodeproj','Packages','Scripts/CI/IntegrationValidation/resolve_skill_format_app.sh'],text=True).splitlines()
hashes={p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in inputs}
(out/'input-sha256.json').write_text(json.dumps(hashes,indent=2))
command=['xcodebuild','-resolvePackageDependencies','-project','AI_HLY.xcodeproj','-scheme','AI_Hanlin','-clonedSourcePackagesDirPath',str(pathlib.Path(os.environ['RUNNER_TEMP'])/'skill-format-app-sourcepackages')]
(out/'command.json').write_text(json.dumps(command))
status={'classification':'NOT_RUN','builds':0,'tests':0}
started=time.monotonic()
try:
    with (out/'resolve.log').open('wb') as log:
        run=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=900)
    status['exitCode']=run.returncode
    if run.returncode:
        status['classification']='INFRA_ERROR'
        raise RuntimeError('Actual app dependency resolution failed; inspect resolve.log')
    raw=lock.read_bytes(); (out/'raw-Package.resolved').write_bytes(raw)
    old={p['identity']:p for p in json.loads(before)['pins']}
    new={p['identity']:p for p in json.loads(raw)['pins']}
    yams=new.get('yams')
    assert yams and yams['location']=='https://github.com/jpsim/Yams.git'
    assert yams['state']=={'version':'6.2.2','revision':'a27b21e0c81c5bf42049b897a62aaf387e80f279'}
    changed={k:{'before':old[k],'after':new.get(k)} for k in old if old[k]!=new.get(k)}
    status.update(classification='RESOLVED_ONLY_PASS',rawLockSHA256=hashlib.sha256(raw).hexdigest(),addedPins=sorted(set(new)-set(old)),changedPins=changed,unrelatedPinReviewRequired=bool(changed))
    # Source inputs other than the resolver-owned app lock must remain exact.
    for p,digest in hashes.items():
        if root/p!=lock: assert hashlib.sha256((root/p).read_bytes()).hexdigest()==digest,p
except subprocess.TimeoutExpired:
    status['classification']='INFRA_ERROR';status['reason']='Bounded 900-second app resolver timeout';raise
except Exception as error:
    if status['classification']=='NOT_RUN':status['classification']='INFRA_ERROR'
    status['reason']=str(error);raise
finally:
    (out/'resolve-duration-seconds.txt').write_text(str(round(time.monotonic()-started)))
    if lock.exists():(out/'raw-Package.resolved').write_bytes(lock.read_bytes())
    (out/'summary.json').write_text(json.dumps(status,indent=2))
print(json.dumps(status))
PY
