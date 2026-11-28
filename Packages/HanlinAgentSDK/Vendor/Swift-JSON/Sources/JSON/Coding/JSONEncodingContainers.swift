// SPDX-License-Identifier: Apache-2.0
import Foundation
struct JSONKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let encoder: JSONNativeEncoder
    var codingPath: [any CodingKey] { encoder.codingPath }
    private func child(_ key: any CodingKey) throws -> JSONNativeEncoder {
        try encoder.state.check()
        guard case .keyed(let storage) = encoder.box.storage else { throw JSONFailure(.configuration, code: .invalidOperation) }
        let child = try encoder.child(key)
        try storage.set(JSONKey(key.stringValue, meter: &encoder.state.meter), box: child.box, meter: &encoder.state.meter)
        return child
    }
    mutating func encodeNil(forKey key: Key) throws { try child(key).set(.null) }
    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws { try child(key).encode(value) }
    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
        var result: JSONNativeEncoder = encoder
        encoder.state.latch { result = try child(key) }
        return result.container(keyedBy: type)
    }
    mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        var result: JSONNativeEncoder = encoder
        encoder.state.latch { result = try child(key) }
        return result.unkeyedContainer()
    }
    mutating func superEncoder() -> any Encoder {
        var result: JSONNativeEncoder = encoder
        encoder.state.latch { result = try child(JSONCodingKey("super")) }
        return result
    }
    mutating func superEncoder(forKey key: Key) -> any Encoder {
        var result: JSONNativeEncoder = encoder
        encoder.state.latch { result = try child(key) }
        return result
    }
}
struct JSONUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    let encoder: JSONNativeEncoder
    var codingPath: [any CodingKey] { encoder.codingPath }
    var count: Int { if case .unkeyed(let boxes) = encoder.box.storage { return boxes.count }; return 0 }
    private func child() throws -> JSONNativeEncoder {
        try encoder.state.check()
        guard case .unkeyed(var boxes) = encoder.box.storage else { throw JSONFailure(.configuration, code: .invalidOperation) }
        try encoder.state.meter.require(.arrayItems, UInt64(boxes.count) + 1)
        let child = try encoder.child(JSONCodingKey(index: boxes.count))
        for _ in boxes { try encoder.state.meter.work() }
        try encoder.state.meter.retain(JSONLogicalWeights.arraySlot); boxes.append(child.box)
        encoder.box.storage = .unkeyed(boxes); return child
    }
    mutating func encodeNil() throws { try child().set(.null) }
    mutating func encode<T: Encodable>(_ value: T) throws { try child().encode(value) }
    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
        var result: JSONNativeEncoder = encoder
        encoder.state.latch { result = try child() }
        return result.container(keyedBy: type)
    }
    mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        var result: JSONNativeEncoder = encoder
        encoder.state.latch { result = try child() }
        return result.unkeyedContainer()
    }
    mutating func superEncoder() -> any Encoder {
        var result: JSONNativeEncoder = encoder
        encoder.state.latch { result = try child() }
        return result
    }
}
struct JSONSingleEncodingContainer: SingleValueEncodingContainer {
    let encoder: JSONNativeEncoder
    var codingPath: [any CodingKey] { encoder.codingPath }
    mutating func encodeNil() throws { try encoder.set(.null) }
    mutating func encode<T: Encodable>(_ value: T) throws { try encoder.encode(value) }
    mutating func encode(_ value: Bool) throws { try encoder.set(.boolean(value)) }
    mutating func encode(_ value: String) throws { try encoder.set(.string(value)) }
    mutating func encode(_ value: Double) throws { try encoder.floating(value) }
    mutating func encode(_ value: Float) throws { try encoder.floating(value) }
    mutating func encode(_ value: Int) throws { try encoder.set(.number(JSONNumber(integer: value))) }
    mutating func encode(_ value: Int8) throws { try encoder.set(.number(JSONNumber(integer: value))) }
    mutating func encode(_ value: Int16) throws { try encoder.set(.number(JSONNumber(integer: value))) }
    mutating func encode(_ value: Int32) throws { try encoder.set(.number(JSONNumber(integer: value))) }
    mutating func encode(_ value: Int64) throws { try encoder.set(.number(JSONNumber(integer: value))) }
    mutating func encode(_ value: UInt) throws { try encoder.set(.number(JSONNumber(integer: value))) }
    mutating func encode(_ value: UInt8) throws { try encoder.set(.number(JSONNumber(integer: value))) }
    mutating func encode(_ value: UInt16) throws { try encoder.set(.number(JSONNumber(integer: value))) }
    mutating func encode(_ value: UInt32) throws { try encoder.set(.number(JSONNumber(integer: value))) }
    mutating func encode(_ value: UInt64) throws { try encoder.set(.number(JSONNumber(integer: value))) }
}
