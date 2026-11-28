// SPDX-License-Identifier: Apache-2.0
/// Exact decoded-scalar key matching for preview redaction.
///
/// Matching performs no case folding or Unicode normalization.
public struct JSONRedaction: Sendable {
    /// Exact scalar keys selected for redaction.
    public var keys: [JSONKey]
    /// Selects exact decoded-scalar keys to redact before visiting their payloads.
    ///
    /// - Parameters:
    ///   - keys: Exact scalar keys to redact before visiting payloads.
    public init(keys: [JSONKey] = ["password", "secret", "token", "access_token", "refresh_token", "api_key", "authorization", "client_secret", "private_key"]) { self.keys = keys }
    package func matches(_ key: JSONKey, meter: inout JSONWorkMeter) throws -> Bool {
        for candidate in keys { if try JSONComparison.textEquals(candidate.string, key.string, meter: &meter) { return true } }
        return false
    }
}
