import Foundation

struct MCPInstallProgress: Codable, Hashable, Sendable, Identifiable {
    var id: UUID { operationID }
    var operationID: UUID
    var phase: MCPInstallPhase
    var fraction: Double?
    var detail: String?
}
