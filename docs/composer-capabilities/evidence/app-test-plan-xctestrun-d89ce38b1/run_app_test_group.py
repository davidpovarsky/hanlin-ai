#!/usr/bin/env python3
"""Root-owned focused test-without-building execution; dry command output by default."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import time
import urllib.parse
import xml.etree.ElementTree as ET

def stamp():
    return datetime.now(timezone.utc).isoformat()

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def save(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")

def objects(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from objects(child)

def identity(node):
    raw = str(node.get("nodeIdentifier") or "")
    url = str(node.get("nodeIdentifierURL") or "")
    if not raw and url:
        parts = urllib.parse.unquote(urllib.parse.urlsplit(url).path).strip("/").split("/")
        raw = "/".join(parts[-2:])
    return raw, url

def normalized(raw):
    # XCTest may report empty parentheses; Swift Testing parameter labels remain intact.
    return raw[:-2] if raw.endswith("()") else raw

def inspect_results(group, summary, tree):
    problems = []
    expected = {normalized(case["relativeIdentity"]): case for case in group["cases"]}
    observed = {}
    for node in objects(tree.get("testNodes", [])):
        if node.get("nodeType") != "Test Case":
            continue
        raw, url = identity(node)
        key = normalized(raw)
        # A target prefix is permitted only if it is the expected target.
        for case in group["cases"]:
            prefix = case["target"] + "/"
            if key.startswith(prefix):
                key = key[len(prefix):]
                break
        observed.setdefault(key, []).append(node)
    if not observed:
        problems.append("ZERO_EXECUTED_TEST_METHODS")
    extra = sorted(set(observed) - set(expected))
    if extra:
        problems.append("UNEXPECTED_METHOD_IDENTITIES: " + repr(extra))
    results = []
    invocation_count = 0
    for key, authored in expected.items():
        nodes = observed.get(key, [])
        record = {"selector": authored["selector"], "relativeIdentity": authored["relativeIdentity"],
                  "expectedInvocations": authored["expectedInvocations"], "observedCopies": len(nodes)}
        if len(nodes) != 1:
            record["status"] = "NOT_RUN" if not nodes else "DUPLICATE"
            problems.append(record["status"] + ": " + authored["relativeIdentity"])
            results.append(record)
            continue
        node = nodes[0]
        raw, url = identity(node)
        record.update(rawIdentity=raw, rawIdentityURL=url, rawResult=node.get("result"),
                      durationSeconds=node.get("durationInSeconds"))
        if url and authored["target"] not in urllib.parse.unquote(urllib.parse.urlsplit(url).path).split("/"):
            problems.append("WRONG_TEST_TARGET: " + url)
        arguments = [child for child in objects(node.get("children", [])) if child.get("nodeType") == "Arguments"]
        record["arguments"] = [{k: child.get(k) for k in ["name", "result", "nodeIdentifierURL", "durationInSeconds"]}
                               for child in arguments]
        if authored["argumentNames"]:
            names = [str(child.get("name")) for child in arguments]
            urls = [str(child.get("nodeIdentifierURL")) for child in arguments]
            if sorted(names) != sorted(authored["argumentNames"]) or len(set(urls)) != len(urls):
                problems.append("PARAMETER_INVOCATION_MISMATCH: " + authored["relativeIdentity"])
            if any(child.get("result") != "Passed" for child in arguments):
                problems.append("PARAMETER_NONPASS: " + authored["relativeIdentity"])
            invocation_count += len(arguments)
        else:
            if arguments:
                problems.append("UNEXPECTED_PARAMETER_CHILDREN: " + authored["relativeIdentity"])
            invocation_count += 1
        passed = node.get("result") == "Passed" and all(child.get("result") == "Passed" for child in arguments)
        record["status"] = "EXECUTED_PASS" if passed else "OBSERVED_NONPASS"
        if not passed:
            problems.append("METHOD_NONPASS: " + authored["relativeIdentity"])
        results.append(record)
    if len(observed) != group["expectedMethodCount"]:
        problems.append("METHOD_COUNT_MISMATCH")
    if invocation_count != group["expectedInvocationCount"]:
        problems.append("INVOCATION_COUNT_MISMATCH")
    tree_devices = {device.get("deviceId") for device in tree.get("devices", [])}
    summary_devices = {entry.get("device", {}).get("deviceId") for entry in summary.get("devicesAndConfigurations", [])}
    if tree_devices != {group["destinationID"]} or summary_devices != {group["destinationID"]}:
        problems.append("EXECUTION_DESTINATION_MISMATCH")
    if summary.get("result") != "Passed":
        problems.append("SUMMARY_NONPASS")
    for field in ["failedTests", "skippedTests", "expectedFailures"]:
        if summary.get(field) != 0:
            problems.append("SUMMARY_" + field + ": " + repr(summary.get(field)))
    # Retain Apple's counts verbatim. Parameterized results may count methods or leaves;
    # the exact method nodes and both argument identities above are the coverage authority.
    accepted_counts = {group["expectedMethodCount"], group["expectedInvocationCount"]}
    for field in ["totalTestCount", "passedTests"]:
        if summary.get(field) not in accepted_counts:
            problems.append("SUMMARY_COUNT_MISMATCH_" + field + ": " + repr(summary.get(field)))
    if summary.get("testFailures"):
        problems.append("SUMMARY_HAS_FAILURE_DIAGNOSTICS")
    return {"expectedMethodCount": group["expectedMethodCount"], "expectedInvocationCount": group["expectedInvocationCount"],
            "observedMethodCount": len(observed), "observedInvocationCount": invocation_count,
            "observedDeviceIDs": sorted(str(value) for value in tree_devices),
            "cases": results, "problems": problems, "passed": not problems}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", type=Path, default=Path(__file__).with_name("app-test-plan.json"))
    parser.add_argument("--group", required=True)
    parser.add_argument("--run-id", default="attempt1")
    parser.add_argument("--source-commit", help="Exact source of the matching root-owned build; defaults to the selector checkpoint.")
    parser.add_argument("--build-receipt", type=Path, help="Optional existing successful root build receipt, preserved by hash.")
    parser.add_argument("--execute", action="store_true", help="Root only: execute this one group on the existing exact simulator.")
    args = parser.parse_args()
    plan = json.loads(args.plan.read_text())
    if args.group not in plan["groups"]:
        parser.error("Unknown group: " + args.group)
    if not re.fullmatch(r"[A-Za-z0-9._-]+", args.run_id):
        parser.error("run-id must be a simple unique filename component")
    group = plan["groups"][args.group]
    root = Path(plan["root"])
    folder = root / "build/composer-evidence" / ("app-tests-" + args.group + "-" + args.run_id)
    command = [part.replace("<RUN_ID>", args.run_id) for part in group["commandTemplate"]]
    source_commit = args.source_commit or plan["selectorSourceCommit"]
    if not args.execute:
        print(json.dumps({"status": "PREPARED_NOT_EXECUTED", "sourceCommit": source_commit,
                          "group": args.group, "command": command, "expected": group["cases"]}, indent=2))
        return 0
    if sys.platform != "darwin":
        raise RuntimeError("Native execution belongs on the authorized Mac, not this host.")
    folder.mkdir(parents=True, exist_ok=False)
    receipt_path = folder / "receipt.json"
    receipt = {"schemaVersion": 1, "status": "PREFLIGHT", "startedAtUTC": stamp(), "sourceCommit": source_commit,
               "group": args.group, "command": command, "planSHA256": digest(args.plan),
               "expectedMethods": group["cases"], "resultBundle": str(folder / "Tests.xcresult"),
               "executionOwner": "/root", "timeoutSeconds": group["timeoutSeconds"]}
    save(receipt_path, receipt)
    process = None
    try:
        current = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
        if current != source_commit:
            raise RuntimeError("HEAD differs from the supplied matching build source: " + current)
        dirty = subprocess.check_output(["git", "diff", "--name-only", "HEAD"], cwd=root, text=True).splitlines()
        if any(not path.startswith("docs/") for path in dirty):
            raise RuntimeError("Tracked application/build inputs are dirty: " + repr(dirty))
        pin = root / plan["packageResolvedFile"]
        lock_before = digest(pin)
        if lock_before != plan["packageResolvedSHA256"]:
            raise RuntimeError("Swift package pins differ from the prepared plan; use the matching build/pins.")
        scheme = root / "AI_HLY.xcodeproj/xcshareddata/xcschemes/AI_HLY.xcscheme"
        xml = ET.parse(scheme)
        variables = {node.attrib["key"]: node.attrib["value"]
                     for node in xml.findall("./TestAction/EnvironmentVariables/EnvironmentVariable")
                     if node.attrib.get("isEnabled") == "YES"}
        if variables.get("HANLIN_UNIT_TEST_HOST") != "1":
            raise RuntimeError("The original scheme TestAction host environment is not intact.")
        files = {case["sourceFile"] for case in group["cases"]} | {
            plan["packageResolvedFile"], "AI_HLY.xcodeproj/project.pbxproj",
            "AI_HLY.xcodeproj/xcshareddata/xcschemes/AI_HLY.xcscheme"}
        inputs = {}
        for name in sorted(files):
            data = (root / name).read_bytes()
            committed = subprocess.check_output(["git", "show", source_commit + ":" + name], cwd=root)
            if data != committed:
                raise RuntimeError("Working input does not match the captured source: " + name)
            inputs[name] = hashlib.sha256(data).hexdigest()
        for case in group["cases"]:
            content = (root / case["sourceFile"]).read_text()
            if not re.search(r"\bfunc\s+" + re.escape(case["method"]) + r"\s*\(", content):
                raise RuntimeError("Selected method no longer exists: " + case["selector"])
        manifests = sorted((Path(plan["derivedData"]) / "Build/Products").glob("AI_HLY*.xctestrun"))
        if not manifests:
            raise RuntimeError("No existing AI_HLY build-for-testing manifest in the owned DerivedData.")
        receipt["buildForTestingManifests"] = {str(path): {"sha256": digest(path), "mtime": path.stat().st_mtime}
                                               for path in manifests}
        if args.build_receipt:
            receipt["buildReceipt"] = {"path": str(args.build_receipt), "sha256": digest(args.build_receipt)}
        else:
            receipt["buildReceipt"] = {"status": "ROOT_MUST_ASSOCIATE_MATCHING_SUCCESSFUL_BUILD_RECEIPT"}
        execution_manifest = plan["executionManifest"]
        selected_manifest = Path(command[command.index("-xctestrun") + 1])
        if (str(selected_manifest) != execution_manifest["path"]
                or digest(selected_manifest) != execution_manifest["sha256"]
                or source_commit != execution_manifest["sourceCommit"]):
            raise RuntimeError("Selected xctestrun does not match the verified fresh build.")
        if not args.build_receipt or digest(args.build_receipt) != execution_manifest["buildReceiptSHA256"]:
            raise RuntimeError("A matching verified successful build receipt is required.")
        matching_build = json.loads(args.build_receipt.read_text())
        if (matching_build.get("exitCode") != 0 or matching_build.get("sourceCommit") != source_commit
                or matching_build.get("scheme") != "AI_HLY"
                or not matching_build.get("resolvedLockUnchanged") or matching_build.get("trackedChanges")):
            raise RuntimeError("Build receipt is not a clean successful build of the selected source.")
        receipt["executedManifest"] = dict(execution_manifest)
        receipt["schemeEnvironment"] = variables
        receipt["packageResolvedSHA256Before"] = lock_before
        receipt["sourceInputs"] = inputs
        receipt["allowedDocumentationChanges"] = dirty
        receipt["toolchain"] = subprocess.check_output(["xcodebuild", "-version"], text=True).strip()
        save(folder / "source-inputs.json", inputs)
        receipt["status"] = "RUNNING"
        save(receipt_path, receipt)
        started = time.monotonic()
        with (folder / "test.log").open("x") as log:
            process = subprocess.Popen(command, cwd=root, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            receipt["pid"] = process.pid
            save(receipt_path, receipt)
            try:
                code = process.wait(timeout=group["timeoutSeconds"])
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=20)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=10)
                code = process.returncode
                receipt["timedOut"] = True
        receipt["exitCode"] = code
        receipt["durationSeconds"] = round(time.monotonic() - started, 3)
        receipt["logSHA256"] = digest(folder / "test.log")
        receipt["status"] = "VERIFYING_RESULT_BUNDLE"
        save(receipt_path, receipt)
        bundle = folder / "Tests.xcresult"
        if not (bundle / "Info.plist").is_file():
            raise RuntimeError("No finalized xcresult: exit zero alone cannot establish a test pass.")
        for kind in ["summary", "tests"]:
            argv = ["xcrun", "xcresulttool", "get", "test-results", kind, "--path", str(bundle), "--format", "json"]
            with (folder / (kind + ".json")).open("x") as out, (folder / (kind + ".stderr.log")).open("x") as err:
                result = subprocess.run(argv, stdout=out, stderr=err, timeout=60)
            if result.returncode:
                raise RuntimeError("xcresult export failed for " + kind)
        summary = json.loads((folder / "summary.json").read_text())
        tree = json.loads((folder / "tests.json").read_text())
        observed = inspect_results(group, summary, tree)
        save(folder / "case-identities.json", observed)
        receipt["actual"] = observed
        receipt["summary"] = {key: summary.get(key) for key in
                              ["result", "totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures"]}
        receipt["packageResolvedSHA256After"] = digest(pin)
        receipt["sourceInputsUnchanged"] = all((root / name).is_file() and digest(root / name) == expected
                                                for name, expected in inputs.items())
        receipt["testProductManifestsUnchanged"] = all(Path(name).is_file() and digest(Path(name)) == value["sha256"]
                                                       for name, value in receipt["buildForTestingManifests"].items())
        bundle_hashes = {path.relative_to(bundle).as_posix(): digest(path)
                         for path in sorted(bundle.rglob("*")) if path.is_file()}
        save(folder / "xcresult-files.json", bundle_hashes)
        receipt["xcresultFilesManifestSHA256"] = digest(folder / "xcresult-files.json")
        receipt["postRunHEAD"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
        verified = (code == 0 and not receipt.get("timedOut") and observed["passed"]
                    and receipt["packageResolvedSHA256After"] == lock_before
                    and receipt["sourceInputsUnchanged"] and receipt["testProductManifestsUnchanged"])
        receipt["status"] = "EXECUTED_PASS" if verified else "FAILED_VALIDATION"
        return 0 if verified else 2
    except KeyboardInterrupt:
        receipt["status"] = "CANCELLED_BY_OWNER"
        return 130
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        receipt["status"] = "BLOCKED_OR_FAILED"
        receipt["error"] = str(error)
        return 2
    finally:
        if process is not None and process.poll() is None:
            # Stop only this runner's process group, preserving the evidence receipt.
            try:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=20)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=10)
            except (ProcessLookupError, subprocess.TimeoutExpired) as error:
                receipt["cleanupError"] = str(error)
            receipt["exitCode"] = process.poll()
        receipt["finishedAtUTC"] = stamp()
        save(receipt_path, receipt)
        print(json.dumps(receipt, indent=2, ensure_ascii=False))

if __name__ == "__main__":
    raise SystemExit(main())
