// SPDX-License-Identifier: Apache-2.0
/// An ordinary read failure with a complete bounded typed path and no JSON payload.
///
/// Resource failures, limit configuration errors and cancellation keep their own
/// types. A mapped read can attach the selected value or missing member's parent
/// location to the cause. Replaced/unmapped documents never invent a location.
public struct JSONAccessFailure: Error, Sendable {
    /// The stable navigation, kind or conversion failure, with an optional source location.
    public let cause: JSONFailure
    /// The exact attempted key/index path, including the failing hop.
    public let path: [JSONLocationComponent]
    package init(cause: JSONFailure, path: [JSONLocationComponent]) { self.cause = cause; self.path = path }
}
