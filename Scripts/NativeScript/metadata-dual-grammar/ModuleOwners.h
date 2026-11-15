#pragma once

#include "ActualUnits.h"
#include "ModelProof.h"

namespace HanlinDual {

class ModuleOwners {
    struct Owner { clang::Module* module; clang::SourceManager* source; };
    std::map<std::string, Owner> canonical;
    std::map<clang::Module*, Owner> actual;
    llvm::json::Array proofs;

    static llvm::json::Value definition(const Owner& owner) {
        const auto loc = owner.source->getExpansionLoc(owner.module->DefinitionLoc);
        if (loc.isInvalid()) throw std::runtime_error("Module owner has no actual definition location");
        const auto id = owner.source->getFileID(loc);
        auto entry = owner.source->getFileEntryRefForID(id);
        if (!entry) throw std::runtime_error("Module owner has no actual source file");
        const auto path = entry->getFileEntry().tryGetRealPathName().str();
        const auto bytes = owner.source->getBufferData(id);
        if (path.empty() || bytes != hanlinRead(path)) throw std::runtime_error("Module owner source identity/drift failure");
        return llvm::json::Object{{"path", path}, {"sha256", hanlinSHA(bytes)},
            {"line", static_cast<int64_t>(owner.source->getSpellingLineNumber(loc))},
            {"column", static_cast<int64_t>(owner.source->getSpellingColumnNumber(loc))}};
    }

    void collect(clang::Module* module, clang::SourceManager& source, bool authority) {
        actual.emplace(module, Owner{module, &source});
        const auto name = module->getFullModuleName();
        auto found = canonical.find(name);
        if (found == canonical.end()) canonical.emplace(name, Owner{module, &source});
        else if (authority && found->second.module != module)
            throw std::runtime_error("Multiple actual module owners in the authoritative AST");
        for (auto child = module->submodule_begin(); child != module->submodule_end(); ++child)
            collect(*child, source, authority);
    }

    void collect(ActualUnit& unit, bool authority) {
        llvm::SmallVector<clang::Module*, 64> modules;
        unit.unit().getPreprocessor().getHeaderSearchInfo().collectAllModules(modules);
        for (auto* module : modules) collect(module, unit.unit().getSourceManager(), authority);
    }

public:
    ModuleOwners(ActualUnit& objc, ActualUnit& cpp) { collect(objc, true); collect(cpp, false); }

    void apply(const std::set<Meta::Meta*>& graph) {
        std::set<clang::Module*> checked;
        for (auto* meta : graph) {
            auto found = actual.find(meta->module);
            if (found == actual.end()) throw std::runtime_error("Metadata refers to an unobserved module owner");
            auto& owner = found->second;
            auto target = canonical.find(owner.module->getFullModuleName());
            if (target == canonical.end()) throw std::runtime_error("Missing canonical module owner");
            if (checked.insert(owner.module).second && owner.module != target->second.module) {
                auto left = actualValue(owner.module);
                auto right = actualValue(target->second.module);
                auto source = definition(owner);
                if (left != right || source != definition(target->second))
                    throw std::runtime_error("Conflicting cross-grammar module definition/semantics: " + owner.module->getFullModuleName());
                proofs.push_back(llvm::json::Object{{"module", owner.module->getFullModuleName()},
                    {"actualDefinition", std::move(source)}, {"disposition", "PROVEN_EQUIVALENT_MODULE_OWNER"}});
            }
            meta->module = target->second.module;
        }
    }

    const llvm::json::Array& ownerProofs() const { return proofs; }
};

} // namespace HanlinDual
