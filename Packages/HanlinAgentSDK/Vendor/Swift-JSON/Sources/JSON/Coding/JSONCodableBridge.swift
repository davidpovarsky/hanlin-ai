// SPDX-License-Identifier: Apache-2.0
import Foundation
/// External decoders may already have rounded numbers or collapsed scalar-distinct keys.
/// Use JSONParser and JSONValueDecoder for complete source fidelity.
extension JSONNumber: Codable {
    /// Decodes through the supplied coder. Native coding preserves exact payloads;
    /// foreign coders determine available number and key fidelity.
    ///
    /// - Throws: Type/conversion errors or the supplied coder's errors.
    ///
    /// - Parameters:
    ///   - decoder: The supplied decoder; external coders determine their available source fidelity.
    public init(from decoder: any Decoder) throws {
        if let native = decoder as? JSONNativeDecoder {
            guard case .number(let number) = native.value else { throw native.mismatch(Self.self) }; self = number; return
        }
        let container = try decoder.singleValueContainer()
        if let integer = try? container.decode(Int64.self) { self.init(integer: integer); return }
        if let integer = try? container.decode(UInt64.self) { self.init(integer: integer); return }
        if var decimal = try? container.decode(Decimal.self), !decimal.isNaN {
            try self.init(parsing: JSONDecimalBridge.text(&decimal)); return
        }
        throw DecodingError.typeMismatch(Self.self, .init(codingPath: decoder.codingPath, debugDescription: "Exact Int64, UInt64 or Decimal required"))
    }
    /// Encodes through the supplied coder; native JSON coding preserves exact payloads.
    ///
    /// Foreign encoders determine their available numeric and key fidelity. Their
    /// work is outside the native operation meter.
    /// - Throws: The supplied coder's errors, or exact number conversion failure.
    ///
    /// - Parameters:
    ///   - encoder: The supplied encoder; external coders determine available numeric/key fidelity.
    public func encode(to encoder: any Encoder) throws {
        if let native = encoder as? JSONNativeEncoder { try native.set(.number(self)); return }
        var container = encoder.singleValueContainer()
        if let integer = try? integer(as: Int64.self) { try container.encode(integer); return }
        if let integer = try? integer(as: UInt64.self) { try container.encode(integer); return }
        do { try container.encode(decimalValue()) }
        catch { throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath, debugDescription: "External encoder cannot represent exact number", underlyingError: error)) }
    }
}
extension JSON: Codable {
    /// Decodes through the supplied coder. Native coding preserves exact payloads;
    /// foreign coders determine available number and key fidelity.
    ///
    /// - Throws: Type/conversion errors or the supplied coder's errors.
    ///
    /// - Parameters:
    ///   - decoder: The supplied decoder; external coders determine their available source fidelity.
    public init(from decoder: any Decoder) throws {
        if let native = decoder as? JSONNativeDecoder { self = native.value; return }
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let boolean = try? container.decode(Bool.self) { self = .boolean(boolean); return }
        if let string = try? container.decode(String.self) { self = .string(string); return }
        if let number = try? container.decode(JSONNumber.self) { self = .number(number); return }
        if var array = try? decoder.unkeyedContainer() {
            var values: [JSON] = []
            while !array.isAtEnd { values.append(try array.decode(JSON.self)) }
            self = .array(values); return
        }
        let object = try decoder.container(keyedBy: JSONCodingKey.self)
        var members: [JSONMember] = []
        for key in object.allKeys { members.append(JSONMember(key.stringValue, value: try object.decode(JSON.self, forKey: key))) }
        self = .object(try JSONObject(members: members))
    }
    /// Encodes through the supplied coder; native JSON coding preserves exact payloads.
    ///
    /// Foreign encoders determine their available numeric and key fidelity. Their
    /// work is outside the native operation meter.
    /// - Throws: The supplied coder's errors, or exact number conversion failure.
    ///
    /// - Parameters:
    ///   - encoder: The supplied encoder; external coders determine available numeric/key fidelity.
    public func encode(to encoder: any Encoder) throws {
        if let native = encoder as? JSONNativeEncoder { try native.set(self); return }
        switch self {
        case .null: var c = encoder.singleValueContainer(); try c.encodeNil()
        case .boolean(let value): var c = encoder.singleValueContainer(); try c.encode(value)
        case .string(let value): var c = encoder.singleValueContainer(); try c.encode(value)
        case .number(let value): try value.encode(to: encoder)
        case .array(let values): var c = encoder.unkeyedContainer(); for value in values { try c.encode(value) }
        case .object(let object):
            var c = encoder.container(keyedBy: JSONCodingKey.self)
            for member in object { try c.encode(member.value, forKey: JSONCodingKey(member.key.string)) }
        }
    }
}

extension JSONObject: Codable {
    /// Decodes through the supplied coder. Native coding preserves exact payloads;
    /// foreign coders determine available number and key fidelity.
    ///
    /// - Throws: Type/conversion errors or the supplied coder's errors.
    ///
    /// - Parameters:
    ///   - decoder: The supplied decoder; external coders determine their available source fidelity.
    public init(from decoder: any Decoder) throws {
        let value = try JSON(from: decoder)
        guard case .object(let object) = value else {
            throw DecodingError.typeMismatch(Self.self, .init(codingPath: decoder.codingPath,
                debugDescription: "JSON object required"))
        }
        self = object
    }
    /// Encodes through the supplied coder; native JSON coding preserves exact payloads.
    ///
    /// Foreign encoders determine their available numeric and key fidelity. Their
    /// work is outside the native operation meter.
    /// - Throws: The supplied coder's errors, or exact number conversion failure.
    ///
    /// - Parameters:
    ///   - encoder: The supplied encoder; external coders determine available numeric/key fidelity.
    public func encode(to encoder: any Encoder) throws { try JSON.object(self).encode(to: encoder) }
}

extension KeyedEncodingContainer {
    /// Omits absent fields, encodes null explicitly, and encodes present values.
    ///
    /// - Throws: The underlying encoder or caller value error.
    ///
    /// - Parameters:
    ///   - presence: Absent, explicit null or a present non-null value.
    ///   - key: The destination key.
    public mutating func encodePresence<T: Encodable>(_ presence: JSONPresence<T>, forKey key: Key) throws {
        switch presence { case .absent: break; case .null: try encodeNil(forKey: key); case .value(let value): try encode(value, forKey: key) }
    }
}
extension KeyedDecodingContainer {
    /// Distinguishes a missing key, explicit null and a decoded non-null value.
    ///
    /// - Returns: The field presence without manufacturing a default.
    /// - Throws: The underlying decoder or caller type error.
    ///
    /// - Parameters:
    ///   - type: The target Swift type.
    ///   - key: The destination key.
    public func decodePresence<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> JSONPresence<T> {
        if !contains(key) { return .absent }
        if try decodeNil(forKey: key) { return .null }
        return .value(try decode(type, forKey: key))
    }
}
extension JSONParser {
    /// Decodes a model with native value-based Codable.
    ///
    /// Integer conversions are exact; binary floating results require finite rounding.
    /// - Returns: The caller model.
    /// - Throws: Type/conversion errors, collapsed scalar keys, caller errors, resource failure or cancellation.
    ///
    /// - Parameters:
    ///   - type: The target Swift type.
    ///   - data: The strict UTF-8 input bytes.
    ///   - coding: Native Codable strategies; composed byte coding intersects these limits with facade limits.
    public func decode<T: Decodable>(_ type: T.Type, from data: Data, coding: JSONCodingOptions = .init()) throws -> T {
        let meter = try JSONWorkMeter(limits: try options.limits.intersection(coding.limits), domain: .coding)
        let state = JSONCodingState(options: coding, meter: meter)
        var bytes: [UInt8] = []
        for byte in data { try state.meter.work(); try state.meter.require(.inputBytes, UInt64(bytes.count) + 1); try state.meter.retain(1); bytes.append(byte) }
        let value = try parse(bytes, meter: &state.meter)
        let result = try JSONNativeDecoder(value: value, state: state, codingPath: []).decode(type)
        try state.check(); return result
    }
}
extension JSONWriter {
    /// Encodes a Codable value using native exact JSON coding.
    ///
    /// Caller callback errors propagate; encoding and any composed writing share work.
    /// - Returns: The complete strict UTF-8 JSON document.
    /// - Throws: Coding, conversion, resource or configuration errors, or cancellation.
    ///
    /// - Parameters:
    ///   - value: The Encodable model to encode before writing under one cumulative budget.
    ///   - coding: Native Codable strategies; composed byte coding intersects these limits with facade limits.
    public func encode<T: Encodable>(_ value: T, coding: JSONCodingOptions = .init()) throws -> Data {
        let meter = try JSONWorkMeter(limits: try options.limits.intersection(coding.limits), domain: .coding)
        let state = JSONCodingState(options: coding, meter: meter)
        let json = try JSONValueEncoder.encode(value, state: state)
        let bytes = try write(json, meter: &state.meter)
        for _ in bytes { try state.meter.work(); try state.meter.retain(1) }
        return Data(bytes)
    }
}
