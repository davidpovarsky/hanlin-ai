#!/usr/bin/env python3
"""Stage a real NativeScript archive and incoming requests in OS-owned containers.

This never seeds an installed-package registry, a provider, a runtime, or results.
The actual UI performs import/install, per-window editing, completion and cancel.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess

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
    parser.add_argument("--package-windows", action="store_true")
    args = parser.parse_args()
    if platform.system() != "Darwin":
        raise RuntimeError("Staging requires actual CoreSimulator OS containers")
    if plistlib.loads((args.app_path / "Info.plist").read_bytes())["CFBundleIdentifier"] != BUNDLE:
        raise RuntimeError("Unexpected compiled companion")
    args.evidence.mkdir(parents=True, exist_ok=True)
    data = Path(run(["xcrun", "simctl", "get_app_container", args.simulator_udid, BUNDLE, "data"])).resolve(strict=True)
    group = Path(run(["xcrun", "simctl", "get_app_container", args.simulator_udid, BUNDLE, GROUP])).resolve(strict=True)
    if not data.is_dir() or not group.is_dir():
        raise RuntimeError("CoreSimulator did not return the app's actual data and App Group containers")

    if args.package_windows:
        archive_paths = ["Scripts/NativeScript/Fixtures/package-window-" + name + ".hanlinNativeScript"
                         for name in ("alpha", "beta")]
        source_paths = archive_paths + ["Scripts/NativeScript/build_package_window_fixtures.py"]
        for name in ("alpha", "beta"):
            source_root = ROOT / ("Scripts/NativeScript/Fixtures/package-window-" + name + "-source")
            source_paths += [path.relative_to(ROOT).as_posix() for path in sorted(source_root.rglob("*"))
                             if path.is_file()]
        fixture_source = "Scripts/ProductSplit/NativeScriptPackageWindowBridgeFixture.swift"
        fixture_name = "nativescript-package-window-bridge-fixture"
    else:
        archive_paths = ["Scripts/NativeScript/Fixtures/window-factory.hanlinNativeScript"]
        source_paths = archive_paths + [
            "Scripts/NativeScript/Fixtures/window-factory-source/script.json",
            "Scripts/NativeScript/Fixtures/window-factory-source/nativescript/app/package.json",
            "Scripts/NativeScript/Fixtures/window-factory-source/nativescript/app/bundle.mjs",
            "Scripts/NativeScript/build-window-factory-fixture.mjs",
        ]
        fixture_source = "Scripts/ProductSplit/NativeScriptWindowBridgeFixture.swift"
        fixture_name = "nativescript-window-bridge-fixture"
    source_paths += [fixture_source]
    hashes = {}
    for relative in source_paths:
        raw = (ROOT / relative).read_bytes()
        if raw != subprocess.check_output(["git", "show", "HEAD:" + relative], cwd=ROOT):
            raise RuntimeError("Fixture differs from its committed source: " + relative)
        hashes[relative] = hashlib.sha256(raw).hexdigest()
    destinations = []
    for archive_relative in archive_paths:
        archive = ROOT / archive_relative
        destination = data / "Documents" / archive.name
        destination.parent.mkdir(exist_ok=True)
        with destination.open("xb") as output, archive.open("rb") as source:
            shutil.copyfileobj(source, output)
        if hashlib.sha256(destination.read_bytes()).hexdigest() != hashes[archive_relative]:
            raise RuntimeError("Staged NativeScript archive bytes changed")
        destinations.append(str(destination))

    executable = args.evidence / fixture_name
    sources = sorted((ROOT / "Packages/HanlinMiniAppsBridge/Sources/HanlinMiniAppsBridge").glob("*.swift"))
    if not sources:
        raise RuntimeError("The original Foundation bridge sources are missing")
    run(["xcrun", "swiftc", "-parse-as-library", *sources,
         ROOT / fixture_source, "-o", executable])
    requests = json.loads(run([executable, "seed", group]))
    proof = {
        "status": "REAL_NATIVESCRIPT_IMPORT_AND_INCOMING_REQUESTS_STAGED",
        "simulator_udid": args.simulator_udid,
        "bundle_id": BUNDLE,
        "source_sha": run(["git", "rev-parse", "HEAD"]),
        "fixture_sources": hashes,
        "archive": destinations[0],
        "archives": destinations,
        "distinct_packages": args.package_windows,
        "shared_group": GROUP,
        "shared_group_container": str(group),
        "seeder": str(executable),
        "requests": requests,
        "verify_command": [str(executable), "verify", str(group)],
        "runtime_result_synthesized": False,
    }
    (args.evidence / "staging.json").write_text(json.dumps(proof, indent=2) + "\n")
    print(json.dumps(proof, indent=2))


if __name__ == "__main__":
    main()
