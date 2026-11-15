#!/usr/bin/env python3
"""Candidate modern frontend build; no production adoption or runtime build."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def enum_prefix_source():
    # Preserve the original terminating results, and stop the observed
    # underscore -> digit -> shorter-prefix cycle before stack exhaustion.
    return r'''static std::string createValidPrefix(const std::vector<std::string>& fieldNames,
                                     const std::string& prefix) {
  std::set<std::string> visited;
  std::string candidate = prefix;
  while (visited.insert(candidate).second) {
    for (const auto& field : fieldNames)
      if (candidate.size() > field.size()) return "";
    bool shortened = false;
    if (!candidate.empty()) {
      for (const auto& field : fieldNames) {
        if (candidate.size() < field.size() && std::isdigit(static_cast<unsigned char>(field[candidate.size()]))) {
          size_t length = candidate.size();
          while (length > 0 && !std::isupper(static_cast<unsigned char>(field[length]))) --length;
          candidate = candidate.substr(0, length);
          shortened = true;
          break;
        }
      }
    }
    if (shortened) continue;
    bool underscore = !fieldNames.empty();
    for (const auto& field : fieldNames)
      if (candidate.size() >= field.size() || field[candidate.size()] != '_') underscore = false;
    if (!underscore) return candidate;
    candidate += '_';
  }
  return "";
}

'''


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
    main_text = base.patch_main(main_cpp.read_text())
    main_text = base.replace_once(main_text, "#include <clang/Lex/Preprocessor.h>",
        "#include <clang/Lex/Preprocessor.h>\n#include <clang/Lex/HeaderSearchOptions.h>")
    main_text = base.replace_once(main_text, "        _headerSearch.collectAllModules(modules);",
        "        // Ownership indexing after parsing never imports a serialized AST.\n"
        "        _headerSearch.getHeaderSearchOpts().ImplicitModuleMaps = true;\n"
        "        _headerSearch.collectAllModules(modules);")
    main_cpp.write_text(main_text)
    writer = generator / "src/TypeScript/DefinitionWriter.cpp"
    writer.write_text(base.patch_declaration_writer(writer.read_text()).replace(
        "clang::ObjCMethodDecl::ImplementationControl::Optional", "clang::ObjCImplementationControl::Optional"))
    serializer = generator / "src/Binary/binarySerializer.cpp"
    serializer.write_text(base.replace_once(serializer.read_text(), "Archive* archive = dyn_cast<Archive>(&binary)", "isa<Archive>(&binary)"))
    parser = generator / "src/HeadersParser/Parser.cpp"
    text = parser.read_text()
    text = base.replace_once(text, "const FileEntry* header,", "FileEntryRef header,")
    text = base.replace_once(text, "header->getName()", "header.getName()")
    text = base.replace_once(text, "module->Umbrella && module->Umbrella.is<FileEntryRef>()", "std::holds_alternative<FileEntryRef>(module->Umbrella)")
    text = base.replace_once(text, "const FileEntry* umbrellaHeader = module->Umbrella.get<FileEntryRef>();", "const FileEntryRef umbrellaHeader = std::get<FileEntryRef>(module->Umbrella);")
    text = base.replace_once(text, "module->Umbrella && module->Umbrella.is<DirectoryEntryRef>()", "std::holds_alternative<DirectoryEntryRef>(module->Umbrella)")
    text = base.replace_once(text, "module->Umbrella.get<DirectoryEntryRef>()", "std::get<DirectoryEntryRef>(module->Umbrella)")
    text = base.replace_once(text, "module->Headers[Module::HK_Normal]", "module->getHeaders(Module::HK_Normal)")
    text = base.replace_once(text, "#include <clang/Lex/HeaderSearch.h>",
        "#include <clang/Lex/HeaderSearch.h>\n#include <clang/Lex/HeaderSearchOptions.h>")
    text = base.replace_once(text, "    headerSearch.collectAllModules(modules);",
        "    // The empty discovery AST has already completed. Read original maps\n"
        "    // to index ownership without changing the actual parser invocation.\n"
        "    headerSearch.getHeaderSearchOpts().ImplicitModuleMaps = true;\n"
        "    headerSearch.collectAllModules(modules);")
    parser.write_text(text)
    # ObjC++ represents C-compatible records as CXXRecordDecl. Retain the
    # original field/layout serializer; never advertise C++ methods or mangled
    # functions/variables as C-callable globals.
    factory = generator / "src/Meta/MetaFactory.cpp"
    factory.write_text(base.replace_once(factory.read_text(), "    case clang::Decl::Kind::Record:",
        "    case clang::Decl::Kind::CXXRecord:\n    case clang::Decl::Kind::Record:"))
    visitor = generator / "src/Meta/DeclarationConverterVisitor.h"
    text = visitor.read_text()
    text = base.replace_once(text, "#include <clang/AST/RecursiveASTVisitor.h>",
        "#include <clang/AST/RecursiveASTVisitor.h>\n#include <clang/AST/DeclTemplate.h>")
    text = base.replace_once(text, "        try {\n            // Remove from cache", '''        if (decl->getASTContext().getLangOpts().CPlusPlus) {
            if (auto function = clang::dyn_cast<clang::FunctionDecl>(decl)) {
                if (!function->isExternC()) return true;
            }
            if (auto variable = clang::dyn_cast<clang::VarDecl>(decl)) {
                if (!variable->isExternC()) return true;
            }
            if (auto record = clang::dyn_cast<clang::CXXRecordDecl>(decl)) {
                if (record->getDescribedClassTemplate() || clang::isa<clang::ClassTemplateSpecializationDecl>(record) ||
                    !record->isCompleteDefinition() || !record->isStandardLayout() ||
                    !record->isTriviallyCopyable() || record->getNumBases() != 0) return true;
            }
        }
        try {
            // Remove from cache''')
    visitor.write_text(text)
    utils = generator / "src/Meta/Utils.cpp"
    text = utils.read_text()
    first = text.index("static std::string createValidPrefix(")
    last = text.index("std::string Utils::calculateEnumFieldsPrefix", first)
    text = text[:first] + enum_prefix_source() + text[last:]
    utils.write_text(base.replace_once(text, '#include "TypeEntities.h"', '#include "TypeEntities.h"\n#include <set>\n#include <cctype>'))
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
        "compilerEnvironment": {key: os.environ.get(key) for key in ["CC", "CXX", "CFLAGS", "CXXFLAGS", "LDFLAGS", "SDKROOT", "DEVELOPER_DIR", "CPATH", "CPLUS_INCLUDE_PATH", "MACOSX_DEPLOYMENT_TARGET", "LIBRARY_PATH", "DYLD_LIBRARY_PATH"]},
        "buildTools": {name: {"path": str(path), "sha256": sha(path)} for name, path in {
            "clang++": Path(subprocess.check_output(["xcrun", "--find", "clang++"], text=True).strip()).resolve(),
            "ld": Path(subprocess.check_output(["xcrun", "--find", "ld"], text=True).strip()).resolve(),
            "cmake": Path(shutil.which("cmake")).resolve()}.items()},
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
        controls = work / "enum-prefix-controls.cpp"
        controls.write_text('#include <string>\n#include <vector>\n#include <set>\n#include <cctype>\n' + enum_prefix_source() + r'''
int main() {
  if (createValidPrefix({"__1", "__2"}, "__") != "") return 1;
  if (createValidPrefix({"__foo1", "__foo2"}, "__foo") != "__") return 2;
  if (createValidPrefix({"MyEnumOne", "MyEnumTwo"}, "MyEnum") != "MyEnum") return 3;
  if (createValidPrefix({"Prefix_One", "Prefix_Two"}, "Prefix") != "Prefix_") return 4;
  if (createValidPrefix({"ABC1", "ABC2"}, "ABC") != "AB") return 5;
  return 0;
}
''')
        control_binary = work / "enum-prefix-controls"
        control_compile = [result["buildTools"]["clang++"]["path"], "-std=c++17", str(controls), "-o", str(control_binary)]
        subprocess.run(control_compile, check=True, capture_output=True, timeout=60)
        subprocess.run([str(control_binary)], check=True, capture_output=True, timeout=5)
        result["enumPrefixControls"] = {"status": "EXECUTED_PASS", "cases": 5, "sourceSHA256": sha(controls), "compileCommand": control_compile,
            "boundary": "Actual portable C++ algorithm execution, not iOS/runtime acceptance."}
        result.update(status="BUILT_NOT_ACCEPTED", generatorSHA256=sha(build / "bin/objc-metadata-generator"))
        import shlex
        dependencies = set()
        for file in build.rglob("*.o.d"):
            text = file.read_text().replace("\\\n", " ")
            for item in shlex.split(text.partition(":")[2]):
                path = Path(item).resolve()
                if path.is_file() and not path.is_relative_to(work):
                    dependencies.add(path)
        result["externalCompileInputs"] = {str(path): sha(path) for path in sorted(dependencies)}
        if not result["externalCompileInputs"]:
            raise RuntimeError("Actual compiler dependency closure was not retained")
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
