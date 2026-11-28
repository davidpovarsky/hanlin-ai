// SPDX-License-Identifier: Apache-2.0
/// Finite resource policy for strict parsing.
public struct JSONParsingOptions: Sendable {
    /// Finite capacities and work quotas applied to library-owned operations.
    public var limits: JSONLimits
    /// Creates the value configuration; finite limits are checked at operation entry.
    ///
    /// - Parameters:
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public init(limits: JSONLimits = .balanced) { self.limits = limits }
}
