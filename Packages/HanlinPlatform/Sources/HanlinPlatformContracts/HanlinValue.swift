import Foundation

public struct HanlinValueLimits: Codable, Hashable, Sendable {
    public let maximumDepth: Int
    public let maximumObjectMembers: Int
    public let maximumArrayItems: Int
    public let maximumStringBytes: Int
    public let maximumKeyBytes: Int
    public let maximumInlineDataBytes: Int
    public let maximumPayloadBytes: Int
    public let maximumNodes: Int

    public init(
        maximumDepth: Int = 64,
        maximumObjectMembers: Int = 4_096,
        maximumArrayItems: Int = 65_536,
        maximumStringBytes: Int = 1_048_576,
        maximumKeyBytes: Int = 16_384,
        maximumInlineDataBytes: Int = 1_048_576,
        maximumPayloadBytes: Int = 1_048_576,
        maximumNodes: Int = 100_000
    ) {
        self.maximumDepth = maximumDepth
        self.maximumObjectMembers = maximumObjectMembers
        self.maximumArrayItems = maximumArrayItems
        self.maximumStringBytes = maximumStringBytes
        self.maximumKeyBytes = maximumKeyBytes
        self.maximumInlineDataBytes = maximumInlineDataBytes
        self.maximumPayloadBytes = maximumPayloadBytes
        self.maximumNodes = maximumNodes
    }

    public static let canonical = HanlinValueLimits()
}

public enum HanlinNumericDestination: String, Codable, Hashable, Sendable {
    case json
    case javaScriptBinary64
}

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

    public func canonicalJSONData(
        limits: HanlinValueLimits = .canonical
    ) throws -> Data {
        var nodes = 0
        try validate(limits: limits, depth: 0, path: "", nodes: &nodes)
        return try taggedJSONValue().canonicalJSONData(limits: limits)
    }

    public static func decodeCanonicalJSON(
        _ data: Data,
        limits: HanlinValueLimits = .canonical
    ) throws -> HanlinValue {
        let tagged = try HanlinJSONValue.decodeCanonicalJSON(data, limits: limits)
        let value = try Self(taggedJSONValue: tagged, path: "")
        var nodes = 0
        try value.validate(limits: limits, depth: 0, path: "", nodes: &nodes)
        return value
    }

    public func jsonValue(
        destination: HanlinNumericDestination = .json,
        path: String = ""
    ) throws -> HanlinJSONValue {
        switch self {
        case .null:
            return .null
        case let .bool(value):
            return .bool(value)
        case let .integer(value):
            if destination == .javaScriptBinary64,
               !(-9_007_199_254_740_991 ... 9_007_199_254_740_991).contains(value)
            {
                throw HanlinContractError.integerNotExact(
                    value: String(value),
                    destination: destination.rawValue,
                    path: path
                )
            }
            return .integer(value)
        case let .number(value):
            guard value.isFinite else {
                throw HanlinContractError.invalidNumber(value)
            }
            return .number(value)
        case let .string(value):
            return .string(value)
        case .data:
            throw HanlinContractError.binaryNotRepresentable(
                destination: destination.rawValue,
                path: path
            )
        case let .array(values):
            return try .array(values.enumerated().map { index, value in
                try value.jsonValue(
                    destination: destination,
                    path: Self.appending(String(index), to: path)
                )
            })
        case let .object(values):
            return try .object(Dictionary(uniqueKeysWithValues: values.map { key, value in
                (
                    key,
                    try value.jsonValue(
                        destination: destination,
                        path: Self.appending(key, to: path)
                    )
                )
            }))
        }
    }

    private func taggedJSONValue() throws -> HanlinJSONValue {
        switch self {
        case .null:
            return .object(["type": .string("null")])
        case let .bool(value):
            return .object(["type": .string("bool"), "value": .bool(value)])
        case let .integer(value):
            return .object([
                "type": .string("integer"),
                "value": .string(String(value))
            ])
        case let .number(value):
            guard value.isFinite else {
                throw HanlinContractError.invalidNumber(value)
            }
            return .object([
                "type": .string("number"),
                "value": .string(Self.binary64Hex(value))
            ])
        case let .string(value):
            return .object(["type": .string("string"), "value": .string(value)])
        case let .data(value):
            return .object([
                "type": .string("data"),
                "value": .object([
                    "base64url": .string(Self.base64URL(value)),
                    "byteCount": .integer(Int64(value.count))
                ])
            ])
        case let .array(values):
            return .object([
                "type": .string("array"),
                "value": .array(try values.map { try $0.taggedJSONValue() })
            ])
        case let .object(values):
            return .object([
                "type": .string("object"),
                "value": .object(try values.mapValues { try $0.taggedJSONValue() })
            ])
        }
    }

    private func validate(
        limits: HanlinValueLimits,
        depth: Int,
        path: String,
        nodes: inout Int
    ) throws {
        guard depth <= limits.maximumDepth else {
            throw HanlinContractError.depthLimitExceeded(
                maximum: limits.maximumDepth,
                path: path
            )
        }
        nodes += 1
        guard nodes <= limits.maximumNodes else {
            throw HanlinContractError.sizeLimitExceeded(
                kind: "rich value nodes",
                measured: nodes,
                maximum: limits.maximumNodes,
                path: path
            )
        }
        switch self {
        case .null, .bool, .integer:
            return
        case let .number(value):
            guard value.isFinite else { throw HanlinContractError.invalidNumber(value) }
        case let .string(value):
            guard value.utf8.count <= limits.maximumStringBytes else {
                throw HanlinContractError.sizeLimitExceeded(
                    kind: "string UTF-8 bytes",
                    measured: value.utf8.count,
                    maximum: limits.maximumStringBytes,
                    path: path
                )
            }
        case let .data(value):
            guard value.count <= limits.maximumInlineDataBytes else {
                throw HanlinContractError.sizeLimitExceeded(
                    kind: "inline data bytes",
                    measured: value.count,
                    maximum: limits.maximumInlineDataBytes,
                    path: path
                )
            }
        case let .array(values):
            guard values.count <= limits.maximumArrayItems else {
                throw HanlinContractError.sizeLimitExceeded(
                    kind: "array items",
                    measured: values.count,
                    maximum: limits.maximumArrayItems,
                    path: path
                )
            }
            for (index, value) in values.enumerated() {
                try value.validate(
                    limits: limits,
                    depth: depth + 1,
                    path: Self.appending(String(index), to: path),
                    nodes: &nodes
                )
            }
        case let .object(values):
            guard values.count <= limits.maximumObjectMembers else {
                throw HanlinContractError.sizeLimitExceeded(
                    kind: "object members",
                    measured: values.count,
                    maximum: limits.maximumObjectMembers,
                    path: path
                )
            }
            for (key, value) in values {
                let memberPath = Self.appending(key, to: path)
                guard key.utf8.count <= limits.maximumKeyBytes else {
                    throw HanlinContractError.sizeLimitExceeded(
                        kind: "object key UTF-8 bytes",
                        measured: key.utf8.count,
                        maximum: limits.maximumKeyBytes,
                        path: memberPath
                    )
                }
                try value.validate(
                    limits: limits,
                    depth: depth + 1,
                    path: memberPath,
                    nodes: &nodes
                )
            }
        }
    }

    private init(taggedJSONValue value: HanlinJSONValue, path: String) throws {
        guard case let .object(container) = value,
              case let .string(type)? = container["type"]
        else {
            throw HanlinContractError.invalidJSON(
                reason: "rich values require an object with a string type",
                byteOffset: 0
            )
        }
        let unexpectedKeys = Set(container.keys).subtracting(["type", "value"])
        guard unexpectedKeys.isEmpty else {
            throw HanlinContractError.invalidJSON(
                reason: "unexpected rich-value members: \(unexpectedKeys.sorted())",
                byteOffset: 0
            )
        }
        switch type {
        case "null":
            guard container["value"] == nil else {
                throw HanlinContractError.invalidJSON(
                    reason: "null values must not carry a payload",
                    byteOffset: 0
                )
            }
            self = .null
        case "bool":
            guard case let .bool(payload)? = container["value"] else {
                throw Self.invalidTaggedPayload(type)
            }
            self = .bool(payload)
        case "integer":
            guard case let .string(payload)? = container["value"],
                  let integer = Int64(payload),
                  String(integer) == payload
            else {
                throw HanlinContractError.integerOutOfRange(
                    value: container["value"].map(String.init(describing:)) ?? "missing",
                    destination: "Int64",
                    path: path
                )
            }
            self = .integer(integer)
        case "number":
            guard case let .string(payload)? = container["value"],
                  payload.count == 16,
                  payload.allSatisfy({ $0.isNumber || ("a" ... "f").contains($0) }),
                  let bits = UInt64(payload, radix: 16)
            else {
                throw Self.invalidTaggedPayload(type)
            }
            let number = Double(bitPattern: bits)
            guard number.isFinite else {
                throw HanlinContractError.invalidNumber(number)
            }
            self = .number(number)
        case "string":
            guard case let .string(payload)? = container["value"] else {
                throw Self.invalidTaggedPayload(type)
            }
            self = .string(payload)
        case "data":
            guard case let .object(payload)? = container["value"],
                  case let .string(encoded)? = payload["base64url"],
                  case let .integer(byteCount)? = payload["byteCount"],
                  payload.count == 2,
                  byteCount >= 0,
                  let decoded = Self.decodeBase64URL(encoded),
                  decoded.count == Int(byteCount),
                  Self.base64URL(decoded) == encoded
            else {
                throw Self.invalidTaggedPayload(type)
            }
            self = .data(decoded)
        case "array":
            guard case let .array(payload)? = container["value"] else {
                throw Self.invalidTaggedPayload(type)
            }
            self = try .array(payload.enumerated().map { index, item in
                try Self(
                    taggedJSONValue: item,
                    path: Self.appending(String(index), to: path)
                )
            })
        case "object":
            guard case let .object(payload)? = container["value"] else {
                throw Self.invalidTaggedPayload(type)
            }
            self = try .object(Dictionary(uniqueKeysWithValues: payload.map { key, item in
                (
                    key,
                    try Self(
                        taggedJSONValue: item,
                        path: Self.appending(key, to: path)
                    )
                )
            }))
        default:
            throw HanlinContractError.invalidJSON(
                reason: "unknown rich-value type '\(type)'",
                byteOffset: 0
            )
        }
    }

    private static func invalidTaggedPayload(_ type: String) -> HanlinContractError {
        .invalidJSON(reason: "invalid payload for rich-value type '\(type)'", byteOffset: 0)
    }

    private static func binary64Hex(_ value: Double) -> String {
        String(format: "%016llx", value.bitPattern)
    }

    private static func base64URL(_ value: Data) -> String {
        value.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        guard value.utf8.allSatisfy({ byte in
            (65 ... 90).contains(byte) || (97 ... 122).contains(byte) ||
                (48 ... 57).contains(byte) || byte == 45 || byte == 95
        }) else {
            return nil
        }
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    private static func appending(_ component: String, to path: String) -> String {
        let escaped = component
            .replacingOccurrences(of: "~", with: "~0")
            .replacingOccurrences(of: "/", with: "~1")
        return path + "/" + escaped
    }
}

extension HanlinValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private struct DataPayload: Codable {
        let base64url: String
        let byteCount: Int
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "null":
            guard !container.contains(.value) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "Null values must not carry a payload."
                )
            }
            self = .null
        case "bool":
            self = try .bool(container.decode(Bool.self, forKey: .value))
        case "integer":
            let payload = try container.decode(String.self, forKey: .value)
            guard let value = Int64(payload), String(value) == payload else {
                throw HanlinContractError.integerOutOfRange(
                    value: payload,
                    destination: "Int64",
                    path: ""
                )
            }
            self = .integer(value)
        case "number":
            let payload = try container.decode(String.self, forKey: .value)
            guard payload.count == 16, let bits = UInt64(payload, radix: 16) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "Binary64 values require 16 hexadecimal digits."
                )
            }
            let value = Double(bitPattern: bits)
            guard value.isFinite else {
                throw HanlinContractError.invalidNumber(value)
            }
            self = .number(value)
        case "string":
            self = try .string(container.decode(String.self, forKey: .value))
        case "data":
            let payload = try container.decode(DataPayload.self, forKey: .value)
            guard payload.byteCount >= 0,
                  let value = Self.decodeBase64URL(payload.base64url),
                  value.count == payload.byteCount,
                  Self.base64URL(value) == payload.base64url
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "Invalid canonical base64url data payload."
                )
            }
            self = .data(value)
        case "array":
            self = try .array(container.decode([HanlinValue].self, forKey: .value))
        case "object":
            self = try .object(container.decode([String: HanlinValue].self, forKey: .value))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown Hanlin value type '\(type)'."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .null:
            try container.encode("null", forKey: .type)
        case let .bool(value):
            try container.encode("bool", forKey: .type)
            try container.encode(value, forKey: .value)
        case let .integer(value):
            try container.encode("integer", forKey: .type)
            try container.encode(String(value), forKey: .value)
        case let .number(value):
            guard value.isFinite else {
                throw HanlinContractError.invalidNumber(value)
            }
            try container.encode("number", forKey: .type)
            try container.encode(Self.binary64Hex(value), forKey: .value)
        case let .string(value):
            try container.encode("string", forKey: .type)
            try container.encode(value, forKey: .value)
        case let .data(value):
            try container.encode("data", forKey: .type)
            try container.encode(
                DataPayload(base64url: Self.base64URL(value), byteCount: value.count),
                forKey: .value
            )
        case let .array(value):
            try container.encode("array", forKey: .type)
            try container.encode(value, forKey: .value)
        case let .object(value):
            try container.encode("object", forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

public indirect enum HanlinJSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([HanlinJSONValue])
    case object([String: HanlinJSONValue])

    public static func finiteNumber(_ value: Double) throws -> HanlinJSONValue {
        guard value.isFinite else {
            throw HanlinContractError.invalidNumber(value)
        }
        return .number(value)
    }

    public func canonicalJSONData(
        limits: HanlinValueLimits = .canonical
    ) throws -> Data {
        var nodes = 0
        try validate(limits: limits, depth: 0, path: "", nodes: &nodes)
        var text = ""
        try appendCanonicalJSON(to: &text)
        let data = Data(text.utf8)
        guard data.count <= limits.maximumPayloadBytes else {
            throw HanlinContractError.sizeLimitExceeded(
                kind: "canonical payload bytes",
                measured: data.count,
                maximum: limits.maximumPayloadBytes,
                path: ""
            )
        }
        return data
    }

    public static func decodeCanonicalJSON(
        _ data: Data,
        limits: HanlinValueLimits = .canonical
    ) throws -> HanlinJSONValue {
        var parser = HanlinJSONParser(data: data, limits: limits)
        return try parser.parse()
    }

    private func validate(
        limits: HanlinValueLimits,
        depth: Int,
        path: String,
        nodes: inout Int
    ) throws {
        guard depth <= limits.maximumDepth else {
            throw HanlinContractError.depthLimitExceeded(
                maximum: limits.maximumDepth,
                path: path
            )
        }
        nodes += 1
        guard nodes <= limits.maximumNodes else {
            throw HanlinContractError.sizeLimitExceeded(
                kind: "value nodes",
                measured: nodes,
                maximum: limits.maximumNodes,
                path: path
            )
        }
        switch self {
        case .null, .bool, .integer:
            return
        case let .number(value):
            guard value.isFinite else {
                throw HanlinContractError.invalidNumber(value)
            }
        case let .string(value):
            try Self.checkSize(
                kind: "string UTF-8 bytes",
                measured: value.utf8.count,
                maximum: limits.maximumStringBytes,
                path: path
            )
        case let .array(values):
            try Self.checkSize(
                kind: "array items",
                measured: values.count,
                maximum: limits.maximumArrayItems,
                path: path
            )
            for (index, value) in values.enumerated() {
                try value.validate(
                    limits: limits,
                    depth: depth + 1,
                    path: Self.appending(String(index), to: path),
                    nodes: &nodes
                )
            }
        case let .object(values):
            try Self.checkSize(
                kind: "object members",
                measured: values.count,
                maximum: limits.maximumObjectMembers,
                path: path
            )
            for (key, value) in values {
                let memberPath = Self.appending(key, to: path)
                try Self.checkSize(
                    kind: "object key UTF-8 bytes",
                    measured: key.utf8.count,
                    maximum: limits.maximumKeyBytes,
                    path: memberPath
                )
                try value.validate(
                    limits: limits,
                    depth: depth + 1,
                    path: memberPath,
                    nodes: &nodes
                )
            }
        }
    }

    private static func checkSize(
        kind: String,
        measured: Int,
        maximum: Int,
        path: String
    ) throws {
        guard measured <= maximum else {
            throw HanlinContractError.sizeLimitExceeded(
                kind: kind,
                measured: measured,
                maximum: maximum,
                path: path
            )
        }
    }

    private func appendCanonicalJSON(to output: inout String) throws {
        switch self {
        case .null:
            output += "null"
        case let .bool(value):
            output += value ? "true" : "false"
        case let .integer(value):
            output += String(value)
        case let .number(value):
            output += try Self.canonicalNumber(value)
        case let .string(value):
            Self.appendJSONString(value, to: &output)
        case let .array(values):
            output += "["
            for (index, value) in values.enumerated() {
                if index > 0 { output += "," }
                try value.appendCanonicalJSON(to: &output)
            }
            output += "]"
        case let .object(values):
            output += "{"
            let sorted = values.sorted { left, right in
                left.key.utf8.lexicographicallyPrecedes(right.key.utf8)
            }
            for (index, member) in sorted.enumerated() {
                if index > 0 { output += "," }
                Self.appendJSONString(member.key, to: &output)
                output += ":"
                try member.value.appendCanonicalJSON(to: &output)
            }
            output += "}"
        }
    }

    private static func canonicalNumber(_ value: Double) throws -> String {
        guard value.isFinite else {
            throw HanlinContractError.invalidNumber(value)
        }
        if value == 0 {
            return value.bitPattern >> 63 == 1 ? "-0.0" : "0.0"
        }
        var result = String(value).lowercased()
        if !result.contains(".") && !result.contains("e") {
            result += ".0"
        }
        return result
    }

    private static func appendJSONString(_ value: String, to output: inout String) {
        output += "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08: output += "\\b"
            case 0x09: output += "\\t"
            case 0x0A: output += "\\n"
            case 0x0C: output += "\\f"
            case 0x0D: output += "\\r"
            case 0x22: output += "\\\""
            case 0x5C: output += "\\\\"
            case 0x00 ... 0x1F:
                output += String(format: "\\u%04x", scalar.value)
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        output += "\""
    }

    private static func appending(_ component: String, to path: String) -> String {
        let escaped = component
            .replacingOccurrences(of: "~", with: "~0")
            .replacingOccurrences(of: "/", with: "~1")
        return path + "/" + escaped
    }
}

extension HanlinJSONValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "null":
            self = .null
        case "bool":
            self = try .bool(container.decode(Bool.self, forKey: .value))
        case "integer":
            let payload = try container.decode(String.self, forKey: .value)
            guard let value = Int64(payload), String(value) == payload else {
                throw HanlinContractError.integerOutOfRange(
                    value: payload,
                    destination: "Int64",
                    path: ""
                )
            }
            self = .integer(value)
        case "number":
            let payload = try container.decode(String.self, forKey: .value)
            guard payload.count == 16, let bits = UInt64(payload, radix: 16) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "Binary64 values require 16 hexadecimal digits."
                )
            }
            let value = Double(bitPattern: bits)
            guard value.isFinite else {
                throw HanlinContractError.invalidNumber(value)
            }
            self = .number(value)
        case "string":
            self = try .string(container.decode(String.self, forKey: .value))
        case "array":
            self = try .array(container.decode([HanlinJSONValue].self, forKey: .value))
        case "object":
            self = try .object(container.decode([String: HanlinJSONValue].self, forKey: .value))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown Hanlin JSON value type '\(type)'."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .null:
            try container.encode("null", forKey: .type)
        case let .bool(value):
            try container.encode("bool", forKey: .type)
            try container.encode(value, forKey: .value)
        case let .integer(value):
            try container.encode("integer", forKey: .type)
            try container.encode(String(value), forKey: .value)
        case let .number(value):
            guard value.isFinite else {
                throw HanlinContractError.invalidNumber(value)
            }
            try container.encode("number", forKey: .type)
            try container.encode(String(format: "%016llx", value.bitPattern), forKey: .value)
        case let .string(value):
            try container.encode("string", forKey: .type)
            try container.encode(value, forKey: .value)
        case let .array(value):
            try container.encode("array", forKey: .type)
            try container.encode(value, forKey: .value)
        case let .object(value):
            try container.encode("object", forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

private struct HanlinJSONParser {
    private let bytes: [UInt8]
    private let limits: HanlinValueLimits
    private var index = 0
    private var nodes = 0

    init(data: Data, limits: HanlinValueLimits) {
        bytes = Array(data)
        self.limits = limits
    }

    mutating func parse() throws -> HanlinJSONValue {
        guard bytes.count <= limits.maximumPayloadBytes else {
            throw HanlinContractError.sizeLimitExceeded(
                kind: "JSON payload bytes",
                measured: bytes.count,
                maximum: limits.maximumPayloadBytes,
                path: ""
            )
        }
        guard !bytes.starts(with: [0xEF, 0xBB, 0xBF]) else {
            throw failure("UTF-8 BOM is not permitted")
        }
        skipWhitespace()
        let value = try parseValue(depth: 0, path: "")
        skipWhitespace()
        guard index == bytes.count else {
            throw failure("unexpected trailing content")
        }
        return value
    }

    private mutating func parseValue(depth: Int, path: String) throws -> HanlinJSONValue {
        guard depth <= limits.maximumDepth else {
            throw HanlinContractError.depthLimitExceeded(
                maximum: limits.maximumDepth,
                path: path
            )
        }
        nodes += 1
        guard nodes <= limits.maximumNodes else {
            throw HanlinContractError.sizeLimitExceeded(
                kind: "JSON value nodes",
                measured: nodes,
                maximum: limits.maximumNodes,
                path: path
            )
        }
        guard let byte = peek() else {
            throw failure("expected a value")
        }
        switch byte {
        case 0x6E:
            try consumeLiteral("null")
            return .null
        case 0x74:
            try consumeLiteral("true")
            return .bool(true)
        case 0x66:
            try consumeLiteral("false")
            return .bool(false)
        case 0x22:
            return .string(try parseString(maximumBytes: limits.maximumStringBytes, path: path))
        case 0x5B:
            return try parseArray(depth: depth, path: path)
        case 0x7B:
            return try parseObject(depth: depth, path: path)
        case 0x2D, 0x30 ... 0x39:
            return try parseNumber(path: path)
        default:
            throw failure("unexpected token")
        }
    }

    private mutating func parseArray(depth: Int, path: String) throws -> HanlinJSONValue {
        index += 1
        skipWhitespace()
        var values: [HanlinJSONValue] = []
        if consumeIf(0x5D) {
            return .array(values)
        }
        while true {
            guard values.count < limits.maximumArrayItems else {
                throw HanlinContractError.sizeLimitExceeded(
                    kind: "array items",
                    measured: values.count + 1,
                    maximum: limits.maximumArrayItems,
                    path: path
                )
            }
            let childPath = append(String(values.count), to: path)
            values.append(try parseValue(depth: depth + 1, path: childPath))
            skipWhitespace()
            if consumeIf(0x5D) { break }
            guard consumeIf(0x2C) else {
                throw failure("expected ',' or ']' in array")
            }
            skipWhitespace()
        }
        return .array(values)
    }

    private mutating func parseObject(depth: Int, path: String) throws -> HanlinJSONValue {
        index += 1
        skipWhitespace()
        var values: [String: HanlinJSONValue] = [:]
        if consumeIf(0x7D) {
            return .object(values)
        }
        while true {
            guard values.count < limits.maximumObjectMembers else {
                throw HanlinContractError.sizeLimitExceeded(
                    kind: "object members",
                    measured: values.count + 1,
                    maximum: limits.maximumObjectMembers,
                    path: path
                )
            }
            guard peek() == 0x22 else {
                throw failure("expected an object key")
            }
            let key = try parseString(maximumBytes: limits.maximumKeyBytes, path: path)
            let memberPath = append(key, to: path)
            guard values[key] == nil else {
                throw HanlinContractError.duplicateObjectKey(key: key, path: path)
            }
            skipWhitespace()
            guard consumeIf(0x3A) else {
                throw failure("expected ':' after object key")
            }
            skipWhitespace()
            values[key] = try parseValue(depth: depth + 1, path: memberPath)
            skipWhitespace()
            if consumeIf(0x7D) { break }
            guard consumeIf(0x2C) else {
                throw failure("expected ',' or '}' in object")
            }
            skipWhitespace()
        }
        return .object(values)
    }

    private mutating func parseString(maximumBytes: Int, path: String) throws -> String {
        guard consumeIf(0x22) else {
            throw failure("expected a string")
        }
        var result = ""
        var segment: [UInt8] = []

        func checked(_ value: String) throws -> String {
            guard value.utf8.count <= maximumBytes else {
                throw HanlinContractError.sizeLimitExceeded(
                    kind: "string UTF-8 bytes",
                    measured: value.utf8.count,
                    maximum: maximumBytes,
                    path: path
                )
            }
            return value
        }

        func flushSegment() throws {
            guard !segment.isEmpty else { return }
            guard let decoded = String(bytes: segment, encoding: .utf8) else {
                throw failure("string contains invalid UTF-8")
            }
            result += decoded
            segment.removeAll(keepingCapacity: true)
        }

        while let byte = peek() {
            index += 1
            switch byte {
            case 0x22:
                try flushSegment()
                return try checked(result)
            case 0x5C:
                try flushSegment()
                guard let escaped = peek() else {
                    throw failure("unterminated escape")
                }
                index += 1
                switch escaped {
                case 0x22: result += "\""
                case 0x5C: result += "\\"
                case 0x2F: result += "/"
                case 0x62: result += "\u{8}"
                case 0x66: result += "\u{c}"
                case 0x6E: result += "\n"
                case 0x72: result += "\r"
                case 0x74: result += "\t"
                case 0x75:
                    let first = try parseHexQuad()
                    let scalarValue: UInt32
                    if (0xD800 ... 0xDBFF).contains(first) {
                        guard consumeIf(0x5C), consumeIf(0x75) else {
                            throw failure("high surrogate requires a low surrogate")
                        }
                        let second = try parseHexQuad()
                        guard (0xDC00 ... 0xDFFF).contains(second) else {
                            throw failure("invalid low surrogate")
                        }
                        scalarValue = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
                    } else {
                        guard !(0xDC00 ... 0xDFFF).contains(first) else {
                            throw failure("unexpected low surrogate")
                        }
                        scalarValue = first
                    }
                    guard let scalar = Unicode.Scalar(scalarValue) else {
                        throw failure("invalid Unicode scalar")
                    }
                    result.unicodeScalars.append(scalar)
                default:
                    throw failure("invalid string escape")
                }
                _ = try checked(result)
            case 0x00 ... 0x1F:
                throw failure("unescaped control character in string")
            default:
                segment.append(byte)
            }
        }
        throw failure("unterminated string")
    }

    private mutating func parseHexQuad() throws -> UInt32 {
        var result: UInt32 = 0
        for _ in 0 ..< 4 {
            guard let byte = peek(), let nibble = hexNibble(byte) else {
                throw failure("invalid Unicode escape")
            }
            index += 1
            result = result * 16 + UInt32(nibble)
        }
        return result
    }

    private mutating func parseNumber(path: String) throws -> HanlinJSONValue {
        let start = index
        _ = consumeIf(0x2D)
        guard let first = peek() else {
            throw failure("incomplete number")
        }
        if first == 0x30 {
            index += 1
            if let next = peek(), (0x30 ... 0x39).contains(next) {
                throw failure("leading zero in number")
            }
        } else {
            guard (0x31 ... 0x39).contains(first) else {
                throw failure("invalid integer part")
            }
            consumeDigits()
        }

        var isBinary64 = false
        if consumeIf(0x2E) {
            isBinary64 = true
            guard let digit = peek(), (0x30 ... 0x39).contains(digit) else {
                throw failure("fraction requires a digit")
            }
            consumeDigits()
        }
        if let exponent = peek(), exponent == 0x65 || exponent == 0x45 {
            isBinary64 = true
            index += 1
            if let sign = peek(), sign == 0x2B || sign == 0x2D {
                index += 1
            }
            guard let digit = peek(), (0x30 ... 0x39).contains(digit) else {
                throw failure("exponent requires a digit")
            }
            consumeDigits()
        }

        guard let token = String(bytes: bytes[start ..< index], encoding: .utf8) else {
            throw failure("number is not UTF-8")
        }
        if !isBinary64 {
            guard let value = Int64(token) else {
                throw HanlinContractError.integerOutOfRange(
                    value: token,
                    destination: "Int64",
                    path: path
                )
            }
            return .integer(value)
        }
        guard let value = Double(token), value.isFinite else {
            throw HanlinContractError.invalidNumber(Double(token) ?? .infinity)
        }
        return .number(value)
    }

    private mutating func consumeDigits() {
        while let byte = peek(), (0x30 ... 0x39).contains(byte) {
            index += 1
        }
    }

    private mutating func consumeLiteral(_ literal: String) throws {
        let expected = Array(literal.utf8)
        guard index + expected.count <= bytes.count,
              Array(bytes[index ..< index + expected.count]) == expected
        else {
            throw failure("invalid literal")
        }
        index += expected.count
    }

    private mutating func skipWhitespace() {
        while let byte = peek(), byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
            index += 1
        }
    }

    private mutating func consumeIf(_ byte: UInt8) -> Bool {
        guard peek() == byte else { return false }
        index += 1
        return true
    }

    private func peek() -> UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private func failure(_ reason: String) -> HanlinContractError {
        .invalidJSON(reason: reason, byteOffset: index)
    }

    private func append(_ component: String, to path: String) -> String {
        let escaped = component
            .replacingOccurrences(of: "~", with: "~0")
            .replacingOccurrences(of: "/", with: "~1")
        return path + "/" + escaped
    }

    private func hexNibble(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30 ... 0x39: byte - 0x30
        case 0x41 ... 0x46: byte - 0x41 + 10
        case 0x61 ... 0x66: byte - 0x61 + 10
        default: nil
        }
    }
}

public indirect enum HanlinValueSchema: Hashable, Sendable {
    case `any`
    case null
    case boolean
    case integer(minimum: Int64?, maximum: Int64?)
    case number(minimum: Double?, maximum: Double?)
    case string(minLength: Int?, maxLength: Int?, pattern: String?)
    case data(maxBytes: Int?)
    case array(items: HanlinValueSchema, minItems: Int?, maxItems: Int?)
    case object(
        properties: [String: HanlinValueSchema],
        required: Set<String>,
        additionalProperties: Bool
    )
    case oneOf([HanlinValueSchema])
    case enumeration([HanlinValue])

    public func validateDefinition() throws {
        switch self {
        case .any, .null, .boolean:
            return
        case let .integer(minimum, maximum):
            if let minimum, let maximum, minimum > maximum {
                throw HanlinContractError.invalidSchema(reason: "integer minimum exceeds maximum")
            }
        case let .number(minimum, maximum):
            if let minimum, !minimum.isFinite { throw HanlinContractError.invalidNumber(minimum) }
            if let maximum, !maximum.isFinite { throw HanlinContractError.invalidNumber(maximum) }
            if let minimum, let maximum, minimum > maximum {
                throw HanlinContractError.invalidSchema(reason: "number minimum exceeds maximum")
            }
        case let .string(minimum, maximum, _):
            try Self.validateBounds(minimum: minimum, maximum: maximum, label: "string length")
        case let .data(maximum):
            if let maximum, maximum < 0 {
                throw HanlinContractError.invalidSchema(reason: "data maximum byte count is negative")
            }
        case let .array(items, minimum, maximum):
            try Self.validateBounds(minimum: minimum, maximum: maximum, label: "array item count")
            try items.validateDefinition()
        case let .object(properties, required, _):
            let unknownRequired = required.subtracting(Set(properties.keys))
            guard unknownRequired.isEmpty else {
                throw HanlinContractError.invalidSchema(
                    reason: "required object properties are undeclared: \(unknownRequired.sorted())"
                )
            }
            for schema in properties.values { try schema.validateDefinition() }
        case let .oneOf(schemas):
            guard !schemas.isEmpty else {
                throw HanlinContractError.invalidSchema(reason: "oneOf requires at least one schema")
            }
            for schema in schemas { try schema.validateDefinition() }
        case let .enumeration(values):
            guard !values.isEmpty else {
                throw HanlinContractError.invalidSchema(reason: "enumeration requires at least one value")
            }
        }
    }

    private static func validateBounds(minimum: Int?, maximum: Int?, label: String) throws {
        if let minimum, minimum < 0 {
            throw HanlinContractError.invalidSchema(reason: "\(label) minimum is negative")
        }
        if let maximum, maximum < 0 {
            throw HanlinContractError.invalidSchema(reason: "\(label) maximum is negative")
        }
        if let minimum, let maximum, minimum > maximum {
            throw HanlinContractError.invalidSchema(reason: "\(label) minimum exceeds maximum")
        }
    }
}

extension HanlinValueSchema: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, minimum, maximum, minLength, maxLength, pattern, maxBytes
        case items, minItems, maxItems, properties, required, additionalProperties
        case schemas, values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "any": self = .any
        case "null": self = .null
        case "boolean": self = .boolean
        case "integer":
            self = .integer(
                minimum: try container.decodeIfPresent(Int64.self, forKey: .minimum),
                maximum: try container.decodeIfPresent(Int64.self, forKey: .maximum)
            )
        case "number":
            self = .number(
                minimum: try container.decodeIfPresent(Double.self, forKey: .minimum),
                maximum: try container.decodeIfPresent(Double.self, forKey: .maximum)
            )
        case "string":
            self = .string(
                minLength: try container.decodeIfPresent(Int.self, forKey: .minLength),
                maxLength: try container.decodeIfPresent(Int.self, forKey: .maxLength),
                pattern: try container.decodeIfPresent(String.self, forKey: .pattern)
            )
        case "data":
            self = .data(maxBytes: try container.decodeIfPresent(Int.self, forKey: .maxBytes))
        case "array":
            self = .array(
                items: try container.decode(HanlinValueSchema.self, forKey: .items),
                minItems: try container.decodeIfPresent(Int.self, forKey: .minItems),
                maxItems: try container.decodeIfPresent(Int.self, forKey: .maxItems)
            )
        case "object":
            self = .object(
                properties: try container.decode([String: HanlinValueSchema].self, forKey: .properties),
                required: Set(try container.decodeIfPresent([String].self, forKey: .required) ?? []),
                additionalProperties: try container.decodeIfPresent(Bool.self, forKey: .additionalProperties) ?? false
            )
        case "oneOf":
            self = .oneOf(try container.decode([HanlinValueSchema].self, forKey: .schemas))
        case "enumeration":
            self = .enumeration(try container.decode([HanlinValue].self, forKey: .values))
        case let type:
            throw HanlinContractError.invalidSchema(reason: "unknown Hanlin value schema type '\(type)'")
        }
        try validateDefinition()
    }

    public func encode(to encoder: Encoder) throws {
        try validateDefinition()
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .any: try container.encode("any", forKey: .type)
        case .null: try container.encode("null", forKey: .type)
        case .boolean: try container.encode("boolean", forKey: .type)
        case let .integer(minimum, maximum):
            try container.encode("integer", forKey: .type)
            try container.encodeIfPresent(minimum, forKey: .minimum)
            try container.encodeIfPresent(maximum, forKey: .maximum)
        case let .number(minimum, maximum):
            try container.encode("number", forKey: .type)
            try container.encodeIfPresent(minimum, forKey: .minimum)
            try container.encodeIfPresent(maximum, forKey: .maximum)
        case let .string(minimum, maximum, pattern):
            try container.encode("string", forKey: .type)
            try container.encodeIfPresent(minimum, forKey: .minLength)
            try container.encodeIfPresent(maximum, forKey: .maxLength)
            try container.encodeIfPresent(pattern, forKey: .pattern)
        case let .data(maximum):
            try container.encode("data", forKey: .type)
            try container.encodeIfPresent(maximum, forKey: .maxBytes)
        case let .array(items, minimum, maximum):
            try container.encode("array", forKey: .type)
            try container.encode(items, forKey: .items)
            try container.encodeIfPresent(minimum, forKey: .minItems)
            try container.encodeIfPresent(maximum, forKey: .maxItems)
        case let .object(properties, required, additionalProperties):
            try container.encode("object", forKey: .type)
            try container.encode(properties, forKey: .properties)
            try container.encode(required.sorted(), forKey: .required)
            try container.encode(additionalProperties, forKey: .additionalProperties)
        case let .oneOf(schemas):
            try container.encode("oneOf", forKey: .type)
            try container.encode(schemas, forKey: .schemas)
        case let .enumeration(values):
            try container.encode("enumeration", forKey: .type)
            try container.encode(values, forKey: .values)
        }
    }
}
