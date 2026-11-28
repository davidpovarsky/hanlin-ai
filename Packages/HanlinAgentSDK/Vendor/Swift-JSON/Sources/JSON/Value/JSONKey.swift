// SPDX-License-Identifier: Apache-2.0
/// A decoded key whose identity is its exact Unicode scalar sequence.
///
/// Composed and decomposed spellings remain distinct even when Swift String equality
/// treats them as equal. Construction itself has no resource budget.
public struct JSONKey: Sendable, Hashable, ExpressibleByStringLiteral {
    /// The decoded scalar spelling.
    public let string: String
    package let fingerprint: UInt64
    /// Owns the supplied decoded scalar spelling without normalization or a resource quota.
    ///
    /// - Parameters:
    ///   - string: Decoded scalar spelling, preserved without normalization.
    public init(_ string: String) {
        self.string = string
        var hash: UInt64 = 14695981039346656037
        for byte in string.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        fingerprint = hash
    }
    package init(_ string: String, meter: inout JSONWorkMeter, subsystem: JSONResourceMetric? = nil) throws {
        self.string = string
        var hash: UInt64 = 14695981039346656037
        for byte in string.utf8 { try meter.work(subsystem: subsystem); hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        fingerprint = hash
    }
    /// A candidate filter only: every fingerprint hit still compares exact scalar bytes.
    package func matches(_ spelling: String, fingerprint: UInt64, meter: inout JSONWorkMeter) throws -> Bool {
        try meter.work()
        guard self.fingerprint == fingerprint else { return false }
        return try JSONComparison.textEquals(string, spelling, meter: &meter)
    }
    /// Constructs a trusted literal value without a resource budget; bounded operations admit it later.
    ///
    /// - Parameters:
    ///   - value: The value supplied by the caller.
    public init(stringLiteral value: String) { self.init(value) }
    /// Compares semantic identity without a throwing work budget.
    ///
    /// - Parameters:
    ///   - lhs: The left value.
    ///   - rhs: The right value.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.fingerprint == rhs.fingerprint && lhs.string.utf8.elementsEqual(rhs.string.utf8)
    }
    /// Hashes semantic identity; the randomized result is not a persistent digest.
    ///
    /// This protocol operation has no throwing work budget.
    ///
    /// - Parameters:
    ///   - hasher: The caller's randomized Swift hasher.
    public func hash(into hasher: inout Hasher) { hasher.combine(fingerprint) }
}

extension JSONKey: Codable {
    /// Decodes through the supplied coder. Native coding preserves exact payloads;
    /// foreign coders determine available number and key fidelity.
    ///
    /// - Throws: Type/conversion errors or the supplied coder's errors.
    ///
    /// - Parameters:
    ///   - decoder: The supplied decoder; external coders determine their available source fidelity.
    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        if let native = decoder as? JSONNativeDecoder { self = try Self(text,meter: &native.state.meter) }
        else { self.init(text) }
    }
    /// Encodes a Codable value using native exact JSON coding.
    ///
    /// Caller callback errors propagate; encoding and any composed writing share work.
    /// - Throws: Coding, conversion, resource or configuration errors, or cancellation.
    ///
    /// - Parameters:
    ///   - encoder: The supplied encoder; external coders determine available numeric/key fidelity.
    public func encode(to encoder: any Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(string) }
}
