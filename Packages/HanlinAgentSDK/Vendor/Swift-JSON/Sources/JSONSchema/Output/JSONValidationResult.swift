// SPDX-License-Identifier: Apache-2.0
import JSON

/// An annotation produced by a successful evaluation branch at an instance location.
public struct JSONEvaluationAnnotation: Sendable {
    /// The Pointer to the instance location that produced the issue or annotation.
    public let instanceLocation: JSONPointer
    /// The Pointer to the evaluated schema keyword.
    public let keywordLocation: JSONPointer
    /// The resolved keyword URI, when available.
    public let absoluteKeywordLocation: JSONSchemaURI?
    /// The exact keyword name associated with the issue, annotation or reference.
    public let keyword: JSONKey
    /// The exact annotation payload collected from a successful branch.
    public let value: JSON
    /// Creates an annotation record from explicit locations, keyword and exact payload.
    ///
    /// - Parameters:
    ///   - instanceLocation: The instance Pointer.
    ///   - keywordLocation: The schema keyword Pointer.
    ///   - absoluteKeywordLocation: The optional absolute keyword URI.
    ///   - keyword: The exact keyword name.
    ///   - value: The exact annotation payload; this record initializer performs no admission.
    public init(instanceLocation: JSONPointer, keywordLocation: JSONPointer, absoluteKeywordLocation: JSONSchemaURI?, keyword: JSONKey, value: JSON) {
        self.instanceLocation = instanceLocation; self.keywordLocation = keywordLocation
        self.absoluteKeywordLocation = absoluteKeywordLocation; self.keyword = keyword; self.value = value
    }
}

/// A completed validation verdict and the diagnostics actually collected.
///
/// Operational failures throw before a result exists. Best-effort collection may
/// be incomplete while the semantic verdict still completes.
public struct JSONValidationResult: Sendable {
    /// The completed semantic verdict; false means ordinary invalidity, not an operational failure.
    public let isValid: Bool
    /// The diagnostic format collected; a flag result cannot be upgraded to invent basic issues.
    public let outputStyle: JSONValidationOutput
    /// The issues actually retained under the selected output and diagnostic policy.
    public let issues: [JSONValidationIssue]
    /// The output annotations actually retained from successful evaluation branches.
    public let annotations: [JSONEvaluationAnnotation]
    /// Whether requested diagnostics were fully collected; independent of ordinary validity.
    public let diagnosticsComplete: Bool
    package init(isValid: Bool, outputStyle: JSONValidationOutput, issues: [JSONValidationIssue], annotations: [JSONEvaluationAnnotation], diagnosticsComplete: Bool) {
        self.isValid = isValid; self.outputStyle = outputStyle; self.issues = issues; self.annotations = annotations; self.diagnosticsComplete = diagnosticsComplete
    }
}
