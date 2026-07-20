import Foundation

enum MCPInstallPhase: String, Codable, CaseIterable, Sendable {
    case resolving
    case downloading
    case verifying
    case extracting
    case installingDependencies
    case checkingCompatibility
    case registering
    case starting
    case completed
}

enum MCPInstallState: Codable, Hashable, Sendable {
    case idle
    case previewing
    case installing(operationID: UUID, phase: MCPInstallPhase, fraction: Double?)
    case completed(serverID: UUID)
    case failed(String)
    case cancelled
}
