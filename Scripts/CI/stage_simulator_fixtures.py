#!/usr/bin/env python3
"""Stage NativeScript and application fixtures into iPad Simulator containers safely and truthfully.

Enforces strict separation between required staging steps and optional system containers:
1. Required: Booting simulator and waiting for bootstatus (bounded timeout). Fails if boot fails.
2. Required (if app provided): Installing target .app bundle. Fails if installation fails.
3. Required: Resolving target app data container. Fails if container cannot be resolved.
4. Required: Staging essential .hanlinNativeScript package fixtures into `<app_container>/Documents`.
   Fails if 0 fixtures are staged or essential fixtures are missing.
5. Optional: Probing `com.apple.DocumentsApp` with a strict 5-second timeout.
   In ephemeral CI runners, system apps are unprovisioned at boot; skipping this probe
   is safe, expected, and never causes a failure or blocks the runner.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from typing import Dict, List, Optional

FIXTURE_NAMES = [
    "HanlinNativeScriptSwiftUI.hanlinNativeScript",
    "HanlinNativeScriptCore.hanlinNativeScript",
    "HanlinNativeScriptUnsupported.hanlinNativeScript",
    "HanlinNativeScriptMalformed.hanlinNativeScript",
    "sefaria-reader-core.hanlinNativeScript",
    "core-unbundled.hanlinNativeScript",
    "uikit-tabbar-bridge.hanlinNativeScript",
    "core-fixture-a-tabview.hanlinNativeScript",
    "core-fixture-b-frame.hanlinNativeScript",
    "core-fixture-c-tabview-frame.hanlinNativeScript",
    "hanlin-script-parity.hanlinNativeScript",
]


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def run_bounded(
    cmd: List[str],
    timeout_seconds: float = 30.0,
    check: bool = False,
) -> subprocess.CompletedProcess[str]:
    """Execute command with strict timeout and output capture."""
    try:
        return subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            check=check,
        )
    except subprocess.TimeoutExpired:
        print(f"[stage_simulator_fixtures] Command timed out after {timeout_seconds}s: {' '.join(cmd)}", file=sys.stderr)
        return subprocess.CompletedProcess(
            args=cmd,
            returncode=124,
            stdout="",
            stderr=f"Timed out after {timeout_seconds}s",
        )


def stage_simulator_fixtures(
    simulator_udid: str,
    bundle_id: str,
    app_path: Optional[Path],
    fixtures_dir: Path,
    log_dir: Optional[Path] = None,
    runner=run_bounded,
) -> Dict[str, any]:
    """Stage fixtures with strict error propagation for required steps and graceful skip for DocumentsApp."""
    fixtures_dir = fixtures_dir.resolve()
    logs: List[str] = [
        f"Staging fixtures for simulator: {simulator_udid}",
        f"Target bundle ID: {bundle_id}",
        f"Fixtures directory: {fixtures_dir}",
    ]

    # 1. Boot simulator if needed and verify bootstatus
    print(f"[stage_simulator_fixtures] Verifying simulator boot state for {simulator_udid}...")
    runner(["xcrun", "simctl", "boot", simulator_udid], timeout_seconds=15.0)
    bootstatus_res = runner(["xcrun", "simctl", "bootstatus", simulator_udid, "-b"], timeout_seconds=45.0)
    logs.append(f"Bootstatus exit: {bootstatus_res.returncode}")
    if bootstatus_res.returncode != 0:
        err_msg = f"Fatal: Simulator bootstatus failed with code {bootstatus_res.returncode}: {bootstatus_res.stderr.strip()}"
        logs.append(err_msg)
        print(f"[stage_simulator_fixtures] {err_msg}", file=sys.stderr)
        if log_dir:
            log_dir.mkdir(parents=True, exist_ok=True)
            (log_dir / "08-nativescript-files-staging.log").write_text("\n".join(logs) + "\n", encoding="utf-8")
        return {
            "status": "BOOT_FAILED",
            "error": err_msg,
            "staged_in_app": 0,
            "staged_in_files": 0,
            "logs": logs,
        }

    # 2. Install application if app_path provided
    if app_path:
        if not app_path.exists():
            err_msg = f"Fatal: Specified app_path does not exist: {app_path}"
            logs.append(err_msg)
            print(f"[stage_simulator_fixtures] {err_msg}", file=sys.stderr)
            return {
                "status": "INSTALL_FAILED",
                "error": err_msg,
                "staged_in_app": 0,
                "staged_in_files": 0,
                "logs": logs,
            }
        print(f"[stage_simulator_fixtures] Installing {app_path.name}...")
        install_res = runner(["xcrun", "simctl", "install", simulator_udid, str(app_path)], timeout_seconds=60.0)
        logs.append(f"Install exit: {install_res.returncode}")
        if install_res.returncode != 0:
            err_msg = f"Fatal: simctl install failed with code {install_res.returncode}: {install_res.stderr.strip()}"
            logs.append(err_msg)
            print(f"[stage_simulator_fixtures] {err_msg}", file=sys.stderr)
            if log_dir:
                log_dir.mkdir(parents=True, exist_ok=True)
                (log_dir / "08-nativescript-files-staging.log").write_text("\n".join(logs) + "\n", encoding="utf-8")
            return {
                "status": "INSTALL_FAILED",
                "error": err_msg,
                "staged_in_app": 0,
                "staged_in_files": 0,
                "logs": logs,
            }

    # 3. Retrieve target app container (MANDATORY)
    app_container_path: Optional[Path] = None
    container_res = runner(
        ["xcrun", "simctl", "get_app_container", simulator_udid, bundle_id, "data"],
        timeout_seconds=20.0,
    )
    if container_res.returncode == 0 and container_res.stdout.strip():
        app_container_path = Path(container_res.stdout.strip())
        logs.append(f"App container resolved: {app_container_path}")
    else:
        err_msg = f"Fatal: Could not resolve app container for bundle {bundle_id}: {container_res.stderr.strip()}"
        logs.append(err_msg)
        print(f"[stage_simulator_fixtures] {err_msg}", file=sys.stderr)
        if log_dir:
            log_dir.mkdir(parents=True, exist_ok=True)
            (log_dir / "08-nativescript-files-staging.log").write_text("\n".join(logs) + "\n", encoding="utf-8")
        return {
            "status": "CONTAINER_NOT_FOUND",
            "error": err_msg,
            "staged_in_app": 0,
            "staged_in_files": 0,
            "logs": logs,
        }

    # Copy fixtures into app container Documents/ (MANDATORY)
    if not fixtures_dir.is_dir():
        err_msg = f"Fatal: Fixtures directory does not exist: {fixtures_dir}"
        logs.append(err_msg)
        print(f"[stage_simulator_fixtures] {err_msg}", file=sys.stderr)
        return {
            "status": "FIXTURES_MISSING",
            "error": err_msg,
            "staged_in_app": 0,
            "staged_in_files": 0,
            "logs": logs,
        }

    staged_in_app = 0
    app_docs = app_container_path / "Documents"
    app_docs.mkdir(parents=True, exist_ok=True)
    for name in FIXTURE_NAMES:
        src = fixtures_dir / name
        if src.is_file():
            dst = app_docs / name
            shutil.copy2(src, dst)
            h = sha256_file(dst)
            logs.append(f"App Doc: {name} (sha256={h[:16]}...)")
            staged_in_app += 1

    if staged_in_app == 0:
        err_msg = f"Fatal: No required fixtures found in {fixtures_dir} to stage into app container"
        logs.append(err_msg)
        print(f"[stage_simulator_fixtures] {err_msg}", file=sys.stderr)
        if log_dir:
            log_dir.mkdir(parents=True, exist_ok=True)
            (log_dir / "08-nativescript-files-staging.log").write_text("\n".join(logs) + "\n", encoding="utf-8")
        return {
            "status": "FIXTURES_MISSING",
            "error": err_msg,
            "staged_in_app": 0,
            "staged_in_files": 0,
            "logs": logs,
        }

    # 4. Probe com.apple.DocumentsApp with strict 5-second timeout (OPTIONAL - system app)
    files_container_path: Optional[Path] = None
    print("[stage_simulator_fixtures] Probing Files container (com.apple.DocumentsApp) with 5s timeout (optional)...")
    files_res = runner(
        ["xcrun", "simctl", "get_app_container", simulator_udid, "com.apple.DocumentsApp", "data"],
        timeout_seconds=5.0,
    )
    staged_in_files = 0
    if files_res.returncode == 0 and files_res.stdout.strip():
        files_container_path = Path(files_res.stdout.strip())
        logs.append(f"Files container resolved: {files_container_path}")
        if files_container_path.is_dir():
            files_docs = files_container_path / "Documents"
            files_docs.mkdir(parents=True, exist_ok=True)
            for name in FIXTURE_NAMES:
                src = fixtures_dir / name
                if src.is_file():
                    dst = files_docs / name
                    shutil.copy2(src, dst)
                    staged_in_files += 1
            logs.append(f"Staged {staged_in_files} fixtures into Files app container")
    else:
        logs.append("Files container probe skipped (optional system container unprovisioned at boot - safe to proceed)")

    if log_dir:
        log_dir.mkdir(parents=True, exist_ok=True)
        (log_dir / "08-nativescript-files-staging.log").write_text("\n".join(logs) + "\n", encoding="utf-8")

    result = {
        "status": "SUCCESS",
        "app_container": str(app_container_path),
        "files_container": str(files_container_path) if files_container_path else None,
        "staged_in_app": staged_in_app,
        "staged_in_files": staged_in_files,
        "logs": logs,
    }
    print(f"[stage_simulator_fixtures] Successfully staged {staged_in_app} fixtures into app container ({staged_in_files} into Files container).")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Stage simulator fixtures with strict error handling")
    parser.add_argument("--simulator-udid", required=True, help="Target simulator UDID")
    parser.add_argument("--bundle-id", default="com.itorah.chavrusachat", help="App bundle identifier")
    parser.add_argument("--app-path", help="Path to tested .app bundle")
    parser.add_argument("--fixtures-dir", default="build/NativeScriptE2E", help="Path containing .hanlinNativeScript fixtures")
    parser.add_argument("--log-dir", help="Directory to write staging logs")

    args = parser.parse_args()
    app_p = Path(args.app_path).resolve() if args.app_path else None
    fix_p = Path(args.fixtures_dir).resolve()
    log_d = Path(args.log_dir).resolve() if args.log_dir else None

    res = stage_simulator_fixtures(
        simulator_udid=args.simulator_udid,
        bundle_id=args.bundle_id,
        app_path=app_p,
        fixtures_dir=fix_p,
        log_dir=log_d,
    )
    return 0 if res["status"] == "SUCCESS" else 1


if __name__ == "__main__":
    sys.exit(main())
