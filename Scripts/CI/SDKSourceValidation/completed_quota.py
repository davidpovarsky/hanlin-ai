"""Admit one actual 0ae quota pass from its fixed parser-failed original run.

The entire original run remains failed. This reader executes no archived code
or product. Full ZIP, source, dependency, command and product bytes are required
before the one named pass can avoid a duplicate compile/test.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import PurePosixPath
import shutil
import stat
import tarfile
import zipfile

from continuation import require, hash_stream, validate_source_continuity


def validate_recorded_scope(raw, fixed, current_inventory, control, current_source):
    """Validate recorded metadata only; this is never full archive admission."""
    value = lambda name: json.loads(raw(name))
    require(current_source == fixed["source"], "Completed quota reuse requires the identical immutable source")
    original_result = value("result.json")
    require(original_result.get("status") == "FAILED_BEFORE_COMPLETION" and
            original_result.get("error") == fixed["originalParserFailure"] and
            "productPreservationError" not in original_result and "suiteResults" not in original_result,
            "Only the exact observed post-test suite-name parser failure is admitted")
    admitted = value("admitted-source.json")
    require(admitted["source"] == fixed["source"] and
            admitted["tree"] == control.CONFIG["reviewedSources"][fixed["source"]]["tree"] and
            admitted["protectedBlobs"] == control.protected_blobs(fixed["source"]),
            "Original completed quota source identity differs")
    require(value("controller-identity.json")["source"] == fixed["controllerSHA"],
            "Original completed quota controller differs")
    inputs = value("dispatch-inputs.json")
    require(inputs["exact_test_selector"] == control.CONFIG["continuation"]["selector"],
            "Original completed quota selector differs")
    control.validate_inputs(inputs, {"GITHUB_EVENT_NAME": "workflow_dispatch",
        "GITHUB_REPOSITORY": "davidpovarsky/hanlin-ai", "HANLIN_SDK_SOURCE_SHA": fixed["source"]})
    original_files = value("original-source-files.json")
    continuity = validate_source_continuity(original_files, current_inventory, current_source, fixed)
    require(len(original_files) == 1005, "Original completed quota inventory differs")
    commands = value("commands.json")
    require(commands == original_result["commands"], "Original completed quota command receipts disagree")
    by_label = {row["label"]: row for row in commands}
    require(len(by_label) == len(commands) == 90, "Original completed quota command set differs")
    for command in commands:
        require(command["exitCode"] == 0 and not command.get("timedOut") and not command.get("interrupted"),
                "Original completed quota command failed or was interrupted")
        custody = command.get("groupCustody", {})
        require(command.get("pid") == command.get("pgid") == custody.get("pgid") and
                custody.get("groupAbsent") is True and custody.get("abnormalCleanup") is False and
                custody.get("signals") == [], "Original completed quota process group did not close normally")
    suite = control.selected_quota_suite(control.CONFIG["suites"][1], True)
    require(suite["expectedMethods"] == {fixed["method"]: 1}, "Completed quota selector changed")
    argv = by_label["payload-quota-tests"]["argv"]
    require(argv[:4] == ["xcrun", "swift", "test", "--package-path"] and
            argv[4].endswith("/source/Packages/HanlinPresentationSDK") and
            argv[5] == "--scratch-path" and argv[6].endswith("/payload-quota-build") and
            argv[7:] == ["--force-resolved-versions", "--skip-update", "--jobs", "2", "--verbose", "--filter", suite["filter"]],
            "Original completed quota execution command differs")
    checkouts = value("payload-quota-checkouts.json")
    require(checkouts == value("payload-quota-posttest-checkouts.json") and len(checkouts) == 18,
            "Original completed quota before/after dependency state differs")
    lock = value("payload-quota-Package.resolved")
    pins = {pin["identity"]: pin["state"]["revision"] for pin in lock["pins"]}
    require(len(pins) == len(lock["pins"]) == 18 and set(pins) == set(checkouts),
            "Original completed quota lock/dependency set differs")
    for identity, checkout in checkouts.items():
        require(checkout["head"] == pins[identity], "Original completed quota dependency revision differs")
        for phase in ("payload-quota", "payload-quota-posttest"):
            for action in ("checkout", "clean"):
                row = by_label[phase + "-" + action + "-" + identity]
                tail = ["rev-parse", "HEAD"] if action == "checkout" else ["status", "--porcelain", "--untracked-files=all"]
                require(row["argv"] == ["git", "-C", checkout["path"], *tail],
                        "Original completed quota checkout/clean command differs")
    products = value("original-products.json")
    require(len(products) == 3 and {x["label"] for x in products} == {"agent-stop", "prior-quota", "payload-quota"},
            "Original completed quota product set differs")
    product = next(x for x in products if x["label"] == "payload-quota")
    require("evidenceOrigin" not in product and product["archive"] == "payload-quota-original-products.tar" and
            product["bytes"] == fixed["originalProductArchiveBytes"] and
            product["sha256"] == fixed["originalProductArchiveSHA256"] and len(product["files"]) == 267,
            "Original current-run quota product receipt differs")
    return {"continuity": continuity, "files": original_files, "commands": commands,
            "byLabel": by_label, "checkouts": checkouts, "suite": suite, "product": product,
            "fullArchiveAdmission": False}


def admit_completed_quota_archive(archive, output, fixed, current_inventory, published_lock, control, current_source):
    with archive.open("rb") as stream:
        size, digest = hash_stream(stream)
    require(size == fixed["artifactBytes"] and digest == fixed["artifactSHA256"],
            "Original completed quota ZIP bytes differ")
    prefix = f'{fixed["runID"]}-{fixed["attempt"]}/'
    with zipfile.ZipFile(archive) as bundle:
        members = bundle.infolist()
        require(len(members) == len({x.filename for x in members}) == 114 and
                sum(x.file_size for x in members) < 2 * 1024**3,
                "Original completed quota artifact member set/bound differs")
        for member in members:
            path = PurePosixPath(member.filename)
            require(not path.is_absolute() and ".." not in path.parts and
                    not stat.S_ISLNK(member.external_attr >> 16) and
                    (member.filename.startswith(prefix) or member.filename == "controller-tests.log"),
                    "Unsafe/foreign original completed quota member")
        def raw(name):
            data = bundle.read(prefix + name)
            expected = fixed["members"].get(name)
            if expected:
                require(len(data) == expected["bytes"] and hashlib.sha256(data).hexdigest() == expected["sha256"],
                        "Original completed quota member differs: " + name)
            return data
        for name in fixed["members"]: raw(name)
        recorded = validate_recorded_scope(raw, fixed, current_inventory, control, current_source)
        evidence = json.loads(raw("evidence-files.json"))
        require(len(evidence) == len({x["path"] for x in evidence}) == 112 and
                {x.filename for x in members} == {prefix + x["path"] for x in evidence} |
                {prefix + "evidence-files.json", "controller-tests.log"}, "Original complete member inventory differs")
        for absent in ("payload-quota-actual-results.json", "widgets-actual-results.json", "resolved-locks.json"):
            require(prefix + absent not in bundle.namelist(), "An original unexecuted post-parser stage was relabeled")
        expected_files = {row["path"]: row for row in recorded["files"]}
        with bundle.open(prefix + "original-source.tar") as stream:
            size, digest = hash_stream(stream)
        require(size == fixed["originalSourceArchiveBytes"] and digest == fixed["originalSourceArchiveSHA256"],
                "Original completed quota source archive differs")
        found = set(); original_test = None
        with bundle.open(prefix + "original-source.tar") as stream, tarfile.open(fileobj=stream, mode="r|") as original:
            for member in original:
                path = PurePosixPath(member.name)
                require(not path.is_absolute() and ".." not in path.parts and (member.isdir() or member.isfile()),
                        "Unsafe original completed quota source member")
                if not member.isfile(): continue
                require(member.name in expected_files and member.name not in found, "Original completed quota source set differs")
                found.add(member.name); data = original.extractfile(member).read(); row = expected_files[member.name]
                require(len(data) == row["bytes"] and hashlib.sha256(data).hexdigest() == row["sha256"] and
                        control.blob_sha(data) == row["blob"] and
                        (member.mode & 0o111) == (0o111 if row["mode"] == "100755" else 0),
                        "Original completed quota source bytes/mode differ: " + member.name)
                if member.name == fixed["testPath"]: original_test = data
        require(found == set(expected_files) and original_test is not None, "Incomplete original completed quota source")
        suite = recorded["suite"]
        require(original_test.count(('@Suite("' + suite["displayName"] + '")').encode()) == 1 and
                original_test.count(('struct ' + suite["suite"] + ': Sendable {').encode()) == 1,
                "The printed suite alias is not the exact original source declaration")
        for command in recorded["commands"]:
            with bundle.open(prefix + command["log"]) as stream: _, digest = hash_stream(stream)
            require(digest == command["logSHA256"], "Original completed quota command output differs")
        for identity, checkout in recorded["checkouts"].items():
            for phase in ("payload-quota", "payload-quota-posttest"):
                for action in ("checkout", "clean"):
                    row = recorded["byLabel"][phase + "-" + action + "-" + identity]
                    require(raw(row["log"]).decode().strip() == (checkout["head"] if action == "checkout" else ""),
                            "Original completed quota actual before/after checkout or clean output differs")
        lock_path = output / "completed-quota-Package.resolved"
        require(not lock_path.exists(), "Original completed quota lock destination exists")
        lock_path.write_bytes(raw("payload-quota-Package.resolved"))
        lock = control.lock_records(lock_path)
        control.validate_lock(lock, published_lock, {"swift-ai-sdk", "swiftyjson", "opentelemetry-swift-core",
            "zipfoundation", "hanlin-streaming-markdown", "a2ui", "swiftsoup"})
        require(set(lock) == set(recorded["checkouts"]), "Original completed quota locked graph differs")
        log = raw("payload-quota-tests.log").decode()
        require("Build complete! (141.33 sec)" in log, "Original completed quota compile completion absent")
        parsed = control.parse_swift_testing(log, suite)
        product = recorded["product"]
        destination = output / product["archive"]
        require(not destination.exists(), "Original completed quota product destination exists")
        with bundle.open(prefix + product["archive"]) as stream, destination.open("xb") as target:
            shutil.copyfileobj(stream, target, 1024 * 1024)
        with destination.open("rb") as stream: size, digest = hash_stream(stream)
        require(size == product["bytes"] and digest == product["sha256"], "Original completed quota product archive differs")
        expected_products = {row["path"]: row for row in product["files"]}; found = set()
        require(len(expected_products) == len(product["files"]) == 267, "Original completed quota product inventory differs")
        with tarfile.open(destination) as original:
            for member in original:
                path = PurePosixPath(member.name)
                require(not path.is_absolute() and ".." not in path.parts, "Unsafe inert original completed product member")
                if not member.isfile(): continue
                require(member.name in expected_products and member.name not in found, "Original completed quota product set differs")
                found.add(member.name)
                with original.extractfile(member) as stream: size, digest = hash_stream(stream)
                require(size == expected_products[member.name]["bytes"] and digest == expected_products[member.name]["sha256"],
                        "Original completed quota product file differs")
        require(found == set(expected_products) and any("HanlinChatUITests.xctest/Contents/MacOS/" in name for name in found),
                "Original completed quota executed bundle absent")
    origin = {"runID": fixed["runID"], "attempt": fixed["attempt"], "jobID": fixed["jobID"],
        "source": fixed["source"], "controller": fixed["controllerSHA"], "artifactID": fixed["artifactID"],
        "artifactSHA256": fixed["artifactSHA256"], "rawLogSHA256": fixed["members"]["payload-quota-tests.log"]["sha256"],
        "toolchainScope": fixed["originalToolchainScope"], "wholeOriginalRunStatus": "FAILED", "reexecuted": False}
    parsed["evidenceOrigin"] = origin
    return {"parsed": parsed, "product": {**product, "evidenceOrigin": origin},
        "resolvedLock": {"sha256": control.sha256(lock_path), "pins": lock}, "lockPath": str(lock_path),
        "admission": {"status": "PASS_ONE_ACTUAL_ORIGINAL_CASE_ONLY", "origin": origin,
            "sourceContinuity": recorded["continuity"], "originalSourceFiles": 1005,
            "originalCommands": 90, "originalDependenciesBeforeAndAfter": 18, "originalProductFiles": 267,
            "fullArchiveAdmission": True,
            "scope": "One actual original0ae case passed before the exact suite-name parser failure. Full source/product archives, all original command outputs/process groups and both dependency/clean snapshots are verified. Final all-suite source checks, Widgets and iOS were NOT_REACHED; no such receipt is invented. No archived code or product is executed."}}
