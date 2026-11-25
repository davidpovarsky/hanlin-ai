#!/usr/bin/env python3
"""Build original Hanlin tests on real Mac at exact850 source. This controller exposes only the build phase; runtime12 and retained compiler18 require separate verification."""
import argparse, collections, datetime, hashlib, json, os, pathlib, re, shutil
import signal, stat, struct, subprocess, sys, time, traceback
import xml.etree.ElementTree as ET

SOURCE = "850de66432fc872d349469a2a63aaa564c61f0a8"
MANIFEST_SHA = "0941b55c21421212c6e5c3da82af6cdb7b8befe231a93c64ef51e7715a47e204"
BASE = pathlib.Path("/Users/m1/builds/hanlin-zip-23040c6c-native-20261125")
ROOT = BASE / "source"
SCRATCH = BASE / "package-resolution-shared"
FILTER = r"HanlinPackageCenterTests|HanlinArchivePolicyTests|HanlinDualWidgetEnginesTests.*(realArchiveImport|installAndVerifiedLoader)"
EXPECTED = {
    "HanlinPackageCenterTests": ["exporterImporterContract", "validPackage", "nativeScriptPackageWithMJS",
                                "fileProviderPathWithSpaces", "unicodeSourcePath", "malformedManifest"],
    "HanlinArchivePolicyTests": ["wrappedPackage", "nativeScriptMJSBundle", "rejectsEscapingPaths",
                                "hostileEntries", "ambiguousManifest", "autonomousSkillResources",
                                "autonomousSkillIntegrity", "ordinaryPackageCapacity", "retainedSourcesAndAssets"],
    "HanlinDualWidgetEnginesTests": ["realArchiveImport", "installAndVerifiedLoader"],
}

class ResourceBlocked(Exception):
    pass

def require(value, message):
    if not value:
        raise RuntimeError(message)

def sha(data):
    return hashlib.sha256(data).hexdigest()

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def file_bytes(path):
    return os.readlink(path).encode() if path.is_symlink() else path.read_bytes()

def inputs():
    manifest_path = ROOT / "SOURCE_MANIFEST-850de664-v3.json"
    raw = manifest_path.read_bytes()
    require(sha(raw) == MANIFEST_SHA, "Exact committed input manifest differs")
    manifest = json.loads(raw)
    require(manifest["source"] == SOURCE and len(manifest["files"]) == 1305, "Wrong original source closure")
    actual = {}
    for row in manifest["files"]:
        path = ROOT / row["path"]
        data = file_bytes(path)
        require(len(data) == row["bytes"] and sha(data) == row["sha256"], "Input changed: " + row["path"])
        blob = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        require(blob == row["git_blob"], "Committed Git blob differs: " + row["path"])
        require(path.is_symlink() == (row["mode"] == "120000"), "Input mode differs: " + row["path"])
        if not path.is_symlink():
            require(bool(path.stat().st_mode & stat.S_IXUSR) == (row["mode"] == "100755"),
                    "Executable mode differs: " + row["path"])
        actual[row["path"]] = sha(data)
    return manifest, actual

def selection():
    result = []
    declaration = re.compile(r"@Test(?:\((?P<attributes>.*?)\))?\s*(?:@MainActor\s*)?func\s+(?P<name>\w+)\s*\((?P<parameters>[^)]*)\)", re.S)
    for suite, methods in EXPECTED.items():
        paths = list((ROOT / "Packages/HanlinPlatform/Tests").rglob(suite + ".swift"))
        require(len(paths) == 1, "Ambiguous original test source")
        path = paths[0]
        source = path.read_text()
        found = [m for m in declaration.finditer(source) if m["name"] in methods]
        require(collections.Counter(m["name"] for m in found) == collections.Counter(methods),
                "Original selected methods differ: " + suite)
        if suite != "HanlinDualWidgetEnginesTests":
            require(len(list(declaration.finditer(source))) == len(methods), "Unreviewed original suite declaration")
        for match in found:
            attributes = (match["attributes"] or "").strip()
            parameters = re.findall(r"(\w+)\s*:", match["parameters"])
            signature = match["name"] + "(" + "".join(x + ":" for x in parameters) + ")"
            arguments = None
            if "arguments:" in attributes:
                array = re.search(r"arguments\s*:\s*(\[[\s\S]*\])", attributes)
                require(array is not None, "Unknown original argument declaration")
                arguments = json.loads(array.group(1))
                require(len(parameters) == 1 and all(isinstance(x, str) for x in arguments),
                        "Unknown original parameter shape")
            display = signature
            if attributes.startswith('"'):
                display = json.JSONDecoder().raw_decode(attributes)[0]
            result.append({"suite": suite, "module": path.parent.name, "method": match["name"],
                           "signature": signature, "display": display, "parameters": parameters,
                           "arguments": arguments, "file": str(path.relative_to(ROOT)), "source_sha256": sha(path.read_bytes())})
    require(len(result) == 17 and sum(len(x["arguments"]) if x["arguments"] else 1 for x in result) == 30,
            "Original seventeen-method/thirty-invocation inventory differs")
    expected_arguments = {
        "rejectsEscapingPaths": ["../script.json", "/script.json", "C:/script.json", "folder/../../script.json"],
        "realArchiveImport": ["Hanlin-Expo-Widget-Counter.hanlinExpo", "Hanlin-Expo-Widget-Visuals.hanlinExpo",
                              "Hanlin-ScriptWidget-Dashboard.scripting", "Hanlin-ScriptWidget-Actions.scripting",
                              "Hanlin-Widget-Legacy-Regression.scripting", "Hanlin-Mixed-Native-Widget.hanlinExpo",
                              "Hanlin-Widget-Invalid-Cases.hanlinExpo"],
        "installAndVerifiedLoader": ["Hanlin-Expo-Widget-Counter.hanlinExpo", "Hanlin-Expo-Widget-Visuals.hanlinExpo",
                                     "Hanlin-ScriptWidget-Dashboard.scripting", "Hanlin-ScriptWidget-Actions.scripting",
                                     "Hanlin-Widget-Legacy-Regression.scripting"],
    }
    for row in result:
        require(row["arguments"] == expected_arguments.get(row["method"]), "Exact original arguments differ")
    return result

def owned_kib():
    return int(subprocess.check_output(["du", "-sk", str(SCRATCH)], text=True).split()[0])


def dependency_identity():
    path = BASE / "evidence/resolution-attempt01/RESULT.json"
    raw = path.read_bytes()
    require(sha(raw) == "76e7e6ae1ca9a89d85a1ee64539ad2b7f2d8860857e9f470c117476f950c834c",
            "Original resolver receipt differs")
    rows = json.loads(raw)["actual_checkouts"]
    for row in rows:
        actual = subprocess.check_output(["git", "-C", row["path"], "rev-parse", "HEAD"], text=True).strip()
        status = subprocess.check_output(["git", "-C", row["path"], "status", "--porcelain=v1", "--untracked-files=no"], text=True)
        require(actual == row["head"] and not status, "Original dependency checkout changed")
    return rows

def binaries():
    paths = sorted({p.resolve() for p in SCRATCH.glob("**/*.xctest/Contents/MacOS/*") if p.is_file()})
    require(paths, "Original test product is absent")
    return [{"path": str(p), "bytes": p.stat().st_size, "sha256": sha(p.read_bytes())} for p in paths]

def verify_runtime(evidence, inventory):
    expected = {(x["module"] + "." + x["suite"], x["signature"]) for x in inventory}
    observed = []
    xml_files = sorted(evidence.glob("archive*.xml"))
    require(xml_files, "No original XML result")
    for path in xml_files:
        tree = ET.fromstring(path.read_bytes())
        for suite in tree.iter("testsuite"):
            for key in ("errors", "failures", "skipped"):
                require(int(suite.get(key, "0")) == 0, "Original XML reported " + key)
        for case in tree.iter("testcase"):
            require(not any(list(case.iter(tag)) for tag in ("failure", "error", "skipped")),
                    "Original case failed or skipped")
            observed.append((case.get("classname"), case.get("name")))
    require(len(observed) == 17 and len(set(observed)) == 17 and set(observed) == expected,
            "Missing, extra, duplicate or mismatched original test method")

    log = re.sub(r"\x1b\[[0-9;]*m", "", (evidence / "run.log").read_text())
    lines = log.splitlines()
    require(not re.search(r"recorded an issue|[✘✗] Test|Test run with .* failed", log),
            "Original Swift Testing log contains a failure")
    require(len(re.findall(r"Test run with 17 tests in 3 suites passed after ", log)) == 1,
            "Original final test-run summary is absent or ambiguous")
    parameter_rows = []
    for line in lines:
        if "Test case passing " not in line:
            continue
        match = re.search(r"Test case passing 1 argument (\w+) → (.+) to (.+) started\.$", line)
        require(match is not None, "Unknown parameter execution record: " + line)
        value, end = json.JSONDecoder().raw_decode(match.group(2))
        require(end == len(match.group(2)) and isinstance(value, str), "Unknown actual argument value")
        label = match.group(3)
        if label.startswith('"'):
            label = json.loads(label)
        parameter_rows.append((match.group(1), value, label))
    expected_parameters = []
    invocations = []
    for row in inventory:
        label = "(?:" + re.escape(row["display"]) + "|" + re.escape(json.dumps(row["display"], ensure_ascii=False)) + ")"
        suffix = " with " + str(len(row["arguments"])) + " test cases" if row["arguments"] else ""
        matches = [x for x in lines if re.search(r"Test " + label + re.escape(suffix) + r" passed after ", x)]
        require(len(matches) == 1, "Missing/duplicate original passed summary: " + row["signature"])
        if row["arguments"]:
            for argument in row["arguments"]:
                expected_parameters.append((row["parameters"][0], argument, row["display"]))
                invocations.append({"class": row["module"] + "." + row["suite"], "method": row["signature"],
                                    "argument": argument, "status": "Passed"})
        else:
            invocations.append({"class": row["module"] + "." + row["suite"], "method": row["signature"], "status": "Passed"})
    require(collections.Counter(parameter_rows) == collections.Counter(expected_parameters)
            and len(parameter_rows) == 16, "Missing/extra/repeated original parameter invocation")
    require(len(invocations) == 30, "Wrong actual invocation count")

    widgets = evidence / "widgets"
    widget_rows = []
    arguments = {x["method"]: x["arguments"] for x in inventory if x["arguments"]}
    for method, prefix in (("realArchiveImport", "analysis-"), ("installAndVerifiedLoader", "installed-")):
        for name in arguments[method]:
            path = widgets / (prefix + name + ".json")
            data = json.loads(path.read_bytes())
            fixture = ROOT / "Fixtures/Widgets" / name
            require(data["archive"] == name and data["archiveSHA256"] == sha(fixture.read_bytes()),
                    "Actual widget receipt is bound to another archive")
            if prefix == "analysis-":
                require(data["canInstall"] is (("Mixed" not in name) and ("Invalid" not in name)),
                        "Actual original archive admission result differs")
            else:
                require(data["familyPrepared"] == "systemMedium" and data["entityID"] and isinstance(data["installedWidget"], dict),
                        "Incomplete original installation receipt")
                if "Legacy" not in name:
                    for key in ("sourceSHA256", "compilerSHA256", "compiledJavaScriptSHA256"):
                        require(re.fullmatch(r"[0-9a-f]{64}", data[key]) is not None, "Missing original program digest")
                if "Expo" not in name:
                    png = widgets / ("installed-" + name + "-native.png")
                    raw = png.read_bytes()
                    require(raw[:8] == b"\x89PNG\r\n\x1a\n" and raw[12:16] == b"IHDR"
                            and struct.unpack(">II", raw[16:24]) == (360, 320),
                            "Original native raster is absent or malformed")
            widget_rows.append({"path": str(path.relative_to(evidence)), "sha256": sha(path.read_bytes())})
    return {"methods": 17, "invocations": invocations, "parameter_invocations": len(parameter_rows),
            "xml_results": [{"path": x.name, "sha256": sha(x.read_bytes())} for x in xml_files],
            "original_widget_receipts": widget_rows, "ordinary_app_ui_credit": False,
            "springboard_credit": False, "maktabah_live_credit": False}

def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--phase", choices=["build"], required=True)
    parser.add_argument("--attempt", required=True)
    parser.add_argument("--reserve-bytes", type=int, required=True)
    parser.add_argument("--own-peak-bytes", type=int, required=True)
    parser.add_argument("--build-receipt")
    args = parser.parse_args()
    require(sys.platform == "darwin", "Actual Apple execution is required")
    require(re.fullmatch(r"[a-zA-Z0-9_-]+", args.attempt) is not None, "Invalid attempt identity")
    require(args.reserve_bytes >= 2 * 1024**3 and 0 < args.own_peak_bytes <= 2 * 1024**3,
            "Invalid resource admission")
    evidence = BASE / "evidence" / ("archive-" + args.phase + "-" + args.attempt)
    require(not evidence.exists(), "Preserve the original attempt")
    evidence.mkdir()
    report = {"status": "NOT_RUN", "source_sha": SOURCE, "manifest_sha256": MANIFEST_SHA, "started_at": now(),
              "phase": args.phase, "resource_plan": {"other_remaining_and_os_bytes": args.reserve_bytes,
                    "own_remaining_peak_bytes": args.own_peak_bytes}, "commands": [], "tests_executed": 0}
    def write():
        (evidence / "RESULT.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    before = {}
    try:
        manifest, before = inputs()
        inventory = selection()
        (evidence / "SOURCE_MANIFEST.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        (evidence / "SOURCE_SELECTION.json").write_text(json.dumps(inventory, indent=2, sort_keys=True) + "\n")
        report["source_before"] = before
        report["dependency_checkouts"] = dependency_identity()
        report["swift"] = subprocess.check_output(["swift", "--version"], text=True).strip()
        report["xcode"] = subprocess.check_output(["xcodebuild", "-version"], text=True).strip()
        require(report["xcode"].startswith("Xcode 27.0\n"), "Unexpected selected Xcode")
        report["resource_plan"]["free_before"] = shutil.disk_usage(BASE).free
        report["resource_plan"]["scratch_kib_before"] = owned_kib()
        required = args.reserve_bytes + args.own_peak_bytes
        report["resource_plan"]["required_free_bytes"] = required
        write()
        if shutil.disk_usage(BASE).free < required:
            report["status"] = "BLOCKED_BEFORE_EXECUTION"
            raise ResourceBlocked()
        common = ["--package-path", str(ROOT / "Packages/HanlinPlatform"), "--scratch-path", str(SCRATCH),
                  "--jobs", "1", "--force-resolved-versions"]
        if args.phase == "build":
            command = ["swift", "build", *common, "--build-tests"]
        else:
            require(args.build_receipt is not None, "Exact accepted build receipt required")
            build_path = pathlib.Path(args.build_receipt).resolve()
            require(build_path.is_relative_to(BASE / "evidence"), "Build receipt is outside owned evidence")
            build_raw = build_path.read_bytes()
            build = json.loads(build_raw)
            require(build["status"] == "ORIGINAL_BUILD_COMPLETE_PENDING_TESTS" and build["source_sha"] == SOURCE
                    and build["manifest_sha256"] == MANIFEST_SHA and build["source_after"] == before,
                    "The original build is not bound to this source")
            require(binaries() == build["actual_test_binaries"], "Original built test products changed")
            report["build_receipt_sha256"] = sha(build_raw)
            report["build_receipt_path"] = str(build_path)
            command = ["swift", "test", *common, "--skip-build", "--filter", FILTER,
                       "--xunit-output", str(evidence / "archive.xml")]
        env = os.environ.copy()
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["HANLIN_WIDGET_EVIDENCE_DIR"] = str(evidence / "widgets")
        (evidence / "widgets").mkdir()
        timeout = 1800 if args.phase == "build" else 300
        logpath = evidence / (args.phase + ".log")
        start = time.monotonic()
        with logpath.open("wb") as log:
            proc = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            row = {"command": command, "pid": proc.pid, "started_at": now()}
            report["commands"].append(row)
            report["status"] = "RUNNING"
            write()
            last_size = start
            while True:
                try:
                    rc = proc.wait(timeout=3)
                    break
                except subprocess.TimeoutExpired:
                    remaining_danger = shutil.disk_usage(BASE).free < args.reserve_bytes
                    expired = time.monotonic() - start > timeout
                    own_exceeded = False
                    if time.monotonic() - last_size >= 15:
                        scratch_growth = max(0, owned_kib() - report["resource_plan"]["scratch_kib_before"]) * 1024
                        report["resource_plan"]["last_scratch_growth_bytes"] = scratch_growth
                        own_exceeded = scratch_growth > args.own_peak_bytes
                        last_size = time.monotonic()
                    if not remaining_danger and not expired and not own_exceeded:
                        continue
                    row["owned_stop_reason"] = ("other_remaining_growth_budget" if remaining_danger else
                                                "owned_incremental_peak" if own_exceeded else "owned_timeout")
                    os.killpg(proc.pid, signal.SIGTERM)
                    try:
                        proc.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        os.killpg(proc.pid, signal.SIGKILL)
                        proc.wait()
                    rc = 124 if expired else 125
                    break
        row.update(exit_code=rc, seconds=round(time.monotonic() - start, 3), log_sha256=sha(logpath.read_bytes()),
                   free_after=shutil.disk_usage(BASE).free)
        write()
        require(rc == 0, "Original " + args.phase + " exited " + str(rc))
        if args.phase == "build":
            report["actual_test_binaries"] = binaries()
            report["status"] = "ORIGINAL_BUILD_COMPLETE_PENDING_TESTS"
        else:
            report["runtime"] = verify_runtime(evidence, inventory)
            report["tests_executed"] = 30
            report["status"] = "ORIGINAL_ARCHIVE_REGRESSION_30_PASS"
    except ResourceBlocked:
        pass
    except Exception as error:
        report.update(status="FAILED", error=repr(error))
        (evidence / "failure.txt").write_text(traceback.format_exc())
    finally:
        try:
            _, after = inputs()
            report["source_after"] = after
            report["source_unchanged"] = before == after
            if before and before != after:
                report["status"] = "FAILED_SOURCE_MUTATION"
            report["actual_scratch_kib"] = owned_kib()
            require(dependency_identity() == report.get("dependency_checkouts"), "Dependency identity changed after execution")
        except Exception as error:
            report["source_verification_error"] = repr(error)
            report["status"] = "FAILED_SOURCE_MUTATION"
        report.update(finished_at=now(), free_after=shutil.disk_usage(BASE).free)
        write()
        print(json.dumps({k:v for k,v in report.items() if k not in ("source_before", "source_after", "runtime")}, sort_keys=True))

    return 0 if report["status"] in ("ORIGINAL_BUILD_COMPLETE_PENDING_TESTS", "ORIGINAL_ARCHIVE_REGRESSION_30_PASS") else 125 if report["status"] == "BLOCKED_BEFORE_EXECUTION" else 1

if __name__ == "__main__":
    sys.exit(main())
