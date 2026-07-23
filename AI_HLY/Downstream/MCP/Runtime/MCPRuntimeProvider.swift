import Foundation
import Observation
import SwiftUI

enum MCPPersistentLoadState: Equatable, Sendable {
    case notLoaded
    case loading
    case loaded
    case failed(String)
}

@MainActor
@Observable
final class MCPRuntimeProvider {
    static let shared = MCPRuntimeProvider()

    private(set) var configuration: MCPFeatureConfiguration = .default
    private(set) var servers: [MCPServerDescriptor] = []
    private(set) var statuses: [UUID: MCPServerStatus] = [:]
    private(set) var runtimeSnapshot: MCPRuntimeSnapshot = .stopped
    private(set) var installState: MCPInstallState = .idle
    private(set) var lastError: String?
    private(set) var persistentLoadState: MCPPersistentLoadState = .notLoaded

    let nodeRuntime: NodeRuntimeService
    let controller: MCPRuntimeController
    private let registryStore: MCPServerRegistryStore
    private let selectionStore: MCPChatSelectionStore
    private let configurationStore: MCPFeatureConfigurationStore
    private let secretStore: MCPSecretStore
    private let installService: MCPPackageInstallService
    private var loadTask: Task<Void, Never>?
    private var activeInstallOperationID: UUID?
    private var cancelledInstallOperationIDs: Set<UUID> = []

    private init() {
        let runtime = AppRuntimeCore.shared.node
        let registry = MCPServerRegistryStore()
        let secrets = MCPSecretStore()
        nodeRuntime = runtime
        registryStore = registry
        selectionStore = MCPChatSelectionStore()
        configurationStore = MCPFeatureConfigurationStore()
        secretStore = secrets
        controller = MCPRuntimeController(runtime: runtime, registry: registry, secrets: secrets)
        installService = MCPPackageInstallService(runtime: runtime)
    }

    func loadIfNeeded(startHost: Bool = false) async {
        switch persistentLoadState {
        case .loaded:
            break
        case .loading:
            if let loadTask { await loadTask.value }
        case .failed:
            return
        case .notLoaded:
            persistentLoadState = .loading
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let loadedConfiguration = try await configurationStore.load()
                    let loadedServers = try await registryStore.load()
                    configuration = loadedConfiguration
                    servers = loadedServers
                    persistentLoadState = .loaded
                    lastError = nil
                } catch {
                    let message = error.localizedDescription
                    persistentLoadState = .failed(message)
                    lastError = message
                }
                loadTask = nil
            }
            loadTask = task
            await task.value
        }
        if startHost, persistentLoadState == .loaded { await ensureRuntime() }
        await refreshSnapshots()
    }

    func retryPersistentLoad() async {
        guard case .failed = persistentLoadState else { return }
        persistentLoadState = .notLoaded
        await loadIfNeeded(startHost: false)
    }

    func setEnabled(_ enabled: Bool) async {
        guard persistentLoadState == .loaded else { return }
        configuration.isEnabled = enabled
        do { try await configurationStore.save(configuration) } catch { lastError = error.localizedDescription }
        if !enabled { await controller.stopAll() }
        await refreshSnapshots()
    }

    func ensureRuntime() async {
        do {
            _ = try await nodeRuntime.ensureRunning(debug: configuration.debugLoggingEnabled)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        await refreshSnapshots()
    }

    func start(_ server: MCPServerDescriptor) async {
        guard configuration.isEnabled, persistentLoadState == .loaded else { return }
        do { try await controller.start(server); lastError = nil } catch { lastError = error.localizedDescription }
        await refreshSnapshots()
    }

    func stop(_ server: MCPServerDescriptor) async {
        await controller.stop(serverID: server.id)
        await refreshSnapshots()
    }

    func restart(_ server: MCPServerDescriptor) async {
        guard persistentLoadState == .loaded else { return }
        do { try await controller.restart(server); lastError = nil } catch { lastError = error.localizedDescription }
        await refreshSnapshots()
    }

    func refreshTools(_ server: MCPServerDescriptor) async {
        guard persistentLoadState == .loaded else { return }
        do { try await controller.refreshTools(server); lastError = nil } catch { lastError = error.localizedDescription }
        await refreshSnapshots()
    }

    func tools(for server: MCPServerDescriptor) async -> [MCPToolDescriptor] {
        guard persistentLoadState == .loaded else { return [] }
        do {
            let tools = try await controller.toolDescriptors(serverIDs: [server.id])
            lastError = nil
            await refreshSnapshots()
            return tools
        } catch {
            lastError = error.localizedDescription
            await refreshSnapshots()
            return []
        }
    }

    func selection(chatID: UUID, temporary: Bool) async -> Set<UUID> {
        do {
            if let stored = try await selectionStore.selection(chatID: chatID, temporary: temporary) {
                return stored
            }
        } catch { lastError = error.localizedDescription }
        return Set(servers.filter { $0.isGloballyEnabled && $0.isEnabledForNewChats }.map(\.id))
    }

    func setSelection(_ ids: Set<UUID>, chatID: UUID, temporary: Bool) async {
        guard persistentLoadState == .loaded else { return }
        do { try await selectionStore.setSelection(ids, chatID: chatID, temporary: temporary) }
        catch { lastError = error.localizedDescription }
    }

    func install(spec: MCPPackageSpec, entryPointOverride: String? = nil) async {
        await performInstall(spec: spec, existing: nil, entryPointOverride: entryPointOverride)
    }

    func replacePackage(_ server: MCPServerDescriptor, latestCompatible: Bool) async {
        do {
            let packageSpec = latestCompatible
                ? server.packageName
                : "\(server.packageName)@\(server.resolvedVersion)"
            let spec = try MCPPackageSpec(packageSpec)
            await performInstall(
                spec: spec,
                existing: server,
                entryPointOverride: server.binName ?? relativeEntryPoint(of: server)
            )
        } catch {
            installState = .failed(operationID: nil, message: error.localizedDescription, rollbackMessage: nil)
            lastError = error.localizedDescription
        }
    }

    private func performInstall(
        spec: MCPPackageSpec,
        existing: MCPServerDescriptor?,
        entryPointOverride: String?
    ) async {
        guard persistentLoadState == .loaded else { return }
        installState = .previewing
        let wasRunning = existing.map { statuses[$0.id]?.state == .running } ?? false
        if let existing { await controller.stop(serverID: existing.id) }
        var installation: MCPPackageInstallation?
        do {
            var installed = try await installService.install(
                spec,
                serverID: existing?.id ?? UUID(),
                entryPointOverride: entryPointOverride
            ) { progress in
                await MainActor.run {
                    self.activeInstallOperationID = progress.operationID
                    if let terminalError = progress.terminalError {
                        self.installState = .failed(
                            operationID: progress.operationID,
                            message: terminalError.localizedMessage,
                            rollbackMessage: terminalError.rollbackMessage
                        )
                    } else {
                        self.installState = .installing(
                            operationID: progress.operationID,
                            phase: progress.phase,
                            fraction: progress.fraction
                        )
                    }
                }
            }
            if let existing {
                installed.descriptor.slug = existing.slug
                installed.descriptor.displayName = existing.displayName
                installed.descriptor.arguments = existing.arguments
                installed.descriptor.environment = existing.environment
                installed.descriptor.installedAt = existing.installedAt
                installed.descriptor.isGloballyEnabled = existing.isGloballyEnabled
                installed.descriptor.isEnabledForNewChats = existing.isEnabledForNewChats
                installed.descriptor.autoStart = existing.autoStart
            }
            installation = installed
            do {
                if installed.descriptor.compatibility.requiresConfiguration != true {
                    installState = .installing(
                        operationID: installed.operationID,
                        phase: .starting,
                        fraction: 0.98
                    )
                    _ = try await controller.ensureRunning(
                        installed.descriptor,
                        reason: .postInstallValidation
                    )
                }
                _ = try await registryStore.upsert(installed.descriptor)
                try await installService.commit(installed)
                if !wasRunning && !installed.descriptor.preloadOnLaunch {
                    await controller.stop(serverID: installed.descriptor.id)
                }
            } catch {
                throw error
            }
            servers = try await registryStore.load()
            installState = .completed(serverID: installed.descriptor.id)
            activeInstallOperationID = nil
            lastError = nil
        } catch is CancellationError {
            _ = await recoverFailedInstallation(installation, existing: existing, restart: wasRunning)
            installState = .cancelled
            activeInstallOperationID = nil
        } catch {
            let operationID = activeInstallOperationID
            let rollbackMessage = await recoverFailedInstallation(installation, existing: existing, restart: wasRunning)
            if let operationID = activeInstallOperationID,
               cancelledInstallOperationIDs.remove(operationID) != nil {
                installState = .cancelled
                lastError = nil
            } else {
                if case .failed(let reportedOperationID, let reportedMessage, let reportedRollback) = installState,
                   reportedOperationID == operationID {
                    let effectiveRollback = rollbackMessage ?? reportedRollback
                    installState = .failed(
                        operationID: operationID,
                        message: reportedMessage,
                        rollbackMessage: effectiveRollback
                    )
                    lastError = [reportedMessage, effectiveRollback].compactMap { $0 }.joined(separator: "\n")
                } else {
                    installState = .failed(
                        operationID: operationID,
                        message: error.localizedDescription,
                        rollbackMessage: rollbackMessage
                    )
                    lastError = [error.localizedDescription, rollbackMessage].compactMap { $0 }.joined(separator: "\n")
                }
            }
            activeInstallOperationID = nil
        }
    }

    private func recoverFailedInstallation(
        _ installation: MCPPackageInstallation?,
        existing: MCPServerDescriptor?,
        restart: Bool
    ) async -> String? {
        var rollbackMessage: String?
        if let installation {
            await controller.stop(serverID: installation.descriptor.id)
            do {
                try await installService.rollback(installation)
            } catch {
                rollbackMessage = error.localizedDescription
            }
        }
        if let existing {
            _ = try? await registryStore.upsert(existing)
            if restart { try? await controller.start(existing) }
        } else if let installation {
            _ = try? await registryStore.remove(id: installation.descriptor.id)
        }
        servers = (try? await registryStore.load()) ?? servers
        await refreshSnapshots()
        return rollbackMessage
    }

    private func relativeEntryPoint(of server: MCPServerDescriptor) -> String? {
        let root = URL(fileURLWithPath: server.packageRoot, isDirectory: true).standardizedFileURL.path
        let entry = URL(fileURLWithPath: server.entryPoint).standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard entry.hasPrefix(prefix) else { return nil }
        return String(entry.dropFirst(prefix.count))
    }

    func cancelInstall() async {
        guard let operationID = activeInstallOperationID else { return }
        cancelledInstallOperationIDs.insert(operationID)
        await installService.cancel(operationID: operationID)
        installState = .cancelled
    }

    func preview(spec: MCPPackageSpec) async throws -> MCPPackageManifestPreview {
        try await installService.preview(spec)
    }

    func update(_ server: MCPServerDescriptor) async {
        guard persistentLoadState == .loaded else { return }
        do { servers = try await registryStore.upsert(server) }
        catch { lastError = error.localizedDescription }
    }

    func updateEnvironment(_ drafts: [MCPEnvironmentDraft], for server: MCPServerDescriptor) async {
        guard persistentLoadState == .loaded else { return }
        var updated = server
        var values: [MCPEnvironmentVariable] = []
        do {
            for draft in drafts {
                let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { continue }
                let existing = server.environment.first { $0.name == name }
                if draft.isSecret {
                    let reference: String
                    if draft.value.isEmpty, let saved = existing?.secretReference {
                        reference = saved
                    } else {
                        if let old = existing?.secretReference { await secretStore.remove(reference: old) }
                        reference = try await secretStore.set(draft.value)
                    }
                    values.append(.init(name: name, value: nil, secretReference: reference))
                } else {
                    if let old = existing?.secretReference { await secretStore.remove(reference: old) }
                    values.append(.init(name: name, value: draft.value, secretReference: nil))
                }
            }
            updated.environment = values
            updated.updatedAt = .now
            servers = try await registryStore.upsert(updated)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func uninstall(_ server: MCPServerDescriptor) async {
        guard persistentLoadState == .loaded else { return }
        await controller.stop(serverID: server.id)
        do {
            if let connection = try? await nodeRuntime.currentConnection() {
                _ = try? await connection.data(
                    path: "/v1/servers/\(server.id.uuidString.lowercased())",
                    method: "DELETE"
                )
            }
            try await selectionStore.removeServer(server.id)
            servers = try await registryStore.remove(id: server.id)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        await refreshSnapshots()
    }

    func requestScope(chatID: UUID?, temporary: Bool = false) async -> AssistantToolRequestScope {
        guard persistentLoadState == .loaded else { return .nativeOnly }
        let ids: Set<UUID>
        if let chatID {
            ids = await selection(chatID: chatID, temporary: temporary)
        } else {
            ids = Set(servers.filter(\.isEnabledForNewChats).map(\.id))
        }
        return AssistantToolRequestScope(
            chatID: chatID,
            mcpServerIDs: ids,
            mcpGloballyEnabled: configuration.isEnabled
        )
    }

    func handleScenePhase(_ phase: ScenePhase) async {
        switch phase {
        case .active:
            await loadIfNeeded()
            guard persistentLoadState == .loaded, configuration.isEnabled else { return }
            for server in servers where server.preloadOnLaunch && server.isGloballyEnabled {
                do {
                    _ = try await controller.ensureRunning(server, reason: .preload)
                } catch {
                    lastError = error.localizedDescription
                }
            }
            await refreshSnapshots()
        case .background:
            await controller.stopAll()
            await refreshSnapshots()
        case .inactive: break
        @unknown default: break
        }
    }

    private func refreshSnapshots() async {
        let currentStatuses = await controller.statuses()
        let nodeSnapshot = await nodeRuntime.snapshot()
        let state: MCPNodeRuntimeState = switch nodeSnapshot.state {
        case .preparing: .starting
        case .ready, .executing: .running
        case .failed, .appRestartRequired: .failed
        case .unavailable, .stopped: .stopped
        }
        let snapshot = MCPRuntimeSnapshot(
            state: state,
            nodeVersion: nodeSnapshot.version,
            protocolVersion: nodeSnapshot.version == nil ? nil : NodeRuntimeService.hostProtocolVersion,
            activeWorkerCount: currentStatuses.values.filter { $0.state == .running }.count,
            message: nodeSnapshot.lastErrorCode
        )
        statuses = currentStatuses
        runtimeSnapshot = snapshot
    }
}
