// SPDX-License-Identifier: Apache-2.0
import JSON

extension JSONCompositionScope {
    /// Normalizes an offline URI using this composition's core ledger.
    ///
    /// URI identity is not a compiled plan: compiledPlanBytes and compileWorkUnits
    /// remain untouched. A supplied base is admitted and retained conservatively.
    /// - Parameters:
    ///   - text: Absolute URI or relative reference.
    ///   - base: Explicit normalized base for a relative reference; never fetched.
    /// - Returns: Native normalized URI identity.
    /// - Throws: Native identifier/resource failure or cancellation, permanently terminal.
    public func uri(_ text: String, relativeTo base: JSONSchemaURI? = nil) throws -> JSONSchemaURI {
        try withMeter { meter in
            if let base { try JSONAdmission.text(base.string, meter: &meter, owned: true) }
            return try JSONSchemaURI.parse(text, relativeTo: base, meter: &meter)
        }
    }

    /// Returns the native resource identity without its fragment on the same ledger.
    /// - Parameter uri: Caller or scope-created identity, re-admitted before use.
    /// - Returns: Normalized URI without its fragment.
    /// - Throws: Native identifier/resource failure or cancellation, permanently terminal.
    public func removingFragment(_ uri: JSONSchemaURI) throws -> JSONSchemaURI {
        try withMeter { meter in
            let admitted = try JSONSchemaURI.parse(uri.string, relativeTo: nil, meter: &meter)
            // Avoid the ordinary unmetered fragment convenience (including its
            // substring allocation). Charge and checkpoint this discovery scan.
            var fragmentPresent = false
            for byte in admitted.string.utf8 {
                try meter.work()
                if byte == 35 { fragmentPresent = true; break }
            }
            return try admitted.withoutFragment(meter: &meter, fragmentPresent: fragmentPresent)
        }
    }
}
