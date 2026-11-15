#!/usr/bin/env python3
"""Run the pinned real metadata generator against the selected Apple SDK.

No app/engine build, simulator, Swift-header stand-in, SDK modification or VM
acceptance claim. The probe includes actual UIKit and Host ObjC headers.
"""
import hashlib
import importlib.util
import argparse
import json
import os
from pathlib import Path
import platform
import re
import shlex
import subprocess
import sys


def capture(*args: str) -> str:
    return subprocess.check_output(args, text=True).strip()


def replay_final_header_staging(root: Path, folder: Path) -> dict:
    """Replay existing production header mutations, without its signing/build steps."""
    sys.path.insert(0, str(root / "Scripts/NativeScript"))
    from metadata_public_headers import framework_inputs
    artifacts = root / "Packages/HanlinExpoRuntime/Artifacts"
    modular = artifacts / "ModularFrameworks"
    before = {p.name: framework_inputs(p) for p in modular.glob("*.framework")}
    script = root / "Scripts/CI/stage_modular_headers.py"
    spec = importlib.util.spec_from_file_location("hanlin_actual_header_staging", script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    staging_root = folder / "final-stage"
    packages = staging_root / "SourcePackages"
    derived = staging_root / "DerivedData"
    packages.mkdir(parents=True, exist_ok=True)
    patcher = root / "Scripts/Expo/patch-hash-combine.mjs"
    with (folder / "final-header-staging.log").open("w") as log:
        import contextlib
        with contextlib.redirect_stdout(log), contextlib.redirect_stderr(log):
            result = module.stage_modular_headers(packages, artifacts, derived_data_dir=derived,
                configurations=["Debug"], force=True, sign_xcframeworks=False)
    if result["status"] != "SUCCESS":
        raise RuntimeError("Actual final header staging did not succeed")
    after = {p.name: framework_inputs(p) for p in modular.glob("*.framework")}
    changes = []
    for framework in sorted(set(before) | set(after)):
        for path in sorted(set(before.get(framework, {})) | set(after.get(framework, {}))):
            old, new = before.get(framework, {}).get(path), after.get(framework, {}).get(path)
            if old != new:
                changes.append({"framework": framework, "path": path, "beforeSHA256": old, "afterSHA256": new})
    evidence = {"stageSourceSHA256": hashlib.sha256(script.read_bytes()).hexdigest(),
        "patcherSourceSHA256": hashlib.sha256(patcher.read_bytes()).hexdigest(), "changes": changes,
        "stagingResult": result, "sourcePackages": str(packages), "derivedData": str(derived),
        "signXCFrameworks": False,
        "boundary": "Complete actual production header staging/copy/materialization; owned temporary outputs, no signing or engine build."}
    (folder / "final-header-staging.json").write_text(json.dumps(evidence, indent=2) + "\n")
    return evidence


def diagnostic_probe_outcome(exit_code: int, diagnostic: dict, aliases: dict) -> dict:
    """Interpret exit3 ONLY for this explicit diagnostic probe, never metadata."""
    complete = exit_code == 3 and diagnostic.get("status") == "COMPLETE" \
        and diagnostic.get("metadataExecution") == "NOT_GENERATED" and aliases.get("status") == "VERIFIED"
    return {"diagnosticStatus": "COMPLETE" if complete else "INCOMPLETE", "metadataExecution": "NOT_GENERATED"}


def probe_runtime_wrapper(root: Path, output: Path, original_generator: Path, arch: str,
                          preprocessing_provenance: bool = False) -> dict:
    """Exercise the actual launcher with a genuinely compiled Swift interface."""
    folder = output / "runtime-wrapper"
    folder.mkdir(exist_ok=True)
    with (folder / "prepare.log").open("w") as log:
        subprocess.run(["node", str(root / "Scripts/NativeScript/prepare-ios-dependencies.mjs")],
                       cwd=root, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=180)
    # Real pinned Expo headers/maps, including the C++ include-only shims that
    # caused the full-app failure. This mode does not compile JSI/engines or
    # invoke the Native API build/signing path.
    with (folder / "expo-prepare.log").open("w") as log:
        subprocess.run(["node", str(root / "Scripts/Expo/prepare-ios-dependencies.mjs"), "--metadata-inputs-only"],
                       cwd=root, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=300)
    final_staging = replay_final_header_staging(root, folder)
    package = root / "Packages/HanlinNativeScriptRuntime"
    document = json.loads(subprocess.check_output(["xcodebuild", "-list", "-json"], cwd=package, text=True))
    schemes = (document.get("workspace") or document.get("project") or {}).get("schemes", [])
    preferred = "HanlinNativeScriptRuntime-Package"
    scheme = preferred if preferred in schemes else schemes[0] if len(schemes) == 1 else None
    if scheme is None:
        raise RuntimeError("Actual NativeScript package scheme is ambiguous")
    derived = root / "build/NativeScriptMetadataProbeDerivedData"
    command = ["xcodebuild", "-scheme", scheme, "-configuration", "Debug", "-destination",
               "generic/platform=iOS Simulator", "-derivedDataPath", str(derived),
               "CODE_SIGNING_ALLOWED=NO", f"ARCHS={arch}", "ONLY_ACTIVE_ARCH=YES"]
    with (folder / "package-build.log").open("w") as log:
        built = subprocess.run([*command, "build"], cwd=package, stdout=log, stderr=subprocess.STDOUT, timeout=480)
    if built.returncode:
        return {"status": "FAILED", "stage": "actual Swift package compilation", "exitCode": built.returncode}
    compilation = None
    frameworks = []
    for line in (folder / "package-build.log").read_text().splitlines():
        if "-module-name HanlinNativeScriptRuntime " not in line:
            continue
        args = shlex.split(line)
        if "-emit-objc-header-path" not in args:
            continue
        compilation = {key: args[args.index(key) + 1] for key in ["-sdk", "-target", "-emit-objc-header-path"]}
        for index, arg in enumerate(args):
            if arg == "-F" and index + 1 < len(args):
                frameworks.append(args[index + 1])
            elif arg.startswith("-F") and len(arg) > 2:
                frameworks.append(arg[2:])
        break
    if compilation is None:
        raise RuntimeError("Successful build did not retain its actual provider Swift compiler invocation")
    # Keep the observed compiler's -F order, then append the genuine staged
    # framework slices in the producer lock's order. Never sort these paths.
    frameworks = list(dict.fromkeys(frameworks))
    artifacts = root / "Packages/HanlinExpoRuntime/Artifacts"
    lock = json.loads((root / "Scripts/Expo/dependency-lock.json").read_text())
    expo_frameworks = []
    for item in lock["artifacts"]:
        target = root / item["target"]
        for slice_path in sorted(target.glob("*simulator*")):
            if any(slice_path.glob("*.framework")):
                expo_frameworks.append(str(slice_path))
    modular = artifacts / "ModularFrameworks"
    frameworks = list(dict.fromkeys([*frameworks, *expo_frameworks, str(modular)]))
    role_receipt = modular / "metadata-input-roles.json"
    if not role_receipt.is_file():
        raise RuntimeError("Actual Expo producer did not retain its input-role receipt")
    (folder / ("staged-" + role_receipt.name)).write_bytes(role_receipt.read_bytes())
    triple = re.fullmatch(r"(arm64|x86_64)-(apple)-ios([0-9.]+)-simulator", compilation["-target"])
    if triple is None:
        raise RuntimeError("Actual provider was not compiled for the requested Apple simulator")
    header = Path(compilation["-emit-objc-header-path"])
    if not header.is_file():
        raise RuntimeError("Actual compiler output Swift ObjC interface is missing")
    # SPM's synthetic product returns [] for -showBuildSettings. Stage a BYTE
    # COPY of its actual compiled header at the wrapper's normal Xcode input
    # location; do not synthesize a header or infer a Swift/ObjC API.
    intermediates = folder / "intermediates"
    staged_header = intermediates / "GeneratedModuleMaps-iphonesimulator" / header.name
    staged_header.parent.mkdir(parents=True, exist_ok=True)
    staged_header.write_bytes(header.read_bytes())
    (folder / header.name).write_bytes(header.read_bytes())
    environment = {**os.environ, "SRCROOT": str(root), "OBJROOT": str(intermediates),
        "SDKROOT": compilation["-sdk"], "SDK_VERSION": capture("xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"),
        "PLATFORM_NAME": "iphonesimulator", "EFFECTIVE_PLATFORM_NAME": "-iphonesimulator",
        "LLVM_TARGET_TRIPLE_VENDOR": triple.group(2), "LLVM_TARGET_TRIPLE_SUFFIX": "-simulator",
        "IPHONEOS_DEPLOYMENT_TARGET": triple.group(3), "GCC_C_LANGUAGE_STANDARD": "gnu17", "ARCHS": triple.group(1),
        "TARGET_TEMP_DIR": str(folder / "temp"), "CONFIGURATION_BUILD_DIR": str(folder / "products"),
        "PER_VARIANT_OBJECT_FILE_DIR": "", "NS_TYPESCRIPT_DECLARATIONS_PATH": str(folder / "types"),
        "FRAMEWORK_SEARCH_PATHS": shlex.join(frameworks),
        "HEADER_SEARCH_PATHS": shlex.join([str(root / "Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptCoreSupport/include"),
                                           str(modular / "react.framework/Headers"),
                                           str(modular / "react.framework/Headers/react")])}
    if preprocessing_provenance:
        environment["HANLIN_METADATA_PREPROCESS_PROVENANCE"] = "1"
    for name in ["TARGET_TEMP_DIR", "CONFIGURATION_BUILD_DIR"]:
        Path(environment[name]).mkdir(exist_ok=True)
    (folder / "build-inputs.json").write_text(json.dumps({"compilerInputs": compilation,
        "actualFrameworkSearchPaths": frameworks,
        "frameworkOrderSource": "Observed Swift compiler order followed by actual Expo lock staging order",
        "expoInputRoleReceiptSHA256": hashlib.sha256(role_receipt.read_bytes()).hexdigest(),
        "generatedSwiftHeaderSHA256": hashlib.sha256(header.read_bytes()).hexdigest(),
        "stagedSwiftHeaderSHA256": hashlib.sha256(staged_header.read_bytes()).hexdigest()}, indent=2) + "\n")
    with (folder / "wrapper.log").open("w") as log:
        execution = subprocess.run([sys.executable, str(original_generator.parent / "build-step-metadata-generator.py"), arch],
                                   cwd=original_generator.parent, env=environment, stdout=log,
                                   stderr=subprocess.STDOUT, timeout=180)
    visibility = root / "build/acceptance/nativescript-metadata" / f"iphonesimulator-{arch}" / "visibility.json"
    recorded = json.loads(visibility.read_text()) if visibility.is_file() else {}
    arguments_path = visibility.parent / "actual-compiler-arguments.json"
    actual_context = json.loads(arguments_path.read_text()) if arguments_path.is_file() else {}
    actual_arguments = actual_context.get("arguments", [])
    effective_path = visibility.parent / "effective-compiler-context.json"
    effective_context = json.loads(effective_path.read_text()) if effective_path.is_file() else {}
    aliases_path = visibility.parent / "header-alias-validation.json"
    alias_validation = json.loads(aliases_path.read_text()) if aliases_path.is_file() else {}
    diagnostic, selected_body = {}, {}
    if preprocessing_provenance:
        diagnostic_path = visibility.parent / "preprocessing-provenance.json"
        diagnostic = json.loads(diagnostic_path.read_text()) if diagnostic_path.is_file() else {}
        selected_path = visibility.parent / "selected-public-header.json"
        selected_body = json.loads(selected_path.read_text()) if selected_path.is_file() else {}
    if preprocessing_provenance:
        recorded = {}  # A previous binary/visibility file is never diagnostic evidence.
    for receipt in visibility.parent.glob("input-roles-*.json"):
        (folder / ("final-" + receipt.name)).write_bytes(receipt.read_bytes())
    # Names confirmed from current staged declarations, not synthetic APIs.
    public_names = ["EXExportedModule", "EXModuleRegistry", "RCTBridge", "RCTView", "RCTAppDelegate",
                    "RCTSwiftUIContainerViewWrapper", "YGNodeNew", "YGConfigNew", "YGNodeStyleSetWidth"]
    binary_path = Path(environment["CONFIGURATION_BUILD_DIR"]) / f"metadata-{arch}.bin"
    binary = binary_path.read_bytes() if binary_path.is_file() and not preprocessing_provenance else b""
    public_symbols = {name: name.encode() + b"\0" in binary for name in public_names}
    inventory_path = visibility.parent / "HanlinMetadataInput.inventory.json"
    inventory = json.loads(inventory_path.read_text()) if inventory_path.is_file() else []
    include_only = [r for r in inventory if r.get("status") == "INCLUDE_SEARCH_ONLY_CPP"]
    passed = execution.returncode == 0 and bool(recorded) and all(recorded["requiredMetadataStringsPresent"].values()) \
        and recorded.get("clangErrorCount") == 0 and all(public_symbols.values()) and bool(include_only)
    return {"status": "DIAGNOSTIC_ONLY" if preprocessing_provenance else "EXECUTED_PASS" if passed else "FAILED", "exitCode": execution.returncode,
            "python": sys.version, "generatedSwiftHeaderSHA256": hashlib.sha256(header.read_bytes()).hexdigest(),
            "visibility": recorded, "publicObjCAndCMetadataNames": public_symbols,
            "symbolChecksStatus": "EXECUTED" if binary else "NOT_RUN_NO_METADATA_BINARY",
            "actualMetadataCompilerArguments": actual_arguments, "actualMetadataContext": actual_context, "effectiveMetadataCompilerContext": effective_context, "actualSwiftProviderTarget": compilation["-target"],
            "headerAliasValidation": alias_validation,
            "preprocessingProvenance": diagnostic, "selectedPublicHeader": selected_body,
            **(diagnostic_probe_outcome(execution.returncode, diagnostic, alias_validation) if preprocessing_provenance
               else {"metadataExecution": "NORMAL_MODE"}),
            "finalHeaderStaging": final_staging,
            "includeOnlyFrameworks": [{"framework": r["framework"], "inputManifestSHA256": r["inputManifestSHA256"],
                                       "declarations": len(r["inputRoleProof"]["declarations"])} for r in include_only],
            "boundary": "Actual Swift compilation+combined SDK/Expo production metadata launcher; no app/VM/device execution."}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["modular", "textual", "textual-direct", "textual-ambient", "textual-public"],
                        default="textual-public")
    parser.add_argument("--generator", type=Path, help="Explicit separately built metadata-tool candidate")
    parser.add_argument("--emit-types", action="store_true", help="Retain actual selected-SDK TypeScript declarations")
    parser.add_argument("--language", choices=["objective-c", "objective-c++"], default="objective-c",
                        help="Explicit standalone candidate dialect; not production adoption")
    parser.add_argument("--runtime-wrapper", action="store_true", help="Compile the real provider and exercise the production metadata launcher")
    parser.add_argument("--preprocessing-provenance", action="store_true",
                        help="Opt-in diagnostic-only wrapper; requires future explicitly authorized native execution")
    options = parser.parse_args()
    if options.language != "objective-c" and (options.generator is None or options.runtime_wrapper):
        parser.error("Candidate ObjC++ dialect requires an explicit standalone generator proof")
    if options.preprocessing_provenance and (not options.runtime_wrapper or options.generator is None or options.emit_types):
        parser.error("--preprocessing-provenance requires --runtime-wrapper and --generator, without --emit-types")
    if sys.platform != "darwin":
        print(json.dumps({"status": "BLOCKED", "reason": "Actual macOS/Xcode SDK required"}))
        return 2
    root = Path(__file__).resolve().parents[2]
    arch = "arm64" if platform.machine() == "arm64" else "x86_64"
    internal = root / "Scripts/NativeScript/node_modules/@nativescript/ios/framework/internal"
    candidates = sorted(p for p in internal.glob(f"metadata-generator-{arch}*/bin/objc-metadata-generator") if p.is_file())
    if len(candidates) != 1:
        raise RuntimeError("Require exactly one pinned metadata generator for the runner architecture")
    generator = candidates[0]
    original_generator = generator
    if options.generator is not None:
        generator = options.generator.resolve(strict=True)
    package = json.loads((internal.parents[1] / "package.json").read_text())
    if package["version"] != "9.1.0":
        raise RuntimeError("Metadata probe requires the existing @nativescript/ios9.1.0 pin")
    sdk = Path(capture("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"))
    version = capture("xcrun", "--sdk", "iphonesimulator", "--show-sdk-version")
    resources = Path(capture("xcrun", "clang", "-print-resource-dir"))
    headers = root / "Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptCoreSupport/include"
    output = root / ("build/acceptance/nativescript-sdk-probe-cpp" if options.language == "objective-c++" else "build/acceptance/nativescript-sdk-probe")
    output.mkdir(parents=True, exist_ok=True)
    if options.preprocessing_provenance:
        if generator != (root / "build/nativescript-metadata-tool/bin/objc-metadata-generator").resolve():
            raise RuntimeError("Diagnostic candidate must match the production wrapper's instrumented tool")
        diagnostic = probe_runtime_wrapper(root, output, original_generator, arch, preprocessing_provenance=True)
        result = {"schemaVersion": 1, "status": "DIAGNOSTIC_ONLY", "metadataExecution": "NOT_GENERATED",
                  "diagnosticStatus": diagnostic.get("diagnosticStatus", "INCOMPLETE"),
                  "runtimeWrapper": diagnostic, "boundary": "Reachability only; no metadata/API/ABI/VM pass."}
        (output / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(result), flush=True)
        return 0 if diagnostic.get("diagnosticStatus") == "COMPLETE" else 2
    umbrella = output / "probe.h"
    umbrella.write_text('#import <UIKit/UIKit.h>\n#import "HanlinNativeServicesBridge.h"\n'
                        '#import "HanlinNativeScriptCompatibility.h"\n', encoding="utf-8")
    if options.mode == "textual-public":
        from metadata_public_headers import write_public_umbrella
        write_public_umbrella(sdk, umbrella, [headers / "HanlinNativeServicesBridge.h",
                                             headers / "HanlinNativeScriptCompatibility.h"])
    result = {"schemaVersion": 1, "nativeScriptIOS": package["version"], "sdk": str(sdk),
              "probePythonVersion": sys.version,
              "sdkVersion": version, "xcode": capture("xcodebuild", "-version"),
              "clangResourceDirectory": str(resources), "architecture": arch,
              "generatorSHA256": hashlib.sha256(generator.read_bytes()).hexdigest(), "modes": {},
              "originalPinnedGeneratorSHA256": hashlib.sha256(original_generator.read_bytes()).hexdigest(),
              "boundary": "Actual ObjC SDK metadata generation only; no app/Swift-provider/VM or physical-device pass."}
    required = ["HanlinNativeServicesBridge", "HanlinNativeServicesSessionBridge", "HanlinNativeScriptCompatibility", "UIView", "NSObject"]
    # Retain the selected SDK declarations that explain header search failures;
    # these are read-only inputs, never compatibility edits or feature overrides.
    context = []
    for path in [sdk / "usr/include/DarwinFoundation1.modulemap", sdk / "usr/include/math.h",
                 resources / "include/float.h"]:
        if path.is_file():
            lines = path.read_text(errors="replace").splitlines()
            context.append({"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                            "lines": [{"line": n, "text": line} for n, line in enumerate(lines, 1)
                                      if (path.name == "DarwinFoundation1.modulemap" and 270 <= n <= 335)
                                      or (path.name == "math.h" and 35 <= n <= 85)
                                      or path.name == "float.h"]})
    (output / "sdk-header-context.json").write_text(json.dumps(context, indent=2) + "\n")
    for mode in [options.mode]:
        destination = output / mode
        destination.mkdir(exist_ok=True)
        binary = destination / "metadata.bin"
        command = [str(generator), "-verbose", "-output-bin", str(binary),
                   "-output-umbrella", str(destination / "umbrella.h"),
                   "Xclang", "-isysroot", str(sdk), "-target", f"{arch}-apple-ios{version}-simulator",
                   "-std=gnu17", "-resource-dir", str(resources), "-I" + str(headers),
                   "-F" + str(sdk / "System/Library/SubFrameworks"),
                   "-fmodule-map-file=" + str(headers / "module.modulemap"),
                   "-fmodules" if mode == "modular" else "-fno-modules"]
        if options.language == "objective-c++":
            command.extend(["-x", "objective-c++", "-std=gnu++20", "-fno-cxx-modules"])
        if options.emit_types:
            command[1:1] = ["-output-typescript", str(destination / "types")]
        if mode in ["textual-direct", "textual-public"]:
            # The upstream generator parses an empty translation unit to discover
            # module headers before parsing its input umbrella. Avoid forcing
            # UIKit into that discovery pass; keep the actual same SDK headers
            # for the real metadata pass.
            command[1:1] = ["-input-umbrella", str(umbrella)]
            if mode == "textual-public":
                # Match the parser's own builtin headers; current SDK C headers
                # remain the selected SDK, with no edits or feature overrides.
                resource_index = command.index("-resource-dir")
                del command[resource_index:resource_index + 2]
        elif mode != "textual-ambient":
            command.extend(["-include", str(umbrella)])
        control = subprocess.run(["xcrun", "clang", "-x", "objective-c", "-fsyntax-only",
                                  *command[command.index("Xclang") + 1:], str(umbrella)],
                                 capture_output=True, timeout=120)
        (destination / "xcode-clang-control.log").write_bytes(control.stdout + control.stderr)
        if options.generator is not None:
            # Exercise the new read-only context mode on the genuine SDK input;
            # the existing SDK generation below verifies the identical vector.
            import importlib.util
            spec = importlib.util.spec_from_file_location("actual_metadata_launcher", root / "Scripts/NativeScript/build-step-metadata-generator-wrapper.py")
            launcher = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(launcher)
            context_file = destination / "native-compiler-context.bin"
            native_context = launcher.capture_native_compiler_context(generator,
                {"generatorCall": command}, os.environ.copy(), generator.parent, context_file)
            (destination / "native-compiler-context.json").write_text(json.dumps(native_context, indent=2) + "\n")
            command[command.index("Xclang"):command.index("Xclang")] = ["-hanlin-expected-clang-context", str(context_file)]
            # A changed relevant define must be rejected BEFORE the AST/emitter.
            drift = subprocess.run([*command, "-D__HANLIN_CONTEXT_NEGATIVE=1"], cwd=generator.parent,
                capture_output=True, timeout=120)
            (destination / "context-drift-negative.log").write_bytes(drift.stdout + drift.stderr)
            result["nativeCompilerContext"] = {**native_context, "driftExitCode": drift.returncode,
                "status": "EXECUTED_PASS" if drift.returncode > 0 and b"Effective metadata compiler context drifted" in drift.stdout + drift.stderr else "FAILED",
                "boundary": "Actual tool argument capture/verification; not a C++ absence or VM proof."}
        completed = subprocess.run(command, cwd=generator.parent, capture_output=True, timeout=180)
        (destination / "stdout.log").write_bytes(completed.stdout)
        (destination / "stderr.log").write_bytes(completed.stderr)
        if completed.returncode < 0:
            debugger = subprocess.run(["xcrun", "lldb", "--batch", "-o", "run", "-k", "bt 32",
                                       "--", *command], cwd=generator.parent, capture_output=True, timeout=120)
            (destination / "crash-backtrace.log").write_bytes(debugger.stdout + debugger.stderr)
        data = binary.read_bytes() if binary.is_file() else b""
        symbols = {name: name.encode() + b"\0" in data for name in required}
        errors = [line for line in completed.stderr.decode("utf-8", errors="replace").splitlines()
                  if re.search(r"(?:^|:\d+(?::\d+)?:\s+)(?:fatal\s+)?error:", line)]
        result["modes"][mode] = {"exitCode": completed.returncode, "requiredMetadataStringsPresent": symbols,
            "xcodeClangSyntaxControlExitCode": control.returncode,
            "metadataSHA256": hashlib.sha256(data).hexdigest(), "metadataBytes": len(data),
            "clangErrorCount": len(errors),
            "status": "EXECUTED_PASS" if completed.returncode == 0 and control.returncode == 0
                      and all(symbols.values()) and not errors else "FAILED"}
        if options.emit_types:
            declarations = {p.relative_to(destination / "types").as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in sorted((destination / "types").rglob("*.d.ts"))}
            result["generatedTypeDeclarations"] = {"files": declarations,
                "strictTypecheck": "NOT_RUN", "boundary": "Actual SDK generation; generated declarations still require full strict checking."}
            if not declarations:
                result["modes"][mode]["status"] = "FAILED"
        print(json.dumps({mode: result["modes"][mode]}), flush=True)
        # Keep the actual first SDK failure bounded in the job log. Full stderr
        # stays in the existing evidence artifact, not another logging system.
        print("\n".join(errors[:8]), flush=True)
    if options.generator is not None:
        parity_root = output / "declaration-parity"
        parity_root.mkdir(exist_ok=True)
        parity_input = parity_root / "input.h"
        parity_input.write_text('#import <UIKit/UIKit.h>\n#import "HanlinNativeServicesBridge.h"\n'
                                '#import "HanlinNativeScriptCompatibility.h"\n')
        flags = command[command.index("Xclang") + 1:]
        manifests = {}
        exits = {}
        for name, executable in [("original", original_generator), ("candidate", generator)]:
            folder = parity_root / name
            folder.mkdir(exist_ok=True)
            comparison_flags = flags
            if name == "original" and options.language == "objective-c++":
                # Compare with the accepted original ObjC reference. Its
                # Clang17 cannot parse the current SDK's C++ standard library.
                if flags[-4:] != ["-x", "objective-c++", "-std=gnu++20", "-fno-cxx-modules"]:
                    raise RuntimeError("Candidate dialect argv changed")
                comparison_flags = flags[:-4]
            invocation = [str(executable), "-input-umbrella", str(parity_input),
                          "-output-yaml", str(folder / "yaml"), "Xclang", *comparison_flags]
            (folder / "command.json").write_text(json.dumps(invocation, indent=2) + "\n")
            execution = subprocess.run(invocation, cwd=executable.parent, capture_output=True, timeout=120)
            (folder / "stdout.log").write_bytes(execution.stdout)
            (folder / "stderr.log").write_bytes(execution.stderr)
            manifests[name] = {p.relative_to(folder / "yaml").as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in sorted((folder / "yaml").glob("*.yaml"))}
            exits[name] = execution.returncode
        parity_ok = bool(manifests["original"]) and manifests["original"] == manifests["candidate"] and all(v == 0 for v in exits.values())
        result["unchangedUIKitAndHostDeclarationParity"] = {"status": "EXECUTED_PASS" if parity_ok else "FAILED",
            "exitCodes": exits, "yamlSHA256": manifests}
        negative_input = parity_root / "negative.h"
        negative_input.write_text('#import <Foundation/Foundation.h>\n@interface HanlinMetadataNegativeFixture : NSObject\n'
                                  '- (HanlinDefinitelyMissingSDKType)invalidAPI;\n@end\n')
        invalid = subprocess.run([str(generator), "-input-umbrella", str(negative_input), "Xclang", *flags],
                                 cwd=generator.parent, capture_output=True, timeout=120)
        (parity_root / "negative-stderr.log").write_bytes(invalid.stderr)
        result["invalidDeclarationRejected"] = {"exitCode": invalid.returncode,
            "status": "EXECUTED_PASS" if invalid.returncode > 0 and b"error:" in invalid.stderr else "FAILED"}
    if options.runtime_wrapper:
        try:
            result["runtimeWrapper"] = probe_runtime_wrapper(root, output, original_generator, arch)
        except (subprocess.SubprocessError, RuntimeError, KeyError, StopIteration) as error:
            result["runtimeWrapper"] = {"status": "FAILED", "stage": "actual runtime-wrapper probe",
                                        "reason": type(error).__name__ + ": " + str(error)}
        print(json.dumps({"runtimeWrapper": result["runtimeWrapper"]}), flush=True)
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    success = result["modes"][options.mode]["status"] == "EXECUTED_PASS"
    if options.generator is not None:
        success = success and parity_ok and result["invalidDeclarationRejected"]["status"] == "EXECUTED_PASS" \
            and result.get("nativeCompilerContext", {}).get("status") == "EXECUTED_PASS"
    if options.runtime_wrapper:
        success = success and result["runtimeWrapper"]["status"] == "EXECUTED_PASS"
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
