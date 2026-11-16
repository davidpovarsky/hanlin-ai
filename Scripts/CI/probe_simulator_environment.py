"""Read installed simulator/runtime state; do not build, install, erase or launch."""
import json
import os
from pathlib import Path
import shutil
import subprocess

out = Path("build/phase2-simulator-environment")
out.mkdir(parents=True, exist_ok=True)
records = []
for name, command in [
    ("xcode", ["xcodebuild", "-version"]),
    ("simulator-sdk", ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"]),
    ("runtime-help", ["xcrun", "simctl", "help", "runtime"]),
    ("runtime-images", ["xcrun", "simctl", "runtime", "list", "-j"]),
    ("runtimes", ["xcrun", "simctl", "list", "runtimes", "-j"]),
]:
    result = subprocess.run(command, capture_output=True, timeout=30)
    (out / (name + ".stdout")).write_bytes(result.stdout)
    (out / (name + ".stderr")).write_bytes(result.stderr)
    records.append({"name": name, "command": command, "exit": result.returncode})
runtime_paths = []
for runtime in json.loads((out / "runtimes.stdout").read_text())["runtimes"]:
    if runtime.get("platform") != "iOS":
        continue
    runtime_paths.append({"runtime": runtime, "root_exists": Path(runtime["runtimeRoot"]).is_dir(),
        "bundle_exists": Path(runtime["bundlePath"]).is_dir(),
        "info_exists": (Path(runtime["bundlePath"]) / "Contents/Info.plist").is_file()})
directories = {}
for directory in ["/Library/Developer/CoreSimulator/Images", "/Library/Developer/CoreSimulator/Volumes",
                  "/Library/Developer/CoreSimulator/Profiles/Runtimes"]:
    root = Path(directory)
    directories[directory] = [{"name": p.name, "is_file": p.is_file(), "is_dir": p.is_dir()}
                              for p in list(root.iterdir())[:100]] if root.is_dir() else None
(out / "summary.json").write_text(json.dumps({"scope": "READ_ONLY_ENVIRONMENT_PROBE",
    "developer_dir": os.environ.get("DEVELOPER_DIR"), "commands": records,
    "runtime_paths": runtime_paths, "directories": directories,
    "free_bytes": shutil.disk_usage(".").free}, indent=2))
