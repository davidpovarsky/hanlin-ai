// SPDX-License-Identifier: Apache-2.0
import Foundation
/// An immutable native Codable encoder that produces exact JSON values.
///
/// JSON, JSONObject and JSONNumber bypass lossy foreign serialization. Arbitrary
/// `Encodable` callbacks execute synchronously and their errors propagate.
public struct JSONValueEncoder: Sendable {
    /// The immutable configuration used to create each invocation.
    public let options: JSONCodingOptions
    /// Creates an immutable native encoder facade with invocation-owned mutable state.
    ///
    /// - Parameters:
    ///   - options: The value configuration used by this facade or operation.
    public init(options: JSONCodingOptions = .init()) { self.options = options }
    /// Encodes a Codable value using native exact JSON coding.
    ///
    /// Caller callback errors propagate; encoding and any composed writing share work.
    /// - Returns: The encoded value or UTF-8 bytes, as declared by this overload.
    /// - Throws: Coding, conversion, resource or configuration errors, or cancellation.
    ///
    /// - Parameters:
    ///   - value: The Encodable model; caller encode callbacks propagate their own errors.
    public func encode<T: Encodable>(_ value: T) throws -> JSON { try encodeWithReport(value).result }
    /// Encodes a Codable value with successful native operation accounting.
    ///
    /// - Returns: An exact JSON value and charged library work. Caller callback work is outside the quota.
    /// - Throws: Coding or caller errors, resource failure, or cancellation.
    ///
    /// - Parameters:
    ///   - value: The Encodable model; caller encode callbacks propagate their own errors.
    public func encodeWithReport<T: Encodable>(_ value: T) throws -> JSONOperationReport<JSON> {
        let meter = try JSONWorkMeter(limits: options.limits, domain: .coding)
        let state = JSONCodingState(options: options, meter: meter)
        let value = try Self.encode(value, state: state)
        return .init(result: value, statistics: state.meter.statistics())
    }
    package static func encode<T: Encodable>(_ value: T, state: JSONCodingState) throws -> JSON {
        try state.check()
        let box = JSONEncodingBox()
        try state.meter.retain(JSONLogicalWeights.node)
        try JSONNativeEncoder(box: box, state: state, codingPath: []).encode(value)
        try state.check()
        let result = try box.materialize(state: state)
        try JSONAdmission.value(result, meter: &state.meter)
        return result
    }
}
/// Exclusive mutable keyed storage avoids extracting/copying the whole member
/// array for every field. This object belongs to one native coding invocation.
package final class JSONKeyedEncodingStorage {
    package private(set) var members: [(JSONKey, JSONEncodingBox)] = []
    private var index = JSONExactKeyIndex()
    private var capacity = 0
    package func set(_ key: JSONKey, box: JSONEncodingBox, meter: inout JSONWorkMeter) throws {
        if let position = try index.find(key, meter: &meter) {
            try meter.work(); members[position] = (key, box); return
        }
        try meter.require(.objectMembers, UInt64(members.count) + 1)
        if members.count == capacity {
            let (doubled, overflow) = capacity.multipliedReportingOverflow(by: 2)
            guard !overflow else { throw JSONFailure(.resource, code: .counterOverflow) }
            let next = min(Int(meter.limits[.objectMembers]), max(1, doubled))
            let (bytes, byteOverflow) = UInt64(next).multipliedReportingOverflow(by: JSONLogicalWeights.member)
            guard !byteOverflow else { throw JSONFailure(.resource, code: .counterOverflow) }
            try meter.retain(bytes)
            do { try meter.work(UInt64(members.count) + 1) }
            catch { try meter.release(bytes); throw error }
            members.reserveCapacity(next)
            try meter.release(UInt64(capacity) * JSONLogicalWeights.member)
            capacity = next
        }
        guard try index.insert(key, position: members.count, meter: &meter) else { throw JSONFailure(.syntax, code: .duplicateKey) }
        members.append((key, box))
    }
}
package final class JSONEncodingBox {
    package enum Storage { case unset, value(JSON), keyed(JSONKeyedEncodingStorage), unkeyed([JSONEncodingBox]) }
    package var storage: Storage = .unset
    package func materialize(state: JSONCodingState) throws -> JSON {
        enum Step { case node(JSONEncodingBox), object([JSONKey]), array(Int) }
        var pending: [Step] = [.node(self)], results: [JSON] = []
        while let step = pending.popLast() {
            try state.meter.work()
            switch step {
            case .node(let node):
                switch node.storage {
                case .unset: throw EncodingError.invalidValue("unset", .init(codingPath: [], debugDescription: "No value was encoded"))
                case .value(let value): results.append(value)
                case .keyed(let storage):
                    var keys: [JSONKey] = []
                    for (key, _) in storage.members { try state.meter.work(); try state.meter.retain(JSONLogicalWeights.arraySlot); keys.append(key) }
                    pending.append(.object(keys))
                    for (_, box) in storage.members.reversed() { try state.meter.work(); try state.meter.retain(16); pending.append(.node(box)) }
                case .unkeyed(let boxes):
                    pending.append(.array(boxes.count))
                    for box in boxes.reversed() { try state.meter.work(); try state.meter.retain(16); pending.append(.node(box)) }
                }
            case .object(let keys):
                var members: [JSONMember] = []
                for (key, value) in zip(keys, results.suffix(keys.count)) {
                    try state.meter.work(); try state.meter.retain(JSONLogicalWeights.member); members.append(JSONMember(key, value: value))
                }
                results.removeLast(keys.count); results.append(.object(try JSONObject.indexed(admitted: members, meter: &state.meter)))
            case .array(let count):
                var values: [JSON] = []
                for value in results.suffix(count) { try state.meter.work(); try state.meter.retain(JSONLogicalWeights.arraySlot); values.append(value) }
                results.removeLast(count); results.append(.array(values))
            }
        }
        guard results.count == 1 else { throw JSONFailure(.configuration, code: .invalidOperation) }
        return results[0]
    }
}
package final class JSONNativeEncoder: Encoder {
    package let box: JSONEncodingBox
    package let state: JSONCodingState
    package let codingPath: [any CodingKey]
    package var userInfo: [CodingUserInfoKey: Any] { state.bridgedUserInfo }
    package init(box: JSONEncodingBox, state: JSONCodingState, codingPath: [any CodingKey]) { self.box = box; self.state = state; self.codingPath = codingPath }
    package func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        state.latch {
            try state.check()
            switch box.storage {
            case .unset: box.storage = .keyed(JSONKeyedEncodingStorage())
            case .keyed: break
            default: throw EncodingError.invalidValue("container", .init(codingPath: codingPath, debugDescription: "Conflicting containers"))
            }
        }
        return KeyedEncodingContainer(JSONKeyedEncodingContainer<Key>(encoder: self))
    }
    package func unkeyedContainer() -> any UnkeyedEncodingContainer {
        state.latch {
            try state.check()
            switch box.storage {
            case .unset: box.storage = .unkeyed([])
            case .unkeyed: break
            default: throw EncodingError.invalidValue("container", .init(codingPath: codingPath, debugDescription: "Conflicting containers"))
            }
        }
        return JSONUnkeyedEncodingContainer(encoder: self)
    }
    package func singleValueContainer() -> any SingleValueEncodingContainer { JSONSingleEncodingContainer(encoder: self) }
    package func set(_ value: JSON) throws {
        try state.check(); try JSONAdmission.value(value, meter: &state.meter, owned: true)
        guard case .unset = box.storage else { throw EncodingError.invalidValue(value, .init(codingPath: codingPath, debugDescription: "Value encoded twice")) }
        box.storage = .value(value)
    }
    package func encode<T: Encodable>(_ value: T) throws {
        if let json = value as? JSON { try set(json) }
        else if let number = value as? JSONNumber { try set(.number(number)) }
        else if let data = value as? Data, state.options.dataStrategy == .base64 {
            let encoded = try JSONBase64.encode(data,meter: &state.meter)
            try set(.string(encoded.text)); try state.meter.release(encoded.bytes)
        } else if let date = value as? Date, state.options.dateStrategy != .deferredToDate {
            if state.options.dateStrategy == .secondsSince1970 { try floating(date.timeIntervalSince1970) }
            else {
                let seconds = date.timeIntervalSince1970
                guard seconds.isFinite,seconds >= -62_167_219_200,seconds < 253_402_300_800 else {
                    throw EncodingError.invalidValue(date,.init(codingPath: codingPath,debugDescription: "ISO-8601 year must be 0000...9999"))
                }
                try state.meter.retain(128); try state.meter.checkpoint()
                let text = date.ISO8601Format(.iso8601.year().month().day().timeZone(separator: .colon).time(includingFractionalSeconds: true))
                try state.meter.checkpoint(); try set(.string(text)); try state.meter.release(128)
            }
        } else { try value.encode(to: self) }
    }
    package func floating<T: BinaryFloatingPoint>(_ value: T) throws {
        guard value.isFinite else { throw EncodingError.invalidValue(value, .init(codingPath: codingPath, debugDescription: "Nonfinite JSON number")) }
        try set(.number(JSONNumber.parse(String(describing: value).utf8, meter: &state.meter)))
    }
    package func child(_ key: any CodingKey) throws -> JSONNativeEncoder {
        let path = try state.path(codingPath, appending: key)
        try state.meter.retain(JSONLogicalWeights.node)
        return .init(box: JSONEncodingBox(), state: state, codingPath: path)
    }
}
