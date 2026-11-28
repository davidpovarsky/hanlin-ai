from pathlib import Path
import datetime
import json
import runpy
import subprocess
import sys
import time

out = Path(__file__).resolve().parent
expected = Path.cwd() / "Scripts/CI/Tests/nativescript_parity_async_startup.test.mjs"
starts = {}
observations = []

def observe(frame, event, value):
    if frame.f_code is not subprocess.run.__code__:
        return
    if event == "call":
        starts[id(frame)] = (datetime.datetime.now(datetime.timezone.utc).isoformat(), time.monotonic())
    elif event == "return":
        started = starts.pop(id(frame), None)
        if isinstance(value, subprocess.CompletedProcess) and isinstance(value.args, list) and value.args == ["node", "--test", "--test-reporter=tap", str(expected)]:
            index = len(observations) + 1
            stdout = out / ("parity-nested-" + str(index) + ".stdout.log")
            stderr = out / ("parity-nested-" + str(index) + ".stderr.log")
            stdout.write_text(value.stdout or "")
            stderr.write_text(value.stderr or "")
            observations.append({"argv": value.args, "exitCode": value.returncode,
                "startedAt": started[0] if started else None,
                "durationSeconds": time.monotonic() - started[1] if started else None,
                "stdout": stdout.name, "stderr": stderr.name})
            (out / "parity-nested-observations.json").write_text(json.dumps(observations, indent=2) + "\n")

sys.argv = ["python3 -m unittest", "discover", "-s", "Scripts/CI/Tests", "-p", "test_nativescript_parity_fixture.py", "-v"]
sys.setprofile(observe)
try:
    runpy.run_module("unittest", run_name="__main__", alter_sys=True)
finally:
    sys.setprofile(None)
