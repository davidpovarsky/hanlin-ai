#!/usr/bin/env python3
"""Read actual loaded images at the original MiniApps runtime UI checkpoints.

This companion is called only by production_runtimes_with_origin. It never
launches a substitute app or writes product data. The original runner still
owns its build, exact25 XCTest selection, simulator, deadline and result gates.
Only the UI runner's nonce-bound request/response directory is writable here.
"""
from __future__ import annotations

import copy
import datetime as dt
import hashlib
import json
import math
import os
from pathlib import Path
import plistlib
import re
import signal
import struct
import subprocess
import time
import uuid


APP_ID = "com.itorah.hanlinminiapps"
RUNNER_ID = "com.itorah.hanlinminiapps.integration.uitests.xctrunner"
UI_TARGET = "HanlinMiniAppsUITests"
EXCHANGE = "HanlinRuntimeImageOrigin"
ATTEMPT_ENV = "HANLIN_RUNTIME_IMAGE_ORIGIN_ATTEMPT"
SOURCE_ENV = "HANLIN_RUNTIME_IMAGE_ORIGIN_SOURCE"
CHECKPOINTS = {
    "nativescript": "testStandaloneNativeScriptUsesRealRuntimesAndSurvivesRelaunch",
    "expo": "testStandaloneExpoRendersNativeControlsAndRunsReactEvents",
}
REQUIRED_IMAGES = {
    # The original checkpoint has already executed these embedded runtimes in
    # this app process, so their loaded producer images are all mandatory.
    "nativescript": ("Frameworks/NativeScript.framework/NativeScript",
                     "Frameworks/NodeMobile.framework/NodeMobile", "Frameworks/Python.framework/Python"),
    "expo": ("Frameworks/React.framework/React", "Frameworks/hermesvm.framework/hermesvm"),
}
MAGICS = {b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe",
          b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}


def require(condition, message):
    if not condition:
        raise RuntimeError("Runtime image origin: " + message)


def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def record(path):
    path = Path(path)
    return {"bytes": path.stat().st_size, "sha256": digest(path)}


def write_json(path, value):
    path = Path(path)
    temporary = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
    temporary.write_text(json.dumps(value, sort_keys=True, indent=2, allow_nan=False) + "\n")
    temporary.replace(path)


def contained(path, root, *, exists=True):
    root = Path(root).resolve(strict=True)
    path = Path(path).resolve(strict=exists)
    require(path.is_relative_to(root) and path != root, "path escaped its admitted owner")
    return path


def canonical_uuid(value):
    require(type(value) is str, "UUID is not text")
    try:
        parsed = str(uuid.UUID(value))
    except ValueError as error:
        raise RuntimeError("Runtime image origin: malformed UUID") from error
    require(value == parsed, "UUID is not canonical lowercase text")
    return value


def macho_uuids(path):
    """Read LC_UUID from the real bounded Mach-O slices, without loading code."""
    path = Path(path)
    size = path.stat().st_size
    result = {}
    with path.open("rb") as stream:
        def read(offset, length):
            require(0 <= offset <= size and 0 <= length <= size - offset, "truncated Mach-O")
            stream.seek(offset)
            value = stream.read(length)
            require(len(value) == length, "Mach-O changed during reading")
            return value

        def thin(offset, length):
            magic = read(offset, 4)
            require(magic in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"), "unsupported product Mach-O slice")
            endian = "<" if magic == b"\xcf\xfa\xed\xfe" else ">"
            header = struct.unpack(endian + "8I", read(offset, 32))
            cpu, subtype, count, command_bytes = header[1], header[2] & 0xFFFFFF, header[4], header[5]
            architecture = {0x0100000C: "arm64e" if subtype == 2 else "arm64",
                            0x01000007: "x86_64h" if subtype == 8 else "x86_64"}.get(cpu)
            require(architecture is not None and 0 < count <= 65536
                    and 32 <= length and command_bytes <= length - 32, "invalid Mach-O header")
            end = offset + 32 + command_bytes
            cursor = offset + 32
            identifiers = []
            for _ in range(count):
                require(cursor + 8 <= end, "truncated Mach-O command header")
                command, command_size = struct.unpack(endian + "2I", read(cursor, 8))
                require(command_size >= 8 and command_size % 4 == 0 and cursor + command_size <= end,
                        "invalid Mach-O command length")
                if command == 0x1B:  # LC_UUID
                    require(command_size == 24, "invalid LC_UUID length")
                    identifiers.append(str(uuid.UUID(bytes=read(cursor + 8, 16))))
                cursor += command_size
            require(cursor == end and len(identifiers) == 1 and architecture not in result,
                    "missing, repeated or ambiguous product image UUID")
            result[architecture] = identifiers[0]

        magic = read(0, 4)
        if magic in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"):
            thin(0, size)
        else:
            require(magic in MAGICS, "product is not a supported Mach-O")
            endian = ">" if magic in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf") else "<"
            wide = magic in (b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca")
            count = struct.unpack(endian + "I", read(4, 4))[0]
            require(0 < count <= 64, "invalid universal image slice count")
            item_size = 32 if wide else 20
            minimum = 8 + count * item_size
            ranges = []
            for index in range(count):
                fields = struct.unpack(endian + ("IIQQII" if wide else "IIIII"),
                                       read(8 + index * item_size, item_size))
                offset, length = fields[2], fields[3]
                require(offset >= minimum and length >= 32 and offset + length <= size
                        and all(offset + length <= lo or offset >= hi for lo, hi in ranges),
                        "invalid or overlapping universal image slice")
                ranges.append((offset, offset + length))
                thin(offset, length)
    return result


def parse_sample(text):
    require(type(text) is str and "\nBinary Images:\n" in text, "sample omitted its actual Binary Images section")
    header_text, images_text = text.split("\nBinary Images:\n", 1)
    fields = {}
    for label in ("Process", "Path", "Code Type", "Platform", "Date/Time", "Launch Time"):
        values = re.findall(r"^" + re.escape(label) + r":\s+(.+)$", header_text, re.MULTILINE)
        require(len(values) == 1, "missing or ambiguous sample header: " + label)
        fields[label] = values[0].strip()
    process = re.fullmatch(r".+ \[([0-9]+)\]", fields["Process"])
    require(process is not None, "sample process header has no actual PID")
    fields["pid"] = int(process[1])
    for label in ("Date/Time", "Launch Time"):
        try:
            fields[label + "Epoch"] = dt.datetime.strptime(fields[label], "%Y-%m-%d %H:%M:%S.%f %z").timestamp()
        except ValueError as error:
            raise RuntimeError("Runtime image origin: unsupported actual sample clock format") from error
    images = []
    for line in images_text.splitlines():
        if not line.strip():
            continue
        match = re.fullmatch(r"\s*(0x[0-9a-fA-F]+)\s+-\s+(0x[0-9a-fA-F]+)\s+(.+?)\s+"
                             r"<([0-9a-fA-F-]{36})>\s+(/.+)", line)
        require(match is not None, "an actual loaded-image row is incomplete or unsupported")
        start, end = int(match[1], 16), int(match[2], 16)
        require(start <= end, "reversed loaded-image address range")
        image_uuid = str(uuid.UUID(match[4]))
        images.append({"start": start, "end": end, "label": match[3],
                       "uuid": image_uuid, "path": match[5]})
    require(images and len({(row["start"], row["end"]) for row in images}) == len(images),
            "empty or repeated loaded-image records")
    return {"header": fields, "images": images}


def validate_request(request, *, attempt, source, checkpoint, started, now, modified):
    keys = {"schema", "attempt", "source", "checkpoint", "requestID", "pid", "runnerPID",
            "bundleID", "caseName", "at", "accessibilityHeader"}
    require(type(request) is dict and set(request) == keys and type(request["schema"]) is int
            and request["schema"] == 1, "invalid UI request schema")
    require(canonical_uuid(request["attempt"]) == attempt and request["source"] == source
            and request["checkpoint"] == checkpoint and checkpoint in CHECKPOINTS
            and request["bundleID"] == APP_ID, "UI request belongs to another attempt/product/checkpoint")
    canonical_uuid(request["requestID"])
    require(all(type(request[key]) is int and request[key] > 1 for key in ("pid", "runnerPID"))
            and request["pid"] != request["runnerPID"], "invalid actual process identity")
    require(type(request["at"]) in (int, float) and math.isfinite(request["at"])
            and started <= request["at"] <= now and started <= modified <= now,
            "stale, future or nonfinite UI checkpoint")
    method = CHECKPOINTS[checkpoint]
    require(type(request["caseName"]) is str and re.search(
        r"(?:[ /])" + re.escape(method) + r"(?:\]|\(\))?$", request["caseName"]) is not None,
        "checkpoint is not the original selected runtime case")
    require(type(request["accessibilityHeader"]) is str and re.match(
        r"^Attributes: Application, .*?, pid: " + str(request["pid"]) + r",", request["accessibilityHeader"]),
        "public accessibility PID and request disagree")
    return request


def parse_process(text, expected_pid):
    match = re.fullmatch(r"\s*([0-9]+)\s+([0-9]+)\s+"
                        r"([A-Za-z]{3}\s+[A-Za-z]{3}\s+[0-9]{1,2}\s+[0-9:]{8}\s+[0-9]{4})\s+(/[^\n]+)\s*", text)
    require(match is not None and int(match[1]) == expected_pid, "OS process snapshot does not identify the requested PID")
    launched = dt.datetime.strptime(re.sub(r"\s+", " ", match[3]), "%a %b %d %H:%M:%S %Y")
    return {"pid": int(match[1]), "parentPID": int(match[2]),
            "launchEpoch": launched.replace(tzinfo=dt.timezone.utc).timestamp(), "path": match[4]}


def validate_sample_identity(sample, before, after, *, executable, started, request_at, sample_started, sample_finished):
    header = sample["header"]
    expected = str(Path(executable).resolve(strict=True))
    require(before == after and before["pid"] == header["pid"], "sample crossed process exit/replacement")
    require(str(Path(before["path"]).resolve(strict=True)) == expected
            and str(Path(header["Path"]).resolve(strict=True)) == expected,
            "sample or OS PID belongs to another installed executable")
    require(math.floor(started) <= before["launchEpoch"] <= sample_started
            and math.floor(header["Launch TimeEpoch"]) == before["launchEpoch"]
            and started - 0.001 <= header["Launch TimeEpoch"] <= request_at,
            "process was not launched in this actual native attempt")
    require(sample_started - 0.001 <= header["Date/TimeEpoch"] <= sample_finished,
            "sample clock is outside the actual command window")
    require(header["Platform"] in ("iOS", "iOS Simulator", "iPadOS", "iPadOS Simulator"),
            "a macOS/foreign-process sample cannot qualify simulator app origin")


def classify_images(sample, *, app, products, device_root, catalog, architecture, executable,
                    checkpoint, platform_roots):
    app, products, device_root = (Path(value).resolve(strict=True) for value in (app, products, device_root))
    known_names = {Path(name).name for name in catalog}
    known_uuids = {value for row in catalog.values() for value in row["uuids"].values()}
    bound, other = [], []
    seen = set()
    for row in sample["images"]:
        path = Path(row["path"]).resolve()
        if path.is_relative_to(app):
            relative = path.relative_to(app).as_posix()
            require(relative in catalog and relative not in seen and path.is_file(),
                    "unknown, repeated or missing installed product image")
            expected = catalog[relative]
            require(record(path) == expected["file"] and macho_uuids(path) == expected["uuids"],
                    "installed loaded image differs from original producer bytes")
            require(expected["uuids"].get(architecture) == row["uuid"],
                    "actual loaded UUID differs from the selected original product slice")
            seen.add(relative)
            bound.append({**row, "relativePath": relative, "file": expected["file"], "architecture": architecture})
        else:
            require(path.name not in known_names and row["uuid"] not in known_uuids,
                    "a product image was loaded from outside its current installed app")
            require(not path.is_relative_to(products) and not path.is_relative_to(device_root),
                    "a loaded image escaped to another build/product/container")
            require(any(path.is_relative_to(Path(root).resolve()) for root in platform_roots),
                    "unqualified non-product loaded-image origin: " + row["path"])
            other.append({**row, "qualification": "RECORDED_PLATFORM_TOOLCHAIN_IMAGE_NOT_PRODUCT_SOURCE_PROOF"})
    require(executable in seen and set(REQUIRED_IMAGES[checkpoint]).issubset(seen),
            "sample omitted the actual executable or selected original engine images")
    return {"productImages": bound, "platformToolchainImages": other}


def descriptor_target(document):
    version = document.get("__xctestrun_metadata__", {}).get("FormatVersion", 1)
    require(type(version) is int and version in (1, 2), "unsupported original xctestrun format")
    if version == 1:
        require("TestConfigurations" not in document, "conflicting descriptor versions")
        targets = [document[UI_TARGET]] if UI_TARGET in document else []
    else:
        targets = []
        configurations = document.get("TestConfigurations")
        require(type(configurations) is list, "missing test configurations")
        for configuration in configurations:
            require(type(configuration) is dict and type(configuration.get("IsEnabled", True)) is bool,
                    "invalid test configuration enablement")
            if configuration.get("IsEnabled", True):
                rows = configuration.get("TestTargets")
                require(type(rows) is list and all(type(row) is dict for row in rows), "invalid test targets")
                targets.extend(row for row in rows if row.get("BlueprintName") == UI_TARGET)
    require(len(targets) == 1 and type(targets[0]) is dict, "missing or ambiguous original UI target")
    target = targets[0]
    require(target.get("IsUITestBundle") is True and target.get("IsEnabled", True) is True
            and not target.get("UseDestinationArtifacts"), "original local UI target is not enabled")
    return target


def descriptor_path(value, products, host=None):
    require(type(value) is str and value, "missing original test product path")
    value = value.replace("__TESTROOT__", str(products))
    if host is not None:
        value = value.replace("__TESTHOST__", str(host))
    require(not re.search(r"__[A-Z_]+__", value) and Path(value).is_absolute(), "unresolved original test product path")
    result = contained(value, products)
    require(result.is_dir(), "original test product is not a directory")
    return result


def origin_descriptor(document, attempt, source):
    canonical_uuid(attempt)
    require(re.fullmatch(r"[0-9a-f]{40}", source), "invalid admitted source commit")
    updated = copy.deepcopy(document)
    target = descriptor_target(updated)
    environment = target.setdefault("EnvironmentVariables", {})
    require(type(environment) is dict and ATTEMPT_ENV not in environment and SOURCE_ENV not in environment,
            "descriptor already carries an origin attempt")
    environment.update({ATTEMPT_ENV: attempt, SOURCE_ENV: source})
    inverse = copy.deepcopy(updated)
    inverse_target = descriptor_target(inverse)
    del inverse_target["EnvironmentVariables"][ATTEMPT_ENV]
    del inverse_target["EnvironmentVariables"][SOURCE_ENV]
    if "EnvironmentVariables" not in descriptor_target(document):
        del inverse_target["EnvironmentVariables"]
    require(inverse == document, "origin environment changed an original descriptor setting")
    return updated


class OriginObserver:
    def __init__(self, root, evidence, derived, state, inputs):
        self.root, self.evidence, self.derived = map(Path, (root, evidence, derived))
        self.state, self.inputs = state, inputs
        self.output = self.evidence / "runtime-image-origin"
        require(not self.output.exists(), "origin evidence must be a fresh original attempt")
        self.output.mkdir()
        self.attempt = str(uuid.uuid4())
        self.source = state["sha"]
        self.device = state["simulator"]
        require(str(uuid.UUID(self.device)).upper() == self.device
                and (self.evidence / "created-simulator.txt").read_text().strip() == self.device,
                "simulator is not the original runner's created device")
        self.device_root = (Path.home() / "Library/Developer/CoreSimulator/Devices" / self.device).resolve(strict=True)
        self.products = (self.derived / "Build/Products").resolve(strict=True)
        self.app = self.products / "Debug-iphonesimulator/HanlinMiniApps.app"
        self.runner = self.products / "Debug-iphonesimulator/HanlinMiniAppsUITests-Runner.app"
        self.test = self.runner / "PlugIns/HanlinMiniAppsUITests.xctest"
        self.operation = 0
        self.observations = {}
        self.errors = []
        self.attempted = set()
        self.started = None
        self.deadline = None
        self.last_roots = None
        self.manifest_path = self.evidence / "consumer-build/producer-manifest.json"
        self.manifest_bytes = self.manifest_path.read_bytes()
        manifest = json.loads(self.manifest_bytes)
        require(manifest["producer_sha"] == self.source and manifest["bundle_id"] == APP_ID
                and manifest["build_status"] == "EXECUTED_PASS" and state.get("build") == "EXECUTED_PASS"
                and manifest["architecture"] == state["architecture"]
                and state.get("consumer_build_export") == "EXECUTED_PASS_BUILD_ONLY_NATIVE_ACCEPTANCE_RUNNING"
                and manifest["source_identity"]["commit"] == self.source
                and manifest["source_identity"]["tracked_file_sha256"] == inputs
                and manifest["codesign_verification"]["status"] == "EXECUTED_PASS",
                "original frozen producer binding is missing")
        self.architecture = state["architecture"]
        self.executable = manifest["executable_name"]
        require(Path(self.executable).name == self.executable, "invalid original executable name")
        self.catalog = {}
        for relative, entry in manifest["app_files"].items():
            require(type(relative) is str and not Path(relative).is_absolute() and ".." not in Path(relative).parts,
                    "invalid original app inventory path")
            if entry.get("kind") != "file":
                continue
            path = contained(self.app / relative, self.app)
            with path.open("rb") as stream:
                magic = stream.read(4)
            if magic in MAGICS:
                file = record(path)
                require(file == {"bytes": entry["bytes"], "sha256": entry["sha256"]}, "original built image changed")
                self.catalog[relative] = {"file": file, "uuids": macho_uuids(path)}
        require(self.executable in self.catalog and all(name in self.catalog for rows in REQUIRED_IMAGES.values() for name in rows),
                "original built app omits the selected engine images")
        self.bundle_bindings = {"app": self.bundle_binding(self.app, APP_ID),
                                "runner": self.bundle_binding(self.runner, RUNNER_ID),
                                "test": self.bundle_binding(self.test, RUNNER_ID.removesuffix(".xctrunner"))}
        descriptors = []
        for path in self.products.glob("*.xctestrun"):
            if path.name.startswith("HanlinMiniApps-origin-"):
                continue  # A retained observation copy is never a build descriptor.
            document = plistlib.loads(path.read_bytes())
            try:
                target = descriptor_target(document)
            except RuntimeError:
                continue
            descriptors.append((path, document, target))
        require(len(descriptors) == 1, "original current-build UI descriptor is missing or ambiguous")
        original, document, target = descriptors[0]
        host = descriptor_path(target.get("TestHostPath"), self.products)
        require(host == self.runner and descriptor_path(target.get("TestBundlePath"), self.products, host) == self.test
                and descriptor_path(target.get("UITargetAppPath"), self.products) == self.app,
                "descriptor points to different built UI products")
        updated = origin_descriptor(document, self.attempt, self.source)
        self.descriptor = original.with_name("HanlinMiniApps-origin-" + self.attempt + ".xctestrun")
        require(not self.descriptor.exists(), "attempt descriptor already exists")
        self.source_binding = self.current_source()
        developer = self.call(["xcode-select", "-p"], "developer-directory").strip()
        runtime = Path(state["runtime"]["bundlePath"]) / "Contents/Resources/RuntimeRoot"
        self.platform_roots = ["/System/Library", "/usr/lib", "/Library/Apple", "/Library/Developer/PrivateFrameworks",
                               str(Path(developer).resolve().parent), str(runtime.resolve(strict=True))]
        self.descriptor.write_bytes(plistlib.dumps(updated, sort_keys=False))
        (self.output / "original.xctestrun").write_bytes(original.read_bytes())
        (self.output / "origin.xctestrun").write_bytes(self.descriptor.read_bytes())
        self.descriptor_record = record(self.descriptor)
        self.admission = {"schema": 1, "attempt": self.attempt, "source": self.source, "device": self.device,
                          "producerManifest": record(self.manifest_path), "sourceBinding": self.source_binding,
                          "descriptor": self.descriptor_record, "bundles": self.bundle_bindings,
                          "catalog": self.catalog, "platformRoots": self.platform_roots,
                          "scope": "ACTUAL_PRODUCT_IMAGES_PLATFORM_PATHS_RECORDED_SEPARATELY",
                          "status": "ADMITTED_NOT_EXECUTED"}
        write_json(self.output / "admission.json", self.admission)

    def call(self, argv, label, timeout=10, *, environment=None):
        self.operation += 1
        prefix = self.output / (f"{self.operation:03d}-" + label)
        started = time.time()
        if self.deadline is not None:
            remaining = self.deadline - time.monotonic()
            require(remaining > 0, "original XCTest deadline expired during observation")
            timeout = min(timeout, remaining)
        timed_out = False
        try:
            result = subprocess.run(argv, cwd=self.root, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    timeout=timeout, env=environment)
            stdout, stderr, code = result.stdout, result.stderr, result.returncode
        except subprocess.TimeoutExpired as error:
            stdout, stderr, code = error.stdout or b"", error.stderr or b"", None
            timed_out = True
        prefix.with_suffix(".stdout").write_bytes(stdout)
        prefix.with_suffix(".stderr").write_bytes(stderr)
        write_json(prefix.with_suffix(".command.json"), {"argv": argv, "exit": code, "timedOut": timed_out,
                   "started": started, "finished": time.time(), "stdout": record(prefix.with_suffix(".stdout")),
                   "stderr": record(prefix.with_suffix(".stderr"))})
        require(code == 0 and not timed_out, "actual public command failed; see " + prefix.name)
        return stdout.decode()

    def current_source(self):
        require(self.call(["git", "rev-parse", "HEAD"], "source-head").strip() == self.source,
                "source commit changed after the original build")
        required = ("Scripts/ProductSplit/run_native_acceptance.py",
                    "Scripts/ProductSplit/observe_runtime_image_origin.py",
                    "HanlinMiniAppsUITests/HanlinMiniAppsUITests.swift",
                    "Scripts/NativeScript/app-binary-preflight.mjs")
        for relative in required:
            require(relative in self.inputs and digest(self.root / relative) == self.inputs[relative],
                    "original captured observation/build source is absent or changed: " + relative)
        require(self.manifest_path.read_bytes() == self.manifest_bytes, "frozen producer manifest changed")
        return {relative: self.inputs[relative] for relative in required}

    @staticmethod
    def bundle_binding(path, bundle_id):
        info = plistlib.loads((path / "Info.plist").read_bytes())
        executable = info.get("CFBundleExecutable")
        require(info.get("CFBundleIdentifier") == bundle_id and type(executable) is str
                and executable and Path(executable).name == executable, "wrong current original bundle identity")
        result = {"bundleID": bundle_id, "executable": executable, "info": record(path / "Info.plist"),
                  "code": {executable: record(path / executable)}}
        debug = path / (executable + ".debug.dylib")
        if debug.exists():
            result["code"][debug.name] = record(debug)
        return result

    def roots(self):
        def probe(bundle, kind):
            return Path(self.call(["xcrun", "simctl", "get_app_container", self.device, bundle, kind],
                                  "container-" + kind, timeout=5).strip()).resolve(strict=True)
        app = probe(APP_ID, "app")
        runner = probe(RUNNER_ID, "app")
        data = probe(RUNNER_ID, "data")
        bundle_root = self.device_root / "data/Containers/Bundle/Application"
        require(app.is_relative_to(bundle_root) and runner.is_relative_to(bundle_root)
                and data.parent == self.device_root / "data/Containers/Data/Application",
                "current OS products are outside the exact owned simulator")
        metadata = plistlib.loads((data / ".com.apple.mobile_container_manager.metadata.plist").read_bytes())
        require(metadata.get("MCMMetadataIdentifier") == RUNNER_ID, "exchange is not the original UI runner container")
        canonical_uuid(str(uuid.UUID(metadata["MCMMetadataUUID"])))
        require(self.bundle_binding(app, APP_ID) == self.bundle_bindings["app"]
                and self.bundle_binding(runner, RUNNER_ID) == self.bundle_bindings["runner"]
                and self.bundle_binding(runner / "PlugIns/HanlinMiniAppsUITests.xctest", RUNNER_ID.removesuffix(".xctrunner"))
                == self.bundle_bindings["test"], "XCTest installed different original app/test binaries")
        return {"app": str(app), "runner": str(runner), "runnerData": str(data),
                "runnerMCMUUID": str(uuid.UUID(metadata["MCMMetadataUUID"]))}

    def process(self, pid, label):
        environment = dict(os.environ, TZ="UTC", LC_ALL="C")
        raw = self.call(["/bin/ps", "-ww", "-p", str(pid), "-o", "pid=,ppid=,lstart=,comm="], label,
                        timeout=5, environment=environment)
        return parse_process(raw, pid)

    def observe(self, checkpoint, request_path, roots):
        request_bytes = request_path.read_bytes()
        require(len(request_bytes) <= 16384, "oversized UI checkpoint")
        request = validate_request(json.loads(request_bytes), attempt=self.attempt, source=self.source,
                                   checkpoint=checkpoint, started=self.started, now=time.time(),
                                   modified=request_path.stat().st_mtime)
        destination = self.output / checkpoint
        destination.mkdir()
        (destination / "request.json").write_bytes(request_bytes)
        app = Path(roots["app"])
        app_process = self.process(request["pid"], checkpoint + "-app-before")
        runner_process = self.process(request["runnerPID"], checkpoint + "-runner")
        require(Path(runner_process["path"]).resolve(strict=True)
                == Path(roots["runner"]) / self.bundle_bindings["runner"]["executable"]
                and math.floor(self.started) <= runner_process["launchEpoch"] <= request["at"],
                "UI request came from a foreign/stale runner process")
        require(Path(app_process["path"]).resolve(strict=True) == app / self.executable
                and math.floor(self.started) <= app_process["launchEpoch"] <= request["at"],
                "AX PID is not this attempt's actual installed app process")
        require(self.current_source() == self.source_binding, "checkpoint source changed")
        sample_path = destination / "sample.txt"
        sample_started = time.time()
        self.call(["/usr/bin/sample", str(request["pid"]), "1", "1", "-file", str(sample_path)],
                  checkpoint + "-sample", timeout=10)
        sample_finished = time.time()
        sample = parse_sample(sample_path.read_text())
        app_after = self.process(request["pid"], checkpoint + "-app-after")
        validate_sample_identity(sample, app_process, app_after, executable=app / self.executable,
                                 started=self.started, request_at=request["at"],
                                 sample_started=sample_started, sample_finished=sample_finished)
        images = classify_images(sample, app=app, products=self.products, device_root=self.device_root,
                                 catalog=self.catalog, architecture=self.architecture, executable=self.executable,
                                 checkpoint=checkpoint, platform_roots=self.platform_roots)
        # Reuse the original reader and its exact unique-host-metadata rule.
        # No copied metadata parser or altered runtime guard is introduced.
        code = ("import {collectHostImages,requireHostMetadata} from './Scripts/NativeScript/app-binary-preflight.mjs';"
                "const images=await collectHostImages(process.argv[1],process.argv[2]);"
                "const owners=[...requireHostMetadata(images)];"
                "console.log(JSON.stringify({images,owners},(_,v)=>typeof v==='bigint'?v.toString():v));")
        metadata = json.loads(self.call(["node", "--input-type=module", "-e", code, str(app), str(app / self.executable)],
                                       checkpoint + "-original-metadata-reader", timeout=10))
        owners = [path for architecture, path in metadata["owners"] if architecture == self.architecture]
        require(len(owners) == 1 and any(Path(row["path"]).resolve() == Path(owners[0]).resolve()
                                      for row in images["productImages"]),
                "the original unique host metadata owner was not actually loaded")
        require(request_path.read_bytes() == request_bytes and self.roots() == roots
                and self.current_source() == self.source_binding, "request, MCM products or source changed at completion")
        receipt = {"schema": 1, "attempt": self.attempt, "source": self.source, "checkpoint": checkpoint,
                   "requestID": request["requestID"], "pid": request["pid"], "request": record(request_path),
                   "roots": roots, "before": app_process, "after": app_after, "runner": runner_process,
                   "sample": record(sample_path), "sampleStarted": sample_started, "sampleFinished": sample_finished,
                   "sampleHeader": sample["header"], "images": images, "originalMetadataReader": metadata,
                   "producerManifest": record(self.manifest_path), "status": "OBSERVED_BOUND_LOADED_IMAGES",
                   "qualification": "Real loaded product images only; original XCTest and Bridge runtime results are separate required gates."}
        write_json(destination / "receipt.json", receipt)
        response = {key: receipt[key] for key in ("schema", "attempt", "source", "checkpoint", "requestID", "pid", "status")}
        response.update(sampleSHA256=receipt["sample"]["sha256"], receiptSHA256=digest(destination / "receipt.json"))
        # Last read is current MCM identity before writing only the runner reply.
        require(self.roots() == roots, "current installed products changed before response publication")
        write_json(request_path.with_name("response.json"), response)
        write_json(destination / "response.json", response)
        self.observations[checkpoint] = {"receipt": record(destination / "receipt.json"), "response": response,
                                         "responseFile": record(destination / "response.json")}
        self.last_roots = roots

    def poll(self):
        # XCTest creates/installs its runner later than build-for-testing. An
        # absent runner has no request and is not guessed from another container.
        if self.attempted == set(CHECKPOINTS):
            return
        try:
            runner_data = Path(self.call(["xcrun", "simctl", "get_app_container", self.device, RUNNER_ID, "data"],
                                        "pending-runner-data", timeout=5).strip()).resolve(strict=True)
        except (RuntimeError, FileNotFoundError, subprocess.TimeoutExpired):
            return
        require(runner_data.parent == self.device_root / "data/Containers/Data/Application",
                "pending exchange is outside the owned simulator")
        for checkpoint in CHECKPOINTS:
            if checkpoint in self.attempted:
                continue
            exchange = runner_data / "Documents" / EXCHANGE / self.attempt / checkpoint
            request = exchange / "request.json"
            if not request.is_file():
                continue
            # Full binary/MCM checks occur only at a real checkpoint, not during
            # unrelated unit cases or the original runtime's cold preparation.
            roots = self.roots()
            require(Path(roots["runnerData"]) == runner_data, "runner container changed while admitting the request")
            require(request.resolve() == request and request.is_relative_to(runner_data / "Documents"),
                    "UI exchange follows an unexpected link")
            self.attempted.add(checkpoint)  # A failed sample is never retried.
            try:
                self.observe(checkpoint, request, roots)
            except Exception as error:
                failure = {"checkpoint": checkpoint, "error": str(error), "at": time.time()}
                self.errors.append(failure)
                write_json(self.output / (checkpoint + "-failure.json"), failure)
                # An invalid request cannot authorize a write at a guessed path.
                # A fully bound existing runner directory may receive failure,
                # which cannot satisfy the UI's required success response.
                if self.roots() == roots:
                    raw = json.loads(request.read_bytes())
                    response = {key: raw.get(key) for key in ("schema", "attempt", "source", "checkpoint", "requestID", "pid")}
                    response.update(status="OBSERVATION_FAILED", sampleSHA256="", receiptSHA256="", error=str(error))
                    write_json(request.with_name("response.json"), response)

    def finish(self, process, started, stop_reason):
        value = {"schema": 1, "attempt": self.attempt, "source": self.source, "device": self.device,
                 "nativePID": process.pid if process else None, "nativeExit": process.returncode if process else None,
                 "started": self.started, "elapsedSeconds": time.monotonic() - started,
                 "stopReason": stop_reason, "attempted": sorted(self.attempted),
                 "observations": self.observations, "errors": self.errors,
                 "status": "REQUIRES_ORIGINAL_25_XCTEST_AND_THREE_BRIDGE_RESULT_GATES"}
        if stop_reason is not None or self.errors or set(self.observations) != set(CHECKPOINTS):
            value["status"] = "ORIGIN_NOT_QUALIFIED"
        write_json(self.output / "controller.json", value)
        return value


def stop_owned(process):
    if process is None or process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        process.wait(timeout=5)
        return
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=5)


def origin_test_command(argv, descriptor, expected_selectors):
    require(argv.count("test-without-building") == 1 and argv.count("-parallel-testing-enabled") == 1
            and argv.index("-parallel-testing-enabled") + 1 < len(argv)
            and argv[argv.index("-parallel-testing-enabled") + 1] == "NO"
            and not any(value.startswith("-skip-testing:") for value in argv)
            and os.environ.get("SPLIT_REUSE_NATIVE_PROOF", "0") != "1", "original exact nonparallel/fresh command changed")
    require([value.removeprefix("-only-testing:") for value in argv if value.startswith("-only-testing:")]
            == expected_selectors and "-xctestrun" not in argv, "original selected test cases changed")
    actual = list(argv)
    # Installed xctestrun(5) carries the built paths; the established original
    # descriptor route uses no project, scheme or scheme-derived-data option.
    for option in ("-project", "-scheme", "-derivedDataPath"):
        require(actual.count(option) == 1, "original build graph option is missing or ambiguous")
        index = actual.index(option)
        del actual[index:index + 2]
    return actual + ["-xctestrun", str(descriptor)]


def run_original_with_origin(argv, log, state, derived, inputs, root, evidence, expected_selectors):
    # Validate the original selection before creating any observation artifact.
    origin_test_command(argv, "ADMISSION_ONLY", expected_selectors)
    observer = OriginObserver(root, evidence, derived, state, inputs)
    actual = origin_test_command(argv, observer.descriptor, expected_selectors)
    state["origin_original_command"] = argv
    state["command"] = actual
    write_json(Path(evidence) / "command.json", actual)
    native = None
    stop_reason = None
    started = time.monotonic()
    observer.started = time.time()
    observer.deadline = started + 1200
    try:
        native = subprocess.Popen(actual, cwd=root, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        next_probe = started
        while native.poll() is None:
            now = time.monotonic()
            if now - started >= 1200:
                stop_reason = "ORIGINAL_1200_SECOND_XCTEST_DEADLINE"
                break
            if now >= next_probe:
                next_probe = now + 1
                observer.poll()
            # Wait on this owned native child's completion, not a fixed delay.
            try:
                native.wait(timeout=min(0.2, max(0.001, observer.deadline - time.monotonic())))
            except subprocess.TimeoutExpired:
                pass
        if stop_reason is None:
            observer.deadline = None  # Original native command has terminated.
            require(observer.current_source() == observer.source_binding
                    and record(observer.descriptor) == observer.descriptor_record
                    and (observer.last_roots is None or observer.roots() == observer.last_roots),
                    "source, original xctestrun or last observed MCM products changed before native terminal")
    except BaseException:
        stop_reason = stop_reason or "ORIGIN_CONTROLLER_FAILED"
        raise
    finally:
        try:
            stop_owned(native)
        except Exception as error:
            stop_reason = stop_reason or "OWNED_NATIVE_CLEANUP_FAILED"
            observer.errors.append({"cleanup": str(error)})
        try:
            require(record(observer.descriptor) == observer.descriptor_record,
                    "owned descriptor changed before cleanup")
            observer.descriptor.unlink()
        except Exception as error:
            stop_reason = stop_reason or "OWNED_DESCRIPTOR_CLEANUP_FAILED"
            observer.errors.append({"descriptorCleanup": str(error)})
        state["runtime_image_origin"] = observer.finish(native, started, stop_reason)
    return subprocess.CompletedProcess(actual, native.returncode)


def validate_origin_terminal(value, evidence):
    require(type(value) is dict and value.get("status") == "REQUIRES_ORIGINAL_25_XCTEST_AND_THREE_BRIDGE_RESULT_GATES"
            and type(value.get("nativeExit")) is int and value["nativeExit"] == 0
            and value.get("stopReason") is None and value.get("errors") == []
            and set(value.get("observations", {})) == set(CHECKPOINTS)
            and value.get("attempted") == sorted(CHECKPOINTS), "incomplete or failed actual image observations")
    output = Path(evidence) / "runtime-image-origin"
    require(json.loads((output / "controller.json").read_bytes()) == value, "controller evidence changed")
    for checkpoint in CHECKPOINTS:
        item = value["observations"][checkpoint]
        path = output / checkpoint / "receipt.json"
        receipt = json.loads(path.read_bytes())
        require(record(path) == item["receipt"] and digest(path) == item["response"]["receiptSHA256"]
                and receipt["attempt"] == value["attempt"] and receipt["source"] == value["source"]
                and receipt["checkpoint"] == checkpoint and receipt["status"] == "OBSERVED_BOUND_LOADED_IMAGES"
                and record(output / checkpoint / "sample.txt") == receipt["sample"]
                and record(output / checkpoint / "response.json") == item["responseFile"]
                and json.loads((output / checkpoint / "response.json").read_bytes()) == item["response"],
                "bound actual sample/receipt/response changed")
    return {"status": "EXECUTED_PASS", "checkpointCount": 2,
            "qualification": "Two actual standalone runtime loaded-image observations, conditional on the separately verified original25 and three Bridge result readers.",
            "controllerSHA256": digest(output / "controller.json")}
