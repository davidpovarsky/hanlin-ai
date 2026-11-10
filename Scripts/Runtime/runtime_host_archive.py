"""Keep source Host modules and their locked dependencies in one verified archive."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tempfile
import zipfile

REPOSITORY = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = REPOSITORY / "AI_HLY/Downstream/RuntimeCore/Node/Host"

def canonical_name(name: str) -> str:
    while name.startswith("./"):
        name = name[2:]
    if name.startswith("/") or ".." in PurePosixPath(name).parts:
        raise ValueError("Invalid Host archive path")
    return name

def validate_archive(archive: Path, source: Path, *, check_sources: bool = False) -> list[str]:
    errors = []
    try:
        manifest = json.loads((source / "package.json").read_text(encoding="utf-8"))
        lock = json.loads((source / "package-lock.json").read_text(encoding="utf-8"))
        with zipfile.ZipFile(archive) as packed:
            entries = {}
            for entry in packed.infolist():
                if entry.is_dir():
                    continue
                name = canonical_name(entry.filename)
                if name in entries:
                    raise ValueError("Ambiguous Host archive entry: " + name)
                entries[name] = entry
            def read(name):
                return packed.read(entries[name])
            if "node_modules/pegjs" not in lock.get("packages", {}) and any(name.startswith("node_modules/pegjs/") for name in entries):
                errors.append("Build-only grammar compiler must not ship in the mobile Host archive")
            if json.loads(read("package.json")) != manifest:
                errors.append("Host package.json differs from current source")
            if json.loads(read("package-lock.json")) != lock:
                errors.append("Host package-lock.json differs from current source")
            for name, version in manifest["dependencies"].items():
                key = "node_modules/" + name
                declared = lock["packages"].get(key, {})
                if declared.get("version") != version:
                    errors.append("Host lock/direct dependency mismatch: " + name)
                metadata = json.loads(read(key + "/package.json"))
                if metadata.get("version") != version:
                    errors.append("Host archive dependency version mismatch: " + name)
            patch_manifest = source / "host-dependency-patches.json"
            if patch_manifest.is_file():
                patches = json.loads(patch_manifest.read_text(encoding="utf-8"))
                if json.loads(read("host-dependency-patches.json")) != patches:
                    errors.append("Host dependency patch manifest differs from current source")
                for license in patches.get("licenses", []):
                    name = canonical_name(license["path"])
                    if hashlib.sha256((source / name).read_bytes()).hexdigest() != license["sha256"]:
                        errors.append("Host source license digest mismatch: " + name)
                    if hashlib.sha256(read(name)).hexdigest() != license["sha256"]:
                        errors.append("Host archive license digest mismatch: " + name)
                for patch in patches["files"]:
                    name = canonical_name(patch["path"])
                    if not name.startswith("node_modules/"):
                        raise ValueError("Invalid Host dependency patch path")
                    if hashlib.sha256(read(name)).hexdigest() != patch["patchedSHA256"]:
                        errors.append("Host dependency patch digest mismatch: " + name)
            if check_sources:
                expected = {path.name: path.read_bytes() for path in source.glob("*.mjs")}
                actual = {name for name in entries if "/" not in name and name.endswith(".mjs")}
                if actual != set(expected):
                    errors.append("Host module inventory differs from current source")
                for name in actual & set(expected):
                    if read(name) != expected[name]:
                        errors.append("Host module differs from current source: " + name)
    except (OSError, KeyError, ValueError, zipfile.BadZipFile) as error:
        errors.append("Invalid/incomplete Host archive: " + str(error))
    return errors

def synchronize_archive(archive: Path, source: Path, builder) -> str:
    if validate_archive(archive, source):
        built = builder()
        errors = validate_archive(built, source, check_sources=True)
        if errors:
            raise RuntimeError("Rebuilt Host failed validation: " + "; ".join(errors))
        if built.resolve() != archive.resolve():
            shutil.copyfile(built, archive)
        return "rebuilt locked dependencies and modules"
    if not validate_archive(archive, source, check_sources=True):
        return "verified existing dependencies and modules"
    descriptor, temporary_name = tempfile.mkstemp(prefix="host-sync-", suffix=".zip", dir=archive.parent)
    os.close(descriptor)
    temporary = Path(temporary_name)
    try:
        with zipfile.ZipFile(archive) as original, zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED) as updated:
            for entry in original.infolist():
                name = canonical_name(entry.filename)
                if "/" not in name and name.endswith(".mjs"):
                    continue
                updated.writestr(entry, original.read(entry))
            for path in sorted(source.glob("*.mjs")):
                updated.writestr(path.name, path.read_bytes())
        errors = validate_archive(temporary, source, check_sources=True)
        if errors:
            raise RuntimeError("Updated Host failed validation: " + "; ".join(errors))
        os.replace(temporary, archive)
    finally:
        temporary.unlink(missing_ok=True)
    return "updated source modules with unchanged locked dependencies"

def input_hash(source: Path, node_fingerprint: str) -> str:
    digest = hashlib.sha256(json.dumps(json.loads(node_fingerprint), sort_keys=True).encode())
    files = []
    for directory, subdirectories, names in os.walk(source):
        subdirectories[:] = sorted(name for name in subdirectories if name not in {"node_modules", ".git"})
        for name in sorted(names):
            if name != ".DS_Store":
                path = Path(directory) / name
                files.append((path.relative_to(source).as_posix(), path))
    files += [("build/prepare-runtime-host.sh", Path(__file__).with_name("prepare-runtime-host.sh")),
              ("build/runtime_host_archive.py", Path(__file__)),
              ("build/generate-yarn-unicode-patch.mjs", Path(__file__).with_name("generate-yarn-unicode-patch.mjs")),
              ("build/generate-yarn-multiline-patch.mjs", Path(__file__).with_name("generate-yarn-multiline-patch.mjs"))]
    for name in ("package.json", "package-lock.json"):
        files.append(("build/HostGrammarTools/" + name, Path(__file__).with_name("HostGrammarTools") / name))
    fixture_root = REPOSITORY / "AI_HLYTests/Fixtures/RuntimeNetworkFixtures.bundle"
    for path in sorted(fixture_root.rglob("*")):
        if path.is_file():
            files.append(("tests/RuntimeNetworkFixtures/" + path.relative_to(fixture_root).as_posix(), path))
    for name, path in sorted(files):
        digest.update(name.encode() + b"\0" + hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()

def reusable_prepared_archive(output: Path, source: Path, fingerprint: str) -> bool:
    try:
        archive = output / "RuntimeHostResources.zip"
        metadata = json.loads((output / "host-metadata.json").read_text(encoding="utf-8"))
        return (metadata.get("sourceInputsHash") == input_hash(source, fingerprint)
                and metadata.get("archiveSha256") == hashlib.sha256(archive.read_bytes()).hexdigest()
                and metadata.get("tests") == "passed"
                and metadata.get("jitlessArchiveSmoke") == "passed"
                and not validate_archive(archive, source, check_sources=True))
    except (OSError, ValueError):
        return False

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["validate", "sync", "fingerprint", "reuse"])
    parser.add_argument("path", nargs="?", type=Path)
    parser.add_argument("--source-root", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--node-fingerprint")
    options = parser.parse_args()
    source = options.source_root
    if options.command == "fingerprint":
        print(input_hash(source, options.node_fingerprint))
        return 0
    if options.command == "reuse":
        return 0 if reusable_prepared_archive(options.path, source, options.node_fingerprint) else 1
    if options.command == "validate":
        errors = validate_archive(options.path, source, check_sources=True)
        if errors:
            print("; ".join(errors), file=sys.stderr)
        return 1 if errors else 0
    def build():
        subprocess.run(["bash", str(Path(__file__).with_name("prepare-runtime-host.sh"))], cwd=REPOSITORY, check=True)
        return REPOSITORY / "build/runtime-host/RuntimeHostResources.zip"
    print("Runtime Host: " + synchronize_archive(options.path, source, build))
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print("Runtime Host preparation failed: " + str(error), file=sys.stderr)
        sys.exit(1)
