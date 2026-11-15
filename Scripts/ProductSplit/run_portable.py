"""Compile actual bridge/migration Swift against the committed canonical contracts.

No generated Package.swift, dependency downloads, CI, Apple frameworks or app builds.
Build products stay under the owned Tests/ProductSplit/.build directory.
"""
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main():
    evidence = ROOT / "docs/product-split/portable-results.json"
    evidence.parent.mkdir(exist_ok=True)
    evidence.write_text('{"status":"IN_PROGRESS","scope":"portable Swift only"}\n', encoding="utf-8", newline="\n")
    build = ROOT / "Tests/ProductSplit/.build"
    build.mkdir(exist_ok=True)
    compiler = shutil.which("swiftc")
    if not compiler:
        raise SystemExit("swiftc unavailable; no test execution claimed")
    flags = ["-swift-version", "6", "-strict-concurrency=complete", "-warnings-as-errors"]
    library_suffix = ".dylib" if sys.platform == "darwin" else ".so"
    library = build / ("HanlinPlatformContracts.dll" if os.name == "nt" else "libHanlinPlatformContracts" + library_suffix)
    # The resource-only helper needs SwiftPM's generated Bundle.module. None of
    # the exercised types uses it; omit it rather than stub production behavior.
    contracts = sorted(p for p in (ROOT / "Packages/HanlinPlatform/Sources/HanlinPlatformContracts").glob("*.swift")
                       if p.name != "HanlinManifestSchema.swift")
    subprocess.run([compiler, *flags, "-parse-as-library", "-emit-library", "-emit-module",
                    "-module-name", "HanlinPlatformContracts", *map(str, contracts),
                    "-emit-module-path", str(build / "HanlinPlatformContracts.swiftmodule"),
                    "-o", str(library)], check=True, cwd=ROOT)
    # Actual canonical request and launch implementations, not replacement stubs.
    core = ROOT / "Packages/HanlinPlatform/Sources/HanlinMiniAppCore"
    core_library = build / ("HanlinMiniAppCore.dll" if os.name == "nt" else "libHanlinMiniAppCore" + library_suffix)
    subprocess.run([compiler, *flags, "-parse-as-library", "-emit-library", "-emit-module",
                    "-module-name", "HanlinMiniAppCore", "-I", str(build), "-L", str(build),
                    "-lHanlinPlatformContracts", str(core / "HanlinMiniAppRequestBroker.swift"),
                    str(core / "HanlinCanonicalMiniAppCatalog.swift"),
                    "-emit-module-path", str(build / "HanlinMiniAppCore.swiftmodule"),
                    "-o", str(core_library)], check=True, cwd=ROOT)
    sources = sorted((ROOT / "Packages/HanlinProductSplit/Sources/HanlinProductSplit").glob("*.swift"))
    executable = build / ("ProductSplitTests.exe" if os.name == "nt" else "ProductSplitTests")
    subprocess.run([compiler, *flags, "-parse-as-library", "-I", str(build), "-L", str(build),
                    "-lHanlinPlatformContracts", "-lHanlinMiniAppCore", *map(str, sources),
                    str(ROOT / "Packages/HanlinProductSplit/Tests/PortableSplitTests.swift"),
                    "-o", str(executable)], check=True, cwd=ROOT)
    env = dict(os.environ)
    env["PATH"] = str(build) + os.pathsep + env.get("PATH", "")
    env["LD_LIBRARY_PATH"] = str(build) + os.pathsep + env.get("LD_LIBRARY_PATH", "")
    fixture = build / "fixture-store"
    fixture.mkdir(exist_ok=True)
    (fixture / ".hanlin-product-split-fixture").write_bytes(b"synthetic-fixture-only-v1\n")
    result = subprocess.run([str(executable), str(fixture)], check=True, cwd=ROOT, env=env, capture_output=True, text=True)
    print(result.stdout, end="")
    report = json.loads(result.stdout)
    report["toolchain"] = subprocess.check_output([compiler, "--version"], text=True).strip()
    report["baseline"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["scope"] = "Portable Swift bridge/migration; no SwiftUI/SDK/OS/device execution"
    report["excluded_contract_source"] = "HanlinManifestSchema.swift (SwiftPM resource helper, not exercised)"
    evidence.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
    if report.get("status") != "EXECUTED_PASS":
        raise SystemExit(1)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        failure = {"status": "FAILED", "error": str(error), "scope": "portable Swift harness"}
        (ROOT / "docs/product-split/portable-results.json").write_text(json.dumps(failure, indent=2) + "\n", encoding="utf-8", newline="\n")
        raise
