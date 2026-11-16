// SPDX-License-Identifier: Apache-2.0
/// One exact key and value in an ordered JSON object.
public struct JSONMember: Sendable, Equatable, Hashable {
    /// The exact decoded-scalar member key.
    public let key: JSONKey
    /// The associated exact JSON value.
    public let value: JSON
    /// Pairs an exact key with a value; bounded object construction performs admission.
    ///
    /// - Parameters:
    ///   - key: The exact decoded-scalar member key, without normalization.
    ///   - value: The associated value; this initializer performs no admission.
    public init(_ key: JSONKey, value: JSON) { self.key = key; self.value = value }
    /// Pairs an exact key with a value; bounded object construction performs admission.
    ///
    /// - Parameters:
    ///   - key: The exact decoded-scalar member key, without normalization.
    ///   - value: The associated value; this initializer performs no admission.
    public init(_ key: String, value: JSON) { self.init(JSONKey(key), value: value) }
}
