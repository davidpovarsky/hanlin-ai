// SPDX-License-Identifier: Apache-2.0
import JSON

/// An immutable offline Draft 2020-12 compilation snapshot.
///
/// The plan and its regex programs can be shared across tasks. Each validation owns
/// its mutable state; declaration inspection does not infer an effective schema.
public struct CompiledJSONSchema: Sendable {
    /// The admitted root schema document retained by this compiled snapshot.
    public let document: JSONSchemaDocument
    package let plan: JSONSchemaPlan
    package init(document: JSONSchemaDocument, plan: JSONSchemaPlan) { self.document = document; self.plan = plan }
    /// Evaluates an instance using this immutable offline plan without recompiling it.
    ///
    /// Delegates to `JSONSchemaValidator.validate(_:against:)`; each call owns its
    /// state and one cumulative evaluation budget. Use the validator's report API
    /// for successful accounting. Compilation options are not evaluation defaults.
    /// - Parameters:
    ///   - instance: The exact instance to admit and evaluate.
    ///   - options: Evaluation, diagnostic and format policies forwarded unchanged.
    /// - Returns: A completed verdict; false means ordinary schema invalidity.
    /// - Throws: Operational evaluation, resource or configuration failure, or cancellation.
    public func validate(_ instance: JSON, options: JSONSchemaOptions = .init()) throws -> JSONValidationResult {
        try JSONSchemaValidator(options: options).validate(instance, against: self)
    }
    /// Inspects one raw object or boolean declaration, optionally at a document Pointer.
    ///
    /// - Returns: Immediate declarations; compiled inspection may add initial reference targets.
    /// - Throws: Missing/invalid location, wrong schema kind, resource failure or cancellation.
    ///
    /// - Parameters:
    ///   - pointer: The optional document Pointer; nil selects the root.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public func node(at pointer: JSONPointer? = nil, limits: JSONLimits = .balanced) throws -> JSONSchemaNodeView {
        try nodeWithReport(at: pointer, limits: limits).result
    }
    /// Inspects a declaration with bounded traversal and successful accounting.
    ///
    /// - Returns: Raw declarations and optional compiled resource/target information.
    /// - Throws: Pointer/schema-kind errors, resource failure or cancellation.
    ///
    /// - Parameters:
    ///   - pointer: The optional document Pointer; nil selects the root.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public func nodeWithReport(at pointer: JSONPointer? = nil, limits: JSONLimits = .balanced) throws -> JSONOperationReport<JSONSchemaNodeView> {
        var meter = try JSONWorkMeter(limits: limits,domain: .core)
        let admitted = try JSONPointer.decodedTokens(pointer?.tokens ?? [],meter: &meter)
        let raw = try admitted.resolve(in: document.raw,meter: &meter)
        let view = try JSONSchemaNodeView.inspect(raw,pointer: admitted,retrievalURI: document.retrievalURI,meter: &meter)
        var selected: Int?
        for i in plan.nodes.indices {
            try meter.work(); let node = plan.nodes[i]
            guard node.document == plan.nodes[plan.root].document, node.pointer.tokens.count == admitted.tokens.count else { continue }
            var same = true
            for j in admitted.tokens.indices { if try !JSONComparison.textEquals(node.pointer.tokens[j].string,admitted.tokens[j].string,meter: &meter) { same = false; break } }
            if same { selected = i; break }
        }
        guard let selected else { return .init(result: view,statistics: meter.statistics()) }
        let node = plan.nodes[selected], resource = plan.resources[node.resource]
        let location = try JSONPointer.decodedTokens(node.pointer.tokens.dropFirst(plan.nodes[resource.root].pointer.tokens.count),meter: &meter)
        var targets: [JSONSchemaReferenceTarget] = []
        for reference in node.references {
            try meter.work(); try meter.retain(64)
            let target = plan.nodes[reference.target], resource = plan.resources[target.resource]
            let pointer = try JSONPointer.decodedTokens(target.pointer.tokens.dropFirst(plan.nodes[resource.root].pointer.tokens.count),meter: &meter)
            targets.append(.init(keyword: try JSONKey(reference.keyword.rawValue,meter: &meter),resourceURI: resource.uri,pointer: pointer,requiresDynamicScope: reference.dynamicAnchor != nil))
        }
        let result = JSONSchemaNodeView(raw: view.raw,documentPointer: view.documentPointer,retrievalURI: view.retrievalURI,
            declaredKeywords: view.declaredKeywords,declaredAnnotations: view.declaredAnnotations,declaredConstraints: view.declaredConstraints,
            resourceURI: resource.uri,resourcePointer: location,referenceTargets: targets)
        return .init(result: result,statistics: meter.statistics())
    }
}
