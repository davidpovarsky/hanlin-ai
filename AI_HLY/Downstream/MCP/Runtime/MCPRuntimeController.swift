import Foundation

actor MCPRuntimeController {
    private let runtime: NodeRuntimeService
    private let registry: MCPServerRegistryStore
    private let secrets: MCPSecretStore
    private let catalog = MCPToolCatalog()
    private var sessions: [UUID: MCPClientSession] = [:]
    private var toolChangeTasks: [UUID: Task<Void, Never>] = [:]
    private var statusValues: [UUID: MCPServerStatus] = [:]

    init(
        runtime: NodeRuntimeService,
        registry: MCPServerRegistryStore = MCPServerRegistryStore(),
        secrets: MCPSecretStore = MCPSecretStore()
    ) {
        self.runtime = runtime
        self.registry = registry
        self.secrets = secrets
    }

    func statuses() -> [UUID: MCPServerStatus] { statusValues }

    func start(_ server: MCPServerDescriptor) async throws {
        guard server.compatibility.verdict != .unsupported else {
            throw MCPError.incompatiblePackage(server.compatibility.findings.map(\.message))
        }
        if sessions[server.id] != nil { return }
        statusValues[server.id] = MCPServerStatus(id: server.id, state: .starting, toolCount: 0)
        var pendingSession: MCPClientSession?
        do {
            let connection = try await runtime.ensureRunning()
            var secretValues: [String: String] = [:]
            for variable in server.environment {
                if let reference = variable.secretReference {
                    secretValues[reference] = try await secrets.value(reference: reference)
                }
            }
            let configuration = MCPServerConfiguration(descriptor: server, secrets: secretValues)
            let transport = EmbeddedNodeMCPTransport(server: configuration, connection: connection)
            let session = MCPClientSession(server: server, transport: transport)
            pendingSession = session
            let tools = try await session.connect()
            let registered = await catalog.replace(server: server, tools: tools)
            sessions[server.id] = session
            toolChangeTasks[server.id] = Task { [weak self, session] in
                for await _ in session.toolListChanges {
                    await self?.handleToolListChanged(serverID: server.id)
                }
            }
            statusValues[server.id] = MCPServerStatus(
                id: server.id,
                state: .running,
                toolCount: registered.count,
                message: nil
            )
            var updated = server
            updated.cachedToolCount = registered.count
            updated.compatibility.runtimeProbePassed = true
            if updated.compatibility.verdict != .unsupported {
                updated.compatibility.verdict = updated.compatibility.findings.isEmpty ? .compatible : .compatibleWithWarnings
            }
            updated.updatedAt = .now
            _ = try await registry.upsert(updated)
        } catch {
            if let pendingSession { await pendingSession.disconnect() }
            statusValues[server.id] = MCPServerStatus(
                id: server.id,
                state: .failed,
                toolCount: 0,
                message: error.localizedDescription
            )
            throw error
        }
    }

    func stop(serverID: UUID) async {
        toolChangeTasks.removeValue(forKey: serverID)?.cancel()
        if let session = sessions.removeValue(forKey: serverID) {
            await session.disconnect()
        }
        await catalog.remove(serverID: serverID)
        statusValues[serverID] = MCPServerStatus(id: serverID, state: .stopped, toolCount: 0)
    }

    func stopAll() async {
        for id in Array(sessions.keys) { await stop(serverID: id) }
    }

    func restart(_ server: MCPServerDescriptor) async throws {
        await stop(serverID: server.id)
        try await start(server)
    }

    func refreshTools(_ server: MCPServerDescriptor) async throws {
        guard let session = sessions[server.id] else {
            try await start(server)
            return
        }
        let tools = try await session.refreshTools()
        let registered = await catalog.replace(server: server, tools: tools)
        statusValues[server.id]?.toolCount = registered.count
    }

    func toolDescriptors(serverIDs: Set<UUID>) async throws -> [MCPToolDescriptor] {
        let servers = try await registry.load().filter {
            serverIDs.contains($0.id) && $0.isGloballyEnabled
        }
        for server in servers where sessions[server.id] == nil {
            try await start(server)
        }
        return await catalog.descriptors(serverIDs: Set(servers.map(\.id)))
    }

    func call(exposedName: String, argumentsJSON: String) async throws -> MCPToolCallOutput {
        guard let descriptor = await catalog.descriptor(exposedName: exposedName) else {
            throw MCPError.toolNotFound
        }
        if sessions[descriptor.serverID] == nil {
            guard let server = try await registry.load().first(where: { $0.id == descriptor.serverID }) else {
                throw MCPError.serverNotFound
            }
            try await start(server)
        }
        guard let session = sessions[descriptor.serverID] else { throw MCPError.serverNotFound }
        return try await session.call(name: descriptor.originalName, argumentsJSON: argumentsJSON)
    }

    func descriptor(exposedName: String) async -> MCPToolDescriptor? {
        await catalog.descriptor(exposedName: exposedName)
    }

    private func handleToolListChanged(serverID: UUID) async {
        guard let server = try? await registry.load().first(where: { $0.id == serverID }) else { return }
        do {
            try await refreshTools(server)
        } catch {
            statusValues[serverID]?.message = error.localizedDescription
        }
    }
}
