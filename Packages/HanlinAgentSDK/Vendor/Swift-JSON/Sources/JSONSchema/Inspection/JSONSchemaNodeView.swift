// SPDX-License-Identifier: Apache-2.0
import JSON
/// A bounded raw declaration view with optional compiled reference information.
///
/// Inspection does not infer an effective schema, insert defaults or determine
/// final dynamic targets outside an evaluation scope.
public struct JSONSchemaNodeView: Sendable {
    /// The exact raw declaration, including unknown keywords and metadata.
    public let raw: JSON
    /// The location in the original document, independent of nested resource boundaries.
    public let documentPointer: JSONPointer
    /// The optional retrieval identity supplied by the caller.
    public let retrievalURI: JSONSchemaURI?
    /// All immediate declared keyword names in insertion order.
    public let declaredKeywords: [JSONKey]
    /// Immediate metadata and unknown declarations; these are not evaluation annotations.
    public let declaredAnnotations: JSONDeclaredAnnotations
    /// Immediate selected assertion declarations without inherited or inferred constraints.
    public let declaredConstraints: JSONObject
    /// The compiled resource identity, or nil when the node has no compiled resource information.
    public let resourceURI: JSONSchemaURI?
    /// The Pointer relative to the enclosing compiled resource, when available.
    public let resourcePointer: JSONPointer?
    /// Initial compiled targets, or nil for document-only inspection or a node outside the compiled graph.
    public let referenceTargets: [JSONSchemaReferenceTarget]?
    /// Looks up an immediate raw keyword without inferring an effective schema.
    ///
    /// - Returns: Absent, null or exact declared value.
    /// - Throws: Resource or configuration failure, or cancellation.
    ///
    /// - Parameters:
    ///   - key: The exact decoded-scalar key to select or insert.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public func declaration(of key: JSONKey, limits: JSONLimits = .balanced) throws -> JSONPresence<JSON> {
        var meter = try JSONWorkMeter(limits: limits, domain: .core)
        try JSONAdmission.text(key.string, key: true, meter: &meter)
        guard let object = raw.objectValue else { return .absent }
        guard let value = try object.lookup(key.string, meter: &meter) else { return .absent }
        try JSONAdmission.value(value, meter: &meter)
        return value.isNull ? .null : .value(value)
    }
    package static func inspect(_ raw: JSON, pointer: JSONPointer, retrievalURI: JSONSchemaURI?, meter: inout JSONWorkMeter) throws -> Self {
        switch raw { case .object, .boolean: break; default: throw JSONSchemaCompilationFailure(.rootKind, location: pointer) }
        try JSONAdmission.value(raw, meter: &meter)
        let annotationNames = ["title", "description", "default", "examples", "deprecated", "readOnly", "writeOnly", "$comment", "format", "contentEncoding", "contentMediaType", "contentSchema"]
        let constraintNames = ["type", "enum", "const", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf", "minLength", "maxLength", "pattern", "format", "minItems", "maxItems", "uniqueItems", "minContains", "maxContains", "minProperties", "maxProperties", "required", "dependentRequired"]
        var keywords: [JSONKey] = [], annotations: [JSONMember] = [], constraints: [JSONMember] = []
        if case .object(let object) = raw {
            for member in object {
                try meter.work(); try meter.retain(JSONLogicalWeights.arraySlot); keywords.append(member.key)
                for name in annotationNames {
                    if try JSONComparison.textEquals(member.key.string, name, meter: &meter) {
                        try meter.retain(JSONLogicalWeights.member); annotations.append(member); break
                    }
                }
                if try JSONSchemaPlan.Keyword.classify(member.key,meter: &meter) == nil {
                    try meter.retain(JSONLogicalWeights.member); annotations.append(member)
                }
                for name in constraintNames {
                    if try JSONComparison.textEquals(member.key.string, name, meter: &meter) {
                        try meter.retain(JSONLogicalWeights.member); constraints.append(member); break
                    }
                }
            }
        }
        return .init(raw: raw, documentPointer: pointer, retrievalURI: retrievalURI, declaredKeywords: keywords,
                     declaredAnnotations: .init(values: try JSONObject.indexed(admitted: annotations, meter: &meter)), declaredConstraints: try JSONObject.indexed(admitted: constraints, meter: &meter), resourceURI: nil, resourcePointer: nil, referenceTargets: nil)
    }
}
extension JSONSchemaDocument {
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
        var meter = try JSONWorkMeter(limits: limits, domain: .core)
        let admitted = try JSONPointer.decodedTokens(pointer?.tokens ?? [], meter: &meter)
        let selected = try admitted.resolve(in: raw, meter: &meter)
        let view = try JSONSchemaNodeView.inspect(selected, pointer: admitted, retrievalURI: retrievalURI, meter: &meter)
        return .init(result: view, statistics: meter.statistics())
    }
}
