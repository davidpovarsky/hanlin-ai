"""Admit five exact old passes from one fixed failed six-case quota execution.

The failed original case and whole original run remain failed. No archived
code/product is executed, and no altered current declaration can reuse a pass.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import PurePosixPath
import re
import shutil
import stat
import tarfile
import zipfile

from continuation import require, hash_stream, validate_source_continuity


def parse_original_quota_failure(text, fixed, suite):
    """Accept only the observed closed six-case failure, returning its five passes."""
    text = re.sub(r"\x1b\[[0-9;]*m", "", text)
    required = suite["expectedMethods"]
    failed = fixed["failedMethod"]
    expected_passes = {name: count for name, count in required.items() if name != failed}
    require(len(required) == 6 and len(expected_passes) == 5 and all(x == 1 for x in required.values()),
            "Original quota obligation must remain the six original single cases")
    starts = re.findall(r"^◇ Test (\w+\(\)) started\.$", text, re.M)
    require(sorted(re.findall(r"^◇ Test (.+) started\.$", text, re.M)) == sorted(["run", *required]),
            "Foreign or duplicate original quota execution start")
    passed = re.findall(r"^✔ Test (\w+\(\)) passed after [^\n]+$", text, re.M)
    failed_methods = re.findall(r"^✘ Test (\w+\(\)) failed after [^\n]+ with 1 issue\.$", text, re.M)
    require(sorted(starts) == sorted(required) and sorted(passed) == sorted(expected_passes),
            "Missing, duplicate or foreign original quota start/pass")
    require(failed_methods == [failed], "A different original method failed")
    issues = re.findall(r"^✘ Test (\w+\(\)) recorded an issue at ([^\n]+)$", text, re.M)
    require(issues == [(failed, "ChatCodeFencePayloadRetentionTests.swift:44:9: Expectation failed: budget.snapshot == .init(bytes: 0, payloads: 0)")],
            "The observed original failure witness differs")
    require(re.findall(r"^✘ Test run with (\d+) tests in (\d+) suite failed after [^\n]+ with (\d+) issue\.$", text, re.M)
            == [("6", "1", "1")], "Original failed six-case summary differs")
    display = '"' + suite["displayName"] + '"' + " (aka '" + suite["suite"] + "')"
    require(re.findall(r"^◇ Suite (.+?) started\.$", text, re.M) == [display] and
            re.findall(r"^✘ Suite (.+?) failed after [^\n]+ with 1 issue\.$", text, re.M) ==
            [display], "Original failed suite differs")
    require("Snapshot(bytes: 13, payloads: 1)" in text and
            len(re.findall(r"^✔ Test .+$", text, re.M)) == 5 and
            len(re.findall(r"^✘ .+$", text, re.M)) == 4 and
            not re.search(r"^.*Test .+ skipped", text, re.M), "Unexpected original quota outcome")
    return {"status": "REUSED_FIVE_ACTUAL_PASSES_FROM_ORIGINAL_FAILED_SIX_CASE_SUITE",
            "suite": suite["suite"], "testModule": suite["testModule"],
            "methods": expected_passes, "methodCount": 5, "caseCount": 5, "arguments": {},
            "originalFailedMethod": failed, "originalSuiteStatus": "FAILED",
            "scope": "Five original named35d passes only; the failed cache fixture and whole original run are not relabeled."}


def validate_unchanged_declarations(original_test, current_test, fixed):
    names = []
    for row in fixed["unchangedDeclarations"]:
        source = row["originalDeclaration"].encode()
        require(len(source) == row["bytes"] and hashlib.sha256(source).hexdigest() == row["sha256"],
                "Reviewed unchanged declaration identity differs")
        require(original_test.count(source) == current_test.count(source) == 1,
                "An original passed test declaration changed or is ambiguous: " + row["method"])
        names.append(row["method"])
    require(len(names) == len(set(names)) == 5 and fixed["failedMethod"] not in names,
            "Reused quota declaration set differs")
    return names


def admit_quota_archive(archive, output, fixed, current_inventory, published_lock, control,
                        current_source, current_test):
    with archive.open("rb") as stream:
        size, digest = hash_stream(stream)
    require(size == fixed["artifactBytes"] and digest == fixed["artifactSHA256"], "Original quota ZIP bytes differ")
    prefix = f'{fixed["runID"]}-{fixed["attempt"]}/'
    with zipfile.ZipFile(archive) as bundle:
        members = bundle.infolist()
        require(len(members) == len({x.filename for x in members}) == 69 and
                sum(x.file_size for x in members) < 2 * 1024**3, "Original quota artifact member set/bound differs")
        for member in members:
            path = PurePosixPath(member.filename)
            require(not path.is_absolute() and ".." not in path.parts and
                    not stat.S_ISLNK(member.external_attr >> 16) and
                    (member.filename.startswith(prefix) or member.filename == "controller-tests.log"),
                    "Unsafe/foreign original quota artifact member")
        def raw(name):
            data = bundle.read(prefix + name)
            expected = fixed["members"].get(name)
            if expected:
                require(len(data) == expected["bytes"] and hashlib.sha256(data).hexdigest() == expected["sha256"],
                        "Original quota member differs: " + name)
            return data
        def value(name):
            return json.loads(raw(name))
        for name in fixed["members"]: raw(name)
        original_result = value("result.json")
        require(original_result.get("status") == "FAILED_BEFORE_COMPLETION" and
                original_result.get("error") == "payload-quota-tests failed; original log retained" and
                "productPreservationError" not in original_result, "Original quota failure classification differs")
        admitted = value("admitted-source.json")
        require(admitted["source"] == fixed["source"] and
                admitted["tree"] == control.CONFIG["reviewedSources"][fixed["source"]]["tree"] and
                admitted["protectedBlobs"] == control.protected_blobs(fixed["source"]), "Original quota source identity differs")
        require(value("controller-identity.json")["source"] == fixed["controllerSHA"], "Original quota controller differs")
        inputs = value("dispatch-inputs.json")
        require(inputs["exact_test_selector"] == control.CONFIG["continuation"]["selector"], "Original quota selector differs")
        control.validate_inputs(inputs, {"GITHUB_EVENT_NAME": "workflow_dispatch",
            "GITHUB_REPOSITORY": "davidpovarsky/hanlin-ai", "HANLIN_SDK_SOURCE_SHA": fixed["source"]})
        original_files = value("original-source-files.json")
        continuity = validate_source_continuity(original_files, current_inventory, current_source, fixed)
        expected_files = {row["path"]: row for row in original_files}
        require(len(expected_files) == len(original_files) == 1005, "Original quota source inventory differs")
        with bundle.open(prefix + "original-source.tar") as stream:
            size, digest = hash_stream(stream)
        require(size == fixed["originalSourceArchiveBytes"] and digest == fixed["originalSourceArchiveSHA256"],
                "Original quota source archive differs")
        found = set(); original_test = None
        with bundle.open(prefix + "original-source.tar") as stream, tarfile.open(fileobj=stream, mode="r|") as original:
            for member in original:
                path = PurePosixPath(member.name)
                require(not path.is_absolute() and ".." not in path.parts and (member.isdir() or member.isfile()),
                        "Unsafe original quota source member")
                if not member.isfile(): continue
                require(member.name in expected_files and member.name not in found, "Original quota source set differs")
                found.add(member.name); data = original.extractfile(member).read(); row = expected_files[member.name]
                require(len(data) == row["bytes"] and hashlib.sha256(data).hexdigest() == row["sha256"] and
                        control.blob_sha(data) == row["blob"] and
                        (member.mode & 0o111) == (0o111 if row["mode"] == "100755" else 0),
                        "Original quota source bytes/mode differ: " + member.name)
                if member.name == fixed["testPath"]: original_test = data
        require(found == set(expected_files) and original_test is not None, "Incomplete original quota source")
        unchanged = validate_unchanged_declarations(original_test, current_test, fixed)
        commands = value("commands.json")
        require(commands == original_result["commands"], "Original quota command receipts disagree")
        by_label = {row["label"]: row for row in commands}
        require(len(by_label) == len(commands) == 50, "Original quota command set differs")
        for command in commands:
            require(command["exitCode"] == (1 if command["label"] == "payload-quota-tests" else 0) and
                    not command.get("timedOut") and not command.get("interrupted"), "Original command outcome differs")
            custody = command.get("groupCustody", {})
            require(command.get("pid") == command.get("pgid") == custody.get("pgid") and
                    custody.get("groupAbsent") is True and custody.get("abnormalCleanup") is False and
                    custody.get("signals") == [], "Original quota command custody did not close normally")
            with bundle.open(prefix + command["log"]) as stream:
                _, digest = hash_stream(stream)
            require(digest == command["logSHA256"], "Original quota command output differs")
        suite = control.CONFIG["suites"][1]; command = by_label["payload-quota-tests"]; argv = command["argv"]
        require(argv[:4] == ["xcrun", "swift", "test", "--package-path"] and
                argv[4].endswith("/source/Packages/HanlinPresentationSDK") and
                argv[5] == "--scratch-path" and argv[6].endswith("/payload-quota-build") and
                argv[7:] == ["--force-resolved-versions", "--skip-update", "--jobs", "2", "--verbose", "--filter", suite["filter"]],
                "Original quota execution command differs")
        lock_path = output / "prior-quota-Package.resolved"
        require(not lock_path.exists(), "Original quota lock destination exists")
        lock_path.write_bytes(raw("payload-quota-Package.resolved"))
        lock = control.lock_records(lock_path)
        control.validate_lock(lock, published_lock, {"swift-ai-sdk", "swiftyjson", "opentelemetry-swift-core",
            "zipfoundation", "hanlin-streaming-markdown", "a2ui", "swiftsoup"})
        checkouts = value("payload-quota-checkouts.json")
        require(len(checkouts) == 18 and set(checkouts) == set(lock), "Original quota dependency set differs")
        for identity, checkout in checkouts.items():
            require(checkout["head"] == lock[identity]["revision"], "Original quota dependency revision differs")
            for action in ("checkout", "clean"):
                row = by_label["payload-quota-" + action + "-" + identity]
                tail = ["rev-parse", "HEAD"] if action == "checkout" else ["status", "--porcelain", "--untracked-files=all"]
                require(row["argv"] == ["git", "-C", checkout["path"], *tail] and
                        raw(row["log"]).decode().strip() == (checkout["head"] if action == "checkout" else ""),
                        "Original quota actual checkout/clean output differs")
        require(prefix + "payload-quota-posttest-checkouts.json" not in bundle.namelist(),
                "Original post-test check status changed; explicit review required")
        log = raw("payload-quota-tests.log").decode()
        require("Build complete! (120.60 sec)" in log, "Original quota compile completion absent")
        parsed = parse_original_quota_failure(log, fixed, suite)
        require(set(parsed["methods"]) == set(unchanged), "Reused methods do not match unchanged declarations")
        products = value("original-products.json")
        selected = [row for row in products if row["label"] == "payload-quota"]
        require(len(products) == 2 and len(selected) == 1, "Original quota product set differs")
        product = selected[0]
        require(product["archive"] == "payload-quota-original-products.tar" and
                product["bytes"] == fixed["originalProductArchiveBytes"] and
                product["sha256"] == fixed["originalProductArchiveSHA256"], "Original quota product receipt differs")
        destination = output / "prior-quota-original-products.tar"
        require(not destination.exists(), "Original quota product destination exists")
        with bundle.open(prefix + product["archive"]) as stream, destination.open("xb") as target:
            shutil.copyfileobj(stream, target, 1024 * 1024)
        with destination.open("rb") as stream: size, digest = hash_stream(stream)
        require(size == product["bytes"] and digest == product["sha256"], "Original quota product archive differs")
        expected_products = {row["path"]: row for row in product["files"]}; found = set()
        require(len(expected_products) == len(product["files"]) == 267, "Original quota product inventory differs")
        with tarfile.open(destination) as original:
            for member in original:
                path = PurePosixPath(member.name)
                require(not path.is_absolute() and ".." not in path.parts, "Unsafe inert original product member")
                if not member.isfile(): continue
                require(member.name in expected_products and member.name not in found, "Original quota product set differs")
                found.add(member.name)
                with original.extractfile(member) as stream: size, digest = hash_stream(stream)
                require(size == expected_products[member.name]["bytes"] and digest == expected_products[member.name]["sha256"],
                        "Original quota product file differs")
        require(found == set(expected_products) and any("HanlinChatUITests.xctest/Contents/MacOS/" in name for name in found),
                "Original executed quota bundle absent")
    origin = {"runID": fixed["runID"], "attempt": fixed["attempt"], "jobID": fixed["jobID"],
        "source": fixed["source"], "controller": fixed["controllerSHA"], "artifactID": fixed["artifactID"],
        "artifactSHA256": fixed["artifactSHA256"], "rawLogSHA256": fixed["members"]["payload-quota-tests.log"]["sha256"],
        "toolchainScope": fixed["originalToolchainScope"], "wholeOriginalRunStatus": "FAILED", "reexecuted": False}
    parsed["evidenceOrigin"] = origin
    retained_product = {**product, "label": "prior-quota", "archive": destination.name,
        "originalArchiveName": product["archive"], "evidenceOrigin": origin}
    return {"parsed": parsed, "product": retained_product,
        "admission": {"status": "PASS_FIVE_UNCHANGED_ORIGINAL_CASES_ONLY", "origin": origin,
            "sourceContinuity": continuity, "unchangedDeclarations": unchanged,
            "originalSourceFiles": 1005, "originalCommands": 50, "originalDependencies": 18, "originalProductFiles": 267,
            "originalQuotaResult": "SIX_EXECUTED_FIVE_PASS_ONE_FAIL", "originalFailedMethod": fixed["failedMethod"],
            "scope": "Original actual pre-test dependency/clean checks, locked command, full source/archive and compiled products are verified. Post-test checkout/source checks were NOT_REACHED after the genuine failure; no post-test receipt is invented. Only the five byte-identical passing declarations are reused; the corrected method must execute in the new source."}}
