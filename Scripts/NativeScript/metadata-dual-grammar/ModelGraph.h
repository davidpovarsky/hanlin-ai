#pragma once

// Reconnect actual metadata objects after duplicate proof. Both owning ASTs
// and both MetaFactories must outlive this traversal and serialization.
#include "Meta/MetaEntities.h"
#include <map>
#include <set>
#include <stdexcept>

namespace HanlinDual {

class ModelGraph {
    const std::map<Meta::Meta*, Meta::Meta*>& routes;
    std::set<Meta::Meta*> metas;
    std::set<Meta::Type*> types;

    template<class T> void reference(T*& value) {
        if (!value) return;
        Meta::Meta* current = value;
        std::set<Meta::Meta*> chain;
        for (;;) {
            auto found = routes.find(current);
            if (found == routes.end() || found->second == current) break;
            if (!chain.insert(current).second) throw std::runtime_error("Cyclic metadata canonical route");
            if (!found->second || found->second->type != current->type)
                throw std::runtime_error("Metadata canonical route changes entity kind");
            current = found->second;
        }
        value = static_cast<T*>(current);
        visit(current);
    }

    template<class T> void references(std::vector<T*>& values) {
        for (auto*& value : values) reference(value);
    }

    void signature(std::vector<Meta::Type*>& values) {
        for (auto* value : values) type(value);
    }

    void fields(std::vector<Meta::RecordField>& values) {
        for (auto& field : values) type(field.encoding);
    }

public:
    explicit ModelGraph(const std::map<Meta::Meta*, Meta::Meta*>& replacements) : routes(replacements) {}

    void visit(Meta::Meta* value) {
        if (!value || !metas.insert(value).second) return;
        switch (value->type) {
        case Meta::MetaType::Interface:
            reference(value->as<Meta::InterfaceMeta>().base);
            [[fallthrough]];
        case Meta::MetaType::Protocol:
        case Meta::MetaType::Category: {
            auto& base = value->as<Meta::BaseClassMeta>();
            references(base.instanceMethods); references(base.staticMethods);
            references(base.instanceProperties); references(base.staticProperties);
            references(base.protocols);
            if (value->is(Meta::MetaType::Category)) reference(value->as<Meta::CategoryMeta>().extendedInterface);
            break;
        }
        case Meta::MetaType::Method: signature(value->as<Meta::MethodMeta>().signature); break;
        case Meta::MetaType::Function: signature(value->as<Meta::FunctionMeta>().signature); break;
        case Meta::MetaType::Property: {
            auto& property = value->as<Meta::PropertyMeta>();
            reference(property.getter); reference(property.setter); break;
        }
        case Meta::MetaType::Struct:
        case Meta::MetaType::Union: fields(value->as<Meta::RecordMeta>().fields); break;
        case Meta::MetaType::Var: type(value->as<Meta::VarMeta>().signature); break;
        case Meta::MetaType::Enum:
        case Meta::MetaType::EnumConstant: break;
        default: throw std::runtime_error("Unknown entity in dual-grammar metadata graph");
        }
    }

    void type(Meta::Type* value) {
        if (!value || !types.insert(value).second) return;
        switch (value->getType()) {
        case Meta::TypeType::TypeClass: references(value->as<Meta::ClassType>().protocols); break;
        case Meta::TypeType::TypeId: references(value->as<Meta::IdType>().protocols); break;
        case Meta::TypeType::TypeInterface: {
            auto& interface = value->as<Meta::InterfaceType>();
            reference(interface.interface); references(interface.protocols); signature(interface.typeArguments); break;
        }
        case Meta::TypeType::TypeBridgedInterface: reference(value->as<Meta::BridgedInterfaceType>().bridgedInterface); break;
        case Meta::TypeType::TypeStruct: reference(value->as<Meta::StructType>().structMeta); break;
        case Meta::TypeType::TypeUnion: reference(value->as<Meta::UnionType>().unionMeta); break;
        case Meta::TypeType::TypeEnum: {
            auto& enumeration = value->as<Meta::EnumType>();
            reference(enumeration.enumMeta); type(enumeration.underlyingType); break;
        }
        case Meta::TypeType::TypeTypeArgument: {
            auto& argument = value->as<Meta::TypeArgumentType>();
            type(argument.underlyingType); references(argument.protocols); break;
        }
        case Meta::TypeType::TypeConstantArray: type(value->as<Meta::ConstantArrayType>().innerType); break;
        case Meta::TypeType::TypeIncompleteArray: type(value->as<Meta::IncompleteArrayType>().innerType); break;
        case Meta::TypeType::TypeExtVector: type(value->as<Meta::ExtVectorType>().innerType); break;
        case Meta::TypeType::TypePointer: type(value->as<Meta::PointerType>().innerType); break;
        case Meta::TypeType::TypeNullable: type(value->as<Meta::NullableType>().innerType); break;
        case Meta::TypeType::TypeNonNullable: type(value->as<Meta::NonNullableType>().innerType); break;
        case Meta::TypeType::TypeBlock: signature(value->as<Meta::BlockType>().signature); break;
        case Meta::TypeType::TypeFunctionPointer: signature(value->as<Meta::FunctionPointerType>().signature); break;
        case Meta::TypeType::TypeAnonymousStruct: fields(value->as<Meta::AnonymousStructType>().fields); break;
        case Meta::TypeType::TypeAnonymousUnion: fields(value->as<Meta::AnonymousUnionType>().fields); break;
        default:
            // Remaining TypeType values are the original scalar encodings.
            if (value->getType() < Meta::TypeType::TypeVoid || value->getType() > Meta::TypeType::TypeProtocol)
                throw std::runtime_error("Unknown type in dual-grammar metadata graph");
        }
    }

    size_t retainedMetaCount() const { return metas.size(); }
    size_t retainedTypeCount() const { return types.size(); }
    const std::set<Meta::Meta*>& retainedMetas() const { return metas; }
};

} // namespace HanlinDual
