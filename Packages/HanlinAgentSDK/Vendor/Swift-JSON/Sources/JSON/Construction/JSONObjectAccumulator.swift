// SPDX-License-Identifier: Apache-2.0
/// An exclusively owned, noncopyable builder for ordered exact-key members.
///
/// Duplicate decoded keys fail; growth and payload work share the builder budget.
public struct JSONObjectAccumulator: ~Copyable {
    private var members: [JSONMember] = []
    private var index = JSONExactKeyIndex()
    private var meter: JSONWorkMeter
    /// Creates an exclusive finite builder and admits its outer object frame.
    ///
    /// - Throws: Configuration, retention or depth failure, or cancellation.
    ///
    /// - Parameters:
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public init(limits: JSONLimits = .balanced) throws {
        try self.init(meter: JSONWorkMeter(limits: limits, domain: .core))
    }
    /// Transfers an invocation's exclusive ledger into construction.
    package init(meter: consuming JSONWorkMeter) throws {
        var initialMeter = meter
        try initialMeter.require(.maxDepth, 1); try initialMeter.charge(.nodes); try initialMeter.retain(JSONLogicalWeights.node)
        self.meter = initialMeter
    }
    /// Appends admitted payloads while retaining cumulative builder work.
    ///
    /// Object builders reject exact duplicate keys before insertion.
    /// - Throws: An exact duplicate key, growth, depth, retention or work failure, or cancellation.
    ///
    /// - Parameters:
    ///   - key: The exact decoded-scalar member key, without normalization.
    ///   - value: The payload to admit before appending at element depth.
    public mutating func append(_ key: String, value: JSON) throws {
        try meter.require(.objectMembers, UInt64(members.count) + 1)
        try JSONAdmission.text(key, key: true, meter: &meter, owned: true)
        let admittedKey = try JSONKey(key, meter: &meter)
        guard try index.find(admittedKey, meter: &meter) == nil else { throw JSONFailure(.syntax, code: .duplicateKey) }
        try JSONAdmission.value(value, meter: &meter, owned: true, depth: 1)
        try meter.retain(JSONLogicalWeights.member)
        guard try index.insert(admittedKey, position: members.count, meter: &meter) else { throw JSONFailure(.syntax, code: .duplicateKey) }
        members.append(JSONMember(admittedKey, value: value))
    }
    /// Consumes the builder and transfers its already admitted result.
    public consuming func finish() -> JSONObject { JSONObject(admitted: members, index: index) }
    package var continuation: JSONWorkMeter.Continuation { meter.continuation }
    /// Continues an owned composition without copying or restarting its ledger.
    package consuming func finish<Result>(continuation: JSONWorkMeter.Continuation, _ body: (JSONObject, inout JSONWorkMeter) throws -> Result) throws -> Result {
        try continuation.check(meter)
        let object = JSONObject(admitted: members, index: index)
        return try body(object, &meter)
    }
}

extension JSONObject {
    /// Builds an object using an exclusively borrowed accumulator, then transfers its result.
    ///
    /// - Throws: Caller body errors, duplicate keys, resource failure or cancellation.
    ///
    /// - Parameters:
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    ///   - body: A synchronous callback borrowing the exclusive builder; its errors propagate.
    public static func build(limits: JSONLimits = .balanced, _ body: (inout JSONObjectAccumulator) throws -> Void) throws -> Self {
        var accumulator = try JSONObjectAccumulator(limits: limits)
        try body(&accumulator)
        return accumulator.finish()
    }
}
