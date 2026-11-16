// SPDX-License-Identifier: Apache-2.0
import JSON
/// Immutable explicitly supplied schema resources without network resolution.
///
/// Each document requires an unambiguous retrieval URI. There is no global cache.
public struct JSONSchemaRegistry: Sendable {
    /// The immutable externally supplied resource documents.
    public let documents: [JSONSchemaDocument]
    /// An immutable registry with no external resources.
    public static let empty = Self(admitted: [])
    /// Admits explicit offline documents with unambiguous retrieval URIs.
    ///
    /// - Throws: Missing/duplicate resource identity, resource failure or cancellation.
    ///
    /// - Parameters:
    ///   - documents: Explicit offline resources, each with an unambiguous retrieval URI.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public init(documents: [JSONSchemaDocument] = [], limits: JSONLimits = .balanced) throws {
        var meter = try JSONWorkMeter(limits: limits, domain: .schemaCompilation)
        try meter.require(.schemaDocuments, UInt64(documents.count))
        var admitted: [JSONSchemaDocument] = [], uris: [JSONSchemaURI] = []
        for document in documents {
            guard let uri = document.retrievalURI else { throw JSONSchemaCompilationFailure(.identifier) }
            let key = try uri.withoutFragment(meter: &meter)
            for previous in uris {
                if try JSONComparison.textEquals(previous.string, key.string, meter: &meter) { throw JSONSchemaCompilationFailure(.identifier) }
            }
            try meter.resetValueBounds(); try JSONAdmission.value(document.raw, meter: &meter, owned: true)
            try meter.work(); try meter.retain(JSONLogicalWeights.frame)
            admitted.append(document); uris.append(key)
        }
        self.documents = admitted
    }
    /// Returns a registry admitting one additional unambiguous offline resource.
    ///
    /// - Throws: Missing/duplicate retrieval identity, resource failure or cancellation.
    ///
    /// - Parameters:
    ///   - document: The admitted schema document with an absolute retrieval URI.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public func adding(_ document: JSONSchemaDocument, limits: JSONLimits = .balanced) throws -> Self {
        var meter = try JSONWorkMeter(limits: limits, domain: .schemaCompilation)
        try meter.require(.schemaDocuments, UInt64(documents.count) + 1)
        var copy: [JSONSchemaDocument] = []
        for item in documents { try meter.work(); try meter.retain(JSONLogicalWeights.frame); copy.append(item) }
        try meter.retain(JSONLogicalWeights.frame); copy.append(document)
        return try Self.checked(copy, meter: &meter)
    }
    package static func checked(_ documents: [JSONSchemaDocument], meter: inout JSONWorkMeter) throws -> Self {
        var keys: [JSONSchemaURI] = []
        for document in documents {
            guard let uri = document.retrievalURI else { throw JSONSchemaCompilationFailure(.identifier) }
            let key = try uri.withoutFragment(meter: &meter)
            for previous in keys { if try JSONComparison.textEquals(previous.string, key.string, meter: &meter) { throw JSONSchemaCompilationFailure(.identifier) } }
            try meter.resetValueBounds(); try JSONAdmission.value(document.raw, meter: &meter, owned: true)
            try meter.work(); try meter.retain(JSONLogicalWeights.frame); keys.append(key)
        }
        return Self(admitted: documents)
    }
    package init(admitted documents: [JSONSchemaDocument]) { self.documents = documents }
}
