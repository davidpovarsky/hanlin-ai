import Foundation

/// Shared passive compatibility data. YAML nodes and syntax findings stay in
/// their original modules; adapters supply requirements with source evidence.
/// None of these values authorizes an install, an engine start, or execution.
enum SkillRuntimeContract {
    struct EngineID: RawRepresentable, Codable, Hashable, Sendable {
        let rawValue: String

        init(rawValue: String) { self.rawValue = rawValue }

        init(from decoder: any Decoder) throws {
            rawValue = try decoder.singleValueContainer().decode(String.self)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        static let node = Self(rawValue: "hanlin.node")
        static let typeScript = Self(rawValue: "hanlin.typescript")
        static let python = Self(rawValue: "hanlin.python")
        static let javaScriptCore = Self(rawValue: "hanlin.javascriptcore")
        static let shell = Self(rawValue: "hanlin.ios-system")
    }

    enum EvidenceKind: String, Codable, Sendable {
        case declared, inferred, observed, tested
    }

    struct SourceEvidence: Codable, Hashable, Sendable {
        let kind: EvidenceKind
        let producer: String
        let producerVersion: String?
        let sourceID: String
        let sourceVersion: String?
        let sourceFingerprint: String?
        let observedAt: Date?
        let artifactReference: String?
    }

    enum RequirementKind: String, Codable, Sendable {
        case engine, module, command, capability, unknown
    }

    /// Version expressions retain their original semantics. Only an existing
    /// engine/package-manager adapter may assert satisfaction of an exact key.
    struct RequirementKey: Codable, Hashable, Sendable {
        let kind: RequirementKind
        let name: String
        let versionConstraint: String?
    }

    struct SkillRequirement: Codable, Hashable, Sendable {
        let id: String
        let key: RequirementKey
        let evidence: SourceEvidence
    }

    /// Cache identity must change with the actual engine or its environment.
    /// A version string or a Linux-like PATH alone is not this identity.
    struct EngineBinding: Codable, Hashable, Sendable {
        let engineID: EngineID
        let engineVersion: String
        let engineFingerprint: String
        let environmentID: String
        let environmentFingerprint: String
    }

    enum FactStatus: String, Codable, Sendable {
        case available, missing, unsupported, unknown
    }

    struct CapabilityFact: Codable, Hashable, Sendable {
        let requirement: RequirementKey
        let binding: EngineBinding
        let status: FactStatus
        let resolvedVersion: String?
        let resolvedPath: String?
        let evidence: SourceEvidence
    }

    enum Readiness: String, Codable, Sendable {
        case verified = "VERIFIED"
        case likely = "LIKELY"
        case partial = "PARTIAL"
        case needsInstall = "NEEDS_INSTALL"
        case unsupported = "UNSUPPORTED"
        case unknown = "UNKNOWN"
    }

    enum ActionKind: String, Codable, Sendable {
        case instructions, script, analysisHelper
    }

    struct Action: Codable, Hashable, Sendable {
        let id: String
        let kind: ActionKind
        let skillID: String
        let sourceFingerprint: String
        let actionFingerprint: String
        /// Includes actual argv/stdin/cwd and other runtime inputs when known.
        /// Without it a previous test cannot verify this invocation.
        let invocationFingerprint: String?
        let relativePath: String?
        let environmentID: String
        /// Selected by an explicit adapter/policy, never by a filename suffix.
        let engineID: EngineID?
        let requirements: [SkillRequirement]
        /// False for incomplete scans, unresolved YAML merges/tags, or opaque
        /// upstream requirements. An empty array cannot erase those unknowns.
        let requirementsComplete: Bool
    }

    struct ExecutionTest: Codable, Hashable, Sendable {
        enum Outcome: String, Codable, Sendable { case passed, failed }

        let actionID: String
        let sourceFingerprint: String
        let actionFingerprint: String
        let invocationFingerprint: String
        let binding: EngineBinding
        let outcome: Outcome
        let evidence: SourceEvidence
    }

    struct Freshness: Codable, Hashable, Sendable {
        let notBefore: Date
        let now: Date

        func contains(_ date: Date?) -> Bool {
            guard let date, notBefore <= now else { return false }
            return notBefore <= date && date <= now
        }
    }

    struct Issue: Codable, Hashable, Sendable {
        enum Code: String, Codable, Sendable {
            case incompleteRequirements, invalidIdentity, missingEngineSelection
            case unregisteredEngine, unknownEngineIdentity, unknownRequirement
            case missingFact, ambiguousFact, staleFact, unprovenFact
            case missingDependency, unsupportedDependency, previousTestFailed
        }

        let code: Code
        let requirementID: String?
    }

    /// Handles refer to existing managers; rendering a handle performs no work.
    struct RemediationHandle: Codable, Hashable, Sendable {
        enum Manager: String, Codable, Sendable {
            case nodePackages, pythonPackages, runtimeManager
        }

        let manager: Manager
        let engineID: EngineID
        let requirementID: String
        let target: String
    }

    struct ExecutionPlan: Codable, Hashable, Sendable {
        let schemaVersion: Int
        let action: Action
        let selectedEngine: EngineID?
        let binding: EngineBinding?
        let readiness: Readiness
        let issues: [Issue]
        let missingRequirements: [SkillRequirement]
        let remediation: [RemediationHandle]
        let lastTest: ExecutionTest?
        let evaluatedAt: Date

        /// A planner result is not a permission grant. The existing execution
        /// tool still owns loaded/enabled/source checks, JobStore and effects.
        var isExecutable: Bool {
            action.kind != .instructions && binding != nil &&
                (readiness == .verified || readiness == .likely)
        }
    }

    struct EngineFacts: Codable, Hashable, Sendable {
        let engineID: EngineID
        let binding: EngineBinding?
        let facts: [CapabilityFact]
    }
}

/// Implementations may inspect cached/previously launched engine facts only.
/// They must never install, import user code, health-start or execute a helper.
protocol SkillRuntimeCapabilityProvider: Sendable {
    var engineID: SkillRuntimeContract.EngineID { get }
    func snapshot(environmentID: String) async -> SkillRuntimeContract.EngineFacts
}
