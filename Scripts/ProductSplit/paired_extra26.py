"""Continue a genuine paired54 pass with the unchanged original extra26 scope.

This adapts the reviewed original extra26-v3 controller to the owning paired
job. It does not build, install replacement products, create another simulator,
change a test descriptor, or accept a receipt from another job/source.
"""
from pathlib import Path
import collections
import datetime
import hashlib
import json
import math
import os
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import time
import zipfile


COMPOSITE_SCOPE = "miniapp_complete_with_extra26"
INVENTORY = "docs/two-wave-integration/20261127/native-union-16b4af44.json"
INVENTORY_SHA256 = "f6ab65b8a897238f52cecefa2cdfe43f38bf359bbd82bbf0251fc7a7f34d3f5e"
ORIGINAL_CONTROLLER_SHA256 = "4a69a7a0a3bd5760f32096f5db022c2b96d387a2f4dd17d829332cb52bf7f275"
DEADLINE_SECONDS = 2400
ADMISSION_FREE_BYTES = 3_000_000_000
CONTINUOUS_FREE_BYTES = 1_073_741_824
ORIGINAL54_JOB_SECONDS = 210 * 60


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def record(path):
    path = Path(path)
    require(path.is_file(), "Required original input is absent: " + str(path))
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)}


def write_json(path, value):
    path = Path(path)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)
    return record(path)


class Original54Deadline:
    """Keep the original job's210-minute ceiling, including checkout/preparation."""

    def __init__(self, evidence):
        self.evidence = evidence
        clock_path = Path(os.environ["PAIRED_JOB_CLOCK"])
        clock = json.loads(clock_path.read_text())
        require(isinstance(clock.get("jobs"), list) and len(clock["jobs"]) == 1,
                "Original job clock is missing or ambiguous")
        job = clock["jobs"][0]
        require(type(clock.get("schema")) is int and clock["schema"] == 1,
                "Original job clock schema is absent")
        require(type(clock.get("runID")) is int and str(clock["runID"]) == os.environ["GITHUB_RUN_ID"]
                and type(clock.get("runAttempt")) is int and str(clock["runAttempt"]) == os.environ["GITHUB_RUN_ATTEMPT"]
                and job["run_id"] == clock["runID"] and job["head_sha"] == os.environ["GITHUB_SHA"]
                and job["name"] == "miniapps" and job["runner_name"] == os.environ["RUNNER_NAME"]
                and job["status"] == "in_progress", "Job clock belongs to another source/run/attempt/runner")
        if "run_attempt" in job:
            require(job["run_attempt"] == clock["runAttempt"], "Job clock attempt changed")
        def epoch(value):
            stamp = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
            require(stamp.tzinfo is not None, "Job clock timestamps must have an explicit timezone")
            return stamp.timestamp()
        self.started = epoch(job["started_at"])
        observed = epoch(clock["observedAt"])
        now = time.time()
        require(self.started <= observed <= now, "Job clock is future-dated or precedes the actual job")
        self.deadline = self.started + ORIGINAL54_JOB_SECONDS
        require(now < self.deadline, "Original54 job deadline expired during preparation")
        self.monotonic_deadline = time.monotonic() + self.deadline - now
        self.clock = clock
        self.clock_record = write_json(evidence / "original54-job-clock.json", clock)

    def remaining(self):
        return min(self.deadline - time.time(), self.monotonic_deadline - time.monotonic())

    def limit(self, name, timeout):
        remaining = self.remaining()
        require(remaining > 0, "Original54 exceeded its original210-minute job deadline")
        effective = min(timeout, remaining)
        with (self.evidence / "original54-deadline-caps.jsonl").open("a") as stream:
            stream.write(json.dumps({"log": name, "requestedTimeout": timeout,
                                     "effectiveTimeout": effective, "at": time.time(),
                                     "jobStartedAt": self.started, "deadlineEpoch": self.deadline}) + "\n")
        return effective

    def complete(self):
        require(self.remaining() >= 0, "Original54 completed after its original210-minute job deadline")
        return {"status": "ORIGINAL54_COMPLETED_WITHIN_ORIGINAL_JOB_BUDGET",
                "clock": self.clock_record, "source": self.clock["jobs"][0]["head_sha"],
                "jobStartedAt": self.started, "deadlineEpoch": self.deadline,
                "originalLimitSeconds": ORIGINAL54_JOB_SECONDS, "completedAt": time.time()}


def inventory(root):
    path = root / INVENTORY
    require(sha256(path) == INVENTORY_SHA256, "The original extra26 inventory changed")
    document = json.loads(path.read_text())
    scope = document["miniappsAdditional"]
    methods = {row["identifier"]: row for row in scope["exactMethods"]}
    require(len(scope["selectors"]) == 6 and len(methods) == 22
            and sum(row["expectedInvocations"] for row in methods.values()) == 26,
            "The original six selectors / 22 definitions / 26 invocations changed")
    scope["originalPaired"] = document["paired"]
    scope["currentSourcePaths"] = list(document["currentPendingSourceBindings"])
    return scope


def source_snapshot(root, scope):
    def git(*arguments):
        return subprocess.check_output(["git", "-C", str(root), *arguments], timeout=120)
    head = git("rev-parse", "HEAD").decode().strip()
    require(re.fullmatch(r"[0-9a-f]{40}", head), "Source HEAD is not an exact commit")
    # The canonical upstream resolver can legitimately apply its retained input
    # patch before the build. Bind its actual bytes; never pretend it is clean.
    patch = git("diff", "--binary", "--no-ext-diff", "HEAD", "--")
    selected = sorted({row["sourceFile"] for row in scope["exactMethods"]} | set(scope["currentSourcePaths"]) | {
        "Scripts/ProductSplit/run_paired_acceptance.py",
        "Scripts/ProductSplit/paired_extra26.py", "Scripts/CI/verify_selected_tests.py",
        "AI_HLY.xcodeproj/project.pbxproj", "HanlinMiniAppsApp/HanlinMiniApps.entitlements",
        "AI_HLY/AI_HLY.entitlements", INVENTORY})
    untracked = [name for name in git("ls-files", "--others", "--exclude-standard", "-z").decode().split("\0")
                 if name and Path(name).suffix in {".swift", ".m", ".mm", ".h", ".c", ".cpp", ".pbxproj", ".entitlements"}]
    return {"head": head, "canonicalWorkingPatchSHA256": hashlib.sha256(patch).hexdigest(),
            "canonicalWorkingPatchBytes": len(patch),
            "indexSHA256": hashlib.sha256(git("ls-files", "--stage", "-z")).hexdigest(),
            "untrackedNativeInputs": {name: sha256(root / name) for name in sorted(untracked)},
            "selectedInputs": {name: sha256(root / name) for name in selected}}


def observe_inputs(root, evidence, state, command, phase):
    scope = inventory(root)
    source = source_snapshot(root, scope)
    require(source["head"] == state["sha"], "The original paired source changed")
    _, raw = command(["node", "Scripts/MiniApps/stage-sdk.mjs", "--fingerprint",
                      "--repository", str(root)], "extra26-" + phase + "-sdk.json", timeout=120)
    fingerprint = json.loads(raw)
    host = root / "AI_HLY/RuntimeHostResources.zip"
    with zipfile.ZipFile(host) as packed:
        sdk_bytes = packed.read("MiniAppSDK/miniapp-sdk.json")
    sdk = json.loads(sdk_bytes)
    require(fingerprint["sha256"] == sdk["inputSHA256"],
            "The shipping Host SDK does not match the actual current inputs")
    toolchain = {}
    for name, argv in (("xcode", ["xcodebuild", "-version"]),
                       ("swift", ["xcrun", "swift", "--version"]),
                       ("sdk", ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"])):
        _, value = command(argv, "extra26-" + phase + "-" + name + ".txt", timeout=60)
        toolchain[name] = value
    return {"source": source, "hostArchive": record(host),
            "sdkInputSHA256": fingerprint["sha256"],
            "packedSDKManifestSHA256": hashlib.sha256(sdk_bytes).hexdigest(),
            "toolchain": toolchain}


def capture_inputs(root, evidence, state, command):
    binding = observe_inputs(root, evidence, state, command, "before-build")
    state["extra26_input_binding"] = write_json(evidence / "extra26-before-build.json", binding)
    return binding


def resolve_descriptor(derived):
    products = (derived / "Build/Products").resolve(strict=True)
    candidates = []
    for path in products.glob("*.xctestrun"):
        content = plistlib.loads(path.read_bytes())
        targets = [target for configuration in content.get("TestConfigurations", [])
                   for target in configuration.get("TestTargets", [])]
        if not targets:
            targets = [value for key, value in content.items()
                       if isinstance(value, dict) and not key.startswith("__")]
        matches = [target for target in targets if target.get("BlueprintName") == "HanlinMiniAppsTests"
                   or target.get("ProductModuleName") == "HanlinMiniAppsTests"]
        if matches:
            candidates.append((path, matches))
    require(len(candidates) == 1 and len(candidates[0][1]) == 1,
            "The original app-hosted test descriptor is missing or ambiguous")
    path, matches = candidates[0]
    target = matches[0]
    require(not target.get("UseDestinationArtifacts") and not target.get("IsUITestBundle"),
            "Extra26 requires the original local app-hosted unit test product")

    def resolve(value, host=None):
        require(isinstance(value, str) and value, "Missing original descriptor path")
        value = value.replace("__TESTROOT__", str(path.parent))
        if host is not None:
            value = value.replace("__TESTHOST__", str(host))
        require(not re.search(r"__[A-Z_]+__", value), "Unresolved original descriptor macro")
        result = Path(value)
        return (result if result.is_absolute() else path.parent / result).resolve(strict=True)

    host = resolve(target["TestHostPath"])
    expected_host = (products / "Debug-iphonesimulator/HanlinMiniApps.app").resolve(strict=True)
    require(host == expected_host and host.is_dir(), "Descriptor points to another app host")
    tests = resolve(target["TestBundlePath"], host)
    allowed = {(products / "Debug-iphonesimulator/HanlinMiniAppsTests.xctest").resolve(),
               (host / "PlugIns/HanlinMiniAppsTests.xctest").resolve()}
    require(tests in allowed and tests.is_dir(), "Descriptor points to another test product")
    if target.get("TestHostBundleIdentifier"):
        require(target["TestHostBundleIdentifier"] == "com.itorah.hanlinminiapps",
                "Descriptor host bundle identifier changed")
    info = plistlib.loads((host / "Info.plist").read_bytes())
    require(info["CFBundleIdentifier"] == "com.itorah.hanlinminiapps", "Wrong original app identity")
    test_info = plistlib.loads((tests / "Info.plist").read_bytes())
    require(test_info["CFBundleExecutable"] == "HanlinMiniAppsTests", "Wrong test executable")
    return {"descriptor": record(path), "testHost": str(host), "testBundle": str(tests),
            "productsRoot": str(products), "target": target}


def product_snapshot(derived):
    binding = resolve_descriptor(derived)
    products = Path(binding["productsRoot"])
    files = {}

    def walk(path, ancestors):
        resolved = path.resolve(strict=True)
        require(resolved.is_relative_to(products), "Original product escapes the owned Products tree")
        if path.is_dir():
            require(resolved not in ancestors, "Cycle in original product links")
            if path.is_symlink():
                files[str(path)] = {"link": os.readlink(path), "resolved": str(resolved)}
            for child in sorted(path.iterdir()):
                walk(child, ancestors | {resolved})
        else:
            files[str(path)] = record(path)
            if path.is_symlink():
                files[str(path)]["link"] = os.readlink(path)

    for path in (Path(binding["testHost"]), Path(binding["testBundle"])):
        walk(path, set())
    binding["files"] = files
    return binding


def capture_products(derived, evidence, state):
    binding = product_snapshot(derived)
    state["extra26_product_binding"] = write_json(evidence / "extra26-before-original54-products.json", binding)
    return binding


def completed_commands(evidence):
    latest = {}
    for line in (evidence / "command-events.jsonl").read_text().splitlines():
        row = json.loads(line)
        latest[row["log"]] = row
    completions = {row["log"]: row for row in
                   (json.loads(line) for line in (evidence / "commands.jsonl").read_text().splitlines())}
    for name, row in latest.items():
        completion = completions.get(name)
        if completion and row.get("completion_recorded"):
            require(row["argv"] == completion["argv"] and row.get("exit") == completion["exit"],
                    "Original command journals disagree: " + name)
            output = record(evidence / name)
            require(output["sha256"] == completion["sha256"], "Original command output changed: " + name)
            row["retainedOutput"] = output
    return latest


def require_phase(commands, name, timeout=None):
    row = commands.get(name, {})
    require(row.get("status") == "completed" and row.get("completion_recorded") is True
            and type(row.get("exit")) is int and row["exit"] == 0
            and row.get("observed_returncode") == 0 and not row.get("stopReason")
            and row.get("retainedOutput"),
            "Original prerequisite did not complete without a stop: " + name)
    if timeout is not None:
        require(row.get("timeout") == timeout, "Original prerequisite budget changed: " + name)
    return row


def validate_admission(payload):
    state, commands = payload["original54"], payload["commands"]
    require(state.get("status") == state.get("ui") == "EXECUTED_PASS"
            and state.get("test_scope") == "miniapp_complete", "Original paired54 did not pass")
    budget = state.get("original54_job_budget", {})
    times = [budget.get(key) for key in ("jobStartedAt", "deadlineEpoch", "completedAt")] + [payload.get("admittedAt")]
    require(all(type(value) in (int, float) and math.isfinite(value) for value in times),
            "Original54 job clock contains non-finite or nonnumeric times")
    require(budget.get("status") == "ORIGINAL54_COMPLETED_WITHIN_ORIGINAL_JOB_BUDGET"
            and budget.get("source") == state.get("sha")
            and budget.get("originalLimitSeconds") == ORIGINAL54_JOB_SECONDS
            and budget.get("deadlineEpoch") == budget.get("jobStartedAt", 0) + ORIGINAL54_JOB_SECONDS
            and budget["jobStartedAt"] <= budget.get("completedAt", float("inf")) <= budget["deadlineEpoch"]
            and budget["completedAt"] <= payload["admittedAt"] <= budget["deadlineEpoch"],
            "Original54/preparation exceeded its original210-minute job budget")
    require(state.get("selected_tests") == payload["originalPlan"]["hanlin"]["selectors"]
            and state.get("original_runtime_selectors") == payload["originalPlan"]["miniapps"]["selectors"],
            "The original paired54 selector arrays changed")
    require(payload["beforeInputs"] == payload["currentInputs"],
            "Source, canonical inputs, compiler, entitlements or shipping SDK changed after the build")
    require(state.get("sha") == payload["beforeInputs"]["source"]["head"], "Wrong original source receipt")
    require(payload["beforeProducts"] == payload["currentProducts"],
            "Original app, test product or unmodified descriptor changed after original54")
    require(state.get("app_group", {}).get("status") == "EXECUTED_PASS",
            "The original two-product App Group prerequisite did not pass")
    require(state.get("native_adapter_assets", {}).get("native_request_proof")
            == "EXECUTED_PASS_RESOURCE_TRANSPORT" and state.get("external_modal_result"),
            "The original runtime fixture/result prerequisites are absent")
    for name, scheme, budget in (("mini-build.log", "HanlinMiniApps", 3600),
                                  ("ai-build.log", "AI_HLY", 1800)):
        phase = require_phase(commands, name)
        require(0 < phase.get("timeout", 0) <= budget, "Original build phase budget was extended")
        argv = phase["argv"]
        require(argv[argv.index("-scheme") + 1] == scheme and "build-for-testing" in argv,
                "Original build prerequisite does not name the required target")
    for prefix, phase, key, expected, budget, scheme in (
            ("original-runtimes", "original-runtimes.log", "original_runtime_selectors", 25, 2400, "HanlinMiniApps"),
            ("paired", "paired-tests.log", "selected_tests", 29, 2100, "AI_HLY")):
        proof = payload["proofs"][prefix]
        summary = proof["summary"]
        require(type(summary.get("passedTests")) is int and summary["passedTests"] == expected
                and summary.get("failedTests", 0) == summary.get("skippedTests", 0)
                == summary.get("expectedFailures", 0) == 0,
                "Original native count/result differs from the required " + str(expected))
        require(summary == state["original_runtime_summary" if expected == 25 else "summary"],
                "Original native summary differs from its durable receipt")
        require(proof["summaryFile"] == require_phase(commands, proof["summaryLog"])["retainedOutput"]
                and proof["nodes"] == require_phase(commands, proof["nodesLog"])["retainedOutput"],
                "Original native result bytes differ from the actual extraction commands")
        native_phase = require_phase(commands, phase)
        require(0 < native_phase.get("timeout", 0) <= budget, "Original54 native phase budget was extended")
        argv = native_phase["argv"]
        selected = [item.removeprefix("-only-testing:") for item in argv if item.startswith("-only-testing:")]
        require(selected == state[key] and argv[argv.index("-scheme") + 1] == scheme
                and "test-without-building" in argv
                and argv[argv.index("-resultBundlePath") + 1] == proof["resultBundle"]
                and argv[argv.index("-destination") + 1] == "platform=iOS Simulator,id=" + state["simulator"],
                "Original native command/source/device/selector binding changed")
        verification = require_phase(commands, proof["verificationLog"])["argv"]
        require(verification[verification.index("--selectors") + 1] == ",".join(state[key])
                and verification[verification.index("--results") + 1] == proof["nodes"]["path"],
                "Original selector verification does not bind the actual native nodes")
    device = payload["device"]
    require(device["udid"] == state["simulator"] and device.get("isAvailable") is True
            and device.get("state") == "Booted" and device["name"].startswith("HanlinPaired-")
            and payload["runtime"]["identifier"] == state["runtime"], "Owned paired simulator changed")
    require(payload["runtime"]["version"] == state["simulator_runtime_selection"]["runtime_version"],
            "Actual original paired runtime version changed")
    require(payload["freeBytes"] >= ADMISSION_FREE_BYTES, "Insufficient original extra26 admission space")


def admit_and_execute(payload, execute):
    """There is one native launch boundary, after every original prerequisite."""
    validate_admission(payload)
    return execute()


def run_native(root, evidence, argv, receipt):
    """Original v3 process-group, 2400-second and 1GiB stop guards."""
    log = evidence / "original-extra26-tests.log"
    phase = {"argv": argv, "status": "STARTING", "timeoutSeconds": DEADLINE_SECONDS,
             "log": str(log), "startedAt": time.time()}
    receipt["nativePhase"] = phase
    receipt_path = evidence / "extra26-acceptance.json"
    write_json(receipt_path, receipt)
    with log.open("xb") as output:
        process = subprocess.Popen(argv, cwd=root, stdin=subprocess.DEVNULL, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        phase.update(pid=process.pid, pgid=process.pid, status="RUNNING")
        receipt["nativeJobsStarted"] = 1
        write_json(receipt_path, receipt)
        started = time.monotonic()
        try:
            while True:
                try:
                    code = process.wait(timeout=min(10, max(0.001, DEADLINE_SECONDS - (time.monotonic() - started))))
                    if time.monotonic() - started > DEADLINE_SECONDS:
                        phase["stopReason"] = "ORIGINAL_PHASE_TIMEOUT"
                    break
                except subprocess.TimeoutExpired:
                    phase["lastObservation"] = {"elapsedSeconds": time.monotonic() - started,
                                                "freeBytes": shutil.disk_usage(evidence).free,
                                                "logBytes": log.stat().st_size}
                    write_json(receipt_path, receipt)
                    if phase["lastObservation"]["freeBytes"] < CONTINUOUS_FREE_BYTES or time.monotonic() - started > DEADLINE_SECONDS:
                        phase["stopReason"] = ("RESOURCE_FLOOR" if phase["lastObservation"]["freeBytes"] < CONTINUOUS_FREE_BYTES
                                               else "ORIGINAL_PHASE_TIMEOUT")
                        os.killpg(process.pid, signal.SIGINT)
                        try:
                            code = process.wait(timeout=30)
                        except subprocess.TimeoutExpired:
                            os.killpg(process.pid, signal.SIGTERM)
                            try:
                                code = process.wait(timeout=15)
                            except subprocess.TimeoutExpired:
                                os.killpg(process.pid, signal.SIGKILL)
                                code = process.wait(timeout=10)
                        break
        except BaseException:
            phase["stopReason"] = "INTERRUPTED"
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=10)
            phase.update(status="STOPPED", exitCode=process.returncode, finishedAt=time.time())
            write_json(receipt_path, receipt)
            raise
    phase.update(status="STOPPED" if phase.get("stopReason") else "COMPLETED",
                 exitCode=code, finishedAt=time.time(), logSHA256=sha256(log))
    write_json(receipt_path, receipt)
    return phase


def reconcile(summary, tree, scope, simulator, runtime, phase):
    """The original v3 exact method/parameter/device reconciliation, unchanged in scope."""
    expected = {row["identifier"]: row for row in scope["exactMethods"]}
    actual = {}

    def walk(node, target=None):
        if node.get("nodeType") == "Unit test bundle":
            target = node["name"]
        if node.get("nodeType") == "Test Case":
            identifier = target + "/" + node["nodeIdentifier"]
            require(identifier not in actual, "Duplicate original test definition")
            actual[identifier] = node
        for child in node.get("children", []):
            walk(child, target)
    for node in tree["testNodes"]:
        walk(node)
    require(set(actual) == set(expected), "Missing or unexpected original extra26 definitions")
    methods, cases, rows, argument_urls = collections.Counter(), collections.Counter(), [], []
    outcomes = ("Passed", "Failed", "Skipped", "Expected Failure")
    for identifier, entry in sorted(expected.items()):
        node = actual[identifier]
        require(node["result"] in outcomes, "Unknown native test outcome")
        methods[node["result"]] += 1
        arguments = [child for child in node.get("children", []) if child.get("nodeType") == "Arguments"]
        row = {"identifier": identifier, "result": node["result"],
               "expectedInvocations": entry["expectedInvocations"],
               "actualInvocations": len(arguments) if arguments else 1,
               "nodeIdentifierURL": node["nodeIdentifierURL"]}
        require(row["actualInvocations"] == entry["expectedInvocations"], "Native argument cardinality changed")
        if entry.get("parameterValues") is not None:
            displays = [str(value).lower() if isinstance(value, bool) else json.dumps(value, ensure_ascii=False)
                        for value in entry["parameterValues"]]
            require(collections.Counter(child["name"] for child in arguments) == collections.Counter(displays),
                    "Original parameter values were omitted or changed")
            row["arguments"] = []
            for child in arguments:
                require(child["result"] in outcomes, "Unknown native argument outcome")
                url = child["nodeIdentifierURL"]
                require(url.startswith(node["nodeIdentifierURL"] + "?args=") and url.split("?args=", 1)[1],
                        "Native argument identity is absent")
                argument_urls.append(url)
                cases[child["result"]] += 1
                row["arguments"].append({"display": child["name"], "result": child["result"], "nodeIdentifierURL": url})
        else:
            require(not arguments, "Unexpected parameterization of an original method")
            cases[node["result"]] += 1
        rows.append(row)
    require(len(argument_urls) == len(set(argument_urls)) == 7
            and sum(methods.values()) == 22 and sum(cases.values()) == 26, "Original22/26/7 reconciliation failed")
    require(summary["totalTestCount"] == 22 and len(summary["devicesAndConfigurations"]) == 1,
            "Native summary contains another definition set or device")
    device = summary["devicesAndConfigurations"][0]
    require(device["device"]["deviceId"] == simulator and device["device"]["osVersion"] == runtime["version"]
            and device["device"]["osBuildNumber"] == runtime["buildversion"],
            "Extra26 did not use the original paired simulator/runtime/build")
    for key, outcome in (("passedTests", "Passed"), ("failedTests", "Failed"),
                         ("skippedTests", "Skipped"), ("expectedFailures", "Expected Failure")):
        require(summary.get(key, 0) == methods[outcome] and device.get(key, 0) == cases[outcome],
                "Native summary disagrees with original method/argument outcomes")
    passed = (phase.get("status") == "COMPLETED" and phase.get("exitCode") == 0
              and not phase.get("stopReason") and methods["Passed"] == 22 and cases["Passed"] == 26
              and not any(cases[key] for key in outcomes[1:]))
    return {"status": "EXACT_REQUIRED_EXTRA26_PASSED" if passed else "EXACT_REQUIRED_EXTRA26_EXECUTED_WITH_FAILURES",
            "actualDefinitions": 22, "actualInvocations": 26, "methodResults": dict(methods),
            "invocationResults": dict(cases), "parameterizedDefinitions": 3, "parameterInvocations": 7,
            "parameterValuesExactlyReconciled": True, "device": device["device"], "tests": rows}


def continue_after_paired(root, evidence, derived, original54, before_inputs, before_products, command):
    receipt = {"status": "NOT_RUN", "source": original54["sha"], "nativeJobsStarted": 0,
               "originalControllerSHA256": ORIGINAL_CONTROLLER_SHA256,
               "inventorySHA256": INVENTORY_SHA256,
               "scope": "Original54 first; original22 definitions/26 invocations on the identical same-job MiniApps products and owned simulator. No OS/device/distribution credit."}
    result = evidence / "Extra26.xcresult"
    try:
        receipt["original54"] = write_json(evidence / "original54-acceptance.json", original54)
        scope = inventory(root)
        current_inputs = observe_inputs(root, evidence, original54, command, "admission")
        current_products = product_snapshot(derived)
        _, raw = command(["xcrun", "simctl", "list", "devices", "-j"], "extra26-owned-device.json")
        devices = [device for device in json.loads(raw)["devices"].get(original54["runtime"], [])
                   if device["udid"] == original54["simulator"]]
        require(len(devices) == 1, "Owned paired simulator is absent or ambiguous")
        runtimes = json.loads((evidence / "runtimes.json").read_text())["runtimes"]
        runtimes = [runtime for runtime in runtimes if runtime["identifier"] == original54["runtime"]]
        require(len(runtimes) == 1 and runtimes[0].get("buildversion"), "Original runtime build evidence is absent")
        proofs = {}
        for prefix, summary_name, nodes_name, verification in (
                ("original-runtimes", "original-runtimes-summary.json", "original-runtimes-nodes.json", "original-runtimes-selected-tests.log"),
                ("paired", "test-summary.json", "test-nodes.json", "requested-tests.log")):
            proofs[prefix] = {"summary": json.loads((evidence / summary_name).read_text()),
                              "summaryFile": record(evidence / summary_name),
                              "nodes": record(evidence / nodes_name), "verificationLog": verification,
                              "summaryLog": summary_name, "nodesLog": nodes_name,
                              "resultBundle": str(evidence / ("OriginalRuntimes.xcresult" if prefix == "original-runtimes" else "Paired.xcresult"))}
        payload = {"original54": original54, "commands": completed_commands(evidence),
                   "originalPlan": scope["originalPaired"],
                   "beforeInputs": before_inputs, "currentInputs": current_inputs,
                   "beforeProducts": before_products, "currentProducts": current_products,
                   "proofs": proofs, "device": devices[0], "runtime": runtimes[0],
                   "freeBytes": shutil.disk_usage(evidence).free, "admittedAt": time.time()}
        receipt["admission"] = write_json(evidence / "extra26-admission.json", payload)
        descriptor = current_products["descriptor"]["path"]
        argv = ["xcodebuild", "-xctestrun", descriptor, "-destination", "platform=iOS Simulator,id=" + original54["simulator"],
                "-parallel-testing-enabled", "NO", "-derivedDataPath", str(derived),
                "-clonedSourcePackagesDirPath", str(root / "build/SourcePackages"),
                "-skipPackagePluginValidation", "-skipMacroValidation", "CODE_SIGNING_ALLOWED=YES",
                "CODE_SIGNING_REQUIRED=YES", "CODE_SIGN_IDENTITY=-", "-collect-test-diagnostics", "never",
                "test-without-building", "-resultBundlePath", str(result)]
        argv += ["-only-testing:" + selector for selector in scope["selectors"]]
        phase = admit_and_execute(payload, lambda: run_native(root, evidence, argv, receipt))
        require(result.is_dir(), "Original extra26 produced no xcresult")
        _, raw = command(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result)],
                         "extra26-summary.json")
        summary = json.loads(raw)
        _, raw = command(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(result)],
                         "extra26-nodes.json")
        tree = json.loads(raw)
        command([sys.executable, "Scripts/CI/verify_selected_tests.py", "--results", str(evidence / "extra26-nodes.json"),
                 "--selectors", ",".join(scope["selectors"])], "extra26-selected-tests.log")
        reconciliation = reconcile(summary, tree, scope, original54["simulator"], runtimes[0], phase)
        receipt["reconciliation"] = write_json(evidence / "extra26-reconciliation.json", reconciliation)
        after_inputs = observe_inputs(root, evidence, original54, command, "after")
        after_products = product_snapshot(derived)
        receipt["afterInputs"] = write_json(evidence / "extra26-after-inputs.json", after_inputs)
        receipt["afterProducts"] = write_json(evidence / "extra26-after-products.json", after_products)
        require(before_inputs == after_inputs and before_products == after_products,
                "Source/compiler/SDK or original app/test/descriptor changed during extra26")
        require(reconciliation["status"] == "EXACT_REQUIRED_EXTRA26_PASSED",
                "An original extra26 invocation failed, skipped, stopped or did not execute")
        receipt.update(status="EXACT_ORIGINAL_EXTRA26_ACCEPTANCE_PASSED", sourceAndOriginalProductsUnchanged=True)
    except BaseException as error:
        receipt.update(status="FAILED" if receipt["nativeJobsStarted"] else "NOT_RUN_PREREQUISITE_FAILED",
                       error=str(error), errorType=type(error).__name__)
        raise
    finally:
        if result.exists():
            try:
                code, _ = command(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result),
                                   "--output-path", str(evidence / "extra26-attachments")],
                                  "extra26-attachments-export.log", timeout=60, allow_failure=True)
                receipt["attachmentExportExitCode"] = code
            except Exception as error:
                receipt["attachmentExportError"] = str(error)
        receipt["finishedAt"] = time.time()
        write_json(evidence / "extra26-acceptance.json", receipt)
    return receipt
