"""Retain original Motion results even when XCTest fails before its first case."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import sys
import time

bundle, device, evidence, test_code = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3]), int(sys.argv[4])
assert re.fullmatch(r"[A-Fa-f0-9-]{36}", device)
selected = json.loads((evidence / "verified-environment.json").read_text())["device"]
assert selected["udid"] == device
status = {"test_exit_code": test_code, "archive": "NOT_CREATED", "readability": "NOT_READ", "diagnostics": []}
if bundle.exists():
    # Preserve the original bundle before invoking the reader which itself can stall.
    partial = evidence / "Motion.xcresult.tar.gz.partial"
    try:
        subprocess.run(["tar", "-czf", str(partial), "-C", str(bundle.parent), bundle.name], check=True, timeout=90)
        archive = evidence / "Motion.xcresult.tar.gz"
        partial.replace(archive)
        status["archive"] = "ARCHIVED"
        status["archive_sha256"] = hashlib.sha256(archive.read_bytes()).hexdigest()
    except (OSError, subprocess.SubprocessError) as error:
        status["archive_error"] = str(error)
        partial.unlink(missing_ok=True)
    try:
        result = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "tests",
                                 "--path", str(bundle), "--format", "json"],
                                capture_output=True, timeout=120, check=True)
        json.loads(result.stdout)
        (evidence / "tests.json").write_bytes(result.stdout)
        status["readability"] = "READABLE"
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        status["readability"] = "READER_FAILED"
        status["reader_error"] = str(error)
        if getattr(error, "stderr", None):
            (evidence / "result-reader.stderr").write_bytes(error.stderr)
else:
    status["readability"] = "NO_RESULT_BUNDLE"

if test_code or status["readability"] != "READABLE":
    diagnostics = evidence / "test-runner-diagnostics"
    diagnostics.mkdir(exist_ok=True)
    # Only the owned proof processes/reports, without environment dumps or broad user logs.
    reports = Path.home() / "Library/Logs/DiagnosticReports"
    for source in sorted(reports.glob("ChatMotionProof*.ips"))[-6:]:
        if source.stat().st_size <= 16 * 1024 * 1024 and source.stat().st_mtime >= time.time() - 3600:
            shutil.copyfile(source, diagnostics / source.name)
            status["diagnostics"].append(source.name)
    try:
        processes = subprocess.run(["ps", "-axo", "pid=,comm="], capture_output=True, text=True, check=True, timeout=5)
        owned = []
        for line in processes.stdout.splitlines():
            parts = line.strip().split(None, 1)
            if len(parts) == 2 and Path(parts[1]).name in {"ChatMotionProof", "ChatMotionProofUITests-Runner"}:
                owned.append((parts[0], parts[1]))
        (diagnostics / "owned-processes.json").write_text(json.dumps(owned, indent=2))
        for pid, name in owned[:3]:
            target = diagnostics / (Path(name).name + "-" + pid + ".sample.txt")
            with (diagnostics / (pid + ".sample-command.log")).open("w") as stream:
                subprocess.run(["sample", pid, "3", "-file", str(target)],
                               stdout=stream, stderr=subprocess.STDOUT, check=False, timeout=12)
    except (OSError, subprocess.SubprocessError) as error:
        status["diagnostic_error"] = str(error)

try:
    result = subprocess.run(["xcrun", "simctl", "get_app_container", device, "ai.hanlin.motion-proof", "data"],
                            capture_output=True, text=True, check=True, timeout=5)
    timeline = Path(result.stdout.strip()) / "Documents/motion-geometry-timeline.json"
    if timeline.exists():
        shutil.copyfile(timeline, evidence / timeline.name)
except (OSError, subprocess.SubprocessError):
    pass
status["status"] = ("FINALIZED_READABLE_ARCHIVED" if status["archive"] == "ARCHIVED" and
                    status["readability"] == "READABLE" else "INCOMPLETE_RAW_RESULT")
(evidence / "raw-result-status.json").write_text(json.dumps(status, indent=2))
print(json.dumps(status))
