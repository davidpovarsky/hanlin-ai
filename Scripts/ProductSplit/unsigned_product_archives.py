"""Create and transfer the original unsigned product archives without signing.

The normal signing tool shares the original package/schema and archive commands.
The create mode never reads signing material or changes the user's keychain.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import time

from signing_profile_preflight import run_owned_process
from extension_inventory import signing_targets_for_owner, embedded_product_bundles

PRODUCTS = (
    ("miniapps", "HanlinMiniApps", "com.itorah.hanlinminiapps"),
    ("ai", "AI_HLY", "com.itorah.chavrusachat"),
)


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def retained_bytes(path, seen):
    path = Path(path)
    result = {"path": str(path), "exists": path.exists(), "logicalBytes": 0,
              "allocatedBytesFromStat": 0, "files": 0, "directories": 0, "links": 0}
    if not result["exists"]:
        return result
    def include(entry):
        info = entry.lstat()
        key = (info.st_dev, info.st_ino)
        if key in seen:
            return
        seen.add(key)
        result["allocatedBytesFromStat"] += info.st_blocks * 512
        if stat.S_ISREG(info.st_mode):
            result["logicalBytes"] += info.st_size
            result["files"] += 1
        elif stat.S_ISLNK(info.st_mode):
            result["logicalBytes"] += info.st_size
            result["links"] += 1
        elif stat.S_ISDIR(info.st_mode):
            result["directories"] += 1
    include(path)
    if path.is_dir() and not path.is_symlink():
        for directory, directories, files in os.walk(path, followlinks=False):
            for name in [*directories, *files]:
                include(Path(directory) / name)
    return result


def record_archive_capacity(root, evidence, role, moment, previous=None):
    """Measure this archive phase; the workflow's earlier disk check is not reused."""
    disk = shutil.disk_usage(root)
    seen = set()
    paths = [
        root / "build/ReleaseDerivedData", root / "build/ReleaseArchives",
        evidence, root / "build/AppSplitDerivedData", root / "build/SourcePackages",
        root / "build/runtime-host",
    ]
    retained = [retained_bytes(path, seen) for path in paths]
    snapshot = {
        "schemaVersion": 1, "observedAt": datetime.now(timezone.utc).isoformat(),
        "role": role, "moment": moment, "filesystem": {
            "totalBytes": disk.total, "usedBytes": disk.used, "freeBytes": disk.free},
        "retainedPaths": retained,
        "retainedLogicalBytes": sum(item["logicalBytes"] for item in retained),
        "retainedAllocatedBytesFromStat": sum(item["allocatedBytesFromStat"] for item in retained),
        "measurement": "Current filesystem free space and retained phase outputs; allocated stat bytes are not an estimate of reclaimable APFS space.",
    }
    if previous is not None:
        snapshot["sincePreviousObservation"] = {
            "moment": previous["moment"],
            "observedFreeConsumedBytes": previous["filesystem"]["freeBytes"] - disk.free,
            "retainedLogicalBytesAdded": snapshot["retainedLogicalBytes"] - previous["retainedLogicalBytes"],
            "retainedAllocatedBytesAdded": snapshot["retainedAllocatedBytesFromStat"] - previous["retainedAllocatedBytesFromStat"],
        }
    path = evidence / (role + "-capacity-" + moment + ".json")
    write_json(path, snapshot)
    snapshot["receipt"] = {"path": str(path), "sha256": sha256(path)}
    return snapshot


def admit_archive_phase(root, evidence, role, snapshot):
    """Estimate remaining allocation from this run's paired products, not an old peak."""
    paired = Path(os.environ.get("SPLIT_DERIVED_DATA", str(root / "build/AppSplitDerivedData")))
    products = paired / "Build/Products"
    paired_bytes = retained_bytes(paired, set())
    product_bytes = retained_bytes(products, set())
    app_root = products / "Debug-iphonesimulator"
    applications = [retained_bytes(app_root / name, set())
                    for name in ("HanlinMiniApps.app", "AI_Hanlin.app")]
    if not all(item["exists"] and item["files"] > 0 for item in applications):
        raise ValueError("Archive estimate requires this run's two completed paired app products")
    release_estimate = max(paired_bytes["logicalBytes"], paired_bytes["allocatedBytesFromStat"])
    archive_estimate = max(product_bytes["logicalBytes"], product_bytes["allocatedBytesFromStat"])
    if release_estimate <= 0 or archive_estimate <= 0:
        raise ValueError("Paired build allocation is unavailable for the archive estimate")
    entries = product_bytes["files"] + product_bytes["directories"] + product_bytes["links"] + 1
    # Assume no compression savings. Account for tar headers/padding/PAX records,
    # and a 1% compression-expansion allowance, rather than a prior compressed ZIP.
    raw_tar_estimate = archive_estimate + entries * 4096 + 10240
    tar_estimate = (raw_tar_estimate * 101 + 99) // 100
    release = retained_bytes(root / "build/ReleaseDerivedData", set())
    release_growth = max(0, release_estimate - release["allocatedBytesFromStat"])
    resource_path = root / "Scripts/ProductSplit/Acceptance/resource-model.json"
    resource = json.loads(resource_path.read_text())
    growth = resource["concurrentGrowthReserveBytes"]
    margin = resource["modestOSMarginBytes"]
    if any(type(value) is not int or value <= 0 for value in (growth, margin)):
        raise ValueError("Original concurrent-growth and OS margins must be positive byte counts")
    index = next(i for i, item in enumerate(PRODUCTS) if item[0] == role)
    remaining = []
    for pending_role, scheme, _ in PRODUCTS[index:]:
        archive = retained_bytes(root / "build/ReleaseArchives" / (scheme + ".xcarchive"), set())
        tar = retained_bytes(evidence / (scheme + ".xcarchive.tar.gz"), set())
        remaining.append({
            "role": pending_role, "archiveEstimateBytes": archive_estimate,
            "tarCopyEstimateBytes": tar_estimate,
            "alreadyAllocatedArchiveBytes": archive["allocatedBytesFromStat"],
            "alreadyAllocatedTarBytes": tar["allocatedBytesFromStat"],
            "remainingArchiveBytes": max(0, archive_estimate - archive["allocatedBytesFromStat"]),
            "remainingTarCopyBytes": max(0, tar_estimate - tar["allocatedBytesFromStat"]),
        })
    archive_growth = sum(item["remainingArchiveBytes"] for item in remaining)
    tar_growth = sum(item["remainingTarCopyBytes"] for item in remaining)
    incremental = release_growth + archive_growth + tar_growth
    required = incremental + growth + margin
    # Resample after walking the live basis so admission uses the latest free value.
    free = shutil.disk_usage(root).free
    plan = {
        "schemaVersion": 1, "role": role, "observedAt": datetime.now(timezone.utc).isoformat(),
        "status": "ADMITTED_ESTIMATE" if free >= required else "DEFERRED_INSUFFICIENT_FREE",
        "kind": "ESTIMATE_FROM_LIVE_PAIRED_OUTPUTS_NOT_A_PROVEN_RELEASE_PEAK",
        "basis": {"pairedDerivedData": paired_bytes, "pairedBuildProducts": product_bytes,
                  "pairedApplications": applications, "currentReleaseDerivedData": release,
                  "observation": snapshot["receipt"], "resourceModel": {
                      "path": str(resource_path), "sha256": sha256(resource_path)}},
        "formula": {
            "releaseDerivedDataTarget": "max(live paired DD logical bytes, live paired DD allocated bytes)",
            "eachRemainingArchiveTree": "max(live paired Build/Products logical bytes, allocated bytes)",
            "eachRemainingTarCopy": "ceil((archive tree estimate + 4096 * (observed product entries + 1) + 10240) * 1.01); no compression savings",
            "requiredFree": "remaining Release DD growth + remaining archive trees + remaining tar copies + concurrent growth + OS margin",
            "credit": "Only allocations already observed in ReleaseDerivedData, archive trees and tar files are credited.",
        },
        "estimatedReleaseDerivedDataTotalBytes": release_estimate,
        "alreadyAllocatedReleaseDerivedDataBytes": release["allocatedBytesFromStat"],
        "remainingReleaseDerivedDataBytes": release_growth,
        "remainingProducts": remaining,
        "remainingArchiveTreeBytes": archive_growth, "remainingTarCopyBytes": tar_growth,
        "estimatedIncrementalBytes": incremental,
        "concurrentGrowthReserveBytes": growth, "modestOSMarginBytes": margin,
        "requiredFreeBytes": required, "observedFreeBytes": free,
    }
    target = evidence / (role + "-archive-admission.json")
    write_json(target, plan)
    return plan


def common_arguments(root):
    return ["xcodebuild", "-project", "AI_HLY.xcodeproj",
            "-clonedSourcePackagesDirPath", root / "build/SourcePackages",
            "-skipPackagePluginValidation", "-skipMacroValidation"]


def prepare_archive_inputs(root, evidence, run):
    packages = root / "build/SourcePackages"
    derived = root / "build/ReleaseDerivedData"
    run(common_arguments(root) + ["-scheme", "AI_HLY", "-resolvePackageDependencies"],
        "resolve-original-packages", 600)
    run([sys.executable, "Scripts/CI/stage_a2ui_schemas.py",
         "--source-packages-path", packages, "--derived-data-path", derived,
         "--evidence", evidence / "original-a2ui-schemas"],
        "original-schema-generator", 360)


def archive_arguments(root, scheme, archive):
    return common_arguments(root) + [
        "-scheme", scheme, "-configuration", "Release",
        "-destination", "generic/platform=iOS",
        "-derivedDataPath", root / "build/ReleaseDerivedData",
        "-archivePath", archive, "archive",
        "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO",
        "CODE_SIGN_IDENTITY=", "PROVISIONING_PROFILE_SPECIFIER=",
        "PROVISIONING_PROFILE=",
    ]


def archive_identity(archive, bundle, host_sha256=None):
    archive = Path(archive)
    info = plistlib.loads((archive / "Info.plist").read_bytes())
    application = info.get("ApplicationProperties", {})
    if application.get("CFBundleIdentifier") != bundle:
        raise ValueError("Archive identity does not match the original product")
    application_path = application.get("ApplicationPath")
    if not isinstance(application_path, str):
        raise ValueError("Archive has no original application path")
    app = archive / "Products" / application_path
    if not app.resolve().is_relative_to(archive.resolve()) or not app.is_dir():
        raise ValueError("Archive application path does not resolve within the archive")
    app_info = plistlib.loads((app / "Info.plist").read_bytes())
    for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"):
        if not app_info.get(key) or app_info[key] != application.get(key):
            raise ValueError("Archive application metadata differs: " + key)
    role = next((role for role, _, expected in PRODUCTS if expected == bundle), None)
    if role is None:
        raise ValueError("Archive is not one of the original products")
    expected_bundles = {target.bundle for target in signing_targets_for_owner(role)}
    bundles = []
    for embedded in embedded_product_bundles(app):
        embedded_info = embedded / "Info.plist"
        identifier = plistlib.loads(embedded_info.read_bytes()).get("CFBundleIdentifier")
        if identifier not in expected_bundles or any(item["bundleID"] == identifier for item in bundles):
            raise ValueError("Archive contains an unexpected or duplicate product/extension")
        bundles.append({"bundleID": identifier, "path": embedded.relative_to(app).as_posix(),
                        "infoSHA256": sha256(embedded_info)})
    if {item["bundleID"] for item in bundles} != expected_bundles:
        raise ValueError("Archive does not contain every declared product extension")
    host = app / "RuntimeHostResources.zip"
    if host_sha256 is not None and (not host.is_file() or sha256(host) != host_sha256):
        raise ValueError("Archive does not contain the exact verified shipping Host/SDK")
    return {"bundleID": bundle, "version": application["CFBundleShortVersionString"],
            "build": application["CFBundleVersion"], "applicationPath": application_path,
            "infoSHA256": sha256(archive / "Info.plist"),
            "embeddedBundles": sorted(bundles, key=lambda item: item["bundleID"]),
            "hostArchiveSHA256": sha256(host) if host.is_file() else None}


def archive_tree(archive):
    archive = Path(archive)
    root_mode = archive.lstat().st_mode
    if not stat.S_ISDIR(root_mode):
        raise ValueError("Archive root must be its original directory")
    entries = [{"path": ".", "kind": "directory", "mode": stat.S_IMODE(root_mode)}]
    file_inodes = {}
    for directory, directories, names in os.walk(archive, followlinks=False):
        directories.sort()
        for name in sorted([*directories, *names]):
            path = Path(directory) / name
            relative = path.relative_to(archive).as_posix()
            info = path.lstat()
            mode = info.st_mode
            record = {"path": relative, "mode": stat.S_IMODE(mode)}
            if stat.S_ISLNK(mode):
                target = os.readlink(path)
                if os.path.isabs(target):
                    raise ValueError("Archive link is absolute and cannot be relocated unchanged: " + relative)
                if not path.resolve(strict=False).is_relative_to(archive.resolve()):
                    raise ValueError("Archive link leaves its original bundle: " + relative)
                record.update(kind="symlink", target=target)
            elif stat.S_ISDIR(mode):
                record.update(kind="directory")
            elif stat.S_ISREG(mode):
                record.update(kind="file", bytes=info.st_size, sha256=sha256(path))
                inode = (info.st_dev, info.st_ino)
                if inode in file_inodes:
                    record["hardlinkTo"] = file_inodes[inode]
                else:
                    file_inodes[inode] = relative
            else:
                raise ValueError("Unsupported archive member: " + relative)
            entries.append(record)
    return sorted(entries, key=lambda item: item["path"])


def tree_sha256(entries):
    return hashlib.sha256(json.dumps(entries, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def verify_producer(root, receipt_path):
    receipt = json.loads(Path(receipt_path).read_text())
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    if receipt.get("schemaVersion") != 1 or receipt.get("sourceCommit") != head:
        raise ValueError("Host producer does not match the checked-out source")
    if receipt.get("status") != "VERIFIED_HOST_SDK" or receipt.get("node", {}).get("platform") != "darwin":
        raise ValueError("An actual verified Darwin Host producer is required")
    inputs_path = root / receipt["sdkInputs"]["path"]
    if sha256(inputs_path) != receipt["sdkInputs"]["sha256"]:
        raise ValueError("SDK input receipt changed after production")
    inputs = json.loads(inputs_path.read_text())
    if inputs.get("sha256") != receipt["sdkManifest"]["inputSHA256"]:
        raise ValueError("Embedded SDK input identity differs from the source receipt")
    for item in inputs["files"]:
        path = root / item["path"]
        if not path.resolve().is_relative_to(root.resolve()) or sha256(path) != item["sha256"]:
            raise ValueError("SDK source changed after production: " + item["path"])
    host = root / receipt["hostArchive"]["path"]
    if sha256(host) != receipt["hostArchive"]["sha256"]:
        raise ValueError("Shipping Host archive changed after production")
    patch = subprocess.check_output(["git", "diff", "--binary", "HEAD"], cwd=root)
    if hashlib.sha256(patch).hexdigest() != receipt["sourcePatch"]["sha256"]:
        raise ValueError("Tracked source changed after the Host/SDK producer")
    catalog = receipt.get("nativeCatalog")
    if not catalog or sha256(root / catalog["path"]) != catalog["sha256"]:
        raise ValueError("Exact prepared native catalog is required")
    native = json.loads((root / catalog["path"]).read_text())
    for name, expected in native["inputSHA256"].items():
        path = root / name
        if not path.resolve().is_relative_to(root.resolve()) or sha256(path) != expected:
            raise ValueError("Native preparation source changed after production: " + name)
    for artifact in native["artifacts"]:
        for library in artifact["libraries"]:
            binary = root / artifact["installPath"] / library["binary"]
            if (not binary.resolve().is_relative_to(root.resolve()) or
                    sha256(binary) != library["binarySHA256"]):
                raise ValueError("Installed native slice changed after production: " +
                                 artifact["target"] + "/" + library["binary"])
    return receipt, inputs


def create_archives(root, output, producer_receipt):
    root, output = Path(root).resolve(), Path(output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    state = {"schemaVersion": 1, "status": "NOT_RUN", "products": [], "commands": [],
             "createdAt": datetime.now(timezone.utc).isoformat(),
             "signing": "NOT_RUN", "export": "NOT_RUN", "physicalDevice": "NOT_RUN"}
    def run(argv, label, timeout=60, required=True):
        started = time.monotonic()
        log = output / (label + ".log")
        with log.open("wb") as stream:
            result, pid = run_owned_process(argv, root, stream, timeout)
        text = log.read_text(errors="replace")
        state["commands"].append({"operation": label, "argv": [str(v) for v in argv],
                                  "exit": result, "seconds": time.monotonic() - started,
                                  "pid": pid, "log": log.name, "logSHA256": sha256(log)})
        if result and required:
            raise RuntimeError(label + " failed; see retained archive log")
        return result, text
    def verify_closure(label):
        check = {"phase": label, "status": "VERIFYING"}
        state.setdefault("closureChecks", []).append(check)
        try:
            patch = subprocess.check_output(["git", "diff", "--binary", "HEAD"], cwd=root)
            patch_path = output / (label + "-source.patch")
            patch_path.write_bytes(patch)
            check["sourcePatch"] = {"path": patch_path.name, "bytes": len(patch),
                                    "sha256": sha256(patch_path)}
            if sha256(producer_receipt) != state["producerReceiptSHA256"]:
                raise ValueError("Host producer receipt changed during archiving")
            current, _ = verify_producer(root, producer_receipt)
            catalog = root / current["nativeCatalog"]["path"]
            run([sys.executable, "Scripts/SDK/native_artifacts.py", "verify",
                 "--catalog", catalog, "--assets", catalog.parent],
                label + "-native-artifacts", 600)
            check["status"] = "VERIFIED"
        except Exception as error:
            check.update(status="FAILED", error=str(error))
            raise
    try:
        producer, source_inputs = verify_producer(root, producer_receipt)
        state.update(sourceCommit=producer["sourceCommit"], producer=producer,
                     producerReceiptSHA256=sha256(producer_receipt),
                     sdkSourceInputs=source_inputs)
        _, sdk = run(["xcrun", "--sdk", "iphoneos", "--show-sdk-version"], "device-sdk")
        if int(sdk.strip().split(".")[0]) != 27:
            raise ValueError("The current stable iOS 27 SDK is required")
        _, xcode = run(["xcodebuild", "-version"], "xcode-version")
        _, swift = run(["xcrun", "swiftc", "--version"], "swift-version")
        state["toolchain"] = {"deviceSDK": sdk.strip(), "xcode": xcode.strip(), "swift": swift.strip()}
        prepare_archive_inputs(root, output, run)
        verify_closure("after-prepare")
        for role, scheme, bundle in PRODUCTS:
            product = {"role": role, "scheme": scheme, "bundleID": bundle, "status": "NOT_RUN"}
            state["products"].append(product)
            archive = root / "build/ReleaseArchives" / (scheme + ".xcarchive")
            archive.parent.mkdir(parents=True, exist_ok=True)
            if archive.exists():
                raise ValueError("Archive output already exists; keep prior evidence separate: " + str(archive))
            capacity_before = record_archive_capacity(root, output, role, "before-archive")
            product["capacity"] = [capacity_before]
            product["admission"] = admit_archive_phase(root, output, role, capacity_before)
            if product["admission"]["status"] != "ADMITTED_ESTIMATE":
                raise RuntimeError("Archive estimate exceeds current free space: " +
                    str(product["admission"]["requiredFreeBytes"]) + " estimated bytes required, " +
                    str(product["admission"]["observedFreeBytes"]) + " bytes observed free")
            code, _ = run(archive_arguments(root, scheme, archive), role + "-archive", 3300, required=False)
            capacity_after = record_archive_capacity(root, output, role, "after-archive", capacity_before)
            product["capacity"].append(capacity_after)
            if code:
                product["status"] = "EXECUTED_FAIL"
                continue
            product.update(archive_identity(archive, bundle, producer["hostArchive"]["sha256"]))
            tree = archive_tree(archive)
            tar_path = output / (scheme + ".xcarchive.tar.gz")
            with tarfile.open(tar_path, "w:gz", compresslevel=1, dereference=False) as packed:
                packed.add(archive, arcname=archive.name)
            verify_closure(role + "-after-archive")
            product.update(status="UNSIGNED_ARCHIVE_VERIFIED", archiveName=archive.name,
                           archiveFile=tar_path.name, archiveBytes=tar_path.stat().st_size,
                           archiveSHA256=sha256(tar_path), treeSHA256=tree_sha256(tree),
                           tree=tree)
            product["capacity"].append(record_archive_capacity(root, output, role, "after-packaging", capacity_after))
            # Preserve a completed product even if the next archive cannot finish.
            write_json(output / "unsigned-archives.json", state)
        state["status"] = "UNSIGNED_ARCHIVES_VERIFIED" if len(state["products"]) == len(PRODUCTS) and all(
            item["status"] == "UNSIGNED_ARCHIVE_VERIFIED" for item in state["products"]) else "ARCHIVE_FAILED"
    except Exception as error:
        state.update(status="ARCHIVE_FAILED", error=str(error))
    finally:
        write_json(output / "unsigned-archives.json", state)
        manifest = output / "unsigned-archives.json"
        (output / "unsigned-archives.sha256").write_text(sha256(manifest) + "  " + manifest.name + "\n")
    return 0 if state["status"] == "UNSIGNED_ARCHIVES_VERIFIED" else 1


def restore_link_modes(archive, entries):
    for item in entries:
        if item["kind"] != "symlink":
            continue
        path = archive / item["path"]
        if not path.is_symlink() or os.readlink(path) != item["target"]:
            raise ValueError("Transferred symlink target spelling changed: " + item["path"])
        if stat.S_IMODE(path.lstat().st_mode) != item["mode"]:
            lchmod = getattr(os, "lchmod", None)
            if callable(lchmod):
                lchmod(path, item["mode"])
            elif os.chmod in os.supports_follow_symlinks:
                os.chmod(path, item["mode"], follow_symlinks=False)
            else:
                raise ValueError("This filesystem cannot restore the original symlink mode: " + item["path"])
            if stat.S_IMODE(path.lstat().st_mode) != item["mode"]:
                raise ValueError("Original symlink mode was not restored: " + item["path"])


def restore_archives(manifest_path, manifest_sha256, expected_source, destination):
    """Authenticate the producer receipt and exact archive trees before any signing."""
    manifest_path, destination = Path(manifest_path), Path(destination)
    if not re.fullmatch(r"[0-9a-f]{64}", manifest_sha256 or "") or sha256(manifest_path) != manifest_sha256:
        raise ValueError("Unsigned archive manifest checksum differs from the producer")
    data = json.loads(manifest_path.read_text())
    if data.get("schemaVersion") != 1 or data.get("status") != "UNSIGNED_ARCHIVES_VERIFIED":
        raise ValueError("Unsigned archives did not complete successfully")
    if not re.fullmatch(r"[0-9a-f]{40}", expected_source or "") or data.get("sourceCommit") != expected_source:
        raise ValueError("Unsigned archives belong to a different source commit")
    expected = {role: (scheme, bundle) for role, scheme, bundle in PRODUCTS}
    records = data.get("products", [])
    if len(records) != len(expected) or {item.get("role") for item in records} != set(expected):
        raise ValueError("Unsigned archive manifest must contain both original products exactly once")
    destination.mkdir(parents=True, exist_ok=False)
    restored = {}
    for item in records:
        role = item["role"]
        scheme, bundle = expected[role]
        name = scheme + ".xcarchive"
        filename = name + ".tar.gz"
        if (item.get("scheme") != scheme or item.get("bundleID") != bundle or
                item.get("archiveName") != name or item.get("archiveFile") != filename or
                item.get("status") != "UNSIGNED_ARCHIVE_VERIFIED"):
            raise ValueError("Unsigned archive product identity changed")
        packed_path = manifest_path.parent / filename
        if packed_path.stat().st_size != item["archiveBytes"] or sha256(packed_path) != item["archiveSHA256"]:
            raise ValueError("Transferred archive checksum differs: " + role)
        with tarfile.open(packed_path, "r:gz") as packed:
            members = packed.getmembers()
            if not members or any(member.name.split("/")[0] != name for member in members):
                raise ValueError("Archive package has an unexpected root")
            def preserve_mode(member, target):
                # data_filter validates paths/links; retain the producer's original mode bits.
                safe = tarfile.data_filter(member, target)
                return safe.replace(name=member.name, mode=member.mode, linkname=member.linkname)
            packed.extractall(destination, filter=preserve_mode)
        archive = destination / name
        restore_link_modes(archive, item["tree"])
        tree = archive_tree(archive)
        if tree != item["tree"] or tree_sha256(tree) != item["treeSHA256"]:
            raise ValueError("Transferred archive structure, file modes, links or bytes changed")
        identity = archive_identity(archive, bundle, data["producer"]["hostArchive"]["sha256"])
        if any(item.get(key) != value for key, value in identity.items()):
            raise ValueError("Transferred archive metadata changed")
        restored[role] = {"path": archive, "record": item}
    return data, restored


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["create"])
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--producer-receipt", type=Path, required=True)
    options = parser.parse_args(argv)
    return create_archives(options.root, options.output, options.producer_receipt)


if __name__ == "__main__":
    sys.exit(main())
