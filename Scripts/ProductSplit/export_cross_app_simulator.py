"""Export the exact successfully built producer for original consumer UI tests."""
from pathlib import Path
import hashlib
import json
import os
import plistlib
import stat
import subprocess

ROOT = Path(__file__).resolve().parents[2]
out = Path(os.environ["SPLIT_EVIDENCE"])


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        for data in iter(lambda: source.read(1024 * 1024), b""):
            result.update(data)
    return result.hexdigest()


def inventory(root):
    entries = {}
    for directory, children, files in os.walk(root, followlinks=False):
        for name in sorted(children + files):
            path = Path(directory) / name
            relative = path.relative_to(root).as_posix()
            info = path.lstat()
            if stat.S_ISLNK(info.st_mode):
                target = os.readlink(path)
                resolved = (path.parent / target).resolve()
                if resolved != root.resolve() and root.resolve() not in resolved.parents:
                    raise RuntimeError("The built app contains a link outside its bundle: " + relative)
                entries[relative] = {"kind": "symlink", "target": target}
            elif stat.S_ISDIR(info.st_mode):
                entries[relative] = {"kind": "directory", "mode": stat.S_IMODE(info.st_mode)}
            elif stat.S_ISREG(info.st_mode):
                entries[relative] = {"kind": "file", "sha256": digest(path),
                                     "bytes": info.st_size, "mode": stat.S_IMODE(info.st_mode)}
            else:
                raise RuntimeError("The built app contains an unsupported filesystem entry: " + relative)
    return entries


receipt_path = out / "acceptance.json"
if not receipt_path.exists():
    raise SystemExit("No native build receipt; producer export not available.")
receipt = json.loads(receipt_path.read_text())
if receipt.get("build") != "EXECUTED_PASS":
    raise SystemExit("Producer did not finish its actual app build.")
commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
if receipt.get("sha") != commit:
    raise SystemExit("The current source commit differs from the actual build receipt.")
build_log = out / "build.log"
build_events = [json.loads(line) for line in (out / "commands.jsonl").read_text().splitlines()]
build_event = next((event for event in build_events
                    if event.get("argv") == receipt.get("build_command") and event.get("log") == build_log.name), None)
if not build_event or build_event.get("exit") != 0 or build_event.get("sha256") != digest(build_log):
    raise SystemExit("The successful original xcodebuild command or original log hash is missing.")
identity_path = out / "source-identity.json"
identity = json.loads(identity_path.read_text())
if identity.get("commit") != commit or digest(identity_path) != receipt.get("source_identity_sha256"):
    raise SystemExit("The recorded pre-build source identity is missing or changed.")
for relative, expected in identity["tracked_file_sha256"].items():
    source = ROOT / relative
    if not source.is_file() or digest(source) != expected:
        raise SystemExit("A recorded source input changed after the original build: " + relative)

app = Path(os.environ["SPLIT_DERIVED_DATA"]) / "Build/Products/Debug-iphonesimulator/HanlinMiniApps.app"
info = plistlib.loads((app / "Info.plist").read_bytes())
if info.get("CFBundleIdentifier") != "com.itorah.hanlinminiapps":
    raise SystemExit("Unexpected producer identity.")
executable_name = info["CFBundleExecutable"]
if Path(executable_name).name != executable_name:
    raise SystemExit("The executable path escapes the app bundle.")
executable = app / executable_name
signature = subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
(out / "export-codesign.log").write_bytes(signature.stdout)
signature.check_returncode()
app_files = inventory(app)
archive = out / "HanlinMiniApps-simulator.zip"
subprocess.run(["ditto", "-c", "-k", "--keepParent", str(app), str(archive)], check=True)

origin = os.environ.get("SPLIT_EXECUTION_ORIGIN", "github-actions" if os.environ.get("GITHUB_ACTIONS") == "true" else "local-mac")
if origin not in {"local-mac", "github-actions"}:
    raise SystemExit("Unknown producer execution origin.")
run_id = None
if origin == "github-actions":
    run_id = os.environ["GITHUB_RUN_ID"]
    if not run_id.isdecimal() or os.environ["GITHUB_SHA"] != commit:
        raise SystemExit("The GitHub run identity differs from the source that actually built.")
elif os.environ.get("GITHUB_ACTIONS") == "true":
    raise SystemExit("A GitHub Actions execution cannot be labeled local.")
manifest = {
    "schema_version": 1,
    "execution_origin": origin,
    "producer_sha": commit,
    "run_id": run_id,
    "bundle_id": info["CFBundleIdentifier"],
    "app_relative_path": "HanlinMiniApps.app",
    "executable_name": executable.name,
    "executable_sha256": digest(executable),
    "archive_name": archive.name,
    "archive_sha256": digest(archive),
    "build_status": receipt["build"],
    "native_acceptance_status": receipt["status"],
    "architecture": receipt["architecture"],
    "sdk": receipt.get("runtime", {}).get("version"),
    "physical_signing_status": "NOT_VALIDATED_BY_SIMULATOR",
    "build_receipt_name": receipt_path.name,
    "build_receipt_sha256": digest(receipt_path),
    "build_log_name": build_log.name,
    "build_log_sha256": digest(build_log),
    "source_identity": identity,
    "app_files": app_files,
    "codesign_verification": {"status": "EXECUTED_PASS", "log_name": "export-codesign.log",
                              "log_sha256": digest(out / "export-codesign.log")},
}
(out / "producer-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(json.dumps({key: value for key, value in manifest.items() if key not in {"app_files", "source_identity"}}))
