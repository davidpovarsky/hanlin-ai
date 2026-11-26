#!/usr/bin/env python3
"""Existing per-build evidence and original separate test groups for hosted CI."""
from pathlib import Path
import datetime, hashlib, importlib.util, json, mmap, os, plistlib, re, signal
import shutil, stat, struct, subprocess, sys, threading, time, uuid

ROOT = Path(os.environ["GITHUB_WORKSPACE"]).resolve()
RUNNER = "Scripts/ProductSplit/run_paired_acceptance.py"
RUNNER_SHA = "a99b6194f8dd20bc30998ff2ad9e86ec219415a00615b250c65670f7dfcdba7d"
HOSTED = "AI_HLYTests/Fixtures/HostServicesProbe.bundle/ExpoSwiftUIProbeA.hanlinExpo"
HANDLER_SELECTOR = "AI_HLYTests/HanlinUnifiedHostServicesE2ETests/nativeScriptActionDeclarationsPreserveRegisteredJavaScriptState()"
QUEUE_SUITE = "HanlinWidgetHostActionTests"
QUEUE_TITLE = "Declared widget Host actions and canonical delivery"
QUEUE_SOURCE = "Packages/HanlinPlatform/Tests/HanlinScriptExtensionsTests/HanlinWidgetHostActionTests.swift"
QUEUE_SOURCE_SHA = "da939924b4de4bfab3a34a17e97d271cc355c641c48c69b0b5816a3395ce8ff6"
QUEUE_PLAN_SHA = "960a95dd9e04acc876a5e6c6a5d3377d789cbf48a9a064252f624d05be5aaa1d"

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def reference(path):
    p = Path(path)
    return {"path": str(p), "bytes": p.stat().st_size, "sha256": digest(p)}


def verified(row):
    p = Path(row["path"])
    assert p.is_file() and p.stat().st_size == row["bytes"] and digest(p) == row["sha256"], str(p)
    return p


def write_json(path, value):
    p = Path(path); temporary = p.with_name(p.name + ".tmp")
    with temporary.open("w") as stream:
        json.dump(value, stream, indent=2); stream.write("\n")
        stream.flush(); os.fsync(stream.fileno())
    temporary.replace(p)


def verify_swift_testing_log(raw, tests, suite_title):
    # Swift Testing's aggregate counts functions. Parameter execution is proved
    # separately by each function's terminal count and its actual argument rows.
    lines = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", raw).splitlines()
    expected = {}
    for item in tests:
        name = item["name"] if "(" in item["name"] else item["name"] + "()"
        assert name not in expected and type(item["instances"]) is int and item["instances"] > 0
        expected[name] = item
    starts, passes, arguments, summaries, suites = [], [], [], [], []
    for number, line in enumerate(lines, 1):
        assert "✘" not in line, {"line": number, "marker": line}
        assert not re.match(r"^[↷⊘].*\b(?:Test|Suite)\b", line), line
        match = re.fullmatch(r"◇ Test (\S+\([^)]*\)) started\.", line)
        if match:
            starts.append(match.group(1))
        match = re.fullmatch(r"✔ Test (\S+)(?: with (\d+) test cases)? passed after [0-9.]+ seconds\.", line)
        if match:
            passes.append({"name": match.group(1), "parameterCount": int(match.group(2)) if match.group(2) else None,
                           "line": number, "marker": line})
        match = re.fullmatch(r"◇ Test case passing 1 argument (\w+) → (.+) to (\S+) started\.", line)
        if match:
            rendered = match.group(2)
            value = json.loads(rendered) if rendered.startswith('"') else rendered.removeprefix(".")
            assert isinstance(value, str), line
            arguments.append({"name": match.group(3), "label": match.group(1), "value": value,
                              "rendered": rendered, "line": number, "marker": line})
        if re.fullmatch(r"✔ Test run with \d+ tests? in \d+ suites? passed after [0-9.]+ seconds\.", line):
            summaries.append(line)
        if re.fullmatch(r'✔ Suite ".+" passed after [0-9.]+ seconds\.', line):
            suites.append(line)
    assert len(starts) == len(expected) and set(starts) == set(expected), starts
    assert len(passes) == len(expected) and {row["name"] for row in passes} == set(expected), passes
    assert len(summaries) == 1 and re.fullmatch(
        rf"✔ Test run with {len(expected)} tests in 1 suite passed after [0-9.]+ seconds\.", summaries[0]), summaries
    assert len(suites) == 1 and re.fullmatch(
        r'✔ Suite "' + re.escape(suite_title) + r'" passed after [0-9.]+ seconds\.', suites[0]), suites
    assert all(row["name"] in expected for row in arguments), arguments
    reviews = []
    for name, item in expected.items():
        terminal = next(row for row in passes if row["name"] == name)
        cases = [row for row in arguments if row["name"] == name]
        values = item.get("arguments", [])
        if values:
            assert terminal["parameterCount"] == item["instances"] == len(values)
            assert len(cases) == len(values) and {row["value"] for row in cases} == set(values), cases
            label = item.get("argumentLabel", name.split("(", 1)[1].split(":", 1)[0])
            assert all(row["label"] == label for row in cases), cases
        else:
            assert item["instances"] == 1 and terminal["parameterCount"] is None and not cases
        reviews.append({"name": name, "status": "EXECUTED_PASS", "instances": item["instances"],
                        "terminal": terminal, "argumentStarts": cases})
    return {"observedFunctions": len(reviews),
            "observedParameterInstances": sum(row["instances"] for row in reviews),
            "failedFunctions": 0, "skippedFunctions": 0, "functionResults": reviews,
            "suitePassMarker": suites[0], "runPassMarker": summaries[0],
            "countBoundary": "Function terminal counts and actual argument markers establish parameter invocations; the native aggregate counts functions."}


def xctestrun_for(derived, target, host_bundle_id):
    products = derived / "Build/Products"
    matches = []
    for p in sorted(products.glob("*.xctestrun")):
        value = plistlib.loads(p.read_bytes())
        record = value.get(target)
        if not isinstance(record, dict):
            continue
        if record.get("TestHostBundleIdentifier") != host_bundle_id:
            continue
        assert record.get("IsAppHostedTestBundle") is True, target
        host = record["TestHostPath"]
        bundle = record["TestBundlePath"]
        assert host == "__TESTROOT__/Debug-iphonesimulator/AI_Hanlin.app", host
        assert bundle == "__TESTHOST__/PlugIns/AI_HLYTests.xctest", bundle
        assert (products / "Debug-iphonesimulator/AI_Hanlin.app/PlugIns/AI_HLYTests.xctest").is_dir()
        matches.append((p, record))
    assert len(matches) == 1, [str(p) for p, _ in matches]
    return matches[0]


def make_preboot_diagnostic_command(original, evidence, source):
    """Keep one unconsumed process snapshot truthful without making it an acceptance gate."""
    expected_argv = ["ps", "-axo", "pid,ppid,%cpu,%mem,state,etime,comm"]
    expected_name = "before-boot-processes.txt"

    def checked(*args, **kwargs):
        argv = args[0] if args else kwargs.get("argv")
        name = args[1] if len(args) > 1 else kwargs.get("name")
        timeout = args[2] if len(args) > 2 else kwargs.get("timeout", 60)
        allow_failure = args[3] if len(args) > 3 else kwargs.get("allow_failure", False)
        if argv != expected_argv or name != expected_name or timeout != 60 or allow_failure is not False:
            return original(*args, **kwargs)
        receipt_path = evidence / "preboot-process-diagnostic.json"
        assert not receipt_path.exists(), str(receipt_path)
        started_at = now()
        started = time.monotonic()
        forwarded_args, forwarded_kwargs = list(args), dict(kwargs)
        if len(forwarded_args) > 3:
            forwarded_args[3] = True
        else:
            forwarded_kwargs["allow_failure"] = True
        # The original runner executes the same argv with its same timeout,
        # kill/wait behavior, raw logfile and actual command/timeout journals.
        result = original(*forwarded_args, **forwarded_kwargs)
        code, _ = result
        warning = None if code == 0 else (
            "Pre-boot process telemetry unavailable: original ps exit " + str(code) +
            "; actual raw log and command journals retained. No product/test result inferred.")
        write_json(receipt_path, {
            "schema": 1, "id": "preboot-process-diagnostic", "source": source,
            "status": "OBSERVED" if code == 0 else "UNAVAILABLE",
            "startedAt": started_at, "finishedAt": now(),
            "actualElapsedSeconds": time.monotonic() - started,
            "argv": expected_argv, "timeoutSeconds": 60,
            "originalCommandExitCode": code, "log": reference(evidence / expected_name),
            "originalRunnerSHA256": RUNNER_SHA, "warning": warning,
            "observationalOnly": True,
            "boundary": "Only the exact unconsumed pre-boot ps snapshot permits an actual nonzero exit. "
                        "Every original build, test, fixture and resource authority remains unchanged."})
        if warning:
            print(warning, file=sys.stderr, flush=True)
        return result

    return checked


def capture_compiled_metadata(d, evidence, derived, log_name, argv, code):
    """Retain each original scheme's metadata before the next scheme overwrites it."""
    schemes = {"mini-build.log": ("HanlinMiniApps", "HanlinMiniApps.app", "metadata-after-mini-build"),
               "ai-build.log": ("AI_HLY", "AI_Hanlin.app", "metadata-after-ai-build")}
    scheme, app_name, label = schemes[log_name]
    assert code == 0 and argv[0] == "xcodebuild" and "build-for-testing" in argv
    assert argv[argv.index("-scheme") + 1] == scheme
    assert argv[argv.index("-derivedDataPath") + 1] == str(derived)
    destination = evidence / label
    destination.mkdir()
    receipt_path = destination / "receipt.json"
    receipt = {"schema": 1, "id": label, "status": "RUNNING", "source": d["source"],
               "sourceTree": d["sourceTree"], "startedAt": now(), "originalBuildLog": log_name,
               "originalBuildExitCode": code, "originalBuildArgv": argv,
               "originalCommandUnchanged": True, "files": [], "images": [], "errors": [],
               "boundary": "Actual original build metadata and exact linked host section, retained per scheme. "
                           "Build-time native-name completeness is separate from real VM visibility and acceptance."}
    write_json(receipt_path, receipt)

    def retain(path, name):
        before = path.stat()
        assert path.is_file() and not path.is_symlink(), str(path)
        origin = reference(path)
        target = destination / name
        assert not target.exists()
        shutil.copy2(path, target)
        stored = reference(target)
        after = path.stat()
        assert (before.st_size, before.st_mtime_ns, before.st_ino) == (
            after.st_size, after.st_mtime_ns, after.st_ino), str(path)
        assert (stored["bytes"], stored["sha256"]) == (origin["bytes"], origin["sha256"])
        receipt["files"].append({"origin": origin, "retained": stored})
        return target

    try:
        wrapper = ROOT / "Scripts/NativeScript/build-step-metadata-generator-wrapper.py"
        assert digest(wrapper) == "577e4d58a3bebd29e379918938199aacff0a4c775cfb1c4923e1f7735686238c"
        receipt["wrapper"] = reference(wrapper)
        receipt["buildLog"] = reference(evidence / log_name)
        producer = ROOT / "build/acceptance/nativescript-metadata/iphonesimulator-arm64"
        names = ["metadata-arm64.bin", "metadata-generation-stderr-arm64.txt", "umbrella-arm64.h",
                 "visibility.json", "HanlinMetadataInput.h", "HanlinMetadataInput.inventory.json",
                 "FrameworkSearchView.inventory.json", "provenance.json"]
        copied = {name: retain(producer / name, name) for name in names}
        products = derived / "Build/Products/Debug-iphonesimulator"
        linked_input = retain(products / "metadata-arm64.bin", "linked-metadata-arm64.bin")
        metadata = reference(copied["metadata-arm64.bin"])
        assert (linked_input.stat().st_size, digest(linked_input)) == (metadata["bytes"], metadata["sha256"])
        visibility = json.loads(copied["visibility.json"].read_text())
        required_names = ["HanlinNativeServicesBridge", "HanlinNativeServicesSessionBridge",
                          "HanlinNativeScriptCompatibility", "UIView", "NSObject", "NSUserDefaults",
                          "NativeScriptEmbedder", "SwiftUIProvider",
                          "HanlinNativeScriptSwiftUIFixtureProvider", "WKNavigationDelegate",
                          "WKWebView", "TNSLabel", "NSCCrypto"]
        assert visibility["scope"] == "HOST_BASELINE_ONLY"
        assert visibility["platform"] == "iphonesimulator" and visibility["architecture"] == "arm64"
        assert set(visibility["requiredMetadataStringsPresent"]) == set(required_names)
        assert all(value is True for value in visibility["requiredMetadataStringsPresent"].values())
        assert visibility["clangErrorCount"] == 0
        for name in ["metadata-arm64.bin", "metadata-generation-stderr-arm64.txt", "umbrella-arm64.h"]:
            assert visibility["sha256"][name] == digest(copied[name]), name
        receipt["visibility"] = visibility
        provenance = json.loads(copied["provenance.json"].read_text())
        tool = ROOT / "build/nativescript-metadata-tool/bin/objc-metadata-generator"
        patch = ROOT / "Scripts/NativeScript/build-metadata-tool.py"
        assert digest(tool) == provenance["generatorSHA256"]
        assert digest(patch) == provenance["patchSourceSHA256"]
        receipt["metadataTool"] = reference(tool)
        receipt["metadataToolSource"] = reference(patch)
        app = products / app_name
        info = plistlib.loads((app / "Info.plist").read_bytes())
        executable = info["CFBundleExecutable"]
        assert Path(executable).name == executable
        receipt["appInfo"] = reference(app / "Info.plist")
        paths = [app / executable]
        debug = app / (executable + ".debug.dylib")
        if debug.is_file():
            paths.append(debug)
        matches = []
        for path in paths:
            before = path.stat()
            record = {"image": reference(path), "sections": []}
            with path.open("rb") as stream:
                with mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as raw:
                    magic, cpu, subtype, filetype, ncmds, command_bytes, flags, reserved = struct.unpack_from("<IiiIIIII", raw, 0)
                    assert magic == 0xfeedfacf and cpu == 0x0100000c, str(path)
                    offset, limit = 32, 32 + command_bytes
                    assert 0 < ncmds < 10000 and limit <= len(raw)
                    for _ in range(ncmds):
                        command, length = struct.unpack_from("<II", raw, offset)
                        assert length >= 8 and offset + length <= limit
                        if command == 0x19:
                            segment = struct.unpack_from("<II16sQQQQiiII", raw, offset)
                            count = segment[-2]
                            assert 72 + count * 80 <= length
                            for index in range(count):
                                section = struct.unpack_from("<16s16sQQIIIIIIII", raw, offset + 72 + index * 80)
                                name = section[0].split(b"\0")[0].decode()
                                segment_name = section[1].split(b"\0")[0].decode()
                                if name != "__TNSMetadata":
                                    continue
                                size, start = section[3], section[4]
                                assert segment_name == "__DATA" and 0 < size and start + size <= len(raw)
                                binary = raw[start:start + size]
                                target = destination / (path.name + "-TNSMetadata.bin")
                                with target.open("xb") as output:
                                    output.write(binary)
                                section_row = {"segment": segment_name, "section": name,
                                               "fileOffset": start, "bytes": size,
                                               "sha256": hashlib.sha256(binary).hexdigest(),
                                               "retained": reference(target)}
                                record["sections"].append(section_row)
                                matches.append(section_row)
                        offset += length
                    assert offset == limit
            after = path.stat()
            assert (before.st_size, before.st_mtime_ns, before.st_ino) == (
                after.st_size, after.st_mtime_ns, after.st_ino), str(path)
            receipt["images"].append(record)
        assert len(matches) == 1, receipt["images"]
        assert (matches[0]["bytes"], matches[0]["sha256"]) == (metadata["bytes"], metadata["sha256"])
        receipt["matchedSection"] = matches[0]
        receipt["status"] = "VERIFIED_COMPILED_METADATA"
    except BaseException as error:
        receipt["status"] = "FAILED_METADATA_VERIFICATION"
        receipt["errors"].append({"type": type(error).__name__, "message": str(error)})
        raise
    finally:
        receipt["finishedAt"] = now()
        write_json(receipt_path, receipt)
    return reference(receipt_path)


def observe_failed_native_execution(evidence, group):
    """Classify retained executed failures without changing the original result verifier."""
    prefix = group["id"]
    summary_path = evidence / (prefix + "-summary.json")
    nodes_path = evidence / (prefix + "-nodes.json")
    result = {"classification": "FAILED_EXECUTION_NOT_ESTABLISHED", "acceptancePassed": False}
    if not summary_path.is_file() or not nodes_path.is_file():
        result["reason"] = "Original result files unavailable."
        return result
    try:
        summary = json.loads(summary_path.read_text())
        nodes = json.loads(nodes_path.read_text())
        pending, cases = list(nodes["testNodes"]), []
        while pending:
            node = pending.pop()
            pending.extend(node.get("children", []))
            if node.get("nodeType") == "Test Case":
                cases.append(node)
        counts = {key: summary[key] for key in ["totalTestCount", "passedTests", "failedTests", "skippedTests"]}
        assert all(type(value) is int and value >= 0 for value in counts.values())
        identities = []
        for case in cases:
            matches = [selector for selector in group["selectors"]
                       if case.get("nodeIdentifierURL", "").endswith("/" + selector)]
            assert len(matches) == 1
            identities.append(matches[0])
        result.update(summary=reference(summary_path), nodes=reference(nodes_path),
                      counts=counts, testcaseIdentities=identities)
        complete = (len(cases) == counts["totalTestCount"] == group["expectedCases"]
                    and len(set(identities)) == len(identities)
                    and set(identities) == set(group["selectors"])
                    and sum(counts[key] for key in ["passedTests", "failedTests", "skippedTests"]) == counts["totalTestCount"]
                    and sum(case.get("result") == "Failed" for case in cases) == counts["failedTests"])
        if complete and counts["failedTests"] > 0:
            result["classification"] = "FAILED_EXECUTED"
            result["reason"] = "The original xcresult contains the selected executed failed testcase identities."
    except (OSError, ValueError, KeyError, TypeError, AssertionError) as error:
        result["classificationError"] = {"type": type(error).__name__, "message": str(error)}
    return result


def verify_current_shipping_bundles(d, evidence, derived, command):
    inventory = json.loads(verified(d["shippingInventory"]).read_text())
    assert inventory["shippingCount"] == len(inventory["shipping"]) == 16
    products = derived / "Build/Products/Debug-iphonesimulator"
    apps = {"ai": products / "AI_Hanlin.app", "miniapps": products / "HanlinMiniApps.app"}
    rows = []
    for target in inventory["shipping"]:
        app = apps[target["owner"]]
        if target["embedded"] is None:
            path = app
        else:
            embedding = target["embedded"]
            if embedding["dstSubfolderSpec"] == "13":
                assert embedding["destinationPath"] == ""
                path = app / "PlugIns" / target["product"]
            else:
                assert embedding["dstSubfolderSpec"] == "16"
                assert embedding["destinationPath"] == "$(EXTENSIONS_FOLDER_PATH)"
                path = app / "Extensions" / target["product"]
        assert path.is_dir() and not path.is_symlink()
        info = plistlib.loads((path / "Info.plist").read_bytes())
        assert info["CFBundleIdentifier"] == target["settings"]["Debug"]["PRODUCT_BUNDLE_IDENTIFIER"]
        executable = info["CFBundleExecutable"]
        assert Path(executable).name == executable and (path / executable).is_file()
        code, _ = command(["codesign", "--verify", "--deep", "--strict", str(path)],
                          "shipping-" + target["target"] + "-signature.log", timeout=60)
        assert code == 0
        rows.append({"target": target["target"], "owner": target["owner"], "path": str(path),
                     "bundleIdentifier": info["CFBundleIdentifier"], "info": reference(path / "Info.plist"),
                     "executable": reference(path / executable),
                     "NSExtension": info.get("NSExtension"), "EXAppExtensionAttributes": info.get("EXAppExtensionAttributes"),
                     "signatureExitCode": code})
    assert len({row["bundleIdentifier"] for row in rows}) == 16
    receipt = {"schema": 1, "status": "VERIFIED_16_BUILT_SHIPPING_BUNDLES",
               "source": d["source"], "observedAt": now(), "inventory": d["shippingInventory"],
               "bundles": rows,
               "boundary": "Actual simulator bundle identities, placement, executables and ad-hoc signatures; no OS surface, distribution or physical-device verdict."}
    write_json(evidence / "current-shipping-bundles.json", receipt)
    return receipt


def make_resource_checked_command(original, assessment, evidence, derived, decision):
    """Observe/admit the next actual command; preserve its original invocation."""
    assert assessment["schema"] == 1
    assert assessment["status"] == "CURRENT_HOSTED_PHASE_ESTIMATES"
    assert assessment["root"] == str(ROOT) and assessment["derivedData"] == str(derived)
    growth = assessment["concurrentGrowthReserveBytes"]
    margin = assessment["modestOSMarginBytes"]
    monitor = assessment["monitor"]
    assert growth == margin == 1073741824
    assert monitor["intervalSeconds"] == 15 and monitor["criticalFreeBytes"] == margin
    assert assessment["buildAllocationPaths"] == ["Build/Products", "Build/Intermediates.noindex",
                                                   "ModuleCache.noindex", "Index.noindex", "Logs"]
    phases = assessment["phases"]
    mapping = assessment["phaseByLogName"]
    assert all(value in phases for value in mapping.values())
    assert derived.is_dir() and not derived.is_symlink() and derived.stat().st_uid == os.getuid()
    assert derived.resolve().is_relative_to(ROOT / "build")
    # These are ordinary owned GHA compiler-cache allocations, never prior PASS.
    # Every original current-source build executes. Live required() below keeps
    # the unchanged cumulative-ceiling / actual-allocation formula and margins.
    journal = evidence / "resource-phase-observations.jsonl"
    writer_lock = threading.Lock()
    owner_pid = os.getpid()

    def emit(value):
        value = {"observedAt": now(), "source": assessment["source"], **value}
        with writer_lock, journal.open("a") as stream:
            stream.write(json.dumps(value) + "\n")
            stream.flush(); os.fsync(stream.fileno())

    def disk(raw=False):
        stat = os.statvfs(ROOT)
        value = {"path": str(ROOT), "freeBytes": stat.f_bavail * stat.f_frsize,
                 "filesystemDevice": ROOT.stat().st_dev, "method": "statvfs.f_bavail*f_frsize"}
        if raw:
            result = subprocess.run(["/bin/df", "-k", str(ROOT)], text=True,
                                    capture_output=True, timeout=10)
            value["df"] = {"argv": result.args, "exitCode": result.returncode,
                           "stdout": result.stdout, "stderr": result.stderr}
            assert result.returncode == 0, value
        return value

    def allocation(path):
        path = Path(path)
        assert not path.is_symlink(), str(path)
        if not path.exists():
            return {"path": str(path), "exists": False, "allocatedBytes": 0}
        assert derived.resolve() in path.resolve().parents, str(path)
        result = subprocess.run(["/usr/bin/du", "-sk", str(path)], text=True,
                                capture_output=True, timeout=20)
        assert result.returncode == 0, {"path": str(path), "stderr": result.stderr}
        return {"path": str(path), "exists": True,
                "allocatedBytes": int(result.stdout.split()[0]) * 1024,
                "argv": result.args, "stdout": result.stdout}

    def required(phase):
        spec = phases[phase]
        extra = spec["additionalAllocationBytes"]
        assert type(extra) is int and extra >= 0
        model = spec["allocationModel"]
        rows = []
        if model == "static":
            amount = extra
        elif model == "remainingBuildAllocation":
            rows = [allocation(derived / relative) for relative in assessment["buildAllocationPaths"]]
            amount = max(0, spec["buildAllocationCeilingBytes"] - sum(row["allocatedBytes"] for row in rows)) + extra
        else:
            assert model in {"productInstall", "testWithProductInstall"}, model
            relative = Path(spec["productRelativePath"])
            assert relative.parts[:3] == ("Build", "Products", "Debug-iphonesimulator")
            assert relative.name in {"AI_Hanlin.app", "HanlinMiniApps.app"}
            assert spec["copyFactor"] == 2
            row = allocation(derived / relative)
            assert row["exists"] and row["allocatedBytes"] > 0
            rows = [row]
            amount = row["allocatedBytes"] * 2 + extra
        return {"phase": phase, "allocationModel": model, "allocations": rows,
                "incrementalAllocationBytes": amount, "concurrentGrowthReserveBytes": growth,
                "modestOSMarginBytes": margin, "requiredBytes": amount + growth + margin}

    def checked(*args, **kwargs):
        name = args[1] if len(args) > 1 else kwargs["name"]
        phase = mapping.get(name)
        if phase is None:
            return original(*args, **kwargs)
        need = required(phase)
        before = disk(raw=True)
        admitted = before["freeBytes"] >= need["requiredBytes"]
        emit({"kind": "before-command", "log": name, "admitted": admitted,
              "requirement": need, "observation": before})
        if not admitted:
            raise RuntimeError("RESOURCE_ADMISSION_BLOCKED: " + json.dumps({"log": name, "requirement": need, "observation": before}))
        stopped = threading.Event()
        resource_stop = []

        def watch():
            while not stopped.wait(15):
                try:
                    observed = disk()
                    critical = observed["freeBytes"] < margin
                    emit({"kind": "active-command", "log": name, "phase": phase,
                          "critical": critical, "observation": observed})
                    if not critical:
                        continue
                    detail = {"reason": "actual_free_bytes_below_modest_os_margin", "observation": observed}
                except BaseException as error:
                    detail = {"reason": "resource_observation_failed", "type": type(error).__name__, "message": str(error)}
                if stopped.is_set():
                    return
                resource_stop.append(detail)
                try:
                    write_json(evidence / "resource-stop.json",
                               {"schema": 1, "status": "RESOURCE_STOP", "source": assessment["source"],
                                "observedAt": now(), "log": name, "phase": phase,
                                "signalTargetPID": owner_pid, "signal": "SIGINT", "detail": detail})
                    emit({"kind": "resource-stop", "log": name, "phase": phase,
                          "signalTargetPID": owner_pid, "signal": "SIGINT", "detail": detail})
                finally:
                    # This exact owned Python guard is the only signal target.
                    # The unchanged original command catches BaseException and
                    # kills/waits its child; original/outer cleanup then runs.
                    if not stopped.is_set():
                        os.kill(owner_pid, signal.SIGINT)
                return

        watcher = threading.Thread(target=watch, daemon=True)
        watcher.start()
        try:
            try:
                result = original(*args, **kwargs)
            finally:
                stopped.set(); watcher.join()
                emit({"kind": "after-command", "log": name, "phase": phase,
                      "resourceStop": resource_stop, "observation": disk(raw=True)})
            if resource_stop:
                raise RuntimeError("RESOURCE_STOP: " + json.dumps(resource_stop))
            return result
        except KeyboardInterrupt as error:
            # This also covers a signal arriving while stopping/joining the
            # watcher or retaining the final snapshot. Join once more before
            # converting our resource interrupt into the runner's normal
            # Exception/failure-capture route.
            stopped.set(); watcher.join()
            if resource_stop:
                raise RuntimeError("RESOURCE_STOP: " + json.dumps(resource_stop)) from error
            raise

    return checked


def run_original_with_groups(d):
    assert os.environ["GITHUB_WORKSPACE"] == str(ROOT) and os.environ["GITHUB_SHA"] == d["source"]
    assert os.environ["PAIRED_TEST_SCOPE"] == "miniapp_complete"
    assert os.environ["SPLIT_EVIDENCE"] == d["evidenceRoot"]
    assert os.environ["SPLIT_DERIVED_DATA"] == d["derivedData"]
    assert verified(d["originalMainGuard"]) == Path(__file__).resolve()
    source = verified(d["hostedFixture"]["source"])
    assert source == ROOT / HOSTED
    handler = d["handlerRegression"]
    assert handler == {
        "id": "handler-registration", "selectors": [HANDLER_SELECTOR],
        "expectedCases": 1, "commandCeilingSeconds": 600,
        "maximumTestExecutionAllowanceSeconds": 600}
    route = d["routeContractGroup"]
    assert route["id"] == "entrypoint-contracts"
    assert route["selectors"] and all(s.startswith("AI_HLYTests/") for s in route["selectors"])
    assert len(route["selectors"]) == len(set(route["selectors"]))
    assert isinstance(route["expectedCases"], int) and route["expectedCases"] > 0
    assert route["commandCeilingSeconds"] == 2100
    assert route["maximumTestExecutionAllowanceSeconds"] == 600
    queue = d["queueContractGroup"]
    assert set(queue) == {"id", "suite", "target", "expectedFunctions", "expectedParameterInstances",
                          "commandCeilingSeconds", "source", "testPlan"}
    assert queue["id"] == "widget-host-action-queue" and queue["suite"] == QUEUE_SUITE
    assert queue["target"] == "HanlinScriptExtensionsTests"
    assert queue["expectedFunctions"] == 10 and queue["expectedParameterInstances"] == 16
    assert queue["commandCeilingSeconds"] == 1200
    assert verified(queue["source"]) == ROOT / QUEUE_SOURCE and queue["source"]["sha256"] == QUEUE_SOURCE_SHA
    plan_path = verified(queue["testPlan"])
    assert queue["testPlan"]["sha256"] == QUEUE_PLAN_SHA
    queue_plan = json.loads(plan_path.read_text())
    assert queue_plan["suite"] == QUEUE_SUITE and queue_plan["target"] == queue["target"]
    assert queue_plan["functions"] == len(queue_plan["tests"]) == 10
    assert queue_plan["parameterInstances"] == sum(row["instances"] for row in queue_plan["tests"]) == 16
    hosted = d["newHostedRegression"]
    assert hosted["id"] == "discovery-capture-hosted" and hosted["expectedCases"] == 4
    assert hosted["selectors"] == [
        "AI_HLYTests/HanlinMiniAppDiscoveryAndCaptureTests/testInstalledCatalogDoesNotDependOnWidgetInstancesAndReconcilesIdentity",
        "AI_HLYTests/HanlinMiniAppDiscoveryAndCaptureTests/testCaptureCatalogRequiresAnActualUnambiguousPreparedAction",
        "AI_HLYTests/HanlinMiniAppDiscoveryAndCaptureTests/testCapturedBytesAreDurableBeforeSessionInvalidationAndRetryKeepsIdentity",
        "AI_HLYTests/HanlinMiniAppDiscoveryAndCaptureTests/testCaptureManifestRejectsForeignProductAndUnownedPath"]
    assistant = d["assistantHostedRegression"]
    assert assistant["id"] == "assistant-hosted" and assistant["expectedCases"] == 7
    assert assistant["commandCeilingSeconds"] == 1200
    assert assistant["maximumTestExecutionAllowanceSeconds"] == 600
    assert assistant["selectors"] == ['AI_HLYTests/HanlinPreparedAssistantToolAdapterTests/testBothPreparedEnginesReturnTheAwaitedTypedBrokerValue', 'AI_HLYTests/HanlinPreparedAssistantToolAdapterTests/testUpdatedDisabledAndRemovedInstallationsDoNotDispatchOldTools', 'AI_HLYTests/HanlinPreparedAssistantToolAdapterTests/testCaseCollidingActionNamesKeepDistinctRoutesAndOriginalDispatchSpelling', 'AI_HLYTests/HanlinPreparedAssistantToolAdapterTests/testHandlerErrorsAndMalformedArgumentsRemainFailures', 'AI_HLYTests/HanlinPreparedAssistantToolAdapterTests/testUnavailableMiniAppCatalogDoesNotThrowAwayOrdinarySources', 'AI_HLYTests/HanlinUnifiedHostServicesE2ETests/installedExpoAssistantToolReturnsTheActualHermesHandlerResult()', 'AI_HLYTests/HanlinUnifiedHostServicesE2ETests/installedNativeScriptAssistantToolReturnsTheActualJavaScriptHandlerResult()']
    runner_path = ROOT / RUNNER
    assert digest(runner_path) == RUNNER_SHA
    # Preserve the original script's sibling import resolution and environment.
    sys.path.insert(0, str(runner_path.parent))
    spec = importlib.util.spec_from_file_location("original_paired_main", runner_path)
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    assessment_path = verified(d["resourceAssessment"]["authority"])
    assessment = json.loads(assessment_path.read_text())
    assert assessment["source"] == d["source"] and assessment["sourceTree"] == d["sourceTree"]
    original_command = make_resource_checked_command(runner.command, assessment, runner.EVIDENCE,
                                                     Path(d["derivedData"]), d)
    original_command = make_preboot_diagnostic_command(original_command, runner.EVIDENCE, d["source"])
    completed_build_hook = []
    regression_reviews = []

    def run_group(group, simulator, xctestrun):
        prefix = group["id"]
        result = runner.EVIDENCE / (prefix + ".xcresult")
        assert not result.exists()
        argv = ["xcodebuild", "test-without-building", "-xctestrun", str(xctestrun),
                "-destination", "platform=iOS Simulator,id=" + simulator,
                "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never",
                "-resultBundlePath", str(result), "-test-timeouts-enabled", "YES",
                "-maximum-test-execution-time-allowance", "600"]
        argv += ["-only-testing:" + selector for selector in group["selectors"]]
        review = {"schema": 1, "id": prefix, "source": d["source"],
                  "status": "RUNNING", "startedAt": now(), "argv": argv,
                  "selectors": group["selectors"], "expectedCases": group["expectedCases"],
                  "xctestrun": reference(xctestrun), "resultBundle": str(result),
                  "boundary": "Separate newly affected regression group; never counted as any original52 case."}
        review_path = runner.EVIDENCE / (prefix + "-review.json")
        write_json(review_path, review)
        try:
            code, _ = original_command(argv, prefix + "-tests.log",
                                      timeout=group["commandCeilingSeconds"], allow_failure=True)
            review["commandExitCode"] = code
            # This unchanged original verifier requires exact executed count,
            # zero failures/skips and the requested actual testcase identities.
            summary = runner.verify_native_result(result, prefix, group["selectors"],
                                                  group["expectedCases"], code)
            review["summary"] = summary
            review["status"] = "EXECUTED_PASS"
        except BaseException as error:
            review["status"] = "FAILED"
            review["error"] = {"type": type(error).__name__, "message": str(error)}
            review["executionObservation"] = observe_failed_native_execution(runner.EVIDENCE, group)
            if review["executionObservation"]["classification"] == "FAILED_EXECUTED":
                review["status"] = "FAILED_EXECUTED"
            raise
        finally:
            review["finishedAt"] = now()
            review["proofs"] = [reference(p) for p in [
                runner.EVIDENCE / (prefix + "-tests.log"),
                runner.EVIDENCE / (prefix + "-summary.json"),
                runner.EVIDENCE / (prefix + "-nodes.json"),
                runner.EVIDENCE / (prefix + "-selected-tests.log")] if p.is_file()]
            if result.is_dir():
                try:
                    code, _ = original_command(
                        ["xcrun", "xcresulttool", "export", "attachments", "--path", str(result),
                         "--output-path", str(runner.EVIDENCE / (prefix + "-attachments"))],
                        prefix + "-attachments-export.log", timeout=60, allow_failure=True)
                    review["attachmentExportExitCode"] = code
                except BaseException as error:
                    review["attachmentExportError"] = {"type": type(error).__name__, "message": str(error)}
            write_json(review_path, review)
        regression_reviews.append(review)

    def run_queue_group():
        prefix = queue["id"]
        scratch = Path(d["derivedData"]) / "swiftpm-widget-host-actions"
        assert not scratch.exists(), str(scratch)
        argv = ["xcrun", "swift", "test", "--package-path", str(ROOT / "Packages/HanlinPlatform"),
                "--scratch-path", str(scratch), "--enable-swift-testing", "--no-parallel",
                "--filter", QUEUE_SUITE]
        review_path = runner.EVIDENCE / (prefix + "-review.json")
        assert not review_path.exists()
        review = {"schema": 1, "id": prefix, "source": d["source"], "status": "RUNNING",
                  "startedAt": now(), "argv": argv, "commandCeilingSeconds": 1200,
                  "suite": QUEUE_SUITE, "target": queue["target"],
                  "expectedFunctions": 10, "expectedParameterInstances": 16,
                  "sourceFile": queue["source"], "testPlan": queue["testPlan"],
                  "currentSDK": d["currentSDK"], "scratchPath": str(scratch),
                  "boundary": "Separate original SwiftPM queue suite, after handler and renderer regressions; never counted as an AI selector or any original52 case."}
        write_json(review_path, review)
        try:
            verified(queue["source"]); verified(queue["testPlan"])
            code, _ = original_command(argv, prefix + "-tests.log", timeout=1200, allow_failure=True)
            review["commandExitCode"] = code
            assert code == 0, {"exitCode": code, "group": prefix}
            verified(queue["source"]); verified(queue["testPlan"])
            raw = (runner.EVIDENCE / (prefix + "-tests.log")).read_text()
            review["verification"] = verify_swift_testing_log(raw, queue_plan["tests"], QUEUE_TITLE)
            assert review["verification"]["observedFunctions"] == 10
            assert review["verification"]["observedParameterInstances"] == 16
            review["status"] = "EXECUTED_PASS"
        except BaseException as error:
            review["status"] = "FAILED"
            review["error"] = {"type": type(error).__name__, "message": str(error)}
            raise
        finally:
            review["finishedAt"] = now()
            log = runner.EVIDENCE / (prefix + "-tests.log")
            review["proofs"] = [reference(log)] if log.is_file() else []
            write_json(review_path, review)
        regression_reviews.append(review)

    def run_affected_swiftpm_group():
        prefix = "affected-swiftpm"
        inventory = json.loads(verified(d["affectedSwiftPM"]["inventory"]).read_text())
        assert inventory["expectedDefinitions"] == 125 and inventory["expectedCases"] == 205
        for family in inventory["families"]:
            for source_ref in [family["source"], *family.get("additionalSources", [])]:
                assert digest(ROOT / source_ref["path"]) == source_ref["sha256"]
        helper = verified(d["affectedSwiftPM"]["verifier"])
        spec = importlib.util.spec_from_file_location("current_affected_swift_verifier", helper)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        scratch = Path(d["derivedData"]) / "swiftpm-widget-host-actions"
        assert scratch.is_dir() and not scratch.is_symlink()
        events = runner.EVIDENCE / "affected-swiftpm-events.jsonl"
        assert not events.exists()
        argv = ["xcrun", "swift", "test", "--package-path", str(ROOT / "Packages/HanlinPlatform"),
                "--scratch-path", str(scratch), "--enable-swift-testing", "--no-parallel",
                "--filter", inventory["filter"], "--event-stream-output-path", str(events),
                "--event-stream-version", "0"]
        review = {"schema": 1, "id": prefix, "source": d["source"], "status": "RUNNING",
                  "startedAt": now(), "argv": argv, "expectedDefinitions": 125,
                  "expectedCases": 205, "inventory": d["affectedSwiftPM"]["inventory"],
                  "boundary": "Actual current-source affected SwiftPM families; separate from queue10/16 and original52."}
        path = runner.EVIDENCE / "affected-swiftpm-review.json"
        write_json(path, review)
        try:
            code, _ = original_command(argv, prefix + "-tests.log", timeout=1200, allow_failure=True)
            review["commandExitCode"] = code
            review["verification"] = module.verify_event_stream(events, inventory, ROOT, code)
            assert code == 0
            assert review["verification"]["status"] == "EXECUTED_PASS", review["verification"]
            review["status"] = "EXECUTED_PASS"
        except BaseException as error:
            review["status"] = "FAILED"
            review["error"] = {"type": type(error).__name__, "message": str(error)}
            raise
        finally:
            review["finishedAt"] = now()
            review["proofs"] = [reference(p) for p in [events, runner.EVIDENCE / (prefix + "-tests.log")] if p.is_file()]
            write_json(path, review)
        regression_reviews.append(review)

    def command_with_postbuild_prerequisites(*args, **kwargs):
        result = original_command(*args, **kwargs)
        log_name = args[1] if len(args) > 1 else kwargs["name"]
        if log_name in {"mini-build.log", "ai-build.log"}:
            build_argv = args[0] if args else kwargs["argv"]
            capture_compiled_metadata(d, runner.EVIDENCE, Path(d["derivedData"]), log_name, build_argv, result[0])
        if log_name == "ai-build.log":
            assert result[0] == 0 and not completed_build_hook
            build_argv = args[0] if args else kwargs["argv"]
            assert build_argv[0] == "xcodebuild"
            assert build_argv[build_argv.index("-scheme") + 1] == "AI_HLY"
            assert "build-for-testing" in build_argv
            simulator = (runner.EVIDENCE / "created-simulator.txt").read_text().strip()
            assert str(uuid.UUID(simulator)).upper() == simulator.upper()
            assert build_argv[build_argv.index("-destination") + 1] == "platform=iOS Simulator,id=" + simulator
            verify_source = verified(d["hostedFixture"]["source"])
            product = Path(d["derivedData"]) / "Build/Products/Debug-iphonesimulator/AI_Hanlin.app"
            test_bundle = product / "PlugIns/AI_HLYTests.xctest"
            candidates = [test_bundle / "Fixtures/HostServicesProbe.bundle",
                          test_bundle / "HostServicesProbe.bundle"]
            bundle = next((p for p in candidates if p.is_dir()), None)
            assert bundle is not None, "Original built HostServicesProbe resource bundle is absent"
            actual = reference(bundle / verify_source.name)
            assert actual["bytes"] == d["hostedFixture"]["source"]["bytes"]
            assert actual["sha256"] == d["hostedFixture"]["source"]["sha256"]
            proof = {"schema": 1, "status": "VERIFIED_PREREQUISITE", "source": d["source"],
                     "observedAt": now(), "originalBuildLog": log_name,
                     "originalBuildExitCode": result[0], "originalCommandUnchanged": True,
                     "sourceResource": d["hostedFixture"]["source"], "builtResource": actual,
                     "lookupOrder": [str(p) for p in candidates],
                     "boundary": "Original AI build completed; actual hosted prerequisite checked before new regressions and original main."}
            write_json(runner.EVIDENCE / "hosted-fixture-built-check.json", proof)
            completed_build_hook.append(proof)

            # The original main normally installs after this hook. Verify the
            # same original app identity/entitlements and install only the AI
            # host needed by the first real-VM test. Its later original install
            # sequence is left untouched.
            info = plistlib.loads((product / "Info.plist").read_bytes())
            assert info["CFBundleIdentifier"] == "com.itorah.chavrusachat"
            executable = info["CFBundleExecutable"]
            assert Path(executable).name == executable
            entitlements = runner.read_simulator_entitlements(product / executable)
            entitlement_source = ROOT / "AI_HLY/AI_HLY.entitlements"
            required = plistlib.loads(entitlement_source.read_bytes())["com.apple.security.application-groups"]
            observed = entitlements["entitlements"].get("com.apple.security.application-groups", [])
            assert runner.GROUP in required and set(required).issubset(observed)
            entitlements["sourceEntitlements"] = reference(entitlement_source)
            write_json(runner.EVIDENCE / "handler-regression-embedded-entitlements.json", entitlements)
            original_command(["codesign", "--verify", "--deep", "--strict", str(product)],
                             "handler-regression-signature.log")
            original_command(["xcrun", "simctl", "install", simulator, str(product)],
                             "handler-regression-install.log", timeout=300)
            xctestrun, target = xctestrun_for(Path(d["derivedData"]), "AI_HLYTests", info["CFBundleIdentifier"])
            write_json(runner.EVIDENCE / "regression-xctestrun.json",
                       {"schema": 1, "source": d["source"], "xctestrun": reference(xctestrun),
                        "targetName": "AI_HLYTests", "target": target})
            verify_current_shipping_bundles(d, runner.EVIDENCE, Path(d["derivedData"]), original_command)
            run_group(handler, simulator, xctestrun)
            run_group(route, simulator, xctestrun)
            run_queue_group()
            run_group(hosted, simulator, xctestrun)
            run_group(assistant, simulator, xctestrun)
            run_affected_swiftpm_group()
        return result

    runner.command = command_with_postbuild_prerequisites
    result = runner.main()
    if result == 0:
        assert len(completed_build_hook) == 1
        assert [v["id"] for v in regression_reviews] == ["handler-registration", "entrypoint-contracts", "widget-host-action-queue", "discovery-capture-hosted", "assistant-hosted", "affected-swiftpm"]
        assert all(v["status"] == "EXECUTED_PASS" for v in regression_reviews)
    return result
