#pragma once

#include "ModelGraph.h"
#include "ModelProof.h"
#include <clang/Basic/TargetInfo.h>
#include <algorithm>
#include <list>

namespace HanlinDual {

class ModelMerge {
    std::map<Meta::Meta*, Meta::Meta*> replacements;
    std::set<std::pair<Meta::Meta*, Meta::Meta*>> compared;
    llvm::json::Array proofs;
    std::set<Meta::Meta*> retained;

    static Meta::Version targetVersion(const clang::ASTContext& context) {
        auto version = context.getTargetInfo().getTriple().getOSVersion();
        return {static_cast<int>(version.getMajor()), static_cast<int>(version.getMinor().value_or(0)),
                static_cast<int>(version.getSubminor().value_or(0))};
    }

    static bool introducedAvailabilityEquivalent(const Meta::Meta& cpp, const Meta::Meta& objc) {
        if (cpp.introducedIn == objc.introducedIn) return true;
        // OBJC_AVAILABLE precedes OBJC_EXPORT's extern-C linkage specification
        // in this SDK. The actual C AST attaches it to the ObjC interface;
        // the C++ AST has an extern-C lexical wrapper and no introduced attr.
        // Prove equivalent availability AT THE BOUND TARGET, retain C's actual
        // annotation in the emitted model, and record this bounded exception.
        if (!cpp.introducedIn.isUnknown() || objc.introducedIn.isUnknown() ||
            !cpp.is(Meta::MetaType::Interface) || !objc.is(Meta::MetaType::Interface) ||
            !cpp.declaration->getLexicalDeclContext()->isExternCContext()) return false;
        const auto cppTarget = targetVersion(cpp.declaration->getASTContext());
        const auto objcTarget = targetVersion(objc.declaration->getASTContext());
        return cppTarget == objcTarget && cppTarget >= objc.introducedIn;
    }

    template<class T> void members(std::vector<T*>& objc, const std::vector<T*>& cpp) {
        std::map<std::string, T*> index;
        for (auto* member : objc) {
            if (!index.emplace(entityKey(*member), member).second)
                throw std::runtime_error("Duplicate member identity in actual ObjC model");
        }
        for (auto* member : cpp) {
            auto found = index.find(entityKey(*member));
            if (found == index.end()) {
                objc.push_back(member);
                index.emplace(entityKey(*member), member);
            } else {
                duplicate(member, found->second);
            }
        }
        std::stable_sort(objc.begin(), objc.end(), [](const T* left, const T* right) {
            return entityKey(*left) < entityKey(*right);
        });
    }

    void duplicate(Meta::Meta* cpp, Meta::Meta* objc) {
        if (!compared.emplace(cpp, objc).second) return;
        if (entityKey(*cpp) != entityKey(*objc) || !sameSourceOwner(*cpp, *objc))
            throw std::runtime_error("Dual-grammar canonical declaration/owner conflict: " + cpp->identificationString());
        auto cppABI = declarationABI(*cpp);
        auto objcABI = declarationABI(*objc);
        if (cppABI != objcABI)
            throw std::runtime_error("Dual-grammar actual AST ABI conflict: " + cpp->identificationString() +
                "\nActual CPP ABI=" + llvm::formatv("{0}", cppABI).str() +
                "\nActual ObjC ABI=" + llvm::formatv("{0}", objcABI).str());
        if (cpp->deprecatedIn != objc->deprecatedIn || cpp->obsoletedIn != objc->obsoletedIn ||
            !introducedAvailabilityEquivalent(*cpp, *objc))
            throw std::runtime_error("Dual-grammar availability conflict: " + cpp->identificationString());

        auto cppModel = modelValue(cpp);
        auto objcModel = modelValue(objc);
        auto* cppFields = cppModel.getAsObject();
        auto* objcFields = objcModel.getAsObject();
        if (!cppFields || !objcFields) throw std::runtime_error("Actual entity model is not an object");
        const bool availabilityDifference = cpp->introducedIn != objc->introducedIn;
        if (availabilityDifference) {
            cppFields->erase("IntroducedIn"); objcFields->erase("IntroducedIn");
        }
        const bool base = cpp->is(Meta::MetaType::Interface) || cpp->is(Meta::MetaType::Protocol) || cpp->is(Meta::MetaType::Category);
        if (base) {
            // Compare the owning entity independently, then prove each shared
            // actual method/property/protocol and retain all real additions.
            for (auto name : {"InstanceMethods", "StaticMethods", "InstanceProperties", "StaticProperties", "Protocols"}) {
                cppFields->erase(name); objcFields->erase(name);
            }
        }
        if (cppModel != objcModel)
            throw std::runtime_error("Dual-grammar actual API model conflict: " + cpp->identificationString() +
                "\nActual CPP model=" + llvm::formatv("{0}", cppModel).str() +
                "\nActual ObjC model=" + llvm::formatv("{0}", objcModel).str());
        if (base) {
            auto& a = cpp->as<Meta::BaseClassMeta>();
            auto& b = objc->as<Meta::BaseClassMeta>();
            members(b.instanceMethods, a.instanceMethods); members(b.staticMethods, a.staticMethods);
            members(b.instanceProperties, a.instanceProperties); members(b.staticProperties, a.staticProperties);
            members(b.protocols, a.protocols);
        }
        if (cpp->is(Meta::MetaType::Property)) {
            auto& a = cpp->as<Meta::PropertyMeta>();
            auto& b = objc->as<Meta::PropertyMeta>();
            if (bool(a.getter) != bool(b.getter) || bool(a.setter) != bool(b.setter))
                throw std::runtime_error("Dual-grammar property accessor conflict");
            if (a.getter) duplicate(a.getter, b.getter);
            if (a.setter) duplicate(a.setter, b.setter);
        }
        replacements.emplace(cpp, objc);
        llvm::json::Object rawLinkage;
        if (const auto* variable = clang::dyn_cast<clang::VarDecl>(cpp->declaration)) {
            const auto* authoritative = clang::dyn_cast<clang::VarDecl>(objc->declaration);
            if (!authoritative) throw std::runtime_error("Actual variable declaration kind mismatch");
            rawLinkage["cppLanguageLinkage"] = static_cast<int64_t>(variable->getLanguageLinkage());
            rawLinkage["objcLanguageLinkage"] = static_cast<int64_t>(authoritative->getLanguageLinkage());
        }
        proofs.push_back(llvm::json::Object{{"canonicalKey", entityKey(*objc)},
            {"source", objc->fileName}, {"actualSourceBytesEqual", true},
            {"actualASTABI", std::move(objcABI)}, {"rawVariableLinkage", std::move(rawLinkage)},
            {"cppRawParameterCVR", rawParameterCVR(*cpp)}, {"objcRawParameterCVR", rawParameterCVR(*objc)},
            {"disposition", "PROVEN_EQUIVALENT_OBJC_AUTHORITY"},
            {"availability", availabilityDifference ? "INTRODUCED_ATTR_EXTERN_C_WRAPPER_EQUIVALENT_AT_BOUND_TARGET" : "EXACT"},
            {"objcIntroducedIn", objc->introducedIn.toString()}, {"cppIntroducedIn", cpp->introducedIn.toString()}});
    }

public:
    std::list<Meta::Meta*> merge(const std::list<Meta::Meta*>& cpp, const std::list<Meta::Meta*>& objc) {
        std::map<std::string, Meta::Meta*> canonical;
        for (auto* meta : objc) {
            auto insertion = canonical.emplace(entityKey(*meta), meta);
            if (!insertion.second && insertion.first->second != meta)
                throw std::runtime_error("Conflicting actual ObjC global identity");
        }
        for (auto* meta : cpp) {
            auto found = canonical.find(entityKey(*meta));
            if (found == canonical.end()) canonical.emplace(entityKey(*meta), meta);
            else duplicate(meta, found->second);
        }
        std::list<Meta::Meta*> result;
        std::map<std::string, Meta::Meta*> exports;
        for (auto& item : canonical) {
            auto* meta = item.second;
            const auto exportKey = meta->module->getTopLevelModule()->getFullModuleName() + "\n" + meta->jsName;
            if (!exports.emplace(exportKey, meta).second)
                throw std::runtime_error("Dual-grammar unresolved global export/owner collision");
            result.push_back(meta);
        }
        ModelGraph graph(replacements);
        for (auto* meta : result) graph.visit(meta);
        retained = graph.retainedMetas();
        graphMetas = graph.retainedMetaCount(); graphTypes = graph.retainedTypeCount();
        return result;
    }

    size_t graphMetas = 0;
    size_t graphTypes = 0;
    const llvm::json::Array& duplicateProofs() const { return proofs; }
    const std::set<Meta::Meta*>& retainedMetas() const { return retained; }
};

} // namespace HanlinDual
