// SPDX-License-Identifier: Apache-2.0
import JSON
/// A schema admission, dialect, reference or meta-schema error.
///
/// This is an operational failure, not an instance-invalid verdict.
public struct JSONSchemaCompilationFailure: Error, Sendable, Equatable {
    /// The schema-compilation condition that failed.
    public enum Category: String, Sendable {
        /// The schema root is neither an object nor a Boolean.
        case rootKind
        /// The declared dialect is unsupported or inconsistent.
        case dialect
        /// A required vocabulary or assertion behavior is unsupported.
        case vocabulary
        /// A schema keyword declaration is malformed.
        case schemaSyntax
        /// A resource identifier is malformed, missing or ambiguous.
        case identifier
        /// An anchor is malformed or ambiguous.
        case anchor
        /// A referenced offline resource was not supplied.
        case missingResource
        /// A reference cannot resolve to a schema target.
        case reference
        /// The schema does not satisfy its supplied or packaged meta-schema.
        case metaSchema
    }
    /// The stable error category.
    public let category: Category
    /// The document Pointer of the failed schema declaration, when available.
    public let location: JSONPointer?
    /// Creates a bounded compilation failure with an optional declaration Pointer.
    ///
    /// - Parameters:
    ///   - category: The stable failure category.
    ///   - location: Optional source/declaration location.
    public init(_ category: Category, location: JSONPointer? = nil) { self.category = category; self.location = location }
}
