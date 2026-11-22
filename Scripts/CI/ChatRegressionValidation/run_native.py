#!/usr/bin/env python3
"""One owned iPad, exact before/after sources, and a bounded native chat probe."""
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
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
OUT = ROOT / "build/chat-regression-native-evidence"
BASELINE_APP = "de9ccac5d38c44f597b2a057701de4757587d6a8"
BASELINE_RENDERER = "ebbbf889276098f3642448e5439ad049c3cd2d6c"
PROVIDER_TEST = "ChatRegressionTests/RichBlockAttachmentRenderingTests/testProviderLookupUsesRichRenderer"
RENDERER_PIN = re.compile(rb'(https://github\.com/davidpovarsky/hanlin-streaming-markdown"\s*,\s*revision:\s*")([0-9a-f]{40})(")')


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def capture_timeout_diagnostics(pid: int, log: Path) -> None:
    """Retain bounded process state without arguments or environment secrets."""
    folder = log.parent / (log.stem + "-timeout")
    folder.mkdir(parents=True, exist_ok=True)
    commands = [
        ("processes", ["ps", "-axo", "pid,ppid,pgid,state,pcpu,pmem,etime,comm"], 5),
        ("sample", ["sample", str(pid), "1", "10", "-file", str(folder / "process.sample.txt")], 8)
    ]
    receipts = []
    for label, arguments, limit in commands:
        with (folder / (label + ".log")).open("w", encoding="utf-8") as output:
            try:
                result = subprocess.run(arguments, stdout=output, stderr=subprocess.STDOUT,
                                        timeout=limit, check=False)
                receipts.append({"diagnostic": label, "exit_code": result.returncode, "limit_seconds": limit})
            except (subprocess.TimeoutExpired, OSError) as error:
                output.write(f"Diagnostic unavailable: {type(error).__name__}\n")
                receipts.append({"diagnostic": label, "error": type(error).__name__, "limit_seconds": limit})
    write_json(folder / "diagnostics.json", {"timed_out_pid": pid, "diagnostics": receipts})


def run(args: list[str], log: Path, timeout: int, *, cwd: Path = ROOT, check: bool = True,
        env: dict[str, str] | None = None) -> int:
    """Bound the whole command process group, retaining diagnostics on failure."""
    log.parent.mkdir(parents=True, exist_ok=True)
    print(f"Native probe: {log.name}", flush=True)
    started = time.monotonic()
    with log.open("w", encoding="utf-8") as stream:
        process = subprocess.Popen(args, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT,
                                   start_new_session=True, env=env)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            # The deadline is still a failure even if the process exits while
            # diagnostics run. Sample only our child, then terminate its group.
            try:
                capture_timeout_diagnostics(process.pid, log)
            except OSError as error:
                stream.write(f"Timeout diagnostic unavailable: {type(error).__name__}\n")
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=10)
            stream.write("\nBounded command timeout; no execution success is inferred.\n")
            code = 124
    write_json(log.with_suffix(".command.json"), {"command": args, "cwd": str(cwd),
        "exit_code": code, "seconds": round(time.monotonic() - started, 3)})
    if check and code:
        raise RuntimeError(f"{log.name} failed (exit {code}); see retained log")
    return code


def read(args: list[str], timeout: int = 20, *, cwd: Path = ROOT) -> str:
    return subprocess.check_output(args, cwd=cwd, text=True, timeout=timeout).strip()


def ensure_xcodegen() -> dict:
    """Use the repository's Homebrew bootstrap, with observed tools and limits."""
    executable = shutil.which("xcodegen")
    brew = shutil.which("brew")
    write_json(OUT / "tool-availability.json", {"xcodegen": executable, "homebrew": brew})
    installed = executable is None
    if installed:
        if brew is None:
            raise RuntimeError("Native runner has neither XcodeGen nor an installed Homebrew executable")
        # Same installation route as docs/chat-motion/run_motion_ui.sh and
        # docs/a2ui/run_media_replay_ui.sh. Do not update unrelated tooling.
        brew_environment = {**os.environ,
            "HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_INSTALL_CLEANUP": "1",
            "HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK": "1", "HOMEBREW_NO_INSTALL_UPGRADE": "1",
            "HOMEBREW_NO_ANALYTICS": "1", "HOMEBREW_CURL_RETRIES": "0"}
        run([brew, "install", "--formula", "--force-bottle", "xcodegen"],
            OUT / "xcodegen-install.log", 180, env=brew_environment)
        # Use this actual formula's path even when the runner PATH has not been
        # refreshed after installation. Never substitute a guessed executable.
        prefix = read([brew, "--prefix", "xcodegen"], timeout=15)
        executable = str(Path(prefix) / "bin/xcodegen")
    tool = Path(executable).resolve(strict=True)
    if not tool.is_file() or not os.access(tool, os.X_OK):
        raise RuntimeError("XcodeGen bootstrap did not produce a runnable executable")
    version = read([str(tool), "--version"], timeout=15)
    if re.search(r"\b\d+\.\d+(?:\.\d+)?\b", version) is None:
        raise RuntimeError("XcodeGen did not report a valid observed version")
    receipt = {"path": str(tool), "version": version,
               "sha256": hashlib.sha256(tool.read_bytes()).hexdigest(),
               "installation": "homebrew-bottle" if installed else "preinstalled"}
    if installed:
        install_receipt = tool.parent.parent / "INSTALL_RECEIPT.json"
        native_receipt = json.loads(install_receipt.read_text())
        if native_receipt.get("poured_from_bottle") is not True:
            raise RuntimeError("XcodeGen was not installed from a Homebrew-verified bottle")
        shutil.copy2(install_receipt, OUT / "xcodegen-install-receipt.json")
    write_json(OUT / "xcodegen-tool.json", receipt)
    return receipt


def value(item):
    return item.get("_value") if isinstance(item, dict) else item


def result_record(folder: Path, exit_code: int, expected_count: int, *, baseline: bool) -> dict:
    bundle = folder / "Tests.xcresult"
    if not bundle.is_dir():
        raise RuntimeError(f"{folder.name}: no native xcresult; this is not an expected assertion failure")
    run(["xcrun", "xcresulttool", "get", "object", "--legacy", "--path", str(bundle),
         "--format", "json"], folder / "result-object.json", 40)
    run(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(bundle),
         "--format", "json"], folder / "tests.json", 40)
    run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle),
         "--output-path", str(folder / "attachments")], folder / "attachments-export.log", 60)
    raw = json.loads((folder / "result-object.json").read_text())
    metrics = raw.get("metrics", {})
    count = int(value(metrics.get("testsCount", 0)))
    failed = int(value(metrics.get("testsFailedCount", 0)))
    skipped = int(value(metrics.get("testsSkippedCount", 0)))
    failures = raw.get("issues", {}).get("testFailureSummaries", {}).get("_values", [])
    diagnostics = [{"test": value(f.get("testCaseName")), "message": value(f.get("message"))}
                   for f in failures]
    expected_failure = baseline and exit_code == 65 and failed == 1 and bool(diagnostics) and all(
        "testProviderLookupUsesRichRenderer" in (f["test"] or "")
        and "UIKit must resolve the rich-block provider, not its generic file-icon fallback" in (f["message"] or "")
        for f in diagnostics)
    passed = exit_code == 0 and failed == 0 and not diagnostics
    record = {"exit_code": exit_code, "tests": count, "failed": failed, "skipped": skipped,
              "failures": diagnostics, "status": "EXPECTED_PROVIDER_FAILURE" if expected_failure
              else "PASS" if passed else "FAIL"}
    write_json(folder / "phase-result.json", record)
    if count != expected_count or skipped or not (passed or expected_failure):
        raise RuntimeError(f"{folder.name}: unexpected native result: {record['status']} ({count} tests)")
    return record


def phase(stage: Path, name: str, revision: str, selectors: list[str], device: str) -> dict:
    folder = OUT / name
    folder.mkdir()
    project = stage / "Scripts/CI/ChatRegressionValidation/HanlinChatRegression.xcodeproj"
    common = ["-project", str(project), "-scheme", "HanlinChatRegression", "-configuration", "Debug",
              "-derivedDataPath", str(stage / "DerivedData"),
              "-clonedSourcePackagesDirPath", str(stage / "SourcePackages"),
              "CODE_SIGNING_ALLOWED=NO", "ENABLE_TESTABILITY=YES"]
    # Package resolution needs no running simulator or concrete destination.
    # Resolve the baseline before booting, as the established release route does.
    run(["xcodebuild", "-resolvePackageDependencies", *common], folder / "resolve.log", 240)
    checkout = stage / "SourcePackages/checkouts/hanlin-streaming-markdown"
    resolved = read(["git", "rev-parse", "HEAD"], cwd=checkout)
    if resolved != revision:
        raise RuntimeError(f"{name}: native renderer checkout does not equal its exact requested pin")
    write_json(folder / "renderer-source.json", {"requested": revision, "resolved": resolved})
    if name == "baseline":
        run(["xcrun", "simctl", "boot", device], OUT / "boot.log", 30)
        run(["xcrun", "simctl", "bootstatus", device, "-b"], OUT / "bootstatus.log", 150)
    destination = ["-destination", f"platform=iOS Simulator,id={device}", "-destination-timeout", "30"]
    code = run(["xcodebuild", "test", *common, *destination, "-disableAutomaticPackageResolution",
                "-parallel-testing-enabled", "NO", "-maximum-concurrent-test-simulator-destinations", "1",
                "-resultBundlePath", str(folder / "Tests.xcresult"),
                *["-only-testing:" + test for test in selectors]], folder / "test.log", 720, check=False)
    result = result_record(folder, code, 1 if name == "baseline" else 4, baseline=name == "baseline")
    if name == "candidate":
        images = [p for p in (folder / "attachments").rglob("*") if p.suffix.lower() in {".png", ".jpg", ".jpeg"}]
        if len(images) < 16:
            raise RuntimeError("Candidate did not retain all 12 Composer, two activity and two renderer images")
        write_json(folder / "image-index.json", [str(p.relative_to(folder)) for p in sorted(images)])
    return result


def main() -> None:
    if platform.system() != "Darwin":
        raise RuntimeError("This probe requires the selected native Apple runner")
    OUT.mkdir(parents=True, exist_ok=True)
    source = read(["git", "rev-parse", "HEAD"])
    expected = os.environ.get("COMPOSER_EXPECTED_SHA", "").strip()
    if expected and expected != source:
        raise RuntimeError("Candidate checkout differs from the explicitly requested source SHA")
    xcode = read([sys.executable, str(ROOT / "Scripts/CI/select_stable_xcode.py")], timeout=60)
    os.environ["DEVELOPER_DIR"] = xcode + "/Contents/Developer"
    xcodegen = ensure_xcodegen()
    write_json(OUT / "toolchain.json", {"source_sha": source, "developer_dir": os.environ["DEVELOPER_DIR"],
        "xcode": read(["xcodebuild", "-version"]), "sdk": read(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"]),
        "xcodegen": xcodegen})
    first_launch_status = run(["xcodebuild", "-checkFirstLaunchStatus"],
                              OUT / "first-launch-status.log", 30, check=False)
    if first_launch_status:
        raise RuntimeError("Selected Xcode first-launch preflight failed; inspect its retained status before bootstrap")
    baseline_available = run(["git", "cat-file", "-e", BASELINE_APP + ":Packages/HanlinPresentationSDK/Package.swift"],
                             OUT / "baseline-availability.log", 20, check=False)
    if baseline_available:
        run(["git", "fetch", "--no-tags", "--depth=1", "origin", BASELINE_APP], OUT / "fetch-baseline.log", 90)
    run([sys.executable, str(HERE / "prepare.py")], OUT / "prepare.log", 20)
    shutil.copy2(HERE / "evidence/native-source-receipt.json", OUT / "native-source-receipt.json")
    candidate_manifest = (ROOT / "Packages/HanlinPresentationSDK/Package.swift").read_bytes()
    match = RENDERER_PIN.search(candidate_manifest)
    if match is None:
        raise RuntimeError("Candidate SDK lacks an exact renderer revision")
    candidate_renderer = match[2].decode()
    if candidate_renderer == BASELINE_RENDERER:
        raise RuntimeError("Candidate renderer must contain the reviewed correction before native comparison")
    write_json(OUT / "sources.json", {"app": source, "baseline_app": BASELINE_APP,
        "baseline_renderer": BASELINE_RENDERER, "candidate_renderer": candidate_renderer,
        "candidate_manifest_sha256": hashlib.sha256(candidate_manifest).hexdigest()})

    device = None
    results = {}
    try:
        run_id, attempt = os.environ["GITHUB_RUN_ID"], os.environ["GITHUB_RUN_ATTEMPT"]
        owned_name = f"Hanlin-Phase2-Regression-{run_id}-{attempt}"
        selection_path = OUT / "simulator-selection.json"
        run([sys.executable, str(ROOT / "Scripts/CI/select_installed_simulator.py"),
             "--family", "iPad", "--create-owned", owned_name, "--output", str(selection_path)],
            OUT / "select-simulator.log", 90)
        selected = json.loads(selection_path.read_text())
        ownership = selected["ownership"]
        observed_device = selected["device"]["udid"]
        if (ownership.get("absent_before_create") is not True or ownership.get("name") != owned_name
                or ownership.get("run_id") != run_id or ownership.get("run_attempt") != attempt
                or ownership.get("simulator") != observed_device):
            raise RuntimeError("Selected simulator has no matching native creation receipt")
        device = observed_device

        with tempfile.TemporaryDirectory(prefix="hanlin-chat-regression-", dir=os.environ.get("RUNNER_TEMP")) as work:
            stage = Path(work)
            harness = stage / "Scripts/CI/ChatRegressionValidation"
            ignore = shutil.ignore_patterns(".build", ".swiftpm", "evidence", "DerivedData", "*.xcodeproj", "__pycache__")
            shutil.copytree(ROOT / "Packages/HanlinPresentationSDK", stage / "Packages/HanlinPresentationSDK", ignore=ignore)
            shutil.copytree(HERE, harness, ignore=ignore)
            manifest = stage / "Packages/HanlinPresentationSDK/Package.swift"
            run([xcodegen["path"], "generate", "--spec", "project.yml"], OUT / "xcodegen.log", 30, cwd=harness)
            try:
                manifest.write_bytes(RENDERER_PIN.sub(lambda m: m[1] + BASELINE_RENDERER.encode() + m[3], candidate_manifest, count=1))
                results["baseline"] = phase(stage, "baseline", BASELINE_RENDERER, [PROVIDER_TEST], device)
            finally:
                manifest.write_bytes(candidate_manifest)
            results["candidate"] = phase(stage, "candidate", candidate_renderer, [
                "ChatRegressionTests/RichBlockAttachmentRenderingTests",
                "ChatRegressionTests/ComposerGlassRenderingTests"], device)
            if manifest.read_bytes() != candidate_manifest:
                raise RuntimeError("Staged candidate manifest changed during native comparison")
        write_json(OUT / "result.json", {"status": "PASS", "phases": results,
            "scope": "Owned native iPad simulator, exact source probes. Inspect native images; physical iPad acceptance remains separate."})
    finally:
        if device:
            run(["xcrun", "simctl", "shutdown", device], OUT / "shutdown.log", 30, check=False)
            run(["xcrun", "simctl", "delete", device], OUT / "delete-owned-simulator.log", 30, check=False)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        write_json(OUT / "failure.json", {"status": "FAIL", "error": str(error)})
        print(f"Native chat regression probe failed: {error}", file=sys.stderr)
        sys.exit(1)
