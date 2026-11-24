import Foundation

/// Ordinary JSON at the new author-manifest boundary. The shared value and
/// schema document Codable formats remain tagged, lossless persistence formats.
struct HanlinManifestJSONValue: Codable {
    let value: HanlinJSONValue

    init(_ value: HanlinJSONValue) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        if let object = try? decoder.container(keyedBy: Key.self) {
            value = .object(try HanlinObject(uniqueMembers: object.allKeys.map { key in
                (key: key.stringValue, value: try object.decode(Self.self, forKey: key).value)
            }))
            return
        }
        if var array = try? decoder.unkeyedContainer() {
            var values: [HanlinJSONValue] = []
            while !array.isAtEnd {
                values.append(try array.decode(Self.self).value)
            }
            value = .array(values)
            return
        }
        let scalar = try decoder.singleValueContainer()
        if scalar.decodeNil() {
            value = .null
        } else if let boolean = try? scalar.decode(Bool.self) {
            value = .bool(boolean)
        } else if let integer = try? scalar.decode(Int64.self) {
            value = .integer(integer)
        } else if let number = try? scalar.decode(Double.self) {
            value = try .finiteNumber(number)
        } else {
            value = .string(try scalar.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch value {
        case let .object(members):
            var object = encoder.container(keyedBy: Key.self)
            for (key, value) in members {
                try object.encode(Self(value), forKey: Key(key))
            }
        case let .array(values):
            var array = encoder.unkeyedContainer()
            for value in values { try array.encode(Self(value)) }
        case .null:
            var scalar = encoder.singleValueContainer()
            try scalar.encodeNil()
        case let .bool(value):
            var scalar = encoder.singleValueContainer()
            try scalar.encode(value)
        case let .integer(value):
            var scalar = encoder.singleValueContainer()
            try scalar.encode(value)
        case let .number(value):
            guard value.isFinite else { throw HanlinContractError.invalidNumber(value) }
            var scalar = encoder.singleValueContainer()
            try scalar.encode(value)
        case let .string(value):
            var scalar = encoder.singleValueContainer()
            try scalar.encode(value)
        }
    }

    private struct Key: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init(_ stringValue: String) { self.stringValue = stringValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

extension KeyedDecodingContainer {
    /// Optional manifest fields default only when absent. Explicit null must be
    /// accepted by the declared value type, rather than silently becoming absent.
    func decodeManifestValueIfDeclared<Value: Decodable>(
        _ type: Value.Type, forKey key: Key
    ) throws -> Value? {
        contains(key) ? try decode(type, forKey: key) : nil
    }
}
