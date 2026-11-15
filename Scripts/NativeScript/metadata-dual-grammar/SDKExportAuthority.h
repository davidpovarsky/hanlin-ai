#pragma once
#include "SDKExportClosure.h"
#include <clang/AST/Attr.h>
#include <clang/Basic/TargetInfo.h>

namespace HanlinDual {

class SDKExportAuthority {
    std::unique_ptr<llvm::json::Value> evidence;
    const llvm::json::Object* fields;
    std::filesystem::path sdk;
    std::map<std::string, std::unique_ptr<SDKExportClosure>> closures;
public:
    SDKExportAuthority(const llvm::json::Object& request, const llvm::json::Object& actualCPP) {
        const auto path = request.getString("sdkExportEvidence");
        if (!path || path->empty()) throw std::runtime_error("Missing SDK export evidence");
        auto parsed = llvm::json::parse(hanlinRead(path->str()));
        if (!parsed) { llvm::consumeError(parsed.takeError()); throw std::runtime_error("Invalid SDK export evidence JSON"); }
        evidence = std::make_unique<llvm::json::Value>(std::move(*parsed));
        fields = evidence->getAsObject();
        if (!fields || fields->getInteger("schemaVersion") != 1 || fields->getString("status") != "STATIC_BINDING_PROOF" ||
            fields->getString("contextCompiler") != actualCPP.getString("compiler") ||
            !fields->getArray("fullArguments") || *fields->getArray("fullArguments") != *actualCPP.getArray("arguments") ||
            fields->getString("target") != actualCPP.getString("target"))
            throw std::runtime_error("SDK export evidence actual compiler/target/argv drift");
        sdk = std::filesystem::canonical(hanlinString(request, "sdkRoot"));
        if (std::filesystem::canonical(hanlinString(*fields, "sdkRoot")) != sdk)
            throw std::runtime_error("SDK export evidence root drift");
        verify();
    }

    void verify() const {
        const auto* inputs = fields->getArray("inputFiles");
        if (!inputs || inputs->empty()) throw std::runtime_error("SDK binding evidence dependency closure missing");
        for (const auto& item : *inputs) {
            const auto* file = item.getAsObject();
            if (!file || hanlinSHA(hanlinRead(hanlinString(*file, "path"))) != hanlinString(*file, "sha256"))
                throw std::runtime_error("SDK binding evidence physical input drift");
        }
        for (const auto& closure : closures) closure.second->verify();
    }

    std::optional<llvm::json::Object> resolve(const Meta::Meta& cpp, const Meta::Meta& objc,
                                            const llvm::json::Value& cppABI, const llvm::json::Value& objcABI) {
        const auto* a = clang::dyn_cast<clang::FunctionDecl>(cpp.declaration);
        const auto* b = clang::dyn_cast<clang::FunctionDecl>(objc.declaration);
        if (!a || !b || !a->hasExternalFormalLinkage() || !b->hasExternalFormalLinkage() ||
            !a->getDeclContext()->isTranslationUnit() || !b->getDeclContext()->isTranslationUnit() ||
            a->getLanguageLinkage() != clang::CXXLanguageLinkage || b->getLanguageLinkage() != clang::CLanguageLinkage ||
            a->hasAttr<clang::AsmLabelAttr>() || b->hasAttr<clang::AsmLabelAttr>() ||
            a->hasAttr<clang::AliasAttr>() || b->hasAttr<clang::AliasAttr>() || a->hasAttr<clang::IFuncAttr>() || b->hasAttr<clang::IFuncAttr>()) return std::nullopt;
        const auto publicRoot = sdk / "System/Library/Frameworks";
        const auto physical = std::filesystem::canonical(objc.fileName);
        const auto relative = physical.lexically_relative(publicRoot);
        if (relative.empty() || relative.is_absolute() || *relative.begin() == "..") return std::nullopt;
        auto part = relative.begin();
        const auto framework = part->string();
        if (!llvm::StringRef(framework).ends_with(".framework") || ++part == relative.end() || *part != "Headers") return std::nullopt;
        const auto name = framework.substr(0, framework.size() - std::string(".framework").size());
        if (objc.module->getTopLevelModule()->getFullModuleName() != name) return std::nullopt;
        const auto* functions = fields->getArray("functions");
        const llvm::json::Object* match = nullptr;
        if (!functions) throw std::runtime_error("SDK binding declaration proofs missing");
        for (const auto& item : *functions) {
            const auto* value = item.getAsObject();
            if (value && value->getString("name") == objc.name) {
                if (match) throw std::runtime_error("Ambiguous SDK binding declaration proof");
                match = value;
            }
        }
        if (!match) return std::nullopt; // Unproven declarations retain the fatal conflict.
        auto& source = b->getASTContext().getSourceManager();
        const auto location = source.getExpansionLoc(b->getLocation());
        if (std::filesystem::canonical(hanlinString(*match, "source")) != physical ||
            match->getString("sourceSHA256") != hanlinSHA(hanlinRead(physical.string())) ||
            match->getInteger("offset") != static_cast<int64_t>(source.getFileOffset(location)))
            throw std::runtime_error("SDK binding declaration physical identity drift");
        const auto* cBinding = objcABI.getAsObject()->getObject("externalBinding");
        const auto* cppBinding = cppABI.getAsObject()->getObject("externalBinding");
        if (!cBinding || !cppBinding || cBinding->getString("clangSymbolBeforeTargetPrefix") != objc.name ||
            match->getString("CBinding") != "_" + objc.name ||
            match->getString("CPPBinding") != "_" + hanlinString(*cppBinding, "clangSymbolBeforeTargetPrefix")) return std::nullopt;
        std::set<std::string> witnessed;
        const auto* proofs = match->getArray("proofs");
        if (!proofs || proofs->size() != 4) throw std::runtime_error("Four actual SDK compiler/link proofs required");
        for (const auto& item : *proofs) {
            const auto* proof = item.getAsObject();
            if (!proof) throw std::runtime_error("Invalid SDK compiler proof");
            const auto role = hanlinString(*proof, "role"), language = hanlinString(*proof, "language");
            if ((role != "lockedLLVM20" && role != "installedApple") ||
                (language != "objective-c" && language != "objective-c++") || !witnessed.insert(role + language).second ||
                !proof->getObject("AST") || proof->getObject("AST")->getInteger("exitCode") != 0 ||
                !proof->getObject("compile") || proof->getObject("compile")->getInteger("exitCode") != 0 ||
                !proof->getObject("link") || proof->getObject("link")->getInteger("exitCode") != (language == "objective-c" ? 0 : 1) ||
                proof->getString("mangledName") != match->getString(language == "objective-c" ? "CBinding" : "CPPBinding") ||
                hanlinSHA(hanlinRead(hanlinString(*proof, "compilerPath"))) != hanlinString(*proof, "compilerSHA256"))
                throw std::runtime_error("SDK actual compiler/link proof is incomplete or inconsistent");
        }
        const auto stub = publicRoot / framework / (name + ".tbd");
        auto& closure = closures[stub.string()];
        if (!closure) closure = std::make_unique<SDKExportClosure>(sdk, stub);
        const auto& triple = b->getASTContext().getTargetInfo().getTriple();
        llvm::MachO::Target target(triple);
        auto proof = closure->choose(target, hanlinString(*match, "CBinding"), hanlinString(*match, "CPPBinding"));
        proof["publicModelOwner"] = moduleName(objc);
        proof["source"] = physical.string();
        proof["sourceSHA256"] = hanlinString(*match, "sourceSHA256");
        proof["target"] = triple.str();
        proof["rawCPPExternalBinding"] = llvm::json::Object(*cppBinding);
        proof["rawCExternalBinding"] = llvm::json::Object(*cBinding);
        proof["compilerLinkEvidence"] = llvm::json::Object(*match);
        proof["bindingEquivalent"] = false;
        return proof;
    }
};

} // namespace HanlinDual
