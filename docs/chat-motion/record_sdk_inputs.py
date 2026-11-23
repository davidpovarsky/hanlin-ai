"""Source/resource accounting for the actual selected SDK and resolved dependencies."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def run(arguments):
    return subprocess.run(arguments, text=True, capture_output=True, check=True).stdout.strip()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_record(root, path):
    file = root / path
    if not file.is_file():
        raise ValueError(f"A recorded SDK input is not materialized: {path}")
    result = {"path": path, "bytes": file.stat().st_size, "sha256": digest(file.read_bytes())}
    if file.is_symlink():
        result["symlink"] = str(file.readlink())
    return result


def tracked_records(root, paths):
    raw = run(["git", "-C", str(root), "ls-files", "-z", "--", *paths])
    names = sorted(set(filter(None, raw.split("\0"))))
    if not names:
        raise ValueError("The selected SDK source closure must contain tracked files")
    return [file_record(root, name) for name in names]


def record_profile(proof, source):
    sdk = proof / "Vendor/HanlinSDK"
    installation = json.loads((sdk / ".hanlin-sdk/installation.json").read_text())
    lock = json.loads((proof / "HanlinSDK.lock.json").read_text())
    if installation["revision"] != lock["revision"] or installation["products"] != lock["products"]:
        raise ValueError("Installed SDK profile differs from the fixture lock")
    if run(["git", "-C", str(sdk), "rev-parse", "HEAD"]) != lock["revision"]:
        raise ValueError("Installed SDK source revision differs from the fixture lock")
    generated = json.loads((sdk / "docs/agent-sdk/unified-package-manifest.json").read_text())
    sdk_files = tracked_records(sdk, installation["sourcePaths"])
    # Record all graph inputs, including manifests and the original remote pins.
    graph_paths = sorted(set(generated["inputs"]) | {
        "Scripts/SDK/generate_manifest.py", "Scripts/SDK/install.py",
        "Scripts/CI/IntegrationValidation/project_graph.py",
        "AI_HLY.xcodeproj/project.pbxproj",
        "AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"})
    graph_files = [file_record(sdk, path) for path in graph_paths]
    for path, expected in installation["generatedSHA256"].items():
        if digest((sdk / path).read_bytes()) != expected:
            raise ValueError("Generated SDK profile changed after installation: " + path)
    harness_paths = ["docs/chat-motion/" + name for name in [
        "MotionUI/App.swift", "MotionUI/MotionUITests.swift", "prepare_motion_ui.py",
        "record_sdk_inputs.py", "run_motion_ui.sh", "record_ui_run.py", "collect_motion_result.py"]]
    harness = [file_record(source, path) for path in harness_paths]
    for item in harness:
        original = subprocess.run(["git", "-C", str(source), "show", lock["revision"] + ":" + item["path"]],
                                  capture_output=True, check=False)
        item["matchesRecordedRevision"] = original.returncode == 0 and digest(original.stdout) == item["sha256"]
    return {
        "schemaVersion": 2,
        "scope": "Original Motion components through actual shared SDK; full app/renderer/engine/scroll/physical acceptance is separate",
        "sourceRevision": lock["revision"], "selectedProducts": lock["products"],
        "productionOwnership": "Canonical selected-product Git checkout; no extracted or copied production component bodies",
        "fixtureInputs": harness, "fixtureMatchesRecordedRevision": all(x["matchesRecordedRevision"] for x in harness),
        "sdkGraphInputs": graph_files, "sdkSourcePaths": installation["sourcePaths"],
        "sdkSourceAndResourceFiles": sdk_files,
        "sdkSourceAndResourceSHA256": digest(json.dumps(sdk_files, sort_keys=True).encode()),
        "generatedSHA256": installation["generatedSHA256"],
        "projectSpecSHA256": digest((proof / "project.json").read_bytes()),
        "runtimeBinaryTargets": installation["binaryTargets"],
        "externalDependencies": "Pinned by generated manifest; actual resolved checkouts and packaged bundle bytes recorded after build",
        "nativeExecution": "NOT_RUN_BY_PREPARATION"}


def record_resolved(proof, derived_data, evidence):
    original = json.loads((evidence / "proof-inputs.json").read_text())
    if not original["fixtureMatchesRecordedRevision"]:
        raise ValueError("Native acceptance requires the exact recorded fixture source revision")
    sdk = proof / "Vendor/HanlinSDK"
    current = tracked_records(sdk, original["sdkSourcePaths"])
    if current != original["sdkSourceAndResourceFiles"]:
        raise ValueError("Selected SDK source/resource bytes changed during the native build")
    for path, expected in original["generatedSHA256"].items():
        if digest((sdk / path).read_bytes()) != expected:
            raise ValueError("Selected SDK manifest changed during the native build")
    locks = list((proof / "ChatMotionProof.xcodeproj").rglob("Package.resolved"))
    if len(locks) != 1:
        raise ValueError("Expected one actual Xcode-resolved dependency lock")
    lock_data = locks[0].read_bytes()
    (evidence / "motion-Package.resolved").write_bytes(lock_data)
    pins = json.loads(lock_data)["pins"]
    dependencies = []
    checkout_root = derived_data / "SourcePackages/checkouts"
    for checkout in sorted(checkout_root.iterdir()):
        if not checkout.is_dir():
            continue
        revision = run(["git", "-C", str(checkout), "rev-parse", "HEAD"])
        matching = [pin for pin in pins if pin["state"].get("revision") == revision]
        exact = [pin for pin in matching if pin["identity"].casefold() == checkout.name.casefold()]
        selected = exact or matching
        if len(selected) != 1:
            raise ValueError("Resolved checkout is not bound to exactly one dependency pin: " + checkout.name)
        if run(["git", "-C", str(checkout), "status", "--porcelain", "--untracked-files=no"]):
            raise ValueError("Resolved dependency has tracked source edits: " + checkout.name)
        files = tracked_records(checkout, ["."])
        dependencies.append({"identity": selected[0]["identity"], "revision": revision,
                             "files": files, "filesSHA256": digest(json.dumps(files, sort_keys=True).encode())})
    if {item["identity"] for item in dependencies} != {pin["identity"] for pin in pins}:
        raise ValueError("Resolved dependency lock and actual checkout inventory differ")
    apps = list((derived_data / "Build/Products").glob("*/ChatMotionProof.app"))
    if len(apps) != 1:
        raise ValueError("Expected one built original Motion fixture app")
    bundles = []
    for bundle in sorted(apps[0].rglob("*.bundle")):
        if bundle.is_dir():
            files = [file_record(bundle, path.relative_to(bundle).as_posix())
                     for path in sorted(bundle.rglob("*")) if path.is_file()]
            bundles.append({"path": bundle.relative_to(apps[0]).as_posix(), "files": files})
    expected = {"HanlinSDK_HanlinLocalization.bundle", "HanlinSDK_HanlinRichUI.bundle", "HanlinSDK_HanlinChatUI.bundle"}
    if not expected.issubset({Path(item["path"]).name for item in bundles}):
        raise ValueError("The built fixture is missing a selected canonical SDK resource bundle")
    receipt = {"schemaVersion": 1, "status": "SOURCE_AND_RESOLVED_INPUTS_RECORDED",
               "sourceRevision": original["sourceRevision"], "selectedProducts": original["selectedProducts"],
               "generatedSHA256": original["generatedSHA256"],
               "sdkSourceAndResourceSHA256": original["sdkSourceAndResourceSHA256"],
               "resolvedLockSHA256": digest(lock_data), "resolvedDependencies": dependencies,
               "packagedResourceBundles": bundles, "nativeAcceptance": "NOT_CLAIMED_BY_SOURCE_ACCOUNTING"}
    (evidence / "sdk-resolved-inputs.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return {"status": receipt["status"], "resolvedDependencies": len(dependencies),
            "resourceBundles": len(bundles), "sourceRevision": receipt["sourceRevision"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--proof", type=Path, required=True)
    parser.add_argument("--derived-data", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(record_resolved(args.proof, args.derived_data, args.evidence), indent=2))


if __name__ == "__main__":
    main()
