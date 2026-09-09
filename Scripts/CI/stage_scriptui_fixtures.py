#!/usr/bin/env python3
"""Stage ScriptUI test fixtures into iPad Simulator app and Files container Documents directories.

This script ensures that the clean iPad Simulator app container has the necessary
.scripting package fixtures in its Documents/ directory before running
HanlinScriptUIProductionE2ETests.

Workflow:
1. Verifies / deterministically creates the .scripting archives in AI_HLYUITests/Fixtures.
2. Installs the tested app onto the booted simulator.
3. Obtains the tested app's data container using `xcrun simctl get_app_container`.
4. Creates `<APP_CONTAINER>/Documents` and copies the three .scripting fixtures there.
5. Optionally copies into `com.apple.DocumentsApp/Documents` if the Files container is present.
6. Writes sha256 hashes and verification logs.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
from typing import List, Optional

try:
    from .create_scriptui_fixtures import create_fixtures, FIXTURE_NAMES
except (ImportError, ValueError):
    try:
        from create_scriptui_fixtures import create_fixtures, FIXTURE_NAMES
    except ImportError:
        import importlib.util
        _helper = Path(__file__).resolve().parent / "create_scriptui_fixtures.py"
        _spec = importlib.util.spec_from_file_location("create_scriptui_fixtures", _helper)
        if _spec and _spec.loader:
            _mod = importlib.util.module_from_spec(_spec)
            _spec.loader.exec_module(_mod)
            create_fixtures = _mod.create_fixtures
            FIXTURE_NAMES = _mod.FIXTURE_NAMES
        else:
            raise


def compute_sha256(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


def stage_fixtures(
    simulator_udid: str,
    app_path: Optional[Path] = None,
    bundle_id: str = "com.davidpovarsky.AI-HLY",
    fixtures_dir: Optional[Path] = None,
    log_file: Optional[Path] = None,
    dry_run: bool = False,
    runner=subprocess.run,
) -> dict:
    root = Path(__file__).resolve().parents[2]
    fix_dir = fixtures_dir or (root / "AI_HLYUITests" / "Fixtures")

    # 1. Ensure fixtures exist and are deterministic
    generated = create_fixtures(fix_dir)

    logs: List[str] = [
        f"Staging ScriptUI fixtures for simulator: {simulator_udid}",
        f"Fixtures directory: {fix_dir}",
    ]

    for fname in generated:
        fpath = fix_dir / fname
        logs.append(f"Fixture {fname} sha256={compute_sha256(fpath)}")

    if dry_run:
        logs.append("Dry run enabled - skipping simctl commands")
        res = {"staged": True, "dry_run": True, "logs": logs}
        if log_file:
            log_file.parent.mkdir(parents=True, exist_ok=True)
            log_file.write_text("\n".join(logs) + "\n", encoding="utf-8")
        return res

    # 2. Install tested app if app_path is provided
    if app_path and app_path.exists():
        logs.append(f"Installing app: {app_path}")
        install_res = runner(
            ["xcrun", "simctl", "install", simulator_udid, str(app_path)],
            capture_output=True,
            text=True,
            check=False,
        )
        if install_res.returncode != 0:
            logs.append(f"Warning: simctl install returned {install_res.returncode}: {install_res.stderr.strip()}")
        else:
            logs.append("App installed successfully")

    # 3. Get app data container
    container_cmd = ["xcrun", "simctl", "get_app_container", simulator_udid, bundle_id, "data"]
    c_res = runner(container_cmd, capture_output=True, text=True, check=False)
    app_container: Optional[Path] = None
    if c_res.returncode == 0 and c_res.stdout.strip():
        app_container = Path(c_res.stdout.strip())
        logs.append(f"App data container: {app_container}")
    else:
        logs.append(f"Warning: could not get app container for {bundle_id}: {c_res.stderr.strip()}")

    # Copy fixtures into app container Documents/
    staged_targets = []
    if app_container and app_container.exists():
        app_docs = app_container / "Documents"
        app_docs.mkdir(parents=True, exist_ok=True)
        for fname in generated:
            src = fix_dir / fname
            dst = app_docs / fname
            shutil.copy2(src, dst)
            logs.append(f"Staged {fname} -> {dst} (sha256={compute_sha256(dst)})")
            staged_targets.append(str(dst))

    # 4. Also stage into com.apple.DocumentsApp if available
    files_cmd = ["xcrun", "simctl", "get_app_container", simulator_udid, "com.apple.DocumentsApp", "data"]
    f_res = runner(files_cmd, capture_output=True, text=True, check=False)
    if f_res.returncode == 0 and f_res.stdout.strip():
        files_container = Path(f_res.stdout.strip())
        files_docs = files_container / "Documents"
        files_docs.mkdir(parents=True, exist_ok=True)
        logs.append(f"Files data container: {files_container}")
        for fname in generated:
            src = fix_dir / fname
            dst = files_docs / fname
            shutil.copy2(src, dst)
            logs.append(f"Staged to Files {fname} -> {dst}")
            staged_targets.append(str(dst))

    if log_file:
        log_file.parent.mkdir(parents=True, exist_ok=True)
        log_file.write_text("\n".join(logs) + "\n", encoding="utf-8")

    return {
        "staged": True,
        "app_container": str(app_container) if app_container else None,
        "staged_targets": staged_targets,
        "logs": logs,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Stage ScriptUI fixtures into simulator app container")
    parser.add_argument("--simulator-udid", required=True, help="Target simulator UDID")
    parser.add_argument("--app-path", help="Path to tested .app bundle")
    parser.add_argument("--bundle-id", default="com.davidpovarsky.AI-HLY", help="Bundle identifier of the tested app")
    parser.add_argument("--fixtures-dir", help="Path to fixtures directory")
    parser.add_argument("--log-file", help="Path to write log output")
    parser.add_argument("--dry-run", action="store_true", help="Perform dry run without invoking simctl")

    args = parser.parse_args()

    app_p = Path(args.app_path).resolve() if args.app_path else None
    fix_p = Path(args.fixtures_dir).resolve() if args.fixtures_dir else None
    log_p = Path(args.log_file).resolve() if args.log_file else None

    res = stage_fixtures(
        simulator_udid=args.simulator_udid,
        app_path=app_p,
        bundle_id=args.bundle_id,
        fixtures_dir=fix_p,
        log_file=log_p,
        dry_run=args.dry_run,
    )

    for line in res["logs"]:
        print(line)

    return 0


if __name__ == "__main__":
    sys.exit(main())
