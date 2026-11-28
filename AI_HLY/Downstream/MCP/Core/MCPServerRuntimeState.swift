import Foundation

public enum MCPServerRuntimeState: String, Codable, Hashable, Sendable {
    case stopped
    case starting
    case running
    case stopping
    case failed
}

public enum MCPServerFailureKind: String, Codable, Hashable, Sendable {
    case runtimeFailure = "mcp_runtime_start_failed"
    case compatibilityFailure = "mcp_compatibility_failed"
    case missingConfiguration = "mcp_configuration_missing"
    case packageInstallationMissing = "mcp_package_directory_missing"
    case packagePathInvalid = "mcp_package_path_invalid"
    case entryPointInvalid = "mcp_entry_point_invalid"
    case entryPointMissing = "mcp_entry_point_missing"
    case registryMigrationFailed = "mcp_registry_migration_failed"
    case nodeHostUnavailable = "mcp_node_host_unavailable"
}

public struct MCPServerFailure: Codable, Hashable, Sendable {
    public internal(set) var kind: MCPServerFailureKind
    public internal(set) var message: String
}

public struct MCPServerStatus: Codable, Hashable, Sendable, Identifiable {
    public internal(set) var id: UUID
    public internal(set) var state: MCPServerRuntimeState
    public internal(set) var toolCount: Int
    public internal(set) var message: String?
    public internal(set) var failure: MCPServerFailure? = nil
    public internal(set) var generation: UInt64 = 0
    public internal(set) var startedAt: Date? = nil
    public internal(set) var stoppedAt: Date? = nil
}
