#!/usr/bin/env python3
# HANLIN_METADATA_WRAPPER_V1

import os
from pathlib import Path
import shutil
import subprocess
import sys


def required_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"Hanlin NativeScript metadata: missing Xcode environment variable {name}")
    return value


def build_intermediates_root() -> Path:
    build_dir = required_env("BUILD_DIR")
    marker = f"{os.sep}Products"
    marker_index = build_dir.rfind(marker)
    if marker_index < 0:
        raise SystemExit(
            f"Hanlin NativeScript metadata: BUILD_DIR does not contain {marker!r}: {build_dir}"
        )
    return Path(build_dir[:marker_index]) / "Intermediates.noindex"


def write_swift_module_map(module_map: Path, runtime_header: Path, arch: str) -> None:
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
        module_flag = f'-fmodule-map-file="{module_map}"'
        environment["OTHER_CFLAGS"] = f'{environment.get("OTHER_CFLAGS", "")} {module_flag}'.strip()
        completed = subprocess.run(
            [sys.executable, str(upstream_generator), *sys.argv[1:]],
            cwd=generator_root,
            env=environment,
            check=False,
        )
        return completed.returncode
    finally:
        shutil.rmtree(module_root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
