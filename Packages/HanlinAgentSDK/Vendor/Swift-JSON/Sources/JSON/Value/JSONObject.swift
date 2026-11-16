// SPDX-License-Identifier: Apache-2.0
/// An ordered collection of exact-key members with order-independent equality.
///
/// Replacing a member preserves its position; removing and re-inserting appends it.
/// Private exact-key metadata accelerates wide objects. Use bounded operations for untrusted work.
public struct JSONObject: Sendable, Hashable, RandomAccessCollection {
    /// The integer position of a member in insertion order.
    public typealias Index = Int
    /// An exact key/value member in insertion order.
    public typealias Element = JSONMember
    /// Members in deterministic insertion order.
    public let members: [JSONMember]
    package let exactIndex: JSONExactKeyIndex
    /// Admits ordered members and rejects identical decoded scalar keys.
    ///
    /// - Throws: Duplicate-key, value/growth/work failure or cancellation.
    ///
    /// - Parameters:
    ///   - members: Members in insertion order; exact duplicates fail checked construction.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public init(members: [JSONMember] = [], limits: JSONLimits = .balanced) throws {
        var meter = try JSONWorkMeter(limits: limits, domain: .core)
        self = try Self.checked(members: members, meter: &meter)
    }
    package init(admitted members: [JSONMember], index: JSONExactKeyIndex) {
        self.members = members; exactIndex = index
    }
    package init(empty: Void) { members = []; exactIndex = .init() }
    package static func indexed(admitted members: [JSONMember], meter: inout JSONWorkMeter) throws -> Self {
        var index = JSONExactKeyIndex()
        for position in members.indices {
            guard try index.insert(members[position].key, position: position, meter: &meter) else {
                throw JSONFailure(.syntax, code: .duplicateKey)
            }
        }
        return Self(admitted: members, index: index)
    }
    package static func checked(members: [JSONMember], meter: inout JSONWorkMeter) throws -> Self {
        try meter.require(.objectMembers, UInt64(members.count))
        var output: [JSONMember] = []
        var index = JSONExactKeyIndex()
        for member in members {
            try JSONAdmission.text(member.key.string, key: true, meter: &meter, owned: true)
            guard try index.insert(member.key, position: output.count, meter: &meter) else {
                throw JSONFailure(.syntax, code: .duplicateKey)
            }
            try JSONAdmission.value(member.value, meter: &meter, owned: true, depth: 1)
            try meter.retain(JSONLogicalWeights.member)
            output.append(member)
        }
        try meter.charge(.nodes); try meter.retain(JSONLogicalWeights.node)
        try meter.require(.maxDepth, 1)
        return Self(admitted: output, index: index)
    }
    /// The first member index; equal to endIndex for an empty object.
    public var startIndex: Int { members.startIndex }
    /// The collection boundary immediately after the final member.
    public var endIndex: Int { members.endIndex }
    /// Reads the member at its insertion-order collection index.
    ///
    /// The index must be in `startIndex..<endIndex`, as with other Swift collections.
    /// - Parameters:
    ///   - position: A valid insertion-order member index.
    public subscript(position: Int) -> JSONMember { members[position] }
    /// Looks up an exact decoded-scalar key using private unmetered metadata.
    ///
    /// Returns nil for absence and JSON.null for a present null. Use bounded JSON
    /// member access when untrusted traversal requires work accounting.
    ///
    /// - Parameters:
    ///   - key: The exact decoded-scalar member key, without normalization.
    public subscript(key: JSONKey) -> JSON? { exactIndex.find(key).map { members[$0].value } }
    /// Looks up an exact decoded-scalar key using private unmetered metadata.
    ///
    /// Returns nil for absence and JSON.null for a present null. Use bounded JSON
    /// member access when untrusted traversal requires work accounting.
    ///
    /// - Parameters:
    ///   - key: The exact decoded-scalar member key, without normalization.
    public subscript(key: String) -> JSON? { self[JSONKey(key)] }
    /// Compares semantic identity without a throwing work budget.
    ///
    /// - Parameters:
    ///   - lhs: The left value.
    ///   - rhs: The right value.
    public static func == (lhs: Self, rhs: Self) -> Bool { JSON.object(lhs) == JSON.object(rhs) }
    /// Hashes semantic identity; the randomized result is not a persistent digest.
    ///
    /// This protocol operation has no throwing work budget.
    ///
    /// - Parameters:
    ///   - hasher: The caller's randomized Swift hasher.
    public func hash(into hasher: inout Hasher) { JSON.object(self).hash(into: &hasher) }
    package func lookup(_ key: String, meter: inout JSONWorkMeter) throws -> JSON? {
        // Preserve the qualified scalar tiny/early-hit path before hashing.
        for member in members.prefix(members.count < 32 ? members.count : 8) {
            try meter.work()
            if try JSONComparison.textEquals(member.key.string, key, meter: &meter) {
                return member.value
            }
        }
        guard members.count >= 32 else { return nil }
        let query = try JSONKey(key, meter: &meter)
        return try exactIndex.find(query, meter: &meter).map { members[$0].value }
    }
    /// Returns an admitted object with a member added or replaced in place.
    ///
    /// A new key appends; replacement preserves its insertion position.
    /// - Throws: Value, key, growth or work limit failure, or cancellation.
    ///
    /// - Parameters:
    ///   - value: The replacement or new payload to admit under the same operation budget.
    ///   - key: The exact decoded-scalar key to select or insert.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public func setting(_ value: JSON, for key: JSONKey, limits: JSONLimits = .balanced) throws -> Self {
        var meter = try JSONWorkMeter(limits: limits, domain: .core)
        try JSONAdmission.value(.object(self), meter: &meter)
        try meter.resetValueBounds(); try JSONAdmission.text(key.string, key: true, meter: &meter, owned: true)
        try JSONAdmission.value(value, meter: &meter, owned: true, depth: 1)
        let result = try JSONEditing.modify(.object(self), token: key, change: .add(value), meter: &meter)
        try meter.resetValueBounds(); try JSONAdmission.value(result, meter: &meter)
        return result.objectValue!
    }
    /// Returns an admitted object without the selected exact key; absence leaves it unchanged.
    ///
    /// - Throws: Resource or configuration failure, or cancellation.
    ///
    /// - Parameters:
    ///   - key: The exact decoded-scalar member key, without normalization.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public func removing(_ key: JSONKey, limits: JSONLimits = .balanced) throws -> Self {
        var meter = try JSONWorkMeter(limits: limits, domain: .core)
        try JSONAdmission.value(.object(self), meter: &meter)
        guard try lookup(key.string, meter: &meter) != nil else { return self }
        let result = try JSONEditing.modify(.object(self), token: key, change: .remove, meter: &meter)
        try meter.resetValueBounds(); try JSONAdmission.value(result, meter: &meter)
        return result.objectValue!
    }
}
