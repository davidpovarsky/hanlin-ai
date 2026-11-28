// SPDX-License-Identifier: Apache-2.0
import Foundation
import JSON
/// A normalized absolute RFC 3986 schema identity resolved during compilation.
///
/// Pointer and anchor fragments identify schema locations. Constructing a URI
/// never fetches it; plans retain indexed reference targets.
public struct JSONSchemaURI: Sendable, Hashable {
    /// The normalized absolute URI spelling used for exact resource identity.
    public let string: String
    private let identity: JSONKey
    /// Resolves and normalizes an absolute URI, optionally relative to a supplied base.
    ///
    /// - Throws: Invalid identifier, resource or configuration failure, or cancellation. No fetch occurs.
    ///
    /// - Parameters:
    ///   - text: The encoded input text to admit.
    ///   - base: The optional absolute base for relative URI resolution.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public init(_ text: String, relativeTo base: Self? = nil, limits: JSONLimits = .balanced) throws {
        var meter = try JSONWorkMeter(limits: limits, domain: .schemaCompilation)
        self = try Self.parse(text, relativeTo: base, meter: &meter)
    }
    package static func parse(_ text: String, relativeTo base: Self?, meter: inout JSONWorkMeter) throws -> Self {
        var count: UInt64 = 0, percent = 0
        func hex(_ byte: UInt8) -> Bool { (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte) }
        for byte in text.utf8 {
            try meter.work(); count += 1; try meter.require(.stringBytes, count); try meter.retain(1)
            guard byte > 32, byte != 127, byte != 92 else { throw JSONSchemaCompilationFailure(.identifier) }
            if percent > 0 { guard hex(byte) else { throw JSONSchemaCompilationFailure(.identifier) }; percent -= 1 }
            else if byte == 37 { percent = 2 }
        }
        guard percent == 0, try JSONSchemaFormats.test(text,name: base == nil ? .uri : .uriReference,meter: &meter) else { throw JSONSchemaCompilationFailure(.identifier) }
        var baseBytes: UInt64 = 0
        if let base { for _ in base.string.utf8 { try meter.work(); baseBytes += 1 } }
        let sum = try meter.adding(.retainedBytes, count, baseBytes)
        let (expanded, overflow) = sum.multipliedReportingOverflow(by: 3)
        guard !overflow else {
            throw JSONFailure(.resource, code: .counterOverflow, resource: .init(domain: meter.domain, metric: .retainedBytes, limit: meter.limits[.retainedBytes], attemptedUsage: nil, overflow: true))
        }
        // Pre-admit the bounded Foundation URI transformation before invoking it.
        try meter.retain(expanded)
        guard let resolved = URL(string: text, relativeTo: base.flatMap { URL(string: $0.string) })?.absoluteURL,
              resolved.scheme != nil else { throw JSONSchemaCompilationFailure(.identifier) }
        let absolute = resolved.absoluteString
        var absoluteBytes: UInt64 = 0
        for _ in absolute.utf8 { try meter.work(); absoluteBytes += 1; try meter.require(.stringBytes, absoluteBytes) }
        let normalized = try JSONSchemaURINormalization.normalize(absolute, meter: &meter)
        try meter.release(expanded + count)
        return try Self(admitted: normalized, meter: &meter)
    }
    private init(admitted text: String, meter: inout JSONWorkMeter) throws { string = text; identity = try JSONKey(text, meter: &meter) }
    /// The encoded fragment text after #, or nil when absent.
    public var fragment: String? { string.firstIndex(of: "#").map { String(string[string.index(after: $0)...]) } }
    /// Returns the normalized resource URI without its fragment.
    ///
    /// - Throws: URI admission or resource failure, or cancellation.
    ///
    /// - Parameters:
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public func removingFragment(limits: JSONLimits = .balanced) throws -> Self {
        try Self(string.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? string, limits: limits)
    }
    package func withoutFragment(meter: inout JSONWorkMeter, fragmentPresent: Bool? = nil) throws -> Self {
        if fragmentPresent == false || (fragmentPresent == nil && fragment == nil) { try meter.work(); return self }
        var bytes: [UInt8] = []
        for byte in string.utf8 {
            try meter.work(); if byte == 35 { break }; try meter.retain(1); bytes.append(byte)
        }
        for _ in bytes { try meter.work(); try meter.retain(1) }
        let result = try Self(admitted: String(decoding: bytes, as: UTF8.self), meter: &meter)
        try meter.release(UInt64(bytes.count))
        return result
    }
    /// Compares semantic identity without a throwing work budget.
    ///
    /// - Parameters:
    ///   - a: The left identity.
    ///   - b: The right identity.
    public static func == (a: Self, b: Self) -> Bool { a.identity == b.identity }
    /// Hashes semantic identity; the randomized result is not a persistent digest.
    ///
    /// This protocol operation has no throwing work budget.
    ///
    /// - Parameters:
    ///   - hasher: The caller's randomized Swift hasher.
    public func hash(into hasher: inout Hasher) { hasher.combine(identity) }
}
