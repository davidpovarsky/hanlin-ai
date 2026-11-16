// SPDX-License-Identifier: Apache-2.0
/// A bounded classification of an error that does not inspect rejected input.
///
/// Caller error descriptions and payloads are not retained.
public struct JSONDiagnostic: Sendable, Equatable {
    /// A bounded error classification without arbitrary error descriptions.
    public enum Kind: String, Sendable {
        /// A structured JSON failure without rejected payload.
        case failure
        /// An operation ended with CancellationError.
        case cancellation
        /// An unrelated caller or upstream error without its arbitrary description.
        case callerError
    }
    /// The bounded classification of this diagnostic.
    public let kind: Kind
    /// The structured JSON failure, or nil for cancellation and caller errors.
    public let failure: JSONFailure?
    /// Classifies JSONFailure, cancellation or a caller error without rendering arbitrary descriptions.
    ///
    /// - Parameters:
    ///   - error: The error to classify without rendering its arbitrary description.
    public init(_ error: any Error) {
        if let error = error as? JSONFailure { kind = .failure; failure = error }
        else if let error = error as? JSONAccessFailure { kind = .failure; failure = error.cause }
        else if error is CancellationError { kind = .cancellation; failure = nil }
        else { kind = .callerError; failure = nil }
    }
}
