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
        public_headers = []
        inventory = []
        for frameworks in [sdk / "System/Library/Frameworks", sdk / "System/Library/SubFrameworks"]:
            for framework in sorted(frameworks.glob("*.framework")):
                module_map = framework / "Modules/module.modulemap"
                matches = re.findall(r'umbrella\s+header\s+"([^"]+)"', module_map.read_text()) if module_map.is_file() else []
                found = [framework / "Headers" / name for name in matches if (framework / "Headers" / name).is_file()]
                public_headers.extend(found)
                inventory.append({"framework": framework.name, "publicUmbrellaHeaders": [str(p) for p in found]})
        umbrella.write_text("\n".join('#import "' + str(p) + '"' for p in public_headers)
                            + '\n#import "HanlinNativeServicesBridge.h"\n#import "HanlinNativeScriptCompatibility.h"\n')
        (output / "public-framework-inventory.json").write_text(json.dumps(inventory, indent=2) + "\n")
    result = {"schemaVersion": 1, "nativeScriptIOS": package["version"], "sdk": str(sdk),
              "sdkVersion": version, "xcode": capture("xcodebuild", "-version"),
              "clangResourceDirectory": str(resources), "architecture": arch,
              "generatorSHA256": hashlib.sha256(generator.read_bytes()).hexdigest(), "modes": {},
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
            "status": "EXECUTED_PASS" if completed.returncode == 0 and all(symbols.values()) and not errors else "FAILED"}
        print(json.dumps({mode: result["modes"][mode]}), flush=True)
        # Keep the actual first SDK failure bounded in the job log. Full stderr
        # stays in the existing evidence artifact, not another logging system.
        print("\n".join(errors[:8]), flush=True)
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return 0 if result["modes"][options.mode]["status"] == "EXECUTED_PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
