#!/usr/bin/env python3
# HANLIN_METADATA_WRAPPER_V1

import argparse
import os
from fnmatch import fnmatchcase
import hashlib
import json
import re
from pathlib import Path
import shlex
import shutil
import subprocess
import sys

REQUIRED_METADATA_NAMES = ["HanlinNativeServicesBridge", "HanlinNativeServicesSessionBridge",
    "HanlinNativeScriptCompatibility", "UIView", "NSObject", "NSUserDefaults", "NativeScriptEmbedder",
    "SwiftUIProvider", "HanlinNativeScriptSwiftUIFixtureProvider",
    "WKNavigationDelegate", "WKWebView", "TNSLabel", "NSCCrypto"]

# Keep the generated Host/provider header dependencies. Original Core adds its
# own native frameworks and the system frameworks declared in native-api-usage.
# Importing unrelated Expo/React umbrellas into the ObjC parser remains the
# separate full-SDK probe; Core's actual native dependencies belong in this host.
HOST_FRAMEWORKS = {"Foundation.framework", "UIKit.framework", "WebKit.framework",
    "AVFoundation.framework", "CoreLocation.framework", "Speech.framework"}


def original_core_frameworks(root: Path, sdk: Path, search_paths: list[Path]) -> set[str]:
    artifacts = root / "Packages/HanlinNativeScriptRuntime/Artifacts"
    closure = json.loads((artifacts / "dependency-closure.json").read_text())
    usage = json.loads((artifacts / "native-api-usage.json").read_text())
    required = {artifact["name"] + ".framework" for artifact in closure["artifacts"]}
    available = {framework.name
                 for directory in [*search_paths, sdk / "System/Library/Frameworks"]
                 for framework in directory.glob("*.framework")}
    missing = required - available
    if missing:
        raise RuntimeError("Original NativeScript Core framework headers missing: "
                           + ", ".join(sorted(missing)))
    # Entries such as TNSWidgets*:* and CoreGraphics.*:* describe native
    # namespaces. Match their actual framework roots, retaining the original
    # public umbrella and all its declarations rather than enumerating classes.
    namespaces = {entry.partition(":")[0].partition(".")[0] for entry in usage["uses"]}
    declared = {name for name in available
                if any(fnmatchcase(name.removesuffix(".framework"), namespace)
                       for namespace in namespaces)}
    return HOST_FRAMEWORKS | required | declared


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
    return shlex.join(["-fno-modules",
                       f"-fmodule-map-file={core_support_dir / 'module.modulemap'}",
                       f"-fmodule-map-file={module_map}"])


def explicit_input_adapter(source: str) -> str:
    # Preserve upstream's Xcode flag/architecture handling. Only add the real
    # input umbrella before Xclang and select the separately verified tool.
    before = 'generator_call = ["./objc-metadata-generator", "-verbose",'
    if source.count(before) != 1 or source.count("    # clang arguments\n") != 1:
        raise RuntimeError("Pinned upstream metadata launcher no longer matches")
    return source.replace(before, 'generator_call = [env("HANLIN_METADATA_GENERATOR"), "-verbose",').replace(
        "    # clang arguments\n",
        '    generator_call.extend(["-input-umbrella", env("HANLIN_METADATA_INPUT_UMBRELLA")])\n\n    # clang arguments\n')


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
    required = REQUIRED_METADATA_NAMES
    symbols = {name: name.encode("utf-8") + b"\0" in binary for name in required}
    # The upstream generator can return zero and emit a partial binary after
    # actual clang errors. An ObjC selector named error: is not a diagnostic.
    diagnostics = paths[0].read_text(encoding="utf-8", errors="replace").splitlines() if paths[0].is_file() else []
    errors = [line for line in diagnostics
              if re.search(r"(?:^|:\d+(?::\d+)?:\s+)(?:fatal\s+)?error:", line)]
    (evidence / "visibility.json").write_text(json.dumps({"schemaVersion": 1,
        "scope": "HOST_BASELINE_ONLY",
        "platform": platform, "architecture": arch, "sha256": hashes,
        "requiredMetadataStringsPresent": symbols,
        "clangErrorCount": len(errors),
        "boundary": "Build-time completeness check; actual VM tests still required."}, indent=2) + "\n", encoding="utf-8")
    if not all(symbols.values()) or errors:
        print("Hanlin NativeScript metadata is incomplete: " + ", ".join(name for name, found in symbols.items() if not found), flush=True)
        print("\n".join(errors[:40]), flush=True)
        return False
    print("Hanlin metadata required strings present; actual JS visibility remains an execution gate.", flush=True)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate complete NativeScript host metadata")
    parser.add_argument("architecture")
    parser.add_argument("--generator-root", type=Path,
                        help="Pinned NativeScript package generator directory")
    arguments = parser.parse_args()
    arch = arguments.architecture
    generator_root = arguments.generator_root or Path(__file__).resolve().parent
    upstream_generator = generator_root / "build-step-metadata-generator-upstream.py"
    if arguments.generator_root is not None:
        # Xcode calls this tracked file directly. A fresh npm installation keeps
        # the original launcher; an already prepared tree retains its backup.
        # Neither installation state may bypass our explicit input/error checks.
        installed_generator = generator_root / "build-step-metadata-generator.py"
        if "HANLIN_METADATA_WRAPPER_V1" not in installed_generator.read_text():
            upstream_generator = installed_generator
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
        swift_headers = write_swift_module_map(module_map, runtime_header, arch)
        environment = os.environ.copy()
        root = Path(required_env("SRCROOT"))
        sys.path.insert(0, str(root / "Scripts/NativeScript"))
        from metadata_public_headers import write_framework_search_view, write_public_umbrella
        core_support_dir = root / "Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptCoreSupport/include"
        tool_root = root / "build/nativescript-metadata-tool"
        tool = tool_root / "bin/objc-metadata-generator"
        provenance = json.loads((tool_root / "provenance.json").read_text())
        if hashlib.sha256(tool.read_bytes()).hexdigest() != provenance["generatorSHA256"] or \
           provenance["patchSourceSHA256"] != hashlib.sha256((root / "Scripts/NativeScript/build-metadata-tool.py").read_bytes()).hexdigest():
            raise RuntimeError("Metadata build-tool provenance does not match actual inputs")
        umbrella = module_root / "HanlinMetadataInput.h"
        evidence = root / "build/acceptance/nativescript-metadata" / f"{platform_name}-{arch}"
        evidence.mkdir(parents=True, exist_ok=True)
        search_view = module_root / "Frameworks"
        search_inventory = evidence / "FrameworkSearchView.inventory.json"
        try:
            search_paths = write_framework_search_view(
                [Path(p) for p in shlex.split(environment.get("FRAMEWORK_SEARCH_PATHS", ""))],
                search_view, search_inventory)
            environment["FRAMEWORK_SEARCH_PATHS"] = shlex.join(str(p) for p in search_paths)
            sdk_root = Path(required_env("SDKROOT"))
            write_public_umbrella(sdk_root, umbrella,
                                  sorted(core_support_dir.glob("*.h")) + swift_headers,
                                  search_paths,
                                  framework_names=original_core_frameworks(root, sdk_root, search_paths))
        finally:
            for path in [umbrella, umbrella.with_suffix(".inventory.json"), tool_root / "provenance.json"]:
                if path.is_file():
                    shutil.copy2(path, evidence / path.name)
        adapter = module_root / "upstream-generator-with-explicit-input.py"
        adapter.write_text(explicit_input_adapter(upstream_generator.read_text()), encoding="utf-8")
        environment["HANLIN_METADATA_GENERATOR"] = str(tool)
        environment["HANLIN_METADATA_INPUT_UMBRELLA"] = str(umbrella)
        environment["CLANG_ENABLE_MODULES"] = "NO"
        extra_flags = metadata_flags(module_root, module_map, core_support_dir)
        environment["OTHER_CFLAGS"] = f'{environment.get("OTHER_CFLAGS", "")} {extra_flags}'.strip()
        completed = subprocess.run(
            [sys.executable, str(adapter), arch],
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
