#!/usr/bin/env python3
"""Run the pinned real metadata generator against the selected Apple SDK.

No app/engine build, simulator, Swift-header stand-in, SDK modification or VM
acceptance claim. The probe includes actual UIKit and Host ObjC headers.
"""
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess
import sys


def capture(*args: str) -> str:
    return subprocess.check_output(args, text=True).strip()


def main() -> int:
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
    result = {"schemaVersion": 1, "nativeScriptIOS": package["version"], "sdk": str(sdk),
              "sdkVersion": version, "xcode": capture("xcodebuild", "-version"),
              "clangResourceDirectory": str(resources), "architecture": arch,
              "generatorSHA256": hashlib.sha256(generator.read_bytes()).hexdigest(), "modes": {},
              "boundary": "Actual ObjC SDK metadata generation only; no app/Swift-provider/VM or physical-device pass."}
    required = ["HanlinNativeServicesBridge", "HanlinNativeServicesSessionBridge", "HanlinNativeScriptCompatibility", "UIView", "NSObject"]
    for mode in ["modular", "textual"]:
        destination = output / mode
        destination.mkdir(exist_ok=True)
        binary = destination / "metadata.bin"
        command = [str(generator), "-verbose", "-output-bin", str(binary),
                   "-output-umbrella", str(destination / "umbrella.h"),
                   "Xclang", "-isysroot", str(sdk), "-target", f"{arch}-apple-ios{version}-simulator",
                   "-std=gnu17", "-resource-dir", str(resources), "-I" + str(headers),
                   "-F" + str(sdk / "System/Library/SubFrameworks"),
                   "-fmodule-map-file=" + str(headers / "module.modulemap"),
                   "-include", str(umbrella), "-fmodules" if mode == "modular" else "-fno-modules"]
        completed = subprocess.run(command, cwd=generator.parent, capture_output=True, timeout=180)
        (destination / "stdout.log").write_bytes(completed.stdout)
        (destination / "stderr.log").write_bytes(completed.stderr)
        data = binary.read_bytes() if binary.is_file() else b""
        symbols = {name: name.encode() + b"\0" in data for name in required}
        errors = [line for line in completed.stderr.decode("utf-8", errors="replace").splitlines()
                  if re.search(r"(?:^|:\d+(?::\d+)?:\s+)(?:fatal\s+)?error:", line)]
        result["modes"][mode] = {"exitCode": completed.returncode, "requiredMetadataStringsPresent": symbols,
            "metadataSHA256": hashlib.sha256(data).hexdigest(), "metadataBytes": len(data),
            "clangErrorCount": len(errors),
            "status": "EXECUTED_PASS" if completed.returncode == 0 and all(symbols.values()) and not errors else "FAILED"}
        print(json.dumps({mode: result["modes"][mode]}), flush=True)
        # Keep the actual first SDK failure bounded in the job log. Full stderr
        # stays in the existing evidence artifact, not another logging system.
        print("\n".join(errors[:8]), flush=True)
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return 0 if result["modes"]["textual"]["status"] == "EXECUTED_PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
