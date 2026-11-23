"""Run only the SDK02 candidate's new original-source controls on the existing Apple job."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile

from verify_native_tool_candidate import EXPECTED, read_cases, summarize
from reuse_native_tool_baseline import REFERENCE_PATH, prepare_reuse

BASE = "7523f45cf8ea180a8e30f511ff0fbd3bb5ccae6d"
PRODUCER = "e7bf34111e603ca977becd007dd4e5bb109af857"
VARIANT_FILES = [
    "Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinAISDKAgentEngine.swift",
    "Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinAISDKModels.swift",
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
    evidence = root / "build/agent-sdk-validation-evidence"
    evidence.mkdir(parents=True, exist_ok=True)
    statuses = dict(preparation_exit=None, baseline_core_exit=None, core_test_exit=None,
                    sdk_test_exit=None, ios_build_exit=None)
    commands = []
    scratch = None
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
        if selector not in {"HanlinNativeToolCandidate", "HanlinNativeToolCandidateRecheck"} or inputs.get("target_validation_group") != "agent_sdk_exact_source_proof":
            raise RuntimeError("Native candidate validation requires the exact reviewed opt-in route")
        reuse_baseline = selector == "HanlinNativeToolCandidateRecheck"
        (evidence / "selected-route.json").write_text(json.dumps(dict(
            exact_test_selector=selector, target_validation_group=inputs["target_validation_group"],
            baseline="REUSE_REQUESTED" if reuse_baseline else "FRESH_REQUESTED",
            run_id=os.environ.get("GITHUB_RUN_ID"), run_attempt=os.environ.get("GITHUB_RUN_ATTEMPT")), indent=2))
        run("exact-json-vendor", ["python3", "Scripts/CI/verify_exact_json_vendor.py"])
        head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
        (evidence / "tested-source-commit.txt").write_text(head + "\n")
        (evidence / "workflow-commit.txt").write_text(head + "\n")
        (evidence / "producer-commit.txt").write_text(PRODUCER + "\n")
        run("baseline-source-fetch", ["git", "fetch", "--refmap=", "--no-tags", "--depth=1", "origin", BASE])
        scratch = Path(tempfile.mkdtemp(prefix="hanlin-native-tool-candidate.", dir=os.environ.get("RUNNER_TEMP", "/tmp")))
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
        workflow_paths = [".github/workflows/build-ios26-unsigned-ipa.yml",
                          "Scripts/CI/IntegrationValidation/run_agent_sdk.sh",
                          "Scripts/CI/IntegrationValidation/run_native_tool_candidate.py",
                          "Scripts/CI/IntegrationValidation/verify_native_tool_candidate.py",
                          "Scripts/CI/IntegrationValidation/reuse_native_tool_baseline.py",
                          "Scripts/CI/IntegrationValidation/xcresult_to_xunit.py",
                          "Scripts/CI/select_stable_xcode.py"]
        if reuse_baseline:
            workflow_paths += [str(path.relative_to(root)) for path in sorted((root / REFERENCE_PATH).iterdir()) if path.is_file()]
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

        sdk_scheme = scheme(sdk, ["HanlinAgentSDK-Package", "HanlinAgentSDK"])
        core_scheme = scheme(core, ["HanlinPlatform-Package", "HanlinPlatform"])
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
                # Retain richer per-method exports from this same execution. If
                # a new Xcode shape cannot be interpreted, the verifier blocks
                # and these originals permit review without rerunning tests.
                suites = EXPECTED["SDKTests" if result == "SDKTests" else "CoreTests"]
                parameterized = {suite + "/" + method for suite, methods in suites.items()
                                 for method, arguments in methods.items() if arguments is not None}
                seen, exports = set(), []
                for case in read_cases(evidence, result)[0]:
                    identifier = case.get("nodeIdentifier")
                    if not isinstance(identifier, str):
                        continue
                    method = identifier.split("(", 1)[0]
                    if method not in parameterized or identifier in seen:
                        continue
                    seen.add(identifier)
                    detail_code, detail_output = run(
                        result + "-arguments-" + str(len(exports)),
                        ["xcrun", "xcresulttool", "get", "test-results", "test-details",
                         "--path", bundle, "--test-id", identifier, "--format", "json"],
                        check=False, timeout=120)
                    exports.append(dict(method=identifier, exit_code=detail_code,
                                        raw_file=detail_output.name, sha256=sha(detail_output)))
                (evidence / (result + "-argument-detail-exports.json")).write_text(json.dumps(exports, indent=2))
            return code

        boundary = ["HanlinChatCoreTests/HanlinAppleToolInputBoundaryTests"]
        candidate_bytes = {p: (scratch / p).read_bytes() for p in VARIANT_FILES}
        baseline_bytes = {p: subprocess.check_output(["git", "show", BASE + ":" + p], cwd=root) for p in VARIANT_FILES}
        (evidence / "baseline-variant.json").write_text(json.dumps({
            "base_commit": BASE,
            "scope": "Candidate package graph and same candidate boundary tests; only the two original engine/model files replaced with exact baseline Git bytes.",
            "files": {p: {"baseline_sha256": hashlib.sha256(baseline_bytes[p]).hexdigest(),
                          "candidate_sha256": hashlib.sha256(candidate_bytes[p]).hexdigest()} for p in VARIANT_FILES}
        }, indent=2))
        statuses["preparation_exit"] = 0
        if reuse_baseline:
            prepare_reuse(root, evidence)
            statuses["baseline_execution"] = "REUSED_VERIFIED"
            # No baseline subprocess ran. Its original exit belongs to the
            # separate authenticated reference, never to current process status.
        else:
            try:
                for relative, data in baseline_bytes.items():
                    (scratch / relative).write_bytes(data)
                statuses["baseline_core_exit"] = test("BaselineCoreTests", core, core_scheme, boundary)
            finally:
                for relative, data in candidate_bytes.items():
                    (scratch / relative).write_bytes(data)
        for relative, digest in digests.items():
            if Path(relative).name == "Package.resolved":
                continue  # The actual resolved locks are retained and verified separately.
            if sha(scratch / relative) != digest:
                raise RuntimeError("Candidate source was not fully restored before acceptance: " + relative)
        statuses["core_test_exit"] = test("CoreTests", core, core_scheme, boundary)
        statuses["sdk_test_exit"] = test("SDKTests", sdk, sdk_scheme, [
            "HanlinAgentCoreTests/HanlinAppleToolSchemaTests",
            "HanlinAgentCoreTests/HanlinAppleToolSessionBridgeTests",
        ])
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
        result = summarize(evidence)
        (evidence / "summary.json").write_text(json.dumps(result, indent=2))
        print(json.dumps(result, indent=2))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
