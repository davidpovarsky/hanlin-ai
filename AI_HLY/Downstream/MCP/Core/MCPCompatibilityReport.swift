import Foundation

enum MCPCompatibilityVerdict: String, Codable, Hashable, Sendable {
    case compatible
    case compatibleWithWarnings
    case unsupported
}

struct MCPCompatibilityFinding: Codable, Hashable, Sendable, Identifiable {
    enum Severity: String, Codable, Hashable, Sendable {
        case warning
        case unsupported
    }

    var id: String { "\(severity.rawValue):\(message)" }
    var severity: Severity
    var message: String
}

struct MCPCompatibilityReport: Codable, Hashable, Sendable {
    var verdict: MCPCompatibilityVerdict
    var findings: [MCPCompatibilityFinding]
    var runtimeProbePassed: Bool

    static let pendingProbe = MCPCompatibilityReport(
        verdict: .compatibleWithWarnings,
        findings: [.init(severity: .warning, message: "Runtime probe has not completed.")],
        runtimeProbePassed: false
    )
}
