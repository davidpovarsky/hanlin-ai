// Candidate export-authority audit only; not wired into metadata generation.
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

using namespace llvm;
using namespace llvm::MachO;
namespace fs = std::filesystem;

class ExportClosure {
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
    ExportClosure(fs::path sdkRoot, fs::path path) : sdk(fs::canonical(sdkRoot)), root(&load(path)) {}
    InterfaceFile& ownerOf(StringRef symbol, const Target& target) {
        for (auto& entry : documents) {
            auto value = entry.second->getSymbol(EncodeKind::GlobalSymbol, symbol);
            if (value && (*value)->hasTarget(target)) return *entry.second;
        }
        throw std::runtime_error("FIXTURE_OWNER_MISSING");
    }
    json::Object choose(const Target& target, StringRef c, StringRef cpp) {
        visit(*root, target, c, cpp);
        if (cOwners.size() != 1) throw std::runtime_error(cOwners.empty() ? "MISSING_C_EXPORT" : "AMBIGUOUS_C_EXPORT");
        if (!cppOwners.empty()) throw std::runtime_error("CPP_EXPORT_EXISTS");
        json::Object hashes;
        for (const auto& file : consumed) hashes[file.first] = file.second;
        return json::Object{{"decision", "PROPOSED_C_EXPORT_AUTHORITY"}, {"owner", *cOwners.begin()},
            {"visitedLibraries", static_cast<int64_t>(visited.size())}, {"consumedExportFiles", std::move(hashes)}};
    }
};

int main(int argc, char** argv) {
    if (argc != 7) return 2;
    const std::string sdk = argv[1], stub = argv[2], targetText = argv[3], c = argv[4], cpp = argv[5], output = argv[6];
    auto parsedTarget = Target::create(targetText);
    if (!parsedTarget) { errs() << toString(parsedTarget.takeError()); return 2; }
    const auto target = *parsedTarget;
    json::Array cases;
    bool passed = true;
    const auto run = [&](StringRef name, StringRef expected, auto mutation, StringRef requestedC = StringRef()) {
        json::Object receipt{{"case", name.str()}, {"expected", expected.str()}};
        try {
            ExportClosure closure(sdk, stub);
            Target selected = target;
            mutation(closure, selected);
            auto proof = closure.choose(selected, requestedC.empty() ? StringRef(c) : requestedC, cpp);
            receipt["decision"] = std::move(proof);
            receipt["status"] = expected == "PASS" ? "EXECUTED_PASS" : "FAILED";
        } catch (const std::exception& error) {
            receipt["reason"] = std::string(error.what());
            receipt["status"] = StringRef(error.what()).starts_with(expected) ? "EXECUTED_PASS" : "FAILED";
        }
        if (receipt.getString("status") != "EXECUTED_PASS") passed = false;
        cases.push_back(std::move(receipt));
    };
    run("actual-sdk-single-C-export", "PASS", [](auto&, auto&) {});
    run("genuine-both-bindings-exported", "CPP_EXPORT_EXISTS", [&](auto& closure, auto& selected) {
        closure.ownerOf(c, selected).addSymbol(EncodeKind::GlobalSymbol, cpp, selected);
    });
    run("ambiguous-C-export-owner", "AMBIGUOUS_C_EXPORT", [&](auto& closure, auto& selected) {
        closure.root->addSymbol(EncodeKind::GlobalSymbol, c, selected);
    });
    run("missing-C-export", "MISSING_C_EXPORT", [](auto&, auto&) {}, c + "_not_exported");
    run("wrong-target-platform", "TARGET_MISMATCH", [&](auto&, auto& selected) {
        auto device = Target::create("arm64-ios");
        if (!device) throw std::runtime_error(toString(device.takeError()));
        selected = *device;
    });
    run("unresolved-target-reexport", "MISSING_EXPORT_FILE", [&](auto& closure, auto& selected) {
        closure.root->addReexportedLibrary("/System/Library/Frameworks/HanlinMissing.framework/HanlinMissing", selected);
    });
    std::error_code error;
    raw_fd_ostream file(output, error);
    if (error) return 2;
    file << formatv("{0:2}\n", json::Value(json::Object{{"status", passed ? "EXECUTED_PASS" : "FAILED"},
        {"scope", "NATIVE_EXPORT_AUTHORITY_PROTOTYPE_ONLY"}, {"target", targetText}, {"CBinding", c}, {"CPPBinding", cpp},
        {"cases", std::move(cases)}, {"productionMergePolicy", "UNCHANGED_FATAL_CONTRACT2"}}));
    return passed ? 0 : 1;
}
