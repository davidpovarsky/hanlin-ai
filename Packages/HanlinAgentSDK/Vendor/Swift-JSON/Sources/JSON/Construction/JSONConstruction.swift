// SPDX-License-Identifier: Apache-2.0
extension JSON: ExpressibleByIntegerLiteral {
    /// Constructs a trusted literal value without a resource budget; bounded operations admit it later.
    ///
    /// - Parameters:
    ///   - value: The value supplied by the caller.
    public init(integerLiteral value: Int64) { self = .number(JSONNumber(integer: value)) }
}
extension JSON: ExpressibleByStringLiteral {
    /// Constructs a trusted literal value without a resource budget; bounded operations admit it later.
    ///
    /// - Parameters:
    ///   - value: The value supplied by the caller.
    public init(stringLiteral value: String) { self = .string(value) }
}
extension JSON: ExpressibleByBooleanLiteral {
    /// Constructs a trusted literal value without a resource budget; bounded operations admit it later.
    ///
    /// - Parameters:
    ///   - value: The value supplied by the caller.
    public init(booleanLiteral value: Bool) { self = .boolean(value) }
}
extension JSON: ExpressibleByNilLiteral {
    /// Constructs a trusted literal value without a resource budget; bounded operations admit it later.
    ///
    /// - Parameters:
    ///   - nilLiteral: The Swift nil literal, represented as JSON null.
    public init(nilLiteral: ()) { self = .null }
}
extension JSON: ExpressibleByArrayLiteral {
    /// Constructs a trusted literal value without a resource budget; bounded operations admit it later.
    ///
    /// - Parameters:
    ///   - values: Trusted array-literal elements; this initializer does not charge a work budget.
    public init(arrayLiteral values: JSON...) { self = .array(values) }
}
