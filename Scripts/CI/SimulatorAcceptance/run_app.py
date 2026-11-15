"""Execute the actual Release app's frozen UI coverage on isolated iOS 27 devices."""
from __future__ import annotations

import json
import os
from pathlib import Path
import platform
import plistlib
import subprocess
import sys
import tempfile

import gate


def command(args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def logged(args, log: Path, env=None):
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w", encoding="utf-8") as stream:
        try:
            return subprocess.run(args, stdout=stream, stderr=subprocess.STDOUT, env=env,
                                  timeout=1800 if "build-for-testing" in args else 900 if "test-without-building" in args else 120).returncode
        except subprocess.TimeoutExpired:
            stream.write("\nCommand timed out; no successful execution is inferred.\n")
            return 124


def snapshot(repo: Path):
    changed = gate.git(repo, "diff", "--name-only").splitlines()
    gate.require(not [p for p in changed if Path(p).suffix in {".swift", ".m", ".mm", ".h", ".py", ".sh", ".yml", ".xcscheme", ".pbxproj"}], "Prepared inputs modified tracked implementation/build source")
    paths = [repo / p for p in ["RuntimeDependencies.lock.json", "AI_HLY/RuntimeHostResources.zip", "AI_HLY/Downstream/RuntimeCore/Resources/RuntimeManifest.json", "build/nativescript-metadata-tool/provenance.json"]]
    paths += list((repo / "AI_HLY.xcodeproj").rglob("Package.resolved"))
    for folder in (repo / "Packages").glob("*/Artifacts"):
        paths += [p for p in folder.rglob("*") if p.is_file()]
    result = {}
    for path in paths:
        gate.require(path.is_file(), f"Prepared input missing: {path.relative_to(repo)}")
        import hashlib
        h = hashlib.sha256()
        with path.open("rb") as stream:
            for part in iter(lambda: stream.read(1024 * 1024), b""):
                h.update(part)
        result[path.relative_to(repo).as_posix()] = h.hexdigest()
    return {"source_sha": gate.git(repo, "rev-parse", "HEAD"), "source_tree": gate.git(repo, "rev-parse", "HEAD^{tree}"), "prepared_sha256": result}


def map_attachments(folder: Path, expected):
    """Associate screenshots using the tool's retained test attachment manifest.

    Unknown export formats produce no association and fail the acceptance gate.
    A screenshot of the final simulator screen is never substituted for a case.
    """
    manifest = folder / "screenshots/manifest.json"
    data = gate.read(manifest)
    result = {}
    for record in gate.nodes(data):
        markers = [value for key, value in record.items() if key in {"testName", "testIdentifier", "testIdentifierString"} and isinstance(value, str)]
        matches = [identity for identity in expected if any(identity in marker or marker.removesuffix("()") == identity.rsplit("/", 1)[-1] for marker in markers)]
        if len(matches) != 1:
            continue
        files = []
        for child in gate.nodes(record):
            for value in child.values():
                if isinstance(value, str) and value.lower().endswith((".png", ".jpg", ".jpeg")):
                    path = gate.safe_path(folder / "screenshots", value)
                    if path.is_file():
                        files.append(path.relative_to(folder).as_posix())
        if files:
            result.setdefault(matches[0], []).extend(sorted(set(files)))
    gate.write(folder / "case-attachments.json", result)


def main():
    repo = Path.cwd().resolve()
    evidence = Path(os.environ["UI_ACCEPTANCE_EVIDENCE"]).resolve()
    build_number = os.environ["BUILD_NUMBER"]
    policy = gate.read(gate.POLICY_PATH)
    plan = gate.read(evidence / "plan.json")
    gate.require(platform.system() == "Darwin", "Actual Mac required; no Windows simulator proof")
    gate.require(gate.git(repo, "rev-parse", "HEAD") == plan["candidate_source_sha"], "Source changed since coverage freeze")
    xcode = command(["xcodebuild", "-version"])
    sdk = command(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"])
    gate.require(xcode.startswith("Xcode 27.") and "beta" not in xcode.lower() and sdk.startswith("27."), "Stable Xcode/iOS Simulator 27 required")
    gate.write(evidence / "toolchain.json", {"xcode": xcode, "sdk": sdk, "swift": command(["xcrun", "swift", "--version"]), "host": command(["sw_vers"]), "runner_os": platform.system()})
    inventory = json.loads(command(["xcrun", "simctl", "list", "-j"]))
    gate.write(evidence / "simulators-before.json", inventory)
    runtime = next(r["identifier"] for r in inventory["runtimes"] if r.get("isAvailable") and r["version"].split(".")[0] == "27" and "iOS" in r["identifier"])
    scratch = Path(tempfile.mkdtemp(prefix="hanlin-app-ui-", dir=os.environ.get("RUNNER_TEMP")))
    derived = scratch / "DerivedData"
    common = ["-project", policy["project"], "-scheme", policy["scheme"], "-configuration", policy["configuration"], "-derivedDataPath", str(derived), "-skipPackagePluginValidation", "-skipMacroValidation", "CODE_SIGNING_ALLOWED=NO", f"CURRENT_PROJECT_VERSION={build_number}"]
    try:
        status = logged(["xcodebuild", "build-for-testing", *common, "-destination", "generic/platform=iOS Simulator", "-only-testing:AI_HLYUITests", "-resultBundlePath", str(evidence / "Build.xcresult")], evidence / "build.log")
        gate.require(status == 0, "Actual app build-for-testing failed; required UI cases NOT_RUN")
        app = derived / "Build/Products/Release-iphonesimulator/AI_Hanlin.app"
        info = plistlib.loads((app / "Info.plist").read_bytes())
        gate.require(info["CFBundleIdentifier"] == policy["app_bundle_id"] and str(info["CFBundleVersion"]) == build_number, "Built app identity/version mismatch")
        gate.write(evidence / "built-app-info.json", {"bundle_id": info["CFBundleIdentifier"], "build_number": info["CFBundleVersion"], "configuration": policy["configuration"]})
        gate.write(evidence / "prepared-inputs.json", snapshot(repo))
        locks = evidence / "raw-locks"
        locks.mkdir(exist_ok=True)
        for number, path in enumerate((repo / "AI_HLY.xcodeproj").rglob("Package.resolved")):
            (locks / f"{number:02d}-Package.resolved").write_bytes(path.read_bytes())
        for variant in plan["variants"]:
            folder = evidence / variant["id"]
            folder.mkdir(exist_ok=True)
            family = variant["family"]
            types = [t for t in inventory["devicetypes"] if t["name"].startswith(family)]
            available = [d for d in inventory["devices"].get(runtime, []) if d.get("isAvailable") and d["name"].startswith(family)]
            kind = next((d.get("deviceTypeIdentifier") or next(t["identifier"] for t in types if t["name"] == d["name"]) for d in available), types[-1]["identifier"])
            device = command(["xcrun", "simctl", "create", "Hanlin-App-Acceptance-" + variant["id"], kind, runtime])
            original_ids = {d["udid"] for items in inventory["devices"].values() for d in items}
            gate.require(device not in original_ids, "Refusing an existing/personal simulator")
            context = {"source_sha": plan["candidate_source_sha"], "build_number": build_number, "bundle_id": info["CFBundleIdentifier"], "configuration": policy["configuration"], "family": family, "locale": variant["locale"], "device_udid": device, "runtime_identifier": runtime, "sdk_version": sdk, "xcode_version": xcode, "runner_os": platform.system(), "xcodebuild_exit_code": None}
            gate.write(folder / "context.json", context)
            try:
                subprocess.run(["xcrun", "simctl", "boot", device], check=True)
                gate.require(logged(["xcrun", "simctl", "bootstatus", device, "-b"], folder / "boot.log") == 0, "Simulator did not boot")
                container = subprocess.run(["xcrun", "simctl", "get_app_container", device, policy["app_bundle_id"], "data"], capture_output=True, text=True, timeout=30)
                gate.require(container.returncode != 0, "Refusing preexisting app data before destructive acceptance fixture")
                gate.write(folder / "device-creation.json", {"device_udid": device, "created_by_this_run": True, "was_in_original_inventory": False, "preexisting_app_container": False, "fixture_reseeds_each_launch": True, "relaunch_persistence_coverage": False})
                env = dict(os.environ, TEST_RUNNER_HANLIN_SIM_ACCEPTANCE_LOCALE=variant["locale"], TEST_RUNNER_HANLIN_SIM_ACCEPTANCE_FAMILY=family)
                selectors = [f"-only-testing:{selector}" for selector in variant["selectors"]]
                context["xcodebuild_exit_code"] = logged(["xcodebuild", "test-without-building", *common, "-destination", f"platform=iOS Simulator,id={device}", "-parallel-testing-enabled", "NO", "-resultBundlePath", str(folder / "Tests.xcresult"), *selectors], folder / "test.log", env)
                gate.write(folder / "context.json", context)
                if (folder / "Tests.xcresult").exists():
                    with (folder / "tests.json").open("w") as stream:
                        subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(folder / "Tests.xcresult"), "--format", "json"], stdout=stream, stderr=subprocess.STDOUT)
                    logged(["xcrun", "xcresulttool", "export", "attachments", "--path", str(folder / "Tests.xcresult"), "--output-path", str(folder / "screenshots")], folder / "attachments-export.log")
                    try:
                        map_attachments(folder, [s.split("/", 1)[1] for s in variant["selectors"]])
                    except (OSError, ValueError) as error:
                        gate.write(folder / "attachment-mapping-error.json", {"reason": str(error)})
            finally:
                logged(["xcrun", "simctl", "spawn", device, "log", "show", "--last", "3m", "--style", "compact", "--predicate", 'process == "AI_Hanlin"'], folder / "app.log")
                subprocess.run(["xcrun", "simctl", "shutdown", device], check=False)
        gate.require(snapshot(repo) == gate.read(evidence / "prepared-inputs.json"), "Inputs changed during UI execution")
        result = gate.verify(evidence, build_number, plan["candidate_source_sha"])
        print(json.dumps({"status": result["status"], "counts": result["counts"]}))
    finally:
        gate.write(evidence / "summary.json", gate.summarize(evidence, plan, policy))


if __name__ == "__main__":
    try:
        main()
    except (gate.GateError, OSError, KeyError, StopIteration, subprocess.CalledProcessError) as error:
        print(f"UI acceptance blocked: {error}", file=sys.stderr)
        sys.exit(1)
