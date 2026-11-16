// SPDX-License-Identifier: Apache-2.0
import Foundation
/// Strategies and finite limits for native value-based Codable.
///
/// Caller Codable callbacks remain caller work. User information must be Sendable;
/// mutable encoding and decoding state is owned by each invocation.
public struct JSONCodingOptions: Sendable {
    /// Native Date representations; explicit ISO-8601 is bounded UTC text.
    public enum DateStrategy: Sendable {
        /// Use the Date type's Codable implementation.
        case deferredToDate
        /// Encode seconds since the Unix epoch using a finite numeric representation.
        case secondsSince1970
        /// Use bounded UTC ISO-8601 text with fractional seconds and four-digit years.
        case iso8601
    }
    /// Native Data representations; Base64 uses strict metered loops.
    public enum DataStrategy: Sendable {
        /// Use strict, natively metered Base64 text.
        case base64
        /// Use the Data type's Codable implementation.
        case deferredToData
    }
    /// Finite capacities and work quotas applied to library-owned operations.
    public var limits: JSONLimits
    /// The representation used for native Date coding.
    public var dateStrategy: DateStrategy
    /// The representation used for native Data coding.
    public var dataStrategy: DataStrategy
    /// Caller context forwarded to Codable callbacks; stored values must be Sendable.
    public var userInfo: [CodingUserInfoKey: any Sendable]
    /// Creates the value configuration; finite limits are checked at operation entry.
    ///
    /// - Parameters:
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    ///   - dateStrategy: The Date coding representation.
    ///   - dataStrategy: The Data coding representation.
    ///   - userInfo: Sendable caller context.
    public init(limits: JSONLimits = .balanced, dateStrategy: DateStrategy = .deferredToDate,
                dataStrategy: DataStrategy = .base64, userInfo: [CodingUserInfoKey: any Sendable] = [:]) {
        self.limits = limits; self.dateStrategy = dateStrategy; self.dataStrategy = dataStrategy; self.userInfo = userInfo
    }
}
package final class JSONCodingState {
    package var meter: JSONWorkMeter
    package private(set) var options: JSONCodingOptions
    package var failure: (any Error)?
    package private(set) var bridgedUserInfo: [CodingUserInfoKey: Any] = [:]
    private var prepared = false
    private var preparedBytes: UInt64 = 0
    package init(options: JSONCodingOptions, meter: consuming JSONWorkMeter) {
        self.options = options; self.meter = meter
    }
    package func check() throws {
        if let failure { throw failure }; try meter.checkpoint()
        if !prepared {
            try meter.require(.objectMembers, UInt64(options.userInfo.count))
            for (key, value) in options.userInfo {
                let before = meter.used(.retainedBytes)
                try JSONAdmission.text(key.rawValue, key: true, meter: &meter, owned: true)
                try meter.work(); try meter.retain(JSONLogicalWeights.member)
                bridgedUserInfo[key] = value
                preparedBytes += meter.used(.retainedBytes) - before
            }
            prepared = true
        }
    }
    package func withOptions<T>(_ requested: JSONCodingOptions, _ body: () throws -> T) throws -> T {
        try meter.restrict(to: requested.limits)
        let oldOptions = options, oldInfo = bridgedUserInfo, oldPrepared = prepared, oldBytes = preparedBytes
        options = requested; bridgedUserInfo = [:]; prepared = false; preparedBytes = 0
        func restore() throws {
            try meter.release(preparedBytes)
            options = oldOptions; bridgedUserInfo = oldInfo; prepared = oldPrepared; preparedBytes = oldBytes
        }
        do {
            try check(); let result = try body(); try check(); try restore(); return result
        } catch { try restore(); throw error }
    }
    package func latch(_ action: () throws -> Void) { do { try action() } catch { if failure == nil { failure = error } } }
    package func path(_ path: [any CodingKey], appending key: any CodingKey) throws -> [any CodingKey] {
        try check(); try meter.require(.maxDepth, UInt64(path.count) + 1)
        var result: [any CodingKey] = []
        for part in path { try meter.work(); try meter.retain(16); result.append(part) }
        try JSONAdmission.text(key.stringValue, key: true, meter: &meter, owned: true)
        try meter.retain(16); result.append(key); return result
    }
}
package struct JSONCodingKey: CodingKey {
    package let stringValue: String
    package let intValue: Int?
    package init(_ string: String) { stringValue = string; intValue = nil }
    package init(index: Int) { stringValue = String(index); intValue = index }
    package init?(stringValue: String) { self.init(stringValue) }
    package init?(intValue: Int) { self.init(index: intValue) }
}
