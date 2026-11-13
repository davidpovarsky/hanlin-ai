#!/usr/bin/env python3
# HANLIN_METADATA_WRAPPER_V1

import os
import hashlib
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import sys


def required_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"Hanlin NativeScript metadata: missing Xcode environment variable {name}")
    return value


def build_intermediates_root() -> Path:
    obj_root = os.environ.get("OBJROOT")
    if obj_root:
        return Path(obj_root)

    build_dir = required_env("BUILD_DIR")
    build_dir_path = Path(build_dir)
    if build_dir_path.name == "BuildProductsPath":
        return build_dir_path.parent / "IntermediateBuildFilesPath"

    marker = f"{os.sep}Products"
    marker_index = build_dir.rfind(marker)
    if marker_index < 0:
        raise SystemExit(
            f"Hanlin NativeScript metadata: BUILD_DIR does not contain {marker!r}: {build_dir}"
        )
    return Path(build_dir[:marker_index]) / "Intermediates.noindex"


def write_swift_module_map(module_map: Path, runtime_header: Path, arch: str) -> list:
    headers = [runtime_header]
    object_root = os.environ.get("PER_VARIANT_OBJECT_FILE_DIR")
    if object_root:
        swift_header_root = Path(object_root) / arch
        if swift_header_root.is_dir():
            headers.extend(sorted(swift_header_root.rglob("*-Swift.h")))

    unique_headers = []
    seen = set()
    for header in headers:
        resolved = header.resolve()
        if resolved not in seen:
            seen.add(resolved)
            unique_headers.append(resolved)

    lines = ["module hanlinnativescriptswiftsupport {"]
    lines.extend(f'  header "{header}"' for header in unique_headers)
    lines.extend(["  export *", "}", ""])
    module_map.write_text("\n".join(lines), encoding="utf-8")
    return unique_headers


def metadata_flags(module_root: Path, module_map: Path, core_support_dir: Path) -> str:
    # Each ObjC header keeps its existing module owner. Listing those headers
    # again in the generated Swift module can make clang's findModuleForHeader
    # ambiguous. The upstream generator silently skips unknown module owners.
    imports = module_root / "HanlinMetadataImports.h"
    imports.write_text("@import HanlinNativeServicesBridge;\n"
                       "@import HanlinNativeScriptCompatibility;\n"
                       "@import hanlinnativescriptswiftsupport;\n", encoding="utf-8")
    return shlex.join([f"-fmodule-map-file={core_support_dir / 'module.modulemap'}",
                       f"-fmodule-map-file={module_map}", "-include", str(imports)])


def retain_and_check_metadata(arch: str, platform: str) -> bool:
    products = Path(required_env("CONFIGURATION_BUILD_DIR"))
    evidence = Path(required_env("SRCROOT")) / "build/acceptance/nativescript-metadata" / f"{platform}-{arch}"
    evidence.mkdir(parents=True, exist_ok=True)
    paths = [products / f"metadata-generation-stderr-{arch}.txt",
             products / f"umbrella-{arch}.h", products / f"metadata-{arch}.bin"]
    hashes = {}
    for path in paths:
        if path.is_file():
            data = path.read_bytes()
            (evidence / path.name).write_bytes(data)
            hashes[path.name] = hashlib.sha256(data).hexdigest()
    binary = paths[2].read_bytes() if paths[2].is_file() else b""
    required = ["HanlinNativeServicesBridge", "HanlinNativeServicesSessionBridge", "HanlinNativeScriptCompatibility", "UIView", "NSObject"]
    symbols = {name: name.encode("utf-8") + b"\0" in binary for name in required}
    (evidence / "visibility.json").write_text(json.dumps({"schemaVersion": 1,
        "platform": platform, "architecture": arch, "sha256": hashes,
        "requiredMetadataStringsPresent": symbols,
        "boundary": "Build-time completeness check; actual VM tests still required."}, indent=2) + "\n", encoding="utf-8")
    if not all(symbols.values()):
        print("Hanlin NativeScript metadata is incomplete: " + ", ".join(name for name, found in symbols.items() if not found), flush=True)
        if paths[0].is_file():
            diagnostics = [line for line in paths[0].read_text(encoding="utf-8", errors="replace").splitlines()
                           if "error:" in line or "HanlinNativeServices" in line or "Unknown module" in line]
            print("\n".join(diagnostics[:40]), flush=True)
        return False
    print("Hanlin metadata required strings present; actual JS visibility remains an execution gate.", flush=True)
    return True


def main() -> int:
    if len(sys.argv) < 2 or not sys.argv[1]:
        raise SystemExit("Hanlin NativeScript metadata: target architecture argument is required")

    arch = sys.argv[1]
    generator_root = Path(__file__).resolve().parent
    upstream_generator = generator_root / "build-step-metadata-generator-upstream.py"
    if not upstream_generator.is_file():
        raise SystemExit(
            f"Hanlin NativeScript metadata: upstream generator backup is missing: {upstream_generator}"
        )

    platform_name = required_env("PLATFORM_NAME")
    runtime_header = (
        build_intermediates_root()
        / f"GeneratedModuleMaps-{platform_name}"
        / "HanlinNativeScriptRuntime-Swift.h"
    )
    if not runtime_header.is_file():
        raise SystemExit(
            f"Hanlin NativeScript metadata: generated runtime Swift header is missing: {runtime_header}"
        )

    module_root = Path(required_env("TARGET_TEMP_DIR")) / f"HanlinNativeScriptSwiftMetadata-{arch}"
    module_map = module_root / "module.modulemap"
    shutil.rmtree(module_root, ignore_errors=True)
    module_root.mkdir(parents=True)

    try:
        write_swift_module_map(module_map, runtime_header, arch)
        environment = os.environ.copy()
        core_support_dir = Path(required_env("SRCROOT")) / "Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptCoreSupport/include"
        extra_flags = metadata_flags(module_root, module_map, core_support_dir)
        environment["OTHER_CFLAGS"] = f'{environment.get("OTHER_CFLAGS", "")} {extra_flags}'.strip()
        completed = subprocess.run(
            [sys.executable, str(upstream_generator), *sys.argv[1:]],
            cwd=generator_root,
            env=environment,
            check=False,
        )
        complete = retain_and_check_metadata(arch, platform_name)
        return completed.returncode if completed.returncode else (0 if complete else 1)
    finally:
        shutil.rmtree(module_root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
