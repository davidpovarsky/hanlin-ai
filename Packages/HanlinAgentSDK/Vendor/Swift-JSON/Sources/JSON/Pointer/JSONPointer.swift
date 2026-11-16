// SPDX-License-Identifier: Apache-2.0
import Foundation
/// An RFC 6901 Pointer with exact decoded-scalar tokens.
///
/// Object tokens remain keys even when numeric. Array evaluation requires strict
/// indices; `-` is a Patch append token and is not a resolvable array index.
public struct JSONPointer: Sendable, Hashable {
    /// Decoded Pointer tokens in traversal order, preserving scalar spelling.
    public let tokens: [JSONKey]
    /// Admits RFC 6901 text or supplied decoded tokens under finite Pointer limits.
    ///
    /// - Throws: Invalid Pointer syntax, capacity/work failure or cancellation.
    ///
    /// - Parameters:
    ///   - text: Encoded input text admitted without repair.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public init(parsing text: String, limits: JSONLimits = .balanced) throws {
        var meter = try JSONWorkMeter(limits: limits, domain: .pointer)
        self = try Self.parse(text, meter: &meter)
    }
    /// Admits RFC 6901 text or supplied decoded tokens under finite Pointer limits.
    ///
    /// - Throws: Invalid Pointer syntax, capacity/work failure or cancellation.
    ///
    /// - Parameters:
    ///   - tokens: Decoded scalar tokens, without RFC 6901 escaping.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public init(tokens: [String], limits: JSONLimits = .balanced) throws {
        var meter = try JSONWorkMeter(limits: limits, domain: .pointer)
        self = try Self.fromStrings(tokens, meter: &meter)
    }
    package static func fromStrings(_ tokens: [String], meter: inout JSONWorkMeter) throws -> Self {
        var keys: [JSONKey] = []
        var encodedBytes: UInt64 = 0
        for token in tokens {
            try meter.require(.pointerTokens, UInt64(keys.count) + 1)
            encodedBytes = try meter.adding(.pointerBytes, encodedBytes, 1)
            for byte in token.utf8 { try meter.work(); encodedBytes = try meter.adding(.pointerBytes, encodedBytes, byte == 47 || byte == 126 ? 2 : 1) }
            try meter.retain(16); keys.append(try JSONKey(token, meter: &meter))
        }
        return try Self.decodedTokens(keys, meter: &meter)
    }
    package static func decodedTokens<S: Sequence>(_ tokens: S, meter: inout JSONWorkMeter) throws -> Self where S.Element == JSONKey {
        var keys: [JSONKey] = [], bytes: UInt64 = 0
        for token in tokens {
            try meter.require(.pointerTokens, UInt64(keys.count) + 1)
            bytes = try meter.adding(.pointerBytes, bytes, 1)
            for byte in token.string.utf8 {
                try meter.work(); bytes = try meter.adding(.pointerBytes, bytes, byte == 47 || byte == 126 ? 2 : 1)
                try meter.retain(1)
            }
            try meter.retain(16); keys.append(token)
        }
        return Self(admitted: keys)
    }
    private init(admitted tokens: [JSONKey]) { self.tokens = tokens }
    package static func parse(_ text: String, meter: inout JSONWorkMeter) throws -> Self {
        var bytes: [UInt8] = []
        for byte in text.utf8 {
            try meter.work(); try meter.require(.pointerBytes, UInt64(bytes.count) + 1); try meter.retain(1); bytes.append(byte)
        }
        if bytes.isEmpty { return Self(admitted: []) }
        guard bytes[0] == 47 else { throw JSONFailure(.pointer, code: .invalidPointer) }
        var tokens: [JSONKey] = [], token: [UInt8] = [], index = 1
        while true {
            try meter.work()
            if index == bytes.count || bytes[index] == 47 {
                try meter.require(.pointerTokens, UInt64(tokens.count) + 1); try meter.retain(16)
                try meter.retain(UInt64(token.count))
                tokens.append(try JSONKey(String(decoding: token, as: UTF8.self), meter: &meter))
                try meter.release(UInt64(token.count))
                token = []
                if index == bytes.count { break }; index += 1
            } else if bytes[index] == 126 {
                guard index + 1 < bytes.count && (bytes[index + 1] == 48 || bytes[index + 1] == 49) else {
                    throw JSONFailure(.pointer, code: .invalidPointer)
                }
                try meter.retain(1); token.append(bytes[index + 1] == 48 ? 126 : 47); index += 2
            } else { try meter.retain(1); token.append(bytes[index]); index += 1 }
        }
        try meter.release(UInt64(bytes.count))
        return Self(admitted: tokens)
    }
    /// Parses a # URI fragment by percent-decoding UTF-8 and then RFC 6901 escapes.
    ///
    /// - Returns: Exact decoded Pointer tokens.
    /// - Throws: Invalid fragment/UTF-8/Pointer syntax, resource failure or cancellation.
    ///
    /// - Parameters:
    ///   - fragment: An encoded # URI fragment.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public static func uriFragment(_ fragment: String, limits: JSONLimits = .balanced) throws -> Self {
        var meter = try JSONWorkMeter(limits: limits, domain: .pointer)
        return try uriFragment(fragment, meter: &meter)
    }
    package static func uriFragment(_ fragment: String, meter: inout JSONWorkMeter) throws -> Self {
        try Self.parse(fragmentText(fragment, meter: &meter), meter: &meter)
    }
    package static func fragmentText(_ fragment: String, meter: inout JSONWorkMeter) throws -> String {
        var raw: [UInt8] = []
        for byte in fragment.utf8 { try meter.work(); try meter.require(.pointerBytes, UInt64(raw.count) + 1); try meter.retain(1); raw.append(byte) }
        guard raw.first == 35 else { throw JSONFailure(.pointer, code: .invalidPointer) }
        func hex(_ byte: UInt8) -> UInt8? {
            switch byte { case 48...57: return byte - 48; case 65...70: return byte - 55; case 97...102: return byte - 87; default: return nil }
        }
        var decoded: [UInt8] = [], index = 1
        while index < raw.count {
            try meter.work(); try meter.retain(1)
            if raw[index] == 37 {
                guard index + 2 < raw.count, let h = hex(raw[index + 1]), let l = hex(raw[index + 2]) else { throw JSONFailure(.pointer, code: .invalidPointer) }
                decoded.append(h * 16 + l); index += 3
            } else { decoded.append(raw[index]); index += 1 }
        }
        try meter.retain(UInt64(decoded.count)); try meter.checkpoint()
        guard let text = String(bytes: decoded, encoding: .utf8) else { throw JSONFailure(.pointer, code: .invalidPointer) }
        try meter.checkpoint(); try meter.release(UInt64(raw.count + decoded.count))
        return text
    }
    package func encodedString(meter: inout JSONWorkMeter) throws -> String {
        var bytes: [UInt8] = []
        func append(_ byte: UInt8,meter: inout JSONWorkMeter) throws {
            try meter.work(); try meter.require(.pointerBytes,UInt64(bytes.count)+1); try meter.require(.stringBytes,UInt64(bytes.count)+1)
            try meter.retain(1); bytes.append(byte)
        }
        for token in tokens {
            try append(47,meter: &meter)
            for byte in token.string.utf8 {
                try meter.work()
                if byte == 126 || byte == 47 { try append(126,meter: &meter); try append(byte == 126 ? 48 : 49,meter: &meter) }
                else { try append(byte,meter: &meter) }
            }
        }
        try meter.retain(UInt64(bytes.count)); let text = String(decoding: bytes,as: UTF8.self)
        try meter.release(UInt64(bytes.count)); return text
    }
    /// The RFC 6901 encoded Pointer text; empty text selects the root. Rendering is unmetered.
    public var string: String {
        var result = ""
        for token in tokens {
            result += "/"
            for scalar in token.string.unicodeScalars {
                if scalar.value == 126 { result += "~0" }
                else if scalar.value == 47 { result += "~1" }
                else { result.unicodeScalars.append(scalar) }
            }
        }
        return result
    }
    /// Returns a new Pointer with the supplied key, index or decoded tokens appended.
    ///
    /// - Throws: Invalid indices or Pointer capacity failure, or cancellation.
    ///
    /// - Parameters:
    ///   - key: The exact decoded-scalar member key, without normalization.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public func appending(key: String, limits: JSONLimits = .balanced) throws -> Self {
        var meter = try JSONWorkMeter(limits: limits, domain: .pointer)
        return try appending(key: key, meter: &meter)
    }
    package func appending(key: String, meter: inout JSONWorkMeter) throws -> Self {
        try meter.require(.pointerTokens, UInt64(tokens.count) + 1)
        var encoded: UInt64 = 1
        for byte in key.utf8 { try meter.work(); encoded = try meter.adding(.pointerBytes, encoded, byte == 47 || byte == 126 ? 2 : 1) }
        let suffix = CollectionOfOne(try JSONKey(key, meter: &meter))
        return try Self.decodedTokens([AnySequence(tokens), AnySequence(suffix)].lazy.flatMap { $0 }, meter: &meter)
    }
    /// Returns a new Pointer with the supplied key, index or decoded tokens appended.
    ///
    /// - Throws: Invalid indices or Pointer capacity failure, or cancellation.
    ///
    /// - Parameters:
    ///   - index: A nonnegative runtime array index.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public func appending(index: Int, limits: JSONLimits = .balanced) throws -> Self {
        guard index >= 0 else { throw JSONFailure(.pointer, code: .invalidIndex) }
        return try appending(key: String(index), limits: limits)
    }
    /// Returns a new Pointer with the supplied key, index or decoded tokens appended.
    ///
    /// - Throws: Invalid indices or Pointer capacity failure, or cancellation.
    ///
    /// - Parameters:
    ///   - other: The decoded Pointer tokens to append.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public func appending(_ other: Self, limits: JSONLimits = .balanced) throws -> Self {
        var meter = try JSONWorkMeter(limits: limits, domain: .pointer)
        return try Self.decodedTokens([tokens, other.tokens].lazy.flatMap { $0 }, meter: &meter)
    }
    /// Resolves exact object keys and strict runtime array indices.
    ///
    /// - Returns: The selected value; the empty Pointer selects the root.
    /// - Throws: Invalid index, wrong kind or missing target, resource failure or cancellation.
    ///
    /// - Parameters:
    ///   - value: The value supplied by the caller.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public func resolve(in value: JSON, limits: JSONLimits = .balanced) throws -> JSON {
        var meter = try JSONWorkMeter(limits: limits, domain: .pointer)
        try JSONAdmission.value(value, meter: &meter)
        let admitted = try Self.decodedTokens(tokens, meter: &meter)
        return try admitted.resolve(in: value, meter: &meter)
    }
    package func resolve(in value: JSON, meter: inout JSONWorkMeter) throws -> JSON {
        try meter.require(.pointerTokens, UInt64(tokens.count))
        var current = value
        for token in tokens {
            try meter.work()
            switch current {
            case .object(let object):
                guard let child = try object.lookup(token.string, meter: &meter) else { throw JSONFailure(.pointer, code: .missingTarget) }
                current = child
            case .array(let array): current = array[try Self.arrayIndex(token.string, count: array.count, allowEnd: false, meter: &meter)]
            default: throw JSONFailure(.typeMismatch, code: .wrongKind)
            }
        }
        return current
    }
    /// Package composition distinguishes absence from malformed array-index grammar.
    /// Present JSON null is a non-nil value; wrong-kind/resource errors still throw.
    package func resolveIfPresent(in value: JSON, meter: inout JSONWorkMeter) throws -> JSON? {
        try meter.require(.pointerTokens, UInt64(tokens.count))
        var current = value
        for token in tokens {
            try meter.work()
            switch current {
            case .object(let object):
                guard let child = try object.lookup(token.string, meter: &meter) else { return nil }
                current = child
            case .array(let values):
                let index = try Self.decodedArrayIndex(token.string, meter: &meter)
                guard index < UInt64(values.count) else { return nil }
                current = values[Int(index)]
            default: throw JSONFailure(.typeMismatch, code: .wrongKind)
            }
        }
        return current
    }
    package static func arrayIndex(_ text: String, count: Int, allowEnd: Bool, meter: inout JSONWorkMeter) throws -> Int {
        if text == "-" && allowEnd { return count }
        let index = try Self.decodedArrayIndex(text, meter: &meter)
        guard index < UInt64(count) || (allowEnd && index == UInt64(count)) else { throw JSONFailure(.pointer, code: .invalidIndex) }
        return Int(index)
    }
    package static func decodedArrayIndex(_ text: String, meter: inout JSONWorkMeter) throws -> UInt64 {
        var index: UInt64 = 0, digits = 0
        for byte in text.utf8 {
            try meter.work()
            guard (48...57).contains(byte), digits == 0 || text.utf8.first != 48 else { throw JSONFailure(.pointer, code: .invalidIndex) }
            let (scaled, overflow) = index.multipliedReportingOverflow(by: 10)
            guard !overflow else { throw JSONFailure(.pointer, code: .invalidIndex) }
            let (sum, overflow2) = scaled.addingReportingOverflow(UInt64(byte - 48))
            guard !overflow2 else { throw JSONFailure(.pointer, code: .invalidIndex) }
            index = sum; digits += 1
        }
        guard digits > 0 else { throw JSONFailure(.pointer, code: .invalidIndex) }
        return index
    }
}
