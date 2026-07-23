import Foundation

public indirect enum HanlinValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case data(Data)
    case array([HanlinValue])
    case object([String: HanlinValue])

    public static func finiteNumber(_ value: Double) throws -> HanlinValue {
        guard value.isFinite else {
            throw HanlinContractError.invalidNumber(value)
        }
        return .number(value)
    }

    public func canonicalJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func decodeCanonicalJSON(_ data: Data) throws -> HanlinValue {
        try JSONDecoder().decode(Self.self, from: data)
    }
}

extension HanlinValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum ValueType: String, Codable {
        case null
        case bool
        case integer
        case number
        case string
        case data
        case array
        case object
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)
        switch type {
        case .null:
            guard !container.contains(.value) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "Null values must not carry a payload."
                )
            }
            self = .null
        case .bool:
            self = try .bool(container.decode(Bool.self, forKey: .value))
        case .integer:
            self = try .integer(container.decode(Int64.self, forKey: .value))
        case .number:
            let value = try container.decode(Double.self, forKey: .value)
            guard value.isFinite else {
                throw HanlinContractError.invalidNumber(value)
            }
            self = .number(value)
        case .string:
            self = try .string(container.decode(String.self, forKey: .value))
        case .data:
            self = try .data(container.decode(Data.self, forKey: .value))
        case .array:
            self = try .array(container.decode([HanlinValue].self, forKey: .value))
        case .object:
            self = try .object(
                container.decode([String: HanlinValue].self, forKey: .value)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .null:
            try container.encode(ValueType.null, forKey: .type)
        case let .bool(value):
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .integer(value):
            try container.encode(ValueType.integer, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .number(value):
            guard value.isFinite else {
                throw HanlinContractError.invalidNumber(value)
            }
            try container.encode(ValueType.number, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .string(value):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .data(value):
            try container.encode(ValueType.data, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .array(value):
            try container.encode(ValueType.array, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .object(value):
            try container.encode(ValueType.object, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

public indirect enum HanlinJSONSchema: Hashable, Sendable {
    case `any`
    case null
    case boolean
    case integer(minimum: Int64?, maximum: Int64?)
    case number(minimum: Double?, maximum: Double?)
    case string(minLength: Int?, maxLength: Int?, pattern: String?)
    case data(maxBytes: Int?)
    case array(items: HanlinJSONSchema, minItems: Int?, maxItems: Int?)
    case object(
        properties: [String: HanlinJSONSchema],
        required: Set<String>,
        additionalProperties: Bool
    )
    case oneOf([HanlinJSONSchema])
    case enumeration([HanlinValue])

    public func validateDefinition() throws {
        switch self {
        case .any, .null, .boolean:
            return
        case let .integer(minimum, maximum):
            if let minimum, let maximum, minimum > maximum {
                throw HanlinContractError.invalidSchema(
                    reason: "integer minimum exceeds maximum"
                )
            }
        case let .number(minimum, maximum):
            if let minimum, !minimum.isFinite {
                throw HanlinContractError.invalidNumber(minimum)
            }
            if let maximum, !maximum.isFinite {
                throw HanlinContractError.invalidNumber(maximum)
            }
            if let minimum, let maximum, minimum > maximum {
                throw HanlinContractError.invalidSchema(
                    reason: "number minimum exceeds maximum"
                )
            }
        case let .string(minLength, maxLength, _):
            try Self.validateBounds(
                minimum: minLength,
                maximum: maxLength,
                label: "string length"
            )
        case let .data(maxBytes):
            if let maxBytes, maxBytes < 0 {
                throw HanlinContractError.invalidSchema(
                    reason: "data maximum byte count is negative"
                )
            }
        case let .array(items, minItems, maxItems):
            try Self.validateBounds(
                minimum: minItems,
                maximum: maxItems,
                label: "array item count"
            )
            try items.validateDefinition()
        case let .object(properties, required, _):
            let unknownRequired = required.subtracting(Set(properties.keys))
            guard unknownRequired.isEmpty else {
                throw HanlinContractError.invalidSchema(
                    reason: "required object properties are undeclared: \(unknownRequired.sorted())"
                )
            }
            for schema in properties.values {
                try schema.validateDefinition()
            }
        case let .oneOf(schemas):
            guard !schemas.isEmpty else {
                throw HanlinContractError.invalidSchema(
                    reason: "oneOf requires at least one schema"
                )
            }
            for schema in schemas {
                try schema.validateDefinition()
            }
        case let .enumeration(values):
            guard !values.isEmpty else {
                throw HanlinContractError.invalidSchema(
                    reason: "enumeration requires at least one value"
                )
            }
        }
    }

    private static func validateBounds(
        minimum: Int?,
        maximum: Int?,
        label: String
    ) throws {
        if let minimum, minimum < 0 {
            throw HanlinContractError.invalidSchema(
                reason: "\(label) minimum is negative"
            )
        }
        if let maximum, maximum < 0 {
            throw HanlinContractError.invalidSchema(
                reason: "\(label) maximum is negative"
            )
        }
        if let minimum, let maximum, minimum > maximum {
            throw HanlinContractError.invalidSchema(
                reason: "\(label) minimum exceeds maximum"
            )
        }
    }
}

extension HanlinJSONSchema: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case minimum
        case maximum
        case minLength
        case maxLength
        case pattern
        case maxBytes
        case items
        case minItems
        case maxItems
        case properties
        case required
        case additionalProperties
        case schemas
        case values
    }

    private enum SchemaType: String, Codable {
        case `any`
        case null
        case boolean
        case integer
        case number
        case string
        case data
        case array
        case object
        case oneOf
        case enumeration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(SchemaType.self, forKey: .type)
        switch type {
        case .any:
            self = .any
        case .null:
            self = .null
        case .boolean:
            self = .boolean
        case .integer:
            self = .integer(
                minimum: try container.decodeIfPresent(Int64.self, forKey: .minimum),
                maximum: try container.decodeIfPresent(Int64.self, forKey: .maximum)
            )
        case .number:
            self = .number(
                minimum: try container.decodeIfPresent(Double.self, forKey: .minimum),
                maximum: try container.decodeIfPresent(Double.self, forKey: .maximum)
            )
        case .string:
            self = .string(
                minLength: try container.decodeIfPresent(Int.self, forKey: .minLength),
                maxLength: try container.decodeIfPresent(Int.self, forKey: .maxLength),
                pattern: try container.decodeIfPresent(String.self, forKey: .pattern)
            )
        case .data:
            self = .data(
                maxBytes: try container.decodeIfPresent(Int.self, forKey: .maxBytes)
            )
        case .array:
            self = .array(
                items: try container.decode(HanlinJSONSchema.self, forKey: .items),
                minItems: try container.decodeIfPresent(Int.self, forKey: .minItems),
                maxItems: try container.decodeIfPresent(Int.self, forKey: .maxItems)
            )
        case .object:
            self = .object(
                properties: try container.decode(
                    [String: HanlinJSONSchema].self,
                    forKey: .properties
                ),
                required: Set(
                    try container.decodeIfPresent(
                        [String].self,
                        forKey: .required
                    ) ?? []
                ),
                additionalProperties: try container.decodeIfPresent(
                    Bool.self,
                    forKey: .additionalProperties
                ) ?? false
            )
        case .oneOf:
            self = .oneOf(
                try container.decode([HanlinJSONSchema].self, forKey: .schemas)
            )
        case .enumeration:
            self = .enumeration(
                try container.decode([HanlinValue].self, forKey: .values)
            )
        }
        try validateDefinition()
    }

    public func encode(to encoder: Encoder) throws {
        try validateDefinition()
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .any:
            try container.encode(SchemaType.any, forKey: .type)
        case .null:
            try container.encode(SchemaType.null, forKey: .type)
        case .boolean:
            try container.encode(SchemaType.boolean, forKey: .type)
        case let .integer(minimum, maximum):
            try container.encode(SchemaType.integer, forKey: .type)
            try container.encodeIfPresent(minimum, forKey: .minimum)
            try container.encodeIfPresent(maximum, forKey: .maximum)
        case let .number(minimum, maximum):
            try container.encode(SchemaType.number, forKey: .type)
            try container.encodeIfPresent(minimum, forKey: .minimum)
            try container.encodeIfPresent(maximum, forKey: .maximum)
        case let .string(minLength, maxLength, pattern):
            try container.encode(SchemaType.string, forKey: .type)
            try container.encodeIfPresent(minLength, forKey: .minLength)
            try container.encodeIfPresent(maxLength, forKey: .maxLength)
            try container.encodeIfPresent(pattern, forKey: .pattern)
        case let .data(maxBytes):
            try container.encode(SchemaType.data, forKey: .type)
            try container.encodeIfPresent(maxBytes, forKey: .maxBytes)
        case let .array(items, minItems, maxItems):
            try container.encode(SchemaType.array, forKey: .type)
            try container.encode(items, forKey: .items)
            try container.encodeIfPresent(minItems, forKey: .minItems)
            try container.encodeIfPresent(maxItems, forKey: .maxItems)
        case let .object(properties, required, additionalProperties):
            try container.encode(SchemaType.object, forKey: .type)
            try container.encode(properties, forKey: .properties)
            try container.encode(required.sorted(), forKey: .required)
            try container.encode(
                additionalProperties,
                forKey: .additionalProperties
            )
        case let .oneOf(schemas):
            try container.encode(SchemaType.oneOf, forKey: .type)
            try container.encode(schemas, forKey: .schemas)
        case let .enumeration(values):
            try container.encode(SchemaType.enumeration, forKey: .type)
            try container.encode(values, forKey: .values)
        }
    }
}
