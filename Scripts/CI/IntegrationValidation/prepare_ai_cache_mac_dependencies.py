#!/usr/bin/env python3
"""Plan or APFS-clone verified Mac dependency inputs; never launch a native build.

The donor is read-only. Existing destinations are never replaced. Original
preparation scripts remain responsible for current provenance, source production,
SDK generation, and Runtime Host tests. A successful clone is not a build pass.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import shlex
import subprocess
import sys

MATCHED_INPUTS = (
    "RuntimeDependencies.lock.json",
    "Scripts/Runtime/prepare-runtime-core.sh",
    "Scripts/Expo/package-lock.json",
    "Scripts/NativeScript/package-lock.json",
    "Scripts/NativeScript/dependency-lock.json",
    "Scripts/NativeScript/build-metadata-tool.py",
    "Scripts/ExpoNativeAPI/dependency-lock.json",
    "Scripts/ExpoNativeAPI/prepare-ios-dependencies.mjs",
    "Scripts/ExpoNativeAPI/multiscene-patch.mjs",
)
CLONE_PATHS = (
    "Scripts/Expo/node_modules",
    "Scripts/NativeScript/node_modules",
    "Packages/HanlinExpoRuntime/Artifacts/ReactNativeHeaders.xcframework",
    "Packages/HanlinExpoRuntime/Artifacts/React.xcframework",
    "Packages/HanlinExpoRuntime/Artifacts/ReactNativeDependencies.xcframework",
    "Packages/HanlinExpoRuntime/Artifacts/hermesvm.xcframework",
    "Packages/HanlinExpoRuntime/Artifacts/ExpoModulesJSI.xcframework",
    "Packages/HanlinExpoRuntime/Artifacts/ExpoModulesCore.xcframework",
    "Packages/HanlinExpoRuntime/Artifacts/ExpoModulesWorklets.xcframework",
    "Packages/HanlinExpoRuntime/Artifacts/ExpoUI.xcframework",
    "Packages/HanlinExpoRuntime/Artifacts/ExpoBrownfield.xcframework",
    "Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks",
    "Packages/HanlinExpoRuntime/Artifacts/ReactModularHeaders",
    "Packages/HanlinExpoNativeAPI/Artifacts/Libffi.xcframework",
    "Packages/HanlinNativeScriptRuntime/Artifacts/TNSWidgets.xcframework",
    "Packages/HanlinNativeScriptRuntime/Artifacts/NSCWinterTC.xcframework",
    "Packages/HanlinNativeScriptRuntime/Artifacts/native-api-usage.json",
    "Packages/HanlinNativeScriptRuntime/Artifacts/dependency-closure.json",
    "Vendor/NodeMobile/NodeMobile.xcframework",
    "Vendor/Python/Python.xcframework",
    "Vendor/Python/Python-VERSIONS",
    "build/nativescript-metadata-tool/bin",
    "build/nativescript-metadata-tool/provenance.json",
    "build/SourcePackages",
)


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def host_node_requirement(root: Path) -> tuple[str, dict]:
    # Read the original generator's gate without executing its patch generation.
    relative = "Scripts/Runtime/generate-yarn-unicode-patch.mjs"
    gate = root / relative
    matches = dict(re.findall(r"process\.versions\.(node|unicode) !== '([^']+)'", gate.read_text()))
    if set(matches) != {"node", "unicode"}:
        raise ValueError("Original Host Node/Unicode gate changed; review " + relative)
    script = """const required = %s;
const actual = {executable: process.execPath, node: process.versions.node,
  unicode: process.versions.unicode, icu: process.versions.icu,
  fullICU: process.config.variables.icu_small === false};
if (actual.node !== required.node || actual.unicode !== required.unicode ||
    !actual.icu || !actual.fullICU) {
  throw new Error("Original Runtime Host generator requires full-ICU Node " +
    required.node + " / Unicode " + required.unicode + "; observed " + JSON.stringify(actual));
}
console.log(JSON.stringify(actual));""" % json.dumps(matches)
    return script, {"required": matches, "requiredBy": relative, "gateSHA256": sha256(gate)}


def preparation_commands(root: Path, node_bin: Path, node_preflight: str) -> str:
    quoted_root, quoted_node = shlex.quote(str(root)), shlex.quote(str(node_bin))
    return f"""# Execute separately on the Mac after reviewing the plan.
# These are the original producers; Expo preparation does invoke native Xcode builds.
# This combined sequence also requires the Host generator's exact Node/Unicode pin and full ICU.
set -euo pipefail
cd {quoted_root}
HANLIN_PREP_TEMP="$(mktemp -d /Users/m1/builds/hanlin-ai-cache-prep.XXXXXX)"
mkdir -p "$HANLIN_PREP_TEMP/bin"
ln -s /opt/homebrew/bin/python3.12 "$HANLIN_PREP_TEMP/bin/python3"
export RUNNER_TEMP="$HANLIN_PREP_TEMP"
export PATH="$HANLIN_PREP_TEMP/bin":{quoted_node}:/Users/m1/.gem/ruby/3.3.0/bin:/opt/homebrew/bin:"$PATH"
node -e {shlex.quote(node_preflight)}
python3 --version
pod --version
node Scripts/MiniApps/install-tooling.mjs --engine=expo --ignore-scripts
node Scripts/MiniApps/install-tooling.mjs --engine=nativescript --ignore-scripts
node Scripts/Expo/prepare-ios-dependencies.mjs
node Scripts/NativeScript/prepare-ios-dependencies.mjs
bash Scripts/Runtime/prepare-runtime-host.sh
python3 Scripts/Runtime/runtime_host_archive.py sync AI_HLY/RuntimeHostResources.zip
python3 Scripts/Runtime/runtime_host_archive.py validate AI_HLY/RuntimeHostResources.zip
node Scripts/Runtime/generate-runtime-manifest.mjs RuntimeDependencies.lock.json AI_HLY/Downstream/RuntimeCore/Resources/RuntimeManifest.json
python3 Scripts/SDK/native_artifacts.py inventory --root .
git diff --check
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--node-bin", type=Path, required=True,
                        help="Already installed full-ICU Node bin directory matching the original Host generator's exact Node/Unicode pin")
    parser.add_argument("--apply-clones", action="store_true")
    parser.add_argument("--derived-data-source", type=Path)
    parser.add_argument("--derived-data-destination", type=Path)
    args = parser.parse_args()
    source, target = args.source.resolve(strict=True), args.destination.resolve(strict=True)
    if source == target or source in target.parents or target in source.parents:
        raise ValueError("Source and destination must be independent checkouts")
    if bool(args.derived_data_source) != bool(args.derived_data_destination):
        raise ValueError("Both DerivedData paths must be supplied together")
    node_bin = args.node_bin.resolve(strict=True)
    if not (node_bin / "node").is_file():
        raise ValueError("--node-bin must contain the already installed host Node executable")
    node_preflight, requirement = host_node_requirement(target)
    probe = subprocess.run([str(node_bin / "node"), "-e", node_preflight],
                           capture_output=True, text=True, timeout=15)
    if probe.returncode:
        raise ValueError("Host Node preflight failed: " + probe.stderr.strip())
    host_node = {**requirement, **json.loads(probe.stdout)}
    inputs = []
    for relative in MATCHED_INPUTS:
        original, current = sha256(source / relative), sha256(target / relative)
        if original != current:
            raise ValueError("Donor input differs; reassess before reuse: " + relative)
        inputs.append({"path": relative, "sha256": current})
    paths = [(source / relative, target / relative) for relative in CLONE_PATHS]
    if args.derived_data_source:
        cache_source = args.derived_data_source.resolve(strict=True)
        cache_target = args.derived_data_destination.resolve()
        if cache_source == cache_target or cache_source in cache_target.parents or cache_target in cache_source.parents:
            raise ValueError("DerivedData paths must be independent")
        paths.append((cache_source, cache_target))
    missing = [str(path) for path, _ in paths if not path.exists()]
    if missing:
        raise ValueError("Donor paths are missing: " + ", ".join(missing))
    occupied = [str(path) for _, path in paths if os.path.lexists(path)]
    plan = {
        "status": "PLAN_ONLY",
        "donor": str(source),
        "destination": str(target),
        "matchedNativeAndNPMLockInputs": inputs,
        "hostNode": host_node,
        "clones": [{"source": str(a), "destination": str(b)} for a, b in paths],
        "preservedExistingDestinations": occupied,
        "pendingCloneCount": len(paths) - len(occupied),
        "notCopied": ["ExpoAsset.xcframework (produce from current original sources)",
                      "RuntimeHostResources.zip (prepare and test current SDK/Host)",
                      "tracked source and current widget resources"],
        "nativeBuildsRun": False,
        "testsRun": False,
        "notes": [
            "APFS clones are independent writable files, not hard links.",
            "Existing source-build receipts remain unchanged; current Expo preparation decides reuse.",
            "New ExpoAsset changes the source producer identity, including ExpoUI.",
            "Current Expo preparation also invokes the original ExpoModulesJSI producer.",
            "Original npm graph validation may reinstall stale local packages or preparation changes.",
            "The combined producer recipe checks the original Host generator's exact Node/Unicode pin and full ICU before reuse.",
            "An inventory or clone is not native compilation or test evidence.",
        ],
    }
    print(json.dumps(plan, indent=2))
    if args.apply_clones:
        if sys.platform != "darwin":
            raise ValueError("APFS cloning must run on the Mac")
        for original, destination in paths:
            if os.path.lexists(destination):
                print("PRESERVED (original preparer must validate) " + str(destination), flush=True)
                continue
            destination.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["/bin/cp", "-cR", str(original), str(destination)], check=True)
            print("CLONED " + str(destination), flush=True)
    print("\n" + preparation_commands(target, node_bin, node_preflight))
    return 0


if __name__ == "__main__":
    if sys.version_info < (3, 11):
        raise SystemExit("Use /opt/homebrew/bin/python3.12; Python >=3.11 is required")
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        raise SystemExit(str(error))
