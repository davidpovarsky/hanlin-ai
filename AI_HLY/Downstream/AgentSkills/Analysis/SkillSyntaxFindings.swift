#if HANLIN_SKILL_ANALYSIS_POC
import Foundation

/// Passive syntax facts only. Runtime05 owns SourceEvidence, dependency resolution,
/// ExecutionPlan and authorization; these values never grant execution or readiness.
public struct SkillSyntaxLocation: Codable, Hashable, Sendable {
    public let file: String
    public let line: Int
    public let utf8Column: Int
    public let byteOffset: Int
    public let byteLength: Int
}

public struct SkillSyntaxFinding: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case interpreter, command, scriptReference, moduleReference, workingDirectory, redirection, unknown
    }
    public enum Confidence: String, Codable, Sendable {
        case literalSyntax, conditionalSyntax, unknown
    }
    public let kind: Kind
    public let value: String?
    public let confidence: Confidence
    public let source: SkillSyntaxLocation
    /// A finite scanner explanation, never raw arguments or parser diagnostics.
    public let reason: String
}

public struct SkillSyntaxProvenance: Codable, Hashable, Sendable {
    public let scanner: String
    public let wrapperRevision: String?
    public let coreRevision: String?
    public let grammarRevision: String?
    public let languageABI: Int?
    public let engineVersion: String?

    public init(scanner: String, wrapperRevision: String? = nil, coreRevision: String? = nil,
                grammarRevision: String? = nil, languageABI: Int? = nil, engineVersion: String? = nil) {
        self.scanner = scanner; self.wrapperRevision = wrapperRevision
        self.coreRevision = coreRevision; self.grammarRevision = grammarRevision
        self.languageABI = languageABI; self.engineVersion = engineVersion
    }
}

public struct SkillSyntaxReport: Codable, Hashable, Sendable {
    public enum Completion: String, Codable, Sendable { case complete, partial, unknown }
    public let file: String
    public let sourceSHA256: String?
    public let completion: Completion
    public let provenance: SkillSyntaxProvenance
    public let findings: [SkillSyntaxFinding]
    public let visitedNodes: Int
    public let inputBytes: Int
    public let limitations: [String]
}

public struct SkillSyntaxBudget: Sendable {
    public let maximumBytes: Int
    public let maximumNodes: Int
    public let maximumFindings: Int
    public let maximumDepth: Int
    public let parseSeconds: Double

    public init(maximumBytes: Int = 262_144, maximumNodes: Int = 20_000,
                maximumFindings: Int = 256, maximumDepth: Int = 128, parseSeconds: Double = 0.1) {
        self.maximumBytes = min(max(maximumBytes, 1), 1_048_576)
        self.maximumNodes = min(max(maximumNodes, 1), 100_000)
        self.maximumFindings = min(max(maximumFindings, 2), 1_024)
        self.maximumDepth = min(max(maximumDepth, 1), 512)
        self.parseSeconds = parseSeconds.isFinite ? min(max(parseSeconds, 0.001), 1) : 0.1
    }
}
#endif
