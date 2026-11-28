// SPDX-License-Identifier: Apache-2.0
import Foundation
struct JSONKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let decoder: JSONNativeDecoder
    let object: JSONObject
    var codingPath: [any CodingKey] { decoder.codingPath }
    var allKeys: [Key] {
        var keys: [Key] = []
        decoder.state.latch {
            for member in object {
                try decoder.state.meter.work(); try decoder.state.meter.retain(16)
                if let key = Key(stringValue: member.key.string) {
                    guard try JSONComparison.textEquals(key.stringValue, member.key.string, meter: &decoder.state.meter) else {
                        throw DecodingError.dataCorrupted(.init(codingPath: codingPath,
                            debugDescription: "CodingKey projection changes the exact JSON member spelling"))
                    }
                    keys.append(key)
                }
            }
        }
        return keys
    }
    func contains(_ key: Key) -> Bool {
        var result = false
        decoder.state.latch { result = try object.lookup(key.stringValue, meter: &decoder.state.meter) != nil }
        return result
    }
    private func child(_ key: any CodingKey) throws -> JSONNativeDecoder {
        try decoder.state.check()
        guard let value = try object.lookup(key.stringValue, meter: &decoder.state.meter) else {
            throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Required JSON member absent"))
        }
        return try decoder.child(value, key: key)
    }
    func decodeNil(forKey key: Key) throws -> Bool { try child(key).value.isNull }
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T { try child(key).decode(type) }
    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> { try child(key).container(keyedBy: type) }
    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer { try child(key).unkeyedContainer() }
    func superDecoder() throws -> any Decoder { try child(JSONCodingKey("super")) }
    func superDecoder(forKey key: Key) throws -> any Decoder { try child(key) }
}
struct JSONUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    let decoder: JSONNativeDecoder
    let values: [JSON]
    var codingPath: [any CodingKey] { decoder.codingPath }
    var count: Int? { values.count }
    var currentIndex: Int = 0
    var isAtEnd: Bool { currentIndex == values.count }
    private func child() throws -> JSONNativeDecoder {
        try decoder.state.check()
        guard !isAtEnd else { throw DecodingError.valueNotFound(JSON.self, .init(codingPath: codingPath, debugDescription: "Unkeyed container exhausted")) }
        return try decoder.child(values[currentIndex], key: JSONCodingKey(index: currentIndex))
    }
    mutating func decodeNil() throws -> Bool {
        let nilValue = try child().value.isNull
        if nilValue { currentIndex += 1 }; return nilValue
    }
    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T { let value = try child().decode(type); currentIndex += 1; return value }
    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> { let value = try child().container(keyedBy: type); currentIndex += 1; return value }
    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer { let value = try child().unkeyedContainer(); currentIndex += 1; return value }
    mutating func superDecoder() throws -> any Decoder { let value = try child(); currentIndex += 1; return value }
}
struct JSONSingleDecodingContainer: SingleValueDecodingContainer {
    let decoder: JSONNativeDecoder
    var codingPath: [any CodingKey] { decoder.codingPath }
    func decodeNil() -> Bool { decoder.value.isNull }
    func decode<T: Decodable>(_ type: T.Type) throws -> T { try decoder.decode(type) }
    func decode(_ type: Bool.Type) throws -> Bool { guard case .boolean(let value) = decoder.value else { throw decoder.mismatch(type) }; return value }
    func decode(_ type: String.Type) throws -> String { guard case .string(let value) = decoder.value else { throw decoder.mismatch(type) }; return value }
    func decode(_ type: Double.Type) throws -> Double { try decoder.floating(type) }
    func decode(_ type: Float.Type) throws -> Float { try decoder.floating(type) }
    func decode(_ type: Int.Type) throws -> Int { try decoder.integer(type) }
    func decode(_ type: Int8.Type) throws -> Int8 { try decoder.integer(type) }
    func decode(_ type: Int16.Type) throws -> Int16 { try decoder.integer(type) }
    func decode(_ type: Int32.Type) throws -> Int32 { try decoder.integer(type) }
    func decode(_ type: Int64.Type) throws -> Int64 { try decoder.integer(type) }
    func decode(_ type: UInt.Type) throws -> UInt { try decoder.integer(type) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try decoder.integer(type) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try decoder.integer(type) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try decoder.integer(type) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try decoder.integer(type) }
}
