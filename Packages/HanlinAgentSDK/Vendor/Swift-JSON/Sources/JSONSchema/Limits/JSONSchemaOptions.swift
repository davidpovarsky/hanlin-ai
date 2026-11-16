// SPDX-License-Identifier: Apache-2.0
import JSON
/// Finite schema budgets, format policy and bounded diagnostic choices.
///
/// Format is annotation by default. Explicit assertion or a required assertion
/// vocabulary enables recognizers. Content annotations do not decode instance data.
public struct JSONSchemaOptions: Sendable {
    /// Finite capacities and work quotas applied to library-owned operations.
    public var limits: JSONLimits
    /// Whether optional known formats are asserted in addition to required vocabulary behavior.
    public var formatAssertion: Bool
    /// The flag or basic diagnostic format collected during evaluation.
    public var output: JSONValidationOutput
    /// Complete diagnostics throw on exhaustion; best-effort collection records incompleteness.
    public var diagnosticPolicy: JSONValidationDiagnosticPolicy
    /// Whether to retain output annotations from successful evaluation branches.
    public var collectAnnotations: Bool
    /// Creates the value configuration; finite limits are checked at operation entry.
    ///
    /// - Parameters:
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    ///   - formatAssertion: Enable optional known native format assertions.
    ///   - output: The diagnostics to collect.
    ///   - diagnosticPolicy: Complete or explicit best-effort diagnostics.
    ///   - collectAnnotations: Retain output annotations from successful branches.
    public init(limits: JSONLimits = .balanced, formatAssertion: Bool = false, output: JSONValidationOutput = .basic, diagnosticPolicy: JSONValidationDiagnosticPolicy = .complete, collectAnnotations: Bool = false) {
        self.limits = limits; self.formatAssertion = formatAssertion; self.output = output
        self.diagnosticPolicy = diagnosticPolicy; self.collectAnnotations = collectAnnotations
    }
}
