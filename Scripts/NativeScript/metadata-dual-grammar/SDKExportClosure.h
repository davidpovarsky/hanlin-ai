#pragma once
// Parse original SDK stubs with LLVM's installed TextAPI reader; resolve only
// exact-target public-framework reexports. Never synthesize a public module.
#include <llvm/ADT/StringExtras.h>
#include <llvm/TextAPI/TextAPIReader.h>
#include <llvm/TextAPI/InterfaceFile.h>
#include <llvm/Support/MemoryBuffer.h>
#include <llvm/Support/JSON.h>
#include <llvm/Support/FormatVariadic.h>
#include <llvm/Support/Error.h>
#include <llvm/Support/SHA256.h>
#include <llvm/Support/raw_ostream.h>
#include <filesystem>
#include <map>
#include <set>
#include <stdexcept>

namespace HanlinDual {
using namespace llvm;
using namespace llvm::MachO;
namespace fs = std::filesystem;

class SDKExportClosure {
    fs::path sdk;
    std::vector<std::unique_ptr<InterfaceFile>> files;
    std::map<std::string, InterfaceFile*> documents;
    std::map<std::string, std::string> consumed;
    std::set<std::string> visited;
    std::set<std::string> cOwners, cppOwners;
    void index(InterfaceFile& file) {
        const auto name = file.getInstallName().str();
        if (!documents.emplace(name, &file).second) throw std::runtime_error("AMBIGUOUS_INSTALL_NAME");
        for (const auto& child : file.documents()) index(*child);
    }
    InterfaceFile& load(fs::path path) {
        if (!fs::is_regular_file(path)) throw std::runtime_error("MISSING_EXPORT_FILE");
        const auto physical = fs::canonical(path);
        const auto relative = physical.lexically_relative(sdk);
        if (relative.empty() || relative.is_absolute() || *relative.begin() == "..") throw std::runtime_error("OUTSIDE_BOUND_SDK");
        auto buffer = MemoryBuffer::getFile(path.string());
        if (!buffer) throw std::runtime_error("MISSING_EXPORT_FILE");
        auto parsed = TextAPIReader::get((*buffer)->getMemBufferRef());
        if (!parsed) throw std::runtime_error("UNPARSEABLE_EXPORT_FILE: " + toString(parsed.takeError()));
        consumed.emplace(physical.string(), toHex(SHA256::hash(arrayRefFromStringRef((*buffer)->getBuffer())), true));
        auto* file = parsed->get();
        files.push_back(std::move(*parsed));
        index(*file);
        return *file;
    }
    InterfaceFile& resolve(StringRef name) {
        auto known = documents.find(name.str());
        if (known != documents.end()) return *known->second;
        fs::path relative(name.str());
        if (!relative.is_absolute()) throw std::runtime_error("UNRESOLVED_NONABSOLUTE_REEXPORT");
        fs::path path = sdk / relative.relative_path();
        if (path.extension() == ".dylib") path.replace_extension(".tbd");
        else path += ".tbd";
        load(path);
        known = documents.find(name.str());
        if (known == documents.end()) throw std::runtime_error("REEXPORT_INSTALL_NAME_MISMATCH");
        return *known->second;
    }
    void visit(InterfaceFile& file, const Target& target, StringRef c, StringRef cpp) {
        if (!file.hasTarget(target)) throw std::runtime_error("TARGET_MISMATCH");
        if (!visited.insert(file.getInstallName().str()).second) return;
        for (const auto* symbol : file.exports()) {
            if (symbol->getKind() != EncodeKind::GlobalSymbol || !symbol->hasTarget(target) || symbol->isUndefined()) continue;
            if (symbol->getName() == c) cOwners.insert(file.getInstallName().str());
            if (symbol->getName() == cpp) cppOwners.insert(file.getInstallName().str());
        }
        for (const auto& reference : file.reexportedLibraries()) {
            bool applies = false;
            for (const auto& item : reference.targets()) if (item == target) applies = true;
            if (applies) visit(resolve(reference.getInstallName()), target, c, cpp);
        }
    }
public:
    InterfaceFile* root;
    SDKExportClosure(fs::path sdkRoot, fs::path path) : sdk(fs::canonical(sdkRoot)), root(&load(path)) {}
    InterfaceFile& ownerOf(StringRef symbol, const Target& target) {
        for (auto& entry : documents) {
            auto value = entry.second->getSymbol(EncodeKind::GlobalSymbol, symbol);
            if (value && (*value)->hasTarget(target)) return *entry.second;
        }
        throw std::runtime_error("FIXTURE_OWNER_MISSING");
    }
    void verify() const {
        for (const auto& input : consumed) {
            auto buffer = MemoryBuffer::getFile(input.first);
            if (!buffer || toHex(SHA256::hash(arrayRefFromStringRef((*buffer)->getBuffer())), true) != input.second)
                throw std::runtime_error("EXPORT_FILE_CHANGED_DURING_OPERATION");
        }
    }
    json::Object choose(const Target& target, StringRef c, StringRef cpp) {
        visited.clear(); cOwners.clear(); cppOwners.clear();
        visit(*root, target, c, cpp);
        if (cOwners.size() != 1) throw std::runtime_error(cOwners.empty() ? "MISSING_C_EXPORT" : "AMBIGUOUS_C_EXPORT");
        if (!cppOwners.empty()) throw std::runtime_error("CPP_EXPORT_EXISTS");
        verify();
        json::Object hashes;
        for (const auto& file : consumed) hashes[file.first] = file.second;
        return json::Object{{"decision", "RESOLVED_TO_EXPORTED_C_AUTHORITY"}, {"exportImplementationInstallName", *cOwners.begin()}, {"publicFrameworkInstallName", root->getInstallName().str()},
            {"visitedLibraries", static_cast<int64_t>(visited.size())}, {"consumedExportFiles", std::move(hashes)}};
    }
};

} // namespace HanlinDual
