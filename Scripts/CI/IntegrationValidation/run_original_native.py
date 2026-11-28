#!/usr/bin/env python3
"""Run only the reviewed original iOS95/current85 or generic5 package lane.

This adapter does not alter tests, resolve different pins, prepare app runtimes,
or repeat the already accepted unfiltered package suite. Native execution is
available only in the explicitly selected GitHub job. The JSON contract retains
the original argv, scripts, phase limits, identities and source boundaries.
"""
from __future__ import annotations

import argparse
import collections
import copy
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import stat
import subprocess
import sys
import time
import traceback
import uuid

MODE = "HanlinPlatformOriginal79Generic5"
GROUP = "agent_sdk_exact_source_proof"
CONTRACT_PATH = Path(__file__).with_name("original_native") / "contract.json"
CONTRACT_SHA256 = "f927fc4ca9af58d08aa1fff4da61ba317b504f14b597855056e90fdf4990b71f"
SELECTORS_SHA256 = "242c7c9cbd63170db62c683a76dfe83998304ef2336c69fcdf43344434c5edf3"
EXPECTED_SHA256 = "2a2c9810858b28f560c49de40026c4358023253720cad583920a7bff7e6919e9"
RESULTS = ("Passed", "Failed", "Skipped", "Expected Failure")


class AdmissionError(RuntimeError):
    pass


def require(condition, reason):
    if not condition:
        raise AdmissionError(reason)


def sha_bytes(value):
    return hashlib.sha256(value).hexdigest()


def sha_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def canonical(value):
    return json.dumps(value, ensure_ascii=True, separators=(",", ":"), sort_keys=True).encode()


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def write_json(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=True) + "\n")
    temporary.replace(path)


def validate_contract(contract):
    require(contract["schemaVersion"] == 1, "Unsupported contract")
    selectors = contract["originalSelectors"]
    require(sha_bytes(canonical(selectors)) == SELECTORS_SHA256,
            "Original95 selector values/order changed")
    require(len(selectors) == 95
            and sum(x.startswith("-only-testing:") for x in selectors) == 15
            and sum(x.startswith("-skip-testing:") for x in selectors) == 80,
            "Original95 selector shape changed")
    expected = contract["expectedTests"]
    require(sha_bytes(canonical(expected)) == EXPECTED_SHA256,
            "Reviewed current identity/argument map changed")
    require(len(expected) == len({x["identifier"] for x in expected}) == 64
            and sum(x["invocations"] for x in expected) == 85,
            "Require all current64 definitions/85 invocations")
    old = [x for x in expected if x["historical"]]
    require(len(old) == 58 and sum(x["invocations"] for x in old) == 79,
            "Historical58/79 subset changed")
    parameterized = [x for x in expected if x["parameterValues"] is not None]
    require(len(parameterized) == 7
            and sum(len(x["parameterValues"]) for x in parameterized) == 28,
            "Original28 parameter cases changed")
    require(sum(x["limitSeconds"] for x in contract["ios"]["buildPhases"]
                + contract["ios"]["testPhases"]) == 7320,
            "Original iOS phase bounds changed")
    require(contract["generic"]["originalOverallDeadlineSeconds"] == 3600,
            "Original generic whole-clock changed")
    for item in contract["generic"]["scripts"]:
        require(sha_bytes(item["body"].encode()) == item["originalSHA256"],
                "Original generic script bytes changed")
        rendered = item["body"].replace("$" + "{{ inputs.force_clean_build }}", "false")
        require("$" + "{{" not in rendered
                and sha_bytes(rendered.encode()) == item["renderedSHA256"],
                "Generic script has an unreviewed rendering")


def load_contract():
    raw = CONTRACT_PATH.read_bytes()
    require(sha_bytes(raw) == CONTRACT_SHA256, "Frozen contract file changed")
    contract = json.loads(raw)
    validate_contract(contract)
    return contract


def admit_request(environment, inputs):
    require(environment.get("GITHUB_ACTIONS") == "true"
            and environment.get("GITHUB_EVENT_NAME") == "workflow_dispatch",
            "Only the explicit hosted workflow may execute native commands")
    require(inputs.get("target_validation_group") == GROUP
            and inputs.get("exact_test_selector") == MODE,
            "Wrong original native dispatch scope")
    for key, value in inputs.items():
        if key not in ("target_validation_group", "exact_test_selector", "runtime_publish_release"):
            require(value in ("", False, None, "false"), "Conflicting dispatch input: " + key)
    for key in ("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT"):
        require(re.fullmatch(r"[1-9][0-9]*", environment.get(key, "")),
                "Missing current GitHub run/attempt")
    require(re.fullmatch(r"[0-9a-f]{40}", environment.get("GITHUB_SHA", "")),
            "Missing exact source SHA")


def phase_stop_reason(free_bytes, phase_elapsed, limit, generic_elapsed=None):
    if free_bytes < 750_000_000:
        return "ACTUAL_DISK_FLOOR"
    if generic_elapsed is not None and generic_elapsed >= 3600:
        return "ORIGINAL_3600_SECOND_JOB_DEADLINE"
    if limit is not None and phase_elapsed > limit:
        return "BOUNDED_CONTROLLER_TIMEOUT"
    return None


def validate_pin_rows(expected, actual):
    require(len(actual) == len(expected), "Resolved checkout count differs")
    by_identity = collections.defaultdict(list)
    for row in actual:
        by_identity[row["identity"].lower()].append(row)
    for pin in expected:
        rows = by_identity[pin["identity"].lower()]
        require(len(rows) == 1 and rows[0]["revision"] == pin["state"]["revision"]
                and rows[0]["status"] == "", "Missing, dirty or different pinned checkout: " + pin["identity"])


def owned_device(observed, owner, simulator_contract):
    matches = [(runtime, item) for runtime, devices in observed["devices"].items()
               for item in devices if item.get("udid", "").upper() == owner["udid"]]
    require(len(matches) == 1, "Owned device is absent or duplicated")
    runtime, device = matches[0]
    require(runtime == simulator_contract["runtimeIdentifier"]
            and device.get("name") == owner["name"]
            and device.get("deviceTypeIdentifier") == simulator_contract["deviceTypeIdentifier"]
            and device.get("isAvailable") is True,
            "Owned device identity/runtime/hardware changed")
    return device


def created_identity(before, output, name, simulator_contract):
    try:
        udid = str(uuid.UUID(output.strip())).upper()
    except (ValueError, AttributeError):
        raise AdmissionError("simctl create did not return one UUID") from None
    previous = {item.get("udid", "").upper() for devices in before["devices"].values() for item in devices}
    require(udid not in previous, "Created UUID was already present")
    owner = {"udid": udid, "name": name, "createdByThisAttempt": True,
             "absentBeforeCreate": True, "runtime": simulator_contract["runtimeIdentifier"],
             "deviceType": simulator_contract["deviceTypeIdentifier"]}
    return owner


def bind_created_device(before, after, output, name, simulator_contract):
    owner = created_identity(before, output, name, simulator_contract)
    owned_device(after, owner, simulator_contract)
    return {**owner, "identityReadbackVerified": True}


def evidence_descriptor(original, evidence_directory):
    require(original.get("__xctestrun_metadata__", {}).get("FormatVersion") == 2,
            "Unsupported original xctestrun format")
    changed = copy.deepcopy(original)
    targets = [target for config in changed["TestConfigurations"] for target in config["TestTargets"]
               if target["BlueprintName"] == "HanlinScriptExtensionsTests"]
    require(len(targets) == 1, "Missing or ambiguous ScriptExtensions test target")
    target = targets[0]
    require("HANLIN_WIDGET_EVIDENCE_DIR" not in target.get("EnvironmentVariables", {}),
            "Evidence override already exists")
    target.setdefault("EnvironmentVariables", {})["HANLIN_WIDGET_EVIDENCE_DIR"] = str(evidence_directory)
    inverse = copy.deepcopy(changed)
    restored = [target for config in inverse["TestConfigurations"] for target in config["TestTargets"]
                if target["BlueprintName"] == "HanlinScriptExtensionsTests"][0]
    restored["EnvironmentVariables"].pop("HANLIN_WIDGET_EVIDENCE_DIR")
    if "EnvironmentVariables" not in [target for config in original["TestConfigurations"]
                                    for target in config["TestTargets"]
                                    if target["BlueprintName"] == "HanlinScriptExtensionsTests"][0]:
        restored.pop("EnvironmentVariables")
    require(inverse == original, "Descriptor changed beyond the original optional evidence output")
    return changed


def selected_products(descriptor, descriptor_path, expected_targets):
    targets = [target for config in descriptor["TestConfigurations"] for target in config["TestTargets"]]
    selected = [target for target in targets if target["BlueprintName"] in expected_targets]
    require(collections.Counter(target["BlueprintName"] for target in selected)
            == collections.Counter(expected_targets), "Ambiguous or missing selected test products")
    base = descriptor_path.parent.resolve()
    products = []
    for target in selected:
        bundle = Path(target["TestBundlePath"].replace("__TESTROOT__", str(base)))
        binary = bundle / target["BlueprintName"]
        require(binary.resolve().is_relative_to(base) and binary.is_file() and not binary.is_symlink(),
                "Selected binary is absent or escapes its fresh build products")
        products.append({"target": target["BlueprintName"], "path": str(binary),
                         "bytes": binary.stat().st_size, "sha256": sha_file(binary),
                         "mode": stat.S_IMODE(binary.stat().st_mode),
                         "originalTestHostPath": target["TestHostPath"]})
    return products


def reconcile(summary, tree, expected_rows, excluded, owner, simulator_contract, native):
    expected = {row["identifier"]: row for row in expected_rows}
    actual = {}

    def visit(node, target=None):
        if node.get("nodeType") == "Unit test bundle":
            target = node["name"]
        if node.get("nodeType") == "Test Case":
            require(target is not None, "Test case has no native bundle")
            identifier = target + "/" + node["nodeIdentifier"]
            require(identifier not in actual, "Duplicate executed method: " + identifier)
            actual[identifier] = node
        for child in node.get("children", []):
            visit(child, target)

    for node in tree["testNodes"]:
        visit(node)
    require(set(actual) == set(expected), {
        "missing": sorted(set(expected) - set(actual)),
        "unexpected": sorted(set(actual) - set(expected))})
    require(not set(excluded).intersection(actual), "Original excluded collateral executed")
    methods, invocations, urls, rows = collections.Counter(), collections.Counter(), [], []
    for identifier, expectation in sorted(expected.items()):
        node = actual[identifier]
        require(node["result"] in RESULTS, "Unknown native method outcome")
        methods[node["result"]] += 1
        args = [child for child in node.get("children", []) if child.get("nodeType") == "Arguments"]
        count = len(args) if args else 1
        require(count == expectation["invocations"], "Invocation count differs: " + identifier)
        row = {"identifier": identifier, "result": node["result"], "invocations": count,
               "nodeIdentifierURL": node["nodeIdentifierURL"], "arguments": [],
               "historical": expectation["historical"]}
        values = expectation["parameterValues"]
        if values is not None:
            require(args and len(args) == len(values), "Parameter cases missing")
            if identifier.endswith(("(engine:)", "(invalidation:)")):
                displays = ["." + str(value) for value in values]
            elif all(isinstance(value, (int, float)) and not isinstance(value, bool) for value in values):
                displays = [str(float(value)) for value in values]
            else:
                require(all(isinstance(value, str) for value in values), "Unsupported original parameter map")
                displays = ['"' + value + '"' for value in values]
            require(collections.Counter(arg["name"] for arg in args) == collections.Counter(displays),
                    "Original parameter values differ: " + identifier)
            for arg in args:
                require(arg["result"] in RESULTS, "Unknown argument outcome")
                url = arg["nodeIdentifierURL"]
                require(url.startswith(node["nodeIdentifierURL"] + "?args=")
                        and url.split("?args=", 1)[1], "Missing native argument identity")
                urls.append(url)
                invocations[arg["result"]] += 1
                row["arguments"].append({"display": arg["name"], "result": arg["result"],
                                         "nodeIdentifierURL": url})
        else:
            require(not args, "Unexpected parameter expansion")
            invocations[node["result"]] += 1
        rows.append(row)
    require(len(urls) == len(set(urls)) == 28, "Original28 argument identities not unique")
    require(sum(methods.values()) == 64 and sum(invocations.values()) == 85,
            "Current64/85 totals differ")
    require(summary["totalTestCount"] == 64, "Native summary method count differs")
    for field, result in (("passedTests", "Passed"), ("failedTests", "Failed"),
                          ("skippedTests", "Skipped"), ("expectedFailures", "Expected Failure")):
        require(summary[field] == methods[result], "Native summary disagrees: " + field)
    configurations = summary["devicesAndConfigurations"]
    require(len(configurations) == 1, "Expected exactly one actual device/configuration")
    config = configurations[0]
    device = config["device"]
    require(device["deviceId"].upper() == owner["udid"]
            and device["osVersion"] == simulator_contract["version"]
            and device["osBuildNumber"] == simulator_contract["build"],
            "Native results came from another device/runtime/build")
    for field, result in (("passedTests", "Passed"), ("failedTests", "Failed"),
                          ("skippedTests", "Skipped"), ("expectedFailures", "Expected Failure")):
        require(config[field] == invocations[result], "Device invocation summary disagrees")
    passed = (native["exitCode"] == 0 and native["status"] == "PASSED"
              and not native.get("stopReason") and methods["Passed"] == 64
              and invocations["Passed"] == 85)
    return {"status": "PASSED" if passed else "EXECUTED_WITH_FAILURES", "acceptancePassed": passed,
            "actualDefinitions": 64, "actualInvocations": 85, "originalDefinitions": 58,
            "originalInvocations": 79, "additiveDefinitions": 6, "parameterInvocations": 28,
            "parameterValuesExactlyReconciled": True, "methodResults": dict(methods),
            "invocationResults": dict(invocations), "device": device, "tests": rows}


class Runner:
    def __init__(self, lane, contract):
        self.started = time.monotonic()
        self.original_seconds = 0.0
        self.cleanup_seconds = 0.0
        self.lane, self.contract = lane, contract
        self.root = Path(os.environ["GITHUB_WORKSPACE"]).resolve()
        self.package = self.root / "Packages/HanlinPlatform"
        self.run_id, self.attempt = os.environ["GITHUB_RUN_ID"], os.environ["GITHUB_RUN_ATTEMPT"]
        self.proof = self.root / "build/original-native-validation" / (self.run_id + "-" + self.attempt) / lane
        self.proof.mkdir(parents=True, exist_ok=False)
        self.receipt = self.proof / "receipt.json"
        self.env = os.environ.copy()
        self.env["NSUnbufferedIO"] = "YES"
        self.owner = None
        self.bindings = {"<SOURCE>": str(self.root), "<EVIDENCE>": str(self.proof)}
        self.data = {"source": os.environ["GITHUB_SHA"], "lane": lane, "status": "PREPARING",
                     "startedAt": now(), "controllerPID": os.getpid(), "commandsStarted": 0,
                     "buildCommandsStarted": 0, "testCommandsStarted": 0,
                     "controllerSHA256": sha_file(Path(__file__)), "contractSHA256": CONTRACT_SHA256,
                     "runID": self.run_id, "runAttempt": self.attempt, "phases": [],
                     "toolchainPortability": contract["toolchain"], "sourceContract": contract["provenance"],
                     "selection": {"originalSelectors": contract["originalSelectors"],
                                   "expectedTests": contract["expectedTests"],
                                   "excludedCollateralIdentifiers": contract["excludedCollateralIdentifiers"],
                                   "sourceOnlyExcludedAdditions": contract["sourceOnlyExcludedAdditions"]}}
        self.save()

    def save(self):
        write_json(self.receipt, self.data)

    def free(self):
        return shutil.disk_usage(self.root).free

    def elapsed(self):
        return time.monotonic() - self.started

    def preparation_elapsed(self):
        return self.elapsed() - self.original_seconds - self.cleanup_seconds

    def limit(self, seconds):
        if self.lane == "generic5":
            require(self.elapsed() < 3600, "Original generic deadline exhausted")
            return min(seconds, 3600 - self.elapsed())
        require(self.preparation_elapsed() < 1200, "Hosted preparation allowance exhausted")
        return min(seconds, 1200 - self.preparation_elapsed())

    def read(self, args, cwd=None, timeout=20):
        result = subprocess.run(args, cwd=cwd or self.root, env=self.env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=self.limit(timeout))
        require(result.returncode == 0, {"readCommand": args, "exit": result.returncode,
                                        "stderr": result.stderr.decode(errors="replace")[-8192:]})
        return result.stdout

    def expand(self, value):
        for old, new in self.bindings.items():
            value = value.replace(old, new)
        require(not re.search(r"<[A-Z0-9_]+>", value), "Unresolved command path binding")
        return value

    def stop(self, process, row, reason):
        row["stopReason"] = reason
        self.save()
        if process.poll() is None:
            require(os.getpgid(process.pid) == process.pid, "Refuse to signal a non-owned process group")
            for sig, grace in ((signal.SIGINT, 30), (signal.SIGTERM, 10)):
                try:
                    os.killpg(process.pid, sig)
                except ProcessLookupError:
                    return process.wait()
                try:
                    return process.wait(timeout=grace)
                except subprocess.TimeoutExpired:
                    pass
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        return process.wait()

    def phase(self, name, args, seconds=None, *, cwd=None, interval=10,
              allow_failure=False, separate=False, preparation=False, cleanup=False):
        if self.lane == "generic5":
            require(self.elapsed() < 3600, "Original generic deadline exhausted before next command")
        if preparation:
            seconds = self.limit(seconds)
        log = self.proof / (name + ".log")
        error_log = self.proof / (name + ".stderr.log")
        row = {"name": name, "command": args, "cwd": str(cwd or self.package),
               "limitSeconds": seconds, "startedAt": now(), "log": str(log), "freeBefore": self.free()}
        self.data["phases"].append(row)
        self.save()
        start = time.monotonic()
        process = None
        try:
            with log.open("xb") as stdout:
                with (error_log.open("xb") if separate else open(os.devnull, "wb")) as stderr:
                    process = subprocess.Popen(args, cwd=cwd or self.package, env=self.env, stdout=stdout,
                                               stderr=stderr if separate else subprocess.STDOUT,
                                               start_new_session=True)
                    row.update(pid=process.pid, pgid=os.getpgid(process.pid), status="RUNNING")
                    self.data["commandsStarted"] += 1
                    if name in ("original-package-build-for-testing", "compile-the-phase-1-swift-package",
                                "compile-contracts-for-generic-ios-simulator", "compile-contracts-for-generic-ios-device"):
                        self.data["buildCommandsStarted"] += 1
                    if name == "original-native-test-without-building":
                        self.data["testCommandsStarted"] += 1
                    self.save()
                    while True:
                        try:
                            code = process.wait(timeout=interval)
                            break
                        except subprocess.TimeoutExpired:
                            observed_free = self.free()
                            row["lastObservation"] = {"at": now(), "freeBytes": observed_free,
                                                       "logBytes": log.stat().st_size,
                                                       "elapsedSeconds": time.monotonic() - start}
                            self.save()
                            reason = phase_stop_reason(observed_free, time.monotonic() - start, seconds,
                                                       self.elapsed() if self.lane == "generic5" else None)
                            if reason:
                                code = self.stop(process, row, reason)
                                break
        except BaseException:
            if process is not None:
                self.stop(process, row, "CONTROLLER_EXCEPTION")
            row["status"] = "FAILED"
            row["exitCode"] = process.returncode if process is not None else None
            raise
        finally:
            if cleanup:
                self.cleanup_seconds += time.monotonic() - start
            row.update(finishedAt=now(), elapsedSeconds=time.monotonic() - start,
                       logSHA256=sha_file(log) if log.exists() else None, freeAfter=self.free())
            if separate and error_log.exists():
                row.update(stderrLog=str(error_log), stderrSHA256=sha_file(error_log))
            self.save()
        row.update(exitCode=code, status="PASSED" if code == 0 and not row.get("stopReason") else "FAILED")
        self.save()
        require(allow_failure or row["status"] == "PASSED",
                {"phase": name, "exit": code, "stopReason": row.get("stopReason")})
        return row

    def original_phase(self, spec, *, interval, allow_failure=False):
        started = time.monotonic()
        try:
            return self.phase(spec["name"], [self.expand(arg) for arg in spec["argv"]],
                              spec["limitSeconds"], interval=interval,
                              separate=spec.get("separateStderr", False), allow_failure=allow_failure)
        finally:
            self.original_seconds += time.monotonic() - started

    def source_snapshot(self):
        head = self.read(["git", "rev-parse", "HEAD"]).decode().strip()
        require(head == os.environ["GITHUB_SHA"], "Checkout differs from the dispatched source")
        status = self.read(["git", "status", "--porcelain", "--untracked-files=all"]).decode()
        require(status == "", "Source checkout is dirty")
        trees = {path: self.read(["git", "rev-parse", "HEAD:" + path]).decode().strip()
                 for path in self.contract["sourceTrees"]}
        require(trees == self.contract["sourceTrees"], "Package/fixture tree differs from reviewed source")
        tracked = self.read(["git", "ls-tree", "-r", "-z", "HEAD", "--",
                             "Packages/HanlinPlatform", "Fixtures/Widgets"]).split(b"\0")
        rows = []
        for item in filter(None, tracked):
            metadata, raw_path = item.split(b"\t", 1)
            mode, kind, blob = metadata.decode().split()
            path = self.root / raw_path.decode()
            require(kind == "blob" and mode in ("100644", "100755")
                    and path.is_file() and not path.is_symlink(), "Unsupported tracked package input")
            raw = path.read_bytes()
            object_id = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
            require(object_id == blob, "Tracked input differs: " + str(path))
            executable = bool(path.stat().st_mode & stat.S_IXUSR)
            require(executable == (mode == "100755"), "Tracked input mode differs")
            rows.append({"path": raw_path.decode(), "gitBlob": blob, "mode": mode,
                         "bytes": len(raw), "sha256": sha_bytes(raw)})
        require(sum(row["path"].startswith("Packages/HanlinPlatform/") for row in rows)
                == self.contract["packageFileCount"], "Incomplete package input closure")
        require(sha_file(self.package / "Package.resolved") == self.contract["packageLockSHA256"]
                and sha_file(self.package / "Package.swift") == self.contract["packageManifestSHA256"],
                "Package manifest/pins changed")
        for fixture in self.contract["externalFixtures"]:
            require(sha_file(self.root / fixture["path"]) == fixture["sha256"], "Original fixture changed")
        context = {}
        for relative in (".github/workflows/build-ios26-unsigned-ipa.yml",
                         "Scripts/CI/IntegrationValidation/run_original_native.py",
                         "Scripts/CI/IntegrationValidation/original_native/contract.json",
                         "RuntimeDependencies.lock.json",
                         "AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"):
            path = self.root / relative
            require(path.is_file() and not path.is_symlink(), "Missing source context")
            context[relative] = sha_file(path)
        return {"head": head, "status": status, "trees": trees, "trackedInputs": rows, "context": context}

    def pins(self, directory, label):
        require(directory.is_dir(), "Missing actual source checkouts: " + str(directory))
        rows = []
        for pin in self.contract["pins"]:
            matches = [path for path in directory.iterdir()
                       if path.is_dir() and path.name.lower() == pin["identity"].lower()]
            require(len(matches) == 1, "Missing or ambiguous checkout: " + pin["identity"])
            path = matches[0]
            rows.append({"identity": pin["identity"], "path": str(path),
                         "revision": self.read(["git", "rev-parse", "HEAD"], cwd=path).decode().strip(),
                         "status": self.read(["git", "status", "--porcelain", "--untracked-files=all"], cwd=path).decode()})
        validate_pin_rows(self.contract["pins"], rows)
        require(sha_file(self.package / "Package.resolved") == self.contract["packageLockSHA256"],
                "Resolving changed Package.resolved")
        self.data.setdefault("resolvedPins", {})[label] = rows
        self.save()

    def toolchain(self, xcode_row=None, sdk_row=None):
        xcode = (Path(xcode_row["log"]).read_text() if xcode_row else
                 self.read(["xcodebuild", "-version"]).decode()).strip()
        simulator_sdk = (Path(sdk_row["log"]).read_text() if sdk_row else
                         self.read(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"]).decode()).strip()
        swift = self.read(["swift", "--version"], timeout=60).decode().strip()
        device_sdk = self.read(["xcrun", "--sdk", "iphoneos", "--show-sdk-version"], timeout=60).decode().strip()
        architecture = self.read(["uname", "-m"]).decode().strip()
        expected = self.contract["toolchain"]["hosted"]
        self.data["actualToolchain"] = {"xcode": xcode, "swift": swift, "simulatorSDK": simulator_sdk,
                                      "deviceSDK": device_sdk, "architecture": architecture,
                                      "developerDirectory": self.env.get("DEVELOPER_DIR")}
        self.save()
        require(xcode.splitlines() == ["Xcode " + expected["xcode"], "Build version " + expected["build"]]
                and re.search(r"\bSwift version " + re.escape(expected["swift"]) + r"\b", swift)
                and simulator_sdk == expected["simulatorSDK"] and device_sdk == expected["deviceSDK"]
                and architecture == expected["architecture"], "Hosted toolchain differs from the admitted portability binding")

    def device_json(self, name, *, available=False, cleanup=False):
        args = ["xcrun", "simctl", "list", "devices"] + (["available"] if available else []) + ["-j"]
        row = self.phase(name, args, 90, preparation=not cleanup, cleanup=cleanup)
        return json.loads(Path(row["log"]).read_text())

    def create_device(self):
        spec = self.contract["simulator"]
        runtimes_row = self.phase("hosted-runtime-inventory", ["xcrun", "simctl", "list", "runtimes", "-j"],
                                  90, preparation=True)
        types_row = self.phase("hosted-device-types", ["xcrun", "simctl", "list", "devicetypes", "-j"],
                               90, preparation=True)
        runtimes = json.loads(Path(runtimes_row["log"]).read_text())["runtimes"]
        matches = [item for item in runtimes if item.get("identifier") == spec["runtimeIdentifier"]]
        require(len(matches) == 1 and matches[0].get("isAvailable") is True
                and matches[0].get("version") == spec["version"]
                and matches[0].get("buildversion") == spec["build"], "Exact available runtime/build missing")
        types = json.loads(Path(types_row["log"]).read_text())["devicetypes"]
        require(sum(item.get("identifier") == spec["deviceTypeIdentifier"] for item in types) == 1,
                "Exact iPad device type missing")
        before = self.device_json("hosted-before-create")
        name = "Hanlin-Original95-" + self.run_id + "-" + self.attempt
        created = self.phase("hosted-device-create",
                             ["xcrun", "simctl", "create", name, spec["deviceTypeIdentifier"], spec["runtimeIdentifier"]],
                             120, preparation=True)
        output = Path(created["log"]).read_text()
        self.owner = {**created_identity(before, output, name, spec), "identityReadbackVerified": False}
        self.data["ownedSimulator"] = self.owner
        self.save()
        after = self.device_json("hosted-created-device-readback")
        self.owner = bind_created_device(before, after, output, name, spec)
        self.owner.update(runID=self.run_id, runAttempt=self.attempt, source=self.data["source"],
                          createLogSHA256=created["logSHA256"], runtimeObservation=matches[0])
        self.data["ownedSimulator"] = self.owner
        self.bindings["<OWNED_DEVICE_UUID>"] = self.owner["udid"]
        self.save()

    def cleanup_device(self):
        if self.owner is None:
            return
        started = time.monotonic()
        self.data["ownedCleanup"] = {"startedAt": now(), "limitSeconds": 360, "udid": self.owner["udid"]}
        try:
            device = owned_device(self.device_json("cleanup-device-readback", cleanup=True),
                                  self.owner, self.contract["simulator"])
            require(device["state"] in ("Booted", "Shutdown"), "Owned device state is not safe for cleanup")
            if device["state"] == "Booted":
                self.phase("cleanup-owned-shutdown", ["xcrun", "simctl", "shutdown", self.owner["udid"]],
                           120, cleanup=True)
            require(time.monotonic() - started < 360, "Owned cleanup allowance exhausted")
            self.phase("cleanup-owned-delete", ["xcrun", "simctl", "delete", self.owner["udid"]],
                       min(120, 360 - (time.monotonic() - started)), cleanup=True)
            self.data["ownedCleanup"]["status"] = "PASSED"
        except BaseException as error:
            self.data["ownedCleanup"].update(status="FAILED", error=repr(error))
            self.data["status"] = "FAILED"
        finally:
            self.data["ownedCleanup"]["finishedAt"] = now()
            self.save()

    def run_ios(self):
        spec = self.contract["ios"]
        self.data["freeAtAdmission"] = self.free()
        require(self.free() > spec["buildAdmission"]["requiredBytes"], "Original build disk allowance unavailable")
        build = spec["buildPhases"]
        xcode = self.original_phase(build[0], interval=15)
        sdk = self.original_phase(build[1], interval=15)
        self.toolchain(xcode, sdk)
        self.original_phase(build[2], interval=15)
        self.create_device()
        derived_data = Path(os.environ["RUNNER_TEMP"]).resolve() / (
            "hanlin-original95-" + self.run_id + "-" + self.attempt)
        require(not derived_data.exists(), "Fresh derived-data root already exists")
        self.bindings["<IOS79_DERIVED_DATA>"] = str(derived_data)
        (self.proof / "ios79/build").mkdir(parents=True)
        (self.proof / "ios79/test").mkdir(parents=True)
        discovery = self.original_phase(build[3], interval=15)
        document = json.loads(Path(discovery["log"]).read_text())
        schemes = (document.get("workspace") or document.get("project") or {}).get("schemes") or []
        if "HanlinPlatform-Package" in schemes:
            scheme = "HanlinPlatform-Package"
        else:
            require(len(schemes) == 1 and schemes[0], "Ambiguous generated package scheme")
            scheme = schemes[0]
        self.bindings["<GENERATED_SCHEME>"] = scheme
        self.data["generatedScheme"] = scheme
        self.pins(derived_data / "SourcePackages/checkouts", "after-original-discovery")
        require(self.free() > spec["buildAdmission"]["requiredBytes"], "Original pre-build disk allowance unavailable")
        self.original_phase(build[4], interval=15)
        products_root = derived_data / "Build/Products"
        sdk_name = self.contract["toolchain"]["hosted"]["simulatorSDK"]
        descriptors = list(products_root.glob("*_iphonesimulator" + sdk_name + "-arm64.xctestrun"))
        require(len(descriptors) == 1 and not descriptors[0].is_symlink(),
                "Require one actual SDK/arm64-generated xctestrun")
        original_path = descriptors[0]
        original_bytes = original_path.read_bytes()
        original = plistlib.loads(original_bytes)
        targets = {row["identifier"].split("/")[0] for row in self.contract["expectedTests"]}
        products = selected_products(original, original_path, targets)
        evidence = self.proof / "raster-evidence"
        evidence.mkdir()
        modified = evidence_descriptor(original, evidence)
        derived_path = original_path.parent / ("HanlinPlatform-original95-evidence-" + self.run_id + "-" + self.attempt + ".xctestrun")
        require(not derived_path.exists(), "Evidence descriptor already exists")
        derived_path.write_bytes(plistlib.dumps(modified, fmt=plistlib.FMT_XML))
        require(plistlib.loads(derived_path.read_bytes()) == modified, "Descriptor serialization changed")
        self.bindings["<SAME_PRODUCTS_DERIVED_DESCRIPTOR>"] = str(derived_path)
        (self.proof / "original.xctestrun").write_bytes(original_bytes)
        (self.proof / "evidence.xctestrun").write_bytes(derived_path.read_bytes())
        self.data["sameProducts"] = {"originalDescriptor": str(original_path),
                                    "originalSHA256": sha_bytes(original_bytes),
                                    "executionDescriptor": str(derived_path),
                                    "executionSHA256": sha_file(derived_path), "selectedProducts": products,
                                    "allGeneratedDescriptorTargets": [
                                        {"target": target["BlueprintName"],
                                         "selectedByOriginalArgv": target["BlueprintName"] in targets}
                                        for config in original["TestConfigurations"] for target in config["TestTargets"]]}
        self.save()
        tests = spec["testPhases"]
        observed = self.original_phase(tests[0], interval=10)
        device = owned_device(json.loads(Path(observed["log"]).read_text()), self.owner, self.contract["simulator"])
        if device["state"] == "Shutdown":
            self.original_phase(tests[1], interval=10)
        else:
            require(device["state"] == "Booted", "Owned device cannot boot from current state")
        self.original_phase(tests[2], interval=10)
        self.data["freeBeforeTest"] = self.free()
        require(self.free() >= spec["testAdmission"]["requiredBytes"], "Original test disk allowance unavailable")
        native = self.original_phase(tests[3], interval=10, allow_failure=True)
        result = self.proof / "ios79/test/PlatformTests.xcresult"
        self.data["nativeExitCode"] = native["exitCode"]
        require((result / "Info.plist").is_file(), "Original native result bundle is incomplete")
        summary_row = self.original_phase(tests[4], interval=10, allow_failure=True)
        tests_row = self.original_phase(tests[5], interval=10, allow_failure=True)
        require(summary_row["status"] == tests_row["status"] == "PASSED", "Native result extraction failed")
        require(sha_file(original_path) == sha_bytes(original_bytes)
                and sha_file(derived_path) == self.data["sameProducts"]["executionSHA256"],
                "Original/evidence descriptors changed")
        for product in products:
            require(sha_file(Path(product["path"])) == product["sha256"]
                    and stat.S_IMODE(Path(product["path"]).stat().st_mode) == product["mode"],
                    "Selected product bytes/mode changed")
        self.pins(derived_data / "SourcePackages/checkouts", "after-original-native")
        result = reconcile(json.loads(Path(summary_row["log"]).read_text()),
                           json.loads(Path(tests_row["log"]).read_text()),
                           self.contract["expectedTests"], self.contract["excludedCollateralIdentifiers"],
                           self.owner, self.contract["simulator"], native)
        write_json(self.proof / "strict-reconciliation.json", result)
        self.data["strictReconciliationSHA256"] = sha_file(self.proof / "strict-reconciliation.json")
        self.data["sourceAfter"] = self.source_snapshot()
        require(self.data["sourceAfter"] == self.data["sourceBefore"], "Source/fixtures/pins changed")
        require(result["acceptancePassed"], "Original native scope has actual failures")
        self.data["status"] = "PASSED"

    def run_generic(self):
        spec = self.contract["generic"]
        self.toolchain()
        self.data["processSnapshot"] = self.read(["/bin/ps", "-axo", "pid=,ppid=,pgid=,etime=,comm="], timeout=10).decode()
        self.data["vmStat"] = self.read(["/usr/bin/vm_stat"]).decode()
        self.data["freeAtAdmission"] = self.free()
        require(self.free() >= spec["requiredAdmissionBytes"], "Original generic allowance unavailable")
        for name in ("Phase1SimulatorDerivedData", "Phase1DeviceDerivedData"):
            require(not (self.root / "build" / name).exists(), "Generic output root is not fresh")
        inputs = self.proof / "original-scripts"
        inputs.mkdir()
        log = self.proof / "generic5"
        log.mkdir()
        github_env = log / "github-env"
        github_env.write_text("")
        self.env.update(PACKAGE_PATH="Packages/HanlinPlatform", GITHUB_WORKSPACE=str(self.root),
                        LOG_DIR=str(log), GITHUB_ENV=str(github_env))
        self.bindings["<INPUTS>"] = str(inputs)
        self.data["originalScripts"] = []
        for index, script in enumerate(spec["scripts"]):
            original = inputs / script["name"]
            original.write_text(script["body"])
            executed = inputs / (script["name"] + ".executed")
            executed.write_text(script["body"].replace("$" + "{{ inputs.force_clean_build }}", "false"))
            require(sha_file(original) == script["originalSHA256"]
                    and sha_file(executed) == script["renderedSHA256"], "Original script changed at staging")
            self.data["originalScripts"].append({"originalPath": str(original),
                                                  "originalSHA256": script["originalSHA256"],
                                                  "executedPath": str(executed),
                                                  "executedSHA256": script["renderedSHA256"]})
            self.phase(script["phaseName"], ["/bin/bash", str(executed)],
                       cwd=Path(self.expand(script["cwd"])), interval=5)
            if index == 0:
                self.pins(self.package / ".build/checkouts", "after-original-resolve")
            if index == 2:
                values = [line.partition("=")[2] for line in github_env.read_text().splitlines()
                          if line.startswith("PACKAGE_XCODE_SCHEME=")]
                require(len(values) == 1 and values[0], "Original scheme discovery was ambiguous")
                self.env["PACKAGE_XCODE_SCHEME"] = values[0]
                self.data["generatedScheme"] = values[0]
            if index in (3, 4):
                derived_name = ("Phase1SimulatorDerivedData", "Phase1DeviceDerivedData")[index - 3]
                self.pins(self.root / "build" / derived_name / "SourcePackages/checkouts",
                          "after-" + script["phaseName"])
        for script in self.data["originalScripts"]:
            require(sha_file(Path(script["originalPath"])) == script["originalSHA256"]
                    and sha_file(Path(script["executedPath"])) == script["executedSHA256"],
                    "Original generic scripts changed during execution")
        self.pins(self.package / ".build/checkouts", "after-original-generic5")
        for derived_name in ("Phase1SimulatorDerivedData", "Phase1DeviceDerivedData"):
            self.pins(self.root / "build" / derived_name / "SourcePackages/checkouts",
                      "final-" + derived_name)
        self.data["sourceAfter"] = self.source_snapshot()
        require(self.data["sourceAfter"] == self.data["sourceBefore"], "Generic source/pins changed")
        require(self.elapsed() <= 3600, "Original generic whole-clock exhausted")
        self.data["status"] = "PASSED"

    def run(self):
        locks = []
        try:
            lock_root = Path.home() / "Library/Caches/hanlin-original-platform-native"
            lock_root.mkdir(parents=True, exist_ok=True)
            require(not lock_root.is_symlink(), "Native lock root must not be an alias")
            for name, operation in (("hanlin-original-native-app.lock", fcntl.LOCK_EX),
                                    ("hanlin-original-native-maintenance.lock", fcntl.LOCK_SH)):
                lock = (lock_root / name).open("a+")
                fcntl.flock(lock, operation | fcntl.LOCK_NB)
                locks.append(lock)
            self.data["coordinationLocks"] = {"native": "exclusive", "maintenance": "shared"}
            self.data["sourceBefore"] = self.source_snapshot()
            if self.lane == "ios-original95":
                self.run_ios()
            else:
                self.run_generic()
        except BaseException as error:
            self.data.update(status="FAILED" if self.data["commandsStarted"] else "NOT_RUN",
                             error=repr(error), traceback=traceback.format_exc())
        finally:
            self.cleanup_device()
            self.data.update(finishedAt=now(), elapsedSeconds=self.elapsed(), freeAfter=self.free(),
                             hostedPreparationSeconds=self.preparation_elapsed())
            self.save()
            for lock in reversed(locks):
                lock.close()
            print(json.dumps({key: self.data.get(key) for key in
                              ("source", "lane", "status", "error", "nativeExitCode", "elapsedSeconds")}), flush=True)
        return 0 if self.data["status"] == "PASSED" else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lane", required=True, choices=("ios-original95", "generic5"))
    args = parser.parse_args()
    inputs = json.loads(os.environ.get("HANLIN_ORIGINAL_NATIVE_INPUTS", "{}"))
    admit_request(os.environ, inputs)
    contract = load_contract()
    def interrupted(signum, frame):
        raise InterruptedError("Hosted controller received signal " + str(signum))
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    return Runner(args.lane, contract).run()


if __name__ == "__main__":
    raise SystemExit(main())
