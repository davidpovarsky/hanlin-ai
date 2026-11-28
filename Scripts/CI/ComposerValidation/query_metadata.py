"""Two authorized Apple metadata queries; never build, test, or create a device."""
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zipfile

from prepare_capability_proof import prepare

SOURCE = "e8ccd81452843609285a0cd7e017a759bda6a6ef"
DEVELOPER = Path("/Applications/Xcode_27.2.app/Contents/Developer")
PRIOR_ARTIFACT = 14153149302
PRIOR_SHA256 = "8f9f58e1ab733ebc5b1701dba1cf8d5b1f7c43d656e2f10c5c6e5bdb228f7050"
KEYS = ("SDKROOT", "SUPPORTED_PLATFORMS", "TARGETED_DEVICE_FAMILY", "IPHONEOS_DEPLOYMENT_TARGET")


def now():
    return datetime.now(timezone.utc).isoformat()


def write(path, value):
    path.write_text(json.dumps(value, indent=2), encoding="utf-8")


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args], timeout=120)


def command(folder, name, argv, cwd, env, seconds):
    started = now()
    tick = time.monotonic()
    process = subprocess.Popen(argv, cwd=cwd, env=env, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, start_new_session=True)
    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=seconds)
    except subprocess.TimeoutExpired:
        timed_out = True
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate(timeout=5)
    (folder / f"{name}.stdout").write_bytes(stdout)
    (folder / f"{name}.stderr").write_bytes(stderr)
    receipt = {"argv": argv, "cwd": str(cwd), "DEVELOPER_DIR": str(DEVELOPER),
               "started_at_utc": started, "finished_at_utc": now(),
               "elapsed_seconds": round(time.monotonic() - tick, 3),
               "timeout_seconds": seconds, "timed_out": timed_out,
               "exit_code": process.returncode,
               "stdout_sha256": hashlib.sha256(stdout).hexdigest(),
               "stderr_sha256": hashlib.sha256(stderr).hexdigest()}
    write(folder / f"{name}.receipt.json", receipt)
    return receipt, stdout, stderr


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def retain_prior(folder):
    token = os.environ["GH_TOKEN"]
    request = urllib.request.Request(
        f"https://api.github.com/repos/davidpovarsky/hanlin-ai/actions/artifacts/{PRIOR_ARTIFACT}/zip",
        headers={"Authorization": "Bearer " + token})
    try:
        urllib.request.build_opener(NoRedirect).open(request, timeout=30)
        raise RuntimeError("Expected artifact redirect")
    except urllib.error.HTTPError as error:
        if error.code != 302:
            raise RuntimeError(f"Prior artifact API HTTP {error.code}") from None
        location = error.headers["Location"]
    # The signed artifact request deliberately receives no GitHub Authorization header.
    try:
        with urllib.request.urlopen(location, timeout=30) as response:
            raw = response.read(51070)
    except Exception:
        raise RuntimeError("Prior artifact retrieval failed") from None
    assert len(raw) == 51069 and hashlib.sha256(raw).hexdigest() == PRIOR_SHA256
    archive = zipfile.ZipFile(io.BytesIO(raw))
    prior = folder / "prior-default"
    prior.mkdir()
    hashes = {}
    for name in ["destinations.txt", "scheme.txt", "schemes.json", "Harness-Package.swift",
                 "xcode-version.txt", "ios-simulator-sdk-version.txt", "swift-version.txt"]:
        content = archive.read(name)
        (prior / name).write_bytes(content)
        hashes[name] = hashlib.sha256(content).hexdigest()
    write(folder / "prior-reference.json",
          {"run": 43694776730, "source": "9623d0e63733d66a51b6fc144daa9f84ca987806",
           "artifact": PRIOR_ARTIFACT, "full_zip_sha256_verified": PRIOR_SHA256,
           "file_sha256": hashes, "new_default_query_executed": False})
    return archive


def main():
    if sys.platform != "darwin":
        raise SystemExit("Remote Apple metadata task only; no local staging permitted")
    repo = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
    folder = repo / "build/composer-metadata-evidence"
    folder.mkdir(parents=True, exist_ok=False)
    result = {"scope": "composer-metadata-only", "status": "BLOCKED",
              "builds": 0, "tests": 0, "devices_created": 0,
              "authored_obligations": 12, "authored_NOT_RUN": 12,
              "test_authorization_extended": False, "errors": []}
    try:
        workflow_sha = git(repo, "rev-parse", "HEAD").decode().strip()
        write(folder / "identity.json", {"workflow_source": workflow_sha,
                                        "frozen_component_source": SOURCE,
                                        "owner_packet": "20980c9448f0a5d78eefcaec38da6e92364de37d"})
        paths = [".github/workflows/build-ios26-unsigned-ipa.yml",
                 "Scripts/CI/ComposerValidation/query_metadata.py",
                 "Scripts/CI/ComposerValidation/prepare_capability_proof.py",
                 "Scripts/CI/ComposerValidation/Package.swift"]
        write(folder / "harness-sha256.json",
              {p: hashlib.sha256(git(repo, "show", f"{workflow_sha}:{p}")).hexdigest() for p in paths})
        if subprocess.run(["git", "-C", str(repo), "cat-file", "-e", SOURCE + "^{commit}"],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30).returncode:
            subprocess.run(["git", "-C", str(repo), "fetch", "--no-tags", "--depth=1", "origin", SOURCE],
                           check=True, timeout=120, stdout=subprocess.DEVNULL)
        for path in paths[2:]:
            assert (repo / path).read_bytes() == git(repo, "show", f"{SOURCE}:{path}"), path
        package = Path(tempfile.mkdtemp(prefix="composer-metadata-", dir=os.environ.get("RUNNER_TEMP"))) / "ComposerValidation"
        plan = prepare(repo, SOURCE, package, True)
        assert len(plan["expected_case_ids"]) == 12 and len(plan["input_sha256"]) == 12
        write(folder / "proof-inputs.json", plan)
        (folder / "Harness-Package.swift").write_bytes((package / "Package.swift").read_bytes())
        prior = retain_prior(folder)
        old = json.loads(prior.read("proof-inputs.json"))
        assert plan["input_sha256"] == old["input_sha256"]
        assert (package / "Package.swift").read_bytes() == prior.read("Harness-Package.swift")
        assert prior.read("scheme.txt").decode().strip() == "ComposerValidation"
        info_path = DEVELOPER.parent / "version.plist"
        version = plistlib.loads(info_path.read_bytes())
        sdk_path = DEVELOPER / "Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/SDKSettings.json"
        sdk = json.loads(sdk_path.read_bytes())
        env = {k: v for k, v in os.environ.items()
               if not re.search(r"TOKEN|PASSWORD|SECRET|CREDENTIAL|AUTHORIZATION|PRIVATE_KEY", k, re.I)}
        env["DEVELOPER_DIR"] = str(DEVELOPER)
        context = {"DEVELOPER_DIR": str(DEVELOPER), "xcode_version_plist": version,
                   "xcode_version_plist_sha256": hashlib.sha256(info_path.read_bytes()).hexdigest(),
                   "simulator_sdk": sdk, "simulator_sdk_sha256": hashlib.sha256(sdk_path.read_bytes()).hexdigest(),
                   "environment": {k: env.get(k) for k in [*KEYS, "TOOLCHAINS"]}}
        write(folder / "toolchain-context.json", context)
        observed_version = version.get("CFBundleShortVersionString", version.get("ProductVersion"))
        if observed_version != "27.2" or version.get("ProductBuildVersion") != "27B52" or str(sdk.get("Version")) != "27.2":
            raise RuntimeError(f"Installed toolchain mismatch: Xcode={observed_version}, build={version.get('ProductBuildVersion')}, simulator SDK={sdk.get('Version')}")
        receipt, stdout, _ = command(folder, "swift-version",
            [str(DEVELOPER / "Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"), "--version"],
            package, env, 30)
        assert receipt["exit_code"] == 0 and b"Apple Swift version 6.4.2 " in stdout
        executable = str(DEVELOPER / "usr/bin/xcodebuild")
        first, destinations, _ = command(folder, "sdk-destinations",
            [executable, "-showdestinations", "-scheme", "ComposerValidation", "-sdk", "iphonesimulator"],
            package, env, 120)
        second, settings, _ = command(folder, "sdk-build-settings",
            [executable, "-showBuildSettings", "-json", "-scheme", "ComposerValidation",
             "-sdk", "iphonesimulator", "-destination", "generic/platform=iOS Simulator"],
            package, env, 120)
        result["query_exit_codes"] = [first["exit_code"], second["exit_code"]]
        for label, receipt in [("destinations", first), ("settings", second)]:
            if receipt["timed_out"] or receipt["exit_code"] != 0:
                result["errors"].append(label + " query failed or timed out")
        concrete = [line.strip() for line in destinations.decode(errors="replace").splitlines()
                    if "platform:iOS Simulator" in line and
                    re.search(r"id:\s*[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", line)]
        result["concrete_simulator_destinations"] = concrete
        try:
            data = json.loads(settings)
            assert isinstance(data, list) and data
        except (ValueError, AssertionError):
            data = []
            result["errors"].append("No nonempty JSON build-settings array; raw output retained")
        targets = []
        for item in data:
            values = item.get("buildSettings", {})
            target = {"target": item.get("target"), "settings": {key: values.get(key) for key in KEYS}}
            targets.append(target)
            missing = [key for key in KEYS if key not in values or values[key] in [None, ""]]
            if missing:
                result["errors"].append(f"{item.get('target')}: missing " + ",".join(missing))
        result["target_settings"] = targets
        if not concrete:
            result["errors"].append("No concrete iOS simulator destination confirmed")
        result["status"] = "BLOCKED" if result["errors"] else "METADATA_RECORDED_NOT_TESTED"
    except Exception as error:
        result["errors"].append(type(error).__name__ + ": " + str(error))
    finally:
        write(folder / "summary.json", result)
        print(json.dumps(result, indent=2))
    return 0 if result["status"] == "METADATA_RECORDED_NOT_TESTED" else 1


if __name__ == "__main__":
    raise SystemExit(main())
