"""Bind fresh publication and authenticated existing-build distribution to UI proof."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys
import zipfile

import gate
from run_app import snapshot


def gh_json(endpoint, paginate=False):
    args = ["gh", "api", endpoint]
    if paginate:
        args += ["--paginate", "--slurp"]
    return json.loads(subprocess.check_output(args))


def validate_origin(artifact, run, repository, build_number, policy):
    gate.require(artifact.get("name") == f"Hanlin-App-UI-{build_number}" and not artifact.get("expired"), "Missing/expired/wrong UI artifact")
    gate.require(run.get("status") == "completed" and run.get("conclusion") == "success", "Original release workflow did not complete successfully")
    gate.require(run.get("path") in policy["accepted_workflow_paths"] and run.get("event") == "workflow_dispatch", "Unapproved original release workflow/event")
    gate.require(run.get("repository", {}).get("full_name") == repository, "Foreign evidence repository")
    origin = artifact.get("workflow_run", {})
    gate.require(origin.get("id") == run.get("id") and origin.get("head_sha") == run.get("head_sha"), "Artifact/source/run mismatch")
    gate.require(origin.get("repository_id") == run["repository"]["id"] == origin.get("head_repository_id"), "Forked artifact source is not release proof")
    gate.require(re.fullmatch(r"[0-9a-f]{40}", run.get("head_sha", "")), "Original source SHA missing")
    gate.require(re.fullmatch(r"sha256:[0-9a-f]{64}", artifact.get("digest", "")), "Authenticated artifact digest missing")
    gate.require(0 < artifact.get("size_in_bytes", 0) <= 2 * 1024**3, "Invalid/oversized UI artifact")


def extract_verified(raw, artifact, output):
    gate.require("sha256:" + gate.digest(raw) == artifact["digest"], "Downloaded artifact ZIP digest mismatch")
    output.mkdir(parents=True, exist_ok=False)
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        gate.require(sum(item.file_size for item in archive.infolist()) <= 4 * 1024**3, "Expanded evidence exceeds bound")
        names = set()
        for item in archive.infolist():
            gate.require(item.filename not in names, "Duplicate archive member")
            names.add(item.filename)
            gate.require(not stat.S_ISLNK(item.external_attr >> 16), "Evidence archive symlink")
            path = gate.safe_path(output, item.filename.rstrip("/"))
            if item.is_dir():
                path.mkdir(parents=True, exist_ok=True)
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(archive.read(item))


def seal(repo: Path, evidence: Path, build_number: str, ipa: Path, run_id: str):
    sha = gate.git(repo, "rev-parse", "HEAD")
    result = gate.verify(evidence, build_number, sha)
    state = gate.read(evidence / "prepared-inputs.json")
    gate.require(snapshot(repo) == state, "Signed archive inputs differ from UI-tested prepared inputs")
    gate.require(ipa.is_file(), "Actual verified signed IPA missing")
    with zipfile.ZipFile(ipa) as archive:
        names = [name for name in archive.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info.plist", name)]
        gate.require(len(names) == 1, "Exactly one signed main application required")
        info = plistlib.loads(archive.read(names[0]))
    policy = gate.read(gate.POLICY_PATH)
    gate.require(info["CFBundleIdentifier"] == policy["app_bundle_id"] and str(info["CFBundleVersion"]) == build_number, "Signed IPA differs from UI-tested app/build")
    hasher = hashlib.sha256()
    with ipa.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(block)
    record = {"schema_version": 1, "scope": result["scope"], "source_sha": sha,
              "source_tree": state["source_tree"], "build_number": build_number,
              "upload_run_id": int(run_id), "ipa_sha256": hasher.hexdigest(),
              "app_bundle_id": info["CFBundleIdentifier"], "marketing_version": info["CFBundleShortVersionString"],
              "contract_sha256": result["contract_sha256"],
              "summary_sha256": gate.digest((evidence / "summary.json").read_bytes()),
              "prepared_inputs_sha256": gate.digest((evidence / "prepared-inputs.json").read_bytes())}
    gate.write(evidence / "release-binding.json", record)
    return {"status": "UI_GATE_PASS", "candidate_source_sha": sha, "build_number": build_number, "counts": result["counts"]}


def bind_uploaded(evidence: Path, readiness: Path):
    binding = gate.read(evidence / "release-binding.json")
    record = gate.read(readiness)
    gate.require(record.get("buildNumber") == binding["build_number"] and record.get("buildID") and record.get("appID"), "Uploaded build readback is missing/different")
    gate.require(record.get("sourceSHA", record.get("verificationSHA")) == binding["source_sha"], "Upload readback comes from a different release run")
    result = {"schema_version": 1, "source_sha": binding["source_sha"], "build_number": binding["build_number"],
              "app_store_build_id": record["buildID"], "app_store_app_id": record["appID"],
              "release_binding_sha256": gate.digest((evidence / "release-binding.json").read_bytes()),
              "readiness": record}
    gate.write(evidence / "uploaded-build.json", result)
    return {"status": "UPLOADED_BUILD_ID_BOUND", "build_number": binding["build_number"]}


def existing(repository: str, build_number: str, destination: Path):
    gate.require(re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository), "Invalid repository")
    gate.require(re.fullmatch(r"[0-9]+", build_number), "Exact existing build number required")
    policy = gate.read(gate.POLICY_PATH)
    gate.require(policy["same_build_reuse"] == "authenticated-original-successful-release-run-only", "Contract does not permit existing-build reuse")
    pages = gh_json(f"repos/{repository}/actions/artifacts?name=Hanlin-App-UI-{build_number}&per_page=100", paginate=True)
    matches = [a for page in pages for a in page["artifacts"] if a.get("name") == f"Hanlin-App-UI-{build_number}" and not a.get("expired")]
    gate.require(len(matches) == 1, "A unique authenticated original build UI artifact is required")
    artifact = gh_json(f"repos/{repository}/actions/artifacts/{matches[0]['id']}")
    run = gh_json(f"repos/{repository}/actions/runs/{artifact['workflow_run']['id']}")
    validate_origin(artifact, run, repository, build_number, policy)
    raw = subprocess.check_output(["gh", "api", f"repos/{repository}/actions/artifacts/{artifact['id']}/zip"])
    proof = destination / "original-ui-proof"
    extract_verified(raw, artifact, proof)
    binding = gate.read(proof / "release-binding.json")
    gate.require(binding.get("schema_version") == 1 and binding.get("build_number") == build_number, "Build receipt absent or for a different build")
    gate.require(binding.get("source_sha") == run["head_sha"] and binding.get("upload_run_id") == run["id"], "Uploaded build's source/run is not the UI-tested candidate")
    gate.require(binding.get("contract_sha256") == gate.digest(gate.POLICY_PATH.read_bytes()), "Versioned reuse contract changed")
    gate.require(re.fullmatch(r"[0-9a-f]{64}", binding.get("ipa_sha256", "")), "Original IPA binding absent")
    gate.require(binding.get("app_bundle_id") == policy["app_bundle_id"], "Uploaded IPA is for a different application")
    uploaded = gate.read(proof / "uploaded-build.json")
    gate.require(uploaded.get("source_sha") == run["head_sha"] and uploaded.get("build_number") == build_number, "Exact uploaded build/source provenance missing")
    gate.require(uploaded.get("release_binding_sha256") == gate.digest((proof / "release-binding.json").read_bytes()), "Uploaded build is not bound to this IPA/UI proof")
    gate.require(uploaded.get("app_store_build_id") and uploaded.get("app_store_app_id"), "Original App Store Connect build identity missing")
    gate.require(binding.get("summary_sha256") == gate.digest((proof / "summary.json").read_bytes()), "Original UI summary changed")
    gate.require(binding.get("prepared_inputs_sha256") == gate.digest((proof / "prepared-inputs.json").read_bytes()), "Original transitive/resource inputs changed")
    state = gate.read(proof / "prepared-inputs.json")
    gate.require(state["source_sha"] == binding["source_sha"] and state["source_tree"] == binding["source_tree"] and state.get("prepared_sha256"), "Incomplete original source/input provenance")
    result = gate.verify(proof, build_number, run["head_sha"])
    repo = Path.cwd()
    source = run["head_sha"]
    if subprocess.run(["git", "cat-file", "-e", source + "^{commit}"], capture_output=True).returncode:
        subprocess.run(["git", "fetch", "--no-tags", "--depth=1", "origin", source], check=True, capture_output=True)
    plan = gate.read(proof / "plan.json")
    gate.require(gate.git(repo, "rev-parse", source + "^{tree}") == plan["candidate_tree"] == binding["source_tree"], "Original full source tree differs")
    for path, expected in plan["inputs_sha256"].items():
        raw_input = subprocess.check_output(["git", "show", f"{source}:{path}"])
        gate.require(gate.digest(raw_input) == expected, "Original committed assertion/fixture/contract bytes differ")
    counts = {status: 0 for status in gate.STATUSES}
    counts["REUSED_VERIFIED_PASS"] = result["counts"]["EXECUTED_PASS"]
    receipt = {"status": "UI_GATE_PASS", "scope": result["scope"], "build_number": build_number,
               "candidate_source_sha": run["head_sha"], "counts": counts,
               "app_store_build_id": uploaded["app_store_build_id"], "app_store_app_id": uploaded["app_store_app_id"],
               "original_run_id": run["id"], "artifact_id": artifact["id"], "artifact_zip_sha256": gate.digest(raw),
               "reuse_basis": "The exact already-uploaded build and original successful release run; no cross-source, cross-build, partial-range or environment-substitution reuse."}
    gate.write(destination / "existing-build-ui-gate.json", receipt)
    return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["seal", "existing", "uploaded"])
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--ipa", type=Path)
    parser.add_argument("--repository")
    parser.add_argument("--run-id")
    parser.add_argument("--readiness", type=Path)
    args = parser.parse_args()
    try:
        if args.action == "seal":
            gate.require(args.ipa and args.run_id, "Actual IPA and original release run required")
            receipt = seal(Path.cwd().resolve(), args.evidence.resolve(), args.build_number, args.ipa, args.run_id)
        elif args.action == "existing":
            gate.require(args.repository, "Authenticated original repository required")
            receipt = existing(args.repository, args.build_number, args.evidence.resolve())
        else:
            gate.require(args.readiness, "Actual upload readback required")
            receipt = bind_uploaded(args.evidence, args.readiness)
        print(json.dumps(receipt))
    except (gate.GateError, OSError, KeyError, TypeError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        gate.write(args.evidence / "release-gate-rejection.json", {"status": "BLOCKED", "reason": str(error), "counts": {s: 0 for s in gate.STATUSES}})
        sys.exit(str(error))
