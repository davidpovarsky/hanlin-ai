// SPDX-License-Identifier: Apache-2.0
import JSON

/// An immutable validator with invocation-owned evaluation state.
///
/// A completed false verdict means ordinary invalidity. Resource exhaustion,
/// cancellation and evaluation errors throw through applicators and references.
public struct JSONSchemaValidator: Sendable {
    /// The immutable configuration used to create each invocation.
    public let options: JSONSchemaOptions
    /// Creates an immutable validator facade; each call owns independent evaluation state.
    ///
    /// - Parameters:
    ///   - options: The value configuration used by this facade or operation.
    public init(options: JSONSchemaOptions = .init()) { self.options = options }
    /// Evaluates one admitted instance against a shareable offline plan.
    ///
    /// - Returns: A completed valid or invalid verdict.
    /// - Throws: Evaluation errors, resource exhaustion or cancellation; these are not false verdicts.
    ///
    /// - Parameters:
    ///   - instance: The exact JSON instance to admit and evaluate.
    ///   - schema: The immutable compiled offline plan.
    public func validate(_ instance: JSON, against schema: CompiledJSONSchema) throws -> JSONValidationResult {
        try validateWithReport(instance, against: schema).result
    }
    /// Evaluates an admitted instance and reports successful cumulative evaluation work.
    ///
    /// - Returns: A valid or invalid verdict and charged counts.
    /// - Throws: Operational evaluation errors, resource exhaustion or cancellation; none is ordinary invalidity.
    ///
    /// - Parameters:
    ///   - instance: The exact JSON instance to admit and evaluate.
    ///   - schema: The immutable compiled offline plan.
    public func validateWithReport(_ instance: JSON, against schema: CompiledJSONSchema) throws -> JSONOperationReport<JSONValidationResult> {
        var meter = try JSONWorkMeter(limits: options.limits, domain: .schemaEvaluation)
        let result = try validate(instance, against: schema, meter: &meter)
        return .init(result: result, statistics: meter.statistics())
    }
    package func validate(_ instance: JSON, against schema: CompiledJSONSchema, meter: inout JSONWorkMeter) throws -> JSONValidationResult {
        try JSONAdmission.value(instance, meter: &meter)
        var evaluator = JSONSchemaEvaluation(plan: schema.plan, options: options)
        let result = try evaluator.evaluate(instance, at: schema.plan.root, meter: &meter)
        return result
    }
}
