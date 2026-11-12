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
    static let automaticCaptureMigrationKey = "agentDiagnosticsAutomaticCaptureMigrationV1"
    private static let migrationLock = NSLock()

    static var level: AgentDiagnosticsLevel {
        migrationLock.lock()
        defer { migrationLock.unlock() }
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: automaticCaptureMigrationKey) {
            defaults.set(AgentDiagnosticsLevel.fullLocalDebug.rawValue, forKey: levelKey)
            defaults.set(true, forKey: automaticCaptureMigrationKey)
        }
        return AgentDiagnosticsLevel(rawValue: defaults.string(forKey: levelKey) ?? "fullLocalDebug") ?? .fullLocalDebug
    }

    /// Zero means that user-accessible session files are retained until manually deleted.
    static var retentionLimit: Int {
        guard UserDefaults.standard.object(forKey: retentionKey) != nil else { return 50 }
        return UserDefaults.standard.integer(forKey: retentionKey)
    }
}
