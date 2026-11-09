#!/usr/bin/env python3
"""Download a completed same-repository Runtime candidate, pinned by its ZIP SHA."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys


def validate_source(run, artifacts, repository, artifact_name):
    if (run.get("head_repository") or {}).get("full_name") != repository:
        raise ValueError("Runtime artifact source must belong to the same repository")
    if run.get("status") != "completed" or run.get("conclusion") != "success":
        raise ValueError("Runtime artifact source must have completed successfully")
    matches = [item for item in artifacts if item.get("name") == artifact_name and not item.get("expired")]
    if len(matches) != 1:
        raise ValueError("Expected one live Runtime bundle artifact")


def verify_archive(archive, expected_sha256):
    if not re.fullmatch(r"[a-f0-9]{64}", expected_sha256 or ""):
        raise ValueError("A verified Runtime bundle SHA-256 is required")
    digest = hashlib.sha256()
    with Path(archive).open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != expected_sha256:
        raise ValueError("Runtime candidate archive checksum mismatch")


def gh(*arguments):
    return subprocess.check_output(["gh", *arguments], text=True)


def download_candidate(repository, run_id, dependency_hash, expected_sha256, destination):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository) or any(part in (".", "..") for part in repository.split("/")):
        raise ValueError("Invalid Runtime source repository")
    if not re.fullmatch(r"[1-9][0-9]*", str(run_id)) or not re.fullmatch(r"[a-f0-9]{64}", dependency_hash):
        raise ValueError("Invalid Runtime source run or dependency hash")
    if not re.fullmatch(r"[a-f0-9]{64}", expected_sha256 or ""):
        raise ValueError("A verified Runtime bundle SHA-256 is required")
    name = f"hanlin-runtime-bundle-{dependency_hash}"
    run = json.loads(gh("api", f"repos/{repository}/actions/runs/{run_id}"))
    pages = json.loads(gh("api", f"repos/{repository}/actions/runs/{run_id}/artifacts", "--paginate", "--slurp"))
    artifacts = [item for page in pages for item in page["artifacts"]]
    validate_source(run, artifacts, repository, name)
    destination = Path(destination).resolve(strict=True)
    extracted = destination / "candidate-artifact"
    gh("run", "download", str(run_id), "--repo", repository, "--name", name, "--dir", str(extracted))
    archive_name = f"hanlin-runtime-{dependency_hash}.zip"
    archive = extracted / archive_name
    verify_archive(archive, expected_sha256)
    shutil.copyfile(archive, destination / archive_name)
    return destination / archive_name


if __name__ == "__main__":
    if len(sys.argv) != 6:
        raise SystemExit("Usage: runtime_bundle_source.py REPOSITORY RUN_ID DEPENDENCY_HASH SHA256 DESTINATION")
    print(download_candidate(*sys.argv[1:]))
