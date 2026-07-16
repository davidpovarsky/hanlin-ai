import Foundation

enum AgentDiagnosticsLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case metadataOnly
    case fullLocalDebug

    var id: String { rawValue }
}

enum AgentDiagnosticsConfiguration {
    static let levelKey = "agentDiagnosticsLevel"
    static let retentionKey = "agentDiagnosticsRetention"

    static var level: AgentDiagnosticsLevel {
        AgentDiagnosticsLevel(rawValue: UserDefaults.standard.string(forKey: levelKey) ?? "metadataOnly") ?? .metadataOnly
    }

    /// Zero means that user-accessible session files are retained until manually deleted.
    static var retentionLimit: Int {
        guard UserDefaults.standard.object(forKey: retentionKey) != nil else { return 50 }
        return UserDefaults.standard.integer(forKey: retentionKey)
    }
}
