#pragma once

// Compare freshly created models and their actual AST ABI. YAML is used only
// as an in-memory view through the original traits, never as an imported model.
#include "Yaml/MetaYamlTraits.h"
#include <clang/AST/ASTContext.h>
#include <clang/AST/RecordLayout.h>
#include <clang/AST/DeclCXX.h>
#include <clang/AST/DeclObjC.h>
#include <llvm/Support/JSON.h>
#include <llvm/Support/SourceMgr.h>
#include <llvm/Support/YAMLParser.h>
#include <llvm/Support/raw_ostream.h>
#include <set>

namespace HanlinDual {

inline std::string moduleName(const Meta::Meta& meta) {
    if (!meta.module) throw std::runtime_error("Model has no canonical module owner");
    return meta.module->getFullModuleName();
}

inline std::string entityKey(const Meta::Meta& meta) {
    return moduleName(meta) + "\n" + std::to_string(meta.type) + "\n" + meta.name + "\n" + meta.jsName;
}

inline llvm::json::Value yamlValue(llvm::yaml::Node* node) {
    if (auto* mapping = llvm::dyn_cast_or_null<llvm::yaml::MappingNode>(node)) {
        llvm::json::Object object;
        for (auto& entry : *mapping) {
            auto* key = llvm::dyn_cast_or_null<llvm::yaml::ScalarNode>(entry.getKey());
            if (!key) throw std::runtime_error("Non-scalar model field");
            llvm::SmallString<64> storage;
            std::string name = key->getValue(storage).str();
            if (object.get(name)) throw std::runtime_error("Duplicate model field");
            object[name] = yamlValue(entry.getValue());
        }
        return llvm::json::Value(std::move(object));
    }
    if (auto* sequence = llvm::dyn_cast_or_null<llvm::yaml::SequenceNode>(node)) {
        llvm::json::Array array;
        for (auto& item : *sequence) array.push_back(yamlValue(&item));
        return llvm::json::Value(std::move(array));
    }
    if (auto* scalar = llvm::dyn_cast_or_null<llvm::yaml::ScalarNode>(node)) {
        llvm::SmallString<128> storage;
        return scalar->getValue(storage).str();
    }
    throw std::runtime_error("Unknown/null node in actual model representation");
}

inline llvm::json::Value modelValue(Meta::Meta* meta) {
    std::string bytes;
    llvm::raw_string_ostream stream(bytes);
    { llvm::yaml::Output output(stream); output << meta; }
    stream.flush();
    llvm::SourceMgr sources;
    llvm::yaml::Stream documents(bytes, sources);
    auto first = documents.begin();
    if (first == documents.end()) throw std::runtime_error("Empty actual metadata model");
    auto value = yamlValue(first->getRoot());
    ++first;
    if (first != documents.end() || documents.failed()) throw std::runtime_error("Invalid actual metadata model");
    return value;
}

inline llvm::json::Object typeABI(clang::ASTContext& context, clang::QualType type) {
    if (type.isNull()) throw std::runtime_error("Missing ABI type");
    if (type->isVoidType()) return llvm::json::Object{{"void", true}};
    if (const auto* array = context.getAsIncompleteArrayType(type))
        return llvm::json::Object{{"incompleteArrayElement", llvm::json::Value(typeABI(context, array->getElementType()))}};
    if (type->isIncompleteType() || type->isFunctionType() || type->isDependentType())
        throw std::runtime_error("Unproven incomplete/function/dependent ABI type");
    const auto info = context.getTypeInfo(type);
    llvm::json::Object result{{"widthBits", static_cast<int64_t>(info.Width)},
        {"alignmentBits", static_cast<int64_t>(info.Align)},
        {"signedIntegerOrEnum", type->isSignedIntegerOrEnumerationType()},
        {"unsignedIntegerOrEnum", type->isUnsignedIntegerOrEnumerationType()},
        {"pointer", type->isPointerType() || type->isObjCObjectPointerType() || type->isBlockPointerType()}};
    return result;
}

inline llvm::json::Value declarationABI(const Meta::Meta& meta) {
    if (!meta.declaration) throw std::runtime_error("Model has no actual AST declaration");
    const auto* decl = meta.declaration;
    auto& context = decl->getASTContext();
    llvm::json::Object result;
    if (const auto* function = clang::dyn_cast<clang::FunctionDecl>(decl)) {
        llvm::json::Array signature;
        signature.push_back(llvm::json::Value(typeABI(context, function->getReturnType())));
        for (const auto* parameter : function->parameters())
            signature.push_back(llvm::json::Value(typeABI(context, parameter->getType())));
        result["signature"] = std::move(signature);
        result["variadic"] = function->isVariadic();
        result["languageLinkage"] = static_cast<int64_t>(function->getLanguageLinkage());
        if (const auto* prototype = function->getType()->getAs<clang::FunctionProtoType>())
            result["callingConvention"] = static_cast<int64_t>(prototype->getCallConv());
    } else if (const auto* method = clang::dyn_cast<clang::ObjCMethodDecl>(decl)) {
        llvm::json::Array signature;
        signature.push_back(llvm::json::Value(typeABI(context, method->getReturnType())));
        for (const auto* parameter : method->parameters())
            signature.push_back(llvm::json::Value(typeABI(context, parameter->getType())));
        result["signature"] = std::move(signature);
        result["variadic"] = method->isVariadic();
        result["instance"] = method->isInstanceMethod();
        result["selector"] = method->getSelector().getAsString();
    } else if (const auto* record = clang::dyn_cast<clang::RecordDecl>(decl)) {
        record = record->getDefinition();
        if (!record) throw std::runtime_error("Forward record has no ABI definition");
        const auto& layout = context.getASTRecordLayout(record);
        result["sizeBytes"] = layout.getSize().getQuantity();
        result["alignmentBytes"] = layout.getAlignment().getQuantity();
        llvm::json::Array fields;
        unsigned index = 0;
        for (const auto* field : record->fields()) {
            auto abi = typeABI(context, field->getType());
            abi["name"] = field->getNameAsString();
            abi["offsetBits"] = static_cast<int64_t>(layout.getFieldOffset(index++));
            abi["bitField"] = field->isBitField();
            if (field->isBitField()) abi["bitWidth"] = static_cast<int64_t>(field->getBitWidthValue(context));
            fields.push_back(llvm::json::Value(std::move(abi)));
        }
        result["fields"] = std::move(fields);
    } else if (const auto* variable = clang::dyn_cast<clang::VarDecl>(decl)) {
        result["type"] = llvm::json::Value(typeABI(context, variable->getType()));
        result["languageLinkage"] = static_cast<int64_t>(variable->getLanguageLinkage());
        result["threadLocal"] = static_cast<int64_t>(variable->getTLSKind());
    } else if (const auto* enumeration = clang::dyn_cast<clang::EnumDecl>(decl)) {
        result["underlyingType"] = llvm::json::Value(typeABI(context, enumeration->getIntegerType()));
    } else if (const auto* property = clang::dyn_cast<clang::ObjCPropertyDecl>(decl)) {
        result["type"] = llvm::json::Value(typeABI(context, property->getType()));
        result["attributes"] = static_cast<int64_t>(property->getPropertyAttributes());
    } else if (const auto* interface = clang::dyn_cast<clang::ObjCInterfaceDecl>(decl)) {
        interface = interface->getDefinition();
        if (!interface) throw std::runtime_error("Forward interface has no ABI definition");
        const auto& layout = context.getASTObjCInterfaceLayout(interface);
        result["sizeBytes"] = layout.getSize().getQuantity();
        result["alignmentBytes"] = layout.getAlignment().getQuantity();
        llvm::json::Array ivars;
        unsigned index = 0;
        for (const auto* ivar : interface->ivars()) {
            auto abi = typeABI(context, ivar->getType());
            abi["name"] = ivar->getNameAsString();
            abi["offsetBits"] = static_cast<int64_t>(layout.getFieldOffset(index++));
            ivars.push_back(llvm::json::Value(std::move(abi)));
        }
        result["ivars"] = std::move(ivars);
    } else if (clang::isa<clang::ObjCProtocolDecl>(decl) ||
               clang::isa<clang::ObjCCategoryDecl>(decl) || clang::isa<clang::EnumConstantDecl>(decl)) {
        // Their members/values are checked from original model traits; every
        // method/property/record also receives its own actual ABI proof.
        result["kind"] = static_cast<int64_t>(meta.type);
    } else {
        throw std::runtime_error("Unsupported AST declaration in duplicate ABI proof");
    }
    return llvm::json::Value(std::move(result));
}

inline bool sameSourceOwner(const Meta::Meta& left, const Meta::Meta& right) {
    if (moduleName(left) != moduleName(right) || left.name != right.name || left.type != right.type ||
        left.fileName != right.fileName || !left.declaration || !right.declaration) return false;
    auto& lsm = left.declaration->getASTContext().getSourceManager();
    auto& rsm = right.declaration->getASTContext().getSourceManager();
    const auto lloc = lsm.getExpansionLoc(left.declaration->getLocation());
    const auto rloc = rsm.getExpansionLoc(right.declaration->getLocation());
    return lsm.getSpellingLineNumber(lloc) == rsm.getSpellingLineNumber(rloc) &&
           lsm.getSpellingColumnNumber(lloc) == rsm.getSpellingColumnNumber(rloc) &&
           lsm.getBufferData(lsm.getFileID(lloc)) == rsm.getBufferData(rsm.getFileID(rloc));
}

} // namespace HanlinDual
