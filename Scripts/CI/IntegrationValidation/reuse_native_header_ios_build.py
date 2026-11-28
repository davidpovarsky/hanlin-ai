"""Reuse only the authenticated452680 iOS compile, never its zero-test result."""
import hashlib
import json
from pathlib import Path
import shutil

REFERENCE_PATH = "Scripts/CI/Tests/Fixtures/native-tool-header-compile-45268041311"
REFERENCE_SHA256 = "e87046d8b0944d0eb91d7001050ba668b2902210dc43fc2d4131f58ce2ceebea"
SOURCE = "846ca37aaee19f46dccca3cd39c7d6762d2561f4"
PRODUCER = "e7bf34111e603ca977becd007dd4e5bb109af857"
FINGERPRINT = ("select-xcode", "xcode", "swift", "macos-sdk", "ios-sdk", "os")


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError("Header iOS compile reuse rejected: " + message)


def validate_inputs(evidence, reference, *, final=False):
    require(sha(reference / "reference.json") == REFERENCE_SHA256, "frozen manifest changed")
    manifest = read(reference / "reference.json")
    require((manifest["run_id"], manifest["run_attempt"], manifest["source_commit"],
             manifest["producer_commit"], manifest["artifact_id"], manifest["zip_sha256"]) ==
            (45268041311, 1, SOURCE, PRODUCER, 14863913714,
             "59c7487ea235103e043d01a1a67901f5d9b639ad90d929e7d7895a6cd9d44fef"),
            "original identity changed")
    for name, digest in manifest["files_sha256"].items():
        relative = Path(name)
        require(not relative.is_absolute() and ".." not in relative.parts and
                sha(reference / relative) == digest, "original bytes changed: " + name)
    run = read(reference / "terminal-run.json")
    artifact = read(reference / "artifact-receipt.json")
    audit = read(reference / "terminal-audit.json")
    require(run["id"] == 45268041311 and run["run_attempt"] == 1 and
            run["head_sha"] == SOURCE and run["status"] == "completed" and
            artifact["artifact_id"] == 14863913714 and artifact["source"] == SOURCE and
            artifact["zip_sha256"] == manifest["zip_sha256"] and
            artifact["api_digest_verified"] is True and artifact["api_run_source_verified"] is True and
            artifact["zip_crc"] == "PASS" and audit["ios_agent_core_compile"] == "PASS",
            "authenticated original compile binding changed")
    original_status = read(reference / "process-status.json")
    require(original_status["preparation_exit"] == 0 and original_status["ios_build_exit"] == 0,
            "original compile was not successful")
    current = (evidence / "tested-source-commit.txt").read_text().strip()
    require(current == (evidence / "workflow-commit.txt").read_text().strip() and
            (evidence / "producer-commit.txt").read_text().strip() == PRODUCER,
            "current source/workflow/producer binding changed")
    old_sources = read(reference / "tested-source-sha256.json")
    require(len(old_sources) == manifest["source_files"] == 404 and
            read(evidence / "tested-source-sha256.json") == old_sources,
            "any of404 package inputs changed")
    commands = read(evidence / "commands.json")
    original_commands = read(reference / "commands.json")
    require(not any(command["argv"][:2] == ["xcodebuild", "build"] or
                    command["name"] == "IOSBuild" for command in commands),
            "a current iOS compile process was invoked")
    originals = [command for command in original_commands if command["name"] == "IOSBuild"]
    require(len(originals) == 1, "original build process is missing or ambiguous")
    build = originals[0]
    args = build["argv"]
    require(build["exit_code"] == 0 and len(args) == 13 and
            args[:6] == ["xcodebuild", "build", "-scheme", "HanlinAgentCore",
                         "-destination", "generic/platform=iOS Simulator"] and
            args[6] == "-derivedDataPath" and Path(args[7]).name == "IOSDerivedData" and
            args[8] == "-resultBundlePath" and Path(args[9]).name == "IOSBuild.xcresult" and
            args[10:] == ["-skipPackagePluginValidation", "-skipMacroValidation", "CODE_SIGNING_ALLOWED=NO"],
            "original dependent iOS build configuration changed")
    require(Path(build["cwd"]).parts[-2:] == ("Packages", "HanlinAgentSDK"),
            "original compile package differs")
    for stream in ("stdout", "stderr"):
        record = build[stream]
        require(sha(reference / record["file"]) == record["sha256"], "original build log digest differs")
    require("** BUILD SUCCEEDED **" in (reference / build["stdout"]["file"]).read_text(),
            "original command did not report build success")
    fingerprint = {}
    for name in FINGERPRINT:
        old = [command for command in original_commands if command["name"] == name]
        new = [command for command in commands if command["name"] == name]
        require(len(old) == len(new) == 1 and old[0]["exit_code"] == new[0]["exit_code"] == 0 and
                old[0]["argv"] == new[0]["argv"], "toolchain command changed: " + name)
        fingerprint[name] = {}
        for stream in ("stdout", "stderr"):
            previous, observed = old[0][stream], new[0][stream]
            require(sha(reference / previous["file"]) == previous["sha256"] and
                    sha(evidence / observed["file"]) == observed["sha256"] and
                    (reference / previous["file"]).read_bytes() ==
                    (evidence / observed["file"]).read_bytes(), "toolchain fingerprint changed: " + name)
            fingerprint[name][stream] = observed["sha256"]
    locks = {}
    for name in ("sdk", "core"):
        relative = name + "-Package.resolved"
        require((evidence / relative).read_bytes() == (reference / relative).read_bytes(),
                "actual raw dependency lock changed: " + name)
        locks[name] = sha(evidence / relative)
    # The runner retains both actual locks again after tests. Require both
    # originals and current final bytes, not merely a declared revision field.
    for container in ([reference, evidence] if final else [reference]):
        records = read(container / "post-build-resolution.json")
        require(len(records) == 2 and len({record["raw_file"] for record in records}) == 2,
                "both distinct post-execution raw locks are required")
        packages = {}
        for record in records:
            path = Path(record["raw_file"])
            require(not path.is_absolute() and len(path.parts) == 2 and path.parts[0] == "raw-locks" and
                    ".." not in path.parts, "raw lock member escaped")
            package = Path(record["source_path"]).parent.name
            require(package in {"HanlinAgentSDK", "HanlinPlatform"} and package not in packages,
                    "post-execution lock package changed")
            name = "sdk" if package == "HanlinAgentSDK" else "core"
            require(sha(container / path) == record["sha256"] == locks[name] and
                    (container / path).read_bytes() == (reference / (name + "-Package.resolved")).read_bytes(),
                    "post-execution raw lock differs: " + package)
            packages[package] = record["sha256"]
        require(set(packages) == {"HanlinAgentSDK", "HanlinPlatform"}, "both packages are required")
    if final:
        status = read(evidence / "process-status.json")
        require("ios_build_exit" in status and status["ios_build_exit"] is None and
                status.get("ios_build_execution") == "REUSED_VERIFIED",
                "reused compile requires explicit null current exit and a separate reuse label")
    return dict(mode="REUSED_VERIFIED", original_run_id=45268041311, original_run_attempt=1,
                original_source_commit=SOURCE, artifact_id=14863913714,
                zip_sha256=manifest["zip_sha256"], reference_manifest_sha256=REFERENCE_SHA256,
                current_source_commit=current, source_files=404, producer_commit=PRODUCER,
                raw_lock_sha256=locks, toolchain_fingerprint=fingerprint,
                original_build=dict(argv=args, exit_code=0, stdout_sha256=build["stdout"]["sha256"],
                                    stderr_sha256=build["stderr"]["sha256"]),
                current_build_process="NOT_INVOKED", native_model_generation="NOT_RUN")


def prepare_reuse(repository, evidence):
    reference = evidence / "ios-build-reuse-original"
    shutil.copytree(repository / REFERENCE_PATH, reference)
    receipt = validate_inputs(evidence, reference)
    (evidence / "ios-build-reuse.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


def validate_reuse(evidence):
    receipt = validate_inputs(evidence, evidence / "ios-build-reuse-original", final=True)
    require(read(evidence / "ios-build-reuse.json") == receipt, "current compile reuse receipt differs")
    return receipt
