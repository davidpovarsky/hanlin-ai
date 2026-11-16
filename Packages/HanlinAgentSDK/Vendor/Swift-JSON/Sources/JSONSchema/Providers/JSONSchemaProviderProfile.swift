// SPDX-License-Identifier: Apache-2.0
import JSON

/// Frozen local checks for Responses base-model schemas; never a remote acceptance guarantee.
public enum JSONSchemaProviderProfile: String, Sendable, CaseIterable {
    /// Contents of Responses `text.format`, using the documented base-model subset.
    case openAIResponsesFormatV1 = "openai.responses.text-format.v1"
    /// One Responses function tool, using the documented base-model subset.
    case openAIResponsesFunctionV1 = "openai.responses.function.v1"
    /// The policy revision; changing provider documentation never changes this profile at runtime.
    public var revision: String { "2026-10-15.v1" }
    /// The provider described by these local rules.
    public var provider: String { "openai" }
    /// Qualified capability category; fine-tuned and unspecified model behavior is not inferred.
    public var capabilityCategory: String { "documented-base-model-subset" }
}

/// Additional finite admission capacities; existing JSON limits also apply cumulatively.
public struct JSONSchemaProviderLimits: Sendable {
    /// Native compilation, text, diagnostic, output and logical retention limits.
    public var json: JSONLimits
    /// Caller-schema graph nodes, excluding native meta-schema bootstrap nodes.
    public var schemaNodes: UInt64
    /// Caller-schema child and reference edges, without recursive expansion.
    public var referenceEdges: UInt64
    /// Immediate declarations across checked caller-schema nodes.
    public var declarations: UInt64
    /// UTF-8 bytes of envelope and schema title/description metadata.
    public var metadataBytes: UInt64
    /// Creates finite capacities. Zero forbids use; invalid capacities throw at operation entry.
    /// - Parameters:
    ///   - json: Native limits shared by every owned phase.
    ///   - schemaNodes: Maximum inspected schema nodes.
    ///   - referenceEdges: Maximum inspected child/reference edges.
    ///   - declarations: Maximum inspected keyword declarations.
    ///   - metadataBytes: Maximum UTF-8 metadata bytes.
    public init(json: JSONLimits = .balanced, schemaNodes: UInt64 = 10_000,
                referenceEdges: UInt64 = 20_000, declarations: UInt64 = 100_000,
                metadataBytes: UInt64 = 262_144) {
        self.json = json; self.schemaNodes = schemaNodes; self.referenceEdges = referenceEdges
        self.declarations = declarations; self.metadataBytes = metadataBytes
    }
    /// Finite default policy; logical byte capacities are not process RSS guarantees.
    public static var balanced: Self { .init() }
    /// Smaller finite local capacities.
    public static var conservative: Self { .init(json: .conservative, schemaNodes: 2_000, referenceEdges: 4_000, declarations: 20_000, metadataBytes: 32_768) }
    /// Larger finite local capacities; provider ceilings remain unchanged.
    public static var offline: Self { .init(json: .offline, schemaNodes: 100_000, referenceEdges: 200_000, declarations: 1_000_000, metadataBytes: 1_048_576) }
    package func validate() throws {
        try json.validate()
        for cap in [schemaNodes, referenceEdges, declarations, metadataBytes] {
            guard cap < UInt64.max else { throw JSONSchemaProviderFailure.invalidConfiguration }
        }
    }
}

/// Additional provider-operation accounting; these do not redefine the 49 native metrics.
public enum JSONSchemaProviderMetric: String, Sendable {
    /// Number of caller-schema nodes inspected.
    case schemaNodes
    /// Number of caller-schema child/reference edges inspected.
    case referenceEdges
    /// Number of immediate keyword declarations inspected.
    case declarations
    /// Number of owned UTF-8 metadata bytes admitted.
    case metadataBytes
}

/// Fixed diagnostic codes; rejected payloads are never retained as messages.
public enum JSONSchemaProviderIssueCode: String, Sendable {
    /// A strict Responses schema must declare an object root without a root union.
    case objectRootRequired
    /// An object must explicitly forbid additional properties.
    case closedObjectRequired
    /// All declared properties must be explicitly required; absence is not rewritten as null.
    case allPropertiesRequired
    /// The declaration lies outside the documented subset.
    case unsupportedKeyword
    /// The declaration or combination has not been qualified by this revision.
    case unverifiedDeclaration
    /// A format has not been qualified by this profile.
    case unsupportedFormat
    /// External reference export has no qualified bundling policy.
    case externalReference
    /// A reference/combinator cycle provides no qualified productive declaration.
    case nonProductiveReference
    /// A frozen provider ceiling or explicitly documented conservative local rule was exceeded.
    case profileCapacity
    /// A Boolean schema is outside the strict subset, except object closure declarations.
    case booleanSchema
}

/// One exact typed schema location and fixed explanation, with no rejected value payload.
public struct JSONSchemaProviderIssue: Sendable {
    /// The bounded reason for incompatibility.
    public let code: JSONSchemaProviderIssueCode
    /// Property keys remain keys; combinator array positions remain indices.
    public let path: [JSONLocationComponent]
    /// Whether the declaration is unverified rather than known unsupported by this revision.
    public let unverified: Bool
    /// Fixed explanation independent of caller-controlled text.
    public var explanation: String {
        switch code {
        case .objectRootRequired: "A strict Responses root must explicitly declare object type without a root union or reference."
        case .closedObjectRequired: "Every object declaration must explicitly set additionalProperties to false."
        case .allPropertiesRequired: "Every declared property must be required; omitted and nullable have different meanings."
        case .unsupportedKeyword: "This keyword is outside the selected strict subset."
        case .unverifiedDeclaration: "This declaration or combination is not qualified by the selected local revision."
        case .unsupportedFormat: "This format is outside the qualified base-model format list."
        case .externalReference: "External references cannot be exported without a qualified bundling policy."
        case .nonProductiveReference: "A reference/combinator cycle has no qualified productive declaration."
        case .profileCapacity: "A frozen ceiling or conservative UTF-8/declaration-depth rule was exceeded."
        case .booleanSchema: "Boolean schemas are outside this strict subset."
        }
    }
}

/// Completed local compatibility inspection, distinct from native validity and remote service acceptance.
public struct JSONSchemaProviderCompatibility: Sendable {
    /// The frozen provider, API purpose, revision and capability category.
    public let profile: JSONSchemaProviderProfile
    /// Stored bounded issues; truncation never permits strict export.
    public let issues: [JSONSchemaProviderIssue]
    /// True when issue storage was exhausted; the check still completed incompatibly.
    public let truncated: Bool
    /// True only when no unsupported or unverified declaration was observed.
    public let isCompatible: Bool
    /// Number of inspected caller-schema nodes.
    public let checkedSchemaNodes: UInt64
    /// Number of inspected child/reference edges.
    public let checkedReferenceEdges: UInt64
    /// Number of inspected immediate declarations.
    public let checkedDeclarations: UInt64
}

/// Operational/configuration failures and explicit strict-export rejection.
public enum JSONSchemaProviderFailure: Error, Sendable {
    /// A finite local capacity is invalid.
    case invalidConfiguration
    /// A helper was called with a profile for another API purpose.
    case profileMismatch
    /// Endpoint metadata violates the frozen name/metadata policy.
    case invalidMetadata
    /// Native compilation completed, but strict export is incompatible or unverified.
    case incompatible(JSONSchemaProviderCompatibility)
    /// An owned provider capacity failed; no successful partial result is returned.
    case limitExceeded(metric: JSONSchemaProviderMetric, limit: UInt64, attempted: UInt64?)
}
