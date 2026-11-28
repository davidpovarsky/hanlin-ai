import Foundation

public enum MCPNodeRuntimeState: String, Codable, Hashable, Sendable {
    case stopped
    case starting
    case running
    case failed
}

public struct MCPRuntimeSnapshot: Codable, Hashable, Sendable {
    public internal(set) var state: MCPNodeRuntimeState
    public internal(set) var nodeVersion: String?
    public internal(set) var protocolVersion: Int?
    public internal(set) var activeWorkerCount: Int
    public internal(set) var message: String?

    static let stopped = MCPRuntimeSnapshot(
        state: .stopped,
        nodeVersion: nil,
        protocolVersion: nil,
        activeWorkerCount: 0,
        message: nil
    )
}
