#!/usr/bin/env python3
"""Stage real import input and enqueue an incoming request in the OS App Group.

This never creates an installed-package registry, runtime output, or result.
The UI test must preview/compile/install the package and complete it itself.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = "com.itorah.hanlinminiapps"
GROUP = "group.com.itorah.shared"


def run(argv):
    return subprocess.check_output([str(value) for value in argv], cwd=ROOT, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator-udid", required=True)
    parser.add_argument("--app-path", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    if platform.system() != "Darwin":
        raise RuntimeError("Staging requires actual CoreSimulator OS containers")
    if plistlib.loads((args.app_path / "Info.plist").read_bytes())["CFBundleIdentifier"] != BUNDLE:
        raise RuntimeError("Unexpected compiled companion")
    args.evidence.mkdir(parents=True, exist_ok=True)
    data = Path(run(["xcrun", "simctl", "get_app_container", args.simulator_udid, BUNDLE, "data"])).resolve(strict=True)
    group = Path(run(["xcrun", "simctl", "get_app_container", args.simulator_udid, BUNDLE, GROUP])).resolve(strict=True)
    if not data.is_dir() or not group.is_dir():
        raise RuntimeError("CoreSimulator did not return actual app/group directories")
    archive = args.evidence / "MiniAppsExternalModal.zip"
    hashes = {}
    with ZipFile(archive, "x", compression=ZIP_DEFLATED) as package:
        for name in ("script.json", "index.tsx"):
            source = ROOT / "Scripts/ProductSplit/Fixtures/ExternalModal" / name
            raw = source.read_bytes()
            relative = source.relative_to(ROOT).as_posix()
            if raw != subprocess.check_output(["git", "show", "HEAD:" + relative], cwd=ROOT):
                raise RuntimeError("Fixture differs from committed source: " + relative)
            hashes[relative] = hashlib.sha256(raw).hexdigest()
            entry = ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            entry.compress_type = ZIP_DEFLATED
            package.writestr(entry, raw)
    destination = data / "Documents" / archive.name
    destination.parent.mkdir(exist_ok=True)
    with destination.open("xb") as output, archive.open("rb") as source:
        shutil.copyfileobj(source, output)
    archive_digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if hashlib.sha256(destination.read_bytes()).hexdigest() != archive_digest:
        raise RuntimeError("Staged fixture bytes changed")
    executable = args.evidence / "external-modal-bridge-fixture"
    bridge = ROOT / "Packages/HanlinMiniAppsBridge/Sources/HanlinMiniAppsBridge"
    sources = sorted(bridge.glob("*.swift"))
    if not sources:
        raise RuntimeError("Original Foundation bridge sources are missing")
    run(["xcrun", "swiftc", "-parse-as-library", *sources,
         ROOT / "Scripts/ProductSplit/ExternalModalBridgeFixture.swift", "-o", executable])
    seed = json.loads(run([executable, "seed", group]))
    proof = {"status": "REAL_IMPORT_AND_INCOMING_REQUEST_STAGED", "simulator_udid": args.simulator_udid,
             "bundle_id": BUNDLE, "source_sha": run(["git", "rev-parse", "HEAD"]),
             "fixture_sources": hashes, "archive_sha256": archive_digest,
             "archive": str(destination), "shared_group": GROUP, "shared_group_container": str(group),
             "seeder": str(executable), "request": seed,
             "verify_command": [str(executable), "verify", str(group)],
             "runtime_result_synthesized": False}
    (args.evidence / "staging.json").write_text(json.dumps(proof, indent=2) + "\n")
    print(json.dumps(proof, indent=2))


if __name__ == "__main__":
    main()
