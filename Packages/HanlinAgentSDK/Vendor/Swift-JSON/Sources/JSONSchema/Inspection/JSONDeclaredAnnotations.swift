// SPDX-License-Identifier: Apache-2.0
import JSON
/// Raw declaration annotations, separate from evaluation annotations.
///
/// Defaults never mutate instances; unknown keyword metadata remains available.
public struct JSONDeclaredAnnotations: Sendable {
    /// Immediate declared annotation values, including unknown metadata.
    public let values: JSONObject
    /// Distinguishes absent, null and present non-null members using exact scalar keys.
    ///
    /// - Parameters:
    ///   - key: The exact decoded-scalar key to select or insert.
    public func presence(of key: JSONKey) -> JSONPresence<JSON> { values.presence(of: key) }
    package init(values: JSONObject) { self.values = values }
}
