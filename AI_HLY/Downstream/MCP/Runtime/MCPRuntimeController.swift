import Foundation

actor MCPRuntimeController {
    private let runtime: NodeRuntimeService
    private let registry: MCPServerRegistryStore
    private let secrets: MCPSecretStore
    private let runtimeEnvironment: RuntimeEnvironmentStore
    private let catalog = MCPToolCatalog()
    private var slots: [UUID: MCPServerRuntimeSlot] = [:]

    init(
        runtime: NodeRuntimeService,
        registry: MCPServerRegistryStore = MCPServerRegistryStore(),
        secrets: MCPSecretStore = MCPSecretStore(),
        runtimeEnvironment: RuntimeEnvironmentStore = AppRuntimeCore.shared.environment
    ) {
        self.runtime = runtime
        self.registry = registry
        self.secrets = secrets
        self.runtimeEnvironment = runtimeEnvironment
    }

    func statuses() -> [UUID: MCPServerStatus] {
        slots.reduce(into: [:]) { result, pair in
            result[pair.key] = MCPServerStatus(
                id: pair.key,
                state: pair.value.phase,
                toolCount: pair.value.toolCount,
                message: pair.value.lastError,
                generation: pair.value.generation,
                startedAt: pair.value.startedAt,
                stoppedAt: pair.value.stoppedAt
            )
        }
    }

    func ensureRunning(
        _ server: MCPServerDescriptor,
        reason: MCPActivationReason
    ) async throws -> MCPClientSession {
        guard server.compatibility.verdict != .unsupported else {
            throw MCPError.incompatiblePackage(server.compatibility.findings.map(\.message))
        }

        while true {
            let slot = slots[server.id] ?? MCPServerRuntimeSlot()
            switch slot.phase {
            case .running:
                if let session = slot.session { return session }
                markFailed(serverID: server.id, message: "Running server has no client session.")
            case .starting, .stopping:
                if let task = slot.lifecycleTask {
                    if let session = try await task.value { return session }
                    continue
                }
                markFailed(serverID: server.id, message: "Lifecycle state has no active operation.")
            case .failed:
                if slot.session != nil
                    || slot.transport != nil
                    || slot.toolChangeTask != nil
                    || slot.terminationTask != nil {
                    _ = try? await beginStop(serverID: server.id).value
                    continue
                }
                let task = beginStart(server, reason: reason)
                if let session = try await task.value { return session }
            case .stopped:
                let task = beginStart(server, reason: reason)
                if let session = try await task.value { return session }
            }
        }
    }

    func start(_ server: MCPServerDescriptor) async throws {
        _ = try await ensureRunning(server, reason: .diagnostics)
    }

    func stop(serverID: UUID) async {
        while true {
            var slot = slots[serverID] ?? MCPServerRuntimeSlot()
            switch slot.phase {
            case .stopped:
                return
            case .starting:
                slot.stopRequested = true
                slots[serverID] = slot
                if let task = slot.lifecycleTask { _ = try? await task.value }
            case .stopping:
                if let task = slot.lifecycleTask { _ = try? await task.value }
                else { markFailed(serverID: serverID, message: "Stop state has no active operation.") }
            case .running, .failed:
                let task = beginStop(serverID: serverID)
                _ = try? await task.value
                return
            }
        }
    }

    func stopAll() async {
        let serverIDs = slots.compactMap { id, slot in
            slot.phase != .stopped
                || slot.session != nil
                || slot.transport != nil
                || slot.lifecycleTask != nil
                ? id
                : nil
        }
        for serverID in serverIDs {
            await stop(serverID: serverID)
        }
    }

    func restart(_ server: MCPServerDescriptor) async throws {
        while true {
            let slot = slots[server.id] ?? MCPServerRuntimeSlot()
            if let task = slot.lifecycleTask {
                if slot.lifecycleKind == .restart {
                    _ = try await task.value
                    return
                }
                _ = try? await task.value
                continue
            }
            _ = try await beginRestart(server).value
            return
        }
    }

    func refreshTools(_ server: MCPServerDescriptor) async throws {
        let session = try await ensureRunning(server, reason: .refreshTools)
        let generation = slots[server.id]?.generation
        let tools = try await session.refreshTools()
        guard generation == slots[server.id]?.generation,
              slots[server.id]?.session === session else { return }
        let registered = await catalog.replace(server: server, tools: tools)
        updateToolCount(registered.count, serverID: server.id)
    }

    func toolDescriptors(serverIDs: Set<UUID>) async throws -> [MCPToolDescriptor] {
        let servers = try await registry.load().filter {
            serverIDs.contains($0.id) && $0.isGloballyEnabled
        }
        for server in servers {
            _ = try await ensureRunning(server, reason: .chatToolSchema)
        }
        return await catalog.descriptors(serverIDs: Set(servers.map(\.id)))
    }

    func call(exposedName: String, argumentsJSON: String) async throws -> MCPToolCallOutput {
        guard let descriptor = await catalog.descriptor(exposedName: exposedName) else {
            throw MCPError.toolNotFound
        }
        guard let server = try await registry.load().first(where: { $0.id == descriptor.serverID }),
              server.isGloballyEnabled else {
            throw MCPError.serverNotFound
        }
        let session = try await ensureRunning(server, reason: .toolCall)
        return try await session.call(name: descriptor.originalName, argumentsJSON: argumentsJSON)
    }

    func descriptor(exposedName: String) async -> MCPToolDescriptor? {
        await catalog.descriptor(exposedName: exposedName)
    }

    private func beginStart(
        _ server: MCPServerDescriptor,
        reason: MCPActivationReason
    ) -> Task<MCPClientSession?, Error> {
        var slot = slots[server.id] ?? MCPServerRuntimeSlot()
        slot.generation &+= 1
        slot.phase = .starting
        slot.stopRequested = false
        slot.lastError = nil
        let generation = slot.generation
        let operationID = UUID()
        slot.lifecycleOperationID = operationID
        slot.lifecycleKind = .start
        let task = Task { [weak self] () throws -> MCPClientSession? in
            guard let self else { throw CancellationError() }
            return try await self.performStart(
                server,
                reason: reason,
                generation: generation,
                operationID: operationID
            )
        }
        slot.lifecycleTask = task
        slots[server.id] = slot
        return task
    }

    private func beginStop(serverID: UUID) -> Task<MCPClientSession?, Error> {
        var slot = slots[serverID] ?? MCPServerRuntimeSlot()
        slot.phase = .stopping
        slot.stopRequested = true
        let generation = slot.generation
        let operationID = UUID()
        slot.lifecycleOperationID = operationID
        slot.lifecycleKind = .stop
        let task = Task { [weak self] () throws -> MCPClientSession? in
            guard let self else { throw CancellationError() }
            await self.performStop(
                serverID: serverID,
                generation: generation,
                operationID: operationID
            )
            return nil
        }
        slot.lifecycleTask = task
        slots[serverID] = slot
        return task
    }

    private func beginRestart(_ server: MCPServerDescriptor) -> Task<MCPClientSession?, Error> {
        var slot = slots[server.id] ?? MCPServerRuntimeSlot()
        slot.generation &+= 1
        slot.phase = .stopping
        slot.stopRequested = false
        slot.lastError = nil
        let generation = slot.generation
        let operationID = UUID()
        slot.lifecycleOperationID = operationID
        slot.lifecycleKind = .restart
        let task = Task { [weak self] () throws -> MCPClientSession? in
            guard let self else { throw CancellationError() }
            return try await self.performRestart(
                server,
                generation: generation,
                operationID: operationID
            )
        }
        slot.lifecycleTask = task
        slots[server.id] = slot
        return task
    }

    private func performStart(
        _ server: MCPServerDescriptor,
        reason: MCPActivationReason,
        generation: UInt64,
        operationID: UUID
    ) async throws -> MCPClientSession {
        var pendingSession: MCPClientSession?
        do {
            let connection = try await runtime.ensureRunning()
            var secretValues: [String: String] = [:]
            for variable in server.environment {
                if let reference = variable.secretReference {
                    secretValues[reference] = try await secrets.value(reference: reference)
                }
            }
            var configuration = MCPServerConfiguration(descriptor: server, secrets: secretValues)
            let inheritedEnvironment = try await runtimeEnvironment.resolved(
                scopes: [.shared, .node, .mcpServer(server.id)]
            )
            configuration.environment = inheritedEnvironment.merging(configuration.environment) {
                _, serverValue in serverValue
            }
            let transport = EmbeddedNodeMCPTransport(server: configuration, connection: connection)
            let session = MCPClientSession(server: server, transport: transport)
            pendingSession = session

            guard installPendingResources(
                session: session,
                transport: transport,
                serverID: server.id,
                generation: generation,
                operationID: operationID
            ) else {
                throw CancellationError()
            }

            let tools = try await session.connect()
            guard isCurrent(serverID: server.id, generation: generation, operationID: operationID),
                  slots[server.id]?.stopRequested == false else {
                throw CancellationError()
            }
            let registered = await catalog.replace(server: server, tools: tools)
            let toolTask = Task { [weak self, session] in
                for await _ in session.toolListChanges {
                    await self?.handleToolListChanged(
                        serverID: server.id,
                        generation: generation
                    )
                }
            }
            completeStart(
                session: session,
                toolTask: toolTask,
                toolCount: registered.count,
                serverID: server.id,
                generation: generation,
                operationID: operationID
            )
            installTerminationObserver(
                transport: transport,
                session: session,
                serverID: server.id,
                generation: generation
            )
            await MCPTraceLogger.shared.log("server_started", fields: [
                "serverID": server.id.uuidString,
                "generation": "\(generation)",
                "reason": reason.rawValue
            ])
            return session
        } catch {
            if let pendingSession { await pendingSession.disconnect() }
            await catalog.remove(serverID: server.id)
            failStart(
                serverID: server.id,
                generation: generation,
                operationID: operationID,
                error: error
            )
            throw error
        }
    }

    private func performStop(
        serverID: UUID,
        generation: UInt64,
        operationID: UUID
    ) async {
        let resources = resourcesForStop(
            serverID: serverID,
            generation: generation,
            operationID: operationID
        )
        resources.toolTask?.cancel()
        resources.terminationTask?.cancel()
        if let session = resources.session { await session.disconnect() }
        await catalog.remove(serverID: serverID)
        completeStop(
            serverID: serverID,
            generation: generation,
            operationID: operationID
        )
    }

    private func performRestart(
        _ server: MCPServerDescriptor,
        generation: UInt64,
        operationID: UUID
    ) async throws -> MCPClientSession {
        let resources = resourcesForStop(
            serverID: server.id,
            generation: generation,
            operationID: operationID
        )
        resources.toolTask?.cancel()
        resources.terminationTask?.cancel()
        if let session = resources.session { await session.disconnect() }
        await catalog.remove(serverID: server.id)
        guard prepareRestartStart(
            serverID: server.id,
            generation: generation,
            operationID: operationID
        ) else {
            completeStop(
                serverID: server.id,
                generation: generation,
                operationID: operationID
            )
            throw CancellationError()
        }
        return try await performStart(
            server,
            reason: .diagnostics,
            generation: generation,
            operationID: operationID
        )
    }

    private func installPendingResources(
        session: MCPClientSession,
        transport: EmbeddedNodeMCPTransport,
        serverID: UUID,
        generation: UInt64,
        operationID: UUID
    ) -> Bool {
        guard isCurrent(serverID: serverID, generation: generation, operationID: operationID) else {
            return false
        }
        slots[serverID]?.session = session
        slots[serverID]?.transport = transport
        return true
    }

    private func completeStart(
        session: MCPClientSession,
        toolTask: Task<Void, Never>,
        toolCount: Int,
        serverID: UUID,
        generation: UInt64,
        operationID: UUID
    ) {
        guard isCurrent(serverID: serverID, generation: generation, operationID: operationID) else {
            toolTask.cancel()
            return
        }
        slots[serverID]?.session = session
        slots[serverID]?.toolChangeTask = toolTask
        slots[serverID]?.phase = .running
        slots[serverID]?.startedAt = .now
        slots[serverID]?.lastError = nil
        slots[serverID]?.lifecycleTask = nil
        slots[serverID]?.lifecycleOperationID = nil
        slots[serverID]?.lifecycleKind = nil
        slots[serverID]?.stopRequested = false
        updateToolCount(toolCount, serverID: serverID)
    }

    private func failStart(
        serverID: UUID,
        generation: UInt64,
        operationID: UUID,
        error: Error
    ) {
        guard isCurrent(serverID: serverID, generation: generation, operationID: operationID) else {
            return
        }
        let stopped = slots[serverID]?.stopRequested == true || error is CancellationError
        slots[serverID]?.phase = stopped ? .stopped : .failed
        slots[serverID]?.session = nil
        slots[serverID]?.transport = nil
        slots[serverID]?.toolChangeTask = nil
        slots[serverID]?.terminationTask?.cancel()
        slots[serverID]?.terminationTask = nil
        slots[serverID]?.toolCount = 0
        slots[serverID]?.lifecycleTask = nil
        slots[serverID]?.lifecycleOperationID = nil
        slots[serverID]?.lifecycleKind = nil
        slots[serverID]?.stoppedAt = stopped ? .now : slots[serverID]?.stoppedAt
        slots[serverID]?.lastError = stopped ? nil : error.localizedDescription
    }

    private func resourcesForStop(
        serverID: UUID,
        generation: UInt64,
        operationID: UUID
    ) -> (
        session: MCPClientSession?,
        toolTask: Task<Void, Never>?,
        terminationTask: Task<Void, Never>?
    ) {
        guard isCurrent(serverID: serverID, generation: generation, operationID: operationID) else {
            return (nil, nil, nil)
        }
        return (
            slots[serverID]?.session,
            slots[serverID]?.toolChangeTask,
            slots[serverID]?.terminationTask
        )
    }

    private func completeStop(serverID: UUID, generation: UInt64, operationID: UUID) {
        guard isCurrent(serverID: serverID, generation: generation, operationID: operationID) else {
            return
        }
        slots[serverID]?.session = nil
        slots[serverID]?.transport = nil
        slots[serverID]?.toolChangeTask = nil
        slots[serverID]?.terminationTask = nil
        slots[serverID]?.toolCount = 0
        slots[serverID]?.phase = .stopped
        slots[serverID]?.stoppedAt = .now
        slots[serverID]?.lastError = nil
        slots[serverID]?.lifecycleTask = nil
        slots[serverID]?.lifecycleOperationID = nil
        slots[serverID]?.lifecycleKind = nil
        slots[serverID]?.stopRequested = false
    }

    private func prepareRestartStart(
        serverID: UUID,
        generation: UInt64,
        operationID: UUID
    ) -> Bool {
        guard isCurrent(serverID: serverID, generation: generation, operationID: operationID),
              slots[serverID]?.stopRequested == false else {
            return false
        }
        slots[serverID]?.session = nil
        slots[serverID]?.transport = nil
        slots[serverID]?.toolChangeTask = nil
        slots[serverID]?.terminationTask = nil
        slots[serverID]?.phase = .starting
        return true
    }

    private func isCurrent(serverID: UUID, generation: UInt64, operationID: UUID) -> Bool {
        slots[serverID]?.generation == generation
            && slots[serverID]?.lifecycleOperationID == operationID
    }

    private func markFailed(serverID: UUID, message: String) {
        var slot = slots[serverID] ?? MCPServerRuntimeSlot()
        slot.phase = .failed
        slot.lastError = message
        slot.lifecycleTask = nil
        slot.lifecycleOperationID = nil
        slot.lifecycleKind = nil
        slots[serverID] = slot
    }

    private func updateToolCount(_ count: Int, serverID: UUID) {
        // Tool count lives in the transient status/catalog. Lifecycle operations
        // deliberately do not write the persistent descriptor.
        slots[serverID]?.toolCount = count
    }

    private func installTerminationObserver(
        transport: EmbeddedNodeMCPTransport,
        session: MCPClientSession,
        serverID: UUID,
        generation: UInt64
    ) {
        guard slots[serverID]?.generation == generation,
              slots[serverID]?.phase == .running,
              slots[serverID]?.session === session else { return }
        let task = Task { [weak self, transport] in
            for await termination in transport.unexpectedTerminations {
                await self?.handleUnexpectedTermination(
                    serverID: serverID,
                    generation: generation,
                    message: termination.message
                )
            }
        }
        slots[serverID]?.terminationTask = task
    }

    private func handleUnexpectedTermination(
        serverID: UUID,
        generation: UInt64,
        message: String
    ) {
        guard var slot = slots[serverID],
              slot.generation == generation,
              slot.phase == .running,
              slot.lifecycleTask == nil else { return }
        let operationID = UUID()
        slot.phase = .stopping
        slot.lastError = message
        slot.lifecycleOperationID = operationID
        slot.lifecycleKind = .stop
        slot.terminationTask = nil
        let task = Task { [weak self] () throws -> MCPClientSession? in
            guard let self else { throw CancellationError() }
            await self.performFailureCleanup(
                serverID: serverID,
                generation: generation,
                operationID: operationID,
                message: message
            )
            return nil
        }
        slot.lifecycleTask = task
        slots[serverID] = slot
    }

    private func performFailureCleanup(
        serverID: UUID,
        generation: UInt64,
        operationID: UUID,
        message: String
    ) async {
        let resources = resourcesForStop(
            serverID: serverID,
            generation: generation,
            operationID: operationID
        )
        resources.toolTask?.cancel()
        if let session = resources.session { await session.disconnect() }
        await catalog.remove(serverID: serverID)
        guard isCurrent(
            serverID: serverID,
            generation: generation,
            operationID: operationID
        ) else { return }
        slots[serverID]?.session = nil
        slots[serverID]?.transport = nil
        slots[serverID]?.toolChangeTask = nil
        slots[serverID]?.terminationTask = nil
        slots[serverID]?.toolCount = 0
        slots[serverID]?.phase = .failed
        slots[serverID]?.lastError = message
        slots[serverID]?.lifecycleTask = nil
        slots[serverID]?.lifecycleOperationID = nil
        slots[serverID]?.lifecycleKind = nil
        slots[serverID]?.stoppedAt = .now
    }

    private func handleToolListChanged(serverID: UUID, generation: UInt64) async {
        guard slots[serverID]?.generation == generation,
              slots[serverID]?.phase == .running,
              let session = slots[serverID]?.session,
              let server = try? await registry.load().first(where: { $0.id == serverID }) else {
            return
        }
        do {
            let tools = try await session.refreshTools()
            guard slots[serverID]?.generation == generation,
                  slots[serverID]?.session === session else { return }
            let registered = await catalog.replace(server: server, tools: tools)
            slots[serverID]?.toolCount = registered.count
        } catch {
            guard slots[serverID]?.generation == generation else { return }
            slots[serverID]?.lastError = error.localizedDescription
        }
    }
}
