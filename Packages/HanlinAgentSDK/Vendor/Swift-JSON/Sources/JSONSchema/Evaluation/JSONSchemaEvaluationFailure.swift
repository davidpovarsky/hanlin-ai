// SPDX-License-Identifier: Apache-2.0
/// An operational evaluation or output error, separate from invalidity.
public struct JSONSchemaEvaluationFailure: Error, Sendable, Equatable {
    /// The operational condition that prevented a completed result.
    public enum Category: String, Sendable {
        /// An active reference repeats without advancing the instance location.
        case nonproductiveReference
        /// The evaluation backend cannot produce a valid operational result.
        case backend
        /// Requested output requires diagnostics that were not collected.
        case outputUnavailable
    }
    /// The stable error category.
    public let category: Category
    /// Creates a bounded operational evaluation failure.
    ///
    /// - Parameters:
    ///   - category: The stable failure category.
    public init(_ category: Category) { self.category = category }
}
