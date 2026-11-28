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
    static let automaticRetentionMigrationKey = "agentDiagnosticsUserManagedRetentionV1"
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
        retentionLimit(in: .standard)
    }

    static func retentionLimit(in defaults: UserDefaults) -> Int {
        migrationLock.lock()
        defer { migrationLock.unlock() }
        // The former default silently removed sessions after 50. Upgrade once
        // to user-managed retention; a subsequent explicit choice is respected.
        if !defaults.bool(forKey: automaticRetentionMigrationKey) {
            defaults.set(0, forKey: retentionKey)
            defaults.set(true, forKey: automaticRetentionMigrationKey)
        }
        return max(0, defaults.integer(forKey: retentionKey))
    }
}
