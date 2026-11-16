"""Read an owned completed xcresult. No build, simulator launch or test execution."""
import json
import os
from pathlib import Path
import subprocess
import tarfile

run = os.environ["SOURCE_RUN_ID"]
assert run.isdigit()
repo = os.environ["GITHUB_REPOSITORY"]
out = Path("native-result-inspection")
out.mkdir(exist_ok=True)
source = json.loads(subprocess.check_output(["gh", "api", f"repos/{repo}/actions/runs/{run}"]))
assert source["status"] == "completed"
(out / "source-run.json").write_text(json.dumps({"run": run, "head": source["head_sha"], "conclusion": source["conclusion"]}, indent=2))
raw = Path(os.environ["RUNNER_TEMP"]) / f"native-result-{run}"
motion = run == "43771756937"
artifact = f"chat-motion-ui-{run}" if motion else "AI_Hanlin-iOS26-simulator-smoke-logs"
subprocess.run(["gh", "run", "download", run, "--repo", repo, "--name", artifact, "--dir", str(raw)], check=True)
if motion:
    archive = next(raw.rglob("Motion.xcresult.tar.gz"))
    with tarfile.open(archive) as packed:
        packed.extractall(raw / "expanded", filter="data")
bundles = list(raw.rglob("Motion.xcresult" if motion else "NativeScriptProductionE2EResult.xcresult"))
assert len(bundles) == 1
tests = ["MotionUITests/testBRapidReversalPresetSwitchAndPersistence()", "MotionUITests/testCReadableLongContentRTLTypeOrientationAndCompletion()"] if motion else ["HanlinMorphComposerUITests/testDismissModelPickerKeepsSelectedModelAndDraft()"]
for index, test in enumerate(tests):
    folder = out / f"case-{index}"
    subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundles[0]), "--output-path", str(folder), "--test-id", test], check=True)
    with (out / f"case-{index}-activities.json").open("w") as log:
        result = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "activities", "--path", str(bundles[0]), "--test-id", test, "--format", "json"], stdout=log, stderr=subprocess.STDOUT)
    assert result.returncode == 0
