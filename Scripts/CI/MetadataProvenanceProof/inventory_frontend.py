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
    finally:
        (OUTPUT / "inventory.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
