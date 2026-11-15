#pragma once

// Compare freshly created models and their actual AST ABI. YAML is used only
// as an in-memory view through the original traits, never as an imported model.
#include "Yaml/MetaYamlTraits.h"
#include <clang/AST/ASTContext.h>
#include <clang/AST/RecordLayout.h>
#include <clang/AST/DeclCXX.h>
#include <clang/AST/DeclObjC.h>
#include <clang/AST/Mangle.h>
#include <llvm/Support/JSON.h>
#include <llvm/Support/SourceMgr.h>
#include <llvm/Support/YAMLParser.h>
#include <llvm/Support/raw_ostream.h>
#include <set>
#include <functional>

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

template<class T> inline llvm::json::Value actualValue(T* meta) {
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

inline llvm::json::Value modelValue(Meta::Meta* meta) { return actualValue(meta); }

inline llvm::json::Object typeABI(clang::ASTContext& context, clang::QualType type, unsigned depth = 0) {
    if (type.isNull()) throw std::runtime_error("Missing ABI type");
    if (depth > 64) throw std::runtime_error("Nested by-value ABI proof depth exceeded");
    if (type->isVoidType()) return llvm::json::Object{{"void", true}};
    if (const auto* array = context.getAsIncompleteArrayType(type))
        return llvm::json::Object{{"incompleteArrayElement", llvm::json::Value(typeABI(context, array->getElementType(), depth + 1))}};
    if (type->isIncompleteType() || type->isFunctionType() || type->isDependentType())
        throw std::runtime_error("Unproven incomplete/function/dependent ABI type: " + type.getAsString() + " [" + type->getTypeClassName() + "]");
    const auto info = context.getTypeInfo(type);
    llvm::json::Object result{{"widthBits", static_cast<int64_t>(info.Width)},
        {"alignmentBits", static_cast<int64_t>(info.Align)},
        {"addressSpace", static_cast<int64_t>(type.getAddressSpace())},
        {"qualifiersCVR", static_cast<int64_t>(type.getCVRQualifiers())},
        {"signedIntegerOrEnum", type->isSignedIntegerOrEnumerationType()},
        {"unsignedIntegerOrEnum", type->isUnsignedIntegerOrEnumerationType()},
        {"pointer", type->isPointerType() || type->isObjCObjectPointerType() || type->isBlockPointerType()}};
    if (const auto* array = context.getAsConstantArrayType(type)) {
        llvm::SmallString<32> count;
        array->getSize().toString(count, 10, false);
        result["arrayCount"] = count.str().str();
        result["arrayElement"] = typeABI(context, array->getElementType(), depth + 1);
    }
    if (type->isPointerType() || type->isObjCObjectPointerType() || type->isBlockPointerType()) {
        const auto pointee = type->getPointeeType();
        result["pointeeAddressSpace"] = static_cast<int64_t>(pointee.getAddressSpace());
        result["pointeeQualifiersCVR"] = static_cast<int64_t>(pointee.getCVRQualifiers());
        if (const auto* function = pointee->getAs<clang::FunctionType>()) {
            llvm::json::Array signature;
            signature.push_back(typeABI(context, function->getReturnType(), depth + 1));
            bool variadic = false;
            if (const auto* prototype = llvm::dyn_cast<clang::FunctionProtoType>(function)) {
                for (const auto& argument : prototype->param_types())
                    signature.push_back(typeABI(context, context.getCanonicalParamType(argument), depth + 1));
                variadic = prototype->isVariadic();
            }
            // Original TypeFactory::createFromFunctionNoProtoType explicitly
            // encodes the return type only; do not invent extra parameters.
            result["callableSignature"] = std::move(signature);
            result["callableConvention"] = static_cast<int64_t>(function->getCallConv());
            result["callableVariadic"] = variadic;
        }
    }
    if (const auto* recordType = type->getAs<clang::RecordType>()) {
        const auto* record = recordType->getDecl()->getDefinition();
        if (!record) throw std::runtime_error("Nested by-value record has no actual definition");
        const auto& layout = context.getASTRecordLayout(record);
        llvm::json::Array fields;
        unsigned index = 0;
        for (const auto* field : record->fields()) {
            auto nested = typeABI(context, field->getType(), depth + 1);
            nested["name"] = field->getNameAsString();
            nested["offsetBits"] = static_cast<int64_t>(layout.getFieldOffset(index++));
            nested["bitField"] = field->isBitField();
            if (field->isBitField()) nested["bitWidth"] = static_cast<int64_t>(field->getBitWidthValue());
            fields.push_back(llvm::json::Value(std::move(nested)));
        }
        result["recordFields"] = std::move(fields);
    }
    return result;
}

inline llvm::json::Array rawParameterCVR(const Meta::Meta& meta) {
    llvm::json::Array qualifiers;
    const auto append = [&](const auto* declaration) {
        for (const auto* parameter : declaration->parameters())
            qualifiers.push_back(static_cast<int64_t>(parameter->getType().getCVRQualifiers()));
    };
    if (const auto* function = clang::dyn_cast<clang::FunctionDecl>(meta.declaration)) append(function);
    else if (const auto* method = clang::dyn_cast<clang::ObjCMethodDecl>(meta.declaration)) append(method);
    return qualifiers;
}

inline llvm::json::Object externalBinding(const clang::NamedDecl& variable) {
    std::unique_ptr<clang::MangleContext> mangler(variable.getASTContext().createMangleContext());
    std::string symbol;
    llvm::raw_string_ostream output(symbol);
    if (mangler->shouldMangleDeclName(&variable)) mangler->mangleName(clang::GlobalDecl(&variable), output);
    else output << variable.getName();
    output.flush();
    if (symbol.empty()) throw std::runtime_error("External declaration has no actual Clang symbol name");
    return llvm::json::Object{{"clangSymbolBeforeTargetPrefix", symbol},
        {"formalLinkage", static_cast<int64_t>(variable.getFormalLinkage())},
        {"visibility", static_cast<int64_t>(variable.getVisibility())}};
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
            signature.push_back(llvm::json::Value(typeABI(context, context.getCanonicalParamType(parameter->getType()))));
        result["signature"] = std::move(signature);
        result["parameterTypeRule"] = "ASTContext.getCanonicalParamType";
        result["variadic"] = function->isVariadic();
        if (function->hasExternalFormalLinkage()) result["externalBinding"] = externalBinding(*function);
        else result["languageLinkage"] = static_cast<int64_t>(function->getLanguageLinkage());
        if (const auto* callable = function->getType()->getAs<clang::FunctionType>())
            result["callingConvention"] = static_cast<int64_t>(callable->getCallConv());
        else throw std::runtime_error("Actual declaration has no function type");
    } else if (const auto* method = clang::dyn_cast<clang::ObjCMethodDecl>(decl)) {
        llvm::json::Array signature;
        signature.push_back(llvm::json::Value(typeABI(context, method->getReturnType())));
        for (const auto* parameter : method->parameters())
            signature.push_back(llvm::json::Value(typeABI(context, context.getCanonicalParamType(parameter->getType()))));
        result["signature"] = std::move(signature);
        result["parameterTypeRule"] = "ASTContext.getCanonicalParamType";
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
            if (field->isBitField()) abi["bitWidth"] = static_cast<int64_t>(field->getBitWidthValue());
            fields.push_back(llvm::json::Value(std::move(abi)));
        }
        result["fields"] = std::move(fields);
    } else if (const auto* variable = clang::dyn_cast<clang::VarDecl>(decl)) {
        const auto valueType = variable->getType();
        const auto* record = valueType->getAs<clang::RecordType>();
        if (valueType->isIncompleteType() && record) {
            const auto& model = meta.as<Meta::VarMeta>();
            if (!variable->hasExternalFormalLinkage() || static_cast<int>(variable->getTLSKind()) != 0 ||
                record->getDecl()->getDefinition() || model.hasValue || !model.signature ||
                !model.signature->stripNullability()->is(Meta::TypeType::TypeVoid))
                throw std::runtime_error("Unproven incomplete variable storage contract");
            const auto tag = record->getDecl()->getQualifiedNameAsString();
            if (tag.empty()) throw std::runtime_error("Opaque external object has no actual type identity");
            // The SDK exports only this object's symbol/address, never its
            // layout or a by-value payload. Preserve the original Void model;
            // do not invent a size/alignment or allow this rule for parameters.
            result["type"] = llvm::json::Object{{"storageContract", "EXTERNAL_OPAQUE_OBJECT_NO_BY_VALUE_ENCODING"},
                {"sourceTypeTag", tag}, {"tagKind", static_cast<int64_t>(record->getDecl()->getTagKind())},
                {"addressSpace", static_cast<int64_t>(valueType.getAddressSpace())},
                {"qualifiersCVR", static_cast<int64_t>(valueType.getCVRQualifiers())},
                {"metadataEncoding", "Void"}, {"layout", "NOT_DECLARED"}};
        } else {
            result["type"] = llvm::json::Value(typeABI(context, valueType));
        }
        if (variable->hasExternalFormalLinkage()) {
            // Global C++ variables can have C++ language linkage while Clang
            // gives them exactly the same external symbol as the C spelling.
            // Prove the actual target-bound name, formal linkage and visibility;
            // the raw language linkage remains in the duplicate proof receipt.
            result["externalBinding"] = externalBinding(*variable);
        } else {
            result["languageLinkage"] = static_cast<int64_t>(variable->getLanguageLinkage());
        }
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

inline llvm::json::Array rawCallablePrototypes(const Meta::Meta& meta) {
    llvm::json::Array facts;
    std::function<void(clang::QualType, const std::string&, unsigned)> visit;
    visit = [&](clang::QualType type, const std::string& path, unsigned depth) {
        if (type.isNull()) return;
        if (depth > 64) throw std::runtime_error("Raw callable prototype evidence depth exceeded");
        if (const auto* function = type->getAs<clang::FunctionType>()) {
            const auto* prototype = llvm::dyn_cast<clang::FunctionProtoType>(function);
            llvm::json::Object fact{{"path", path}, {"hasPrototype", prototype != nullptr},
                {"callingConvention", static_cast<int64_t>(function->getCallConv())},
                {"originalFactorySignatureEntries", static_cast<int64_t>(prototype ? prototype->getNumParams() + 1 : 1)}};
            fact["sourceDeclaredParameterCount"] = prototype ? llvm::json::Value(static_cast<int64_t>(prototype->getNumParams())) : llvm::json::Value(nullptr);
            facts.push_back(std::move(fact));
            visit(function->getReturnType(), path + ".return", depth + 1);
            if (prototype) {
                unsigned index = 0;
                for (const auto& argument : prototype->param_types())
                    visit(argument, path + ".parameter[" + std::to_string(index++) + "]", depth + 1);
            }
        } else if (type->isPointerType() || type->isBlockPointerType()) {
            // Match ABI traversal: ordinary pointee records are not by-value.
            if (type->getPointeeType()->isFunctionType()) visit(type->getPointeeType(), path + ".pointee", depth + 1);
        } else if (const auto* array = type->getAsArrayTypeUnsafe()) {
            visit(array->getElementType(), path + ".element", depth + 1);
        } else if (const auto* record = type->getAs<clang::RecordType>()) {
            if (const auto* definition = record->getDecl()->getDefinition()) {
                unsigned index = 0;
                for (const auto* field : definition->fields())
                    visit(field->getType(), path + ".field[" + std::to_string(index++) + "]", depth + 1);
            }
        }
    };
    const auto* declaration = meta.declaration;
    if (const auto* function = clang::dyn_cast<clang::FunctionDecl>(declaration)) visit(function->getType(), "function", 0);
    else if (const auto* method = clang::dyn_cast<clang::ObjCMethodDecl>(declaration)) {
        visit(method->getReturnType(), "method.return", 0);
        unsigned index = 0;
        for (const auto* parameter : method->parameters()) visit(parameter->getType(), "method.parameter[" + std::to_string(index++) + "]", 0);
    } else if (const auto* property = clang::dyn_cast<clang::ObjCPropertyDecl>(declaration)) visit(property->getType(), "property", 0);
    else if (const auto* variable = clang::dyn_cast<clang::VarDecl>(declaration)) visit(variable->getType(), "variable", 0);
    else if (const auto* record = clang::dyn_cast<clang::RecordDecl>(declaration)) visit(record->getASTContext().getRecordType(record), "record", 0);
    else if (const auto* interface = clang::dyn_cast<clang::ObjCInterfaceDecl>(declaration)) {
        unsigned index = 0;
        for (const auto* field : interface->ivars()) visit(field->getType(), "ivar[" + std::to_string(index++) + "]", 0);
    }
    return facts;
}

inline bool sameABIExceptExternalSymbol(const llvm::json::Value& left, const llvm::json::Value& right) {
    const auto* a = left.getAsObject(); const auto* b = right.getAsObject();
    if (!a || !b || !a->getObject("externalBinding") || !b->getObject("externalBinding")) return false;
    auto bindingA = llvm::json::Object(*a->getObject("externalBinding"));
    auto bindingB = llvm::json::Object(*b->getObject("externalBinding"));
    bindingA.erase("clangSymbolBeforeTargetPrefix"); bindingB.erase("clangSymbolBeforeTargetPrefix");
    if (llvm::json::Value(std::move(bindingA)) != llvm::json::Value(std::move(bindingB))) return false;
    auto shapeA = llvm::json::Object(*a); auto shapeB = llvm::json::Object(*b);
    shapeA.erase("externalBinding"); shapeB.erase("externalBinding");
    return llvm::json::Value(std::move(shapeA)) == llvm::json::Value(std::move(shapeB));
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
