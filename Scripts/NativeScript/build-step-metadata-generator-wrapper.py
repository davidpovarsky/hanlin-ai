#!/usr/bin/env python3
# HANLIN_METADATA_WRAPPER_V1

from __future__ import annotations

import os
import hashlib
import json
import re
from pathlib import Path
import shlex
import shutil
import subprocess
import sys

REQUIRED_METADATA_NAMES = ["HanlinNativeServicesBridge", "HanlinNativeServicesSessionBridge",
    "HanlinNativeScriptCompatibility", "UIView", "NSObject", "NativeScriptEmbedder",
    "SwiftUIProvider", "HanlinNativeScriptSwiftUIFixtureProvider"]


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


def metadata_flags(module_root: Path, module_map: Path, core_support_dir: Path, header_alias_overlay: Path = None) -> str:
    # Each ObjC header keeps its existing module owner. Listing those headers
    # again in the generated Swift module can make clang's findModuleForHeader
    # ambiguous. The upstream generator silently skips unknown module owners.
    flags = ["-fno-modules",
                       f"-fmodule-map-file={core_support_dir / 'module.modulemap'}",
                       f"-fmodule-map-file={module_map}"]
    if header_alias_overlay is not None:
        flags.extend(["-ivfsoverlay", str(header_alias_overlay)])
    return shlex.join(flags)


def explicit_input_adapter(source: str) -> str:
    # Preserve upstream's Xcode flag/architecture handling. Only add the real
    # input umbrella before Xclang and select the separately verified tool.
    before = 'generator_call = ["./objc-metadata-generator", "-verbose",'
    if source.count(before) != 1 or source.count("    # clang arguments\n") != 1:
        raise RuntimeError("Pinned upstream metadata launcher no longer matches")
    invocation = "    child_process = subprocess.Popen(generator_call, stderr=subprocess.PIPE, universal_newlines=True)"
    target = 'llvm_target_triple_os_version, llvm_target_triple_suffix)'
    if source.count(invocation) != 1 or source.count(target) != 1:
        raise RuntimeError("Pinned upstream metadata compiler invocation no longer matches")
    # Bind the metadata parser to the app's actual deployment context, not the SDK version.
    source = source.replace(target, '\"ios\" + deployment_target, llvm_target_triple_suffix)')
    source = source.replace(before, 'generator_call = [env("HANLIN_METADATA_GENERATOR"), "-verbose",').replace(
        "    # clang arguments\n",
        '    generator_call.extend(["-input-umbrella", env("HANLIN_METADATA_INPUT_UMBRELLA")])\n'
        '    if os.environ.get("HANLIN_METADATA_EFFECTIVE_CONTEXT"):\n'
        '        generator_call.extend(["-hanlin-expected-clang-context", os.environ["HANLIN_METADATA_EFFECTIVE_CONTEXT"]])\n'
        '\n    # clang arguments\n')
    return source.replace(invocation,
        '    import json, hashlib\n'
        '    ignored = {"HANLIN_METADATA_CAPTURE_ARGUMENTS", "HANLIN_METADATA_EXPECTED_CONTEXT", "HANLIN_METADATA_ACTUAL_CONTEXT"}\n'
        '    context = {"schemaVersion": 1, "workingDirectory": os.path.realpath(os.getcwd()),\n'
        '        "arguments": generator_call[generator_call.index("Xclang") + 1:], "generatorCall": generator_call,\n'
        '        "environmentSHA256": hashlib.sha256(json.dumps({k:v for k,v in os.environ.items() if k not in ignored}, sort_keys=True).encode()).hexdigest()}\n'
        '    if os.environ.get("HANLIN_METADATA_CAPTURE_ARGUMENTS"):\n'
        '        with open(os.environ["HANLIN_METADATA_CAPTURE_ARGUMENTS"], "w") as output:\n'
        '            json.dump(context, output)\n'
        '        return\n'
        '    with open(os.environ["HANLIN_METADATA_EXPECTED_CONTEXT"]) as expected:\n'
        '        if context != json.load(expected):\n'
        '            raise RuntimeError("Metadata generator invocation context drifted after classification")\n'
        '    with open(os.environ["HANLIN_METADATA_ACTUAL_CONTEXT"], "w") as output:\n'
        '        json.dump(context, output)\n' + invocation)


def capture_compiler_arguments(adapter: Path, environment: dict, arch: str, destination: Path,
                               working_directory: Path | None = None) -> list[str]:
    working_directory = (working_directory or adapter.parent).resolve()
    captured = subprocess.run([sys.executable, str(adapter), arch], cwd=working_directory,
        env={**environment, "HANLIN_METADATA_CAPTURE_ARGUMENTS": str(destination)}, check=False)
    if captured.returncode or not destination.is_file():
        raise RuntimeError("Actual upstream metadata compiler arguments were not captured")
    plan = json.loads(destination.read_text(encoding="utf-8"))
    if Path(plan["workingDirectory"]).resolve() != working_directory:
        raise RuntimeError("Metadata capture working directory differs from generator")
    return plan["arguments"]


def capture_native_compiler_context(tool: Path, invocation_plan: dict, environment: dict,
                                    working_directory: Path, destination: Path) -> dict:
    call = invocation_plan["generatorCall"]
    if Path(call[0]).resolve() != tool.resolve():
        raise RuntimeError("Captured metadata invocation selects a different tool")
    position = call.index("Xclang")
    command = [*call[:position], "-hanlin-dump-clang-context", str(destination), *call[position:]]
    with destination.with_suffix(".log").open("w") as log:
        completed = subprocess.run(command, cwd=working_directory, env=environment,
            stdout=log, stderr=subprocess.STDOUT, check=False)
    if completed.returncode or not destination.is_file():
        raise RuntimeError("Actual metadata frontend context was not captured")
    raw = destination.read_bytes()
    if not raw.endswith(b"\0"):
        raise RuntimeError("Actual metadata frontend context is not fully framed")
    values = [value.decode("utf-8") for value in raw[:-1].split(b"\0")]
    if len(values) < 2 or not values[0]:
        raise RuntimeError("Actual metadata frontend context is incomplete")
    return {"compiler": values[0], "arguments": values[1:],
            "generatorSHA256": hashlib.sha256(tool.read_bytes()).hexdigest(),
            "contextSHA256": hashlib.sha256(raw).hexdigest()}


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

    module_root = (Path(required_env("TARGET_TEMP_DIR")) / f"HanlinNativeScriptSwiftMetadata-{arch}").resolve()
    module_map = module_root / "module.modulemap"
    shutil.rmtree(module_root, ignore_errors=True)
    module_root.mkdir(parents=True)

    root = Path(required_env("SRCROOT")).resolve()
    sys.path.insert(0, str(root / "Scripts/NativeScript"))
    from metadata_public_headers import compiler_working_directory
    try:
        with compiler_working_directory(generator_root):
            return generate_final_metadata(root, arch, platform_name, module_root, module_map, runtime_header, generator_root, upstream_generator)
    finally:
        shutil.rmtree(module_root, ignore_errors=True)


def generate_final_metadata(root, arch, platform_name, module_root, module_map, runtime_header, generator_root, upstream_generator):
    swift_headers = write_swift_module_map(module_map, runtime_header, arch)
    environment = os.environ.copy()
    from metadata_public_headers import (write_public_umbrella, write_verified_header_alias_overlay,
        produce_role_inventory, ROLE_MANIFEST, verify_role_context)
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
    alias_overlay = module_root / "HanlinHeaderAliases.json"
    adapter = module_root / "build-step-metadata-generator-adapter.py"
    adapter.write_text(explicit_input_adapter(upstream_generator.read_text()), encoding="utf-8")
    environment["HANLIN_METADATA_GENERATOR"] = str(tool)
    environment["HANLIN_METADATA_INPUT_UMBRELLA"] = str(umbrella)
    environment["CLANG_ENABLE_MODULES"] = "NO"
    original_cflags = environment.get("OTHER_CFLAGS", "")
    environment["OTHER_CFLAGS"] = f'{original_cflags} {metadata_flags(module_root, module_map, core_support_dir)}'.strip()
    directories = [Path(p) for p in shlex.split(environment.get("FRAMEWORK_SEARCH_PATHS", ""))]
    role_roots = list(dict.fromkeys(p.resolve() for p in directories if (p / ROLE_MANIFEST).is_file()))
    receipts = {str(directory): module_root / f"input-roles-{n}.json" for n, directory in enumerate(role_roots)}
    try:
        library = None
        if role_roots:
            clang = Path(subprocess.check_output(["xcrun", "--find", "clang"], text=True).strip()).resolve()
            library = clang.parent.parent / "lib/libclang.dylib"
            # First inventory only discovers ownership/aliases; it grants no include-only role.
            for directory in role_roots:
                produce_role_inventory(directory, [], library, classify=False, receipt_path=receipts[str(directory)])
        inventory = write_public_umbrella(Path(required_env("SDKROOT")), umbrella,
            sorted(core_support_dir.glob("*.h")) + swift_headers, directories, receipts)
        aliases = write_verified_header_alias_overlay(inventory, alias_overlay)
        environment["OTHER_CFLAGS"] = f'{original_cflags} {metadata_flags(module_root, module_map, core_support_dir, alias_overlay if aliases else None)}'.strip()
        context_path = module_root / "actual-compiler-arguments.json"
        environment["HANLIN_METADATA_EXPECTED_CONTEXT"] = str(context_path)
        environment["HANLIN_METADATA_ACTUAL_CONTEXT"] = str(module_root / "actual-generator-context.json")
        effective_path = module_root / "effective-compiler-context.bin"
        environment["HANLIN_METADATA_EFFECTIVE_CONTEXT"] = str(effective_path)
        arguments = capture_compiler_arguments(adapter, environment, arch, context_path, generator_root)
        verify_role_context(arguments)
        metadata_compiler = capture_native_compiler_context(tool, json.loads(context_path.read_text()),
            environment, generator_root, effective_path)
        (module_root / "effective-compiler-context.json").write_text(json.dumps(metadata_compiler, indent=2) + "\n")
        arguments = metadata_compiler["arguments"]
        verify_role_context(arguments)
        # Reclassify ALL final, post-staging bytes at the exact captured context.
        # Never promote a stale receipt by updating hashes alone.
        for directory in role_roots:
            produce_role_inventory(directory, arguments, library, receipt_path=receipts[str(directory)], metadata_compiler=metadata_compiler)
        inventory = write_public_umbrella(Path(required_env("SDKROOT")), umbrella,
            sorted(core_support_dir.glob("*.h")) + swift_headers, directories, receipts, arguments, metadata_compiler)
    finally:
        for path in [umbrella, umbrella.with_suffix(".inventory.json"), alias_overlay,
                     alias_overlay.with_suffix(".evidence.json"), tool_root / "provenance.json",
                     module_root / "actual-compiler-arguments.json", module_root / "effective-compiler-context.bin",
                     module_root / "effective-compiler-context.json", module_root / "effective-compiler-context.log", *receipts.values()]:
            if path.is_file():
                shutil.copy2(path, evidence / path.name)
    completed = subprocess.run(
        [sys.executable, str(adapter), *sys.argv[1:]],
        cwd=generator_root,
        env=environment,
        check=False,
    )
    actual_context = module_root / "actual-generator-context.json"
    if actual_context.is_file():
        shutil.copy2(actual_context, evidence / actual_context.name)
    complete = retain_and_check_metadata(arch, platform_name)
    return completed.returncode if completed.returncode else (0 if complete else 1)

if __name__ == "__main__":
    raise SystemExit(main())
