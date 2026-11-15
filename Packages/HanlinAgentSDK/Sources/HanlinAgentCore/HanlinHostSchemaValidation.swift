import AISDKProvider
import Foundation
import JSON
import JSONSchema

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

    /// The existing provider schema API uses Double and String dictionaries. Check its actual
    /// encode/decode projection before publishing any schema to the model. Unsupported fidelity
    /// fails closed rather than advertising a weakened assertion. Returned bytes remain original.
    public static func providerSchema(_ originalJSON: Data) throws -> Data {
        _ = try parse(originalJSON)
        let projected = try JSONDecoder().decode(AISDKProvider.JSONValue.self, from: originalJSON)
        try requireSameValue(originalJSON: originalJSON, projectedJSON: JSONEncoder().encode(projected))
        return originalJSON
    }

    private static func parse(_ data: Data) throws -> JSON {
        guard data.count <= maximumBytes else { throw Failure.inputTooLarge }
        return try JSONParser(options: .init(limits: limits)).parse(data)
    }
}
