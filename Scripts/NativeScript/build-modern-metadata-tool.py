#!/usr/bin/env python3
"""Candidate modern frontend build; no production adoption or runtime build."""
import hashlib
import importlib.util
import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if sys.platform != "darwin" or platform.machine() != "arm64":
        raise RuntimeError("Candidate asset is pinned to actual macOS arm64")
    lock_path = ROOT / "Scripts/NativeScript/metadata-frontend-lock.json"
    lock = json.loads(lock_path.read_text())
    prefix = Path(lock["installedPrefix"]).resolve(strict=True)
    for relative, digest in lock["files"].items():
        if sha(prefix / relative) != digest:
            raise RuntimeError("Pinned modern frontend input changed: " + relative)
    if subprocess.check_output([str(prefix / "bin/llvm-config"), "--version"], text=True).strip() != lock["version"]:
        raise RuntimeError("Pinned modern LLVM version changed")
    if shutil.disk_usage(ROOT).free < 8 * 1024**3:
        raise RuntimeError("Insufficient disk for focused generator build")
    work = ROOT / "build/nativescript-modern-metadata-tool"
    work.mkdir(parents=True, exist_ok=True)
    spec = importlib.util.spec_from_file_location("pinned_metadata_builder", ROOT / "Scripts/NativeScript/build-metadata-tool.py")
    base = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(base)
    archive_path = work / "source.tgz"
    base.download(f"https://codeload.github.com/NativeScript/ios/tar.gz/{base.SOURCE}", archive_path, base.SOURCE_SHA)
    source = work / f"ios-{base.SOURCE}"
    if source.exists():
        raise RuntimeError("Candidate source output must be fresh; preserve prior evidence")
    with tarfile.open(archive_path) as archive:
        archive.extractall(work, filter="data")
    generator = source / "metadata-generator"
    main_cpp = generator / "src/main.cpp"
    main_cpp.write_text(base.patch_main(main_cpp.read_text()))
    writer = generator / "src/TypeScript/DefinitionWriter.cpp"
    writer.write_text(base.patch_declaration_writer(writer.read_text()))
    serializer = generator / "src/Binary/binarySerializer.cpp"
    serializer.write_text(base.replace_once(serializer.read_text(), "Archive* archive = dyn_cast<Archive>(&binary)", "isa<Archive>(&binary)"))
    # LLVM20 renamed StringRef's spelling; this is an API migration only.
    for path in (generator / "src").rglob("*"):
        if path.suffix in {".h", ".cpp"}:
            before = path.read_text()
            after = before.replace(".startswith(", ".starts_with(").replace(".endswith(", ".ends_with(")
            if before != after:
                path.write_text(after)
    # Reuse the exact upstream source list; dynamically link the installed
    # Clang frontend and LLVM from the same pinned keg as the C API classifier.
    src_cmake = generator / "src/CMakeLists.txt"
    text = src_cmake.read_text()
    first = text.index("target_link_libraries(objc-metadata-generator")
    last = text.index("\n)", first) + 2
    src_cmake.write_text(text[:first] + "target_link_libraries(objc-metadata-generator PRIVATE clang-cpp LLVM ${LIBXML2_LIBRARIES})" + text[last:])
    (generator / "CMakeLists.txt").write_text('''cmake_minimum_required(VERSION 3.20)
project(HanlinModernMetadata LANGUAGES C CXX)
find_package(LibXml2 REQUIRED)
find_package(LLVM 20.1.8 EXACT REQUIRED CONFIG)
find_package(Clang REQUIRED CONFIG)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED YES)
set(CMAKE_BUILD_TYPE Release)
include_directories(SYSTEM ${LLVM_INCLUDE_DIRS} ${CLANG_INCLUDE_DIRS})
add_definitions(${LLVM_DEFINITIONS})
set(LLVM_LIBDIR "''' + prefix.as_posix() + '''/lib")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin/lib)
add_subdirectory(src)
''')
    build = work / "cmake-build"
    commands = [["cmake", "-S", str(generator), "-B", str(build),
        "-DLLVM_DIR=" + str(prefix / "lib/cmake/llvm"), "-DClang_DIR=" + str(prefix / "lib/cmake/clang")],
        ["cmake", "--build", str(build), "--parallel", "3"]]
    result = {"schemaVersion": 2, "status": "BUILDING", "sourceCommit": base.SOURCE,
        "sourceArchiveSHA256": base.SOURCE_SHA, "frontendLockSHA256": sha(lock_path),
        "basePatchSourceSHA256": sha(ROOT / "Scripts/NativeScript/build-metadata-tool.py"),
        "modernPatchSourceSHA256": sha(Path(__file__)), "frontendRoot": str(prefix),
        "classifierLibrary": str(prefix / "lib/libclang.dylib"), "frontendVersion": lock["version"],
        "commands": commands, "platform": platform.platform(),
        "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
        "serializerSources": {p.relative_to(generator).as_posix(): sha(p) for p in (generator / "src/Binary").rglob("*") if p.is_file()},
        "frontendInputs": {p.relative_to(prefix).as_posix(): sha(p) for folder in ["include/clang", "include/llvm", "lib/clang"]
            for p in (prefix / folder).rglob("*") if p.is_file()},
        "libraries": {p.name: sha(p) for p in [prefix / "lib/libclang.dylib", prefix / "lib/libclang-cpp.dylib", prefix / "lib/libLLVM.dylib"]},
        "boundary": "Candidate build only; no metadata/API/ABI/VM/UI acceptance."}
    receipt = work / "provenance.json"
    try:
        for index, command in enumerate(commands):
            with (work / f"build-{index}.log").open("w") as log:
                subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=420)
        result.update(status="BUILT_NOT_ACCEPTED", generatorSHA256=sha(build / "bin/objc-metadata-generator"))
        (work / "bin").mkdir(exist_ok=True)
        shutil.copy2(build / "bin/objc-metadata-generator", work / "bin/objc-metadata-generator")
        shutil.copytree(build / "bin/lib", work / "bin/lib", dirs_exist_ok=True)
        result["linkedLibraries"] = subprocess.check_output(["otool", "-L", str(work / "bin/objc-metadata-generator")], text=True)
    except Exception as error:
        result.update(status="BUILD_FAILED", reason=type(error).__name__ + ": " + str(error))
        raise
    finally:
        receipt.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: value for key, value in result.items() if key != "frontendInputs"}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
