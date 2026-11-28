// SPDX-License-Identifier: Apache-2.0
/// Presence without conflating a missing field, JSON null and a non-null value.
public enum JSONPresence<Value> {
    /// The field is not present.
    case absent
    /// The field is present as JSON null.
    case null
    /// The field is present with a non-null payload.
    case value(Value)
}
extension JSONPresence: Sendable where Value: Sendable {}
extension JSONPresence: Equatable where Value: Equatable {}
extension JSONPresence: Hashable where Value: Hashable {}

extension JSONPresence {
    /// Transforms a non-null payload while preserving absence and explicit null.
    ///
    /// The callback runs exactly once for `.value` and never for the other cases.
    /// Its computation is caller work; this helper performs no bounded admission.
    /// - Parameter transform: The synchronous payload transformation.
    /// - Returns: The same presence state, with a transformed value when present.
    /// - Throws: The callback's error unchanged.
    public func map<NewValue>(_ transform: (Value) throws -> NewValue) rethrows -> JSONPresence<NewValue> {
        switch self {
        case .absent: return .absent
        case .null: return .null
        case .value(let payload): return .value(try transform(payload))
        }
    }

    /// Selects exactly one callback for absent, null or non-null presence.
    ///
    /// Callback computation is caller work; no resource quota is implied.
    /// - Parameters:
    ///   - absent: Invoked only when the field is missing.
    ///   - null: Invoked only for explicit JSON null.
    ///   - value: Invoked only with a non-null payload.
    /// - Returns: The selected callback's result.
    /// - Throws: The selected callback's error unchanged.
    public func fold<Result>(absent: () throws -> Result, null: () throws -> Result, value: (Value) throws -> Result) rethrows -> Result {
        switch self {
        case .absent: return try absent()
        case .null: return try null()
        case .value(let payload): return try value(payload)
        }
    }
}

extension JSONObject {
    /// Looks up an exact scalar key and distinguishes absence, null and non-null values.
    ///
    /// This convenience performs unmetered linear lookup. Use JSON.presence(of:limits:)
    /// when the enclosing operation requires bounded traversal.
    ///
    /// - Parameters:
    ///   - key: The exact decoded-scalar key to select or insert.
    public func presence(of key: JSONKey) -> JSONPresence<JSON> {
        guard let value = self[key] else { return .absent }
        if case .null = value { return .null }
        return .value(value)
    }
    /// Looks up an exact scalar key and distinguishes absence, null and non-null values.
    ///
    /// This convenience performs unmetered linear lookup. Use JSON.presence(of:limits:)
    /// when the enclosing operation requires bounded traversal.
    ///
    /// - Parameters:
    ///   - key: The exact decoded-scalar key to select or insert.
    public func presence(of key: String) -> JSONPresence<JSON> { presence(of: JSONKey(key)) }
}
