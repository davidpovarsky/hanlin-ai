// Compile the exact adapted producer into a focused native test executable.
// This rename changes only this host test's entry point, never SDK feature macros.
#define main hanlin_original_metadata_entry
#include "../main.cpp"
#undef main
#include "Pipeline.h"
#include "OptionsMacro.h"
#include <map>

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
        llvm::json::Array observedArguments;
        for (const auto& argument : cppArguments) observedArguments.push_back(argument);
        receipt["cppArguments"] = std::move(observedArguments);
        std::string whitelistFile, blacklistFile;
        Meta::ModulesBlacklist blacklist(whitelistFile, blacklistFile);
        HanlinDual::Pipeline pipeline(hanlinRead(root + "/full.h"), cppArguments,
            hanlinRead(root + "/objc.h"), objcArguments, blacklist, llvm::vfs::getRealFileSystem());
        auto& cpp = pipeline.cpp;
        stage = "merge";
        auto& models = pipeline.merge();
        receipt["mergeProof"] = pipeline.proofReceipt();
        const auto* coverage = receipt.getObject("mergeProof")->getObject("originalAModelCoverage");
        if (!coverage || coverage->getString("status") != "COMPLETE" ||
            coverage->getInteger("unmappedModels") != 0 ||
            coverage->getInteger("originalGraphModels") !=
                coverage->getInteger("retainedOriginalModels").value_or(-1) + coverage->getInteger("mappedWithProof").value_or(-1) ||
            !coverage->getInteger("retainedOriginalModels").value_or(0) || !coverage->getInteger("mappedWithProof").value_or(0))
            throw std::runtime_error("Every actual original-A graph model was not explicitly preserved or proven mapped");
        const auto graphLifetime = pipeline.lifetime();
        if (!graphLifetime.getInteger("cppOwnedModels").value_or(0) ||
            !graphLifetime.getInteger("objcOwnedModels").value_or(0))
            throw std::runtime_error("Both actual AST lifetimes were not exercised");
        if (expectation != "pass") throw std::runtime_error("Expected conflict was not rejected");

        Meta::StructMeta* shared = nullptr;
        Meta::FunctionMeta* provider = nullptr;
        Meta::FunctionMeta* recordAliases = nullptr;
        bool lateNamed = false, inlineAlias = false, lateAliasExported = false;
        Meta::InterfaceMeta* repeatedConsumer = nullptr;
        Meta::InterfaceMeta* sharedObject = nullptr;
        bool onlyCRecord = false, onlyCFunction = false;
        for (auto* meta : models) {
            if (meta->name == "HanlinDualShared") shared = &meta->as<Meta::StructMeta>();
            if (meta->name == "HanlinDualProvider") provider = &meta->as<Meta::FunctionMeta>();
            if (meta->name == "HanlinDualRecordAliases") recordAliases = &meta->as<Meta::FunctionMeta>();
            if (meta->name == "HanlinDualObject") sharedObject = &meta->as<Meta::InterfaceMeta>();
            if (meta->name == "HanlinDualRepeatedConsumer") repeatedConsumer = &meta->as<Meta::InterfaceMeta>();
            lateNamed |= meta->name == "HanlinDualLateNamed";
            inlineAlias |= meta->name == "HanlinDualInlineAlias";
            lateAliasExported |= meta->name == "HanlinDualLaterAlias";
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
        if (!repeatedConsumer || repeatedConsumer->protocols.size() != 2 ||
            repeatedConsumer->protocols[0] != repeatedConsumer->protocols[1] ||
            repeatedConsumer->protocols[0]->name != "HanlinDualRepeatedProtocol")
            throw std::runtime_error("Original same-object protocol multiplicity was not preserved");
        receipt["sameProtocolObjectMultiplicityPreserved"] = true;
        if (!sharedObject || sharedObject->protocols.size() != 1 ||
            sharedObject->protocols[0] != repeatedConsumer->protocols[0] ||
            &sharedObject->protocols[0]->declaration->getASTContext() != &pipeline.objc.context())
            throw std::runtime_error("CPP-only duplicate conformance did not reach the canonical C protocol object");
        receipt["cppAddedProtocolRoutedToCanonicalCObject"] = true;
        if (!recordAliases || !lateNamed || !inlineAlias || lateAliasExported)
            throw std::runtime_error("Actual inline/standalone record identity was not preserved");
        const std::vector<std::string> recordNames{"HanlinDualLateNamed", "HanlinDualLateNamed", "HanlinDualInlineAlias"};
        for (size_t index = 0; index < recordNames.size(); ++index) {
            auto* encoding = recordAliases->signature.at(index + 1)->stripNullability();
            if (!encoding->is(Meta::TypeType::TypePointer)) throw std::runtime_error("Actual record alias parameter is not a pointer");
            auto* pointed = encoding->as<Meta::PointerType>().innerType;
            if (!pointed->is(Meta::TypeType::TypeStruct) || pointed->as<Meta::StructType>().structMeta->name != recordNames[index])
                throw std::runtime_error("Actual record alias signature identity is inconsistent");
        }
        receipt["actualRecordAliasIdentity"] = true;
        // Exercise original factories, not a model projection: a lookalike
        // vendor macro stays primitive in both retained ASTs, while the actual
        // NS_OPTIONS/CF_OPTIONS ancestry keeps the existing named Enum model.
        const std::map<std::string, std::string> vendorConstants{
            {"HanlinDualVendorSuccess", "0"}, {"HanlinDualVendorFailure", "-21766"},
            {"HanlinDualVendorNoFlags", "0"}, {"HanlinDualVendorHighFlag", "2147483648"}};
        for (auto* unit : {&pipeline.cpp, &pipeline.objc}) {
            bool vendorFunction = false;
            std::set<std::string> constants, options;
            for (auto* meta : unit->models()) {
                if ((meta->name == "HanlinDualVendorError" || meta->name == "HanlinDualVendorFlags") &&
                    meta->type == Meta::MetaType::Enum)
                    throw std::runtime_error("Vendor lookalike was incorrectly named as an options enum");
                if (meta->name == "HanlinDualVendorCall") {
                    auto& function = meta->as<Meta::FunctionMeta>();
                    const auto* declaration = clang::dyn_cast<clang::FunctionDecl>(meta->declaration);
                    if (!declaration || !declaration->getReturnType()->isIntegerType() ||
                        declaration->getReturnType()->isEnumeralType() || declaration->getNumParams() != 1 ||
                        !declaration->getParamDecl(0)->getType()->isIntegerType() ||
                        declaration->getParamDecl(0)->getType()->isEnumeralType() || function.signature.size() != 2 ||
                        !function.signature[0]->stripNullability()->is(Meta::TypeType::TypeLong) ||
                        !function.signature[1]->stripNullability()->is(Meta::TypeType::TypeUInt))
                        throw std::runtime_error("Actual vendor typedef/primitive signature was not preserved");
                    vendorFunction = true;
                }
                const auto expectedConstant = vendorConstants.find(meta->name);
                if (expectedConstant != vendorConstants.end()) {
                    if (meta->type != Meta::MetaType::EnumConstant ||
                        meta->as<Meta::EnumConstantMeta>().value != expectedConstant->second ||
                        meta->as<Meta::EnumConstantMeta>().isScoped)
                        throw std::runtime_error("Original unscoped vendor constant/value was not preserved");
                    constants.insert(meta->name);
                }
                if (meta->name == "HanlinDualOptionsCall" || meta->name == "HanlinDualCFOptionsCall") {
                    auto& function = meta->as<Meta::FunctionMeta>();
                    const std::string expectedEnum = meta->name == "HanlinDualOptionsCall" ?
                        "HanlinDualActualOptions" : "HanlinDualActualCFOptions";
                    if (function.signature.size() != 2)
                        throw std::runtime_error("Actual options signature was not collected");
                    for (auto* entry : function.signature) {
                        auto* type = entry->stripNullability();
                        if (!type->is(Meta::TypeType::TypeEnum) ||
                            type->as<Meta::EnumType>().enumMeta->name != expectedEnum ||
                            !type->as<Meta::EnumType>().underlyingType->is(Meta::TypeType::TypeUInt))
                            throw std::runtime_error("Actual NS_OPTIONS/CF_OPTIONS model was not preserved");
                    }
                    options.insert(meta->name);
                }
            }
            if (!vendorFunction || constants.size() != vendorConstants.size() || options.size() != 2)
                throw std::runtime_error("Actual macro ancestry controls did not execute in both grammars");
        }
        receipt["vendorMacroPrimitiveAndConstantsPreserved"] = true;
        receipt["originalOptionsMacroModelsPreserved"] = true;
        // Derived adversarial ABI objects start from a real retained Clang
        // declaration. Changing only its symbol may be considered later;
        // changing visibility or formal linkage can never qualify.
        for (auto* meta : cpp.models()) if (meta->name == "HanlinDualSharedFunction") {
            auto actual = HanlinDual::declarationABI(*meta);
            auto changed = llvm::json::Value(llvm::json::Object(*actual.getAsObject()));
            auto* binding = changed.getAsObject()->getObject("externalBinding");
            if (!binding) throw std::runtime_error("Actual fixture has no external binding");
            (*binding)["clangSymbolBeforeTargetPrefix"] = "__hanlin_derived_different_binding";
            if (!HanlinDual::sameABIExceptExternalSymbol(actual, changed)) throw std::runtime_error("Name-only ABI counterexample was not recognized");
            (*binding)["visibility"] = -123;
            if (HanlinDual::sameABIExceptExternalSymbol(actual, changed)) throw std::runtime_error("Changed visibility passed SDK binding guard");
            (*binding)["visibility"] = actual.getAsObject()->getObject("externalBinding")->getInteger("visibility").value_or(-999);
            (*binding)["formalLinkage"] = -123;
            if (HanlinDual::sameABIExceptExternalSymbol(actual, changed)) throw std::runtime_error("Changed formal linkage passed SDK binding guard");
            receipt["bindingNameOnlyGuardCounterexamples"] = true;
        }
        if (receipt.getBoolean("bindingNameOnlyGuardCounterexamples") != true)
            throw std::runtime_error("Actual binding guard counterexamples did not execute");
        cpp.producer().hanlinFactory().validate(provider->signature.at(1));
        receipt["crossFactoryTypeValidation"] = true;
        if (hanlinWriterEntries) throw std::runtime_error("An output writer ran before both parses and merge succeeded");
        stage = "serialization";
        cla_outputBinFile.setValue(output);
        cla_outputYamlFolder.setValue(output + ".yaml");
        cla_outputDtsFolder.setValue(output + ".types");
        pipeline.emit();
        receipt["lifetime"] = pipeline.lifetime();
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
