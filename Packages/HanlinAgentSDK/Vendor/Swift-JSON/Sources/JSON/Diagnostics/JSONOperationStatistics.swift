// SPDX-License-Identifier: Apache-2.0
/// Versioned charged counts and peak logical retention for one operation.
///
/// Logical bytes are accounting weights, not allocation sizes or RSS. Capacity-only
/// predicates report zero; subsystem work is already included in aggregate work.
public struct JSONOperationStatistics: Sendable, Equatable {
    /// The logical accounting version; version 1 uses the published logical weights.
    public let accountingVersion: UInt32
    /// The subsystem owning these counts or this resource failure.
    public let domain: JSONOperationDomain
    private let counters: [UInt64]
    /// The peak concurrently retained logical bytes; this is not RSS or allocator size.
    public let peakLogicalRetainedBytes: UInt64
    /// Returns the charged count for a metric; capacity-only predicates report zero.
    ///
    /// - Parameters:
    ///   - metric: The resource metric whose charged count to read.
    public subscript(metric: JSONResourceMetric) -> UInt64 { counters[metric.index] }
    package init(domain: JSONOperationDomain, counters: [UInt64], peak: UInt64) {
        accountingVersion = JSONLogicalWeights.version
        self.domain = domain; self.counters = counters; peakLogicalRetainedBytes = peak
    }
}
