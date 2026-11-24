#!/usr/bin/env python3
"""Publish/install the original prepared Hanlin native dependencies; never build them."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import platform
import plistlib
import posixpath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

REPOSITORY = "davidpovarsky/hanlin-ai"
ROOT = Path(__file__).resolve().parents[2]
TARGETS = {
    **{name: f"Packages/HanlinExpoRuntime/Artifacts/{name}.xcframework" for name in (
        "ReactNativeHeaders", "React", "ReactNativeDependencies", "hermesvm",
        "ExpoModulesJSI", "ExpoModulesCore", "ExpoModulesWorklets", "ExpoUI", "ExpoBrownfield")},
    "Libffi": "Packages/HanlinExpoNativeAPI/Artifacts/Libffi.xcframework",
    "TNSWidgets": "Packages/HanlinNativeScriptRuntime/Artifacts/TNSWidgets.xcframework",
    "NSCWinterTC": "Packages/HanlinNativeScriptRuntime/Artifacts/NSCWinterTC.xcframework",
    "NodeMobile": "Vendor/NodeMobile/NodeMobile.xcframework",
    "Python": "Vendor/Python/Python.xcframework",
}
SUPPORT_GROUPS = {
    "HanlinExpoHeaderSupport": {
        "targets": tuple(name for name in TARGETS if name not in ("TNSWidgets", "NSCWinterTC", "NodeMobile", "Python")),
        "paths": ("Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks",
                  "Packages/HanlinExpoRuntime/Artifacts/ReactModularHeaders"),
    },
    "HanlinExpoWidgetRuntimeSupport": {
        "targets": ("ExpoUI", "ExpoModulesCore"),
        "paths": ("Packages/HanlinExpoRuntime/Sources/ExpoWidgets/Resources/ExpoWidgets.bundle",),
    },
    "HanlinNativeScriptHostSupport": {
        "targets": ("TNSWidgets", "NSCWinterTC"),
        "paths": ("Packages/HanlinNativeScriptRuntime/Artifacts/native-api-usage.json",
                  "Packages/HanlinNativeScriptRuntime/Artifacts/dependency-closure.json",
                  "build/nativescript-metadata-tool/bin",
                  "build/nativescript-metadata-tool/provenance.json"),
    },
    "HanlinNodeHostSupport": {
        "targets": ("NodeMobile",), "paths": ("AI_HLY/RuntimeHostResources.zip",),
    },
    "HanlinPythonHostSupport": {
        "targets": ("Python",), "paths": ("Vendor/Python/Python-VERSIONS",),
    },
}
INPUTS = (
    "RuntimeDependencies.lock.json", "Scripts/Expo/dependency-lock.json",
    "Scripts/Expo/prepare-ios-dependencies.mjs",
    "Scripts/Expo/build-original-expo-source.mjs",
    "Scripts/Expo/build-original-widget-runtime.mjs",
    "Scripts/Expo/package-lock.json", "Scripts/Expo/babel.config.cjs",

    "Scripts/ExpoNativeAPI/dependency-lock.json",
    "Scripts/ExpoNativeAPI/prepare-ios-dependencies.mjs",
    "Scripts/NativeScript/dependency-lock.json", "Scripts/NativeScript/package-lock.json",
    "Scripts/NativeScript/prepare-ios-dependencies.mjs",
    "Scripts/NativeScript/build-metadata-tool.py",
    "Scripts/NativeScript/build-step-metadata-generator-wrapper.py",
    "Scripts/Runtime/prepare-runtime-core.sh",
)
MACHO = {b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf",
         b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
         b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}
SCHEMA_VERSION = 1


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def json_write(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def relative(value: str) -> PurePosixPath:
    path = PurePosixPath(value)
    if not value or "\\" in value or path.is_absolute() or any(p in ("", ".", "..") for p in value.split("/")):
        raise ValueError(f"Unsafe artifact path: {value!r}")
    return path


def inside(root: Path, path: Path) -> None:
    if not path.resolve().is_relative_to(root.resolve()):
        raise ValueError(f"Artifact escapes its root: {path}")


def framework_libraries(root: Path, target: str) -> list[dict]:
    if root.name != f"{target}.xcframework" or not root.is_dir():
        raise ValueError(f"Missing prepared {target}.xcframework at {root}")
    info = plistlib.loads((root / "Info.plist").read_bytes())
    libraries = info.get("AvailableLibraries", [])
    if not libraries:
        raise ValueError(f"No real XCFramework slices: {root}")
    platforms = set()
    result = []
    for item in libraries:
        identifier = str(relative(item["LibraryIdentifier"]))
        library_path = relative(item["LibraryPath"])
        library = root / identifier / library_path
        inside(root, library)
        if not library.exists():
            raise ValueError(f"Missing prepared library: {library}")
        if library.suffix == ".framework":
            metadata = library / "Info.plist"
            if not metadata.exists() and not metadata.is_symlink():
                metadata = library / "Resources" / "Info.plist"
            inside(library, metadata)
            framework_info = plistlib.loads(metadata.read_bytes())
            executable = framework_info.get("CFBundleExecutable", library.stem)
            relative(executable)
            # Versioned Catalyst frameworks declare their actual executable in
            # BinaryPath and need not contain a root-level executable alias.
            binary = (root / identifier / relative(item["BinaryPath"])
                      if "BinaryPath" in item else library / executable)
            inside(library, binary)
            if binary.name != executable:
                raise ValueError(f"Declared framework binary differs from CFBundleExecutable: {binary}")
        else:
            binary = library
        inside(root, binary)
        if not binary.is_file():
            raise ValueError(f"Missing native binary: {binary}")
        # ZIP symlinks retain their link bytes. Bind the catalog to the actual
        # regular executable member so verification hashes native bytes.
        binary = binary.resolve()
        with binary.open("rb") as stream:
            prefix = stream.read(8)
        if prefix[:4] not in MACHO and prefix != b"!<arch>\n":
            raise ValueError(f"Not a native Mach-O/static archive: {binary}")
        if binary.stat().st_size <= 8:
            raise ValueError(f"Empty native library: {binary}")
        archs = item.get("SupportedArchitectures", [])
        variant = item.get("SupportedPlatformVariant")
        if item.get("SupportedPlatform") == "ios" and "arm64" in archs:
            platforms.add(variant or "device")
        result.append({
            "identifier": identifier, "platform": item.get("SupportedPlatform"),
            "variant": variant, "architectures": archs,
            "binary": str(binary.relative_to(root.resolve())), "binarySHA256": digest(binary),
        })
    if not {"device", "simulator"}.issubset(platforms):
        raise ValueError(f"{target} must retain real arm64 iOS device and Simulator slices")
    return result


def source_inputs(root: Path) -> dict[str, str]:
    return {name: digest(root / name) for name in INPUTS if (root / name).is_file()}


def source_commit(root: Path) -> str:
    return subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()


def pinned_files(root: Path, names: tuple[str, ...], revision: str | None = None) -> tuple[str, dict[str, bytes]]:
    """Read exact Git blobs without requiring sparse inputs to be checked out."""
    revision = revision or source_commit(root)
    if source_commit(root) != revision:
        raise ValueError("Native preparation input revision changed")
    changed = subprocess.run(["git", "-C", str(root), "diff", "--quiet", "--no-ext-diff",
                              revision, "--", *names], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if changed.returncode:
        raise ValueError("Modified native preparation input: " + ", ".join(names))
    tree = subprocess.check_output(["git", "-C", str(root), "ls-tree", "-r", "-z", revision, "--", *names])
    entries = []
    for entry in tree.split(b"\0"):
        if not entry:
            continue
        metadata, name = entry.split(b"\t", 1)
        mode, kind, oid = metadata.split()
        name = str(relative(name.decode("utf-8")))
        if kind != b"blob" or mode not in (b"100644", b"100755"):
            raise ValueError("Native preparation input is not a regular Git file: " + name)
        entries.append((name, oid))
    raw = subprocess.check_output(["git", "-C", str(root), "cat-file", "--batch"],
                                  input=b"".join(oid + b"\n" for _, oid in entries))
    stream = io.BytesIO(raw)
    files = {}
    for name, oid in entries:
        header = stream.readline().split()
        if len(header) != 3 or header[:2] != [oid, b"blob"] or not header[2].isdigit():
            raise ValueError("Invalid pinned native preparation input: " + name)
        length = int(header[2])
        content = stream.read(length)
        if len(content) != length or stream.read(1) != b"\n":
            raise ValueError("Truncated pinned native preparation input: " + name)
        current = root / name
        inside(root, current)
        if current.is_symlink() or (current.exists() and
                (not current.is_file() or current.read_bytes() != content)):
            raise ValueError("Modified materialized native preparation input: " + name)
        files[name] = content
    if stream.read() or source_commit(root) != revision:
        raise ValueError("Native preparation input revision or blob inventory changed")
    return revision, files


def verify_source_inputs(catalog: dict, root: Path) -> str:
    expected = catalog.get("inputSHA256")
    if (not isinstance(expected, dict) or set(expected) != set(INPUTS)
            or any(not isinstance(value, str) or not re.fullmatch(r"[a-f0-9]{64}", value)
                   for value in expected.values())):
        raise ValueError("Native catalog preparation inputs do not match the complete declared set")
    revision, files = pinned_files(root, INPUTS)
    if set(files) != set(INPUTS):
        raise ValueError("Pinned native preparation input inventory differs")
    mismatched = [name for name in INPUTS if hashlib.sha256(files[name]).hexdigest() != expected[name]]
    if mismatched:
        raise ValueError("Native preparation input differs from published catalog: " + ", ".join(mismatched))
    return revision


def validate_node_support(root: Path, archive: Path, revision: str) -> None:
    # Reuse the original source/archive policy, including dependency patches and
    # exact module inventory. Only small tracked sources are materialized; no npm,
    # native builder, frozen runtime extraction or second archive schema is used.
    validator = "Scripts/Runtime/runtime_host_archive.py"
    host = "AI_HLY/Downstream/RuntimeCore/Node/Host"
    _, files = pinned_files(root, (validator, host), revision)
    with tempfile.TemporaryDirectory(prefix="hanlin-sdk-source-") as temporary:
        source = Path(temporary)
        for name, content in files.items():
            destination = source / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(content)
        result = subprocess.run([sys.executable, "-B", str(source / validator), "validate",
            str(archive.resolve(strict=True)), "--source-root", str(source / host)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if result.returncode:
            raise ValueError("Node Host support differs from pinned source: " +
                             (result.stderr.strip() or result.stdout.strip()))
    if source_commit(root) != revision:
        raise ValueError("Native preparation input revision changed")


def support_paths(root: Path, selected: list[str]) -> tuple[dict[str, list[str]], dict | None]:
    groups = {name: list(group["paths"]) for name, group in SUPPORT_GROUPS.items()
              if set(group["targets"]).intersection(selected)}
    provenance = None
    if "HanlinNativeScriptHostSupport" in groups:
        provenance = json.loads((root / "build/nativescript-metadata-tool/provenance.json").read_text())
        architecture = provenance["architecture"]
        if architecture not in ("arm64", "x86_64"):
            raise ValueError("Unsupported prepared metadata-tool architecture")
        tool = root / "build/nativescript-metadata-tool/bin/objc-metadata-generator"
        if digest(tool) != provenance["generatorSHA256"]:
            raise ValueError("Prepared NativeScript metadata tool checksum mismatch")
        if digest(root / "Scripts/NativeScript/build-metadata-tool.py") != provenance["patchSourceSHA256"]:
            raise ValueError("Prepared NativeScript metadata tool does not match its original source")
        launchers = [
            f"Scripts/NativeScript/node_modules/@nativescript/ios/framework/internal/metadata-generator-{architecture}/bin/{name}"
            for name in ("build-step-metadata-generator.py", "build-step-metadata-generator-upstream.py")
        ]
        groups["HanlinNativeScriptHostSupport"] += launchers
        if "HANLIN_METADATA_WRAPPER_V1" not in (root / launchers[0]).read_text():
            raise ValueError("NativeScript launcher has not received Hanlin's original wrapper")
    missing = [path for paths in groups.values() for path in paths if not (root / path).exists()]
    if missing:
        raise ValueError("Missing prepared host support: " + ", ".join(missing))
    if "Python" in selected:
        python = root / TARGETS["Python"]
        if 'FRAMEWORK_BUNDLE_ID="org.python.runtime.module-$FRAMEWORK_MODULE_ID"' not in (python / "build/utils.sh").read_text():
            raise ValueError("Run original prepare-runtime-core.sh before exporting Python host support")
        if plistlib.loads((python / "build/iOS-dylib-Info-template.plist").read_bytes()).get("CFBundlePackageType") != "FMWK":
            raise ValueError("Prepared Python dynamic modules must retain the original FMWK patch")
    return groups, provenance

def ignored(path: Path) -> bool:
    return path.name in (".DS_Store", ".artifact-manifest.json", "__MACOSX") or path.name.startswith("._")


def entries(source: Path):
    """Yield the original tree without following directory symlinks."""
    yield source
    if source.is_dir() and not source.is_symlink():
        for child in sorted(source.iterdir(), key=lambda p: p.name):
            if not ignored(child):
                yield from entries(child)


def archive_paths(output: Path, roots: list[tuple[Path, PurePosixPath]]) -> None:
    """Stable ZIP layout, file permissions and internal symlinks; no timestamp receipts."""
    temp = output.with_suffix(".zip.partial")
    try:
        with zipfile.ZipFile(temp, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            written = set()
            for source, name in roots:
                if not source.exists():
                    raise ValueError(f"Missing prepared input: {source}")
                for item in entries(source):
                    arcname = name / item.relative_to(source)
                    value = str(arcname)
                    relative(value)
                    if value in written:
                        raise ValueError(f"Duplicate archive entry: {value}")
                    written.add(value)
                    mode = item.lstat().st_mode
                    if stat.S_ISLNK(mode):
                        inside(source if source.is_dir() else source.parent, item)
                        if not item.exists():
                            raise ValueError(f"Broken artifact symlink: {item}")
                    elif not stat.S_ISDIR(mode) and not stat.S_ISREG(mode):
                        raise ValueError(f"Unsupported special artifact file: {item}")
                    info = zipfile.ZipInfo(value + ("/" if stat.S_ISDIR(mode) else ""), (1980, 1, 1, 0, 0, 0))
                    info.create_system = 3
                    info.external_attr = (mode & 0xFFFF) << 16
                    info.compress_type = zipfile.ZIP_DEFLATED
                    if stat.S_ISDIR(mode):
                        archive.writestr(info, b"")
                    elif stat.S_ISLNK(mode):
                        archive.writestr(info, os.readlink(item).encode())
                    else:
                        with item.open("rb") as source_stream, archive.open(info, "w", force_zip64=True) as target:
                            shutil.copyfileobj(source_stream, target, length=1024 * 1024)
        temp.replace(output)
    finally:
        temp.unlink(missing_ok=True)


def archive_members(archive: zipfile.ZipFile, expected_root: str) -> list[zipfile.ZipInfo]:
    relative(expected_root)
    members = archive.infolist()
    seen = set()
    symlinks = set()
    for item in members:
        name = item.filename.rstrip("/")
        path = relative(name)
        if path.parts[0] != expected_root or name in seen:
            raise ValueError(f"Unexpected or duplicate archive entry: {name}")
        seen.add(name)
        mode = item.external_attr >> 16
        if stat.S_ISLNK(mode):
            target = archive.read(item).decode()
            if not target or target.startswith("/") or "\\" in target:
                raise ValueError(f"Unsafe artifact symlink: {name}")
            resolved = PurePosixPath(posixpath.normpath(str(path.parent / target)))
            if resolved.parts[0] != expected_root or ".." in resolved.parts:
                raise ValueError(f"Artifact symlink escapes archive: {name}")
            symlinks.add(path)
    for item in members:
        if any(parent in symlinks for parent in PurePosixPath(item.filename).parents):
            raise ValueError(f"Archive entry descends through a symlink: {item.filename}")
    return members


def extract_verified(archive_path: Path, checksum: str, destination: Path, expected_root: str) -> None:
    if not re.fullmatch(r"[a-f0-9]{64}", checksum) or digest(archive_path) != checksum:
        raise ValueError(f"Artifact checksum mismatch: {archive_path.name}")
    with zipfile.ZipFile(archive_path) as archive:
        members = archive_members(archive, expected_root)
        links = []
        for item in members:
            output = destination / item.filename.rstrip("/")
            inside(destination, output)
            mode = item.external_attr >> 16
            if item.is_dir():
                output.mkdir(parents=True, exist_ok=True)
            elif stat.S_ISLNK(mode):
                links.append((output, archive.read(item).decode()))
            else:
                output.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(item) as source, output.open("xb") as target:
                    shutil.copyfileobj(source, target, length=1024 * 1024)
                output.chmod((mode & 0o777) or 0o644)
        for output, target in links:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.symlink_to(target)
        # A framework's root aliases may precede Versions/Current in the ZIP.
        # Validate the complete link graph only after every internal link exists.
        for output, _ in links:
            inside(destination, output)
            if not output.exists():
                raise ValueError(f"Broken installed symlink: {output}")


def artifact_record(target: str, output: Path, libraries: list[dict]) -> dict:
    return {"target": target, "kind": "xcframework", "installPath": TARGETS[target],
            "archive": output.name, "checksum": digest(output), "bytes": output.stat().st_size,
            "root": f"{target}.xcframework", "libraries": libraries}


def export(root: Path, output: Path, selected: list[str] | None, include_support: bool, prepared_root: Path | None = None) -> dict:
    prepared_root = prepared_root or root
    selected = selected or list(TARGETS)
    unknown = set(selected) - TARGETS.keys()
    if unknown:
        raise ValueError("Unknown native targets: " + ", ".join(sorted(unknown)))
    # Validate everything before producing a publication candidate.
    validated = {name: framework_libraries(prepared_root / TARGETS[name], name) for name in selected}
    support, tool_provenance = support_paths(prepared_root, selected) if include_support else ({}, None)
    if "HanlinNodeHostSupport" in support:
        # Original preparation already synchronizes source-only Host changes over
        # the verified frozen closure. Validation never invokes a builder.
        subprocess.run([sys.executable, str(root / "Scripts/Runtime/runtime_host_archive.py"),
                        "validate", str(prepared_root / "AI_HLY/RuntimeHostResources.zip"),
                        "--source-root", str(root / "AI_HLY/Downstream/RuntimeCore/Node/Host")], check=True)
    output.mkdir(parents=True, exist_ok=True)
    artifacts = []
    for name in selected:
        path = output / f"{name}.xcframework.zip"
        archive_paths(path, [(prepared_root / TARGETS[name], PurePosixPath(f"{name}.xcframework"))])
        artifacts.append(artifact_record(name, path, validated[name]))
        print(f"Exported {path.name} {artifacts[-1]['checksum']}", flush=True)
    support_artifacts = []
    for name, paths in support.items():
        path = output / f"{name}.zip"
        archive_paths(path, [(prepared_root / source, PurePosixPath(name) / source) for source in paths])
        support_artifacts.append({
            "target": name, "kind": "host-support", "root": name,
            "archive": path.name, "checksum": digest(path), "bytes": path.stat().st_size,
            "installPaths": paths, "requiredBy": list(SUPPORT_GROUPS[name]["targets"]),
            "metadataTool": tool_provenance if name == "HanlinNativeScriptHostSupport" else None,
        })
    identity = hashlib.sha256(json.dumps({
        item["target"]: item["checksum"] for item in [*artifacts, *support_artifacts]
    }, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    tag = f"sdk-native-v1-{identity}"
    for item in [*artifacts, *support_artifacts]:
        item["url"] = f"https://github.com/{REPOSITORY}/releases/download/{tag}/{item['archive']}"
    catalog = {
        "schemaVersion": SCHEMA_VERSION, "state": "prepared", "repository": REPOSITORY,
        "sourceCommit": source_commit(root), "releaseTag": tag, "contentSHA256": identity,
        "artifacts": artifacts, "supportArtifacts": support_artifacts,
        "requiredTargets": list(TARGETS), "missingTargets": sorted(set(TARGETS) - set(selected)),
        "inputSHA256": source_inputs(root),
        "scope": "full" if len(selected) == len(TARGETS) and len(support) == len(SUPPORT_GROUPS) else "selected-targets",
        "acceptance": {
            "nativeSlices": "validated-existing-binaries",
            "appleBuild": "reuse-producer-evidence; this exporter does not build or test runtimes",
            "ordinaryVersionDependency": "requires original host acceptance; prepared Expo header paths and host build phases need integration",
        },
    }
    json_write(output / "native-artifacts.json", catalog)
    return catalog


def load_catalog(path: Path) -> dict:
    catalog = json.loads(path.read_text())
    if catalog.get("schemaVersion") != SCHEMA_VERSION or catalog.get("repository") != REPOSITORY:
        raise ValueError("Unsupported native artifact catalog")
    if catalog.get("state") == "unpublished":
        raise ValueError("Native assets have not been published; export the original prepared Apple dependencies first")
    if not re.fullmatch(r"sdk-native-v1-[a-f0-9]{64}", catalog.get("releaseTag", "")):
        raise ValueError("Catalog has no content-addressed publication")
    records = [*catalog.get("artifacts", []), *catalog.get("supportArtifacts", [])]
    if not records or len({x["target"] for x in records}) != len(records):
        raise ValueError("Missing or duplicate native artifact records")
    for item in records:
        if not re.fullmatch(r"[a-f0-9]{64}", item.get("checksum", "")):
            raise ValueError("Missing native artifact checksum")
        relative(item["archive"])
        if "/" in item["archive"] or not item["archive"].endswith(".zip"):
            raise ValueError("Artifact filename must be a ZIP basename")
        expected = f"https://github.com/{REPOSITORY}/releases/download/{catalog['releaseTag']}/{item['archive']}"
        if item.get("url") != expected:
            raise ValueError("Artifact URL does not match immutable publication identity")
        if item["kind"] == "xcframework":
            if TARGETS.get(item["target"]) != item["installPath"] or item["root"] != f"{item['target']}.xcframework":
                raise ValueError("Unexpected framework install location")
        elif item["kind"] == "host-support":
            if item["target"] not in SUPPORT_GROUPS or item["root"] != item["target"]:
                raise ValueError("Unexpected host support identity")
            for name in item["installPaths"]:
                relative(name)
        else:
            raise ValueError("Unexpected artifact kind")
    actual = hashlib.sha256(json.dumps({
        item["target"]: item["checksum"] for item in records
    }, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    if catalog["releaseTag"] != f"sdk-native-v1-{actual}":
        raise ValueError("Catalog content identity mismatch")
    return catalog


def verify(catalog: dict, assets: Path) -> None:
    for item in [*catalog["artifacts"], *catalog["supportArtifacts"]]:
        path = assets / item["archive"]
        if digest(path) != item["checksum"] or path.stat().st_size != item["bytes"]:
            raise ValueError(f"Artifact checksum or size mismatch: {path}")
        with zipfile.ZipFile(path) as archive:
            archive_members(archive, item["root"])
            if item["kind"] == "xcframework":
                plistlib.loads(archive.read(f"{item['root']}/Info.plist"))
                for library in item["libraries"]:
                    with archive.open(f"{item['root']}/{library['binary']}") as stream:
                        if hashlib.file_digest(stream, "sha256").hexdigest() != library["binarySHA256"]:
                            raise ValueError(f"Native slice changed: {item['target']}/{library['identifier']}")
    print("Verified every ZIP checksum, archive path and native slice hash.", flush=True)


def download(item: dict, cache: Path) -> Path:
    cache.mkdir(parents=True, exist_ok=True)
    path = cache / f"{item['checksum']}-{item['archive']}"
    if path.exists() and digest(path) == item["checksum"]:
        return path
    temporary = path.with_suffix(".partial")
    try:
        request = urllib.request.Request(item["url"], headers={"User-Agent": "HanlinSDK-native-artifacts/1"})
        with urllib.request.urlopen(request, timeout=60) as source, temporary.open("wb") as target:
            shutil.copyfileobj(source, target, length=1024 * 1024)
        if digest(temporary) != item["checksum"] or temporary.stat().st_size != item["bytes"]:
            raise ValueError(f"Downloaded artifact checksum/size mismatch: {item['archive']}")
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)
    return path


def selected_records(catalog: dict, targets: list[str] | None, support: bool) -> list[dict]:
    selected = set(targets or [item["target"] for item in catalog["artifacts"]])
    available = {item["target"] for item in catalog["artifacts"]}
    if not selected.issubset(available):
        raise ValueError("Requested targets have not been published")
    records = [item for item in catalog["artifacts"] if item["target"] in selected]
    if support:
        required_groups = {name for name, group in SUPPORT_GROUPS.items() if set(group["targets"]).intersection(selected)}
        available_groups = {item["target"] for item in catalog["supportArtifacts"]}
        if not required_groups.issubset(available_groups):
            raise ValueError("Selected host support has not been published")
        records += [item for item in catalog["supportArtifacts"] if item["target"] in required_groups]
    return records


def verify_installed_source(catalog: dict, root: Path, targets: list[str] | None, support: bool) -> dict:
    if catalog["state"] != "published":
        raise ValueError("Only a published, readback-verified catalog can be checked")
    revision = verify_source_inputs(catalog, root)
    records = selected_records(catalog, targets, support)
    node = any(item["target"] == "HanlinNodeHostSupport" for item in records)
    if node:
        validate_node_support(root, root / "AI_HLY/RuntimeHostResources.zip", revision)
    return {"sourceCommit": revision, "declaredPreparationInputs": len(INPUTS),
            "nodeHostSourceValidated": node}


def install(catalog: dict, root: Path, cache: Path, targets: list[str] | None, support: bool) -> None:
    if catalog["state"] != "published":
        raise ValueError("Only a published, readback-verified catalog can be installed")
    revision = verify_source_inputs(catalog, root)
    records = selected_records(catalog, targets, support)
    receipt_path = root / ".hanlin-sdk/native-artifacts-installed.json"
    receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else {"paths": {}}
    for item in records:
        names = [item["installPath"]] if item["kind"] == "xcframework" else item["installPaths"]
        if all(receipt["paths"].get(name) == item["checksum"] and (root / name).exists() for name in names):
            if item["target"] == "HanlinNodeHostSupport":
                validate_node_support(root, root / "AI_HLY/RuntimeHostResources.zip", revision)
            continue
        archive = download(item, cache)
        with tempfile.TemporaryDirectory(prefix="hanlin-sdk-install-", dir=root) as temporary:
            temp = Path(temporary)
            extract_verified(archive, item["checksum"], temp, item["root"])
            if item["kind"] == "xcframework":
                framework_libraries(temp / item["root"], item["target"])
            if item["target"] == "HanlinNodeHostSupport":
                validate_node_support(root, temp / item["root"] / "AI_HLY/RuntimeHostResources.zip", revision)
            for name in names:
                destination = root / name
                inside(root, destination)
                if destination.exists() and name not in receipt["paths"]:
                    raise ValueError(f"Refusing to replace unmanaged prepared input: {destination}")
                source = temp / item["root"]
                if item["kind"] == "host-support":
                    source /= name
                if not source.exists():
                    raise ValueError(f"Published support is missing {name}")
                destination.parent.mkdir(parents=True, exist_ok=True)
                backup = temp / ("backup-" + hashlib.sha256(name.encode()).hexdigest())
                if destination.exists():
                    destination.rename(backup)
                try:
                    source.rename(destination)
                except Exception:
                    if backup.exists():
                        backup.rename(destination)
                    raise
                receipt["paths"][name] = item["checksum"]
                # Save each completed replacement so an interrupted install can resume.
                json_write(receipt_path, receipt)
    if source_commit(root) != revision:
        raise ValueError("Native preparation input revision changed")
    receipt["releaseTag"] = catalog["releaseTag"]
    json_write(receipt_path, receipt)


def gh(*arguments: str) -> str:
    return subprocess.check_output(["gh", *arguments], text=True).strip()


def publish(catalog_path: Path, assets: Path, allow_selected: bool) -> dict:
    catalog = load_catalog(catalog_path)
    verify(catalog, assets)
    if catalog["scope"] != "full" and not allow_selected:
        raise ValueError("A selected-target publication requires --allow-selected-targets")
    tag = catalog["releaseTag"]
    lookup = subprocess.run(["gh", "api", f"repos/{REPOSITORY}/releases/tags/{tag}"],
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if lookup.returncode:
        if "404" not in lookup.stderr:
            raise RuntimeError(lookup.stderr.strip())
        gh("release", "create", tag, "--repo", REPOSITORY, "--target", catalog["sourceCommit"],
           "--title", f"Hanlin SDK native dependencies {catalog['contentSHA256'][:12]}",
           "--notes", "Original prepared Hanlin native binaries and shared host support. No runtime was rebuilt by this publication.")
        remote = json.loads(gh("api", f"repos/{REPOSITORY}/releases/tags/{tag}"))
    else:
        remote = json.loads(lookup.stdout)
    existing = {item["name"]: item for item in remote["assets"]}
    records = [*catalog["artifacts"], *catalog["supportArtifacts"]]
    for item in records:
        if item["archive"] in existing:
            asset = existing[item["archive"]]
            expected = "sha256:" + item["checksum"]
            if asset.get("digest") != expected or asset["size"] != item["bytes"]:
                raise ValueError(f"Refusing to overwrite immutable release asset {item['archive']}")
        else:
            gh("release", "upload", tag, str(assets / item["archive"]), "--repo", REPOSITORY)
    # Read the exact published download URLs, independently of the gh upload path.
    with tempfile.TemporaryDirectory(prefix="hanlin-sdk-readback-") as temporary:
        for item in records:
            readback = download(item, Path(temporary))
            readback.unlink()
    catalog["state"] = "published"
    json_write(catalog_path, catalog)
    remote = json.loads(gh("api", f"repos/{REPOSITORY}/releases/tags/{tag}"))
    catalog_assets = [item for item in remote["assets"] if item["name"] == "native-artifacts.json"]
    if catalog_assets:
        request = urllib.request.Request(catalog_assets[0]["browser_download_url"])
        with urllib.request.urlopen(request, timeout=30) as response:
            existing_catalog = json.loads(response.read())
        if (existing_catalog.get("inputSHA256") != catalog["inputSHA256"] or
            existing_catalog.get("artifacts") != catalog["artifacts"] or
            existing_catalog.get("supportArtifacts") != catalog["supportArtifacts"]):
            raise ValueError("Existing immutable native-artifacts.json differs")
        # Reuse the original producer commit when unchanged bytes are exported
        # from a later source-only commit; never replace an immutable asset.
        catalog = existing_catalog
        json_write(catalog_path, catalog)
    else:
        gh("release", "upload", tag, str(catalog_path), "--repo", REPOSITORY)
    return catalog


def host_stage(root: Path, operation: str) -> None:
    if platform.system() != "Darwin":
        raise ValueError("Original host staging requires an Apple Xcode build environment")
    environment = os.environ.copy()
    if operation == "host-python":
        framework = root / TARGETS["Python"]
        helper = framework / "build/utils.sh"
        if not helper.is_file():
            raise ValueError("Install the published Python native dependency first")
        if not environment.get("EXPANDED_CODE_SIGN_IDENTITY"):
            environment["EXPANDED_CODE_SIGN_IDENTITY"] = "-"
            environment["EXPANDED_CODE_SIGN_IDENTITY_NAME"] = "Ad Hoc"
        subprocess.run(["/bin/bash", "-e", "-c", 'source "$1"; install_python "$2"',
                        "hanlin-sdk-python", str(helper), str(framework)], env=environment, check=True)
    else:
        architecture = platform.machine()
        generator = root / f"Scripts/NativeScript/node_modules/@nativescript/ios/framework/internal/metadata-generator-{architecture}/bin/build-step-metadata-generator.py"
        if not generator.is_file():
            raise ValueError(f"Install matching NativeScript host support for {architecture}")
        target = environment.get("CURRENT_ARCH", "")
        if not target or target == "undefined_arch":
            target = environment.get("ARCHS", "").split(" ")[0]
        if not target:
            raise ValueError("Missing Xcode target architecture")
        # All host build/output/SDK paths remain Xcode's absolute values. Only
        # original SDK source/tool lookup uses this installed checkout.
        environment["SRCROOT"] = str(root)
        subprocess.run([sys.executable, str(generator), target], cwd=generator.parent,
                       env=environment, check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    command = commands.add_parser("inventory", help="Report missing prepared files without creating stand-ins")
    command.add_argument("--root", type=Path, default=ROOT)
    command = commands.add_parser("export", help="Package already-prepared original XCFrameworks and host support")
    command.add_argument("--root", type=Path, default=ROOT)
    command.add_argument("--output", type=Path, required=True)
    command.add_argument("--prepared-root", type=Path, help="Optional original prepared layout separate from source checkout")
    command.add_argument("--targets", nargs="+", choices=list(TARGETS))
    command.add_argument("--without-host-support", action="store_true")
    for name in ("verify", "publish"):
        command = commands.add_parser(name)
        command.add_argument("--catalog", type=Path, required=True)
        command.add_argument("--assets", type=Path, required=True)
        if name == "publish":
            command.add_argument("--allow-selected-targets", action="store_true")
    for name in ("install", "verify-source"):
        command = commands.add_parser(name, help="Install or verify published native source in a pinned SDK checkout")
        command.add_argument("--catalog", type=Path, default=ROOT / "docs/native-artifacts.json")
        command.add_argument("--root", type=Path, default=ROOT)
        if name == "install":
            command.add_argument("--cache", type=Path, required=True)
        command.add_argument("--targets", nargs="+", choices=list(TARGETS))
        command.add_argument("--without-host-support", action="store_true")
    command = commands.add_parser("swift-targets", help="Print validated URL/checksum binary-target declarations")
    command.add_argument("--catalog", type=Path, default=ROOT / "docs/native-artifacts.json")
    for name in ("host-python", "host-nativescript"):
        command = commands.add_parser(name, help="Invoke the original shared host build phase")
        command.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    if hasattr(args, "root"):
        args.root = args.root.resolve(strict=True)
    if args.command == "inventory":
        result = {"requiredTargets": TARGETS, "availableTargets": [], "missingTargets": [],
                  "sourceCommit": source_commit(args.root), "inputSHA256": source_inputs(args.root)}
        for target, path in TARGETS.items():
            key = "availableTargets" if (args.root / path / "Info.plist").is_file() else "missingTargets"
            result[key].append(target)
        print(json.dumps(result, indent=2))
    elif args.command == "export":
        export(args.root, args.output, args.targets, not args.without_host_support, args.prepared_root)
    elif args.command == "verify":
        verify(load_catalog(args.catalog), args.assets)
    elif args.command == "publish":
        publish(args.catalog, args.assets, args.allow_selected_targets)
    elif args.command == "install":
        install(load_catalog(args.catalog), args.root, args.cache, args.targets, not args.without_host_support)
    elif args.command == "verify-source":
        print(json.dumps(verify_installed_source(load_catalog(args.catalog), args.root,
              args.targets, not args.without_host_support), sort_keys=True))
    elif args.command == "swift-targets":
        catalog = load_catalog(args.catalog)
        if catalog["state"] != "published":
            raise ValueError("Remote declarations require a published catalog")
        for item in catalog["artifacts"]:
            print(f'.binaryTarget(name: "{item["target"]}", url: "{item["url"]}", checksum: "{item["checksum"]}"),')
    else:
        host_stage(args.root, args.command)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit(f"Hanlin native artifacts: {error}") from error
