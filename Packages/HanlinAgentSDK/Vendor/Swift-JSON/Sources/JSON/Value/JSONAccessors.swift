// SPDX-License-Identifier: Apache-2.0
extension JSON {
    /// The object payload, or nil when the value has another kind.
    public var objectValue: JSONObject? { if case .object(let v) = self { return v }; return nil }
    /// The array payload, or nil when the value has another kind.
    public var arrayValue: [JSON]? { if case .array(let v) = self { return v }; return nil }
    /// The string payload without coercion, or nil for another kind.
    public var stringValue: String? { if case .string(let v) = self { return v }; return nil }
    /// The exact number payload without coercion, or nil for another kind.
    public var numberValue: JSONNumber? { if case .number(let v) = self { return v }; return nil }
    /// The Boolean payload without coercion, or nil for another kind.
    public var booleanValue: Bool? { if case .boolean(let v) = self { return v }; return nil }
    /// Whether this value is JSON null.
    public var isNull: Bool { if case .null = self { return true }; return false }
    /// Looks up an exact scalar key and requires a present member on an object.
    ///
    /// - Returns: The value, including JSON null when present.
    /// - Throws: Wrong-kind or missing-member failure, resource failure or cancellation.
    ///
    /// - Parameters:
    ///   - key: The exact decoded-scalar member key, without normalization.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public func requiredMember(_ key: String, limits: JSONLimits = .balanced) throws -> JSON {
        var meter = try JSONWorkMeter(limits: limits, domain: .core)
        guard case .object(let object) = self else { throw JSONFailure(.typeMismatch, code: .wrongKind) }
        try JSONAdmission.text(key, key: true, meter: &meter)
        guard let value = try object.lookup(key, meter: &meter) else { throw JSONFailure(.missingValue, code: .missingMember) }
        return value
    }
    /// Looks up a member with bounded exact-key traversal.
    ///
    /// - Returns: Absent, null or a non-null value.
    /// - Throws: Wrong-kind failure, resource or configuration failure, or cancellation.
    ///
    /// - Parameters:
    ///   - key: The exact decoded-scalar key to select or insert.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public func presence(of key: String, limits: JSONLimits = .balanced) throws -> JSONPresence<JSON> {
        var meter = try JSONWorkMeter(limits: limits, domain: .core)
        guard case .object(let object) = self else { throw JSONFailure(.typeMismatch, code: .wrongKind) }
        try JSONAdmission.text(key, key: true, meter: &meter)
        guard let value = try object.lookup(key, meter: &meter) else { return .absent }
        if case .null = value { return .null }
        return .value(value)
    }
}
