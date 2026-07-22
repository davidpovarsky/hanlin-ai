import Foundation

enum MCPCompatibilityVerdict: String, Codable, Hashable, Sendable {
    case compatible
    case compatibleWithWarnings
    case unsupported
}

struct MCPCompatibilityFinding: Codable, Hashable, Sendable, Identifiable {
    enum Severity: String, Codable, Hashable, Sendable {
        case info
        case warning
        case unsupported
    }

    var id: String { "\(severity.rawValue):\(code ?? "message"):\(path ?? parentPath ?? message)" }
    var severity: Severity
    var message: String
    var code: String?
    var path: String?
    var specifier: String?
    var parentPath: String?
    var reachable: Bool?
    var phase: String?
    var importChain: [String]?

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

struct MCPModuleAccess: Codable, Hashable, Sendable {
    var code: String?
    var specifier: String
    var parentPath: String?
    var resolvedPath: String?
    var importChain: [String]?
}

struct MCPModuleEdge: Codable, Hashable, Sendable {
    var parentPath: String?
    var specifier: String
    var resolvedPath: String?
    var moduleType: String
}

struct MCPCompatibilityReport: Codable, Hashable, Sendable {
    var verdict: MCPCompatibilityVerdict
    var findings: [MCPCompatibilityFinding]
    var runtimeProbePassed: Bool
    var entryPoint: String?
    var treeFileCount: Int?
    var reachableModuleCount: Int?
    var resolvedModuleCount: Int?
    var dynamicUnresolvedCount: Int?
    var runtimeProbeDuration: Int?
    var requiresConfiguration: Bool?
    var blockedAccesses: [MCPModuleAccess]?
    var moduleEdges: [MCPModuleEdge]?
    var runtimeProbeToolCount: Int?

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
