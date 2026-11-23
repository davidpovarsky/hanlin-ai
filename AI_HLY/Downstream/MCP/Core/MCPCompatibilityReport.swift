import Foundation

public enum MCPCompatibilityVerdict: String, Codable, Hashable, Sendable {
    case compatible
    case compatibleWithWarnings
    case unsupported
}

public struct MCPCompatibilityFinding: Codable, Hashable, Sendable, Identifiable {
    public enum Severity: String, Codable, Hashable, Sendable {
        case info
        case warning
        case unsupported
    }

    public var id: String { "\(severity.rawValue):\(code ?? "message"):\(path ?? parentPath ?? message)" }
    public internal(set) var severity: Severity
    public internal(set) var message: String
    public internal(set) var code: String?
    public internal(set) var path: String?
    public internal(set) var specifier: String?
    public internal(set) var parentPath: String?
    public internal(set) var reachable: Bool?
    public internal(set) var phase: String?
    public internal(set) var importChain: [String]?

    init(
        severity: Severity,
        message: String,
        code: String? = nil,
        path: String? = nil,
        specifier: String? = nil,
        parentPath: String? = nil,
        reachable: Bool? = nil,
        phase: String? = nil,
        importChain: [String]? = nil
    ) {
        self.severity = severity
        self.message = message
        self.code = code
        self.path = path
        self.specifier = specifier
        self.parentPath = parentPath
        self.reachable = reachable
        self.phase = phase
        self.importChain = importChain
    }
}

public struct MCPModuleAccess: Codable, Hashable, Sendable {
    public internal(set) var code: String?
    public internal(set) var specifier: String
    public internal(set) var operation: String?
    public internal(set) var parentPath: String?
    public internal(set) var resolvedPath: String?
    public internal(set) var importChain: [String]?
}

public struct MCPModuleEdge: Codable, Hashable, Sendable {
    public internal(set) var parentPath: String?
    public internal(set) var specifier: String
    public internal(set) var resolvedPath: String?
    public internal(set) var moduleType: String
}

public struct MCPCompatibilityReport: Codable, Hashable, Sendable {
    public internal(set) var verdict: MCPCompatibilityVerdict
    public internal(set) var findings: [MCPCompatibilityFinding]
    public internal(set) var runtimeProbePassed: Bool
    public internal(set) var entryPoint: String?
    public internal(set) var treeFileCount: Int?
    public internal(set) var reachableModuleCount: Int?
    public internal(set) var resolvedModuleCount: Int?
    public internal(set) var dynamicUnresolvedCount: Int?
    public internal(set) var runtimeProbeDuration: Int?
    public internal(set) var internalLoaderRetryCount: Int?
    public internal(set) var requiresConfiguration: Bool?
    public internal(set) var blockedAccesses: [MCPModuleAccess]?
    public internal(set) var moduleEdges: [MCPModuleEdge]?
    public internal(set) var runtimeProbeToolCount: Int?

    init(
        verdict: MCPCompatibilityVerdict,
        findings: [MCPCompatibilityFinding],
        runtimeProbePassed: Bool,
        entryPoint: String? = nil,
        treeFileCount: Int? = nil,
        reachableModuleCount: Int? = nil,
        resolvedModuleCount: Int? = nil,
        dynamicUnresolvedCount: Int? = nil,
        runtimeProbeDuration: Int? = nil,
        internalLoaderRetryCount: Int? = nil,
        requiresConfiguration: Bool? = nil,
        blockedAccesses: [MCPModuleAccess]? = nil,
        moduleEdges: [MCPModuleEdge]? = nil,
        runtimeProbeToolCount: Int? = nil
    ) {
        self.verdict = verdict
        self.findings = findings
        self.runtimeProbePassed = runtimeProbePassed
        self.entryPoint = entryPoint
        self.treeFileCount = treeFileCount
        self.reachableModuleCount = reachableModuleCount
        self.resolvedModuleCount = resolvedModuleCount
        self.dynamicUnresolvedCount = dynamicUnresolvedCount
        self.runtimeProbeDuration = runtimeProbeDuration
        self.internalLoaderRetryCount = internalLoaderRetryCount
        self.requiresConfiguration = requiresConfiguration
        self.blockedAccesses = blockedAccesses
        self.moduleEdges = moduleEdges
        self.runtimeProbeToolCount = runtimeProbeToolCount
    }

    static let pendingProbe = MCPCompatibilityReport(
        verdict: .compatibleWithWarnings,
        findings: [.init(severity: .warning, message: "Runtime probe has not completed.")],
        runtimeProbePassed: false
    )
}
