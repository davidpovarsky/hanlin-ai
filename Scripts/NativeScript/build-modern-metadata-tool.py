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
    # Preserve original terminating results while bounding recursive prefix
    # progression, including enums with no fields and repeated candidates.
    return r'''static std::string createValidPrefix(const std::vector<std::string>& fieldNames,
                                     const std::string& prefix) {
  std::set<std::string> visited;
  std::string candidate = prefix;
  while (visited.insert(candidate).second) {
    if (candidate.empty()) return ""; // Original routine terminates at empty prefix.
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
    support = ROOT / "Scripts/NativeScript/metadata-dual-grammar"
    support_sources = {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted(support.glob("*")) if p.suffix in {".h", ".cpp", ".py"}}
    if not support_sources:
        raise RuntimeError("Dual-grammar support source closure is missing")
    shutil.copytree(support, generator / "src/HanlinDual")
    main_text = base.patch_main(main_cpp.read_text())
    main_text = base.replace_once(main_text, '#include "Yaml/YamlSerializer.h"',
        '#include "Yaml/YamlSerializer.h"\n#include "HanlinDual/ModelMerge.h"')
    main_text = base.replace_once(main_text, "    clang::SourceManager &sm;",
        "    clang::SourceManager &sm;\n    clang::Preprocessor &pp;")
    main_text = base.replace_once(main_text,
        "HanlinProvenanceCallbacks(clang::SourceManager &s, HanlinProvenanceState &v) : sm(s), state(v) {}",
        "HanlinProvenanceCallbacks(clang::SourceManager &s, clang::Preprocessor &p, HanlinProvenanceState &v) : sm(s), pp(p), state(v) {}")
    main_text = base.replace_once(main_text,
        "std::make_unique<HanlinProvenanceCallbacks>(ci.getSourceManager(), state)",
        "std::make_unique<HanlinProvenanceCallbacks>(ci.getSourceManager(), ci.getPreprocessor(), state)")
    main_text = base.replace_once(main_text, "        // Preserve ALL handlers. Only pragma-once has established equivalence",
        r'''        // LLVM20 InitPreprocessor emits these two push_macro directives.
        // They execute entirely in PP. Trust only the actual predefines FileID,
        // never a presumed filename that a source #line directive can spoof.
        auto fileID = sm.getFileID(sm.getExpansionLoc(loc));
        if (pp.getPredefinesFileID().isValid() && fileID == pp.getPredefinesFileID() &&
            (text == "#pragma push_macro(\"__GCC_DESTRUCTIVE_SIZE\")" ||
             text == "#pragma push_macro(\"__GCC_CONSTRUCTIVE_SIZE\")")) {
            state.event(llvm::json::Object{{"kind", "compiler-predefine-pragma"},
                {"source", textBytes}, {"predefinesSHA256", hanlinSHA(sm.getBufferData(fileID))}});
            return; // Observed classification only; the original handler still runs.
        }
        // Preserve ALL handlers. Only pragma-once has established equivalence''')
    main_text = base.replace_once(main_text, "#include <clang/Lex/Preprocessor.h>",
        "#include <clang/Lex/Preprocessor.h>\n#include <clang/Lex/HeaderSearchOptions.h>")
    main_text = base.replace_once(main_text, "        _headerSearch.collectAllModules(modules);",
        "        // Ownership indexing after parsing never imports a serialized AST.\n"
        "        _headerSearch.getHeaderSearchOpts().ImplicitModuleMaps = true;\n"
        "        _headerSearch.collectAllModules(modules);")
    main_cpp.write_text(main_text)
    support_spec = importlib.util.spec_from_file_location("dual_grammar_patches", support / "patches.py")
    support_patch = importlib.util.module_from_spec(support_spec)
    support_spec.loader.exec_module(support_patch)
    main_cpp.write_text(support_patch.apply(main_cpp.read_text(), base.replace_once))
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
    text = base.replace_once(factory.read_text(), "    case clang::Decl::Kind::Record:",
        "    case clang::Decl::Kind::CXXRecord:\n    case clang::Decl::Kind::Record:")
    text = base.replace_once(text, "          if (tagType->getDecl() == tagDecl) {", '''          if (tagType->getDecl() == tagDecl) {
            // After a retained source AST completes, C and C++ can both
            // canonicalize a later standalone typedef to the definition.
            // Preserve its original tag; an inline typedef still keeps its
            // original alias because its beginning precedes the record end.
            const auto& sm = tagDecl->getASTContext().getSourceManager();
            if (!tagDecl->getName().empty() &&
                sm.isBeforeInTranslationUnit(tagDecl->getEndLoc(), nextDecl->getBeginLoc()))
              return tagDecl->getNameAsString();''')
    text = base.replace_once(text, "  if (var.getLexicalDeclContext() !=\n      var.getASTContext().getTranslationUnitDecl()) {",
        "  if (var.getLexicalDeclContext()->getRedeclContext() !=\n      var.getASTContext().getTranslationUnitDecl()) {")
    text = base.replace_once(text, "  // The decl has no typedef name, so we return its name.", '''  // NS_OPTIONS in C++ is a preceding integer typedef and anonymous enum.
  // Recover only the real typedef at the same macro expansion location;
  // preserve the original enumerator/value serializer and public identity.
  if (tagDecl->getASTContext().getLangOpts().CPlusPlus &&
      clang::isa<clang::EnumDecl>(tagDecl) && tagDecl->getName().empty() &&
      tagDecl->getBeginLoc().isMacroID()) {
    const auto& sm = tagDecl->getASTContext().getSourceManager();
    const clang::TypedefDecl* previous = nullptr;
    for (const auto* sibling : tagDecl->getDeclContext()->decls()) {
      if (sibling == tagDecl) break;
      previous = clang::dyn_cast<clang::TypedefDecl>(sibling);
    }
    if (previous && previous->getUnderlyingType()->isIntegerType() &&
        sm.getExpansionLoc(previous->getLocation()) == sm.getExpansionLoc(tagDecl->getBeginLoc()))
      return previous->getNameAsString();
  }
  // The decl has no typedef name, so we return its name.''')
    factory_header = generator / "src/Meta/MetaFactory.h"
    header_text, text = support_patch.patch_factories(factory_header.read_text(), text, base.replace_once)
    factory_header.write_text(header_text)
    factory.write_text(text)
    type_factory = generator / "src/Meta/TypeFactory.cpp"
    text = base.replace_once(type_factory.read_text(),
        '  vector<string> boolTypedefs{"BOOL", "Boolean", "bool"};', '''  // The C++ NS_OPTIONS integer typedef belongs to its immediately following
  // anonymous enum at the same macro expansion. Preserve the existing Enum
  // model in function/property signatures as well as in named exports.
  const auto* alias = type->getDecl();
  if (alias->getASTContext().getLangOpts().CPlusPlus &&
      alias->getUnderlyingType()->isIntegerType() && alias->getLocation().isMacroID()) {
    if (const auto* enumeration = clang::dyn_cast_or_null<clang::EnumDecl>(alias->getNextDeclInContext())) {
      const auto& sm = alias->getASTContext().getSourceManager();
      if (enumeration->getName().empty() && enumeration->getBeginLoc().isMacroID() &&
          sm.getExpansionLoc(alias->getLocation()) == sm.getExpansionLoc(enumeration->getBeginLoc())) {
        auto* model = &this->_metaFactory->create(*enumeration)->as<EnumMeta>();
        return make_shared<EnumType>(this->create(alias->getUnderlyingType()).get(), model);
      }
    }
  }
  vector<string> boolTypedefs{"BOOL", "Boolean", "bool"};''')
    type_factory.write_text(text)
    visitor = generator / "src/Meta/DeclarationConverterVisitor.h"
    text = visitor.read_text()
    text = base.replace_once(text, "#include <clang/AST/RecursiveASTVisitor.h>",
        "#include <clang/AST/RecursiveASTVisitor.h>\n#include <clang/AST/DeclTemplate.h>")
    text = base.replace_once(text, "        try {\n            // Remove from cache", '''        if (decl->getASTContext().getLangOpts().CPlusPlus) {
            if (auto function = clang::dyn_cast<clang::FunctionDecl>(decl)) {
                if (function->getDescribedFunctionTemplate() || function->isFunctionTemplateSpecialization()) return true;
                if (!function->isExternC() && !function->getDeclContext()->getRedeclContext()->isTranslationUnit()) return true;
            }
            if (auto variable = clang::dyn_cast<clang::VarDecl>(decl)) {
                if (!variable->isExternC() && !variable->getDeclContext()->getRedeclContext()->isTranslationUnit()) return true;
            }
            if (auto record = clang::dyn_cast<clang::CXXRecordDecl>(decl)) {
                if (record->isInjectedClassName() || record->getDescribedClassTemplate() || clang::isa<clang::ClassTemplateSpecializationDecl>(record) ||
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
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
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
        "supportSources": support_sources,
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
        # Compile only one focused control object; relink the exact already
        # compiled generator dependencies, excluding its original main object.
        # Keep the actual CMake compiler/link vectors rather than inventing a
        # parallel LLVM toolchain or compiling all source objects again.
        import shlex
        compilation = next(item for item in json.loads((build / "compile_commands.json").read_text())
                           if Path(item["file"]).resolve() == main_cpp.resolve())
        control_object = work / "dual-controls.o"
        control_dependencies = work / "dual-controls.o.d"
        control_compile = list(compilation.get("arguments") or shlex.split(compilation["command"]))
        control_compile[control_compile.index("-o") + 1] = str(control_object)
        control_compile = [str(generator / "src/HanlinDual/Controls.cpp") if item == str(main_cpp) else item for item in control_compile]
        if "-MF" in control_compile:
            control_compile[control_compile.index("-MF") + 1] = str(control_dependencies)
        else:
            control_compile.extend(["-MD", "-MF", str(control_dependencies)])
        if "-MT" in control_compile:
            control_compile[control_compile.index("-MT") + 1] = str(control_object)
        link_file = build / "src/CMakeFiles/objc-metadata-generator.dir/link.txt"
        control_link = shlex.split(link_file.read_text())
        main_objects = [n for n, item in enumerate(control_link) if item.endswith("/main.cpp.o")]
        if len(main_objects) != 1 or str(main_cpp) not in (compilation.get("arguments") or shlex.split(compilation["command"])):
            raise RuntimeError("Actual focused control compiler/link inputs are ambiguous")
        control_link[main_objects[0]] = str(control_object)
        dual_control_binary = build / "bin/HanlinDualGrammarControls"
        control_link[control_link.index("-o") + 1] = str(dual_control_binary)
        result["dualControlCommands"] = [{"argv": control_compile, "cwd": compilation["directory"]},
                                         {"argv": control_link, "cwd": str(build / "src")}]
        for index, (command, cwd) in enumerate([(control_compile, compilation["directory"]), (control_link, build / "src")], 3):
            with (work / f"build-{index}-dual-control.log").open("w") as log:
                subprocess.run(command, cwd=cwd, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=120)
        result["dualControlBinarySHA256"] = sha(dual_control_binary)
        controls = work / "enum-prefix-controls.cpp"
        controls.write_text('#include <string>\n#include <vector>\n#include <set>\n#include <cctype>\n' + enum_prefix_source() + r'''
int main() {
  if (createValidPrefix({"__1", "__2"}, "__") != "") return 1;
  if (createValidPrefix({"__foo1", "__foo2"}, "__foo") != "") return 2;
  if (createValidPrefix({"MyEnumOne", "MyEnumTwo"}, "MyEnum") != "MyEnum") return 3;
  if (createValidPrefix({"Prefix_One", "Prefix_Two"}, "Prefix") != "Prefix_") return 4;
  if (createValidPrefix({"ABC1", "ABC2"}, "ABC") != "AB") return 5;
  if (createValidPrefix({"_CLOCK_REALTIME", "_CLOCK_MONOTONIC"}, "") != "") return 6;
  if (createValidPrefix({}, "EmptyEnum") != "EmptyEnum") return 7;
  return 0;
}
''')
        control_binary = work / "enum-prefix-controls"
        control_compile = ["xcrun", "clang++", "-std=c++17", str(controls), "-o", str(control_binary)]
        with (work / "build-2-enum-prefix-controls.log").open("w") as log:
            subprocess.run(control_compile, check=True, stdout=log, stderr=subprocess.STDOUT, timeout=60)
            subprocess.run([str(control_binary)], check=True, stdout=log, stderr=subprocess.STDOUT, timeout=5)
        result["enumPrefixControls"] = {"status": "EXECUTED_PASS", "cases": 7, "sourceSHA256": sha(controls), "compileCommand": control_compile,
            "boundary": "Actual portable C++ algorithm execution, not iOS/runtime acceptance."}
        result.update(status="BUILT_NOT_ACCEPTED", generatorSHA256=sha(build / "bin/objc-metadata-generator"))
        dependencies = set()
        for file in [*build.rglob("*.o.d"), control_dependencies]:
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
        shutil.copy2(dual_control_binary, work / "bin/HanlinDualGrammarControls")
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
