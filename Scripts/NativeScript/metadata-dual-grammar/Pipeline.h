#pragma once

#include "ModelMerge.h"
#include "ActualUnits.h"
#include "ModuleOwners.h"

namespace HanlinDual {

// The fixture controls and the real entry point share this retained pipeline.
// These units own the real declarations and original factories until all
// serializers, including the per-declaration TypeScript writer, have finished.
class Pipeline {
    ModelMerge merger;
    std::unique_ptr<SDKExportAuthority> sdkAuthority;
    std::unique_ptr<ModuleOwners> owners;
    std::list<Meta::Meta*> canonical;
    Meta::ResolveGlobalNamesCollisionsFilter::MetasByModules modules;
    bool merged = false;

    Meta::MetaFactory& factory(Meta::Meta* meta) {
        if (!meta->declaration) throw std::runtime_error("Retained model has no actual declaration");
        auto* context = &meta->declaration->getASTContext();
        if (context == &cpp.context()) return cpp.producer().hanlinFactory();
        if (context == &objc.context()) return objc.producer().hanlinFactory();
        throw std::runtime_error("Model points outside the two retained AST contexts");
    }

public:
    ActualUnit cpp;
    ActualUnit objc;

    Pipeline(const std::string& cppCode, const std::vector<std::string>& cppArguments,
             const std::string& objcCode, const std::vector<std::string>& objcArguments,
             Meta::ModulesBlacklist& blacklist, llvm::IntrusiveRefCntPtr<llvm::vfs::FileSystem> fs,
             const llvm::json::Object* request = nullptr)
        : cpp(cppCode, cppArguments, blacklist, fs), objc(objcCode, objcArguments, blacklist, fs) {
        llvm::errs() << "Hanlin dual resources: retained AST/model collection cpp=" << cpp.models().size()
                     << " objc=" << objc.models().size() << " peakRSSBytes=" << peakResidentBytes() << "\n";
        if (!cpp.context().getLangOpts().CPlusPlus || objc.context().getLangOpts().CPlusPlus ||
            !cpp.context().getLangOpts().ObjC || !objc.context().getLangOpts().ObjC)
            throw std::runtime_error("Dual grammar requires actual ObjC++ and ObjC source ASTs");
        for (const auto* key : {"compiler", "target", "resourceDirectory"})
            if (cpp.receipt.getString(key) != objc.receipt.getString(key))
                throw std::runtime_error(std::string("Actual dual compiler context differs: ") + key);
        if (searchDirectories(cpp.unit()) != searchDirectories(objc.unit()))
            throw std::runtime_error("Actual include search priority/characteristics differ");
        if (request && request->getString("sdkExportEvidence") && !request->getString("sdkExportEvidence")->empty()) {
            sdkAuthority = std::make_unique<SDKExportAuthority>(*request, cpp.receipt);
            merger.setExportAuthority(sdkAuthority.get());
        }
        cpp.producer().hanlinFactory().hanlinSetPeer(objc.producer().hanlinFactory());
        objc.producer().hanlinFactory().hanlinSetPeer(cpp.producer().hanlinFactory());
    }

    std::list<Meta::Meta*>& merge() {
        if (merged) throw std::runtime_error("Dual grammar merge may execute only once");
        canonical = merger.merge(cpp.models(), objc.models());
        llvm::errs() << "Hanlin dual resources: complete model merge peakRSSBytes=" << peakResidentBytes() << "\n";
        requireResidentBudget("complete model merge and original-A coverage");
        owners = std::make_unique<ModuleOwners>(objc, cpp);
        owners->apply(merger.retainedMetas());
        std::map<std::string, std::pair<clang::Module*, std::vector<Meta::Meta*>>> groups;
        Meta::ResolveGlobalNamesCollisionsFilter::InterfacesByName interfaces;
        for (auto* meta : canonical) {
            factory(meta).validate(meta);
            auto* owner = meta->module->getTopLevelModule();
            auto& group = groups[owner->getFullModuleName()];
            if (group.first && group.first != owner) throw std::runtime_error("Noncanonical serialized module owner");
            group.first = owner; group.second.push_back(meta);
            if (meta->is(Meta::MetaType::Interface) && !interfaces.emplace(meta->name, &meta->as<Meta::InterfaceMeta>()).second)
                throw std::runtime_error("Duplicate native ObjC interface identity");
        }
        cpp.producer().hanlinFactory().getTypeFactory().resolveCachedBridgedInterfaceTypes(interfaces);
        objc.producer().hanlinFactory().getTypeFactory().resolveCachedBridgedInterfaceTypes(interfaces);
        for (auto& group : groups) modules.push_back(std::move(group.second));
        merged = true;
        return canonical;
    }

    const std::set<Meta::Meta*>& retainedMetas() const { return merger.retainedMetas(); }

    llvm::json::Object proofReceipt() const {
        if (!merged) throw std::runtime_error("No complete dual model merge");
        return llvm::json::Object{{"cpp", llvm::json::Object(cpp.receipt)},
            {"objc", llvm::json::Object(objc.receipt)}, {"mergePolicyVersion", 3},
            {"duplicateProofs", llvm::json::Array(merger.duplicateProofs())},
            {"originalAModelCoverage", llvm::json::Object(merger.originalAProof())},
            {"sameObjectRepeatedMemberReferencesPreserved", static_cast<int64_t>(merger.repeatedAuthoritativeReferences)},
            {"moduleOwnerProofs", llvm::json::Array(owners->ownerProofs())}};
    }

    llvm::json::Object lifetime() {
        requireResidentBudget("retained AST lifetime postflight");
        if (sdkAuthority) sdkAuthority->verify();
        size_t cppModels = 0, objcModels = 0;
        for (auto* meta : merger.retainedMetas()) {
            auto& owner = factory(meta);
            if (&owner == &cpp.producer().hanlinFactory()) ++cppModels;
            else ++objcModels;
        }
        // Read both roots after the actual output writers, while both real
        // SourceManagers and all factory-owned model/type objects are alive.
        for (auto* unit : {&cpp, &objc}) {
            auto& source = unit->unit().getSourceManager();
            if (unit->receipt.getString("rootSHA256").value_or("") != hanlinSHA(source.getBufferData(source.getMainFileID())))
                throw std::runtime_error("Actual AST root lifetime/identity changed before serialization completed");
            if (dependencies(unit->unit()) != *unit->receipt.getObject("sourceDependencies"))
                throw std::runtime_error("Actual source dependency changed during dual serialization");
        }
        return llvm::json::Object{{"cppOwnedModels", static_cast<int64_t>(cppModels)},
            {"objcOwnedModels", static_cast<int64_t>(objcModels)},
            {"bothSourceManagersReadAfterSerialization", true},
            {"retainedGraphTypes", static_cast<int64_t>(merger.graphTypes)}};
    }

    void emit() {
        if (!merged || hanlinWriterEntries) throw std::runtime_error("Writers must follow a complete dual merge exactly once");
        const std::string types = cla_outputDtsFolder.getValue();
        // Binary/YAML use the original emitter unchanged. The original DTS
        // writer must use the factory owning its actual class declaration.
        cla_outputDtsFolder.setValue("");
        cpp.producer().hanlinEmitMetadata(canonical, modules);
        cla_outputDtsFolder.setValue(types);
        if (!types.empty()) {
            ++hanlinWriterEntries;
            if (llvm::sys::fs::create_directories(types)) throw std::runtime_error("Cannot create dual TypeScript output");
            const std::string docs = cla_docSetFile.getValue();
            for (auto& module : modules) {
                const auto path = types + "/objc!" + module.first->getFullModuleName() + ".d.ts";
                std::error_code error;
                llvm::raw_fd_ostream file(path, error, llvm::sys::fs::CD_CreateNew);
                if (error) throw std::runtime_error("Cannot exclusively create dual TypeScript file");
                for (auto* meta : module.second) {
                    std::pair<clang::Module*, std::vector<Meta::Meta*>> one{module.first, {meta}};
                    TypeScript::DefinitionWriter writer(one, factory(meta).getTypeFactory(), docs);
                    file << writer.write();
                }
                file.close();
                if (file.has_error()) throw std::runtime_error("Dual TypeScript write failed");
            }
        }
        requireResidentBudget("original binary/YAML/TypeScript serialization");
    }
};

} // namespace HanlinDual
