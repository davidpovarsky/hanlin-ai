"""Only resolve the reviewed exact ZIP pin and build HanlinAgentCore on iOS."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile

import verify_native_tool_pin_build as proof


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
    evidence = root / "build/agent-sdk-validation-evidence"
    evidence.mkdir(parents=True, exist_ok=True)
    statuses = dict(preparation_exit=None, ios_resolve_exit=None, ios_build_exit=None,
                    current_test_invocations=0, native15_execution="NOT_ADMITTED",
                    accepted_cases_execution="NOT_ADMITTED", baseline_execution="HISTORICAL_REFERENCE_ONLY",
                    ios_build_execution="NOT_RUN", **{key: None for key in proof.NULL_EXITS})
    commands, scratch = [], None
    environment = os.environ.copy()

    def run(name, argv, cwd=root, check=True, timeout=1200):
        index = len(commands) + 1
        stdout, stderr = (evidence / f"{index:02d}-{name}.{stream}.log" for stream in ("stdout", "stderr"))
        item = dict(name=name, argv=list(map(str, argv)), cwd=str(cwd), started_utc=now())
        with stdout.open("wb") as out, stderr.open("wb") as err:
            process = subprocess.Popen(item["argv"], cwd=cwd, env=environment,
                                       stdout=out, stderr=err, start_new_session=True)
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                code = 124
        item.update(exit_code=code, finished_utc=now(),
                    stdout=dict(file=stdout.name, sha256=sha(stdout)),
                    stderr=dict(file=stderr.name, sha256=sha(stderr)))
        commands.append(item)
        (evidence / "commands.json").write_text(json.dumps(commands, indent=2))
        if check and code:
            raise RuntimeError(f"{name} exited {code}; original logs retained")
        return code, stdout

    def retain_locks(packages, destination, post=False):
        records = []
        for label, package in packages.items():
            path = package / "Package.resolved"
            raw, value = path.read_bytes(), json.loads(path.read_bytes())
            target = evidence / destination / (label + "-Package.resolved") if destination else evidence / (label + "-Package.resolved")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw)
            record = dict(package=label, source_path=str(path), sha256=sha(target), resolved=value)
            record["raw_file" if post else "file"] = str(target.relative_to(evidence))
            records.append(record)
        return records

    def producer_checkouts(packages, phase):
        locations = {name: package / ".build/checkouts/swift-ai-sdk" for name, package in packages.items()}
        locations["xcode"] = scratch / "IOSDerivedData/SourcePackages/checkouts/swift-ai-sdk"
        checkouts = {}
        for name, checkout in locations.items():
            commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=checkout, text=True).strip()
            if commit != proof.PRODUCER:
                raise RuntimeError("Wrong actual producer in " + name)
            _, clean = run(name + "-" + phase + "-producer-status",
                           ["git", "status", "--porcelain", "--untracked-files=all", "--", "Package.swift", "Sources"], cwd=checkout)
            if clean.read_text():
                raise RuntimeError("Actual producer source is dirty in " + name)
            paths = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", commit, "--", "Package.swift", "Sources"],
                                            cwd=checkout, text=True).splitlines()
            digests = {}
            for relative in paths:
                raw = (checkout / relative).read_bytes()
                if raw != subprocess.check_output(["git", "show", commit + ":" + relative], cwd=checkout):
                    raise RuntimeError("Actual producer blob differs: " + relative)
                digests[relative] = hashlib.sha256(raw).hexdigest()
            checkouts[name] = dict(path=str(checkout), commit=commit, status=clean.read_text(), source_sha256=digests)
        (evidence / ("producer-checkouts-" + phase + ".json")).write_text(json.dumps(checkouts, indent=2))
        return locations["xcode"]

    try:
        inputs = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text()).get("inputs", {})
        if inputs.get("exact_test_selector") != proof.SELECTOR or inputs.get("target_validation_group") != "agent_sdk_exact_source_proof":
            raise RuntimeError("Exact reviewed build-only route is required")
        unrelated = {name: inputs.get(name, "false") for name in proof.UNRELATED_FLAGS}
        if any(value is not False and value != "false" for value in unrelated.values()):
            raise RuntimeError("Build-only route cannot enable unrelated workflow flags")
        (evidence / "selected-route.json").write_text(json.dumps(dict(
            exact_test_selector=proof.SELECTOR, target_validation_group="agent_sdk_exact_source_proof",
            current_test_invocations=0, baseline="HISTORICAL_REFERENCE_ONLY", unrelated_flags=unrelated,
            run_id=os.environ.get("GITHUB_RUN_ID"), run_attempt=os.environ.get("GITHUB_RUN_ATTEMPT")), indent=2))
        run("exact-json-vendor", ["python3", "Scripts/CI/verify_exact_json_vendor.py"])
        head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
        for name in ("tested-source-commit.txt", "workflow-commit.txt"):
            (evidence / name).write_text(head + "\n")
        (evidence / "producer-commit.txt").write_text(proof.PRODUCER + "\n")
        proof.prepare_reference(root, evidence)
        manifest, original_proof = proof.reference(evidence)
        scratch = Path(tempfile.mkdtemp(prefix="hanlin-native-pin-build.", dir=os.environ.get("RUNNER_TEMP", "/tmp")))
        archive = evidence / "tested-source.tar"
        with archive.open("wb") as output:
            subprocess.run(["git", "archive", head, "Packages/HanlinAgentSDK", "Packages/HanlinPlatform"],
                           cwd=root, stdout=output, check=True)
        run("extract-source", ["tar", "-xf", archive, "-C", scratch])
        paths = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", head, "--",
                                         "Packages/HanlinAgentSDK", "Packages/HanlinPlatform"], cwd=root, text=True).splitlines()
        digests = {}
        for relative in paths:
            raw = (scratch / relative).read_bytes()
            if raw != subprocess.check_output(["git", "show", head + ":" + relative], cwd=root):
                raise RuntimeError("Archived source differs from exact Git: " + relative)
            digests[relative] = hashlib.sha256(raw).hexdigest()
        if digests != proof.expected_source(manifest, original_proof):
            raise RuntimeError("Current source differs beyond the reviewed exact ZIP constraint")
        (evidence / "tested-source-sha256.json").write_text(json.dumps(digests, indent=2))
        workflow_paths = [
            ".github/workflows/build-ios26-unsigned-ipa.yml", "Scripts/CI/IntegrationValidation/run_agent_sdk.sh",
            "Scripts/CI/IntegrationValidation/run_native_tool_pin_build.py",
            "Scripts/CI/IntegrationValidation/verify_native_tool_pin_build.py",
            "Scripts/CI/IntegrationValidation/verify_native_tool_candidate.py",
            "Scripts/CI/IntegrationValidation/verify_native_tool_cancellation_recheck.py",
            "Scripts/CI/IntegrationValidation/verify_stop_continuation_delta.py",
            "Scripts/CI/IntegrationValidation/xcresult_to_xunit.py", "Scripts/CI/select_stable_xcode.py",
            "Scripts/CI/verify_exact_json_vendor.py",
        ]
        for folder in (proof.REFERENCE_PATH, manifest["proof_repository_path"], manifest["prior_reference_repository_path"]):
            workflow_paths += [str(path.relative_to(root)) for path in sorted((root / folder).rglob("*")) if path.is_file()]
        for relative in workflow_paths:
            if (root / relative).read_bytes() != subprocess.check_output(["git", "show", head + ":" + relative], cwd=root):
                raise RuntimeError("Workflow/proof differs from Git: " + relative)
        (evidence / "workflow-sha256.json").write_text(json.dumps({path: sha(root / path) for path in workflow_paths}, indent=2))
        _, selected = run("select-xcode", ["python3", "Scripts/CI/select_stable_xcode.py"])
        environment["DEVELOPER_DIR"] = str(Path(selected.read_text().strip()) / "Contents/Developer")
        for name, argv in (
            ("xcode", ["xcodebuild", "-version"]), ("swift", ["xcrun", "swift", "--version"]),
            ("macos-sdk", ["xcrun", "--sdk", "macosx", "--show-sdk-version"]),
            ("ios-sdk", ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"]), ("os", ["sw_vers"]),
        ):
            run(name, argv)
        packages = {"sdk": scratch / "Packages/HanlinAgentSDK", "core": scratch / "Packages/HanlinPlatform"}
        for name, package in packages.items():
            run(name + "-resolve", ["xcrun", "swift", "package", "--package-path", package, "resolve"])
        (evidence / "cli-resolution.json").write_text(json.dumps(retain_locks(packages, "cli-locks"), indent=2))
        # This is real resolver work for the exact manifest, before the build.
        # Capture its actual originHash rather than manufacture a lock digest.
        statuses["ios_resolve_exit"], _ = run("XcodeResolve", [
            "xcodebuild", "-resolvePackageDependencies", "-scheme", "HanlinAgentCore",
            "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", scratch / "IOSDerivedData"
        ], cwd=packages["sdk"], check=False)
        if statuses["ios_resolve_exit"]:
            raise RuntimeError("Exact Xcode pre-build resolution failed")
        (evidence / "pre-build-resolution.json").write_text(json.dumps(dict(
            resolver_command="XcodeResolve", captured_utc=now(), locks=retain_locks(packages, "")
        ), indent=2))
        producer = producer_checkouts(packages, "before")
        with (evidence / "producer-source.tar").open("wb") as output:
            subprocess.run(["git", "archive", proof.PRODUCER, "Package.swift", "Sources"], cwd=producer, stdout=output, check=True)
        for relative, digest in digests.items():
            if Path(relative).name != "Package.resolved" and sha(scratch / relative) != digest:
                raise RuntimeError("Source changed during resolution: " + relative)
        reuse = proof.validate_reuse(evidence)
        (evidence / "pin-build-reuse.json").write_text(json.dumps(reuse, indent=2))
        statuses.update(preparation_exit=0, native15_execution="REUSED_VERIFIED",
                        accepted_cases_execution="REUSED_VERIFIED", ios_build_execution="EXECUTED")
        statuses["ios_build_exit"], _ = run("IOSBuild", [
            "xcodebuild", "build", "-scheme", "HanlinAgentCore", "-destination", "generic/platform=iOS Simulator",
            "-derivedDataPath", scratch / "IOSDerivedData", "-resultBundlePath", evidence / "IOSBuild.xcresult",
            "-disableAutomaticPackageResolution", "-skipPackagePluginValidation", "-skipMacroValidation", "CODE_SIGNING_ALLOWED=NO"
        ], cwd=packages["sdk"], check=False)
        producer_checkouts(packages, "after")
        for relative, digest in digests.items():
            if Path(relative).name != "Package.resolved" and sha(scratch / relative) != digest:
                raise RuntimeError("Source changed during current build: " + relative)
    except Exception as error:
        statuses["preparation_exit"] = 1
        (evidence / "preparation-error.txt").write_text(str(error) + "\n")
    finally:
        if scratch is not None:
            try:
                packages = {"sdk": scratch / "Packages/HanlinAgentSDK", "core": scratch / "Packages/HanlinPlatform"}
                (evidence / "post-build-resolution.json").write_text(json.dumps(retain_locks(packages, "raw-locks", post=True), indent=2))
            except Exception as error:
                statuses["preparation_exit"] = 1
                (evidence / "resolution-error.txt").write_text(str(error) + "\n")
        (evidence / "process-status.json").write_text(json.dumps(statuses, indent=2))
        result = proof.summarize(evidence)
        (evidence / "summary.json").write_text(json.dumps(result, indent=2))
        print(json.dumps(result, indent=2))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
