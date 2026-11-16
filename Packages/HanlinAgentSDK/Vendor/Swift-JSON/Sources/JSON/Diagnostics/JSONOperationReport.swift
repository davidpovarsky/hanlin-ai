// SPDX-License-Identifier: Apache-2.0
/// A successful operation result paired with versioned resource accounting.
///
/// Reports contain no clocks or payloads in their statistics. A report is Sendable
/// when its result is Sendable. A thrown operation produces no successful report.
public struct JSONOperationReport<Result> {
    /// The successful operation result.
    public let result: Result
    /// Versioned accounting for the completed operation or cumulative stream lifetime.
    public let statistics: JSONOperationStatistics
    /// Pairs a successful result with its already recorded accounting.
    ///
    /// - Parameters:
    ///   - result: The successful operation result.
    ///   - statistics: Already recorded successful operation accounting.
    public init(result: Result, statistics: JSONOperationStatistics) {
        self.result = result; self.statistics = statistics
    }
}
extension JSONOperationReport: Sendable where Result: Sendable {}
