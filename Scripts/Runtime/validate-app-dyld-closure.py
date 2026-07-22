#!/usr/bin/env python3
"""Validate the complete Mach-O/dyld dependency closure of an Apple app bundle."""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Protocol, Sequence


MACHO_MAGICS = {
    b"\xfe\xed\xfa\xce",
    b"\xce\xfa\xed\xfe",
    b"\xfe\xed\xfa\xcf",
    b"\xcf\xfa\xed\xfe",
    b"\xca\xfe\xba\xbe",
    b"\xbe\xba\xfe\xca",
    b"\xca\xfe\xba\xbf",
    b"\xbf\xba\xfe\xca",
}
SYSTEM_PREFIXES = ("/System/Library/Frameworks/", "/usr/lib/")
BANNED_PATH_MARKERS = ("/Users/", "/DerivedData/", "/Applications/", "/opt/homebrew/", "/usr/local/")
EXPECTED_PLATFORM = {"iphoneos": "IOS", "iphonesimulator": "IOS_SIMULATOR"}
PLATFORM_NUMBERS = {2: "IOS", 7: "IOS_SIMULATOR"}
FRAMEWORK_DEPENDENCY = re.compile(r"(?:^|/)([^/]+\.framework)/([^/]+)$")
EXECUTABLE_BUNDLE_SUFFIXES = {".app", ".appex", ".xpc"}
SIMULATOR_ONLY_ARCHITECTURES = {"i386", "x86_64"}


@dataclass(frozen=True)
class MachOInspection:
    file_description: str
    install_ids: tuple[str, ...]
    dependencies: tuple[str, ...]
    rpaths: tuple[str, ...]
    architectures: tuple[str, ...]
    apple_platforms: tuple[str, ...]
    minimum_os_versions: tuple[str, ...]


class InspectionToolchain(Protocol):
    def inspect(self, binary: Path) -> MachOInspection: ...


class AppleToolchain:
    def inspect(self, binary: Path) -> MachOInspection:
        file_description = self._run(("file", "-b", str(binary))).strip()
        install_ids = self._parse_otool_ids(self._run(("otool", "-D", str(binary))), binary)
        dependencies = self._parse_otool_dependencies(self._run(("otool", "-L", str(binary))), binary)
        load_commands = self._run(("otool", "-l", str(binary)))
        rpaths = self._parse_rpaths(load_commands)
        architectures = self._parse_architectures(self._run(("lipo", "-archs", str(binary))))
        build_output = self._run(("vtool", "-show-build", str(binary)))
        platforms, minimum_versions = self._parse_build_versions(build_output, load_commands)
        return MachOInspection(
            file_description=file_description,
            install_ids=tuple(sorted(set(install_ids))),
            dependencies=tuple(dict.fromkeys(dependencies)),
            rpaths=tuple(dict.fromkeys(rpaths)),
            architectures=tuple(dict.fromkeys(architectures)),
            apple_platforms=tuple(platforms),
            minimum_os_versions=tuple(minimum_versions),
        )

    @staticmethod
    def _run(command: Sequence[str]) -> str:
        completed = subprocess.run(command, check=False, capture_output=True, text=True)
        if completed.returncode != 0:
            detail = completed.stderr.strip() or completed.stdout.strip() or "no diagnostic output"
            raise RuntimeError(f"{' '.join(command)} failed: {detail}")
        return completed.stdout

    @staticmethod
    def _parse_otool_ids(output: str, binary: Path) -> list[str]:
        values = []
        for line in output.splitlines():
            candidate = line.strip()
            if not candidate or candidate.endswith(":") or candidate == str(binary):
                continue
            values.append(candidate)
        return values

    @staticmethod
    def _parse_otool_dependencies(output: str, binary: Path) -> list[str]:
        values = []
        for line in output.splitlines():
            candidate = line.strip()
            if not candidate or candidate.endswith(":") or candidate == str(binary):
                continue
            values.append(candidate.split(" (", 1)[0])
        return values

    @staticmethod
    def _parse_rpaths(output: str) -> list[str]:
        values = []
        awaiting_path = False
        for line in output.splitlines():
            stripped = line.strip()
            if stripped == "cmd LC_RPATH":
                awaiting_path = True
                continue
            if awaiting_path and stripped.startswith("path "):
                values.append(stripped[5:].rsplit(" (offset ", 1)[0])
                awaiting_path = False
        return values

    @staticmethod
    def _parse_architectures(output: str) -> list[str]:
        stripped = output.strip()
        if " are: " in stripped:
            return stripped.rsplit(" are: ", 1)[1].split()
        if " architecture: " in stripped:
            return stripped.rsplit(" architecture: ", 1)[1].split()
        if stripped and all(re.fullmatch(r"[A-Za-z0-9_]+", value) for value in stripped.split()):
            return stripped.split()
        raise RuntimeError(f"Unrecognized lipo output: {stripped}")

    @staticmethod
    def _parse_build_versions(vtool_output: str, load_commands: str) -> tuple[list[str], list[str]]:
        platforms = []
        minimum_versions = []
        for line in vtool_output.splitlines():
            stripped = line.strip()
            if stripped.startswith("platform "):
                platforms.append(normalize_platform(stripped.split(None, 1)[1]))
            elif stripped.startswith("minos "):
                minimum_versions.append(stripped.split(None, 1)[1])

        if not platforms:
            command = None
            for line in load_commands.splitlines():
                stripped = line.strip()
                if stripped.startswith("cmd LC_"):
                    command = stripped.removeprefix("cmd ")
                elif command == "LC_BUILD_VERSION" and stripped.startswith("platform "):
                    value = stripped.split(None, 1)[1]
                    platforms.append(PLATFORM_NUMBERS.get(int(value), f"UNKNOWN_{value}") if value.isdigit() else normalize_platform(value))
                elif command == "LC_BUILD_VERSION" and stripped.startswith("minos "):
                    minimum_versions.append(stripped.split(None, 1)[1])
                elif command == "LC_VERSION_MIN_IPHONEOS" and stripped.startswith("version "):
                    platforms.append("IOS")
                    minimum_versions.append(stripped.split(None, 1)[1])

        return sorted(set(platforms)), sorted(set(minimum_versions))


def normalize_platform(value: str) -> str:
    normalized = re.sub(r"[^A-Za-z0-9]+", "_", value).strip("_").upper()
    aliases = {
        "IPHONEOS": "IOS",
        "IOS": "IOS",
        "IOSSIMULATOR": "IOS_SIMULATOR",
        "IOS_SIMULATOR": "IOS_SIMULATOR",
        "IPHONESIMULATOR": "IOS_SIMULATOR",
    }
    return aliases.get(normalized, normalized)


def is_macho(path: Path) -> bool:
    try:
        with path.open("rb") as stream:
            return stream.read(4) in MACHO_MAGICS
    except OSError:
        return False


def scan_app(app: Path, platform: str, toolchain: InspectionToolchain | None = None) -> dict[str, object]:
    app = app.resolve()
    if not app.is_dir() or app.suffix != ".app":
        raise ValueError(f"--app must point to an existing .app directory: {app}")
    if platform not in EXPECTED_PLATFORM:
        raise ValueError(f"Unsupported platform: {platform}")

    inspector = toolchain or AppleToolchain()
    macho_paths = sorted(path for path in app.rglob("*") if path.is_file() and is_macho(path))
    framework_paths = sorted(path for path in app.rglob("*.framework") if path.is_dir())
    invalid_frameworks, duplicate_bundle_ids, framework_metadata = inspect_frameworks(app, framework_paths)
    executable_bundle_paths = [app, *sorted(
        path
        for path in app.rglob("*")
        if path.is_dir() and path.suffix in EXECUTABLE_BUNDLE_SUFFIXES
    )]
    invalid_executable_bundles = inspect_executable_bundles(app, executable_bundle_paths)
    binaries = []
    unresolved = []
    invalid_absolute_paths = []
    errors = []
    expected_platform = EXPECTED_PLATFORM[platform]

    for binary in macho_paths:
        relative = binary.relative_to(app).as_posix()
        try:
            inspection = inspector.inspect(binary)
        except Exception as error:  # Tool diagnostics must be retained in the report.
            message = f"Mach-O inspection failed: {error}"
            errors.append({"binary": relative, "message": message})
            binaries.append({"path": relative, "inspectionError": message})
            continue

        binary_errors = []
        architectures = sorted(set(inspection.architectures))
        apple_platforms = sorted({normalize_platform(value) for value in inspection.apple_platforms})
        if "arm64" not in architectures:
            binary_errors.append(f"missing arm64 architecture for {platform}")
        if platform == "iphoneos":
            simulator_architectures = sorted(set(architectures) & SIMULATOR_ONLY_ARCHITECTURES)
            if simulator_architectures:
                binary_errors.append(
                    f"simulator architecture in device app: {', '.join(simulator_architectures)}"
                )
        if not apple_platforms:
            binary_errors.append("missing Apple platform load command")
        elif any(value != expected_platform for value in apple_platforms):
            binary_errors.append(
                f"platform mismatch: expected {expected_platform}, found {', '.join(apple_platforms)}"
            )

        for install_id in inspection.install_ids:
            path_error = unsafe_path_error(install_id, "LC_ID_DYLIB")
            if path_error is None and is_invalid_absolute_path(install_id):
                path_error = f"LC_ID_DYLIB contains unexpected absolute non-system path: {install_id}"
            if path_error:
                binary_errors.append(path_error)
                invalid_absolute_paths.append(
                    {"binary": relative, "kind": "LC_ID_DYLIB", "path": install_id, "message": path_error}
                )

        for rpath in inspection.rpaths:
            path_error = unsafe_path_error(rpath, "LC_RPATH")
            if path_error:
                binary_errors.append(path_error)
                if is_invalid_absolute_path(rpath):
                    invalid_absolute_paths.append(
                        {"binary": relative, "kind": "LC_RPATH", "path": rpath, "message": path_error}
                    )

        install_ids = set(inspection.install_ids)
        dependency_records = []
        for dependency in inspection.dependencies:
            if dependency in install_ids:
                dependency_records.append(
                    {
                        "path": dependency,
                        "kind": "install-id",
                        "status": "self",
                        "resolvedPath": relative,
                    }
                )
                continue

            record, dependency_error = resolve_dependency(
                dependency=dependency,
                app=app,
                binary=binary,
                rpaths=inspection.rpaths,
                framework_metadata=framework_metadata,
            )
            dependency_records.append(record)
            if dependency_error:
                entry = {"binary": relative, "dependency": dependency, "message": dependency_error}
                unresolved.append(entry)
                binary_errors.append(dependency_error)
                if is_invalid_absolute_path(dependency):
                    invalid_absolute_paths.append(
                        {
                            "binary": relative,
                            "kind": "dependency",
                            "path": dependency,
                            "message": dependency_error,
                        }
                    )

        for message in binary_errors:
            errors.append({"binary": relative, "message": message})
        binaries.append(
            {
                "path": relative,
                "fileDescription": inspection.file_description,
                "installID": inspection.install_ids[0] if len(inspection.install_ids) == 1 else None,
                "installIDs": list(inspection.install_ids),
                "architectures": architectures,
                "applePlatforms": apple_platforms,
                "minimumOSVersions": sorted(set(inspection.minimum_os_versions)),
                "rpaths": list(inspection.rpaths),
                "directDependencies": dependency_records,
                "errors": binary_errors,
            }
        )

    for framework in invalid_frameworks:
        errors.append({"framework": framework["path"], "message": framework["message"]})
    for bundle in invalid_executable_bundles:
        errors.append({"bundle": bundle["path"], "message": bundle["message"]})
    for identifier, paths in duplicate_bundle_ids.items():
        errors.append({"bundleIdentifier": identifier, "message": f"duplicate framework bundle identifier: {', '.join(paths)}"})

    return {
        "appPath": str(app),
        "scanTimestamp": datetime.now(timezone.utc).isoformat(),
        "platform": platform,
        "machOCount": len(macho_paths),
        "frameworkCount": len(framework_paths),
        "executableBundleCount": len(executable_bundle_paths),
        "binaries": binaries,
        "unresolvedDependencies": unresolved,
        "unresolvedDependencyCount": len(unresolved),
        "invalidAbsolutePaths": invalid_absolute_paths,
        "duplicateBundleIdentifiers": duplicate_bundle_ids,
        "invalidFrameworks": invalid_frameworks,
        "invalidExecutableBundles": invalid_executable_bundles,
        "errors": errors,
        "result": "pass" if not errors else "fail",
    }


def inspect_frameworks(
    app: Path, framework_paths: list[Path]
) -> tuple[list[dict[str, str]], dict[str, list[str]], dict[Path, dict[str, str]]]:
    invalid = []
    identifiers: dict[str, list[str]] = {}
    metadata: dict[Path, dict[str, str]] = {}
    for framework in framework_paths:
        relative = framework.relative_to(app).as_posix()
        info_path = framework / "Info.plist"
        try:
            with info_path.open("rb") as stream:
                info = plistlib.load(stream)
        except Exception as error:
            invalid.append({"path": relative, "message": f"malformed or missing Info.plist: {error}"})
            continue
        executable = info.get("CFBundleExecutable")
        identifier = info.get("CFBundleIdentifier")
        if not isinstance(identifier, str) or not identifier:
            invalid.append({"path": relative, "message": "missing CFBundleIdentifier"})
            continue
        identifiers.setdefault(identifier, []).append(relative)
        if not isinstance(executable, str) or not executable:
            invalid.append({"path": relative, "message": "missing CFBundleExecutable"})
            continue
        executable_path = framework / executable
        if not executable_path.is_file():
            invalid.append({"path": relative, "message": f"missing CFBundleExecutable binary: {executable}"})
            continue
        if not is_macho(executable_path):
            invalid.append({"path": relative, "message": f"CFBundleExecutable is not Mach-O: {executable}"})
            continue
        metadata[framework.resolve()] = {"executable": executable, "identifier": identifier}
    duplicates = {identifier: paths for identifier, paths in identifiers.items() if len(paths) > 1}
    return invalid, duplicates, metadata


def inspect_executable_bundles(app: Path, bundle_paths: list[Path]) -> list[dict[str, str]]:
    invalid = []
    for bundle in bundle_paths:
        relative = "." if bundle == app else bundle.relative_to(app).as_posix()
        info_path = bundle / "Info.plist"
        try:
            with info_path.open("rb") as stream:
                info = plistlib.load(stream)
        except Exception as error:
            invalid.append({"path": relative, "message": f"malformed or missing Info.plist: {error}"})
            continue
        executable = info.get("CFBundleExecutable")
        if not isinstance(executable, str) or not executable:
            invalid.append({"path": relative, "message": "missing CFBundleExecutable"})
            continue
        executable_path = bundle / executable
        if not executable_path.is_file():
            invalid.append({"path": relative, "message": f"missing CFBundleExecutable binary: {executable}"})
            continue
        if not is_macho(executable_path):
            invalid.append({"path": relative, "message": f"CFBundleExecutable is not Mach-O: {executable}"})
    return invalid


def resolve_dependency(
    dependency: str,
    app: Path,
    binary: Path,
    rpaths: Sequence[str],
    framework_metadata: dict[Path, dict[str, str]],
) -> tuple[dict[str, object], str | None]:
    unsafe = unsafe_path_error(dependency, "dependency")
    if unsafe:
        return dependency_record(dependency, "invalid", None, [], status="invalid"), unsafe
    if dependency.startswith(SYSTEM_PREFIXES):
        return dependency_record(dependency, "system", dependency, [dependency]), None
    if dependency.startswith("/"):
        return (
            dependency_record(dependency, "invalid", None, [dependency], status="invalid"),
            f"unexpected absolute non-system library path: {dependency}",
        )

    executable_root = containing_executable_root(app, binary)
    candidates: list[Path] = []
    if dependency.startswith("@rpath/"):
        suffix = dependency.removeprefix("@rpath/")
        for rpath in rpaths:
            expanded = expand_loader_token(rpath, executable_root, binary.parent)
            if expanded is not None:
                candidates.append(expanded / suffix)
        candidates.extend((executable_root / "Frameworks" / suffix, app / "Frameworks" / suffix))
        kind = "rpath"
    elif dependency.startswith("@executable_path"):
        expanded = expand_loader_token(dependency, executable_root, binary.parent)
        candidates = [expanded] if expanded is not None else []
        kind = "executable-path"
    elif dependency.startswith("@loader_path"):
        expanded = expand_loader_token(dependency, executable_root, binary.parent)
        candidates = [expanded] if expanded is not None else []
        kind = "loader-path"
    else:
        return (
            dependency_record(dependency, "invalid", None, [], status="invalid"),
            f"unsupported relative dependency: {dependency}",
        )

    unique_candidates = unique_paths(candidates)
    resolved = next((candidate for candidate in unique_candidates if candidate.is_file()), None)
    if resolved is None:
        message = f"unresolved {dependency}"
        return dependency_record(dependency, kind, None, unique_candidates), message
    if not is_within(resolved, app):
        message = f"dependency resolves outside app bundle: {dependency} -> {resolved}"
        return dependency_record(dependency, kind, str(resolved), unique_candidates, status="invalid"), message
    if not is_macho(resolved):
        message = f"dependency resolves to a non-Mach-O file: {dependency} -> {resolved}"
        return dependency_record(dependency, kind, str(resolved), unique_candidates, status="invalid"), message

    framework_error = validate_framework_dependency(dependency, resolved, framework_metadata)
    if framework_error:
        return dependency_record(dependency, kind, str(resolved), unique_candidates, status="invalid"), framework_error
    return dependency_record(dependency, kind, str(resolved), unique_candidates), None


def dependency_record(
    dependency: str,
    kind: str,
    resolved: str | None,
    candidates: Sequence[Path | str],
    *,
    status: str | None = None,
) -> dict[str, object]:
    return {
        "path": dependency,
        "kind": kind,
        "status": status or ("resolved" if resolved else "unresolved"),
        "resolvedPath": resolved,
        "candidates": [str(candidate) for candidate in candidates],
    }


def containing_executable_root(app: Path, binary: Path) -> Path:
    current = binary.parent
    while current != app.parent:
        if current.suffix in {".app", ".appex"}:
            return current
        if current == app:
            break
        current = current.parent
    return app


def expand_loader_token(value: str, executable_root: Path, loader_root: Path) -> Path | None:
    if value == "@executable_path" or value.startswith("@executable_path/"):
        suffix = value.removeprefix("@executable_path").lstrip("/")
        return (executable_root / suffix).resolve()
    if value == "@loader_path" or value.startswith("@loader_path/"):
        suffix = value.removeprefix("@loader_path").lstrip("/")
        return (loader_root / suffix).resolve()
    if value.startswith("/"):
        return Path(value).resolve()
    return None


def validate_framework_dependency(
    dependency: str, resolved: Path, framework_metadata: dict[Path, dict[str, str]]
) -> str | None:
    match = FRAMEWORK_DEPENDENCY.search(dependency)
    if not match:
        return None
    framework_name, dependency_executable = match.groups()
    framework = next((parent for parent in (resolved.parent, *resolved.parents) if parent.name == framework_name), None)
    if framework is None:
        return f"dependency resolved outside expected {framework_name}: {resolved}"
    metadata = framework_metadata.get(framework.resolve())
    if metadata is None:
        return f"dependency points to invalid framework {framework_name}: {resolved}"
    expected_executable = metadata["executable"]
    expected_path = (framework / expected_executable).resolve()
    if dependency_executable != expected_executable or resolved.resolve() != expected_path:
        return (
            f"dependency points to wrong framework executable: {dependency} resolved to {resolved}; "
            f"expected {framework_name}/{expected_executable}"
        )
    return None


def unsafe_path_error(value: str, label: str) -> str | None:
    normalized = value.replace("\\", "/")
    for marker in BANNED_PATH_MARKERS:
        if marker in normalized:
            return f"{label} contains forbidden developer-machine path: {value}"
    if label == "LC_RPATH" and is_invalid_absolute_path(normalized):
        return f"LC_RPATH contains unexpected absolute non-system path: {value}"
    return None


def is_invalid_absolute_path(value: str) -> bool:
    normalized = value.replace("\\", "/")
    is_absolute = normalized.startswith("/") or re.match(r"^[A-Za-z]:/", normalized) is not None
    return is_absolute and not normalized.startswith(SYSTEM_PREFIXES)


def is_within(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def unique_paths(paths: Sequence[Path]) -> list[Path]:
    seen = set()
    result = []
    for path in paths:
        resolved = path.resolve()
        if resolved not in seen:
            seen.add(resolved)
            result.append(resolved)
    return result


def render_text_report(report: dict[str, object]) -> str:
    lines = [
        "Mach-O / dyld closure validation",
        "================================",
        f"App: {report['appPath']}",
        f"Timestamp: {report['scanTimestamp']}",
        f"Platform: {report['platform']}",
        f"Mach-O count: {report['machOCount']}",
        f"Framework count: {report['frameworkCount']}",
        f"Executable bundle count: {report['executableBundleCount']}",
        f"Unresolved dependency count: {report['unresolvedDependencyCount']}",
        f"Invalid absolute path count: {len(report['invalidAbsolutePaths'])}",
        f"Duplicate framework bundle-ID count: {len(report['duplicateBundleIdentifiers'])}",
        f"Invalid framework count: {len(report['invalidFrameworks'])}",
        f"Invalid executable bundle count: {len(report['invalidExecutableBundles'])}",
        f"Result: {str(report['result']).upper()}",
        "",
    ]
    for binary in report["binaries"]:
        lines.append(f"Binary: {binary['path']}")
        if "inspectionError" in binary:
            lines.extend((f"  ERROR: {binary['inspectionError']}", ""))
            continue
        lines.append(f"  Install ID: {binary['installID'] or '(none)'}")
        lines.append(f"  Architectures: {', '.join(binary['architectures']) or '(none)'}")
        lines.append(f"  Apple platforms: {', '.join(binary['applePlatforms']) or '(none)'}")
        lines.append(f"  Minimum OS: {', '.join(binary['minimumOSVersions']) or '(unknown)'}")
        lines.append(f"  LC_RPATH: {', '.join(binary['rpaths']) or '(none)'}")
        lines.append("  Direct dependencies:")
        for dependency in binary["directDependencies"]:
            target = dependency["resolvedPath"] or "MISSING"
            lines.append(f"    [{dependency['status']}] {dependency['path']} -> {target}")
        for error in binary["errors"]:
            lines.append(f"  ERROR: {error}")
        lines.append("")
    if report["duplicateBundleIdentifiers"]:
        lines.append("Duplicate framework bundle identifiers:")
        for identifier, paths in report["duplicateBundleIdentifiers"].items():
            lines.append(f"  {identifier}: {', '.join(paths)}")
        lines.append("")
    if report["invalidFrameworks"]:
        lines.append("Invalid frameworks:")
        for framework in report["invalidFrameworks"]:
            lines.append(f"  {framework['path']}: {framework['message']}")
        lines.append("")
    if report["invalidExecutableBundles"]:
        lines.append("Invalid executable bundles:")
        for bundle in report["invalidExecutableBundles"]:
            lines.append(f"  {bundle['path']}: {bundle['message']}")
        lines.append("")
    if report["invalidAbsolutePaths"]:
        lines.append("Invalid absolute paths:")
        for entry in report["invalidAbsolutePaths"]:
            lines.append(f"  {entry['binary']} [{entry['kind']}]: {entry['path']} ({entry['message']})")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def parse_arguments(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--platform", choices=sorted(EXPECTED_PLATFORM), required=True)
    parser.add_argument("--json-output", type=Path, required=True)
    parser.add_argument("--text-output", type=Path, required=True)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    arguments = parse_arguments(argv or sys.argv[1:])
    try:
        report = scan_app(arguments.app, arguments.platform)
    except Exception as error:
        print(f"dyld closure validation could not start: {error}", file=sys.stderr)
        return 2
    arguments.json_output.parent.mkdir(parents=True, exist_ok=True)
    arguments.text_output.parent.mkdir(parents=True, exist_ok=True)
    arguments.json_output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    arguments.text_output.write_text(render_text_report(report), encoding="utf-8")
    print(render_text_report(report), end="")
    return 0 if report["result"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
