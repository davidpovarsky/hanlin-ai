// SPDX-License-Identifier: Apache-2.0
/// A structured JSON operation error without a retained rejected payload.
///
/// Resource failures carry the violated metric. Cancellation propagates separately
/// as `CancellationError`; schema compilation and evaluation have their own errors.
public struct JSONFailure: Error, Sendable, Equatable {
    /// A stable classification of the failed operation.
    public enum Category: String, Sendable, Codable {
        /// The input violates strict JSON syntax or UTF-8 rules.
        case syntax
        /// The selected value has the wrong JSON kind.
        case typeMismatch
        /// A required member or value is absent.
        case missingValue
        /// Pointer syntax or traversal failed.
        case pointer
        /// A Patch operation or test failed.
        case patch
        /// A numeric projection cannot satisfy its requested fidelity.
        case conversion
        /// The options or finite limits are unsupported.
        case configuration
        /// A finite capacity, work quota or checked counter was exhausted.
        case resource
    }
    /// A stable machine-readable reason without arbitrary input text.
    public enum Code: String, Sendable, Codable {
        /// The limit or presentation configuration is unsupported.
        case invalidLimits
        /// The next admitted unit would exceed an inclusive ceiling.
        case limitExceeded
        /// Checked resource arithmetic could not represent the attempted usage.
        case counterOverflow
        /// The input violates strict grammar.
        case invalidSyntax
        /// Input bytes or escaped scalars do not form valid Unicode.
        case invalidUTF8
        /// Two decoded object keys have identical scalar sequences.
        case duplicateKey
        /// EOF arrived before required syntax or a value completed.
        case unexpectedEOF
        /// Data follows a root without a permitted framing boundary.
        case trailingData
        /// The selected value has an unexpected kind.
        case wrongKind
        /// An exact required object key is absent.
        case missingMember
        /// A numeric token violates grammar or supported exact-number admission.
        case invalidNumber
        /// A number is out of range or cannot satisfy the conversion policy.
        case inexactConversion
        /// The encoded Pointer or URI fragment is malformed.
        case invalidPointer
        /// An array index violates strict syntax or supported index range.
        case invalidIndex
        /// A Pointer or Patch target does not exist.
        case missingTarget
        /// A Patch test did not find semantic equality.
        case failedTest
        /// A Patch declaration or requested edit is invalid.
        case invalidOperation
    }
    /// The stable error category.
    public let category: Category
    /// The stable machine-readable failure code.
    public let code: Code
    /// An optional location in the admitted source.
    public let location: JSONSourceLocation?
    /// The violated resource policy, when this is a resource failure.
    public let resource: JSONResourceViolation?
    /// Creates bounded structured error fields without retaining a rejected value.
    ///
    /// - Parameters:
    ///   - category: The stable failure category.
    ///   - code: The stable failure reason.
    ///   - location: Optional source/declaration location.
    ///   - resource: Optional structured resource violation.
    public init(_ category: Category, code: Code, location: JSONSourceLocation? = nil,
                resource: JSONResourceViolation? = nil) {
        self.category = category; self.code = code; self.location = location; self.resource = resource
    }
}
