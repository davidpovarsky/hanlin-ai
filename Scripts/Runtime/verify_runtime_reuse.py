#!/usr/bin/env python3
"""Fail-closed reuse of native components; the current Host is always rebuilt.

GitHub metadata must be fetched with the authenticated API for this repository.
This verifies component production, not simulator/app/physical acceptance.
"""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import tempfile
import zipfile

from runtime_native_identity import native_identity

COMPONENTS = {
    "node-device": ("node-mobile-device", "build-node-device", "Build one Node slice with heartbeat"),
    "node-simulator": ("node-mobile-simulator", "build-node-simulator", "Build one Node slice with heartbeat"),
    "python": ("python-runtime", "prepare-python-runtime", "Prepare verified prebuilt Python runtime"),
}
WORKFLOWS = {".github/workflows/build-runtime-bundle.yml", ".github/workflows/build-ios26-unsigned-ipa.yml"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def positive_id(value):
    require(type(value) is int and value > 0, "Invalid GitHub object ID")
    return value


def instant(value):
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    require(parsed.year >= 2020 and parsed.tzinfo is not None, "Missing actual execution timestamp")
    return parsed


def validate_source(run, repository):
    require(re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository), "Invalid repository")
    require(run.get("repository", {}).get("full_name") == repository and
            run.get("head_repository", {}).get("full_name") == repository, "Foreign source repository")
    require(run.get("status") == "completed", "Source run is still mutable/in progress")
    require(run.get("path") in WORKFLOWS, "Unexpected producer workflow")
    require(re.fullmatch(r"[0-9a-f]{40}", run.get("head_sha", "")), "Invalid producer source SHA")
    positive_id(run.get("id"))
    positive_id(run["repository"].get("id"))
    positive_id(run["head_repository"].get("id"))
    return run["head_sha"]


def verify(run, jobs, artifacts, repository, dependency_hash, producer_identity, current_identity,
           source_dependency_hash=None):
    source_sha = validate_source(run, repository)
    require(re.fullmatch(r"[0-9a-f]{64}", dependency_hash), "Invalid dependency identity")
    source_dependency_hash = source_dependency_hash or dependency_hash
    require(re.fullmatch(r"[0-9a-f]{64}", source_dependency_hash), "Invalid producer dependency identity")
    require(re.fullmatch(r"[0-9a-f]{64}", producer_identity) and producer_identity == current_identity,
            "Native binary inputs changed; rebuild native components")
    receipt = {"schemaVersion": 1, "status": "REUSED_VERIFIED_PASS", "scope": "native-component-production-only",
               "repository": repository, "sourceRunID": run["id"], "sourceSHA": source_sha,
               "sourceRunConclusion": run.get("conclusion"), "nativeInputSHA256": current_identity,
               "sourceDependencyHash": source_dependency_hash,
               "consumerDependencyHash": dependency_hash, "components": {}}
    for directory, (prefix, job_name, step_name) in COMPONENTS.items():
        # Reruns may clone successful jobs with zero steps. Those are not new evidence.
        executed = [job for job in jobs if job.get("name", "").split(" / ")[-1] == job_name
                    and any(step.get("name") == step_name for step in job.get("steps", []))]
        require(executed, f"No actual producer execution for {directory}")
        # GitHub also clones old step timestamps into successful rerun jobs. Pick
        # the original attempt for an identical execution interval, never credit
        # the cloned job as another actual build.
        job = max(executed, key=lambda item: (
            instant(next(step["started_at"] for step in item["steps"] if step.get("name") == step_name)),
            -positive_id(item.get("run_attempt")), -positive_id(item.get("id"))))
        require(job.get("run_id") == run["id"] and job.get("head_sha") == source_sha,
                f"Wrong producer job source for {directory}")
        require(job.get("status") == "completed" and job.get("conclusion") == "success",
                f"Latest actual {directory} production did not pass")
        step = next(step for step in job["steps"] if step.get("name") == step_name)
        require(step.get("status") == "completed" and step.get("conclusion") == "success",
                f"Producer step did not pass for {directory}")
        start, finish = instant(step["started_at"]), instant(job["completed_at"])
        require(start <= instant(step["completed_at"]) <= finish, "Invalid producer execution interval")
        name = f"{prefix}-{source_dependency_hash}"
        candidates = [artifact for artifact in artifacts if artifact.get("name") == name]
        require(len(candidates) == 1, f"Missing or ambiguous producer artifact: {name}")
        artifact = candidates[0]
        positive_id(artifact.get("id"))
        require(artifact.get("expired") is False and type(artifact.get("size_in_bytes")) is int
                and artifact["size_in_bytes"] > 0, f"Expired/empty artifact: {name}")
        require(re.fullmatch(r"sha256:[0-9a-f]{64}", artifact.get("digest", "")), "Missing archive digest")
        source = artifact.get("workflow_run", {})
        require(source.get("id") == run["id"] and source.get("head_sha") == source_sha
                and source.get("repository_id") == run["repository"]["id"]
                and source.get("head_repository_id") == run["head_repository"]["id"], "Artifact source mismatch")
        require(start <= instant(artifact["created_at"]) <= instant(artifact["updated_at"]) <= finish,
                f"Artifact does not belong to the successful component execution: {name}")
        receipt["components"][directory] = {"artifactID": artifact["id"], "artifactName": name,
            "archiveDigest": artifact["digest"], "producerJobID": job["id"], "producerAttempt": job["run_attempt"]}
    return receipt


def extract_verified(archive, digest, destination):
    with archive.open("rb") as stream:
        require("sha256:" + hashlib.file_digest(stream, "sha256").hexdigest() == digest, "Artifact archive digest mismatch")
    with zipfile.ZipFile(archive) as zipped:
        for member in zipped.infolist():
            path = PurePosixPath(member.filename)
            require(member.orig_filename == member.filename and "\x00" not in member.orig_filename
                    and not path.is_absolute() and ".." not in path.parts and "\\" not in member.filename
                    and not re.match(r"^[A-Za-z]:", member.filename), "Unsafe artifact archive path")
            require(not stat.S_ISLNK(member.external_attr >> 16), "Artifact envelope contains a symlink")
        zipped.extractall(destination)


def download(receipt, destination):
    repository = receipt["repository"]
    require(re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository), "Invalid repository")
    require(set(receipt["components"]) == set(COMPONENTS), "Incomplete native receipt")
    destination.mkdir(parents=True, exist_ok=True)
    for directory, component in receipt["components"].items():
        artifact_id = positive_id(component["artifactID"])
        with tempfile.TemporaryDirectory(prefix="native-download-", dir=destination) as temporary:
            archive = Path(temporary) / "artifact.zip"
            with archive.open("wb") as stream:
                result = subprocess.run(["gh", "api", f"repos/{repository}/actions/artifacts/{artifact_id}/zip"],
                                        stdout=stream, stderr=subprocess.PIPE)
            # Never expose redirect URLs or signed query strings from a failed download.
            require(result.returncode == 0, f"GitHub artifact download failed for ID {artifact_id}")
            extract_verified(archive, component["archiveDigest"], destination / directory)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-run", type=Path)
    parser.add_argument("--source-jobs", type=Path)
    parser.add_argument("--source-artifacts", type=Path)
    parser.add_argument("--repository-name")
    parser.add_argument("--dependency-hash")
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--print-source-sha", action="store_true")
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--download-to", type=Path)
    args = parser.parse_args()
    if args.download_to:
        download(json.loads(args.receipt.read_bytes()), args.download_to)
        return
    run = json.loads(args.source_run.read_bytes())
    source_sha = validate_source(run, args.repository_name)
    if args.print_source_sha:
        print(source_sha)
        return
    receipt = verify(run, json.loads(args.source_jobs.read_bytes())["jobs"],
                     json.loads(args.source_artifacts.read_bytes())["artifacts"], args.repository_name,
                     args.dependency_hash, native_identity(args.repository, source_sha), native_identity(args.repository),
                     source_dependency_hash(args.repository, source_sha))
    receipt["consumerSHA"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=args.repository, text=True).strip()
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    args.receipt.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(f"Verified native component production from run {run['id']}; current Host and smoke remain required.")


def source_dependency_hash(repository, revision):
    with tempfile.TemporaryDirectory(prefix="native-producer-lock-") as temporary:
        lock = Path(temporary) / "RuntimeDependencies.lock.json"
        lock.write_bytes(subprocess.check_output(["git", "show", f"{revision}:RuntimeDependencies.lock.json"], cwd=repository))
        return subprocess.check_output(["node", str(repository / "Scripts/Runtime/compute-runtime-dependency-hash.mjs"),
                                        str(lock)], text=True, cwd=repository).strip()


if __name__ == "__main__":
    main()
