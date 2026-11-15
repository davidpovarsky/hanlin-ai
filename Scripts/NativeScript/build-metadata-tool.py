#!/usr/bin/env python3
"""Build the pinned NativeScript metadata tool; never build a runtime engine.

Original NativeScript source and LLVM assets retain their upstream licenses.
Only declaration parsing/error propagation changes; the metadata format and
serializers remain the pinned runtime's source.
"""
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
import urllib.request

SOURCE = "5d4569c197810cdd4c1e02e7c16d42a01a77d5c0"
SOURCE_SHA = "fad3c54f5d321148e39c46eae6d9cbc8e2891afb414064eb3a10f64ba25d3f8b"
# Upstream's trimmed bundle is built from the SAME Apple LLVM source as17.0.6:
# swift-6.0-DEVELOPMENT-SNAPSHOT-2024-06-08-a. No LLVM/SDK version substitution.
CMAKE_SOURCE = "8856ee520a44641dfed313a71cfc01dd47e0352b"
CMAKE_HASHES = {
    "metadata-generator/CMakeLists.txt": "0d64383530493f13d1bce04d367984bb6081e665814d893693f4b065fd1bcf51",
    "metadata-generator/src/CMakeLists.txt": "0f0a48c60391e75c62db3387639de62088cb688e2d004a7576db36e02f18788b",
}
LLVM_HASHES = {"arm64": "4d2eade1e9fb7a5fae1a502d0e5d935d20190007477743a1379d81838d87b832",
               "x86_64": "f5f6047a047d8d4339e67c134e2f03be5ca30432da3fdc54de0a4a811a764eb4"}


def download(url: str, destination: Path, expected: str) -> None:
    if not destination.is_file() or hashlib.sha256(destination.read_bytes()).hexdigest() != expected:
        with urllib.request.urlopen(url, timeout=60) as response:
            destination.write_bytes(response.read())
    if hashlib.sha256(destination.read_bytes()).hexdigest() != expected:
        raise RuntimeError(f"Pinned upstream input digest mismatch: {destination.name}")


def replace_once(text: str, before: str, after: str) -> str:
    if text.count(before) != 1:
        raise RuntimeError("Pinned metadata source patch no longer matches exactly once")
    return text.replace(before, after)


def patch_main(text: str) -> str:
    text = replace_once(text, "#include <llvm/Support/Path.h>",
                        "#include <llvm/Support/Path.h>\n#include <llvm/Support/MemoryBuffer.h>\n"
                        "#include <llvm/Support/VirtualFileSystem.h>\n#include <stdexcept>")
    text = replace_once(text, "        Context.getDiagnostics().Reset();",
                        "        // Preserve actual parser errors for runToolOnCodeWithArgs.")
    text = replace_once(text, "        Compiler.getPreprocessor().SetSuppressIncludeNotFoundError(!cla_strictIncludes);",
                        "        // Metadata serializes declarations, not inline implementation bodies.\n"
                        "        Compiler.getFrontendOpts().SkipFunctionBodies = true;\n"
                        "        Compiler.getPreprocessor().SetSuppressIncludeNotFoundError(!cla_strictIncludes);")
    before = "        clang::tooling::runToolOnCodeWithArgs("
    text = replace_once(text, before, "        bool parsed = clang::tooling::runToolOnCodeWithArgs(")
    text = replace_once(text, "        std::clock_t end = clock();",
                        "        if (!parsed) return 1;\n\n        std::clock_t end = clock();")
    # Tooling's convenience overload constructs its own real FileManager and
    # does not apply -ivfsoverlay. Pass the verified overlay through the public
    # VFS overload instead. Keep the original path when no aliases are needed.
    call = 'clang::tooling::runToolOnCodeWithArgs(std::unique_ptr<MetaGenerationFrontendAction>(new MetaGenerationFrontendAction(/*r*/modulesBlacklist)), umbrellaContent, clangArgs, "umbrella.h", "objc-metadata-generator")'
    setup = '''        auto metadataFS = llvm::vfs::getRealFileSystem();
        bool customFS = false;
        for (size_t i = 0; i < clangArgs.size(); ++i) {
            if (clangArgs[i] != "-ivfsoverlay") continue;
            if (++i == clangArgs.size()) throw std::runtime_error("Missing metadata VFS overlay path");
            auto buffer = llvm::MemoryBuffer::getFile(clangArgs[i]);
            if (!buffer) throw std::runtime_error("Cannot read verified metadata VFS overlay");
            auto overlay = llvm::vfs::getVFSFromYAML(std::move(*buffer), nullptr, clangArgs[i], nullptr, metadataFS);
            if (!overlay) throw std::runtime_error("Invalid verified metadata VFS overlay");
            metadataFS = llvm::IntrusiveRefCntPtr<llvm::vfs::FileSystem>(overlay.release());
            customFS = true;
        }
        bool parsed;
        if (customFS) {
            auto memoryFS = llvm::makeIntrusiveRefCnt<llvm::vfs::InMemoryFileSystem>();
            auto layeredFS = llvm::makeIntrusiveRefCnt<llvm::vfs::OverlayFileSystem>(metadataFS);
            layeredFS->pushOverlay(memoryFS);
            memoryFS->addFile("umbrella.h", 0, llvm::MemoryBuffer::getMemBufferCopy(umbrellaContent));
            parsed = ''' + call.replace('umbrellaContent, clangArgs', 'umbrellaContent, layeredFS, clangArgs') + ''';
        } else {
            parsed = ''' + call + ''';
        }'''
    text = replace_once(text, "        bool parsed = " + call + ";", setup)
    return text


def patch_declaration_writer(text: str) -> str:
    # The existing inner writer hides ownership/runtime-only members such as
    # zone. Its outer class-member writer still emits "readonly" before that
    # empty result, producing a phantom implicit-any property in hundreds of
    # generated classes. Apply the SAME visibility rule before any modifiers.
    before = "    CompoundMemberMap<PropertyMeta> baseClassProperties) {\n  _buffer << std::endl"
    after = "    CompoundMemberMap<PropertyMeta> baseClassProperties) {\n" \
            "  if (hiddenMethods.find(propertyMeta->jsName) != hiddenMethods.end() || propertyMeta->jsName.empty()) return;\n" \
            "  _buffer << std::endl"
    text = replace_once(text, before, after)
    before = '      return tsifyType(*nullableType.innerType, isFuncParam) + " | null";'
    after = '      if (nullableType.innerType->stripNullability()->is(TypeBlock)) {\n' \
            '        return "(" + tsifyType(*nullableType.innerType, isFuncParam) + ") | null";\n' \
            '      }\n' + before
    return replace_once(text, before, after)


def main() -> int:
    if sys.platform != "darwin":
        print("BLOCKED: actual macOS/Xcode required for the metadata tool")
        return 2
    root = Path(__file__).resolve().parents[2]
    arch = platform.machine()
    if arch not in LLVM_HASHES:
        raise RuntimeError("Unsupported metadata-tool architecture")
    work = root / "build/nativescript-metadata-tool"
    work.mkdir(parents=True, exist_ok=True)
    source_archive = work / "source.tgz"
    download(f"https://codeload.github.com/NativeScript/ios/tar.gz/{SOURCE}", source_archive, SOURCE_SHA)
    source = work / f"ios-{SOURCE}"
    if source.exists():
        # Exactly this owned extraction directory; no package/runtime outputs.
        if source.resolve().parent != work.resolve():
            raise RuntimeError("Unsafe metadata-source extraction directory")
        shutil.rmtree(source)
    with tarfile.open(source_archive) as archive:
        archive.extractall(work, filter="data")
    llvm_archive = work / f"llvm-17.0.8-{arch}.tgz"
    download(f"https://github.com/NativeScript/ios-llvm/releases/download/v17.0.8/{llvm_archive.name}",
             llvm_archive, LLVM_HASHES[arch])
    (source / "llvm").mkdir(exist_ok=True)
    with tarfile.open(llvm_archive) as archive:
        archive.extractall(source / "llvm", filter="data")
    for relative, digest in CMAKE_HASHES.items():
        download(f"https://raw.githubusercontent.com/NativeScript/ios/{CMAKE_SOURCE}/{relative}",
                 source / relative, digest)
    main_cpp = source / "metadata-generator/src/main.cpp"
    main_cpp.write_text(patch_main(main_cpp.read_text()), encoding="utf-8")
    writer = source / "metadata-generator/src/TypeScript/DefinitionWriter.cpp"
    writer.write_text(patch_declaration_writer(writer.read_text()), encoding="utf-8")
    serializer = source / "metadata-generator/src/Binary/binarySerializer.cpp"
    serializer.write_text(replace_once(serializer.read_text(), "Archive* archive = dyn_cast<Archive>(&binary)",
                                       "isa<Archive>(&binary)"), encoding="utf-8")
    # The trimmed library archive omits compiler resources. Retain the actual
    # existing pinned generator's builtin headers, rather than newer intrinsics.
    internal = root / "Scripts/NativeScript/node_modules/@nativescript/ios/framework/internal"
    generators = list(internal.glob(f"metadata-generator-{arch}*/bin/objc-metadata-generator"))
    if len(generators) != 1:
        raise RuntimeError("Require the actual pinned metadata generator")
    resources = generators[0].parent / "lib/clang"
    if not resources.is_dir():
        raise RuntimeError("Pinned metadata generator builtin headers missing")
    shutil.copytree(resources, source / f"llvm/17.0.8/lib_{arch}/clang", dirs_exist_ok=True)
    build = source / "cmake-build/metadata"
    subprocess.run(["cmake", "-S", str(source / "metadata-generator"), "-B", str(build),
                    f"-DMETADATA_BINARY_ARCH={arch}"], check=True)
    subprocess.run(["cmake", "--build", str(build), "--parallel", "3"], check=True)
    binary = build / "bin/objc-metadata-generator"
    destination = work / "bin"
    destination.mkdir(exist_ok=True)
    shutil.copy2(binary, destination / binary.name)
    shutil.copytree(build / "bin/lib", destination / "lib", dirs_exist_ok=True)
    provenance = {"schemaVersion": 1, "sourceCommit": SOURCE, "sourceArchiveSHA256": SOURCE_SHA,
        "cmakeSourceCommit": CMAKE_SOURCE, "cmakeSHA256": CMAKE_HASHES,
        "llvmArchiveSHA256": LLVM_HASHES[arch], "architecture": arch,
        "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
        "patchSourceSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "generatorSHA256": hashlib.sha256(binary.read_bytes()).hexdigest(),
        "boundary": "Build tool only. No NativeScript/Node/Python engine or app rebuilt; no VM pass."}
    (work / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print(json.dumps(provenance))
    return 0


if __name__ == "__main__":
    sys.exit(main())
