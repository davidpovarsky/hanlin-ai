"""Admit one immutable original Agent execution; never infer success from a failed run.

The caller downloads only the fixed Actions artifact. No archived code or product
is executed. Original bytes are verified before the named terminal is reparsed.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import tarfile
import zipfile


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def hash_stream(stream):
    digest = hashlib.sha256()
    count = 0
    for data in iter(lambda: stream.read(1024 * 1024), b""):
        digest.update(data)
        count += len(data)
    return count, digest.hexdigest()


def validate_api(run, jobs, artifact, fixed):
    require(run.get("id") == fixed["runID"] and run.get("run_attempt") == fixed["attempt"] and
            run.get("workflow_id") == fixed["workflowID"] and run.get("head_sha") == fixed["controllerSHA"] and
            run.get("head_branch") == fixed["controllerBranch"] and run.get("event") == "workflow_dispatch" and
            run.get("status") == "completed" and run.get("conclusion") == "failure" and
            run.get("repository", {}).get("full_name") == "davidpovarsky/hanlin-ai",
            "Original run identity/status differs from the fixed failed run")
    rows = jobs.get("jobs", [])
    require(jobs.get("total_count") == len(rows) == 28 and len({x.get("id") for x in rows}) == 28,
            "Original job list is incomplete or duplicated")
    selected = [x for x in rows if x.get("id") == fixed["jobID"]]
    require(len(selected) == 1, "Original SDK job absent")
    for row in rows:
        require(row.get("run_id") == fixed["runID"] and row.get("run_attempt") == fixed["attempt"] and
                row.get("head_sha") == fixed["controllerSHA"] and row.get("status") == "completed",
                "Original job provenance differs")
        require(row.get("conclusion") == ("failure" if row["id"] == fixed["jobID"] else "skipped"),
                "An unrelated original workflow job ran")
    steps = {x["name"]: x for x in selected[0].get("steps", [])}
    for name, conclusion in {
        "Verify closed controller without Apple or native operations": "success",
        "Test the explicit immutable original package source": "failure",
        "Preserve original source, locks, logs, products and every failure": "success",
    }.items():
        require(steps.get(name, {}).get("conclusion") == conclusion, "Original step outcome differs")
    require(artifact.get("id") == fixed["artifactID"] and artifact.get("name") == fixed["artifactName"] and
            artifact.get("size_in_bytes") == fixed["artifactBytes"] and artifact.get("expired") is False and
            artifact.get("digest") == "sha256:" + fixed["artifactSHA256"] and
            artifact.get("workflow_run", {}).get("id") == fixed["runID"] and
            artifact.get("workflow_run", {}).get("head_sha") == fixed["controllerSHA"],
            "Original artifact metadata differs")


def admit_archive(archive, output, fixed, source_inventory, published_lock, control):
    """Hash originals and actual outputs, then return only the exact Agent obligation."""
    with archive.open("rb") as stream:
        count, digest = hash_stream(stream)
    require(count == fixed["artifactBytes"] and digest == fixed["artifactSHA256"],
            "Original artifact ZIP bytes differ")
    prefix = f'{fixed["runID"]}-{fixed["attempt"]}/'
    with zipfile.ZipFile(archive) as bundle:
        names = [x.filename for x in bundle.infolist()]
        require(len(names) == len(set(names)) == 49, "Original artifact member set differs")
        require(sum(x.file_size for x in bundle.infolist()) < 1024**3, "Unbounded original artifact")
        for info in bundle.infolist():
            path = PurePosixPath(info.filename)
            require(not path.is_absolute() and ".." not in path.parts and
                    not stat.S_ISLNK(info.external_attr >> 16), "Unsafe original artifact member")
            require(info.filename.startswith(prefix) or info.filename == "controller-tests.log",
                    "Foreign run in original artifact")
        def raw(name):
            data = bundle.read(prefix + name)
            expected = fixed["members"].get(name)
            if expected is not None:
                require(len(data) == expected["bytes"] and hashlib.sha256(data).hexdigest() == expected["sha256"],
                        "Original artifact member differs: " + name)
            return data
        def value(name):
            return json.loads(raw(name))
        for name in fixed["members"]:
            raw(name)
        original_result = value("result.json")
        require(original_result.get("status") == "FAILED_BEFORE_COMPLETION" and
                original_result.get("error") == "Wrong executed method count" and
                "productPreservationError" not in original_result,
                "Only the observed parser failure can be continued")
        admitted = value("admitted-source.json")
        require(admitted["source"] == fixed["source"] and
                admitted["tree"] == control.CONFIG["reviewedSources"][fixed["source"]]["tree"] and
                admitted["protectedBlobs"] == control.CONFIG["protectedBlobs"],
                "Original source qualification differs")
        identity = value("controller-identity.json")
        require(identity["source"] == fixed["controllerSHA"], "Original controller differs")
        inputs = value("dispatch-inputs.json")
        require(inputs["exact_test_selector"] == control.CONFIG["selector"], "Original selector differs")
        control.validate_inputs(inputs, {"GITHUB_EVENT_NAME": "workflow_dispatch",
            "GITHUB_REPOSITORY": "davidpovarsky/hanlin-ai", "HANLIN_SDK_SOURCE_SHA": fixed["source"]})
        original_files = value("original-source-files.json")
        require(original_files == source_inventory, "Original execution source inventory differs from current immutable source")
        expected_files = {row["path"]: row for row in original_files}
        require(len(expected_files) == len(original_files), "Duplicate original source identity")
        with bundle.open(prefix + "original-source.tar") as stream:
            count, digest = hash_stream(stream)
        require(count == fixed["originalSourceArchiveBytes"] and digest == fixed["originalSourceArchiveSHA256"],
                "Original source archive bytes differ")
        found = set()
        with bundle.open(prefix + "original-source.tar") as stream, tarfile.open(fileobj=stream, mode="r|") as source:
            for member in source:
                path = PurePosixPath(member.name)
                require(not path.is_absolute() and ".." not in path.parts and (member.isfile() or member.isdir()),
                        "Unsafe original source archive")
                if not member.isfile():
                    continue
                require(member.name in expected_files and member.name not in found, "Original source archive set differs")
                found.add(member.name)
                data = source.extractfile(member).read()
                row = expected_files[member.name]
                require(len(data) == row["bytes"] and hashlib.sha256(data).hexdigest() == row["sha256"] and
                        control.blob_sha(data) == row["blob"] and
                        (member.mode & 0o111) == (0o111 if row["mode"] == "100755" else 0),
                        "Original source archive differs from immutable Git: " + member.name)
        require(found == set(expected_files), "Original source archive is incomplete")
        commands = value("commands.json")
        require(commands == original_result["commands"], "Original command receipts disagree")
        by_label = {row["label"]: row for row in commands}
        require(len(by_label) == len(commands) == 34, "Original command set differs")
        for command in commands:
            require(command.get("exitCode") == 0 and not command.get("timedOut") and not command.get("interrupted"),
                    "Original command did not finish successfully")
            custody = command.get("groupCustody", {})
            require(command.get("pgid") == command.get("pid") == custody.get("pgid") and
                    custody.get("groupAbsent") is True and custody.get("abnormalCleanup") is False and
                    custody.get("signals") == [], "Original process custody was not closed normally")
            require(hashlib.sha256(raw(command["log"])).hexdigest() == command["logSHA256"],
                    "Original command output differs")
        suite = control.CONFIG["suites"][0]
        executed = by_label["agent-stop-tests"]
        argv = executed["argv"]
        require(argv[:4] == ["xcrun", "swift", "test", "--package-path"] and
                argv[4].endswith("/source/Packages/HanlinAgentSDK") and
                argv[5] == "--scratch-path" and argv[6].endswith("/agent-stop-build") and
                argv[7:] == ["--force-resolved-versions", "--skip-update", "--jobs", "2", "--verbose", "--filter", suite["filter"]],
                "Original selected Swift test command differs")
        lock_path = output / "agent-stop-Package.resolved"
        require(not lock_path.exists(), "Original lock evidence destination already exists")
        lock_path.write_bytes(raw("agent-stop-Package.resolved"))
        lock = control.lock_records(lock_path)
        control.validate_lock(lock, published_lock, {"swift-ai-sdk", "swiftyjson", "opentelemetry-swift-core", "zipfoundation"})
        before = value("agent-stop-checkouts.json")
        after = value("agent-stop-posttest-checkouts.json")
        require(before == after and set(before) == set(lock), "Original actual dependency checkouts changed")
        for identity, checkout in before.items():
            require(checkout["head"] == lock[identity]["revision"], "Original checkout differs from locked revision")
            for prefix_label in ("agent-stop", "agent-stop-posttest"):
                for action in ("checkout", "clean"):
                    row = by_label[prefix_label + "-" + action + "-" + identity]
                    expected_tail = ["rev-parse", "HEAD"] if action == "checkout" else ["status", "--porcelain", "--untracked-files=all"]
                    require(row["argv"] == ["git", "-C", checkout["path"], *expected_tail], "Original checkout command differs")
                    observed = raw(row["log"]).decode().strip()
                    require(observed == (checkout["head"] if action == "checkout" else ""), "Original checkout output differs")
        parsed = control.parse_swift_testing(raw("agent-stop-tests.log").decode(), suite)
        products = value("original-products.json")
        require(len(products) == 1 and products[0]["label"] == "agent-stop", "Original executed product set differs")
        product = products[0]
        require(product["archive"] == "agent-stop-original-products.tar" and
                product["bytes"] == fixed["originalProductArchiveBytes"] and
                product["sha256"] == fixed["originalProductArchiveSHA256"], "Original product receipt differs")
        destination = output / product["archive"]
        require(not destination.exists(), "Original product evidence destination already exists")
        with bundle.open(prefix + product["archive"]) as stream, destination.open("xb") as target:
            shutil.copyfileobj(stream, target, 1024 * 1024)
        with destination.open("rb") as stream:
            count, digest = hash_stream(stream)
        require(count == product["bytes"] and digest == product["sha256"], "Original product archive bytes differ")
        expected_products = {row["path"]: row for row in product["files"]}
        require(len(expected_products) == len(product["files"]) == 203, "Original product inventory differs")
        found = set()
        with tarfile.open(destination) as original_products:
            for member in original_products:
                path = PurePosixPath(member.name)
                require(not path.is_absolute() and ".." not in path.parts, "Unsafe original product member")
                # Preserve original framework symlinks as inert archive bytes;
                # never extract or follow them or execute an archived binary.
                if not member.isfile():
                    continue
                require(member.name in expected_products and member.name not in found, "Original product member set differs")
                found.add(member.name)
                with original_products.extractfile(member) as stream:
                    count, digest = hash_stream(stream)
                row = expected_products[member.name]
                require(count == row["bytes"] and digest == row["sha256"], "Original product inventory bytes differ")
        require(found == set(expected_products) and
                any("HanlinAgentCoreTests.xctest/Contents/MacOS/" in name for name in found),
                "Original executed Agent test binary is absent")
    origin = {"runID": fixed["runID"], "attempt": fixed["attempt"], "jobID": fixed["jobID"],
              "controller": fixed["controllerSHA"], "source": fixed["source"],
              "artifactID": fixed["artifactID"], "artifactSHA256": fixed["artifactSHA256"],
              "rawLogSHA256": fixed["members"]["agent-stop-tests.log"]["sha256"],
              "toolchainScope": fixed["originalToolchainScope"], "reexecuted": False}
    parsed["evidenceOrigin"] = origin
    product["evidenceOrigin"] = origin
    return {"parsed": parsed, "product": product,
            "resolvedLock": {"sha256": fixed["members"]["agent-stop-Package.resolved"]["sha256"], "pins": lock},
            "admission": {"status": "PASS_REPARSED_ORIGINAL_AGENT_EXECUTION_ONLY", "origin": origin,
                "originalFailedResultPreserved": True, "originalResultStatus": original_result["status"],
                "originalError": original_result["error"], "sourceFiles": len(original_files),
                "originalCommandCount": len(commands), "originalDependencyCount": len(lock),
                "originalProductFiles": len(expected_products), "methodCount": parsed["methodCount"],
                "caseCount": parsed["caseCount"],
                "scope": "Original compile-input Git/archive identities, actual dependency pre/post checks, normal process-group absence, exact named terminal and compiled products. Original controller failed before its final all-suite source check; it is never relabeled as an overall successful run. New remaining suites and final current-source check are separate."}}
