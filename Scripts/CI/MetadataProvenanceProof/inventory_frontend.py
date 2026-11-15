#!/usr/bin/env python3
"""Read-only inventory of actual installed macOS frontend development assets."""
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
OUTPUT = ROOT / "build/acceptance/metadata-frontend-inventory"


def main():
    OUTPUT.mkdir(parents=True, exist_ok=False)
    result = {"platform": platform.platform(), "architecture": platform.machine(),
        "freeBytes": shutil.disk_usage(ROOT).free, "commands": [], "assets": []}
    def run(argv):
        call = subprocess.run(argv, capture_output=True, timeout=45, text=True)
        result["commands"].append({"argv": argv, "exitCode": call.returncode,
            "stdout": call.stdout, "stderr": call.stderr})
        return call.stdout.strip() if call.returncode == 0 else None
    try:
        clang = run(["xcrun", "--find", "clang"])
        run(["xcodebuild", "-version"])
        run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"])
        run(["xcrun", "clang", "--version"])
        roots = [Path(clang).resolve().parent.parent] if clang else []
        brew = shutil.which("brew")
        if brew:
            run([brew, "list", "--versions"])
            for name in ["llvm", "llvm@21", "llvm@20"]:
                prefix = run([brew, "--prefix", name])
                if prefix and Path(prefix).is_dir():
                    roots.append(Path(prefix))
        result["roots"] = [str(p) for p in roots]
        for root in roots:
            for relative in ["include/clang/AST/ASTContext.h", "include/llvm/Config/llvm-config.h",
                             "lib/cmake/llvm/LLVMConfig.cmake", "bin/llvm-config"]:
                path = root / relative
                result["assets"].append({"path": str(path), "exists": path.is_file(),
                    **({"sha256": hashlib.sha256(path.read_bytes()).hexdigest()} if path.is_file() else {})})
            for directory in [root / "lib", root / "lib/clang", root / "include"]:
                result["assets"].append({"directory": str(directory),
                    "children": sorted(p.name for p in directory.iterdir()) if directory.is_dir() else []})
            for path in sorted((root / "lib").glob("libclang*")):
                if path.is_file():
                    result["assets"].append({"path": str(path.resolve()), "bytes": path.stat().st_size,
                        "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
            config = root / "bin/llvm-config"
            if config.is_file():
                run([str(config), "--version", "--cmakedir", "--includedir", "--libdir", "--shared-mode"])
        # Read-only AST facts resolve the remaining actual SDK grammar gaps;
        # these are diagnostics, never metadata/API acceptance substitutes.
        lock = json.loads((ROOT / "Scripts/NativeScript/metadata-frontend-lock.json").read_text())
        frontend = Path(lock["installedPrefix"])
        for name, digest in lock["files"].items():
            if hashlib.sha256((frontend / name).read_bytes()).hexdigest() != digest:
                raise RuntimeError("SDK fact frontend drift: " + name)
        sdk = Path(run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"]))
        version = run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"])
        facts = OUTPUT / "sdk-declarations"
        facts.mkdir()
        input_path = facts / "input.h"
        input_path.write_text('#import <UIKit/UIKit.h>\n#import "HanlinNativeServicesBridge.h"\n#import "HanlinNativeScriptCompatibility.h"\n')
        core = ROOT / "Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptCoreSupport/include"
        for language, standard in [("objective-c", "gnu17"), ("objective-c++", "gnu++20")]:
            for symbol in ["NSObject", "imaxabs", "imaxdiv_t", "exception"]:
                label = language + "-" + symbol
                argv = [str(frontend / "bin/clang"), "-fsyntax-only", "-x", language, "-std=" + standard,
                    "-fno-objc-arc", "-fno-modules", "-fno-implicit-module-maps",
                    "-D__NATIVESCRIPT_METADATA_GENERATOR=1", "-isysroot", str(sdk),
                    "-target", platform.machine() + "-apple-ios" + version + "-simulator",
                    "-I" + str(core), "-F" + str(sdk / "System/Library/SubFrameworks")]
                if language == "objective-c++":
                    argv.extend(["-Xclang", "-fno-cxx-modules"])
                argv.extend(["-Xclang", "-ast-dump", "-Xclang", "-ast-dump-filter", "-Xclang", symbol, str(input_path)])
                with (facts / (label + ".stdout")).open("wb") as stdout, (facts / (label + ".stderr")).open("wb") as stderr:
                    executed = subprocess.run(argv, stdout=stdout, stderr=stderr, timeout=45)
                result["commands"].append({"purpose": "READ_ONLY_SDK_DECLARATION_FACTS_NOT_ACCEPTANCE",
                    "argv": argv, "exitCode": executed.returncode,
                    "stdoutFile": "sdk-declarations/" + label + ".stdout", "stderrFile": "sdk-declarations/" + label + ".stderr"})
        for name in ["usr/include/objc/objc-api.h", "usr/include/objc/NSObjCRuntime.h", "usr/include/math.h",
                     "usr/include/_stdlib.h", "usr/include/c++/v1/inttypes.h", "usr/include/c++/v1/stdlib.h"]:
            path = sdk / name
            if path.is_file() and path.stat().st_size <= 1024 * 1024:
                destination = facts / "sources" / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(path.read_bytes())
    finally:
        (OUTPUT / "inventory.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))
    return 0


def sdk_linkage_facts():
    """Read actual SDK header/export bytes; do not execute metadata or change inputs."""
    OUTPUT.mkdir(parents=True, exist_ok=False)
    sdk = Path(subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip())
    symbol = "AVCaptureTimecodeCreateMetadataSampleBufferAssociatedWithPresentationTimeStamp"
    relative = "System/Library/Frameworks/AVFoundation.framework"
    paths = [sdk / relative / "Headers/AVCaptureTimecodeGenerator.h", sdk / relative / "Headers/AVBase.h"]
    paths.extend(sorted((sdk / relative).rglob("*.tbd")))
    result = {"status": "READ_ONLY_FACTS", "symbol": symbol, "sdk": str(sdk),
        "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(), "files": []}
    for path in paths:
        if not path.is_file():
            result["files"].append({"path": str(path), "status": "MISSING"})
            continue
        data = path.read_bytes()
        if len(data) > 16 * 1024 * 1024:
            raise RuntimeError("SDK fact file exceeds bounded size")
        target = OUTPUT / "sdk-linkage" / path.relative_to(sdk)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        lines = data.decode("utf-8").splitlines()
        matches = [index for index, text in enumerate(lines) if symbol in text or (path.suffix == ".h" and any(key in text for key in ["extern", "AVF_EXPORT", "__cplusplus"]))]
        indexes = sorted({i for index in matches for i in range(max(0, index - 3), min(len(lines), index + 4))})
        result["files"].append({"path": str(path), "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data),
            "retained": target.relative_to(OUTPUT).as_posix(), "matches": [{"line": i + 1, "text": lines[i]} for i in indexes]})
    (OUTPUT / "sdk-linkage-facts.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))
    return 0


def sdk_enum_facts():
    """Read exact Accelerate conditional enum declarations/values, not metadata."""
    OUTPUT.mkdir(parents=True, exist_ok=False)
    sdk = Path(subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip())
    version = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], text=True).strip()
    lock = json.loads((ROOT / "Scripts/NativeScript/metadata-frontend-lock.json").read_text())
    frontend = Path(lock["installedPrefix"])
    for path, digest in lock["files"].items():
        if hashlib.sha256((frontend / path).read_bytes()).hexdigest() != digest:
            raise RuntimeError("Enum fact compiler drift")
    source = OUTPUT / "accelerate.h"
    source.write_text('#import <Accelerate/Accelerate.h>\n')
    result = {"status": "READ_ONLY_SDK_ENUM_FACTS", "sdk": str(sdk), "target": "arm64-apple-ios" + version + "-simulator",
        "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(), "commands": [], "files": []}
    for language, standard in [("objective-c", "gnu17"), ("objective-c++", "gnu++20")]:
        for symbol in ["vImage_Error", "vImage_Flags", "kvImage"]:
            label = language + "-" + symbol
            command = [str(frontend / "bin/clang"), "-x", language, "-std=" + standard, "-fno-objc-arc", "-fno-modules",
                "-fno-implicit-module-maps", "-D__NATIVESCRIPT_METADATA_GENERATOR=1", "-isysroot", str(sdk), "-target", result["target"],
                "-Xclang", "-fno-cxx-modules", "-fsyntax-only", "-Xclang", "-ast-dump=json", "-Xclang", "-ast-dump-filter", "-Xclang", symbol, str(source)]
            call = subprocess.run(command, capture_output=True, timeout=60)
            (OUTPUT / (label + ".stdout")).write_bytes(call.stdout)
            (OUTPUT / (label + ".stderr")).write_bytes(call.stderr)
            result["commands"].append({"argv": command, "exitCode": call.returncode, "stdout": label + ".stdout", "stderr": label + ".stderr"})
    for relative in ["System/Library/Frameworks/Accelerate.framework/Frameworks/vImage.framework/Headers/vImage_Types.h",
                     "System/Library/Frameworks/Accelerate.framework/Frameworks/vImage.framework/Headers/Alpha.h",
                     "System/Library/Frameworks/Accelerate.framework/Frameworks/vecLib.framework/Headers/thread_api.h"]:
        path = sdk / relative
        data = path.read_bytes()
        output = OUTPUT / "sources" / relative
        output.parent.mkdir(parents=True, exist_ok=True); output.write_bytes(data)
        result["files"].append({"path": str(path), "retained": output.relative_to(OUTPUT).as_posix(), "sha256": hashlib.sha256(data).hexdigest()})
    (OUTPUT / "enum-facts.json").write_text(json.dumps(result, indent=2) + "\n")
    manifest = [{"path": p.relative_to(OUTPUT).as_posix(), "sha256": hashlib.sha256(p.read_bytes()).hexdigest(), "bytes": p.stat().st_size} for p in sorted(OUTPUT.rglob("*")) if p.is_file()]
    (OUTPUT / "artifact-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"status": result["status"], "exitCodes": [c["exitCode"] for c in result["commands"]]}))
    return 0 if all(c["exitCode"] == 0 for c in result["commands"]) else 1


if __name__ == "__main__":
    sys.exit(sdk_enum_facts() if "--sdk-enum-facts" in sys.argv else sdk_linkage_facts() if "--sdk-linkage-facts" in sys.argv else main())
