"""Export the exact successfully built producer for original consumer UI tests."""
from pathlib import Path
import hashlib, json, os, plistlib, subprocess

out = Path(os.environ["SPLIT_EVIDENCE"])
receipt_path = out / "acceptance.json"
if not receipt_path.exists():
    raise SystemExit("No native build receipt; producer export not available.")
receipt = json.loads(receipt_path.read_text())
if receipt.get("build") != "EXECUTED_PASS":
    raise SystemExit("Producer did not finish its actual app build.")
app = Path(os.environ["SPLIT_DERIVED_DATA"]) / "Build/Products/Debug-iphonesimulator/HanlinMiniApps.app"
info = plistlib.loads((app / "Info.plist").read_bytes())
if info.get("CFBundleIdentifier") != "com.itorah.hanlinminiapps":
    raise SystemExit("Unexpected producer identity.")
executable = app / info["CFBundleExecutable"]
archive = out / "HanlinMiniApps-simulator.zip"
subprocess.run(["ditto", "-c", "-k", "--keepParent", str(app), str(archive)], check=True)
manifest = {
    "schema_version": 1,
    "producer_sha": os.environ["GITHUB_SHA"],
    "run_id": os.environ["GITHUB_RUN_ID"],
    "bundle_id": info["CFBundleIdentifier"],
    "app_relative_path": "HanlinMiniApps.app",
    "executable_name": executable.name,
    "executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
    "archive_name": archive.name,
    "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
    "build_status": receipt["build"],
    "native_acceptance_status": receipt["status"],
    "architecture": receipt["architecture"],
    "sdk": receipt.get("runtime", {}).get("version"),
    "physical_signing_status": "NOT_VALIDATED_BY_SIMULATOR",
}
(out / "producer-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(json.dumps(manifest))
