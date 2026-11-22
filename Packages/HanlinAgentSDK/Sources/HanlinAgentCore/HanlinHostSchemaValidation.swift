import AISDKProvider
import Foundation
import JSON
import HanlinExactJSONSchema
import HanlinPlatformContracts

/// A transient, bounded validation plan. JSON/JSONSchema are implementation details, not a
/// second canonical value, transcript, permission authority or persistent store.
public struct HanlinHostSchemaValidation: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        case inputTooLarge, invalidArguments, lossyProjection, unsupportedSchema
    }

    private let plan: CompiledJSONSchema
    private static let maximumBytes = 1_048_576
    private static var limits: JSONLimits {
        var limits = JSONLimits.conservative
        limits[.inputBytes] = UInt64(maximumBytes)
        limits[.schemaBytes] = UInt64(maximumBytes)
        return limits
    }
    private static var options: JSONSchemaOptions { .init(limits: limits, formatAssertion: false,
        output: .basic, diagnosticPolicy: .complete, collectAnnotations: false) }

    public init(schemaJSON: Data) throws {
        try Task.checkCancellation()
        let schema = try Self.parse(schemaJSON)
        // Explicit empty offline registry: unresolved external refs fail; no network fetching.
        plan = try JSONSchemaCompiler(options: Self.options).compileWithReport(schema, registry: .empty).result
        try Task.checkCancellation()
    }

    public func validate(argumentsJSON: Data) throws {
        try Task.checkCancellation()
        let value = try Self.parse(argumentsJSON)
        let verdict = try plan.validate(value, options: Self.options)
        guard verdict.isValid, verdict.diagnosticsComplete else { throw Failure.invalidArguments }
        try Task.checkCancellation()
    }

    /// Capture exact schema values at the original MCP wire boundary, before MCP.Value
    /// or Foundation dictionaries can round numbers or coalesce Unicode keys.
    /// Keys are base64 UTF-8 tool names, preserving scalar spelling across Swift dictionaries.
    public static func mcpToolSchemas(responseJSON: Data) throws -> [String: Data] {
        let root = try parse(responseJSON)
        guard case .object(let envelope) = root,
              case .object(let result)? = envelope["result"],
              case .array(let tools)? = result["tools"] else { return [:] }
        guard tools.count <= 256 else { throw Failure.inputTooLarge }
        var schemas: [String: Data] = [:]
        for item in tools {
            guard case .object(let tool) = item, case .string(let name)? = tool["name"],
                  !name.isEmpty, let schema = tool["inputSchema"] else { throw Failure.invalidArguments }
            let key = Data(name.utf8).base64EncodedString()
            guard schemas[key] == nil else { throw Failure.invalidArguments }
            var bounded = limits
            bounded[.outputBytes] = UInt64(maximumBytes)
            schemas[key] = try JSONWriter(options: .init(limits: bounded, keyOrder: .scalar, numberStyle: .normalized)).write(schema)
        }
        return schemas
    }

    /// Proves semantic identity using exact decimals and scalar keys/strings with a finite budget.
    /// Only the named top-level host metadata keys may be removed by the existing executor adapter.
    public static func requireSameValue(originalJSON: Data, projectedJSON: Data,
                                        removingMetadataKeys: [String] = []) throws {
        try Task.checkCancellation()
        var original = try parse(originalJSON)
        if !removingMetadataKeys.isEmpty {
            guard removingMetadataKeys.count <= 2 else { throw Failure.lossyProjection }
            if case .object(var object) = original {
                for key in removingMetadataKeys { object = try object.removing(JSONKey(key), limits: limits) }
                original = .object(object)
            }
        }
        let projection = try parse(projectedJSON)
        guard try JSONComparison.equals(original, projection, limits: limits) else { throw Failure.lossyProjection }
        try Task.checkCancellation()
    }

    /// The portable DTO deliberately uses binary64 numbers. Prove that it is the
    /// deterministic projection of the retained original; it is never an executor input.
    /// Exact original-schema and original-to-executor comparisons remain mandatory.
    public static func requirePortableProjection(originalJSON: Data, projected: HanlinJSONValue) throws {
        _ = try parse(originalJSON)
        let expected = try HanlinJSONValue.decodeCanonicalJSON(originalJSON)
        guard try expected.canonicalJSONData() == projected.canonicalJSONData() else {
            throw Failure.lossyProjection
        }
        try Task.checkCancellation()
    }

    /// Reads only declared identity fields for a consent scope. Non-string identities
    /// fail closed; other payload data never enters a durable grant.
    public static func topLevelStringFields(argumentsJSON: Data, keys: [String]) throws -> [String: String] {
        guard keys.count <= 32, keys.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }) else {
            throw Failure.inputTooLarge
        }
        guard case .object(let object) = try parse(argumentsJSON) else { throw Failure.invalidArguments }
        var fields: [String: String] = [:]
        for key in keys {
            guard let value = object[key] else { continue }
            guard case .string(let text) = value else { throw Failure.invalidArguments }
            fields[key] = text
        }
        return fields
    }

    /// Removes only the named top-level host fields using exact decimal/scalar JSON.
    /// Nested coordinates, integers, object keys, and string spellings are retained.
    public static func extractStringMetadata(
        argumentsJSON: Data, keys: [String]
    ) throws -> (argumentsJSON: Data, strings: [String: String], presentKeys: Set<String>) {
        guard keys.count <= 2, Set(keys).count == keys.count else { throw Failure.lossyProjection }
        let root = try parse(argumentsJSON)
        guard case .object(var object) = root else { return (argumentsJSON, [:], []) }
        var strings: [String: String] = [:]
        var present: Set<String> = []
        for key in keys {
            guard let value = object[key] else { continue }
            present.insert(key)
            if case .string(let text) = value { strings[key] = text }
            object = try object.removing(JSONKey(key), limits: limits)
        }
        // Do not rewrite an untouched document at all.
        guard !present.isEmpty else { return (argumentsJSON, strings, present) }
        var bounded = limits
        bounded[.outputBytes] = UInt64(maximumBytes)
        let bytes = try JSONWriter(options: .init(
            limits: bounded, keyOrder: .scalar, numberStyle: .normalized
        )).write(.object(object))
        try Task.checkCancellation()
        return (bytes, strings, present)
    }

    /// The existing provider schema API uses Double and String dictionaries. Check its actual
    /// encode/decode projection before publishing any schema to the model. Unsupported fidelity
    /// fails closed rather than advertising a weakened assertion. Returned bytes remain original.
    public static func providerSchema(_ originalJSON: Data) throws -> Data {
        _ = try parse(originalJSON)
        let projected = try JSONDecoder().decode(AISDKProvider.JSONValue.self, from: originalJSON)
        try requireSameValue(originalJSON: originalJSON, projectedJSON: JSONEncoder().encode(projected))
        return originalJSON
    }

    /// Deterministic exact JSON bytes for DTO fingerprints. Uses the already approved bounded
    /// parser/writer, scalar key ordering and exact decimal normalization, never a Double bridge.
    /// This is a local encoding contract, not a claim of an external signature canonicalization.
    public static func deterministicJSONData(_ originalJSON: Data) throws -> Data {
        try Task.checkCancellation()
        let value = try parse(originalJSON)
        var bounded = limits
        bounded[.outputBytes] = UInt64(maximumBytes)
        let bytes = try JSONWriter(options: .init(limits: bounded, keyOrder: .scalar, numberStyle: .normalized)).write(value)
        try Task.checkCancellation()
        return bytes
    }

    private static func parse(_ data: Data) throws -> JSON {
        guard data.count <= maximumBytes else { throw Failure.inputTooLarge }
        return try JSONParser(options: .init(limits: limits)).parse(data)
    }
}
