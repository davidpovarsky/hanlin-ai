#!/usr/bin/env python3
"""Execute only the existing store lifecycle method with real Apple SwiftCrypto.

Production declarations are copied unchanged except CryptoKit -> Crypto imports
and conditional OSLog statements. No store branch, hash, file operation, decoder,
grant policy, or lifecycle test assertion is replaced. This is a Linux projection,
not unmodified Apple-module or application acceptance.
"""
from pathlib import Path
import argparse,difflib,hashlib,json,os,re,shutil,subprocess,tarfile,time
ROOT=Path(__file__).resolve().parents[4]
parser=argparse.ArgumentParser()
parser.add_argument("--output",type=Path,required=True)
parser.add_argument("--build-root",type=Path,required=True)
parser.add_argument("--expect",choices=["red","green"],required=True)
args=parser.parse_args()
out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
work=args.build_root.resolve();work.mkdir(parents=True,exist_ok=True)
package=work/"package";sources=package/"Sources";tests=package/"Tests"
sources.mkdir(parents=True,exist_ok=True);tests.mkdir(exist_ok=True)
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
deps=[]
for name,repo,revision in [
 ("swift-crypto","/mnt/development/build-cache/swift-package-cache/repositories/swift-crypto-7e0614ea","3280a5f72874d2f73bf25551bbb64f524c76d834"),
 ("swift-asn1","/mnt/development/build-cache/swift-package-cache/repositories/swift-asn1-7065ad2c","97fd57437fc94cfa6b62f2b8f84c50f433534e17")
]:
 destination=work/"dependencies"/name
 marker=destination/".hanlin-proof-revision"
 if not marker.exists():
  destination.mkdir(parents=True,exist_ok=True)
  archive=work/(name+".tar")
  subprocess.run(["git","--git-dir",repo,"archive","--format=tar","--output",str(archive),revision],check=True)
  archive_sha=digest(archive)
  with tarfile.open(archive) as value: value.extractall(destination,filter="data")
  marker.write_text(revision+"\n"+archive_sha+"\n")
  archive.unlink()
 assert marker.read_text().splitlines()[0]==revision
 tree=subprocess.check_output(["git","--git-dir",repo,"rev-parse",revision+"^{tree}"],text=True).strip()
 deps.append({"package":name,"originalRevision":revision,"originalTree":tree,
              "gitArchiveSHA256":marker.read_text().splitlines()[1],
              "packageManifestSHA256":digest(destination/"Package.swift"),
              "source":"Existing original Git cache, git archive; no network fetch or package install."})
store_names={
 "HanlinAtomicScriptStore.swift","HanlinProductTransfer.swift",
 "HanlinStoredPackageSnapshot+MiniAppRegistration.swift","HanlinScriptPackageDiscovery.swift"
}
inputs=[];diffs=[]
for module in ["HanlinPlatformContracts","HanlinScriptContracts","HanlinMiniAppCore","HanlinScriptStore"]:
 original=ROOT/"Packages/HanlinPlatform/Sources"/module
 dest=sources/module;dest.mkdir(exist_ok=True)
 for source in sorted(original.rglob("*")):
  if not source.is_file(): continue
  relative=source.relative_to(original)
  if module=="HanlinScriptStore" and source.name not in store_names: continue
  target=dest/relative;target.parent.mkdir(parents=True,exist_ok=True)
  raw=source.read_bytes()
  if source.suffix==".swift":
   before=raw.decode();after=before.replace("import CryptoKit\n","import Crypto\n")
   if source.name=="HanlinAtomicScriptStore.swift":
    assert after.count("import OSLog\n")==1
    after=after.replace("import OSLog\n","#if canImport(OSLog)\nimport OSLog\n#endif\n")
    declaration='    private static let logger = Logger(subsystem: "com.hanlin.ai", category: "ScriptArtifactStore")'
    assert after.count(declaration)==1
    after=after.replace(declaration,"#if canImport(OSLog)\n"+declaration+"\n#endif")
    start=after.index("            Self.logger.error(\n")
    end=after.index("\n            )",start)+len("\n            )")
    statement=after[start:end]
    after=after[:start]+"#if canImport(OSLog)\n"+statement+"\n#endif"+after[end:]
   target.write_text(after)
   diffs.extend(difflib.unified_diff(before.splitlines(True),after.splitlines(True),
                                   fromfile=str(source.relative_to(ROOT)),tofile="projection/"+str(relative)))
  else: target.write_bytes(raw)
  inputs.append({"path":str(source.relative_to(ROOT)),"originalSHA256":hashlib.sha256(raw).hexdigest(),
                 "projectedSHA256":digest(target),"unchanged":raw==target.read_bytes()})
test_source=ROOT/"Packages/HanlinPlatform/Tests/HanlinScriptStoreTests/HanlinAtomicScriptStoreTests.swift"
test_dir=tests/"HanlinScriptStoreTests";test_dir.mkdir(exist_ok=True)
target=test_dir/test_source.name
before=test_source.read_text();after=before.replace("import CryptoKit\n","import Crypto\n")
target.write_text(after)
inputs.append({"path":str(test_source.relative_to(ROOT)),"originalSHA256":digest(test_source),
               "projectedSHA256":digest(target),"unchanged":before==after})
diffs.extend(difflib.unified_diff(before.splitlines(True),after.splitlines(True),
                               fromfile=str(test_source.relative_to(ROOT)),tofile="projection/"+test_source.name))
(out/"projection.diff").write_text("".join(diffs))
manifest="""// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "HanlinStoreLifecycleProjection",
    dependencies: [.package(path: "../dependencies/swift-crypto")],
    targets: [
        .target(name: "HanlinPlatformContracts", resources: [.process("Resources")]),
        .target(name: "HanlinScriptContracts", dependencies: ["HanlinPlatformContracts", .product(name: "Crypto", package: "swift-crypto")], resources: [.process("Resources")]),
        .target(name: "HanlinMiniAppCore", dependencies: ["HanlinPlatformContracts"]),
        .target(name: "HanlinScriptStore", dependencies: ["HanlinPlatformContracts", "HanlinScriptContracts", "HanlinMiniAppCore", .product(name: "Crypto", package: "swift-crypto")]),
        .testTarget(name: "HanlinScriptStoreTests", dependencies: ["HanlinScriptStore", "HanlinMiniAppCore", "HanlinScriptContracts", "HanlinPlatformContracts", .product(name: "Crypto", package: "swift-crypto")])
    ], swiftLanguageModes: [.v6])
"""
(package/"Package.swift").write_text(manifest)
(out/"projection-Package.swift").write_text(manifest)
swift=shutil.which("swift");assert swift
toolchain=subprocess.check_output([swift,"--version"],text=True).strip()
command=[swift,"test","--package-path",str(package),"--scratch-path",str(work/".build"),
         "--jobs","2","--filter","HanlinAtomicScriptStoreTests/lifecycle"]
env=dict(os.environ);env["SWIFTCI_USE_LOCAL_DEPS"]="1"
plan={"schemaVersion":1,"baseSourceSHA":subprocess.check_output(["git","rev-parse","HEAD"],cwd=ROOT,text=True).strip(),
      "expect":args.expect,"command":command,"environmentChanges":{"SWIFTCI_USE_LOCAL_DEPS":"1"},
      "toolchain":toolchain,"dependencies":deps,"inputs":inputs,
      "projectionDiffSHA256":digest(out/"projection.diff"),
      "selectedMethod":"HanlinAtomicScriptStoreTests/lifecycle",
      "excludedUnreferencedStoreFiles":["HanlinShareInboxStore.swift","HanlinShareItemLoader.swift"],
      "boundary":"Actual production store/core/contracts plus authentic Apple SwiftCrypto; Linux imports/logging projection only. The complete atomic-store test file compiles; only lifecycle executes. No Apple native-module, UIKit, package analyzer, original engine rendering, or application UI claim."}
(out/"plan.json").write_text(json.dumps(plan,indent=2)+"\n")
started=time.monotonic();log=out/"swift-test.txt"
with log.open("wb") as stream:
 process=subprocess.Popen(command,cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT)
 (out/"active.json").write_text(json.dumps({"pid":process.pid,"command":command,"status":"RUNNING"})+"\n")
 while process.poll() is None:
  try: process.wait(timeout=30)
  except subprocess.TimeoutExpired:
   print(json.dumps({"phase":args.expect,"pid":process.pid,"elapsedSeconds":round(time.monotonic()-started,1),"logBytes":log.stat().st_size}),flush=True)
  if time.monotonic()-started>900:
   process.kill();process.wait();raise TimeoutError("Owned lifecycle build exceeded15 minutes")
code=process.returncode;text=log.read_text(errors="replace")
passed=bool(re.search(r"Test run with 1 tests? in 1 suites? passed",text))
failed_case='Lifecycle' in text and bool(re.search(r"Test.*Install, update, rollback, disable, restore, and uninstall preserve stable identity.*failed",text))
if args.expect=="red":
 result="REPRODUCED_FAILURE" if code!=0 and failed_case and "rolledBackSnapshot" in text else "UNEXPECTED_RESULT"
else:
 result="PORTABLE_PROJECTED_SOURCE_PASS" if code==0 and passed else "FAILED"
receipt={**plan,"status":result,"exit":code,"seconds":time.monotonic()-started,
         "rawLog":"swift-test.txt","rawLogSHA256":digest(log),"executedMethods":1 if passed or failed_case else 0,
         "otherMethodsExecuted":False,"nativeAppleExecution":"NOT_RUN"}
(out/"result.json").write_text(json.dumps(receipt,indent=2)+"\n")
(out/"active.json").write_text(json.dumps({"pid":process.pid,"status":"COMPLETED","exit":code})+"\n")
print(json.dumps({k:receipt[k] for k in ["status","exit","seconds","executedMethods","rawLogSHA256"]},indent=2),flush=True)
if result in ["UNEXPECTED_RESULT","FAILED"]:raise SystemExit(1)
