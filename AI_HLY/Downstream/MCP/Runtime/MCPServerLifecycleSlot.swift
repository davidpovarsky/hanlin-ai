import Foundation

enum MCPActivationReason: String, Sendable {
    case chatToolSchema
    case toolCall
    case refreshTools
    case preload
    case diagnostics
    case postInstallValidation
}

enum MCPServerLifecycleOperationKind: Equatable, Sendable {
    case start
    case stop
    case restart
}

struct MCPServerRuntimeSlot {
    var generation: UInt64 = 0
    var phase: MCPServerRuntimeState = .stopped
    var session: MCPClientSession?
    var transport: EmbeddedNodeMCPTransport?
    var toolChangeTask: Task<Void, Never>?
    var terminationTask: Task<Void, Never>?
    var lifecycleTask: Task<MCPClientSession?, Error>?
    var lifecycleOperationID: UUID?
    var lifecycleKind: MCPServerLifecycleOperationKind?
    var stopRequested = false
    var startedAt: Date?
    var stoppedAt: Date?
    var lastError: String?
    var toolCount = 0
}
