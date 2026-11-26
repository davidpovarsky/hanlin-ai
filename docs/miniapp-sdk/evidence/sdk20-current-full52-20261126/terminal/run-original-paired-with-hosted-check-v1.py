#!/usr/bin/env python3
"""Original paired main with one post-AI-build resource-integrity prerequisite."""
from pathlib import Path
import argparse,datetime,hashlib,importlib.util,json,os,sys
ROOT=Path("/Users/m1/builds/hanlin-notification-wire-fix-20261125")
RUNNER="Scripts/ProductSplit/run_paired_acceptance.py"
RUNNER_SHA="a99b6194f8dd20bc30998ff2ad9e86ec219415a00615b250c65670f7dfcdba7d"
HOSTED="AI_HLYTests/Fixtures/HostServicesProbe.bundle/ExpoSwiftUIProbeA.hanlinExpo"
def digest(p):
    h=hashlib.sha256()
    with Path(p).open("rb") as f:
        for chunk in iter(lambda:f.read(1024*1024),b""):h.update(chunk)
    return h.hexdigest()
def verify(row):
    p=Path(row["path"])
    assert p.is_file() and p.stat().st_size==row["bytes"] and digest(p)==row["sha256"],str(p)
    return p
def main():
    p=argparse.ArgumentParser();p.add_argument("--decision",type=Path,required=True);args=p.parse_args()
    d=json.loads(args.decision.read_text())
    assert d["status"]=="SEALED" and d["id"]=="paired52-sdk20-v2" and d["root"]==str(ROOT)
    assert os.environ["GITHUB_WORKSPACE"]==str(ROOT) and os.environ["GITHUB_SHA"]==d["source"]
    assert os.environ["PAIRED_TEST_SCOPE"]=="miniapp_complete"
    assert os.environ["SPLIT_EVIDENCE"]==str(Path(d["output"])/"original")
    assert os.environ["SPLIT_DERIVED_DATA"]==d["derivedData"]
    assert verify(d["originalMainGuard"])==Path(__file__).resolve()
    source=verify(d["hostedFixture"]["source"]);assert source==ROOT/HOSTED
    runner_path=ROOT/RUNNER;assert digest(runner_path)==RUNNER_SHA
    # Match the original script execution import root for its sibling helper.
    sys.path.insert(0,str(runner_path.parent))
    spec=importlib.util.spec_from_file_location("original_paired_main",runner_path)
    runner=importlib.util.module_from_spec(spec);spec.loader.exec_module(runner)
    original_command=runner.command
    checks=[]
    def command_with_hosted_prerequisite(*args,**kwargs):
        result=original_command(*args,**kwargs)
        log_name=args[1] if len(args)>1 else kwargs["name"]
        if log_name=="ai-build.log":
            assert result[0]==0 and not checks
            verify(d["hostedFixture"]["source"])
            test_bundle=Path(d["derivedData"])/"Build/Products/Debug-iphonesimulator/AI_Hanlin.app/PlugIns/AI_HLYTests.xctest"
            candidates=[test_bundle/"Fixtures/HostServicesProbe.bundle",test_bundle/"HostServicesProbe.bundle"]
            bundle=next((item for item in candidates if item.is_dir()),None)
            assert bundle is not None,"Original built HostServicesProbe resource bundle is absent"
            archive=bundle/source.name
            actual={"path":str(archive),"bytes":archive.stat().st_size,"sha256":digest(archive)}
            assert actual["bytes"]==d["hostedFixture"]["source"]["bytes"] and actual["sha256"]==d["hostedFixture"]["source"]["sha256"],"Built original hosted resource differs from the authenticated Metro producer output"
            proof={"schema":1,"status":"VERIFIED_PREREQUISITE","source":d["source"],"observedAt":datetime.datetime.now(datetime.timezone.utc).isoformat(),"originalBuildLog":log_name,"originalBuildExitCode":result[0],"originalCommandUnchanged":True,"sourceResource":d["hostedFixture"]["source"],"builtResource":actual,"lookupOrder":[str(item) for item in candidates],"boundary":"Actual original AI build completed; resource bytes verified before original main continues. No test result is inferred or supplied."}
            (runner.EVIDENCE/"hosted-fixture-built-check.json").write_text(json.dumps(proof,indent=2)+"\n")
            checks.append(proof)
        return result
    runner.command=command_with_hosted_prerequisite
    result=runner.main()
    if result==0:assert len(checks)==1
    return result
if __name__=="__main__":raise SystemExit(main())
