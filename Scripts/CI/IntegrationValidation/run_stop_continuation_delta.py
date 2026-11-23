"""Run only the three new composed original-engine continuation controls."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile

from verify_stop_continuation_delta import COMPOSED_SOURCE, SELECTORS, summarize

PRODUCER = "07431abccbfb151ca2dab67bca6cf86fcb2bd3b8"



def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
    evidence = root / "build/agent-sdk-validation-evidence"
    evidence.mkdir(parents=True, exist_ok=True)
    statuses = dict(preparation_exit=None, delta_test_exit=None, ios_build_exit=None,
                    baseline_core_exit=None, core_test_exit=None, sdk_test_exit=None)
    commands = []
    scratch = None
    cancellation_recheck = False
    environment = os.environ.copy()

    def run(name, argv, cwd=root, check=True, timeout=1200):
        index = len(commands) + 1
        stdout = evidence / f"{index:02d}-{name}.stdout.log"
        stderr = evidence / f"{index:02d}-{name}.stderr.log"
        command = dict(name=name, argv=list(map(str, argv)), cwd=str(cwd),
                       started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
        with stdout.open("wb") as out, stderr.open("wb") as err:
            process = subprocess.Popen(command["argv"], cwd=cwd, env=environment,
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
        command.update(exit_code=code, finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                       stdout={"file": stdout.name, "sha256": sha(stdout)},
                       stderr={"file": stderr.name, "sha256": sha(stderr)})
        commands.append(command)
        (evidence / "commands.json").write_text(json.dumps(commands, indent=2))
        if check and code:
            raise RuntimeError(f"{name} exited {code}; see the retained original logs")
        return code, stdout

    try:
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
        inputs = event.get("inputs", {})
        selector = inputs.get("exact_test_selector")
        if selector not in {"HanlinStopContinuationDelta", "HanlinNativeToolCancellationRecheck"} or inputs.get("target_validation_group") != "agent_sdk_exact_source_proof":
            raise RuntimeError("Native candidate validation requires the exact reviewed opt-in route")
        cancellation_recheck = selector == "HanlinNativeToolCancellationRecheck"
        if cancellation_recheck:
            from verify_native_tool_cancellation_recheck import (
                REFERENCE_PATH, CORE_EXPECTED, SDK_EXPECTED, CORE_SELECTORS, SDK_SELECTORS, UNRELATED_FLAGS,
                prepare_reuse, summarize as summarize_cancellation,
            )
            from verify_native_tool_candidate import read_cases
            statuses.update(native_core_test_exit=None, native_sdk_test_exit=None,
                            baseline_execution="HISTORICAL_REFERENCE_ONLY")
        (evidence / "selected-route.json").write_text(json.dumps(dict(
            exact_test_selector=selector, target_validation_group=inputs["target_validation_group"],
            baseline="HISTORICAL_REFERENCE_ONLY" if cancellation_recheck else "NOT_SELECTED",
            run_id=os.environ.get("GITHUB_RUN_ID"), run_attempt=os.environ.get("GITHUB_RUN_ATTEMPT")), indent=2))
        if cancellation_recheck:
            unrelated = {name: inputs.get(name, "false") for name in UNRELATED_FLAGS}
            if any(value is not False and value != "false" for value in unrelated.values()):
                raise RuntimeError("Native cancellation route cannot enable unrelated workflow flags")
            route_path = evidence / "selected-route.json"
            route = json.loads(route_path.read_text())
            route["unrelated_flags"] = unrelated
            route_path.write_text(json.dumps(route, indent=2))
        run("exact-json-vendor", ["python3", "Scripts/CI/verify_exact_json_vendor.py"])
        head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
        (evidence / "tested-source-commit.txt").write_text(head + "\n")
        (evidence / "workflow-commit.txt").write_text(head + "\n")
        (evidence / "producer-commit.txt").write_text(PRODUCER + "\n")
        scratch = Path(tempfile.mkdtemp(prefix="hanlin-stop-continuation.", dir=os.environ.get("RUNNER_TEMP", "/tmp")))
        archive = evidence / "tested-source.tar"
        with archive.open("wb") as output:
            subprocess.run(["git", "archive", head, "Packages/HanlinAgentSDK", "Packages/HanlinPlatform"],
                           cwd=root, stdout=output, check=True)
        run("extract-source", ["tar", "-xf", archive, "-C", scratch])
        paths = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", head, "--",
                                         "Packages/HanlinAgentSDK", "Packages/HanlinPlatform"], cwd=root, text=True).splitlines()
        digests = {}
        for relative in paths:
            path = scratch / relative
            expected = subprocess.check_output(["git", "show", head + ":" + relative], cwd=root)
            if path.read_bytes() != expected:
                raise RuntimeError("Archived source differs from Git: " + relative)
            digests[relative] = sha(path)
        (evidence / "tested-source-sha256.json").write_text(json.dumps(digests, indent=2))
        if cancellation_recheck:
            expected_source = json.loads((root / REFERENCE_PATH / "current-source-sha256.json").read_text())
            if digests != expected_source:
                raise RuntimeError("Composed cancellation package source differs from the reviewed snapshot")
        elif any(digests.get(path) != digest for path, digest in COMPOSED_SOURCE.items()):
            raise RuntimeError("Composed boundary/header sources do not match the reviewed candidate")
        workflow_paths = [".github/workflows/build-ios26-unsigned-ipa.yml",
                          "Scripts/CI/IntegrationValidation/run_agent_sdk.sh",
                          "Scripts/CI/IntegrationValidation/run_stop_continuation_delta.py",
                          "Scripts/CI/IntegrationValidation/verify_native_tool_candidate.py",
                          "Scripts/CI/IntegrationValidation/verify_stop_continuation_delta.py",
                          "Scripts/CI/verify_exact_json_vendor.py",
                          "Scripts/CI/IntegrationValidation/xcresult_to_xunit.py",
                          "Scripts/CI/select_stable_xcode.py"]
        if cancellation_recheck:
            workflow_paths += ["Scripts/CI/IntegrationValidation/verify_native_tool_cancellation_recheck.py"]
            workflow_paths += [str(path.relative_to(root)) for path in sorted((root / REFERENCE_PATH).rglob("*")) if path.is_file()]
        for relative in workflow_paths:
            if (root / relative).read_bytes() != subprocess.check_output(["git", "show", head + ":" + relative], cwd=root):
                raise RuntimeError("Workflow source differs from Git: " + relative)
        (evidence / "workflow-sha256.json").write_text(json.dumps({p: sha(root / p) for p in workflow_paths}, indent=2))
        _, selected = run("select-xcode", ["python3", "Scripts/CI/select_stable_xcode.py"])
        environment["DEVELOPER_DIR"] = str(Path(selected.read_text().strip()) / "Contents/Developer")
        for name, command in [
            ("xcode", ["xcodebuild", "-version"]),
            ("swift", ["xcrun", "swift", "--version"]),
            ("macos-sdk", ["xcrun", "--sdk", "macosx", "--show-sdk-version"]),
            ("ios-sdk", ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"]),
            ("os", ["sw_vers"]),
        ]:
            run(name, command)
        sdk, core = scratch / "Packages/HanlinAgentSDK", scratch / "Packages/HanlinPlatform"
        for name, package in [("sdk", sdk), ("core", core)]:
            run(name + "-resolve", ["xcrun", "swift", "package", "--package-path", package, "resolve"])
        producer = sdk / ".build/checkouts/swift-ai-sdk"
        if subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=producer, text=True).strip() != PRODUCER:
            raise RuntimeError("Resolved producer checkout is not the pinned commit")
        run("producer-clean", ["git", "diff", "--exit-code", PRODUCER, "--", "Package.swift", "Sources"], cwd=producer)
        if cancellation_recheck:
            checkouts = {}
            for name, package in (("sdk", sdk), ("core", core)):
                checkout = package / ".build/checkouts/swift-ai-sdk"
                commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=checkout, text=True).strip()
                if commit != PRODUCER:
                    raise RuntimeError("Wrong actual producer checkout for " + name)
                _, clean = run(name + "-producer-status", [
                    "git", "status", "--porcelain", "--untracked-files=all", "--", "Package.swift", "Sources"
                ], cwd=checkout)
                if clean.read_text() != "":
                    raise RuntimeError("Producer source checkout is not clean for " + name)
                producer_paths = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", PRODUCER,
                    "--", "Package.swift", "Sources"], cwd=checkout, text=True).splitlines()
                checkouts[name] = dict(path=str(checkout), commit=commit, status=clean.read_text(),
                    source_sha256={relative: sha(checkout / relative) for relative in producer_paths})
            (evidence / "producer-checkouts.json").write_text(json.dumps(checkouts, indent=2))
        with (evidence / "producer-source.tar").open("wb") as output:
            subprocess.run(["git", "archive", PRODUCER, "Package.swift", "Sources", "Tests"], cwd=producer, stdout=output, check=True)
        locks = []
        for name, package in [("sdk", sdk), ("core", core)]:
            lock = package / "Package.resolved"
            data = json.loads(lock.read_text())
            pins = [p for p in data["pins"] if p["identity"] == "swift-ai-sdk"]
            if len(pins) != 1 or pins[0]["state"]["revision"] != PRODUCER:
                raise RuntimeError("Wrong resolved producer for " + name)
            destination = evidence / (name + "-Package.resolved")
            destination.write_bytes(lock.read_bytes())
            locks.append(dict(package=name, sha256=sha(destination), file=destination.name, resolved=data))
        (evidence / "resolution.json").write_text(json.dumps(locks, indent=2))

        def scheme(package, candidates):
            _, output = run(package.name + "-schemes", ["xcodebuild", "-list", "-json"], cwd=package)
            data = json.loads(output.read_text())
            names = data.get("workspace", {}).get("schemes", []) + data.get("project", {}).get("schemes", [])
            return next(name for name in candidates if name in names)

        core_scheme = scheme(core, ["HanlinPlatform-Package", "HanlinPlatform"])
        if cancellation_recheck:
            sdk_scheme = scheme(sdk, ["HanlinAgentSDK-Package", "HanlinAgentSDK"])
        common = ["-skipPackagePluginValidation", "-skipMacroValidation", "CODE_SIGNING_ALLOWED=NO"]

        def test(result, package, selected_scheme, selectors):
            command = ["xcodebuild", "test", "-scheme", selected_scheme, "-destination", "platform=macOS",
                       "-derivedDataPath", scratch / "MacDerivedData",
                       "-resultBundlePath", evidence / (result + ".xcresult"), *common]
            command += ["-only-testing:" + value for value in selectors]
            code, _ = run(result, command, cwd=package, check=False)
            bundle = evidence / (result + ".xcresult")
            if bundle.exists():
                _, output = run(result + "-cases", ["xcrun", "xcresulttool", "get", "test-results", "tests",
                                "--path", bundle, "--format", "json"], check=False)
                (evidence / (result + ".json")).write_bytes(output.read_bytes())
                if cancellation_recheck:
                    suites = CORE_EXPECTED if result == "NativeCoreTests" else SDK_EXPECTED
                    parameterized = {suite + "/" + name for suite, methods in suites.items()
                                     for name, arguments in methods.items() if arguments is not None}
                    seen, exports = set(), []
                    for case in read_cases(evidence, result)[0]:
                        identifier = case.get("nodeIdentifier")
                        if not isinstance(identifier, str) or identifier.split("(", 1)[0] not in parameterized or identifier in seen:
                            continue
                        seen.add(identifier)
                        detail_code, detail_output = run(result + "-arguments-" + str(len(exports)), [
                            "xcrun", "xcresulttool", "get", "test-results", "test-details",
                            "--path", bundle, "--test-id", identifier, "--format", "json"
                        ], check=False, timeout=120)
                        exports.append(dict(method=identifier, exit_code=detail_code,
                                            raw_file=detail_output.name, sha256=sha(detail_output)))
                    (evidence / (result + "-argument-detail-exports.json")).write_text(json.dumps(exports, indent=2))
            return code

        statuses["preparation_exit"] = 0
        for relative, digest in digests.items():
            if Path(relative).name == "Package.resolved":
                continue  # The actual resolved locks are retained and verified separately.
            if sha(scratch / relative) != digest:
                raise RuntimeError("Candidate source was not fully restored before acceptance: " + relative)
        if cancellation_recheck:
            prepare_reuse(root, evidence)
            statuses["accepted_cases_execution"] = "REUSED_VERIFIED"
            statuses["native_core_test_exit"] = test("NativeCoreTests", core, core_scheme, CORE_SELECTORS)
            statuses["native_sdk_test_exit"] = test("NativeSDKTests", sdk, sdk_scheme, SDK_SELECTORS)
            statuses["ios_build_execution"] = "EXECUTED"
        else:
            statuses["delta_test_exit"] = test("StopContinuationTests", core, core_scheme, SELECTORS)
        statuses["ios_build_exit"], _ = run("IOSBuild", [
            "xcodebuild", "build", "-scheme", "HanlinAgentCore", "-destination", "generic/platform=iOS Simulator",
            "-derivedDataPath", scratch / "IOSDerivedData", "-resultBundlePath", evidence / "IOSBuild.xcresult", *common
        ], cwd=sdk, check=False)
    except Exception as error:
        statuses["preparation_exit"] = 1
        (evidence / "preparation-error.txt").write_text(str(error) + "\n")
    finally:
        if scratch is not None:
            try:
                folder = evidence / "raw-locks"
                folder.mkdir(exist_ok=True)
                retained = []
                for path in scratch.rglob("Package.resolved"):
                    if any(part in [".build", "checkouts", "DerivedData"] for part in path.relative_to(scratch).parts):
                        continue
                    raw = path.read_bytes()
                    data = json.loads(raw)
                    pins = [pin for pin in data["pins"] if pin["identity"] == "swift-ai-sdk"]
                    if len(pins) != 1 or pins[0]["state"]["revision"] != PRODUCER:
                        raise RuntimeError("Actual post-build lock does not retain the producer pin: " + str(path))
                    destination = folder / f"{len(retained):02d}-Package.resolved"
                    destination.write_bytes(raw)
                    retained.append(dict(source_path=str(path), raw_file=str(destination.relative_to(evidence)),
                                         sha256=sha(destination), resolved=data))
                (evidence / "post-build-resolution.json").write_text(json.dumps(retained, indent=2))
                if statuses["preparation_exit"] == 0 and not retained:
                    raise RuntimeError("No actual post-build resolved locks were retained")
            except Exception as error:
                statuses["preparation_exit"] = 1
                (evidence / "resolution-error.txt").write_text(str(error) + "\n")
        (evidence / "process-status.json").write_text(json.dumps(statuses, indent=2))
        result = summarize_cancellation(evidence) if cancellation_recheck else summarize(evidence)
        (evidence / "summary.json").write_text(json.dumps(result, indent=2))
        print(json.dumps(result, indent=2))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
