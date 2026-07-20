import Foundation

enum MCPNodeRuntimeState: String, Codable, Hashable, Sendable {
    case stopped
    case starting
    case running
    case failed
}

struct MCPRuntimeSnapshot: Codable, Hashable, Sendable {
    var state: MCPNodeRuntimeState
    var nodeVersion: String?
    var protocolVersion: Int?
    var activeWorkerCount: Int
    var message: String?

    static let stopped = MCPRuntimeSnapshot(
        state: .stopped,
        nodeVersion: nil,
        protocolVersion: nil,
        activeWorkerCount: 0,
        message: nil
    )
}
