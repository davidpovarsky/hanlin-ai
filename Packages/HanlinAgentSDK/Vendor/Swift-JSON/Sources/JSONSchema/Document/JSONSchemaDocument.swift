// SPDX-License-Identifier: Apache-2.0
import JSON
/// An admitted object or boolean schema preserving every raw declaration.
///
/// Unknown annotation keywords remain inspectable. Admission alone does not prove
/// that a schema is compilable; the compiler is the dialect authority.
public struct JSONSchemaDocument: Sendable {
    /// The exact raw declaration, including unknown keywords and metadata.
    public let raw: JSON
    /// The optional retrieval identity supplied by the caller.
    public let retrievalURI: JSONSchemaURI?
    /// Optional bounded mapping from typed value paths to original source byte spans.
    public let sourceMap: JSONSourceMap?
    /// Admits an object or Boolean schema while preserving raw declarations and optional source mapping.
    ///
    /// - Throws: Root-kind, resource or configuration failure, or cancellation. Compilation is a separate step.
    ///
    /// - Parameters:
    ///   - raw: The exact raw object or Boolean schema.
    ///   - retrievalURI: An optional absolute retrieval identity; this does not fetch resources.
    ///   - sourceMap: Optional coherent source spans.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public init(_ raw: JSON, retrievalURI: JSONSchemaURI? = nil, sourceMap: JSONSourceMap? = nil, limits: JSONLimits = .balanced) throws {
        var meter = try JSONWorkMeter(limits: limits, domain: .schemaCompilation)
        try self.init(raw, retrievalURI: retrievalURI, sourceMap: sourceMap, meter: &meter)
    }
    package init(_ raw: JSON, retrievalURI: JSONSchemaURI? = nil, sourceMap: JSONSourceMap? = nil, meter: inout JSONWorkMeter) throws {
        switch raw { case .object, .boolean: break; default: throw JSONSchemaCompilationFailure(.rootKind) }
        try JSONAdmission.value(raw, meter: &meter)
        self.raw = raw; self.retrievalURI = retrievalURI; self.sourceMap = sourceMap
    }
    package init(admitted raw: JSON, retrievalURI: JSONSchemaURI) {
        self.raw = raw; self.retrievalURI = retrievalURI; sourceMap = nil
    }
    /// Admits an object or Boolean schema while preserving raw declarations and optional source mapping.
    ///
    /// - Throws: Root-kind, resource or configuration failure, or cancellation. Compilation is a separate step.
    ///
    /// - Parameters:
    ///   - document: The parsed source document whose root and source map to retain.
    ///   - retrievalURI: An optional absolute retrieval identity; this does not fetch resources.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public init(_ document: JSONDocument, retrievalURI: JSONSchemaURI? = nil, limits: JSONLimits = .balanced) throws {
        try self.init(document.root, retrievalURI: retrievalURI, sourceMap: document.sourceMap, limits: limits)
    }
}
