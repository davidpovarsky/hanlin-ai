import Foundation

enum MCPServerRuntimeState: String, Codable, Hashable, Sendable {
    case stopped
    case starting
    case running
    case stopping
    case failed
}

struct MCPServerStatus: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var state: MCPServerRuntimeState
    var toolCount: Int
    var message: String?
    var generation: UInt64 = 0
    var startedAt: Date? = nil
    var stoppedAt: Date? = nil
}
