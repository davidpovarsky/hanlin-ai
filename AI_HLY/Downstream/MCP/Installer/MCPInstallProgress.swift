import Foundation

struct MCPInstallTerminalError: Codable, Hashable, Sendable {
    var code: String
    var message: String
    var rollbackMessage: String?
    var findings: [MCPCompatibilityFinding]?
}

struct MCPInstallProgress: Codable, Hashable, Sendable, Identifiable {
    var id: UUID { operationID }
    var operationID: UUID
    var phase: MCPInstallPhase
    var fraction: Double?
    var detail: String?
    var terminalError: MCPInstallTerminalError?

    init(
        operationID: UUID,
        phase: MCPInstallPhase,
        fraction: Double?,
        detail: String? = nil,
        terminalError: MCPInstallTerminalError? = nil
    ) {
        self.operationID = operationID
        self.phase = phase
        self.fraction = fraction
        self.detail = detail
        self.terminalError = terminalError
    }
}
