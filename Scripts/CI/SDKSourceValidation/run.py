#!/usr/bin/env python3
"""Run closed obligations on an explicitly selected original Hanlin source.

The workflow/controller revision and the tested source revision are separate.
No app, native runtime bundle, simulator, signing or publication route is used.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import time
import traceback


HERE = Path(__file__).resolve().parent
CONFIG = json.loads((HERE / "obligations.json").read_text())
APP_LOCK = "AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
FALSE_INPUTS = (
    "composer_validation_only", "nativescript_metadata_validation_only",
    "runtime_job_foundation_only", "markdown_renderer_validation_only",
    "code_fence_webkit_validation_only", "diagnostics_capture_validation_only",
    "testflight_upload", "runtime_bundle_only", "runtime_publish_release",
    "phase1_validation_only", "fast_validation_only", "nativescript_poc_only",
    "force_clean_build", "measure_warm_rebuild", "simulator_e2e_only", "full_validation",
)
EMPTY_INPUTS = (
    "scripting_package_test_filter", "testflight_existing_build_number",
    "testflight_audience_source_build", "runtime_bundle_artifact_run_id",
    "runtime_reuse_artifacts_run_id", "compare_base_sha",
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def sha256(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(data)
    return value.hexdigest()


def blob_sha(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def validate_inputs(inputs: dict, environment: dict) -> str:
    require(environment.get("GITHUB_EVENT_NAME") == "workflow_dispatch", "Manual dispatch required")
    require(environment.get("GITHUB_REPOSITORY") == "davidpovarsky/hanlin-ai", "Wrong repository")
    require(inputs.get("target_validation_group") == CONFIG["group"], "Wrong SDK group")
    require(inputs.get("exact_test_selector") == CONFIG["selector"], "Wrong closed selector")
    source = inputs.get(CONFIG["sourceInput"], "")
    require(isinstance(source, str) and re.fullmatch(r"[0-9a-f]{40}", source) is not None,
            "A complete immutable source SHA is required; refs/latest/defaults are not admitted")
    require(source in CONFIG["reviewedSources"], "Source has no exact reviewed tree entry in this controller")
    require(environment.get("HANLIN_SDK_SOURCE_SHA") == source, "Workflow/source input mismatch")
    for name in FALSE_INPUTS:
        require(inputs.get(name) in (False, "false"), f"{name} must be explicitly false")
    for name in EMPTY_INPUTS:
        require(inputs.get(name, "") == "", f"{name} must be empty")
    return source


def parse_swift_testing(text: str, suite: dict) -> dict:
    """Require original named passes, summary and all parameter arguments.

    Swift Testing counts the five Stop methods in its summary, while two
    methods each execute two cases. Zero tests or a partial case set cannot pass.
    """
    text = re.sub(r"\x1b\[[0-9;]*m", "", text)
    require(not re.search(r"^.*(?:✘|Test .+ skipped|Test .+ failed|recorded an issue)", text, re.M),
            "Swift Testing reported a failure, issue or skipped test")
    records = re.findall(r"^✔ Test ([^\n]+?\([^\n]*?\))(?: with (\d+) test cases)? passed after [^\n]+$",
                         text, re.M)
    require(len(records) == len(suite["expectedMethods"]), "Wrong executed method count")
    actual = {}
    for name, cases in records:
        require(name not in actual, "Duplicate executed method")
        actual[name] = int(cases) if cases else 1
    require(actual == suite["expectedMethods"], "Named methods/case counts do not match original obligation")
    summaries = re.findall(r"^✔ Test run with (\d+) tests? in (\d+) suites? passed after [^\n]+$", text, re.M)
    require(summaries == [(str(len(actual)), "1")], "Missing or ambiguous successful Swift Testing summary")
    require(re.search(r"^✔ Suite " + re.escape(suite["suite"]) + r" passed after ", text, re.M) is not None,
            "Original suite did not pass")
    arguments = {}
    for name, expected in suite["parameterArguments"].items():
        pattern = (r"^◇ Test case passing 1 argument " + re.escape(expected["parameter"]) +
                   r" → ([^\n]+?) to " + re.escape(name) + r" started\.$")
        values = re.findall(pattern, text, re.M)
        require(sorted(values) == sorted(expected["values"]), "Missing/duplicate original parameter case")
        arguments[name] = values
    return {"status": "PASS_ACTUAL_NAMED_SWIFT_TESTING_OUTPUT", "suite": suite["suite"],
            "testModule": suite["testModule"], "methods": actual, "methodCount": len(actual),
            "caseCount": sum(actual.values()), "arguments": arguments, "scope": suite["scope"]}


def normalized_location(value: str) -> str:
    return value.rstrip("/").removesuffix(".git").lower()


def lock_records(path: Path) -> dict:
    document = json.loads(path.read_text())
    require(document.get("version") in (2, 3), "Unsupported lock format")
    records = {}
    for pin in document["pins"]:
        identity = pin["identity"]
        require(identity not in records, "Duplicate package identity")
        require(pin["kind"] == "remoteSourceControl", "Unqualified binary/registry dependency")
        revision = pin["state"].get("revision", "")
        require(re.fullmatch(r"[0-9a-f]{40}", revision) is not None, "Dependency lacks exact revision")
        records[identity] = {"revision": revision, "location": normalized_location(pin["location"])}
    require(bool(records), "Empty actual dependency lock")
    return records


def validate_lock(actual: dict, published: dict, required: set[str]) -> None:
    require(required <= actual.keys(), "Required original dependency missing")
    for identity, value in actual.items():
        require(identity in published and value == published[identity],
                f"Resolved dependency differs from selected source's original lock: {identity}")


def finish_original_process_group(process: subprocess.Popen, pgid: int) -> dict:
    """Prove absence of this command's original group, never a process-name kill.

    A successful leader exit is insufficient when its own children remain.
    Cleanup is abnormal even when it succeeds; it cannot turn the command green.
    This covers the owned POSIX process group, not unrelated system/XPC daemons.
    """
    require(pgid == process.pid and pgid > 0, "Process-group custody mismatch")
    result = {"pgid": pgid, "signals": [], "groupAbsent": False, "abnormalCleanup": False}

    def absent() -> bool:
        process.poll()  # Reap the original leader before checking its group.
        try:
            os.killpg(pgid, 0)
            return False
        except ProcessLookupError:
            return True

    def await_absence(seconds: float) -> bool:
        deadline = time.monotonic() + seconds
        while True:
            if absent():
                return True
            if time.monotonic() >= deadline:
                return False
            time.sleep(0.05)

    if absent():
        result["groupAbsent"] = True
        return result
    result["abnormalCleanup"] = True
    for signum, wait_seconds in ((signal.SIGTERM, 3), (signal.SIGKILL, 5)):
        try:
            os.killpg(pgid, signum)
            result["signals"].append(int(signum))
        except ProcessLookupError:
            pass
        if await_absence(wait_seconds):
            result["groupAbsent"] = True
            return result
    return result


class Run:
    def __init__(self, root: Path, output: Path):
        self.root, self.output = root, output
        self.environment = dict(os.environ, NO_COLOR="1", TERM="dumb", PYTHONUNBUFFERED="1")
        self.commands = []
        self.products = []
        self.build_roots = []
        self.deadline = time.monotonic() + 70 * 60  # Leave the workflow time for original product/artifact preservation.

    def command(self, label: str, argv: list[str], cwd: Path | None = None,
                timeout: int = 1200, allow_failure: bool = False) -> str:
        log = self.output / (label + ".log")
        timeout = min(timeout, int(self.deadline - time.monotonic()))
        require(timeout > 0, "Controller execution budget exhausted before the next command")
        record = {"label": label, "argv": argv, "cwd": str(cwd or self.root),
                  "log": log.name, "startedUTC": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                  "timeoutSeconds": timeout}
        self.commands.append(record)
        write_json(self.output / "commands.json", self.commands)
        began = time.monotonic()
        with log.open("wb") as stream:
            process = subprocess.Popen(argv, cwd=cwd or self.root, env=self.environment,
                                       stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
            record["pid"] = process.pid
            record["pgid"] = process.pid  # start_new_session establishes this original command group.
            write_json(self.output / "commands.json", self.commands)
            interrupted = None
            try:
                process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                record["timedOut"] = True
            except BaseException as error:
                interrupted = error
                record["interrupted"] = type(error).__name__
            finally:
                try:
                    record["groupCustody"] = finish_original_process_group(process, process.pid)
                except BaseException as error:
                    record["groupCustody"] = {"pgid": process.pid, "groupAbsent": False,
                                               "abnormalCleanup": True, "error": str(error)}
            record.update(exitCode=process.poll(), elapsedSeconds=round(time.monotonic() - began, 3))
        record["logSHA256"] = sha256(log)
        write_json(self.output / "commands.json", self.commands)
        text = log.read_text(errors="replace")
        if interrupted is not None:
            raise interrupted
        require(record["groupCustody"]["groupAbsent"] and not record["groupCustody"]["abnormalCleanup"],
                f"{label}: original process group required abnormal cleanup or did not drain")
        if not allow_failure:
            require(record["exitCode"] == 0 and not record.get("timedOut"), f"{label} failed; original log retained")
        return text

    def git(self, *args: str) -> str:
        # Metadata only; no credential-bearing configuration or environment dump.
        result = subprocess.run(["git", *args], cwd=self.root, capture_output=True, text=True, timeout=60)
        require(result.returncode == 0, "Git metadata read failed: " + " ".join(args[:2]))
        return result.stdout.strip()

    def free_floor(self, minimum: int) -> None:
        free = shutil.disk_usage(self.output).free
        require(free >= minimum, f"Hosted runner free bytes {free} below declared {minimum}")

    def verify_checkouts(self, package: Path, scratch: Path, actual: dict, label: str) -> None:
        state = json.loads((scratch / "workspace-state.json").read_text())
        checked = {}
        for dependency in state.get("object", state).get("dependencies", []):
            package_ref = dependency.get("packageRef", {})
            identity = package_ref.get("identity")
            if identity not in actual:
                require(dependency.get("state", {}).get("name") in ("fileSystem", "local"),
                        "Unknown resolved checkout")
                continue
            path = scratch / "checkouts" / dependency["subpath"]
            require(path.is_dir(), "Original dependency checkout absent")
            head = self.command(label + "-checkout-" + identity,
                                ["git", "-C", str(path), "rev-parse", "HEAD"], timeout=60).strip()
            require(head == actual[identity]["revision"], "Actual dependency checkout revision differs")
            dirty = self.command(label + "-clean-" + identity,
                                 ["git", "-C", str(path), "status", "--porcelain", "--untracked-files=all"], timeout=60)
            require(not dirty.strip(), "Original dependency checkout was changed")
            checked[identity] = {"head": head, "path": str(path)}
        require(set(checked) == set(actual), "Actual resolved checkout set differs from lock")
        write_json(self.output / (label + "-checkouts.json"), checked)

    def preserve_products(self) -> None:
        # Preserve original test bundles, resources, binaries and dSYMs, including
        # a failed build's existing products. Compiler intermediates are not copied.
        require(all(command.get("groupCustody", {}).get("groupAbsent") for command in self.commands),
                "Original process group not drained; refusing to copy potentially changing products")
        for label, build in self.build_roots:
            if not build.exists():
                continue
            roots = []
            if label == "ios":
                products = build / "Build/Products"
                if products.exists():
                    roots = [products]
            else:
                apple_products = [p for p in (build / "apple/Products", build / "out/Products", build / "Products") if p.is_dir()]
                roots.extend(apple_products)
                for folder in sorted(build.glob("*/debug")):
                    if not folder.is_dir() or folder.is_symlink():
                        continue
                    roots.extend(p for p in sorted(folder.iterdir())
                                 if p.suffix in (".xctest", ".bundle", ".dSYM", ".dylib"))
            if not roots:
                continue
            destination = self.output / (label + "-original-products.tar")
            inventory = []
            with tarfile.open(destination, "w") as archive:
                for item in roots:
                    archive.add(item, arcname=str(item.relative_to(build)), recursive=True)
                    for file in sorted(item.rglob("*")) if item.is_dir() else [item]:
                        if file.is_file() and not file.is_symlink():
                            inventory.append({"path": str(file.relative_to(build)), "bytes": file.stat().st_size,
                                              "sha256": sha256(file)})
            record = {"label": label, "archive": destination.name, "bytes": destination.stat().st_size,
                      "sha256": sha256(destination), "files": inventory}
            self.products.append(record)
        write_json(self.output / "original-products.json", self.products)


def source_inventory(run: Run, source: str, materialized: Path) -> list[dict]:
    raw = subprocess.check_output(["git", "ls-tree", "-r", "-z", source, "--", *CONFIG["archivePaths"]],
                                  cwd=run.root)
    records = []
    folded = set()
    for record in raw.split(b"\0"):
        if not record:
            continue
        metadata, path = record.split(b"\t", 1)
        mode, kind, blob = metadata.decode().split()
        relative = path.decode()
        require(kind == "blob" and mode in ("100644", "100755"), "Unexpected source link/submodule")
        require(relative.casefold() not in folded, "Selected source has a case alias")
        folded.add(relative.casefold())
        data = (materialized / relative).read_bytes()
        require(blob_sha(data) == blob, "Materialization differs from original Git blob")
        records.append({"path": relative, "mode": mode, "blob": blob, "bytes": len(data),
                        "sha256": hashlib.sha256(data).hexdigest()})
    require(records, "No source materialized")
    return records


def execute(run: Run, source: str) -> dict:
    require(platform.system() == "Darwin" and platform.machine() == "arm64", "Original Apple ARM64 host required")
    require(os.environ.get("GITHUB_ACTIONS") == "true" and
            os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted", "Independent hosted runner required")
    run.free_floor(20 * 1024**3)
    control = run.git("rev-parse", "HEAD")
    require(control == os.environ.get("GITHUB_SHA"), "Actual controller checkout differs from dispatched ref")
    control_paths = [".github/workflows/build-ios26-unsigned-ipa.yml",
                     "Scripts/CI/SDKSourceValidation/run.py", "Scripts/CI/SDKSourceValidation/obligations.json"]
    controls = {}
    for path in control_paths:
        data = (run.root / path).read_bytes()
        require(blob_sha(data) == run.git("rev-parse", f"{control}:{path}"), "Controller source changed")
        controls[path] = {"blob": blob_sha(data), "sha256": hashlib.sha256(data).hexdigest()}
    write_json(run.output / "controller-identity.json", {"source": control, "files": controls})
    run.command("fetch-original-source", ["git", "fetch", "--no-tags", "--depth=1", "--filter=blob:none",
                                          "origin", source], timeout=600)
    require(run.git("rev-parse", source + "^{commit}") == source, "Fetched source identity mismatch")
    require(run.git("rev-parse", source + "^{tree}") == CONFIG["reviewedSources"][source]["tree"],
            "Source tree differs from the exact reviewed source entry")
    for path, expected in CONFIG["protectedBlobs"].items():
        require(run.git("rev-parse", f"{source}:{path}") == expected,
                "Protected test/manifest/fixture/lock changed; new source review required: " + path)
    write_json(run.output / "admitted-source.json", {"source": source, "tree": run.git("rev-parse", source + "^{tree}"),
               "referenceSource": CONFIG["referenceSource"], "reviewedSource": CONFIG["reviewedSources"][source],
               "protectedBlobs": CONFIG["protectedBlobs"],
               "notCovered": CONFIG["notCovered"], "priorEvidenceReuse": CONFIG["priorEvidenceReuse"]})
    private = Path(tempfile.mkdtemp(prefix="hanlin-original-sdk-", dir=os.environ.get("RUNNER_TEMP", "/tmp")))
    materialized = private / "source"
    materialized.mkdir()
    archive = run.output / "original-source.tar"
    run.command("archive-original-source", ["git", "archive", "--format=tar", "-o", str(archive), source,
                                            *CONFIG["archivePaths"]], timeout=180)
    with tarfile.open(archive) as source_archive:
        names = set()
        for member in source_archive.getmembers():
            name = Path(member.name)
            require(not name.is_absolute() and ".." not in name.parts and
                    (member.isfile() or member.isdir()), "Unadmitted archive member")
            require(member.name.casefold() not in names, "Case alias in selected archive")
            names.add(member.name.casefold())
        # All members were admitted above as relative regular files/directories,
        # with no links or traversal. Keep compatibility with Apple's Python3.9.
        source_archive.extractall(materialized)
    before = source_inventory(run, source, materialized)
    write_json(run.output / "original-source-files.json", before)
    run.command("original-json-vendor", [sys.executable, str(materialized / "Scripts/CI/verify_exact_json_vendor.py")],
                cwd=materialized, timeout=60)
    xcode = run.command("select-original-stable-xcode", [sys.executable,
                        str(materialized / "Scripts/CI/select_stable_xcode.py")], timeout=120).splitlines()[-1]
    require(Path(xcode, "Contents/Developer/usr/bin/xcodebuild").is_file(), "Stable Xcode unavailable")
    run.environment["DEVELOPER_DIR"] = str(Path(xcode, "Contents/Developer"))
    run.command("xcode", ["xcodebuild", "-version"], timeout=30)
    run.command("swift", ["xcrun", "swift", "--version"], timeout=30)
    run.command("macos", ["sw_vers"], timeout=30)
    run.command("simulator-sdk", ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], timeout=30)
    published = lock_records(materialized / APP_LOCK)
    suite_results = []
    resolved_locks = {}
    for suite in CONFIG["suites"]:
        run.free_floor(2 * 1024**3)
        label = suite["name"]
        package = materialized / "Packages" / suite["package"]
        scratch = private / (label + "-build")
        run.build_roots.append((label, scratch))
        original_lock = package / "Package.resolved"
        required = {"swift-ai-sdk", "swiftyjson", "opentelemetry-swift-core", "zipfoundation"}
        if suite["package"] == "HanlinPresentationSDK":
            require(not original_lock.exists(), "Presentation graph now has a source lock; explicit review required")
            # This is a published source-lock seed, not an invented resolved graph.
            # The real resolver must produce and verify its own lock before build.
            shutil.copyfile(materialized / APP_LOCK, original_lock)
            required |= {"hanlin-streaming-markdown", "a2ui", "swiftsoup"}
            write_json(run.output / "presentation-lock-seed.json", {"source": APP_LOCK,
                       "sourceSHA256": sha256(materialized / APP_LOCK), "originalPackageLocalLock": "ABSENT",
                       "meaning": "Unmodified published App lock seed; real resolved lock is recorded separately"})
        run.command(label + "-resolve", ["xcrun", "swift", "package", "--package-path", str(package),
                    "--scratch-path", str(scratch), "--skip-update", "resolve"], timeout=600)
        actual = lock_records(original_lock)
        validate_lock(actual, published, required)
        shutil.copyfile(original_lock, run.output / (label + "-Package.resolved"))
        resolved_locks[label] = {"sha256": sha256(original_lock), "pins": actual}
        run.verify_checkouts(package, scratch, actual, label)
        if label == "widgets":
            run.environment["HANLIN_WIDGET_EVIDENCE_DIR"] = str(run.output / "widget-native-program")
        log = run.command(label + "-tests", ["xcrun", "swift", "test", "--package-path", str(package),
                    "--scratch-path", str(scratch), "--force-resolved-versions", "--skip-update", "--jobs", "2", "--verbose",
                    "--filter", suite["filter"]], timeout=1800)
        require(lock_records(original_lock) == actual, "Dependency revisions changed while testing")
        run.verify_checkouts(package, scratch, actual, label + "-posttest")
        result = parse_swift_testing(log, suite)
        suite_results.append(result)
        write_json(run.output / (label + "-actual-results.json"), result)
    measurements = json.loads((run.output / "widget-native-program/native-program-measurements.json").read_text())
    observed = measurements.get("measurements", [])
    require(len(observed) == len(CONFIG["widgetArchives"]), "Missing original prepared-program evidence")
    for path in CONFIG["widgetArchives"]:
        matching = [row for row in observed if row.get("archive") == Path(path).name]
        require(len(matching) == 1 and matching[0].get("archiveSHA256") == sha256(materialized / path),
                "Prepared-program fixture identity differs")
    ios = CONFIG["iosBuild"]
    package = materialized / "Packages" / ios["package"]
    ios_build = private / "ios-derived-data"
    run.build_roots.append(("ios", ios_build))
    run.free_floor(2 * 1024**3)
    run.command("ios-original-product", ["xcodebuild", "build", "-scheme", ios["scheme"],
                "-destination", ios["destination"], "-derivedDataPath", str(ios_build),
                "-resultBundlePath", str(run.output / "OriginalHanlinChatUI.xcresult"),
                "-clonedSourcePackagesDirPath", str(ios_build / "SourcePackages"),
                "-disableAutomaticPackageResolution", "-onlyUsePackageVersionsFromResolvedFile",
                "-skipPackagePluginValidation", "-skipMacroValidation", "-jobs", "2",
                "CODE_SIGNING_ALLOWED=NO"], cwd=package, timeout=1800)
    require(lock_records(package / "Package.resolved") == resolved_locks["payload-quota"]["pins"],
            "iOS build changed resolved package revisions")
    # The actual Xcode checkouts must close to the same published locked graph.
    ios_state = ios_build / "SourcePackages/workspace-state.json"
    require(ios_state.is_file(), "Original iOS dependency state missing")
    run.verify_checkouts(package, ios_build / "SourcePackages",
                         resolved_locks["payload-quota"]["pins"], "ios-postbuild")
    for row in before:
        if row["path"] in {"Packages/HanlinAgentSDK/Package.resolved", "Packages/HanlinPlatform/Package.resolved"}:
            continue  # Actual resolved locks above are separately retained/verified.
        require(sha256(materialized / row["path"]) == row["sha256"], "Original source changed during validation")
    write_json(run.output / "resolved-locks.json", resolved_locks)
    return {"status": "PASS_SELECTED_ORIGINAL_SDK_OBLIGATIONS_AND_IOS_PRODUCT_BUILD", "source": source,
            "controller": control, "suiteResults": suite_results, "iosBuild": ios,
            "notCovered": CONFIG["notCovered"], "priorEvidenceReuse": CONFIG["priorEvidenceReuse"]}


def main() -> int:
    root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
    suffix = os.environ.get("GITHUB_RUN_ID", "missing") + "-" + os.environ.get("GITHUB_RUN_ATTEMPT", "missing")
    require(re.fullmatch(r"[0-9]+-[0-9]+", suffix) is not None, "Real workflow run identity required")
    output = root / "build/sdk-original-obligations" / suffix
    output.mkdir(parents=True, exist_ok=False)
    run = Run(root, output)
    result = {"status": "FAILED_BEFORE_COMPLETION", "notCovered": CONFIG["notCovered"]}
    try:
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
        inputs = event.get("inputs", {})
        source = validate_inputs(inputs, os.environ)
        write_json(output / "dispatch-inputs.json", inputs)
        result = execute(run, source)
    except BaseException as error:
        result["error"] = str(error)
        (output / "controller-error.log").write_text(traceback.format_exc())
    finally:
        try:
            run.preserve_products()
            if result["status"] == "PASS_SELECTED_ORIGINAL_SDK_OBLIGATIONS_AND_IOS_PRODUCT_BUILD":
                preserved = {row["label"]: row for row in run.products}
                require(set(preserved) == {suite["name"] for suite in CONFIG["suites"]} | {"ios"},
                        "Original compiled product set was not preserved")
                for suite in CONFIG["suites"]:
                    require(any(".xctest/" in row["path"] for row in preserved[suite["name"]]["files"]),
                            "Original executed test bundle was not retained")
                require(bool(preserved["ios"]["files"]), "Original iOS product archive is empty")
        except BaseException as error:
            result["productPreservationError"] = str(error)
            result["status"] = "FAILED_PRODUCT_PRESERVATION"
        result["commands"] = run.commands
        result["products"] = [{k: v for k, v in row.items() if k != "files"} for row in run.products]
        write_json(output / "result.json", result)
        inventory = [{"path": str(p.relative_to(output)), "bytes": p.stat().st_size, "sha256": sha256(p)}
                     for p in sorted(output.rglob("*")) if p.is_file() and not p.is_symlink()]
        write_json(output / "evidence-files.json", inventory)
    print(json.dumps({"status": result["status"], "source": result.get("source"), "evidence": str(output)}))
    return 0 if result["status"] == "PASS_SELECTED_ORIGINAL_SDK_OBLIGATIONS_AND_IOS_PRODUCT_BUILD" else 1


if __name__ == "__main__":
    raise SystemExit(main())
