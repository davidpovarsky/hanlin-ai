// Compile the exact adapted producer into a focused native test executable.
// This rename changes only this host test's entry point, never SDK feature macros.
#define main hanlin_original_metadata_entry
#include "../main.cpp"
#undef main
#include "ActualUnits.h"
#include "ModuleOwners.h"

static void writeControlReceipt(const std::string& path, const llvm::json::Object& receipt) {
    std::error_code error;
    llvm::raw_fd_ostream stream(path, error, llvm::sys::fs::CD_CreateNew);
    if (error) throw std::runtime_error("Control receipt path is not exclusively owned");
    stream << llvm::formatv("{0:2}", llvm::json::Value(llvm::json::Object(receipt))) << "\n";
}

int main(int argc, const char** argv) {
    if (argc != 2) return 2;
    auto parsed = llvm::json::parse(hanlinRead(argv[1]));
    if (!parsed || !parsed->getAsObject()) return 2;
    const auto& config = *parsed->getAsObject();
    const std::string root = hanlinString(config, "root");
    const std::string sdk = hanlinString(config, "sdk");
    const std::string resource = hanlinString(config, "resource");
    const std::string output = hanlinString(config, "output");
    const std::string receiptPath = hanlinString(config, "receipt");
    const std::string expectation = hanlinString(config, "expectation");
    const std::string expectedReason = hanlinString(config, "expectedReason");
    llvm::json::Object receipt{{"status", "FAILED"}, {"metadataAcceptance", "NOT_ESTABLISHED"},
        {"boundary", "Actual compiler/model/serializer control only; no VM, app or device acceptance"}};
    std::string stage = "parse";
    try {
        std::vector<std::string> common{"-target", hanlinString(config, "target"), "-isysroot", sdk,
            "-resource-dir", resource, "-fno-objc-arc", "-fno-modules", "-fmodule-maps", "-fno-implicit-module-maps",
            "-D__NATIVESCRIPT_METADATA_GENERATOR=1", "-I" + root,
            "-fmodule-map-file=" + root + "/module.modulemap",
            "-isystem", sdk + "/usr/include/c++/v1", "-isystem", resource + "/include",
            "-isystem", sdk + "/usr/include", "-iframework", sdk + "/System/Library/Frameworks"};
        auto cppArguments = common;
        cppArguments.insert(cppArguments.end(), {"-x", "objective-c++", "-std=gnu++20", "-Xclang", "-fno-cxx-modules"});
        auto objcArguments = common;
        objcArguments.insert(objcArguments.end(), {"-x", "objective-c", "-std=gnu17"});
        std::string whitelistFile, blacklistFile;
        Meta::ModulesBlacklist blacklist(whitelistFile, blacklistFile);
        HanlinDual::ActualUnit cpp(hanlinRead(root + "/full.h"), cppArguments, blacklist, llvm::vfs::getRealFileSystem());
        receipt["cpp"] = llvm::json::Object(cpp.receipt);
        HanlinDual::ActualUnit objc(hanlinRead(root + "/objc.h"), objcArguments, blacklist, llvm::vfs::getRealFileSystem());
        receipt["objc"] = llvm::json::Object(objc.receipt);
        cpp.producer().hanlinFactory().hanlinSetPeer(objc.producer().hanlinFactory());
        objc.producer().hanlinFactory().hanlinSetPeer(cpp.producer().hanlinFactory());
        if (HanlinDual::searchDirectories(cpp.unit()) != HanlinDual::searchDirectories(objc.unit()))
            throw std::runtime_error("Actual include search priority/characteristics differ");
        stage = "merge";
        HanlinDual::ModelMerge merge;
        auto models = merge.merge(cpp.models(), objc.models());
        receipt["duplicateProofs"] = llvm::json::Value(llvm::json::Array(merge.duplicateProofs()));
        HanlinDual::ModuleOwners owners(objc, cpp);
        owners.apply(merge.retainedMetas());
        receipt["moduleOwnerProofs"] = llvm::json::Value(llvm::json::Array(owners.ownerProofs()));
        size_t cppModels = 0, objcModels = 0;
        for (auto* meta : merge.retainedMetas()) {
            if (!meta->declaration) throw std::runtime_error("Retained model has no real AST declaration");
            auto* context = &meta->declaration->getASTContext();
            if (context == &cpp.context()) ++cppModels;
            else if (context == &objc.context()) ++objcModels;
            else throw std::runtime_error("Model points outside the two retained actual AST contexts");
        }
        if (!cppModels || !objcModels) throw std::runtime_error("Both actual AST lifetimes were not exercised");
        if (expectation != "pass") throw std::runtime_error("Expected conflict was not rejected");

        std::map<std::string, std::pair<clang::Module*, std::vector<Meta::Meta*>>> groups;
        Meta::ResolveGlobalNamesCollisionsFilter::InterfacesByName interfaces;
        Meta::StructMeta* shared = nullptr;
        Meta::FunctionMeta* provider = nullptr;
        bool onlyCRecord = false, onlyCFunction = false;
        for (auto* meta : models) {
            auto* owner = meta->module->getTopLevelModule();
            auto& group = groups[owner->getFullModuleName()];
            if (group.first && group.first != owner) throw std::runtime_error("Noncanonical serialized module owner");
            group.first = owner; group.second.push_back(meta);
            if (meta->is(Meta::MetaType::Interface) && !interfaces.emplace(meta->name, &meta->as<Meta::InterfaceMeta>()).second)
                throw std::runtime_error("Duplicate native ObjC interface identity");
            if (meta->name == "HanlinDualShared") shared = &meta->as<Meta::StructMeta>();
            if (meta->name == "HanlinDualProvider") provider = &meta->as<Meta::FunctionMeta>();
            onlyCRecord |= meta->name == "HanlinDualCOnlyRecord";
            onlyCFunction |= meta->name == "HanlinDualCOnlyFunction";
        }
        if (!shared || !provider || !onlyCRecord || !onlyCFunction)
            throw std::runtime_error("Actual C-only/provider/shared models were not preserved");
        auto* argument = provider->signature.at(1)->stripNullability();
        if (!argument->is(Meta::TypeType::TypePointer) ||
            !argument->as<Meta::PointerType>().innerType->is(Meta::TypeType::TypeStruct) ||
            argument->as<Meta::PointerType>().innerType->as<Meta::StructType>().structMeta != shared)
            throw std::runtime_error("Cross-context provider type did not reconnect to authoritative actual record");
        cpp.producer().hanlinFactory().validate(provider->signature.at(1));
        receipt["crossFactoryTypeValidation"] = true;
        cpp.producer().hanlinFactory().getTypeFactory().resolveCachedBridgedInterfaceTypes(interfaces);
        objc.producer().hanlinFactory().getTypeFactory().resolveCachedBridgedInterfaceTypes(interfaces);
        Meta::ResolveGlobalNamesCollisionsFilter::MetasByModules modules;
        for (auto& group : groups) modules.push_back(std::move(group.second));
        if (hanlinWriterEntries) throw std::runtime_error("An output writer ran before both parses and merge succeeded");
        stage = "serialization";
        cla_outputBinFile.setValue(output);
        cla_outputYamlFolder.setValue(output + ".yaml");
        cpp.producer().hanlinEmitMetadata(models, modules);
        // Touch both live SourceManagers after original serialization. This is
        // actual declaration/context ownership execution, not a lifetime stub.
        const auto cppRoot = cpp.unit().getSourceManager().getBufferData(cpp.unit().getSourceManager().getMainFileID());
        const auto objcRoot = objc.unit().getSourceManager().getBufferData(objc.unit().getSourceManager().getMainFileID());
        if (hanlinSHA(cppRoot) != hanlinSHA(hanlinRead(root + "/full.h")) ||
            hanlinSHA(objcRoot) != hanlinSHA(hanlinRead(root + "/objc.h")))
            throw std::runtime_error("Actual AST root lifetime/identity changed before serialization completed");
        receipt["lifetime"] = llvm::json::Object{{"cppOwnedModels", static_cast<int64_t>(cppModels)},
            {"objcOwnedModels", static_cast<int64_t>(objcModels)}, {"bothSourceManagersReadAfterSerialization", true},
            {"retainedGraphTypes", static_cast<int64_t>(merge.graphTypes)}};
        receipt["metadataSHA256"] = hanlinSHA(hanlinRead(output));
        receipt["peakRSSAfterSerialization"] = HanlinDual::peakResidentBytes();
        receipt["status"] = "EXECUTED_PASS";
    } catch (const std::exception& error) {
        receipt["reason"] = std::string(error.what());
        llvm::errs() << "Dual grammar control rejected at " << stage << ": " << error.what() << "\n";
        receipt["stage"] = stage;
        const auto expectedStage = expectation == "parse-failure" ? "parse" : "merge";
        if (expectation != "pass" && !expectedReason.empty() && std::string(error.what()).find(expectedReason) == 0 &&
            stage == expectedStage && !llvm::sys::fs::exists(output) && hanlinWriterEntries == 0)
            receipt["status"] = "REJECTED_EXPECTED";
    }
    receipt["consumerEntries"] = static_cast<int64_t>(hanlinConsumerEntries);
    receipt["writerEntries"] = static_cast<int64_t>(hanlinWriterEntries);
    writeControlReceipt(receiptPath, receipt);
    auto status = receipt.getString("status");
    return status && (*status == "EXECUTED_PASS" || *status == "REJECTED_EXPECTED") ? 0 : 1;
}
