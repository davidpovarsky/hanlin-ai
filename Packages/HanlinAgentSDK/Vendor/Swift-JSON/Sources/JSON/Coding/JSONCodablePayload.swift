// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Exact JSON value persistence through a fixed, versioned Codable envelope.
///
/// Version 1 carries `format: "swift-json-value"`, integer `version: 1` and
/// `utf8Base64`: strict standard Base64 of one complete strict UTF-8 document.
/// The inner writer preserves member order, scalar identity and admitted number
/// lexemes. Whitespace, escape spelling and source documents are not persisted.
/// Only validated bytes are stored; opening parses afresh without a hidden DOM.
/// Automatic coding uses finite balanced limits. Foreign coder work is caller
/// work; nesting in the native coder shares its cumulative meter.
public struct JSONCodablePayload: Sendable, Codable {
    private let utf8: Data
    private enum Keys: String, CodingKey { case format, version, utf8Base64 }
    private init(validated bytes: Data) { utf8 = bytes }

    /// Writes an exact value with Version 1's compact, insertion-order policy.
    /// - Parameters:
    ///   - value: The admitted JSON value, including a present JSON null.
    ///   - limits: Finite ceilings intersected with the balanced persistence profile.
    /// - Throws: Resource/configuration failure or cancellation; no partial payload.
    public init(preserving value: JSON, limits: JSONLimits = .balanced) throws {
        self = try Self.preservingWithReport(value, limits: limits).result
    }
    /// Creates a payload and reports owned writing, copies and prospective envelope checks.
    /// - Parameters:
    ///   - value: The exact JSON value to preserve.
    ///   - limits: Tightening ceilings; a larger profile cannot widen automatic persistence.
    /// - Throws: Resource/configuration failure or cancellation.
    public static func preservingWithReport(_ value: JSON, limits: JSONLimits = .balanced) throws -> JSONOperationReport<Self> {
        var meter = try JSONWorkMeter(limits: JSONLimits.balanced.intersection(limits), domain: .coding)
        let bytes = try JSONWriter(options: .init(numberStyle: .preserved)).write(value, meter: &meter)
        try envelopeCapacity(UInt64(bytes.count), meter: &meter)
        for _ in bytes { try meter.work(); try meter.retain(1) }
        let data = Data(bytes)
        try meter.release(UInt64(bytes.count)); try meter.checkpoint()
        return .init(result: Self(validated: data), statistics: meter.statistics())
    }
    /// Opens a validated payload through a new complete strict parse operation.
    /// - Parameter limits: Finite ceilings intersected with the balanced profile.
    /// - Throws: Resource/configuration failure or cancellation.
    public func value(limits: JSONLimits = .balanced) throws -> JSON { try valueWithReport(limits: limits).result }
    /// Parses afresh and reports owned stored-byte admission, copying and parsing.
    /// - Parameter limits: Tightening ceilings; stored data never selects limits.
    /// - Throws: Resource/configuration failure or cancellation.
    public func valueWithReport(limits: JSONLimits = .balanced) throws -> JSONOperationReport<JSON> {
        var meter = try JSONWorkMeter(limits: JSONLimits.balanced.intersection(limits), domain: .parsing)
        try Self.admit(utf8, meter: &meter)
        let value = try Self.parse(utf8, meter: &meter)
        try meter.release(UInt64(utf8.count)); try meter.checkpoint()
        return .init(result: value, statistics: meter.statistics())
    }
    private static func admit(_ bytes: Data, meter: inout JSONWorkMeter) throws {
        try meter.require(.inputBytes, UInt64(bytes.count))
        for _ in bytes { try meter.work(); try meter.retain(1) }
    }
    private static func parse(_ bytes: Data, meter: inout JSONWorkMeter) throws -> JSON {
        var input: [UInt8] = []
        for byte in bytes { try meter.work(); try meter.retain(1); input.append(byte) }
        let result = try JSONParser().parse(input, meter: &meter)
        try meter.release(UInt64(input.count)); return result
    }
    private static func envelopeCapacity(_ length: UInt64, meter: inout JSONWorkMeter) throws {
        try meter.require(.inputBytes, length)
        let rounded = try meter.adding(.outputBytes, length, 2) / 3
        let (base64, overflow) = rounded.multipliedReportingOverflow(by: 4)
        if overflow { _ = try meter.adding(.outputBytes, UInt64.max, 1) }
        try meter.require(.stringBytes, base64)
        // Fixed primitive fields in their shortest compact JSON spelling.
        let overhead = UInt64(#"{"format":"swift-json-value","version":1,"utf8Base64":""}"#.utf8.count)
        _ = try meter.adding(.outputBytes, base64, overhead)
        let text = try meter.adding(.aggregateTextBytes, base64, 39)
        _ = try meter.adding(.aggregateTextBytes, meter.used(.aggregateTextBytes), text)
    }
    private func encoded(meter: inout JSONWorkMeter) throws -> (String, UInt64) {
        let before = meter.used(.retainedBytes)
        do {
            try Self.admit(utf8, meter: &meter)
            try Self.envelopeCapacity(UInt64(utf8.count), meter: &meter)
            let (text, count) = try JSONBase64.encode(utf8, meter: &meter)
            try meter.charge(.aggregateTextBytes, count)
            try meter.release(UInt64(utf8.count))
            return (text, count)
        } catch { try meter.release(meter.used(.retainedBytes) - before); throw error }
    }
    /// Encodes Version 1 primitive fields; it never invokes foreign numeric/key coding for the inner JSON.
    /// - Parameter encoder: The enclosing coder, whose callbacks are outside owned work caps.
    /// - Throws: Coder errors, resource/configuration failure or cancellation.
    public func encode(to encoder: any Encoder) throws {
        let native = encoder as? JSONNativeEncoder
        if let native {
            try native.state.meter.restrict(to: .balanced)
            let (text, reservation) = try encoded(meter: &native.state.meter)
            do { try encodeFields(text, to: encoder); try native.state.check() }
            catch { try native.state.meter.release(reservation); throw error }
            try native.state.meter.release(reservation)
        } else {
            var local = try JSONWorkMeter(limits: .balanced, domain: .coding)
            let (text, reservation) = try encoded(meter: &local)
            do { try encodeFields(text, to: encoder); try local.checkpoint() }
            catch { try local.release(reservation); throw error }
            try local.release(reservation)
        }
    }
    private func encodeFields(_ text: String, to encoder: any Encoder) throws {
        // Do not keep an inout meter borrow across arbitrary Encoder callbacks.
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode("swift-json-value", forKey: .format)
        try container.encode(1, forKey: .version)
        try container.encode(text, forKey: .utf8Base64)
    }
    private static func validated(_ marker: String, version: Int, text: String, meter: inout JSONWorkMeter) throws -> Data {
        let before = meter.used(.retainedBytes)
        do {
            try JSONAdmission.text(marker, meter: &meter, owned: true)
            try JSONAdmission.text(text, meter: &meter, owned: true)
            guard marker == "swift-json-value", version == 1 else { throw JSONFailure(.syntax, code: .invalidSyntax) }
            var count: UInt64 = 0
            for _ in text.utf8 { try meter.work(); count = try meter.adding(.stringBytes, count, 1) }
            guard count % 4 == 0 else { throw JSONFailure(.syntax, code: .invalidSyntax) }
            // Maximum decoded size is checked before Base64's first output byte.
            let (maximum, overflow) = (count / 4).multipliedReportingOverflow(by: 3)
            if overflow { _ = try meter.adding(.inputBytes, UInt64.max, 1) }
            // Padding may reduce the inclusive decoded capacity by up to two.
            var padding: UInt64 = 0
            for byte in text.utf8.suffix(2).reversed() { try meter.work(); if byte == 61 { padding += 1 } else { break } }
            guard maximum >= padding else { throw JSONFailure(.syntax, code: .invalidSyntax) }
            try envelopeCapacity(maximum - padding, meter: &meter)
            let bytes = try JSONBase64.decode(text, meter: &meter)
            let beforeDOM = meter.used(.retainedBytes)
            _ = try parse(bytes, meter: &meter) // Certifies trailing syntax/whitespace/EOF.
            try meter.release(meter.used(.retainedBytes) - beforeDOM)
            try meter.release(meter.used(.retainedBytes) - before - UInt64(bytes.count))
            try meter.checkpoint(); return bytes
        } catch { try meter.release(meter.used(.retainedBytes) - before); throw error }
    }
    /// Validates Version 1, strict Base64 and the complete inner document before storing only its bytes.
    /// - Parameter decoder: The enclosing coder supplying fixed primitive fields.
    /// - Throws: Ordinary Codable field errors or bounded corruption; operational errors retain their types.
    public init(from decoder: any Decoder) throws {
        let native = decoder as? JSONNativeDecoder
        if let native { try native.state.meter.restrict(to: .balanced) }
        let container = try decoder.container(keyedBy: Keys.self)
        let marker = try container.decode(String.self, forKey: .format)
        let version = try container.decode(Int.self, forKey: .version)
        let text = try container.decode(String.self, forKey: .utf8Base64)
        do {
            if let native { utf8 = try Self.validated(marker, version: version, text: text, meter: &native.state.meter) }
            else {
                var local = try JSONWorkMeter(limits: .balanced, domain: .coding)
                utf8 = try Self.validated(marker, version: version, text: text, meter: &local)
            }
        } catch let failure as JSONFailure where failure.category == .syntax {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid Swift-JSON Version 1 payload", underlyingError: failure))
        }
    }
}
