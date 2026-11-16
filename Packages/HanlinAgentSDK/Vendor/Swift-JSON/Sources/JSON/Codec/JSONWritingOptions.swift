// SPDX-License-Identifier: Apache-2.0
/// The UTF-8 character used for each indentation unit.
public enum JSONIndentationUnit: Sendable {
    /// One ASCII space per unit; the legacy writer default.
    case spaces
    /// One horizontal tab per unit; display width belongs to the receiving application.
    case tabs
}

/// Resource and presentation choices for strict JSON output.
public struct JSONWritingOptions: Sendable {
    /// The member order chosen for output.
    public enum KeyOrder: Sendable {
        /// Preserve member insertion order.
        case insertion
        /// Sort by exact decoded Unicode scalar key order; no signature canonicalization is implied.
        case scalar
    }
    /// Finite capacities and work quotas applied to library-owned operations.
    public var limits: JSONLimits
    /// Indentation units per nesting level, from 0 through 8; nil selects compact output.
    public var indentation: Int?
    /// Insertion order or ascending decoded-scalar key order.
    public var keyOrder: KeyOrder
    /// Normalized decimal spelling or original lexemes when available.
    public var numberStyle: JSONNumberTextStyle
    /// Space or tab units; compact output ignores this choice.
    public var indentationUnit: JSONIndentationUnit
    /// Creates the legacy space-indented configuration, preserving its initializer function type.
    ///
    /// - Parameters:
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    ///   - indentation: Spaces per level, 0...8, or nil for compact output.
    ///   - keyOrder: Insertion or scalar key order.
    ///   - numberStyle: Normalized or preserved numeric spelling.
    public init(limits: JSONLimits = .balanced, indentation: Int? = nil,
                keyOrder: KeyOrder = .insertion, numberStyle: JSONNumberTextStyle = .normalized) {
        self.init(limits: limits, indentation: indentation, keyOrder: keyOrder,
                  numberStyle: numberStyle, indentationUnit: .spaces)
    }
    /// Creates the value configuration; finite limits are checked at operation entry.
    ///
    /// - Parameters:
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    ///   - indentation: Units per level, 0...8, or nil for compact output.
    ///   - keyOrder: Insertion or scalar key order.
    ///   - numberStyle: Normalized or preserved numeric spelling.
    ///   - indentationUnit: Literal space or tab units; this overload requires an explicit choice.
    public init(limits: JSONLimits = .balanced, indentation: Int? = nil,
                keyOrder: KeyOrder = .insertion, numberStyle: JSONNumberTextStyle = .normalized,
                indentationUnit: JSONIndentationUnit) {
        self.limits = limits; self.indentation = indentation; self.keyOrder = keyOrder; self.numberStyle = numberStyle
        self.indentationUnit = indentationUnit
    }
}
