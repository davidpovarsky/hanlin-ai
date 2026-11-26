from pathlib import Path
import os,sys,subprocess,json,hashlib,time,traceback,datetime
BASE=Path("/Users/m1/builds/hanlin-motion-dacb4ca5-20261126")
STAGE=BASE/"revisions/24bc34c6/ax-diagnostic-stdout"
PROOF=BASE/"proof"
DD=Path("/Users/m1/caches/DerivedData/hanlin-motion-dacb4ca5-20261126")
DEVICE="B58E5A52-6C30-4B1B-BE7D-D8CE97B5645D"
PRODUCTION=PROOF/"Vendor/HanlinSDK/Packages/HanlinPresentationSDK/Sources/HanlinChatUI/Motion/HanlinAnimatedDisclosure.swift"
ORIGINAL_TEST=PROOF/"UITests/MotionUITests.swift"
DIAG=PROOF/"UITests/MotionAXDiagnosticTests.swift"
PROJECT=PROOF/"ChatMotionProof.xcodeproj/project.pbxproj"
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
status={"status":"RUNNING","purpose":"Read-only AX ownership diagnosis; not original B/A/C acceptance","productionSHA":"24bc34c618615cb75b362d9d64f55e4607fd0e74","diagnosticOnlyOptions":{"collect-test-diagnostics":"never","authority":"Installed xcodebuild -help supports on-failure|never; avoid reproduced sysdiagnose finalizer hang. Original B/A/C controller unchanged.","stdoutAndPNG":"Direct owned runner-container copies in addition to retained raw result"} ,"steps":[],"pid":os.getpid(),"startedUTC":datetime.datetime.now(datetime.timezone.utc).isoformat()}
def save(): (STAGE/"status.json").write_text(json.dumps(status,indent=2)+"\n")
def run(name,args,cwd=PROOF):
 started=time.monotonic()
 with (STAGE/(name+".log")).open("w") as f:r=subprocess.run(args,cwd=cwd,stdout=f,stderr=subprocess.STDOUT)
 status["steps"].append({"name":name,"command":[str(x) for x in args],"exitCode":r.returncode,"seconds":time.monotonic()-started})
 save();return r.returncode
old_project=None
try:
 free=os.statvfs(BASE).f_bavail*os.statvfs(BASE).f_frsize
 status["freeAtStart"]=free
 assert free>600000000+1073741824, "Phase disk budget"
 assert sha(ORIGINAL_TEST)=="5f714f6ad4fc5db3abec22abc5e520f4bba94d5f66740f69673ed3d401665874"
 assert sha(PRODUCTION)=="948c6ba85207b017c3819dd27694419e5f195a62fa08d3cfdcbe4f043eba2f7d"
 assert not DIAG.exists()
 old_project=PROJECT.read_bytes()
 (STAGE/"original-project.pbxproj").write_bytes(old_project)
 status["originalProjectSHA256"]=hashlib.sha256(old_project).hexdigest()
 DIAG.write_bytes((STAGE/"MotionAXDiagnosticTests.swift").read_bytes())
 assert run("xcodegen",["/opt/homebrew/bin/xcodegen","generate","--spec","project.json"])==0
 build=["xcodebuild","build-for-testing","-project","ChatMotionProof.xcodeproj","-scheme","ChatMotionProof","-derivedDataPath",str(DD),"-destination","platform=iOS Simulator,id="+DEVICE,"-destination-timeout","60","-disableAutomaticPackageResolution","-skipMacroValidation","CODE_SIGNING_ALLOWED=NO"]
 assert run("build",build)==0
 command=["xcodebuild","test-without-building","-project","ChatMotionProof.xcodeproj","-scheme","ChatMotionProof","-derivedDataPath",str(DD),"-destination","platform=iOS Simulator,id="+DEVICE,"-destination-timeout","60","-resultBundlePath",str(STAGE/"Diagnostic.xcresult"),"-disableAutomaticPackageResolution","-skipMacroValidation","-parallel-testing-enabled","NO","-test-timeouts-enabled","YES","-default-test-execution-time-allowance","600","-maximum-test-execution-time-allowance","720","CODE_SIGNING_ALLOWED=NO","-collect-test-diagnostics","never","-only-testing:ChatMotionProofUITests/MotionAXDiagnosticTests/testCaptureRetainedDisclosureAccessibility"]
 code=run("diagnostic",command)
 status["testExit"]=code
 run("attachments",["xcrun","xcresulttool","export","attachments","--path",str(STAGE/"Diagnostic.xcresult"),"--output-path",str(STAGE/"attachments")])
 run("tests",["xcrun","xcresulttool","get","test-results","tests","--path",str(STAGE/"Diagnostic.xcresult"),"--compact"])
 status["status"]="DIAGNOSTIC_CAPTURED" if code==0 else "DIAGNOSTIC_FAILED"
except BaseException as e:
 status["status"]="ERROR";status["error"]=str(e);status["traceback"]=traceback.format_exc()
finally:
 if DIAG.exists():DIAG.rename(STAGE/"MotionAXDiagnosticTests.staged.swift")
 if old_project is not None:PROJECT.write_bytes(old_project)
 status["fixtureRestored"]={"originalTestSHA256":sha(ORIGINAL_TEST),"productionSHA256":sha(PRODUCTION),"projectSHA256":sha(PROJECT),"diagnosticSourceRemoved":not DIAG.exists()}
 status["finishedUTC"]=datetime.datetime.now(datetime.timezone.utc).isoformat();save()
