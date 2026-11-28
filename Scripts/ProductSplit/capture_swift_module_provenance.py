"""Retain named Swift module evidence only after an original MiniApps build fails.

This observes existing DerivedData. It does not compile, clean caches, select a
module, interpret API strings, or change the original build result.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import os
import re
import stat
import subprocess
import sys
import time


MODULE = "HanlinPlatformContracts"
CONFIGURATION = "Debug-iphonesimulator"
MAX_FILE_BYTES = 8 * 1024 * 1024
MAX_RETAINED_BYTES = 16 * 1024 * 1024
MAX_READ_BYTES = 32 * 1024 * 1024
MAX_CANDIDATES = 48
MAX_DIRECTORY_ENTRIES = 4096
COLLECTION_SECONDS = 6
CHILD_TIMEOUT_SECONDS = 8
DIRECTORY_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
FILE_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
MODULE_SUFFIXES = (".swiftmodule", ".swiftdoc", ".swiftinterface", ".abi.json")
PRODUCTS = f"Build/Products/{CONFIGURATION}"
PRODUCER = (f"Build/Intermediates.noindex/HanlinSDK.build/{CONFIGURATION}/"
            f"{MODULE}-t.build/Objects-normal/arm64")
IMPORTER = (f"Build/Intermediates.noindex/AI_HLY.build/{CONFIGURATION}/"
            "HanlinMiniApps.build/Objects-normal/arm64")
MODULE_DIRECTORIES = (
    f"{PRODUCTS}/{MODULE}.swiftmodule",
    f"{PRODUCTS}/PackageFrameworks/{MODULE}.framework/Modules/{MODULE}.swiftmodule",
    f"{PRODUCTS}/{MODULE}.framework/Modules/{MODULE}.swiftmodule",
)
EXPLICIT_MODULES = "Build/Intermediates.noindex/SwiftExplicitPrecompiledModules"


def open_directory(path, parent=None):
    """Walk from an existing directory fd, never following a path component."""
    path = Path(path)
    if ".." in path.parts or (parent is not None and path.is_absolute()):
        raise ValueError("directory escapes its evidence anchor")
    if parent is None:
        if not path.is_absolute():
            raise ValueError("absolute evidence anchor required")
        current = os.open("/", DIRECTORY_FLAGS)
        parts = path.parts[1:]
    else:
        current = os.dup(parent)
        parts = path.parts
    try:
        for part in parts:
            following = os.open(part, DIRECTORY_FLAGS, dir_fd=current)
            os.close(current)
            current = following
        return current
    except BaseException:
        os.close(current)
        raise


def owned_directory(path):
    descriptor = open_directory(path)
    if os.fstat(descriptor).st_uid != os.getuid():
        os.close(descriptor)
        raise PermissionError("directory is not owned by this runner")
    return descriptor


def identity(value):
    return {key: getattr(value, key) for key in
            ("st_dev", "st_ino", "st_mode", "st_uid", "st_gid", "st_nlink",
             "st_size", "st_mtime_ns", "st_ctime_ns")}


def write_json(directory, name, value):
    temporary = name + ".tmp"
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                         0o600, dir_fd=directory)
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(value, stream, indent=2, sort_keys=True)
            stream.write("\n")
        os.replace(temporary, name, src_dir_fd=directory, dst_dir_fd=directory)
    finally:
        try:
            os.unlink(temporary, dir_fd=directory)
        except FileNotFoundError:
            pass


def collect(derived, output, phase_deadline):
    """Both descriptors are already owned directory anchors; no source is read."""
    for descriptor in (derived, output):
        value = os.fstat(descriptor)
        if not stat.S_ISDIR(value.st_mode) or value.st_uid != os.getuid():
            raise PermissionError("unowned collection anchor")
    started = time.monotonic()
    if not math.isfinite(phase_deadline) or phase_deadline <= started:
        raise ValueError("original build deadline expired")
    deadline = min(started + COLLECTION_SECONDS, phase_deadline)
    report = {
        "schemaVersion": 1, "status": "COLLECTING", "module": MODULE,
        "purpose": "Existing compiler artifacts only; no API or native acceptance conclusion.",
        "derivedIdentity": identity(os.fstat(derived)),
        "limits": {"fileBytes": MAX_FILE_BYTES, "retainedBytes": MAX_RETAINED_BYTES,
                   "readBytes": MAX_READ_BYTES, "candidates": MAX_CANDIDATES,
                   "directoryEntries": MAX_DIRECTORY_ENTRIES, "seconds": COLLECTION_SECONDS,
                   "effectiveDeadlineMonotonic": deadline},
        "files": [], "directories": [], "limitReasons": [],
        "bytesRead": 0, "bytesRetained": 0,
    }
    os.mkdir("blobs", 0o700, dir_fd=output)
    blobs = os.open("blobs", DIRECTORY_FLAGS, dir_fd=output)
    retained = set()
    seen = set()

    def checkpoint():
        report["elapsedSeconds"] = time.monotonic() - started
        write_json(output, "receipt.json", report)

    def available():
        if time.monotonic() >= deadline:
            if "TIME_LIMIT" not in report["limitReasons"]:
                report["limitReasons"].append("TIME_LIMIT")
            return False
        return True

    def capture(relative):
        if relative in seen or not available():
            return
        if len(seen) >= MAX_CANDIDATES:
            if "CANDIDATE_LIMIT" not in report["limitReasons"]:
                report["limitReasons"].append("CANDIDATE_LIMIT")
            return
        seen.add(relative)
        row = {"path": relative, "status": "UNREAD"}
        report["files"].append(row)
        parent = descriptor = None
        try:
            path = Path(relative)
            parent = open_directory(path.parent, derived)
            descriptor = os.open(path.name, FILE_FLAGS, dir_fd=parent)
            before = os.fstat(descriptor)
            row["identityBefore"] = identity(before)
            if (not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid()
                    or before.st_nlink != 1):
                row["status"] = "REJECTED_FILE_IDENTITY"
                return
            if before.st_size > MAX_FILE_BYTES:
                row["status"] = "FILE_SIZE_LIMIT"
                return
            if report["bytesRead"] + before.st_size > MAX_READ_BYTES:
                row["status"] = "TOTAL_READ_LIMIT"
                return
            pieces = []
            length = 0
            while length < before.st_size:
                if not available():
                    row["status"] = "TIME_LIMIT"
                    return
                chunk = os.read(descriptor, min(65536, before.st_size - length))
                if not chunk:
                    break
                pieces.append(chunk)
                length += len(chunk)
                report["bytesRead"] += len(chunk)
            after = os.fstat(descriptor)
            row["identityAfter"] = identity(after)
            if identity(before) != identity(after) or length != before.st_size:
                row["status"] = "CHANGED_DURING_READ"
                return
            data = b"".join(pieces)
            digest = hashlib.sha256(data).hexdigest()
            row.update(bytes=len(data), sha256=digest)
            if digest not in retained:
                if report["bytesRetained"] + len(data) > MAX_RETAINED_BYTES:
                    row["status"] = "TOTAL_RETAINED_LIMIT"
                    return
                target = os.open(digest, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                                 0o600, dir_fd=blobs)
                with os.fdopen(target, "wb") as stream:
                    stream.write(data)
                retained.add(digest)
                report["bytesRetained"] += len(data)
            row.update(status="CAPTURED", blob="blobs/" + digest)
        except (OSError, ValueError) as error:
            row.update(status="UNAVAILABLE", errorType=type(error).__name__)
        finally:
            if descriptor is not None:
                os.close(descriptor)
            if parent is not None:
                os.close(parent)
            checkpoint()

    def scan(relative, accepts):
        if not available():
            return
        row = {"path": relative, "status": "UNREAD", "entriesExamined": 0}
        report["directories"].append(row)
        descriptor = None
        try:
            descriptor = open_directory(relative, derived)
            with os.scandir(descriptor) as entries:
                for entry in entries:
                    if not available():
                        row["status"] = "TIME_LIMIT"
                        break
                    if row["entriesExamined"] >= MAX_DIRECTORY_ENTRIES:
                        row["status"] = "DIRECTORY_ENTRY_LIMIT"
                        report["limitReasons"].append("DIRECTORY_ENTRY_LIMIT")
                        break
                    row["entriesExamined"] += 1
                    if accepts(entry.name):
                        capture(relative + "/" + entry.name)
                else:
                    row["status"] = "ENUMERATED"
        except (OSError, ValueError) as error:
            row.update(status="UNAVAILABLE", errorType=type(error).__name__)
        finally:
            if descriptor is not None:
                os.close(descriptor)
            checkpoint()

    def module_member(name):
        return bool(re.fullmatch(
            r"arm64(?:-apple-ios-simulator)?(?:\.private|\.package)?"
            r"\.(?:swiftmodule|swiftdoc|swiftinterface|abi\.json)", name))

    def driver_member(name, target):
        return name == target + ".SwiftFileList" or bool(re.fullmatch(
            re.escape(target) +
            r"-(?:OutputFileMap|dependencies(?:-[0-9]+)?|dependency-scan|"
            r"DependencyScan|SwiftDependencyMap|explicit-module-map)\.json", name))

    try:
        checkpoint()
        for suffix in MODULE_SUFFIXES:
            capture(PRODUCER + "/" + MODULE + suffix)
            capture(PRODUCTS + "/" + MODULE + suffix)
        for directory in MODULE_DIRECTORIES:
            scan(directory, module_member)
        scan(PRODUCER, lambda name: driver_member(name, MODULE))
        scan(IMPORTER, lambda name: driver_member(name, "HanlinMiniApps"))
        scan(EXPLICIT_MODULES, lambda name: bool(re.fullmatch(
            re.escape(MODULE) + r"-[A-Za-z0-9_-]+\.(?:swiftmodule|swiftdoc|swiftinterface|abi\.json)",
            name)))
        limited = report["limitReasons"] or any("LIMIT" in row["status"] for row in report["files"])
        report["status"] = "PARTIAL_LIMIT" if limited else "OBSERVED"
        checkpoint()
        return report
    finally:
        os.close(blobs)


def capture_failed_build(derived_data, evidence, log_name, exit_code, log_sha256, phase_deadline):
    """An observation failure must never replace the original build exception."""
    if log_name not in {"mini-build.log", "build.log"} or type(exit_code) is not int or exit_code == 0:
        return {"status": "NOT_A_FAILED_MINIAPPS_BUILD"}
    started = time.monotonic()
    if (type(phase_deadline) not in (int, float) or not math.isfinite(phase_deadline)
            or phase_deadline <= started):
        return {"status": "NO_ORIGINAL_BUILD_TIME_REMAINING"}
    result = {"schemaVersion": 1, "status": "NOT_STARTED", "buildLog": log_name,
              "buildLogSHA256": log_sha256, "originalExitCode": exit_code,
              "childTimeoutCapSeconds": CHILD_TIMEOUT_SECONDS,
              "originalPhaseDeadlineMonotonic": phase_deadline,
              "originalPhaseSecondsRemainingAtCapture": phase_deadline - started,
              "acceptance": "UNCHANGED_ORIGINAL_BUILD_FAILURE"}
    handles = []
    output = None
    try:
        if not re.fullmatch(r"[0-9a-f]{64}", log_sha256):
            raise ValueError("invalid existing build-log digest")
        evidence_fd = owned_directory(Path(evidence).absolute())
        handles.append(evidence_fd)
        os.mkdir("swift-module-provenance", 0o700, dir_fd=evidence_fd)
        output = os.open("swift-module-provenance", DIRECTORY_FLAGS, dir_fd=evidence_fd)
        handles.append(output)
        derived = owned_directory(Path(derived_data).absolute())
        handles.append(derived)
        result["derivedData"] = str(Path(derived_data).absolute())
        result["derivedIdentity"] = identity(os.fstat(derived))
        timeout = min(CHILD_TIMEOUT_SECONDS, phase_deadline - time.monotonic())
        if timeout <= 0:
            result["status"] = "NO_ORIGINAL_BUILD_TIME_REMAINING"
            return result
        result["childTimeoutSeconds"] = timeout
        write_json(output, "controller-start.json", result)
        process = subprocess.run(
            [sys.executable, str(Path(__file__).resolve()), "--derived-fd", str(derived),
             "--output-fd", str(output), "--phase-deadline", str(phase_deadline)],
            pass_fds=(derived, output), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=timeout, check=False)
        result.update(status="COLLECTOR_EXITED", childExitCode=process.returncode)
    except subprocess.TimeoutExpired:
        result["status"] = "COLLECTOR_TIMED_OUT"
    except Exception as error:
        result.update(status="CAPTURE_UNAVAILABLE", errorType=type(error).__name__)
    finally:
        result["captureElapsedSeconds"] = time.monotonic() - started
        if output is not None:
            try:
                write_json(output, "controller.json", result)
            except Exception as error:
                result["receiptErrorType"] = type(error).__name__
        for descriptor in reversed(handles):
            os.close(descriptor)
    print("Swift module provenance: " + result["status"], file=sys.stderr)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--derived-fd", type=int, required=True)
    parser.add_argument("--output-fd", type=int, required=True)
    parser.add_argument("--phase-deadline", type=float, required=True)
    args = parser.parse_args()
    collect(args.derived_fd, args.output_fd, args.phase_deadline)
