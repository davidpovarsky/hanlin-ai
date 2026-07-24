import Foundation

enum MCPServerRuntimeState: String, Codable, Hashable, Sendable {
    case stopped
    case starting
    case running
    case stopping
    case failed
}

enum MCPServerFailureKind: String, Codable, Hashable, Sendable {
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

struct MCPServerFailure: Codable, Hashable, Sendable {
    var kind: MCPServerFailureKind
    var message: String
}

struct MCPServerStatus: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var state: MCPServerRuntimeState
    var toolCount: Int
    var message: String?
    var failure: MCPServerFailure? = nil
    var generation: UInt64 = 0
    var startedAt: Date? = nil
    var stoppedAt: Date? = nil
}
