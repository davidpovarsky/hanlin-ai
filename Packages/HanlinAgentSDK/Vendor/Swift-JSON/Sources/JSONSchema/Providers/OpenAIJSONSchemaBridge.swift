// SPDX-License-Identifier: Apache-2.0
import Foundation
import JSON

/// Offline strict Responses schema checks and exact request fragments.
///
/// This facade never calls a service, selects a model, reads credentials or rewrites
/// declarations. A compatible local profile is not a remote acceptance guarantee.
/// Each compound operation owns one finite cumulative ledger through compilation,
/// checking, metadata, envelope construction and optional native UTF-8 writing.
public struct OpenAIJSONSchemaBridge: Sendable {
    /// Frozen API purpose, revision and qualified capability category.
    public let profile: JSONSchemaProviderProfile
    /// Finite native and provider-specific local capacities.
    public let limits: JSONSchemaProviderLimits
    /// Creates an immutable facade; configuration is checked at operation entry.
    /// - Parameters:
    ///   - profile: The explicit Responses endpoint purpose.
    ///   - limits: Finite capacities for the complete owned operation.
    public init(profile: JSONSchemaProviderProfile, limits: JSONSchemaProviderLimits = .balanced) {
        self.profile = profile; self.limits = limits
    }
    /// Completes native compilation and local compatibility inspection without modifying the schema.
    /// - Parameters:
    ///   - schema: An admitted declaration; admission alone is not compilation.
    ///   - registry: Explicit offline resources. External-reference export remains incompatible.
    /// - Returns: Compatibility false for unsupported/unverified declarations.
    /// - Throws: Malformed schema, unresolved reference, resource/configuration failure or cancellation.
    public func check(_ schema: JSONSchemaDocument, registry: JSONSchemaRegistry = .empty) throws -> JSONSchemaProviderCompatibility {
        try checkWithReport(schema, registry: registry).result
    }
    /// Checks compatibility with cumulative compilation/inspection accounting.
    /// - Parameters:
    ///   - schema: The exact admitted declaration to inspect.
    ///   - registry: Immutable explicitly supplied offline resources.
    /// - Returns: Completed compatibility, including explicit issue truncation and charged work.
    /// - Throws: Native compilation, finite resource, configuration or cancellation failures.
    public func checkWithReport(_ schema: JSONSchemaDocument, registry: JSONSchemaRegistry = .empty) throws -> JSONOperationReport<JSONSchemaProviderCompatibility> {
        try limits.validate()
        var meter = try JSONWorkMeter(limits: limits.json, domain: .schemaCompilation)
        let result = try check(schema.raw, retrievalURI: schema.retrievalURI, registry: registry, meter: &meter)
        return .init(result: result, statistics: meter.statistics())
    }
    /// Returns the object inserted directly at Responses `text.format`.
    /// - Parameters:
    ///   - schema: Original exact object schema; incompatible declarations are never lowered.
    ///   - name: Nonempty ASCII letters/digits/underscore/dash, at most 64 bytes.
    ///   - description: Optional exact description under finite metadata limits.
    ///   - registry: Explicit offline resources; no external bundling is performed.
    /// - Returns: Native JSON with object-valued schema and strict true.
    /// - Throws: Profile/metadata errors, incompatible report, native error, resource failure or cancellation.
    public func responseFormat(_ schema: JSONSchemaDocument, name: String, description: String? = nil, registry: JSONSchemaRegistry = .empty) throws -> JSON {
        try responseFormatWithReport(schema, name: name, description: description, registry: registry).result
    }
    /// Returns one flat Responses function tool, not a Chat Completions wrapper.
    /// - Parameters:
    ///   - parameters: Original exact parameter schema.
    ///   - name: Endpoint name admitted by the frozen ASCII/64-byte policy.
    ///   - description: Optional exact description under finite metadata limits.
    ///   - registry: Explicit offline resources, without automatic bundling.
    /// - Returns: Native JSON with type function, object parameters and strict true.
    /// - Throws: Profile/metadata errors, incompatible report, native error, resource failure or cancellation.
    public func functionTool(_ parameters: JSONSchemaDocument, name: String, description: String? = nil, registry: JSONSchemaRegistry = .empty) throws -> JSON {
        try functionToolWithReport(parameters, name: name, description: description, registry: registry).result
    }
    /// Prepares a strict text-format fragment with complete owned accounting.
    /// - Parameters:
    ///   - schema: Exact admitted source schema.
    ///   - name: Frozen endpoint-compatible name.
    ///   - description: Optional bounded metadata.
    ///   - registry: Explicit immutable offline resources.
    /// - Returns: Complete fragment and cumulative statistics.
    /// - Throws: Strict rejection or operational/configuration failure; no successful partial report.
    public func responseFormatWithReport(_ schema: JSONSchemaDocument, name: String, description: String? = nil, registry: JSONSchemaRegistry = .empty) throws -> JSONOperationReport<JSON> {
        try valueReport(schema, name: name, description: description, registry: registry, purpose: .openAIResponsesFormatV1)
    }
    /// Prepares a strict function tool with complete owned accounting.
    /// - Parameters:
    ///   - parameters: Exact admitted source schema.
    ///   - name: Frozen endpoint-compatible name.
    ///   - description: Optional bounded metadata.
    ///   - registry: Explicit immutable offline resources.
    /// - Returns: Complete tool and cumulative statistics.
    /// - Throws: Strict rejection or operational/configuration failure; no successful partial report.
    public func functionToolWithReport(_ parameters: JSONSchemaDocument, name: String, description: String? = nil, registry: JSONSchemaRegistry = .empty) throws -> JSONOperationReport<JSON> {
        try valueReport(parameters, name: name, description: description, registry: registry, purpose: .openAIResponsesFunctionV1)
    }
    /// Serializes the complete format fragment with the native preserved-number writer.
    /// - Parameters:
    ///   - schema: Exact admitted source schema.
    ///   - name: Frozen endpoint-compatible name.
    ///   - description: Optional bounded metadata.
    ///   - registry: Explicit immutable offline resources.
    /// - Returns: UTF-8 bytes; this is not an HTTP request body wrapper.
    /// - Throws: Strict rejection or operational/configuration failure.
    public func responseFormatData(_ schema: JSONSchemaDocument, name: String, description: String? = nil, registry: JSONSchemaRegistry = .empty) throws -> Data {
        try responseFormatDataWithReport(schema, name: name, description: description, registry: registry).result
    }
    /// Serializes the complete function tool through the native writer.
    /// - Parameters:
    ///   - parameters: Exact admitted source schema.
    ///   - name: Frozen endpoint-compatible name.
    ///   - description: Optional bounded metadata.
    ///   - registry: Explicit immutable offline resources.
    /// - Returns: Complete UTF-8 tool JSON bytes.
    /// - Throws: Strict rejection or operational/configuration failure.
    public func functionToolData(_ parameters: JSONSchemaDocument, name: String, description: String? = nil, registry: JSONSchemaRegistry = .empty) throws -> Data {
        try functionToolDataWithReport(parameters, name: name, description: description, registry: registry).result
    }
    /// Serializes a text-format fragment and charges its owned String copy.
    /// - Parameters:
    ///   - schema: Exact admitted source schema.
    ///   - name: Frozen endpoint-compatible name.
    ///   - description: Optional bounded metadata.
    ///   - registry: Explicit immutable offline resources.
    /// - Returns: Complete strict UTF-8 JSON text.
    /// - Throws: Strict rejection or operational/configuration failure.
    public func responseFormatString(_ schema: JSONSchemaDocument, name: String, description: String? = nil, registry: JSONSchemaRegistry = .empty) throws -> String {
        try responseFormatStringWithReport(schema, name: name, description: description, registry: registry).result
    }
    /// Serializes a function tool and charges its owned String copy.
    /// - Parameters:
    ///   - parameters: Exact admitted source schema.
    ///   - name: Frozen endpoint-compatible name.
    ///   - description: Optional bounded metadata.
    ///   - registry: Explicit immutable offline resources.
    /// - Returns: Complete strict UTF-8 JSON tool text.
    /// - Throws: Strict rejection or operational/configuration failure.
    public func functionToolString(_ parameters: JSONSchemaDocument, name: String, description: String? = nil, registry: JSONSchemaRegistry = .empty) throws -> String {
        try functionToolStringWithReport(parameters, name: name, description: description, registry: registry).result
    }
    /// Produces bytes with one ledger through compilation, envelope, writing and Data copy.
    /// - Parameters:
    ///   - schema: Exact admitted source schema.
    ///   - name: Frozen endpoint-compatible name.
    ///   - description: Optional bounded metadata.
    ///   - registry: Explicit immutable offline resources.
    /// - Returns: UTF-8 Data and cumulative accounting.
    /// - Throws: Strict rejection or operational/configuration failure.
    public func responseFormatDataWithReport(_ schema: JSONSchemaDocument, name: String, description: String? = nil, registry: JSONSchemaRegistry = .empty) throws -> JSONOperationReport<Data> {
        let (bytes, statistics) = try bytesReport(schema, name: name, description: description, registry: registry, purpose: .openAIResponsesFormatV1)
        return .init(result: Data(bytes), statistics: statistics)
    }
    /// Produces function bytes with one ledger through every owned phase.
    /// - Parameters:
    ///   - parameters: Exact admitted source schema.
    ///   - name: Frozen endpoint-compatible name.
    ///   - description: Optional bounded metadata.
    ///   - registry: Explicit immutable offline resources.
    /// - Returns: UTF-8 Data and cumulative accounting.
    /// - Throws: Strict rejection or operational/configuration failure.
    public func functionToolDataWithReport(_ parameters: JSONSchemaDocument, name: String, description: String? = nil, registry: JSONSchemaRegistry = .empty) throws -> JSONOperationReport<Data> {
        let (bytes, statistics) = try bytesReport(parameters, name: name, description: description, registry: registry, purpose: .openAIResponsesFunctionV1)
        return .init(result: Data(bytes), statistics: statistics)
    }
    /// Produces text with one ledger, including the overlapping owned UTF-8 String copy.
    /// - Parameters:
    ///   - schema: Exact admitted source schema.
    ///   - name: Frozen endpoint-compatible name.
    ///   - description: Optional bounded metadata.
    ///   - registry: Explicit immutable offline resources.
    /// - Returns: Complete text and cumulative accounting.
    /// - Throws: Strict rejection or operational/configuration failure.
    public func responseFormatStringWithReport(_ schema: JSONSchemaDocument, name: String, description: String? = nil, registry: JSONSchemaRegistry = .empty) throws -> JSONOperationReport<String> {
        let (bytes, statistics) = try bytesReport(schema, name: name, description: description, registry: registry, purpose: .openAIResponsesFormatV1)
        return .init(result: String(decoding: bytes, as: UTF8.self), statistics: statistics)
    }
    /// Produces function text with one ledger, including its overlapping owned copy.
    /// - Parameters:
    ///   - parameters: Exact admitted source schema.
    ///   - name: Frozen endpoint-compatible name.
    ///   - description: Optional bounded metadata.
    ///   - registry: Explicit immutable offline resources.
    /// - Returns: Complete text and cumulative accounting.
    /// - Throws: Strict rejection or operational/configuration failure.
    public func functionToolStringWithReport(_ parameters: JSONSchemaDocument, name: String, description: String? = nil, registry: JSONSchemaRegistry = .empty) throws -> JSONOperationReport<String> {
        let (bytes, statistics) = try bytesReport(parameters, name: name, description: description, registry: registry, purpose: .openAIResponsesFunctionV1)
        return .init(result: String(decoding: bytes, as: UTF8.self), statistics: statistics)
    }
    private func valueReport(_ schema: JSONSchemaDocument, name: String, description: String?, registry: JSONSchemaRegistry, purpose: JSONSchemaProviderProfile) throws -> JSONOperationReport<JSON> {
        try limits.validate()
        var meter = try JSONWorkMeter(limits: limits.json, domain: .schemaCompilation)
        let value = try prepare(schema.raw, name: name, description: description, registry: registry, purpose: purpose, retrievalURI: schema.retrievalURI, meter: &meter)
        return .init(result: value, statistics: meter.statistics())
    }
    private func bytesReport(_ schema: JSONSchemaDocument, name: String, description: String?, registry: JSONSchemaRegistry, purpose: JSONSchemaProviderProfile) throws -> ([UInt8], JSONOperationStatistics) {
        try limits.validate()
        var meter = try JSONWorkMeter(limits: limits.json, domain: .schemaCompilation)
        let value = try prepare(schema.raw, name: name, description: description, registry: registry, purpose: purpose, retrievalURI: schema.retrievalURI, meter: &meter)
        let bytes = try JSONWriter(options: .init(limits: limits.json, numberStyle: .preserved)).write(value, meter: &meter)
        for _ in bytes { try meter.work(); try meter.retain(1) }
        return (bytes, meter.statistics())
    }
    package func check(_ raw: JSON, retrievalURI: JSONSchemaURI? = nil, registry: JSONSchemaRegistry, meter: inout JSONWorkMeter) throws -> JSONSchemaProviderCompatibility {
        try limits.validate(); try meter.checkpoint()
        let compiled = try JSONSchemaCompiler(options: .init(limits: meter.limits)).compile(raw, retrievalURI: retrievalURI, registry: registry, meter: &meter)
        var state = JSONSchemaProviderInspection(profile: profile, limits: limits)
        return try state.inspect(compiled, meter: &meter)
    }
    /// Borrowing composition used by the CLI; no public helper resets its ledger.
    package func prepare(_ raw: JSON, name: String, description: String?, registry: JSONSchemaRegistry,
                         purpose: JSONSchemaProviderProfile, retrievalURI: JSONSchemaURI? = nil, meter: inout JSONWorkMeter) throws -> JSON {
        try limits.validate(); try meter.checkpoint()
        guard profile == purpose else { throw JSONSchemaProviderFailure.profileMismatch }
        var state = JSONSchemaProviderInspection(profile: profile, limits: limits)
        try state.metadataText(name, meter: &meter)
        var size: UInt64 = 0
        for byte in name.utf8 {
            try meter.work(); size += 1
            guard (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 95 || byte == 45 else { throw JSONSchemaProviderFailure.invalidMetadata }
        }
        guard size > 0 && size <= 64 else { throw JSONSchemaProviderFailure.invalidMetadata }
        try JSONAdmission.text(name, key: false, meter: &meter)
        if let description { try state.metadataText(description, meter: &meter); try JSONAdmission.text(description, key: false, meter: &meter) }
        let compiled = try JSONSchemaCompiler(options: .init(limits: meter.limits)).compile(raw, retrievalURI: retrievalURI, registry: registry, meter: &meter)
        let compatibility = try state.inspect(compiled, meter: &meter)
        guard compatibility.isCompatible else { throw JSONSchemaProviderFailure.incompatible(compatibility) }
        try meter.retain(JSONLogicalWeights.member * 4)
        var members = [JSONMember("type", value: .string(purpose == .openAIResponsesFormatV1 ? "json_schema" : "function")), JSONMember("name", value: .string(name))]
        if let description { try meter.retain(JSONLogicalWeights.member); members.append(.init("description", value: .string(description))) }
        members.append(.init("strict", value: .boolean(true)))
        members.append(.init(purpose == .openAIResponsesFormatV1 ? "schema" : "parameters", value: raw))
        let value = JSON.object(try JSONObject.indexed(admitted: members, meter: &meter))
        try JSONAdmission.value(value, meter: &meter)
        return value
    }
}
