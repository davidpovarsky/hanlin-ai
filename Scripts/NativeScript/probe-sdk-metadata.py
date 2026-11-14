#!/usr/bin/env python3
"""Run the pinned real metadata generator against the selected Apple SDK.

No app/engine build, simulator, Swift-header stand-in, SDK modification or VM
acceptance claim. The probe includes actual UIKit and Host ObjC headers.
"""
import hashlib
import argparse
import json
from pathlib import Path
import platform
import re
import subprocess
import sys


def capture(*args: str) -> str:
    return subprocess.check_output(args, text=True).strip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["modular", "textual", "textual-direct", "textual-ambient", "textual-public"],
                        default="textual-public")
    parser.add_argument("--generator", type=Path, help="Explicit separately built metadata-tool candidate")
    parser.add_argument("--emit-types", action="store_true", help="Retain actual selected-SDK TypeScript declarations")
    options = parser.parse_args()
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
    output = root / "build/acceptance/nativescript-sdk-probe"
    output.mkdir(parents=True, exist_ok=True)
    umbrella = output / "probe.h"
    umbrella.write_text('#import <UIKit/UIKit.h>\n#import "HanlinNativeServicesBridge.h"\n'
                        '#import "HanlinNativeScriptCompatibility.h"\n', encoding="utf-8")
    if options.mode == "textual-public":
        from metadata_public_headers import write_public_umbrella
        write_public_umbrella(sdk, umbrella, [headers / "HanlinNativeServicesBridge.h",
                                             headers / "HanlinNativeScriptCompatibility.h"])
    result = {"schemaVersion": 1, "nativeScriptIOS": package["version"], "sdk": str(sdk),
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
            invocation = [str(executable), "-input-umbrella", str(parity_input),
                          "-output-yaml", str(folder / "yaml"), "Xclang", *flags]
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
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    success = result["modes"][options.mode]["status"] == "EXECUTED_PASS"
    if options.generator is not None:
        success = success and parity_ok and result["invalidDeclarationRejected"]["status"] == "EXECUTED_PASS"
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
