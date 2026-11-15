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

# Permanent non-success for production entry: tracing never generated metadata.
# Only the explicitly selected diagnostic probe interprets this sentinel.
DIAGNOSTIC_ONLY_EXIT = 3
DIAGNOSTIC_EVIDENCE_FAILURE_EXIT = 4


def required_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"Hanlin NativeScript metadata: missing Xcode environment variable {name}")
    return value


def validate_modern_tool(root: Path) -> tuple[Path, Path]:
    """Bind the opt-in candidate to its actual source and complete frontend inputs."""
    tool_root = root / "build/nativescript-modern-metadata-tool"
    tool = tool_root / "bin/objc-metadata-generator"
    receipt = json.loads((tool_root / "provenance.json").read_text(encoding="utf-8"))
    sources = {"basePatchSourceSHA256": "build-metadata-tool.py",
               "modernPatchSourceSHA256": "build-modern-metadata-tool.py",
               "frontendLockSHA256": "metadata-frontend-lock.json"}
    digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    if receipt.get("schemaVersion") != 2 or receipt.get("status") != "BUILT_NOT_ACCEPTED" or \
       receipt.get("generatorSHA256") != digest(tool) or any(
           receipt.get(key) != digest(root / "Scripts/NativeScript" / name) for key, name in sources.items()):
        raise RuntimeError("Modern metadata source/binary provenance mismatch")
    lock = json.loads((root / "Scripts/NativeScript/metadata-frontend-lock.json").read_text(encoding="utf-8"))
    support = {p.relative_to(root).as_posix(): digest(p) for p in sorted((root / "Scripts/NativeScript/metadata-dual-grammar").glob("*")) if p.suffix in {".h", ".cpp", ".py"}}
    if not support or receipt.get("supportSources") != support:
        raise RuntimeError("Modern metadata support source closure mismatch")
    prefix = Path(lock["installedPrefix"]).resolve(strict=True)
    library = prefix / "lib/libclang.dylib"
    if receipt.get("frontendRoot") != str(prefix) or receipt.get("classifierLibrary") != str(library) or \
       receipt.get("frontendVersion") != lock["version"]:
        raise RuntimeError("Modern metadata classifier/generator frontend identity mismatch")
    inputs = {**receipt.get("frontendInputs", {}), **lock["files"],
              **{"lib/" + name: value for name, value in receipt.get("libraries", {}).items()}}
    if not receipt.get("frontendInputs") or not receipt.get("libraries") or any(
        Path(name).is_absolute() or ".." in Path(name).parts or digest(prefix / name) != value
        for name, value in inputs.items()):
        raise RuntimeError("Modern metadata frontend headers/resources/libraries changed")
    return tool_root, library


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


def validate_preprocessing_receipt(receipt: dict, request: dict) -> list[str]:
    """Pure structural/binding gate; never confers metadata/API/ABI acceptance."""
    if not isinstance(receipt, dict):
        return ["receipt-schema"]
    failures = []
    if type(receipt.get("schemaVersion")) is not int or receipt["schemaVersion"] != 1 or receipt.get("mode") != "preprocessing-provenance":
        failures.append("receipt-schema")
    if receipt.get("bindings") != request["bindings"]:
        failures.append("receipt-binding-drift")
    if receipt.get("status") != "COMPLETE":
        failures.append("native-preprocessing-incomplete")
    for key in ["sawEOF", "endOfMainFile", "actionEnded"]:
        if receipt.get(key) is not True:
            failures.append(key)
    for key in ["hadASTContext", "hadSema", "hadErrors", "serializedContext", "truncated"]:
        if receipt.get(key) is not False:
            failures.append(key)
    for key in ["diagnosticErrors", "lookupMisses", "unknownOwners", "uncorrelated", "unprovenPragmas", "consumerEntries", "writerEntries"]:
        if type(receipt.get(key)) is not int or receipt[key] != 0:
            failures.append(key)
    observed = receipt.get("observedInputs")
    if not isinstance(observed, list) or any(not isinstance(item, dict) or not isinstance(item.get("path"), str)
            or not item["path"].startswith("/") or not isinstance(item.get("sha256"), str)
            or re.fullmatch(r"[0-9a-f]{64}", item["sha256"]) is None for item in observed):
        failures.append("observed-input-schema")
    if not isinstance(receipt.get("events"), list) or any(not isinstance(event, dict) for event in receipt["events"]):
        failures.append("event-schema")
    roots = receipt.get("roots", [])
    if not isinstance(roots, list) or len(roots) != len(request["roots"]) or type(receipt.get("expectedRootOccurrences")) is not int or receipt["expectedRootOccurrences"] != len(request["roots"]):
        failures.append("root-occurrence-coverage")
        return failures
    resolved = inactive = 0
    for expected, actual in zip(request["roots"], roots):
        if not isinstance(actual, dict):
            failures.append("root-occurrence-schema")
            continue
        if any(type(actual.get(key)) is not int for key in ["ordinal", "line"]):
            failures.append("root-occurrence-types")
        if any(actual.get(key) != expected[key] for key in ["ordinal", "line", "path", "owner", "sha256"]):
            failures.append("root-occurrence-identity")
        if actual.get("state") == "resolved":
            resolved += 1
            if actual.get("resolvedPath") != expected["path"] or actual.get("observedOwner") != expected["owner"]:
                failures.append("resolved-root-owner")
        elif actual.get("state") == "inactive":
            inactive += 1
            if actual.get("resolvedPath") or actual.get("observedOwner"):
                failures.append("inactive-is-not-resolved")
        else:
            failures.append("unresolved-root-occurrence")
    if any(type(receipt.get(key)) is not int for key in ["resolvedRootOccurrences", "inactiveRootOccurrences"]) or receipt.get("resolvedRootOccurrences") != resolved or receipt.get("inactiveRootOccurrences") != inactive:
        failures.append("root-occurrence-counts")
    if receipt.get("reasons") != []:
        failures.append("native-incomplete-reasons")
    return failures


def capture_preprocessing_provenance(tool: Path, plan: dict, context: dict, environment: dict,
                                    cwd: Path, module_root: Path, inventory: list[dict],
                                    umbrella: Path, inventory_path: Path, overlay: Path,
                                    patch_source: Path, tool_provenance: Path) -> dict:
    """Opt-in diagnostic transport. No final metadata invocation or alias bypass."""
    request_path = module_root / "preprocessing-provenance-inputs.json"
    native_path = module_root / "preprocessing-provenance.native.json"
    output_path = module_root / "preprocessing-provenance.json"
    log_path = module_root / "preprocessing-provenance.log"
    summary = {"schemaVersion": 1, "status": "INCOMPLETE", "metadataExecution": "NOT_RUN_DIAGNOSTIC_ONLY",
               "reason": "diagnostic-not-completed"}
    # New outputs must not replace an old receipt, input, canary, or symlink.
    for path in [request_path, native_path, output_path, log_path]:
        if path.exists() or path.is_symlink():
            raise RuntimeError("Diagnostic output already exists: " + str(path))
    call = plan["generatorCall"]
    if Path(call[0]).resolve() != tool.resolve() or Path(plan["workingDirectory"]).resolve() != cwd.resolve():
        raise RuntimeError("Diagnostic tool/cwd differs from captured invocation")
    ignored = {"HANLIN_METADATA_CAPTURE_ARGUMENTS", "HANLIN_METADATA_EXPECTED_CONTEXT", "HANLIN_METADATA_ACTUAL_CONTEXT"}
    environment_sha = hashlib.sha256(json.dumps({key: value for key, value in environment.items()
        if key not in ignored}, sort_keys=True).encode()).hexdigest()
    if environment_sha != plan["environmentSHA256"]:
        raise RuntimeError("Diagnostic environment differs from captured invocation")
    provenance = json.loads(tool_provenance.read_text(encoding="utf-8"))
    if provenance.get("patchSourceSHA256") != hashlib.sha256(patch_source.read_bytes()).hexdigest() or provenance.get("generatorSHA256") != hashlib.sha256(tool.read_bytes()).hexdigest():
        raise RuntimeError("Instrumented binary/source provenance mismatch")
    arguments = context["arguments"]
    owners = [{"root": str(Path(row["path"]).resolve()), "id": "framework:" + str(Path(row["path"]).resolve())}
              for row in inventory if row["status"] == "SELECTED"]
    sdk = Path(arguments[arguments.index("-isysroot") + 1]).resolve()
    owners.append({"root": str(sdk), "id": "selected-sdk"})
    for argument in arguments:
        if argument.startswith("-idirafter"):
            directory = Path(argument[len("-idirafter"):])
            if not directory.is_absolute():
                directory = cwd / directory
            if directory.is_dir():
                owners.append({"root": str(directory.resolve()), "id": "captured-include:" + str(directory.resolve())})
    def owner_for(path):
        candidates = [owner for owner in owners if path == Path(owner["root"]) or Path(owner["root"]) in path.parents]
        return max(candidates, key=lambda value: len(value["root"]))["id"] if candidates else None
    roots = []
    for line, text in enumerate(umbrella.read_text(encoding="utf-8").splitlines(), 1):
        match = re.fullmatch(r'\s*#\s*(?:import|include)\s+["<]([^">]+)[">]\s*', text)
        if not match:
            if text.strip():
                raise RuntimeError("Production umbrella contains an unbound directive")
            continue
        name = match[1]
        path = (sdk / "System/Library/Frameworks/UIKit.framework/Headers/UIKit.h") if name == "UIKit/UIKit.h" else Path(name)
        path = path.resolve(strict=True)
        for row in inventory:
            for header in row.get("publicUmbrellaHeaders", []):
                if Path(header["path"]).resolve() == path and hashlib.sha256(path.read_bytes()).hexdigest() != header["sha256"]:
                    raise RuntimeError("Diagnostic public root differs from inventory")
        owner = owner_for(path)
        if owner is None:
            owners.append({"root": str(path.parent), "id": "explicit-root:" + str(path.parent)})
            owner = owner_for(path)
        roots.append({"ordinal": len(roots), "line": line, "path": str(path), "owner": owner,
                      "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    if not roots:
        raise RuntimeError("Diagnostic umbrella has no root occurrences")
    verified = [umbrella, inventory_path, overlay, tool, patch_source, tool_provenance,
                module_root / "effective-compiler-context.bin", *[Path(root["path"]) for root in roots]]
    for row in inventory:
        if row["status"] != "SELECTED":
            continue
        for relative, expected_sha in row.get("inputSHA256", {}).items():
            path = Path(row["path"]) / relative
            if hashlib.sha256(path.read_bytes()).hexdigest() != expected_sha:
                raise RuntimeError("Diagnostic framework input differs from inventory")
            verified.append(path)
    for index, argument in enumerate(arguments):
        if argument.startswith("-fmodule-map-file="):
            verified.append(Path(argument.split("=", 1)[1]))
        elif argument == "-ivfsoverlay":
            verified.append(Path(arguments[index + 1]))
    verified = list(dict.fromkeys(verified))
    bindings = {"contextSHA256": context["contextSHA256"],
        "umbrellaSHA256": hashlib.sha256(umbrella.read_bytes()).hexdigest(),
        "inventorySHA256": hashlib.sha256(inventory_path.read_bytes()).hexdigest(),
        "overlaySHA256": hashlib.sha256(overlay.read_bytes()).hexdigest(),
        "instrumentedBinarySHA256": hashlib.sha256(tool.read_bytes()).hexdigest(),
        "patchSourceSHA256": hashlib.sha256(patch_source.read_bytes()).hexdigest(),
        "toolProvenanceSHA256": hashlib.sha256(tool_provenance.read_bytes()).hexdigest(),
        "environmentSHA256": plan["environmentSHA256"], "cwd": str(cwd.resolve()),
        "compiler": context["compiler"]}
    prefixes = []
    for row in inventory:
        if row["status"] != "SELECTED":
            continue
        base = Path(row["path"]).resolve()
        if row["framework"] == "jsi.framework":
            prefixes.append(str(base / "Headers"))
        elif row["framework"] in {"NativeScript.framework", "react.framework"}:
            prefixes.append(str(base / "Headers/jsi"))
    request = {"schemaVersion": 1, "bindings": bindings, "roots": roots, "owners": owners,
        "filteredPrefixes": prefixes,
        "verifiedFiles": [{"path": str(path.resolve()), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in verified]}
    # Snapshot existing normal output trees, including directory/symlink identity.
    normal_options = {"-output-bin", "-output-yaml", "-output-typescript", "-output-modulemaps", "-output-umbrella"}
    normal_paths = [(Path(call[i + 1]) if Path(call[i + 1]).is_absolute() else cwd / call[i + 1])
                    for i, value in enumerate(call[:-1]) if value in normal_options]
    for path in [request_path, native_path, output_path, log_path]:
        if any(path.resolve() == normal.resolve() or normal.resolve() in path.resolve().parents for normal in normal_paths):
            raise RuntimeError("Diagnostic output collides with normal output")
    def snapshot():
        result = {}
        for path in normal_paths:
            entries = [path, *(path.rglob("*") if path.is_dir() and not path.is_symlink() else [])]
            for entry in entries:
                result[str(entry)] = ("symlink", os.readlink(entry)) if entry.is_symlink() else (
                    ("file", hashlib.sha256(entry.read_bytes()).hexdigest()) if entry.is_file() else
                    ("directory", None) if entry.is_dir() else ("absent", None))
        return result
    before = snapshot()
    request_path.write_text(json.dumps(request, indent=2) + "\n", encoding="utf-8")
    output_path.write_text(json.dumps(summary) + "\n", encoding="utf-8")
    split = call.index("Xclang")
    diagnostic_call = [*call[:split], "-hanlin-preprocess-provenance", str(native_path),
                       "-hanlin-provenance-inputs", str(request_path), *call[split:]]
    try:
        with log_path.open("x", encoding="utf-8") as log:
            completed = subprocess.run(diagnostic_call, cwd=cwd, env=environment, stdout=log,
                                       stderr=subprocess.STDOUT, check=False, timeout=180)
        native_value = json.loads(native_path.read_text(encoding="utf-8")) if native_path.is_file() else {}
        failures = validate_preprocessing_receipt(native_value, request)
        native = native_value if isinstance(native_value, dict) else {}
        if completed.returncode:
            failures.append("native-exit-" + str(completed.returncode))
        for item in request["verifiedFiles"]:
            if hashlib.sha256(Path(item["path"]).read_bytes()).hexdigest() != item["sha256"]:
                failures.append("input-content-drift")
        if isinstance(native.get("observedInputs"), list) and "observed-input-schema" not in failures:
            for item in native["observedInputs"]:
                if hashlib.sha256(Path(item["path"]).read_bytes()).hexdigest() != item["sha256"]:
                    failures.append("observed-input-content-drift")
        if native.get("requestSHA256") != hashlib.sha256(request_path.read_bytes()).hexdigest():
            failures.append("request-drift")
        if snapshot() != before:
            failures.append("normal-output-canary-changed")
        summary.update(status="COMPLETE" if not failures else "INCOMPLETE", failures=failures,
                       native=native, bindings=bindings, reason="diagnostic-only-no-metadata-acceptance")
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        summary.update(reason=type(error).__name__ + ": " + str(error))
    output_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


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


def retain_diagnostic_evidence(inventory, module_root, evidence, diagnostic_result):
    """Called ONLY in explicit diagnostic mode; never mask a primary failure."""
    failures = []
    selected = {"status": "NOT_RETAINED", "reason": "selected umbrella not discovered"}
    try:
        for row in inventory:
            if row["framework"] != "ExpoModulesCore.framework" or row["status"] != "SELECTED":
                continue
            for header in row["publicUmbrellaHeaders"]:
                path = Path(header["path"])
                if path.name != "ExpoModulesCore_umbrella.h":
                    continue
                selected = {"status": "INCOMPLETE", "path": str(path), "expectedSHA256": header["sha256"]}
                with path.open("rb") as source:
                    body = source.read(128 * 1024 + 1)
                selected["actualSHA256"] = hashlib.sha256(body).hexdigest()
                if len(body) > 128 * 1024 or selected["actualSHA256"] != header["sha256"]:
                    raise RuntimeError("Selected diagnostic header size/hash mismatch")
                (evidence / "selected-ExpoModulesCore_umbrella.h").write_bytes(body)
                selected.update(status="RETAINED_EXACT", bytes=len(body))
        (evidence / "selected-public-header.json").write_text(json.dumps(selected, indent=2) + "\n", encoding="utf-8")
    except Exception as error:
        failures.append("selected-header: " + type(error).__name__ + ": " + str(error))
    for name in ["preprocessing-provenance-inputs.json", "preprocessing-provenance.native.json", "preprocessing-provenance.log"]:
        try:
            source = module_root / name
            if source.is_file():
                shutil.copy2(source, evidence / name)
        except Exception as error:
            failures.append(name + ": " + type(error).__name__ + ": " + str(error))
    diagnostic_result = dict(diagnostic_result or {"schemaVersion": 1, "status": "INCOMPLETE"})
    diagnostic_result["metadataExecution"] = "NOT_GENERATED"
    if failures:
        diagnostic_result.update(status="INCOMPLETE", diagnosticEvidenceFailures=failures)
    try:
        (evidence / "preprocessing-provenance.json").write_text(json.dumps(diagnostic_result, indent=2) + "\n", encoding="utf-8")
    except Exception as error:
        failures.append("diagnostic-receipt: " + type(error).__name__ + ": " + str(error))
    if failures:
        # stderr survives even if the evidence destination is unwritable. The
        # caller also returns a different non-success code when no primary
        # exception is already propagating; stale COMPLETE files cannot pass.
        print("Hanlin diagnostic evidence INCOMPLETE: " + "; ".join(failures), file=sys.stderr)
    return not failures


def generate_final_metadata(root, arch, platform_name, module_root, module_map, runtime_header, generator_root, upstream_generator):
    swift_headers = write_swift_module_map(module_map, runtime_header, arch)
    environment = os.environ.copy()
    from metadata_public_headers import (write_public_umbrella, write_verified_header_alias_overlay,
        produce_role_inventory, ROLE_MANIFEST, verify_role_context)
    core_support_dir = root / "Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptCoreSupport/include"
    frontend_mode = environment.get("HANLIN_METADATA_FRONTEND", "legacy")
    if frontend_mode not in {"legacy", "modern-candidate"}:
        raise RuntimeError("Unknown metadata frontend selection")
    modern = frontend_mode == "modern-candidate"
    tool_root = root / "build/nativescript-metadata-tool"
    modern_library = None
    if modern:
        tool_root, modern_library = validate_modern_tool(root)
    tool = tool_root / "bin/objc-metadata-generator"
    provenance = json.loads((tool_root / "provenance.json").read_text())
    if not modern and (hashlib.sha256(tool.read_bytes()).hexdigest() != provenance["generatorSHA256"] or \
       provenance["patchSourceSHA256"] != hashlib.sha256((root / "Scripts/NativeScript/build-metadata-tool.py").read_bytes()).hexdigest()):
        raise RuntimeError("Metadata build-tool provenance does not match actual inputs")
    umbrella = module_root / "HanlinMetadataInput.h"
    evidence = root / "build/acceptance/nativescript-metadata" / f"{platform_name}-{arch}"
    evidence.mkdir(parents=True, exist_ok=True)
    alias_overlay = module_root / "HanlinHeaderAliases.json"
    alias_validation = module_root / "header-alias-validation.json"
    adapter = module_root / "build-step-metadata-generator-adapter.py"
    adapter.write_text(explicit_input_adapter(upstream_generator.read_text()), encoding="utf-8")
    environment["HANLIN_METADATA_GENERATOR"] = str(tool)
    environment["HANLIN_METADATA_INPUT_UMBRELLA"] = str(umbrella)
    environment["CLANG_ENABLE_MODULES"] = "NO"
    original_cflags = environment.get("OTHER_CFLAGS", "")
    if modern:
        from metadata_public_headers import MODERN_CPP_ARGUMENTS
        original_cflags = shlex.join([*shlex.split(original_cflags), *MODERN_CPP_ARGUMENTS])
    environment["OTHER_CFLAGS"] = f'{original_cflags} {metadata_flags(module_root, module_map, core_support_dir)}'.strip()
    directories = [Path(p) for p in shlex.split(environment.get("FRAMEWORK_SEARCH_PATHS", ""))]
    role_roots = list(dict.fromkeys(p.resolve() for p in directories if (p / ROLE_MANIFEST).is_file()))
    receipts = {str(directory): module_root / f"input-roles-{n}.json" for n, directory in enumerate(role_roots)}
    diagnostic_mode = environment.get("HANLIN_METADATA_PREPROCESS_PROVENANCE", "0")
    if diagnostic_mode not in {"0", "1"}:
        raise RuntimeError("Invalid preprocessing provenance opt-in")
    if modern and diagnostic_mode == "1":
        raise RuntimeError("Modern diagnostic wrapper is not accepted; use retained standalone controls")
    diagnostic_result = None
    diagnostic_evidence_ok = False
    inventory = []
    try:
        library = None
        if role_roots:
            if modern:
                library = modern_library
            else:
                clang = Path(subprocess.check_output(["xcrun", "--find", "clang"], text=True).strip()).resolve()
                library = clang.parent.parent / "lib/libclang.dylib"
            # First inventory only discovers ownership/aliases; it grants no include-only role.
            for directory in role_roots:
                produce_role_inventory(directory, [], library, classify=False, receipt_path=receipts[str(directory)])
        inventory = write_public_umbrella(Path(required_env("SDKROOT")), umbrella,
            sorted(core_support_dir.glob("*.h")) + swift_headers, directories, receipts)
        # Capture the real frontend vector even when a later alias validation
        # rejects the inputs. The tool's dump exits before parsing/emission.
        # Keep the same overlay argument for capture and final execution; the
        # empty discovery overlay grants no aliases or language-role exemption.
        alias_overlay.write_text(json.dumps({"version": 0, "use-external-names": True, "roots": []}) + "\n", encoding="utf-8")
        alias_validation.write_text(json.dumps({"status": "PENDING"}) + "\n", encoding="utf-8")
        environment["OTHER_CFLAGS"] = f'{original_cflags} {metadata_flags(module_root, module_map, core_support_dir, alias_overlay)}'.strip()
        context_path = module_root / "actual-compiler-arguments.json"
        environment["HANLIN_METADATA_EXPECTED_CONTEXT"] = str(context_path)
        environment["HANLIN_METADATA_ACTUAL_CONTEXT"] = str(module_root / "actual-generator-context.json")
        effective_path = module_root / "effective-compiler-context.bin"
        environment["HANLIN_METADATA_EFFECTIVE_CONTEXT"] = str(effective_path)
        arguments = capture_compiler_arguments(adapter, environment, arch, context_path, generator_root)
        verify_role_context(arguments)
        metadata_compiler = capture_native_compiler_context(tool, json.loads(context_path.read_text()),
            environment, generator_root, effective_path)
        if modern:
            from metadata_public_headers import compiler_version
            if metadata_compiler.get("compiler") != compiler_version(modern_library):
                raise RuntimeError("Actual modern classifier and generator compiler identities differ")
            (module_root / "metadata-frontend.json").write_text(json.dumps({
                "status": "CANDIDATE_NOT_ACCEPTED", "frontend": "modern-candidate",
                "rootPolicy": "ALL_PUBLIC_INPUTS_RETAINED", "includeOnlyExemptions": 0,
                "compiler": metadata_compiler["compiler"],
                "generatorSHA256": hashlib.sha256(tool.read_bytes()).hexdigest(),
                "classifierLibrarySHA256": hashlib.sha256(modern_library.read_bytes()).hexdigest(),
                "contextSHA256": metadata_compiler["contextSHA256"]}, indent=2) + "\n", encoding="utf-8")
        (module_root / "effective-compiler-context.json").write_text(json.dumps(metadata_compiler, indent=2) + "\n")
        arguments = metadata_compiler["arguments"]
        verify_role_context(arguments)
        if diagnostic_mode == "1":
            try:
                diagnostic_result = capture_preprocessing_provenance(tool, json.loads(context_path.read_text()),
                    metadata_compiler, environment, generator_root, module_root, inventory, umbrella,
                    umbrella.with_suffix(".inventory.json"), alias_overlay,
                    root / "Scripts/NativeScript/build-metadata-tool.py", tool_root / "provenance.json")
            except (RuntimeError, OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
                diagnostic_result = {"schemaVersion": 1, "status": "INCOMPLETE",
                    "metadataExecution": "NOT_RUN_DIAGNOSTIC_ONLY", "reason": type(error).__name__ + ": " + str(error)}
        try:
            aliases = write_verified_header_alias_overlay(inventory, alias_overlay)
        except RuntimeError as error:
            alias_validation.write_text(json.dumps({"status": "FAILED", "reason": str(error)}) + "\n", encoding="utf-8")
            raise
        alias_validation.write_text(json.dumps({"status": "VERIFIED", "contractVersion": 2,
            "aliases": sum(r["disposition"] == "VERIFIED_EQUIVALENT" for r in aliases),
            "notAliased": sum(r["disposition"] == "NOT_ALIASED" for r in aliases)}) + "\n", encoding="utf-8")
        if diagnostic_mode == "0":
            # Reclassify ALL final, post-staging bytes at the exact captured context.
            # Never promote a stale receipt by updating hashes alone.
            for directory in role_roots:
                # The modern candidate parses every root in ObjC++; grant no
                # include-only exemption and retain all actual public inputs.
                produce_role_inventory(directory, arguments, library, classify=not modern,
                    receipt_path=receipts[str(directory)], metadata_compiler=metadata_compiler)
            inventory = write_public_umbrella(Path(required_env("SDKROOT")), umbrella,
                sorted(core_support_dir.glob("*.h")) + swift_headers, directories, receipts, arguments, metadata_compiler)
    finally:
        for path in [umbrella, umbrella.with_suffix(".inventory.json"), alias_overlay, alias_validation,
                     alias_overlay.with_suffix(".evidence.json"), tool_root / "provenance.json",
                     module_root / "actual-compiler-arguments.json", module_root / "effective-compiler-context.bin",
                     *([module_root / "metadata-frontend.json"] if modern else []),
                     module_root / "effective-compiler-context.json", module_root / "effective-compiler-context.log", *receipts.values()]:
            if path.is_file():
                shutil.copy2(path, evidence / path.name)
        if diagnostic_mode == "1":
            try:
                diagnostic_evidence_ok = retain_diagnostic_evidence(inventory, module_root, evidence, diagnostic_result)
            except Exception as error:
                # A diagnostic-only evidence failure must not replace the
                # alias/source exception that is already unwinding this try.
                diagnostic_evidence_ok = False
                try:
                    print("Hanlin diagnostic evidence INCOMPLETE: " + type(error).__name__ + ": " + str(error), file=sys.stderr)
                except Exception:
                    pass  # Neither writable receipt nor stderr; exit4 stays non-success.
    if diagnostic_mode == "1":
        # Even a complete trace with verified aliases is a failed production
        # generation invocation. Never inspect/accept a prior metadata binary.
        return DIAGNOSTIC_ONLY_EXIT if diagnostic_evidence_ok else DIAGNOSTIC_EVIDENCE_FAILURE_EXIT
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
