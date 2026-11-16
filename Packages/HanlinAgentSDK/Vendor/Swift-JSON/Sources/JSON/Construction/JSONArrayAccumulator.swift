// SPDX-License-Identifier: Apache-2.0
/// An exclusively owned, noncopyable builder that checks limits before appending.
///
/// Consume the accumulator with `finish()` to transfer the admitted values.
public struct JSONArrayAccumulator: ~Copyable {
    private var values: [JSON] = []
    private var meter: JSONWorkMeter
    /// Creates an exclusive finite builder and admits its outer array frame.
    ///
    /// - Throws: Configuration, retention or depth failure, or cancellation.
    ///
    /// - Parameters:
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public init(limits: JSONLimits = .balanced) throws {
        var initialMeter = try JSONWorkMeter(limits: limits, domain: .core)
        try initialMeter.require(.maxDepth, 1); try initialMeter.charge(.nodes); try initialMeter.retain(JSONLogicalWeights.node)
        meter = initialMeter
    }
    /// Appends admitted payloads while retaining cumulative builder work.
    ///
    /// Each append admits the payload at array-element depth under the same budget.
    /// - Throws: Growth, depth, retention or work failure, or cancellation.
    ///
    /// - Parameters:
    ///   - value: The payload to admit before appending at element depth.
    public mutating func append(_ value: JSON) throws {
        try meter.require(.arrayItems, UInt64(values.count) + 1)
        try JSONAdmission.value(value, meter: &meter, owned: true, depth: 1)
        try meter.retain(JSONLogicalWeights.arraySlot); values.append(value)
    }
    /// Appends admitted payloads while retaining cumulative builder work.
    ///
    /// Each append admits the payload at array-element depth under the same budget.
    /// - Throws: Growth, depth, retention or work failure, or cancellation.
    ///
    /// - Parameters:
    ///   - values: The values to append explicitly, with charged traversal.
    public mutating func append(contentsOf values: [JSON]) throws {
        for value in values { try append(value) }
    }
    /// Consumes the builder and transfers its already admitted result.
    public consuming func finish() -> [JSON] { values }
}
extension JSON {
    /// Builds an array using an exclusively borrowed accumulator, then transfers its result.
    ///
    /// - Throws: Caller body errors, resource failure or cancellation.
    ///
    /// - Parameters:
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    ///   - body: A synchronous callback borrowing the exclusive builder; its errors propagate.
    public static func buildArray(limits: JSONLimits = .balanced, _ body: (inout JSONArrayAccumulator) throws -> Void) throws -> Self {
        var accumulator = try JSONArrayAccumulator(limits: limits)
        try body(&accumulator)
        return .array(accumulator.finish())
    }
}
