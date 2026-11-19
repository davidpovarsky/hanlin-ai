"""Retain original Motion results even when XCTest fails before its first case."""
from pathlib import Path
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import sys
import time

PROOF_BUNDLE_ID = "ai.hanlin.motion-proof"
TIMELINE_FILENAME = "motion-geometry-timeline.json"
MAX_TIMELINE_BYTES = 64 * 1024 * 1024


def _has_symlink_component(paths: list[Path]) -> bool:
    return any(path.is_symlink() for path in paths)


def _find_unique_uuid_container(device: str, devices_root: Path) -> tuple[Path | None, dict[str, object]]:
    info: dict[str, object] = {"attempted": True}
    if not devices_root.exists() or devices_root.is_symlink() or not devices_root.is_dir():
        info["status"] = "DEVICES_ROOT_UNAVAILABLE"
        return None, info

    device_dir = devices_root / device
    data_dir = device_dir / "data"
    containers_dir = data_dir / "Containers"
    data_containers_dir = containers_dir / "Data"
    apps_root = data_containers_dir / "Application"
    if _has_symlink_component([device_dir, data_dir, containers_dir, data_containers_dir, apps_root]):
        info["status"] = "UNSAFE_SIMULATOR_PATH"
        return None, info
    if not apps_root.exists():
        info["status"] = "APPLICATIONS_DIR_MISSING"
        return None, info
    if not apps_root.is_dir():
        info["status"] = "APPLICATIONS_DIR_UNSAFE"
        return None, info

    root_resolved = devices_root.resolve()
    apps_root_resolved = apps_root.resolve()
    if not apps_root_resolved.is_relative_to(root_resolved):
        info["status"] = "APPLICATIONS_PATH_ESCAPE"
        return None, info

    matches: list[Path] = []
    unsafe_symlinks = 0
    corrupt_plists = 0
    for entry in sorted(apps_root.iterdir()):
        if entry.is_symlink():
            unsafe_symlinks += 1
            continue
        if not entry.is_dir():
            continue
        entry_resolved = entry.resolve()
        if not entry_resolved.is_relative_to(apps_root_resolved):
            unsafe_symlinks += 1
            continue
        meta_path = entry / ".com.apple.mobile_container_manager.metadata.plist"
        if not meta_path.exists():
            continue
        if meta_path.is_symlink() or not meta_path.is_file() or not meta_path.resolve().is_relative_to(entry_resolved):
            unsafe_symlinks += 1
            continue
        try:
            with meta_path.open("rb") as fh:
                meta = plistlib.load(fh)
        except (OSError, plistlib.InvalidFileException, ValueError):
            corrupt_plists += 1
            continue
        if isinstance(meta, dict) and meta.get("MCMMetadataIdentifier") == PROOF_BUNDLE_ID:
            matches.append(entry)

    info["match_count"] = len(matches)
    if unsafe_symlinks:
        info["unsafe_symlinks_skipped"] = unsafe_symlinks
    if corrupt_plists:
        info["corrupt_plists_skipped"] = corrupt_plists

    if len(matches) == 1:
        info["status"] = "MATCHED_UNIQUE"
        return matches[0], info
    if len(matches) > 1:
        info["status"] = "AMBIGUOUS_CONTAINERS"
        return None, info
    info["status"] = "NO_MATCHING_CONTAINER"
    return None, info


def collect_motion_timeline(
    device: str,
    evidence: Path,
    devices_root: Path | None = None,
    run_cmd=subprocess.run,
) -> dict[str, object]:
    """Locate, validate, and copy the proof app's timeline JSON, failing closed on ambiguity or unsafe paths."""
    if not re.fullmatch(r"[A-Fa-f0-9-]{36}", device):
        return {"bundle_id": PROOF_BUNDLE_ID, "status": "INVALID_DEVICE_UUID"}

    timeline_status: dict[str, object] = {"bundle_id": PROOF_BUNDLE_ID, "status": "NOT_FOUND"}
    simctl_info: dict[str, object] = {}
    container_path: Path | None = None
    source: str | None = None

    try:
        result = run_cmd(
            ["xcrun", "simctl", "get_app_container", device, PROOF_BUNDLE_ID, "data"],
            capture_output=True,
            text=True,
            check=False,
            timeout=5,
        )
        simctl_info["exit_code"] = result.returncode
        stderr_text = (result.stderr or "").strip()
        if stderr_text:
            simctl_info["stderr"] = stderr_text[:500]
        stdout_text = (result.stdout or "").strip()
        if result.returncode == 0 and stdout_text:
            container_path = Path(stdout_text)
            source = "simctl"
        elif result.returncode == 0:
            simctl_info["error"] = "EMPTY_CONTAINER_PATH"
    except subprocess.TimeoutExpired as error:
        simctl_info["timed_out"] = True
        simctl_info["error"] = f"TIMEOUT:{error.timeout}"
    except (OSError, subprocess.SubprocessError) as error:
        simctl_info["error"] = str(error)

    timeline_status["simctl"] = simctl_info

    if container_path is None:
        root = devices_root if devices_root is not None else (Path.home() / "Library/Developer/CoreSimulator/Devices")
        container_path, fallback_info = _find_unique_uuid_container(device, root)
        timeline_status["fallback"] = fallback_info
        if container_path is not None:
            source = "container_metadata_fallback"
        elif fallback_info.get("status") in {"AMBIGUOUS_CONTAINERS", "UNSAFE_SIMULATOR_PATH", "APPLICATIONS_PATH_ESCAPE"}:
            timeline_status["status"] = str(fallback_info["status"])

    if container_path is None:
        return timeline_status

    timeline_status["source"] = source
    if container_path.is_symlink() or not container_path.is_dir():
        timeline_status["status"] = "UNSAFE_CONTAINER"
        return timeline_status

    container_resolved = container_path.resolve()
    docs_dir = container_path / "Documents"
    if not docs_dir.exists():
        timeline_status["status"] = "MISSING_DOCUMENTS_DIR"
        return timeline_status
    if docs_dir.is_symlink() or not docs_dir.is_dir() or not docs_dir.resolve().is_relative_to(container_resolved):
        timeline_status["status"] = "UNSAFE_DOCUMENTS_DIR"
        return timeline_status

    docs_resolved = docs_dir.resolve()
    timeline = docs_dir / TIMELINE_FILENAME
    if timeline.is_symlink():
        timeline_status["status"] = "SYMLINK_REJECTED"
        return timeline_status
    if not timeline.exists():
        timeline_status["status"] = "MISSING_TIMELINE"
        return timeline_status
    if not timeline.is_file() or not timeline.resolve().is_relative_to(docs_resolved):
        timeline_status["status"] = "PATH_ESCAPE_REJECTED"
        return timeline_status

    size = timeline.stat().st_size
    if size <= 0 or size > MAX_TIMELINE_BYTES:
        timeline_status["status"] = "INVALID_TIMELINE_SIZE"
        timeline_status["bytes"] = size
        return timeline_status

    try:
        raw_bytes = timeline.read_bytes()
        parsed = json.loads(raw_bytes.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        timeline_status["status"] = "INVALID_JSON"
        timeline_status["error"] = str(error)
        return timeline_status

    if not isinstance(parsed, list) or not all(isinstance(item, dict) for item in parsed):
        timeline_status["status"] = "INVALID_TIMELINE_SCHEMA"
        return timeline_status

    dest = evidence / TIMELINE_FILENAME
    evidence_resolved = evidence.resolve()
    if dest.is_symlink() or dest.resolve().parent != evidence_resolved:
        timeline_status["status"] = "UNSAFE_DESTINATION"
        return timeline_status

    dest.write_bytes(raw_bytes)
    timeline_status["status"] = "COPIED"
    timeline_status["bytes"] = len(raw_bytes)
    timeline_status["sha256"] = hashlib.sha256(raw_bytes).hexdigest()
    timeline_status["sample_count"] = len(parsed)
    timeline_status["presets"] = sorted(
        {item["preset"] for item in parsed if isinstance(item.get("preset"), str)}
    )
    return timeline_status


def main() -> None:
    bundle, device, evidence, test_code = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3]), int(sys.argv[4])
    assert re.fullmatch(r"[A-Fa-f0-9-]{36}", device)
    selected = json.loads((evidence / "verified-environment.json").read_text())["device"]
    assert selected["udid"] == device
    status = {"test_exit_code": test_code, "archive": "NOT_CREATED", "readability": "NOT_READ", "diagnostics": []}
    if bundle.exists():
        # Preserve the original bundle before invoking the reader which itself can stall.
        partial = evidence / "Motion.xcresult.tar.gz.partial"
        try:
            subprocess.run(["tar", "-czf", str(partial), "-C", str(bundle.parent), bundle.name], check=True, timeout=90)
            archive = evidence / "Motion.xcresult.tar.gz"
            partial.replace(archive)
            status["archive"] = "ARCHIVED"
            status["archive_sha256"] = hashlib.sha256(archive.read_bytes()).hexdigest()
        except (OSError, subprocess.SubprocessError) as error:
            status["archive_error"] = str(error)
            partial.unlink(missing_ok=True)
        try:
            result = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "tests",
                                     "--path", str(bundle), "--format", "json"],
                                    capture_output=True, timeout=120, check=True)
            json.loads(result.stdout)
            (evidence / "tests.json").write_bytes(result.stdout)
            status["readability"] = "READABLE"
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            status["readability"] = "READER_FAILED"
            status["reader_error"] = str(error)
            if getattr(error, "stderr", None):
                (evidence / "result-reader.stderr").write_bytes(error.stderr)
    else:
        status["readability"] = "NO_RESULT_BUNDLE"

    # Retain the owned diagnostic action receipts even when a later setup assertion
    # fails. This exports existing XCTest evidence; it does not rerun any gesture.
    scope_path = evidence / "selected-scope.txt"
    if bundle.exists() and scope_path.exists() and scope_path.read_text().strip() == "input-diagnostic":
        try:
            result = subprocess.run(
                ["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle),
                 "--output-path", str(evidence / "input-diagnostic-attachments"),
                 "--test-id", "MotionUITests/testDRapidInputDiagnosticOnly()"],
                capture_output=True, timeout=90, check=False)
            (evidence / "input-diagnostic-attachments-export.log").write_bytes(
                result.stdout + b"\nSTDERR\n" + result.stderr)
            status["diagnostic_attachments"] = {
                "status": "EXPORTED" if result.returncode == 0 else "EXPORT_FAILED",
                "exit_code": result.returncode}
        except (OSError, subprocess.SubprocessError) as error:
            status["diagnostic_attachments"] = {"status": "EXPORT_FAILED", "error": str(error)}

    if test_code or status["readability"] != "READABLE":
        diagnostics = evidence / "test-runner-diagnostics"
        diagnostics.mkdir(exist_ok=True)
        # Only the owned proof processes/reports, without environment dumps or broad user logs.
        reports = Path.home() / "Library/Logs/DiagnosticReports"
        for source in sorted(reports.glob("ChatMotionProof*.ips"))[-6:]:
            if source.stat().st_size <= 16 * 1024 * 1024 and source.stat().st_mtime >= time.time() - 3600:
                shutil.copyfile(source, diagnostics / source.name)
                status["diagnostics"].append(source.name)
        try:
            processes = subprocess.run(["ps", "-axo", "pid=,comm="], capture_output=True, text=True, check=True, timeout=5)
            owned = []
            for line in processes.stdout.splitlines():
                parts = line.strip().split(None, 1)
                if len(parts) == 2 and Path(parts[1]).name in {"ChatMotionProof", "ChatMotionProofUITests-Runner"}:
                    owned.append((parts[0], parts[1]))
            (diagnostics / "owned-processes.json").write_text(json.dumps(owned, indent=2))
            for pid, name in owned[:3]:
                target = diagnostics / (Path(name).name + "-" + pid + ".sample.txt")
                with (diagnostics / (pid + ".sample-command.log")).open("w") as stream:
                    subprocess.run(["sample", pid, "3", "-file", str(target)],
                                   stdout=stream, stderr=subprocess.STDOUT, check=False, timeout=12)
        except (OSError, subprocess.SubprocessError) as error:
            status["diagnostic_error"] = str(error)

    status["timeline"] = collect_motion_timeline(device, evidence)
    status["status"] = ("FINALIZED_READABLE_ARCHIVED" if status["archive"] == "ARCHIVED" and
                        status["readability"] == "READABLE" else "INCOMPLETE_RAW_RESULT")
    (evidence / "raw-result-status.json").write_text(json.dumps(status, indent=2))
    print(json.dumps(status))


if __name__ == "__main__":
    main()
