// SPDX-License-Identifier: Apache-2.0
/// The subsystem that owns an operation report or resource failure.
public enum JSONOperationDomain: String, Sendable, Codable {
    /// General value admission, traversal or construction.
    case core
    /// Strict UTF-8 parsing.
    case parsing
    /// Strict UTF-8 writing.
    case writing
    /// Native Codable encoding or decoding.
    case coding
    /// Pointer admission or navigation.
    case pointer
    /// Offline schema admission or compilation.
    case schemaCompilation
    /// Schema instance evaluation.
    case schemaEvaluation
    /// Native bounded regex work.
    case regex
    /// Staged Patch work.
    case patch
    /// Pull-stream parsing or framing.
    case streaming
}

/// The finite metric that prevented an operation from progressing.
///
/// On counter overflow, `attemptedUsage` is nil and `overflow` is true.
public struct JSONResourceViolation: Sendable, Equatable, Codable {
    /// The subsystem owning these counts or this resource failure.
    public let domain: JSONOperationDomain
    /// The resource identifier whose ceiling was exceeded.
    public let metric: JSONResourceMetric
    /// The inclusive configured ceiling for the violated metric.
    public let limit: UInt64
    /// The rejected usage, or nil when checked counter arithmetic overflowed.
    public let attemptedUsage: UInt64?
    /// Whether the attempted usage could not be represented without overflow.
    public let overflow: Bool
    package init(domain: JSONOperationDomain, metric: JSONResourceMetric, limit: UInt64,
                 attemptedUsage: UInt64?, overflow: Bool = false) {
        self.domain = domain; self.metric = metric; self.limit = limit
        self.attemptedUsage = attemptedUsage; self.overflow = overflow
    }
}
