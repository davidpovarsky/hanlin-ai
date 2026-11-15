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


def preprocessing_provenance_source() -> str:
    # Public llvmorg-17.0.6 APIs verified in the read-only design review.
    # Source only until the instrumented tool and black-box controls execute.
    return r'''
static uint64_t hanlinConsumerEntries = 0, hanlinWriterEntries = 0;

static std::string hanlinSHA(llvm::StringRef bytes) {
    auto digest = llvm::SHA256::hash(llvm::ArrayRef<uint8_t>(
        reinterpret_cast<const uint8_t *>(bytes.data()), bytes.size()));
    const char *hex = "0123456789abcdef";
    std::string result;
    for (auto byte : digest) { result += hex[byte >> 4]; result += hex[byte & 15]; }
    return result;
}
static std::string hanlinRead(const std::string &path) {
    auto buffer = llvm::MemoryBuffer::getFile(path);
    if (!buffer) throw std::runtime_error("Cannot read provenance input: " + path);
    return buffer.get()->getBuffer().str();
}
static std::string hanlinCanonicalPath(llvm::StringRef input) {
    llvm::SmallString<256> path(input), real;
    if (llvm::sys::fs::make_absolute(path)) throw std::runtime_error("Cannot resolve diagnostic path");
    llvm::sys::path::remove_dots(path, true);
    if (!llvm::sys::fs::real_path(path, real)) return real.str().str();
    if (!llvm::sys::fs::real_path(llvm::sys::path::parent_path(path), real)) {
        llvm::sys::path::append(real, llvm::sys::path::filename(path));
        return real.str().str();
    }
    return path.str().str();
}
static std::string hanlinString(const llvm::json::Object &o, llvm::StringRef key) {
    auto value = o.getString(key);
    if (!value) throw std::runtime_error("Missing provenance string: " + key.str());
    return value->str();
}
static llvm::IntrusiveRefCntPtr<llvm::vfs::FileSystem>
hanlinProvenanceFS(const std::vector<std::string> &args, llvm::StringRef content) {
    auto fs = llvm::vfs::getRealFileSystem();
    for (size_t i = 0; i < args.size(); ++i) {
        if (args[i] != "-ivfsoverlay") continue;
        if (++i == args.size()) throw std::runtime_error("Missing provenance VFS");
        auto buffer = llvm::MemoryBuffer::getFile(args[i]);
        if (!buffer) throw std::runtime_error("Unreadable provenance VFS");
        auto overlay = llvm::vfs::getVFSFromYAML(std::move(*buffer), nullptr, args[i], nullptr, fs);
        if (!overlay) throw std::runtime_error("Invalid provenance VFS");
        fs = llvm::IntrusiveRefCntPtr<llvm::vfs::FileSystem>(overlay.release());
    }
    auto memory = llvm::makeIntrusiveRefCnt<llvm::vfs::InMemoryFileSystem>();
    auto layered = llvm::makeIntrusiveRefCnt<llvm::vfs::OverlayFileSystem>(fs);
    layered->pushOverlay(memory);
    // Match the normal Tooling VFS/cwd and main-file identity exactly.
    memory->addFile("umbrella.h", 0, llvm::MemoryBuffer::getMemBufferCopy(content));
    return layered;
}
struct HanlinProvenanceState {
    llvm::json::Array events, reasons;
    std::map<std::string, std::string> observedInputs;
    std::vector<llvm::json::Object> roots;
    std::vector<std::pair<std::string, std::string>> owners;
    std::vector<std::string> filtered;
    uint64_t misses = 0, unknownOwners = 0, uncorrelated = 0, pragmas = 0;
    unsigned diagnosticErrors = 0, diagnosticWarnings = 0;
    bool eof = false, ended = false, actionEnded = false, error = false;
    bool ast = false, sema = false, serialized = false, truncated = false;
    bool serializedArguments = false;
    std::string lastTarget;
    std::string lastIncluder, lastDirective;
    unsigned lastLine = 0;
    std::string umbrellaSHA;
    int lastRoot = -1;
    void fail(llvm::StringRef reason) {
        for (const auto &entry : reasons) { auto value = entry.getAsString(); if (value && *value == reason) return; }
        if (reasons.size() >= 64) { truncated = true; return; }
        reasons.push_back(reason.str());
    }
    std::string owner(llvm::StringRef path) {
        std::string best, result;
        for (const auto &entry : owners) {
            auto value = path.str();
            if ((value == entry.first || value.compare(0, entry.first.size() + 1, entry.first + "/") == 0) && entry.first.size() > best.size()) {
                best = entry.first; result = entry.second;
            }
        }
        return result;
    }
    bool retain(llvm::StringRef path) {
        for (const auto &prefix : filtered) if (path.str().compare(0, prefix.size() + 1, prefix + "/") == 0) return true;
        return false;
    }
    void event(llvm::json::Object value) {
        if (events.size() >= 20000) { truncated = true; return; }
        events.push_back(std::move(value));
    }
};
class HanlinProvenanceCallbacks final : public clang::PPCallbacks {
    clang::SourceManager &sm;
    HanlinProvenanceState &state;
    unsigned line(clang::SourceLocation loc) {
        return sm.getSpellingLineNumber(sm.getExpansionLoc(loc));
    }
    std::string physical(clang::SourceLocation loc) {
        auto entry = sm.getFileEntryRefForID(sm.getFileID(sm.getExpansionLoc(loc)));
        return entry ? entry->getFileEntry().tryGetRealPathName().str() : std::string();
    }
    std::string sourceLine(clang::SourceLocation loc) {
        auto fileLoc = sm.getExpansionLoc(loc);
        auto data = sm.getBufferData(sm.getFileID(fileLoc));
        auto offset = sm.getFileOffset(fileLoc);
        auto first = data.rfind('\n', offset);
        first = first == llvm::StringRef::npos ? 0 : first + 1;
        auto end = data.find('\n', offset);
        return data.slice(first, end == llvm::StringRef::npos ? data.size() : end).str();
    }
    void condition(clang::SourceLocation loc, llvm::StringRef kind, int value = -1) {
        auto path = physical(loc);
        if (sm.getFileID(sm.getExpansionLoc(loc)) == sm.getMainFileID() || state.retain(path))
            state.event({{"kind", kind.str()}, {"includer", path}, {"line", static_cast<int64_t>(line(loc))},
                {"source", sourceLine(loc)}, {"value", value}});
    }
    std::string form(llvm::StringRef source, bool angled) {
        auto text = source.ltrim();
        if (!text.empty() && text.front() == '#') text = text.drop_front().ltrim();
        size_t n = 0;
        while (n < text.size() && ((text[n] >= 'a' && text[n] <= 'z') || text[n] == '_')) ++n;
        text = text.drop_front(n).ltrim();
        if (!text.empty() && (text.front() == '"' || text.front() == '<')) {
            if ((text.front() == '<') != angled) ++state.uncorrelated;
            return text.front() == '<' ? "angle" : "quote";
        }
        if (!text.empty() && ((text.front() >= 'A' && text.front() <= 'Z') ||
            (text.front() >= 'a' && text.front() <= 'z') || text.front() == '_')) return "macro";
        ++state.uncorrelated; return "unknown";
    }
public:
    HanlinProvenanceCallbacks(clang::SourceManager &s, HanlinProvenanceState &v) : sm(s), state(v) {}
    bool FileNotFound(llvm::StringRef name) override {
        ++state.misses; state.fail("include-lookup-miss");
        state.event({{"kind", "missing"}, {"spelling", name.str()}});
        return false; // Observe only; never silently skip/recover an include.
    }
    void InclusionDirective(clang::SourceLocation hash, const clang::Token &token,
        llvm::StringRef name, bool angled, clang::CharSourceRange range,
        clang::OptionalFileEntryRef file, llvm::StringRef search, llvm::StringRef relative,
        const clang::Module *imported, clang::SrcMgr::CharacteristicKind) override {
        const bool main = sm.getFileID(sm.getExpansionLoc(hash)) == sm.getMainFileID();
        auto target = file ? file->getFileEntry().tryGetRealPathName().str() : std::string();
        auto parent = physical(hash);
        auto owner = state.owner(target);
        auto parentOwner = main ? "input-umbrella" : state.owner(parent);
        state.lastRoot = -1; state.lastTarget = target;
        state.lastIncluder = main ? "umbrella.h" : parent;
        state.lastLine = line(hash);
        state.lastDirective = token.getIdentifierInfo() ? token.getIdentifierInfo()->getName().str() : "unknown";
        if (imported) { state.serialized = true; state.fail("module-import"); }
        if (!file) { state.fail("unresolved-directive"); ++state.uncorrelated; }
        if (file && (target.empty() || owner.empty() || parentOwner.empty())) ++state.unknownOwners;
        if (main) {
            for (size_t i = 0; i < state.roots.size(); ++i) {
                auto &root = state.roots[i];
                if (root.getInteger("line") != static_cast<int64_t>(line(hash))) continue;
                if (hanlinString(root, "state") != "pending") { ++state.uncorrelated; break; }
                state.lastRoot = static_cast<int>(i);
                root["state"] = file ? "resolved" : "unresolved";
                root["resolvedPath"] = target; root["observedOwner"] = owner;
                if (hanlinString(root, "path") != target || hanlinString(root, "owner") != owner)
                    ++state.uncorrelated;
                if (file && hanlinSHA(hanlinRead(target)) != hanlinString(root, "sha256"))
                    state.fail("root-content-drift");
                break;
            }
            if (state.lastRoot < 0) ++state.uncorrelated;
        }
        auto source = sourceLine(hash);
        auto includeForm = form(source, angled);
        if (main || state.retain(target) || state.retain(parent)) {
            state.event({{"kind", "include"}, {"line", static_cast<int64_t>(line(hash))},
                {"directive", token.getIdentifierInfo() ? token.getIdentifierInfo()->getName().str() : "unknown"},
                {"form", includeForm}, {"filenameRangeIsMacro", range.getBegin().isMacroID()},
                {"sourceDirective", source}, {"isAngled", angled},
                {"expandedName", name.str()}, {"includer", main ? "umbrella.h" : parent},
                {"includerOwner", parentOwner}, {"requestedVFS", file ? file->getNameAsRequested().str() : ""},
                {"externalVFS", file ? file->getName().str() : ""}, {"resolvedPath", target},
                {"resolvedSHA256", file && !target.empty() ? hanlinSHA(hanlinRead(target)) : ""},
                {"includerSHA256", main ? state.umbrellaSHA : parent.empty() ? "" : hanlinSHA(hanlinRead(parent))},
                {"owner", owner}, {"searchPath", search.str()}, {"relativePath", relative.str()}});
        }
    }
    void FileSkipped(const clang::FileEntryRef &file, const clang::Token &token,
                     clang::SrcMgr::CharacteristicKind) override {
        auto path = file.getFileEntry().tryGetRealPathName().str();
        if (path.empty() || path != state.lastTarget) { ++state.uncorrelated; return; }
        if (state.lastRoot >= 0) {
            auto &root = state.roots[state.lastRoot];
            if (root.getInteger("line") != static_cast<int64_t>(line(token.getLocation()))) ++state.uncorrelated;
            else root["skip"] = "clang-file-skipped-mechanism-not-inferred";
        }
        if (state.lastRoot >= 0 || state.retain(path) || state.retain(state.lastIncluder))
            state.event({{"kind", "skipped"}, {"resolvedPath", path}, {"owner", state.owner(path)},
                {"includer", state.lastIncluder}, {"line", static_cast<int64_t>(state.lastLine)},
                {"rootOrdinal", state.lastRoot}, {"directive", state.lastDirective}});
    }
    void LexedFileChanged(clang::FileID fid, LexedFileChangeReason reason,
        clang::SrcMgr::CharacteristicKind, clang::FileID, clang::SourceLocation) override {
        auto file = sm.getFileEntryRefForID(fid);
        if (!file) return; // Compiler-owned non-file buffers, not include targets.
        auto path = file->getFileEntry().tryGetRealPathName().str();
        if (fid != sm.getMainFileID() && reason == LexedFileChangeReason::EnterFile) {
            if (path.empty() || state.owner(path).empty()) ++state.unknownOwners;
            else {
                auto digest = hanlinSHA(sm.getBufferData(fid));
                if (digest != hanlinSHA(hanlinRead(path))) state.fail("observed-buffer-content-drift");
                auto old = state.observedInputs.find(path);
                if (old != state.observedInputs.end() && old->second != digest) state.fail("observed-input-drift");
                if (state.observedInputs.size() >= 20000) state.truncated = true;
                else state.observedInputs[path] = digest;
            }
        }
        if (state.retain(path)) state.event({{"kind", reason == LexedFileChangeReason::EnterFile ? "enter" : "exit"},
            {"resolvedPath", path}, {"owner", state.owner(path)}});
    }
    void SourceRangeSkipped(clang::SourceRange range, clang::SourceLocation) override {
        if (sm.getFileID(sm.getExpansionLoc(range.getBegin())) != sm.getMainFileID()) return;
        auto first = line(range.getBegin()), last = line(range.getEnd());
        for (auto &root : state.roots) {
            auto n = root.getInteger("line");
            if (n && *n >= first && *n <= last && hanlinString(root, "state") == "pending")
                root["state"] = "inactive"; // Not a resolved include/observed owner.
        }
    }
    void PragmaDirective(clang::SourceLocation loc, clang::PragmaIntroducerKind) override {
        auto textBytes = sourceLine(loc);
        auto text = llvm::StringRef(textBytes).trim();
        auto path = physical(loc);
        if (state.retain(path)) state.event({{"kind", "pragma"}, {"includer", path},
            {"owner", state.owner(path)}, {"line", static_cast<int64_t>(line(loc))}, {"source", textBytes}});
        // Preserve ALL handlers. Only pragma-once has established equivalence
        // here; parser/Sema-dependent or unknown pragmas conservatively fail.
        if (text != "#pragma once" && text != "# pragma once") {
            ++state.pragmas; state.fail("unproven-pragma-semantics");
        }
    }
    void If(clang::SourceLocation loc, clang::SourceRange, ConditionValueKind value) override {
        condition(loc, "if", static_cast<int>(value));
    }
    void Elif(clang::SourceLocation loc, clang::SourceRange, ConditionValueKind value, clang::SourceLocation) override {
        condition(loc, "elif", static_cast<int>(value));
    }
    void Ifdef(clang::SourceLocation loc, const clang::Token &, const clang::MacroDefinition &value) override {
        condition(loc, "ifdef", value.getMacroInfo() != nullptr);
    }
    void Ifndef(clang::SourceLocation loc, const clang::Token &, const clang::MacroDefinition &value) override {
        condition(loc, "ifndef", value.getMacroInfo() == nullptr);
    }
    void Else(clang::SourceLocation loc, clang::SourceLocation) override { condition(loc, "else"); }
    void Endif(clang::SourceLocation loc, clang::SourceLocation) override { condition(loc, "endif"); }
    void moduleImport(clang::SourceLocation, clang::ModuleIdPath, const clang::Module *) override {
        state.serialized = true; state.fail("module-import");
    }
    void EndOfMainFile() override { state.ended = true; }
};
class HanlinProvenanceAction final : public clang::PreprocessorFrontendAction {
    HanlinProvenanceState &state;
public:
    explicit HanlinProvenanceAction(HanlinProvenanceState &s) : state(s) {}
    bool BeginInvocation(clang::CompilerInstance &ci) override {
        const auto &pp = ci.getPreprocessorOpts();
        state.ast |= ci.hasASTContext(); state.sema |= ci.hasSema();
        state.serialized = state.serializedArguments || ci.getLangOpts().Modules || !pp.ImplicitPCHInclude.empty() ||
            !pp.ChainedIncludes.empty() || pp.PrecompiledPreambleBytes.first != 0;
        if (state.serialized) state.fail("unsupported-serialized-context");
        return !state.serialized && !state.ast && !state.sema;
    }
    bool hasPCHSupport() const override { return false; }
    bool hasASTFileSupport() const override { return false; }
    bool BeginSourceFileAction(clang::CompilerInstance &ci) override {
        ci.getPreprocessor().SetSuppressIncludeNotFoundError(!cla_strictIncludes);
        ci.getPreprocessor().addPPCallbacks(std::make_unique<HanlinProvenanceCallbacks>(ci.getSourceManager(), state));
        return true;
    }
    void ExecuteAction() override {
        auto &ci = getCompilerInstance();
        auto &pp = ci.getPreprocessor();
        clang::Token token;
        pp.EnterMainSourceFile();
        do {
            pp.Lex(token);
            // A parser may be required to interpret source-level @import or
            // C++ import tokens. Do not infer module absence from PPCallbacks
            // alone when the parser is deliberately absent.
            if (token.is(clang::tok::identifier) || token.is(clang::tok::kw_import)) {
                auto *identifier = token.getIdentifierInfo();
                if (identifier && identifier->getName() == "import") {
                    state.serialized = true; state.fail("source-import-requires-parser");
                }
            }
        } while (token.isNot(clang::tok::eof));
        state.eof = token.is(clang::tok::eof);
        state.ast |= ci.hasASTContext(); state.sema |= ci.hasSema();
        state.error |= ci.getDiagnostics().hasErrorOccurred() || ci.getDiagnostics().hasFatalErrorOccurred();
        state.diagnosticErrors = ci.getDiagnostics().getNumErrors();
        state.diagnosticWarnings = ci.getDiagnostics().getNumWarnings();
    }
    void EndSourceFileAction() override {
        auto &ci = getCompilerInstance();
        state.actionEnded = true;
        state.ast |= ci.hasASTContext(); state.sema |= ci.hasSema();
        state.error |= ci.getDiagnostics().hasErrorOccurred() || ci.getDiagnostics().hasFatalErrorOccurred();
    }
};
static int hanlinProvenance(const std::vector<std::string> &args, const std::string &content,
                             const std::string &context) {
    auto outputPath = cla_provenanceOutput.getValue();
    if (outputPath.empty() || !llvm::sys::path::is_absolute(outputPath))
        throw std::runtime_error("Diagnostic receipt requires an absolute owned path");
    outputPath = hanlinCanonicalPath(outputPath);
    for (const auto &normal : {cla_outputBinFile.getValue(), cla_outputUmbrellaHeaderFile.getValue(),
        cla_outputYamlFolder.getValue(), cla_outputDtsFolder.getValue(), cla_outputModuleMapsFolder.getValue(),
        cla_inputUmbrellaHeaderFile.getValue(), cla_expectedClangContext.getValue(), cla_provenanceInputs.getValue()}) {
        auto canonical = normal.empty() ? std::string() : hanlinCanonicalPath(normal);
        if (!canonical.empty() && (outputPath == canonical || outputPath.compare(0, canonical.size() + 1, canonical + "/") == 0))
            throw std::runtime_error("Diagnostic receipt collides with an input/normal output");
    }
    auto requestBytes = hanlinRead(cla_provenanceInputs);
    auto value = llvm::json::parse(requestBytes);
    if (!value) { llvm::consumeError(value.takeError()); throw std::runtime_error("Invalid provenance JSON"); }
    if (!value->getAsObject()) throw std::runtime_error("Invalid provenance request");
    auto &request = *value->getAsObject();
    auto *bindings = request.getObject("bindings");
    auto *files = request.getArray("verifiedFiles");
    auto *roots = request.getArray("roots");
    auto *owners = request.getArray("owners");
    auto *prefixes = request.getArray("filteredPrefixes");
    if (!bindings || !files || !roots || !owners || !prefixes || roots->empty())
        throw std::runtime_error("Incomplete provenance request");
    if (hanlinString(*bindings, "contextSHA256") != hanlinSHA(context) ||
        hanlinString(*bindings, "umbrellaSHA256") != hanlinSHA(content))
        throw std::runtime_error("Provenance context/root drift");
    for (const auto &entry : *files) {
        auto *file = entry.getAsObject();
        if (!file || hanlinSHA(hanlinRead(hanlinString(*file, "path"))) != hanlinString(*file, "sha256"))
            throw std::runtime_error("Provenance bound-file drift");
    }
    HanlinProvenanceState state;
    state.umbrellaSHA = hanlinSHA(content);
    // Reject serialization requests in BeginInvocation, before preamble/PCH or
    // module-cache work. Module-map associations alone remain valid with modules
    // disabled; never rewrite the captured frontend vector to make it acceptable.
    for (const auto &arg : args) {
        llvm::StringRef flag(arg);
        if (flag == "-fmodules" || flag == "-fcxx-modules" || flag == "-fmodules-ts" ||
            flag == "-include-pch" || flag == "-include-pth" || flag == "-pch-through-header" ||
            flag.startswith("-fmodule-file") || flag.startswith("-fprebuilt-") ||
            flag.startswith("-fmodule-header") || flag.startswith("-preamble-bytes") ||
            flag.startswith("-emit-pch") || flag.startswith("-emit-module"))
            state.serializedArguments = true;
    }
    for (const auto &entry : *roots) {
        auto *root = entry.getAsObject();
        if (!root) throw std::runtime_error("Invalid root occurrence");
        auto line = root->getInteger("line");
        auto ordinal = root->getInteger("ordinal");
        if (!line || *line <= 0 || !ordinal || *ordinal != static_cast<int64_t>(state.roots.size()))
            throw std::runtime_error("Invalid root occurrence identity");
        for (const auto &previous : state.roots)
            if (previous.getInteger("line") == *line) throw std::runtime_error("Duplicate root occurrence line");
        llvm::json::Object copy{{"line", *line}, {"ordinal", *ordinal},
            {"path", hanlinString(*root, "path")}, {"owner", hanlinString(*root, "owner")},
            {"sha256", hanlinString(*root, "sha256")}};
        copy["state"] = "pending"; state.roots.push_back(std::move(copy));
    }
    for (const auto &entry : *owners) {
        auto *owner = entry.getAsObject();
        if (!owner) throw std::runtime_error("Invalid owner");
        state.owners.emplace_back(hanlinString(*owner, "root"), hanlinString(*owner, "id"));
    }
    for (const auto &entry : *prefixes) {
        auto prefix = entry.getAsString();
        if (!prefix) throw std::runtime_error("Invalid trace prefix");
        state.filtered.push_back(prefix->str());
    }
    auto fs = hanlinProvenanceFS(args, content);
    const bool ran = clang::tooling::runToolOnCodeWithArgs(
        std::make_unique<HanlinProvenanceAction>(state), content, fs, args,
        "umbrella.h", "objc-metadata-generator");
    uint64_t resolved = 0, inactive = 0;
    llvm::json::Array observedInputs;
    for (const auto &input : state.observedInputs) {
        if (hanlinSHA(hanlinRead(input.first)) != input.second) state.fail("observed-input-postflight-drift");
        observedInputs.push_back(llvm::json::Object{{"path", input.first}, {"sha256", input.second}});
    }
    llvm::json::Array rootResults;
    for (auto &root : state.roots) {
        if (hanlinString(root, "state") == "resolved") ++resolved;
        else if (hanlinString(root, "state") == "inactive") ++inactive;
        else state.fail("uncovered-root-occurrence");
        rootResults.push_back(std::move(root));
    }
    const bool complete = ran && state.eof && state.ended && state.actionEnded && !state.error &&
        !state.ast && !state.sema && !state.serialized && !state.truncated && !state.misses &&
        !state.unknownOwners && !state.uncorrelated && !state.pragmas && state.reasons.empty() &&
        !hanlinConsumerEntries && !hanlinWriterEntries;
    llvm::json::Object receipt{{"schemaVersion", 1}, {"mode", "preprocessing-provenance"},
        {"status", complete ? "COMPLETE" : "INCOMPLETE"}, {"bindings", std::move(*bindings)},
        {"requestSHA256", hanlinSHA(requestBytes)}, {"sawEOF", state.eof}, {"endOfMainFile", state.ended},
        {"actionEnded", state.actionEnded}, {"hadASTContext", state.ast}, {"hadSema", state.sema},
        {"hadErrors", state.error}, {"serializedContext", state.serialized}, {"truncated", state.truncated},
        {"diagnosticErrors", static_cast<int64_t>(state.diagnosticErrors)}, {"diagnosticWarnings", static_cast<int64_t>(state.diagnosticWarnings)},
        {"expectedRootOccurrences", static_cast<int64_t>(state.roots.size())},
        {"resolvedRootOccurrences", static_cast<int64_t>(resolved)}, {"inactiveRootOccurrences", static_cast<int64_t>(inactive)},
        {"lookupMisses", static_cast<int64_t>(state.misses)}, {"unknownOwners", static_cast<int64_t>(state.unknownOwners)},
        {"uncorrelated", static_cast<int64_t>(state.uncorrelated)}, {"unprovenPragmas", static_cast<int64_t>(state.pragmas)},
        {"consumerEntries", static_cast<int64_t>(hanlinConsumerEntries)}, {"writerEntries", static_cast<int64_t>(hanlinWriterEntries)},
        {"roots", std::move(rootResults)}, {"observedInputs", std::move(observedInputs)},
        {"events", std::move(state.events)}, {"reasons", std::move(state.reasons)}};
    // Exclusive output creation prevents input/canary/symlink overwrites.
    std::error_code ec;
    llvm::raw_fd_ostream output(outputPath, ec, llvm::sys::fs::CD_CreateNew);
    if (ec) throw std::runtime_error("Provenance receipt already exists or cannot be created");
    output << llvm::formatv("{0:2}", llvm::json::Value(std::move(receipt))) << "\n";
    output.close();
    return complete ? 0 : 2;
}
'''


def patch_main(text: str) -> str:
    text = replace_once(text, "#include <llvm/Support/Path.h>",
                        "#include <llvm/Support/Path.h>\n#include <llvm/Support/MemoryBuffer.h>\n"
                        "#include <llvm/Support/VirtualFileSystem.h>\n#include <stdexcept>")
    text = replace_once(text, '#include <clang/Frontend/CompilerInstance.h>',
                        '#include <clang/Frontend/CompilerInstance.h>\n#include <clang/Basic/Version.h>\n'
                        '#include <clang/Frontend/FrontendAction.h>\n#include <clang/Lex/PPCallbacks.h>\n'
                        '#include <clang/Lex/Preprocessor.h>\n#include <clang/Basic/SourceManager.h>\n'
                        '#include <clang/Lex/PreprocessorOptions.h>\n#include <llvm/Support/JSON.h>\n'
                        '#include <llvm/Support/FileSystem.h>\n'
                        '#include <llvm/Support/SHA256.h>\n#include <llvm/Support/FormatVariadic.h>\n#include <map>')
    text = replace_once(text, '// Command line parameters',
        '// Command line parameters\n'
        'llvm::cl::opt<string> cla_dumpClangContext("hanlin-dump-clang-context", llvm::cl::desc("Dump actual compiler context without AST generation"));\n'
        'llvm::cl::opt<string> cla_expectedClangContext("hanlin-expected-clang-context", llvm::cl::desc("Verify actual compiler context before AST generation"));\n'
        'llvm::cl::opt<string> cla_provenanceOutput("hanlin-preprocess-provenance", llvm::cl::desc("Opt-in diagnostic-only receipt; never emit metadata"));\n'
        'llvm::cl::opt<string> cla_provenanceInputs("hanlin-provenance-inputs", llvm::cl::desc("Bound diagnostic input manifest"));')
    text = replace_once(text, 'class MetaGenerationConsumer :', preprocessing_provenance_source() + '\nclass MetaGenerationConsumer :')
    # The upstream discovery helper builds an AST even with an explicit input
    # umbrella. A trace must not enter that helper. Reuse ONLY the discovery
    # tail from the separately captured normal context, checking every actual
    # generator/user argument and compiler byte before accepting that tail.
    text = replace_once(text,
        '        std::string umbrellaContent = CreateUmbrellaHeader(clangArgs, includePaths);', r'''
        std::string umbrellaContent;
        if (cla_provenanceOutput.empty()) {
            umbrellaContent = CreateUmbrellaHeader(clangArgs, includePaths);
        } else {
            if (cla_inputUmbrellaHeaderFile.empty() || cla_expectedClangContext.empty())
                throw std::runtime_error("Diagnostic mode requires explicit input and captured normal context");
            const auto captured = hanlinRead(cla_expectedClangContext);
            std::vector<std::string> fields;
            size_t start = 0;
            for (size_t i = 0; i < captured.size(); ++i) if (captured[i] == '\0') {
                fields.push_back(captured.substr(start, i - start)); start = i + 1;
            }
            if (start != captured.size() || fields.size() < clangArgs.size() + 1 ||
                fields[0] != clang::getClangFullVersion())
                throw std::runtime_error("Invalid captured normal compiler context");
            for (size_t i = 0; i < clangArgs.size(); ++i)
                if (fields[i + 1] != clangArgs[i]) throw std::runtime_error("Actual diagnostic argument drift");
            for (size_t i = clangArgs.size() + 1; i < fields.size(); ++i) {
                llvm::StringRef path(fields[i]);
                if (!path.startswith("-idirafter") || path.size() == 10 ||
                    !llvm::sys::fs::is_directory(path.drop_front(10)))
                    throw std::runtime_error("Unsupported captured discovery tail");
                includePaths.push_back(fields[i]);
            }
        }
''')
    context_hook = r'''
        // NUL framing preserves every argument byte without shell/JSON quoting.
        std::string hanlinContext = clang::getClangFullVersion();
        hanlinContext.push_back('\0');
        for (const auto& argument : clangArgs) {
            hanlinContext.append(argument);
            hanlinContext.push_back('\0');
        }
        if (!cla_provenanceOutput.empty() && (!cla_dumpClangContext.empty() ||
            cla_expectedClangContext.empty() || cla_provenanceInputs.empty()))
            throw std::runtime_error("Diagnostic mode requires an exclusive expected-context/input manifest");
        if (!cla_dumpClangContext.empty()) {
            std::ofstream output(cla_dumpClangContext.getValue(), std::ios::binary);
            output.write(hanlinContext.data(), hanlinContext.size());
            output.close();
            if (!output) throw std::runtime_error("Cannot retain actual metadata compiler context");
            return 0;
        }
        if (!cla_expectedClangContext.empty()) {
            std::ifstream expected(cla_expectedClangContext.getValue(), std::ios::binary);
            const std::string captured((std::istreambuf_iterator<char>(expected)), std::istreambuf_iterator<char>());
            if (!expected || captured != hanlinContext) throw std::runtime_error("Effective metadata compiler context drifted");
        }
        if (!cla_provenanceOutput.empty()) return hanlinProvenance(clangArgs, umbrellaContent, hanlinContext);
'''
    text = replace_once(text, '        clangArgs.insert(clangArgs.end(), includePaths.begin(), includePaths.end());',
        '        clangArgs.insert(clangArgs.end(), includePaths.begin(), includePaths.end());\n' + context_hook)
    text = replace_once(text, "        Context.getDiagnostics().Reset();",
                        "        // Preserve actual parser errors for runToolOnCodeWithArgs.")
    text = replace_once(text, "        Compiler.getPreprocessor().SetSuppressIncludeNotFoundError(!cla_strictIncludes);",
                        "        // Metadata serializes declarations, not inline implementation bodies.\n"
                        "        ++hanlinConsumerEntries;\n        Compiler.getFrontendOpts().SkipFunctionBodies = true;\n"
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
    for anchor in ['        if (!cla_outputModuleMapsFolder.empty()) {',
                   '        if (!cla_outputYamlFolder.empty()) {',
                   '        if (!cla_outputBinFile.empty()) {',
                   '        if (!cla_outputDtsFolder.empty()) {',
                   '        if (!cla_outputUmbrellaHeaderFile.empty()) {']:
        text = replace_once(text, anchor, anchor + '\n            ++hanlinWriterEntries;')
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
