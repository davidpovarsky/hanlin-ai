import AISDKProvider
import Foundation

/// A deliberately closed JSON Schema subset that can be represented by Apple's public
/// DynamicGenerationSchema constructors without dropping validation constraints.
/// It is an internal candidate; the shipping provider's capability gate stays closed.
struct HanlinAppleToolSchema: Sendable {
    struct Property: Sendable {
        let name: String
        let schema: Node
        let required: Bool
    }

    struct Node: Sendable {
        indirect enum Kind: Sendable {
            case string([String]?)
            case boolean
            case null
            case array(Node, minimum: Int?, maximum: Int?)
            case object([Property])
        }
        let kind: Kind
        let description: String?
    }

    let root: Node

    init(_ schema: JSONValue) throws {
        var remaining = 256
        root = try Self.parse(schema, depth: 0, remaining: &remaining)
        guard case .object = root.kind else { throw HanlinAppleToolBridgeError.unsupportedSchema }
    }

    func validate(arguments: JSONValue) throws {
        var remaining = 4_096
        try Self.validate(arguments, node: root, depth: 0, remaining: &remaining)
    }

    private static func parse(_ value: JSONValue, depth: Int, remaining: inout Int) throws -> Node {
        guard depth <= 16, remaining > 0, case .object(let fields) = value,
              case .string(let type) = fields["type"] else {
            throw HanlinAppleToolBridgeError.unsupportedSchema
        }
        remaining -= 1
        let common: Set<String> = ["type", "title", "description", "$schema"]
        for key in ["title", "description"] where fields[key] != nil {
            guard case .string(let text) = fields[key], text.utf8.count <= 16_384 else {
                throw HanlinAppleToolBridgeError.unsupportedSchema
            }
        }
        if let dialect = fields["$schema"] {
            guard depth == 0, case .string(let url) = dialect, [
                "http://json-schema.org/draft-07/schema#",
                "https://json-schema.org/draft/2020-12/schema",
                "https://json-schema.org/draft/2019-09/schema"
            ].contains(url) else { throw HanlinAppleToolBridgeError.unsupportedSchema }
        }
        let description: String?
        if case .string(let text) = fields["description"] { description = text } else { description = nil }
        let kind: Node.Kind
        switch type {
        case "string":
            guard Set(fields.keys).isSubset(of: common.union(["enum"])) else {
                throw HanlinAppleToolBridgeError.unsupportedSchema
            }
            var choices: [String]?
            if let enumeration = fields["enum"] {
                guard case .array(let values) = enumeration, !values.isEmpty, values.count <= 256 else {
                    throw HanlinAppleToolBridgeError.unsupportedSchema
                }
                let strings = try values.map { value -> String in
                    guard case .string(let text) = value, text.utf8.count <= 16_384 else {
                        throw HanlinAppleToolBridgeError.unsupportedSchema
                    }
                    return text
                }
                guard Set(strings).count == strings.count else { throw HanlinAppleToolBridgeError.unsupportedSchema }
                choices = strings
            }
            kind = .string(choices)
        case "boolean", "null":
            guard Set(fields.keys).isSubset(of: common) else { throw HanlinAppleToolBridgeError.unsupportedSchema }
            kind = type == "boolean" ? .boolean : .null
        case "array":
            guard Set(fields.keys).isSubset(of: common.union(["items", "minItems", "maxItems"])),
                  let items = fields["items"] else { throw HanlinAppleToolBridgeError.unsupportedSchema }
            let minimum = try bound(fields["minItems"])
            let maximum = try bound(fields["maxItems"])
            if let minimum, let maximum, minimum > maximum { throw HanlinAppleToolBridgeError.unsupportedSchema }
            kind = .array(try parse(items, depth: depth + 1, remaining: &remaining),
                          minimum: minimum, maximum: maximum)
        case "object":
            guard Set(fields.keys).isSubset(of: common.union(["properties", "required", "additionalProperties"])),
                  fields["additionalProperties"] == .bool(false) else {
                throw HanlinAppleToolBridgeError.unsupportedSchema
            }
            let properties: [String: JSONValue]
            if let value = fields["properties"] {
                guard case .object(let members) = value, members.count <= 128 else {
                    throw HanlinAppleToolBridgeError.unsupportedSchema
                }
                properties = members
            } else { properties = [:] }
            var required: Set<String> = []
            if let value = fields["required"] {
                guard case .array(let names) = value else { throw HanlinAppleToolBridgeError.unsupportedSchema }
                for name in names {
                    guard case .string(let name) = name, properties[name] != nil,
                          required.insert(name).inserted else { throw HanlinAppleToolBridgeError.unsupportedSchema }
                }
            }
            kind = .object(try properties.keys.sorted().map { name in
                guard !name.isEmpty, name.utf8.count <= 512, let value = properties[name] else {
                    throw HanlinAppleToolBridgeError.unsupportedSchema
                }
                return Property(name: name, schema: try parse(value, depth: depth + 1, remaining: &remaining),
                                required: required.contains(name))
            })
        default:
            // GeneratedContent exposes numbers as Double, not original numeric tokens.
            // Numeric and unrepresented constraints must fail before advertising the tool.
            throw HanlinAppleToolBridgeError.unsupportedSchema
        }
        return Node(kind: kind, description: description)
    }

    private static func bound(_ value: JSONValue?) throws -> Int? {
        guard let value else { return nil }
        guard case .number(let number) = value, number.isFinite, number.rounded() == number,
              number >= 0, number <= 4_096 else { throw HanlinAppleToolBridgeError.unsupportedSchema }
        return Int(number)
    }

    private static func validate(_ value: JSONValue, node: Node, depth: Int, remaining: inout Int) throws {
        guard depth <= 32, remaining > 0 else { throw HanlinAppleToolBridgeError.invalidArguments }
        remaining -= 1
        if case .number = value { throw HanlinAppleToolBridgeError.numericArgumentsUnsupported }
        switch (node.kind, value) {
        case (.string(let choices), .string(let text)):
            guard text.utf8.count <= 65_536, choices?.contains(text) != false else {
                throw HanlinAppleToolBridgeError.invalidArguments
            }
        case (.boolean, .bool), (.null, .null): break
        case (.array(let item, let minimum, let maximum), .array(let values)):
            guard values.count >= (minimum ?? 0), values.count <= (maximum ?? 4_096) else {
                throw HanlinAppleToolBridgeError.invalidArguments
            }
            for value in values { try validate(value, node: item, depth: depth + 1, remaining: &remaining) }
        case (.object(let properties), .object(let values)):
            guard Set(values.keys).isSubset(of: Set(properties.map(\.name))) else {
                throw HanlinAppleToolBridgeError.invalidArguments
            }
            for property in properties {
                if let value = values[property.name] {
                    try validate(value, node: property.schema, depth: depth + 1, remaining: &remaining)
                } else if property.required { throw HanlinAppleToolBridgeError.invalidArguments }
            }
        default: throw HanlinAppleToolBridgeError.invalidArguments
        }
    }
}

enum HanlinAppleToolBridgeError: String, Error, Sendable {
    case unsupportedSchema, invalidArguments, numericArgumentsUnsupported
    case invalidHistory, invalidHandoff, unexpectedToolExecution
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 27.0, macOS 27.0, *)
extension HanlinAppleToolSchema {
    func nativeSchema(name: String) throws -> GenerationSchema {
        var ordinal = 0
        let root = Self.nativeNode(root, name: name, ordinal: &ordinal)
        return try GenerationSchema(root: root, dependencies: [])
    }

    private static func nativeNode(_ node: Node, name: String, ordinal: inout Int) -> DynamicGenerationSchema {
        ordinal += 1
        let typeName = name + "_" + String(ordinal)
        switch node.kind {
        case .string(let choices):
            if let choices { return .init(name: typeName, description: node.description, anyOf: choices) }
            return .init(type: String.self)
        case .boolean: return .init(type: Bool.self)
        case .null: return .null
        case .array(let item, let minimum, let maximum):
            return .init(arrayOf: nativeNode(item, name: name, ordinal: &ordinal),
                         minimumElements: minimum, maximumElements: maximum)
        case .object(let properties):
            return .init(name: typeName, description: node.description, properties: properties.map { property in
                .init(name: property.name, description: property.schema.description,
                      schema: nativeNode(property.schema, name: name, ordinal: &ordinal),
                      isOptional: !property.required)
            })
        }
    }
}
#endif
