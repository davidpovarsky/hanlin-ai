import Foundation
import Observation
import SwiftUI

public enum MCPPersistentLoadState: Equatable, Sendable {
    case notLoaded
    case loading
    case loaded
    case failed(String)
}

enum MCPChatSelectionReadError: Error, Sendable {
    case storageNotLoaded
}

@MainActor
@Observable
private final class MCPChatSelectionSignal {
    var revision: UInt64 = 0
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
    @ObservationIgnored private var selectionSignals: [MCPChatSelectionScope: MCPChatSelectionSignal] = [:]

    let nodeRuntime: NodeRuntimeService
    let controller: MCPRuntimeController
    private let registryStore: MCPServerRegistryStore
    private let selectionStore: MCPChatSelectionStore
    // Internal fixture seam only; nil in production, without an extra suspension.
    private let selectionIntentAdmission: (@Sendable () async -> Void)?
    private let administrationAdmission: (@Sendable () async -> Void)?
    private let configurationStore: MCPFeatureConfigurationStore
    private let secretStore: MCPSecretStore
    private let installService: MCPPackageInstallService
    private var loadTask: Task<Void, Never>?
    private var activeAdministrationID: UUID?
    var isPerformingAdministration: Bool { activeAdministrationID != nil }
    private var activeInstallOperationID: UUID?
    private var activeInstallationID: UUID?
    private var installationCancellationRequested = false
    @ObservationIgnored private var foregroundPreloadID: UUID?

    init(
        runtime: NodeRuntimeService? = nil,
        fileLayout: MCPFileLayout = .default,
        runtimeEnvironment: RuntimeEnvironmentStore? = nil,
        selectionStore: MCPChatSelectionStore? = nil,
        selectionIntentAdmission: (@Sendable () async -> Void)? = nil,
        administrationAdmission: (@Sendable () async -> Void)? = nil
    ) {
        let runtime = runtime ?? AppRuntimeCore.shared.node
        let registry = MCPServerRegistryStore(fileLayout: fileLayout)
        let secrets = MCPSecretStore()
        nodeRuntime = runtime
        registryStore = registry
        self.selectionStore = selectionStore ?? MCPChatSelectionStore(fileLayout: fileLayout)
        self.selectionIntentAdmission = selectionIntentAdmission
        self.administrationAdmission = administrationAdmission
        configurationStore = MCPFeatureConfigurationStore(fileLayout: fileLayout)
        secretStore = secrets
        controller = MCPRuntimeController(runtime: runtime, registry: registry, secrets: secrets,
            runtimeEnvironment: runtimeEnvironment ?? AppRuntimeCore.shared.environment, fileLayout: fileLayout)
        installService = MCPPackageInstallService(runtime: runtime, fileLayout: fileLayout)
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
                    let persistedServers = try await registryStore.load()
                    let loadedServers = await controller.migratePersistedPaths(
                        in: persistedServers
                    )
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
        do { try await setEnabledReporting(enabled) }
        catch { lastError = error.localizedDescription }
    }

    func setEnabledReporting(_ enabled: Bool) async throws {
        try await configureReporting(enabled: enabled)
    }

    func configureReporting(enabled: Bool? = nil, debugLogging: Bool? = nil) async throws {
        try requirePersistentStorage()
        try await reportOperation {
            var updated = configuration
            if let enabled { updated.isEnabled = enabled }
            if let debugLogging { updated.debugLoggingEnabled = debugLogging }
            // Publish only after the original store has actually committed.
            try await configurationStore.save(updated)
            configuration = updated
            if !updated.isEnabled { await controller.stopAll() }
        }
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
        do { try await startReporting(server) }
        catch { lastError = error.localizedDescription }
    }

    func startReporting(_ server: MCPServerDescriptor) async throws {
        try requirePersistentStorage()
        try await reportOperation {
            guard configuration.isEnabled else { throw MCPError.featureDisabled }
            try await controller.start(server)
        }
    }

    func stop(_ server: MCPServerDescriptor) async {
        do { try await stopReporting(server) }
        catch { lastError = error.localizedDescription }
    }

    func stopReporting(_ server: MCPServerDescriptor) async throws {
        try requirePersistentStorage()
        try await reportOperation {
            await controller.stop(serverID: server.id)
        }
        if let status = statuses[server.id], status.state == .failed {
            throw MCPError.runtimeUnavailable(status.message ?? "The server did not stop.")
        }
    }

    func restart(_ server: MCPServerDescriptor) async {
        do { try await restartReporting(server) }
        catch { lastError = error.localizedDescription }
    }

    func restartReporting(_ server: MCPServerDescriptor) async throws {
        try requirePersistentStorage()
        try await reportOperation {
            guard configuration.isEnabled else { throw MCPError.featureDisabled }
            try await controller.restart(server)
        }
    }

    func refreshTools(_ server: MCPServerDescriptor) async {
        do { try await refreshToolsReporting(server) }
        catch { lastError = error.localizedDescription }
    }

    func refreshToolsReporting(_ server: MCPServerDescriptor) async throws {
        try requirePersistentStorage()
        try await reportOperation {
            guard configuration.isEnabled else { throw MCPError.featureDisabled }
            try await controller.refreshTools(server)
        }
    }

    func tools(for server: MCPServerDescriptor) async -> [MCPToolDescriptor] {
        do { return try await toolsReporting(for: server) }
        catch { lastError = error.localizedDescription; return [] }
    }

    func toolsReporting(for server: MCPServerDescriptor) async throws -> [MCPToolDescriptor] {
        try requirePersistentStorage()
        return try await reportOperation {
            guard configuration.isEnabled else { throw MCPError.featureDisabled }
            return try await controller.toolDescriptors(serverIDs: [server.id])
        }
    }

    func requirePersistentStorage() throws {
        guard persistentLoadState == .loaded else {
            let reason: String
            if case .failed(let message) = persistentLoadState { reason = message }
            else { reason = "The store has not finished loading." }
            throw HanlinApplicationMCPError.storageUnavailable(reason)
        }
    }

    private func admitAdministration() throws -> UUID {
        guard activeAdministrationID == nil else {
            throw HanlinApplicationMCPError.operationInProgress
        }
        let id = UUID()
        activeAdministrationID = id
        return id
    }

    private func finishAdministration(_ id: UUID) {
        if activeAdministrationID == id { activeAdministrationID = nil }
    }

    private func reportOperation<Value>(
        _ operation: @MainActor () async throws -> Value
    ) async throws -> Value {
        let operationID = try admitAdministration()
        defer { finishAdministration(operationID) }
        if let administrationAdmission { await administrationAdmission() }
        do {
            let result = try await operation()
            lastError = nil
            await refreshSnapshots()
            return result
        } catch {
            lastError = error.localizedDescription
            await refreshSnapshots()
            throw error
        }
    }

    /// Stable per-chat observation: inserting or mutating another token is ignored.
    func selectionRevision(chatID: UUID, temporary: Bool) -> UInt64 {
        selectionSignal(for: .init(chatID: chatID, temporary: temporary)).revision
    }

    private func selectionSignal(for scope: MCPChatSelectionScope) -> MCPChatSelectionSignal {
        if let signal = selectionSignals[scope] { return signal }
        let signal = MCPChatSelectionSignal()
        selectionSignals[scope] = signal
        return signal
    }

    /// Notification only; the committed store outcome carries no new authority.
    func publishSelectionMutation(_ mutation: MCPChatSelectionMutation) {
        for scope in mutation.affectedScopes { selectionSignal(for: scope).revision &+= 1 }
    }

    /// Request-scoped read: absence uses defaults, while storage failures throw.
    func readSelection(chatID: UUID, temporary: Bool) async throws -> Set<UUID> {
        _ = selectionRevision(chatID: chatID, temporary: temporary)
        guard persistentLoadState == .loaded else { throw MCPChatSelectionReadError.storageNotLoaded }
        if let stored = try await selectionStore.selection(chatID: chatID, temporary: temporary) {
            return stored
        }
        return Set(servers.filter { $0.isGloballyEnabled && $0.isEnabledForNewChats }.map(\.id))
    }

    func selection(chatID: UUID, temporary: Bool) async -> Set<UUID> {
        _ = selectionRevision(chatID: chatID, temporary: temporary)
        do {
            if let stored = try await selectionStore.selection(chatID: chatID, temporary: temporary) {
                return stored
            }
        } catch { lastError = error.localizedDescription }
        return Set(servers.filter { $0.isGloballyEnabled && $0.isEnabledForNewChats }.map(\.id))
    }

    func setSelection(_ ids: Set<UUID>, chatID: UUID, temporary: Bool) async {
        guard persistentLoadState == .loaded else { return }
        do {
            let mutation = try await selectionStore.setSelection(ids, chatID: chatID, temporary: temporary)
            publishSelectionMutation(mutation)
        } catch { lastError = error.localizedDescription }
    }

    /// Composer intent against canonical current storage, never a UI selection
    /// snapshot. Throws this request's failure and returns its committed readback.
    /// The caller still owns scope/revision guards for asynchronous presentation.
    /// Defaults are a request-entry snapshot of eligible configured servers, used
    /// only if this intent first materializes an absent record. Later default or
    /// global-enable changes never rebase explicit selections. This is a stored
    /// preference; runtime resolution/calls still enforce current eligibility.
    @discardableResult
    func applySelectionIntent(
        _ intent: MCPChatServerSelectionIntent,
        chatID: UUID,
        temporary: Bool
    ) async throws -> Set<UUID> {
        guard persistentLoadState == .loaded else { throw MCPChatSelectionReadError.storageNotLoaded }
        let defaults = Set(servers.filter { $0.isGloballyEnabled && $0.isEnabledForNewChats }.map(\.id))
        if let selectionIntentAdmission { await selectionIntentAdmission() }
        let result = try await selectionStore.applySelectionIntent(
            intent, chatID: chatID, temporary: temporary, defaultServerIDs: defaults
        )
        publishSelectionMutation(result.mutation)
        return result.serverIDs
    }

    func install(spec: MCPPackageSpec, entryPointOverride: String? = nil) async {
        _ = await performInstall(spec: spec, existing: nil, entryPointOverride: entryPointOverride)
    }

    func installReporting(
        spec: MCPPackageSpec, entryPointOverride: String? = nil
    ) async throws -> MCPServerDescriptor {
        try await performInstall(spec: spec, existing: nil, entryPointOverride: entryPointOverride).get()
    }

    func replacePackage(_ server: MCPServerDescriptor, latestCompatible: Bool) async {
        _ = try? await replacePackageReporting(server, latestCompatible: latestCompatible)
    }

    func replacePackageReporting(
        _ server: MCPServerDescriptor, latestCompatible: Bool
    ) async throws -> MCPServerDescriptor {
        let spec: MCPPackageSpec
        do {
            spec = try MCPPackageSpec(latestCompatible
                ? server.packageName : "\(server.packageName)@\(server.resolvedVersion)")
        } catch {
            installState = .failed(operationID: nil, message: error.localizedDescription, rollbackMessage: nil)
            lastError = error.localizedDescription
            throw error
        }
        return try await performInstall(spec: spec, existing: server,
            entryPointOverride: server.binName ?? relativeEntryPoint(of: server),
            latestCompatible: latestCompatible).get()
    }

    private func performInstall(
        spec: MCPPackageSpec,
        existing: MCPServerDescriptor?,
        entryPointOverride: String?,
        latestCompatible: Bool? = nil
    ) async -> Result<MCPServerDescriptor, any Error> {
        do { try requirePersistentStorage() }
        catch { return .failure(error) }
        let administrationID: UUID
        do { administrationID = try admitAdministration() }
        catch { return .failure(error) }
        activeInstallationID = administrationID
        installationCancellationRequested = false
        defer {
            if activeInstallationID == administrationID {
                activeInstallationID = nil
                installationCancellationRequested = false
            }
            finishAdministration(administrationID)
        }
        if let administrationAdmission { await administrationAdmission() }
        guard !installationCancellationRequested, !Task.isCancelled else {
            installState = .cancelled
            activeInstallOperationID = nil
            return .failure(CancellationError())
        }
        var existing = existing
        var spec = spec
        var entryPointOverride = entryPointOverride
        if let requested = existing {
            do {
                // A retained original UI descriptor can predate this operation.
                // Re-read it under the same lease before choosing version,
                // credentials, arguments or rollback state; never resurrect an
                // installation already removed by another completed request.
                let installed = try await registryStore.load()
                guard let current = installed.first(where: { $0.id == requested.id }) else {
                    throw MCPError.serverNotFound
                }
                existing = current
                if let latestCompatible {
                    spec = try MCPPackageSpec(latestCompatible
                        ? current.packageName : "\(current.packageName)@\(current.resolvedVersion)")
                }
                entryPointOverride = current.binName ?? relativeEntryPoint(of: current)
            } catch {
                installState = .failed(operationID: nil, message: error.localizedDescription, rollbackMessage: nil)
                lastError = error.localizedDescription
                return .failure(error)
            }
        }
        installState = .previewing
        let wasRunning = existing.map { statuses[$0.id]?.state == .running } ?? false
        if let existing { await controller.stop(serverID: existing.id) }
        var installation: MCPPackageInstallation?
        do {
            try Task.checkCancellation()
            if installationCancellationRequested { throw CancellationError() }
            let defaultArgs: [String]
            let isServerFilesystem: Bool = {
                if case .npm(let pkgName, _) = spec.source {
                    return pkgName.lowercased().contains("server-filesystem")
                }
                return false
            }()
            if isServerFilesystem, (existing?.arguments.isEmpty ?? true) {
                let allowedDir = RuntimeFileLayout.default.clients.path
                try? FileManager.default.createDirectory(
                    atPath: allowedDir,
                    withIntermediateDirectories: true
                )
                defaultArgs = [allowedDir]
            } else {
                defaultArgs = existing?.arguments ?? []
            }
            var installed = try await installService.install(
                spec,
                serverID: existing?.id ?? UUID(),
                entryPointOverride: entryPointOverride,
                arguments: defaultArgs
            ) { progress in
                await MainActor.run {
                    guard self.activeInstallationID == administrationID else { return }
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
                await self.cancelInstallationIfRequested(
                    installationID: administrationID, operationID: progress.operationID)
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
                try Task.checkCancellation()
                if installationCancellationRequested { throw CancellationError() }
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
                try Task.checkCancellation()
                if installationCancellationRequested { throw CancellationError() }
                _ = try await registryStore.upsert(installed.descriptor)
                try Task.checkCancellation()
                if installationCancellationRequested { throw CancellationError() }
                // After this durable commit, late cancellation cannot report that
                // the actual installed package was rolled back.
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
            return .success(installed.descriptor)
        } catch is CancellationError {
            let rollback = await recoverFailedInstallation(installation, existing: existing, restart: wasRunning)
            activeInstallOperationID = nil
            if let rollback {
                let message = "The MCP installation was cancelled, but rollback did not complete."
                installState = .failed(operationID: nil, message: message, rollbackMessage: rollback)
                lastError = [message, rollback].joined(separator: "\n")
                return .failure(HanlinApplicationMCPError.installationFailed(
                    message: message, rollbackMessage: rollback))
            }
            installState = .cancelled
            lastError = nil
            return .failure(CancellationError())
        } catch {
            let operationID = activeInstallOperationID
            let rollbackMessage = await recoverFailedInstallation(installation, existing: existing, restart: wasRunning)
            if installationCancellationRequested, rollbackMessage == nil {
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
            if case .cancelled = installState { return .failure(CancellationError()) }
            if case .failed(_, let message, let rollback) = installState {
                return .failure(HanlinApplicationMCPError.installationFailed(
                    message: message, rollbackMessage: rollback))
            }
            return .failure(error)
        }
    }

    private func recoverFailedInstallation(
        _ installation: MCPPackageInstallation?,
        existing: MCPServerDescriptor?,
        restart: Bool
    ) async -> String? {
        var failures: [String] = []
        if let installation {
            await controller.stop(serverID: installation.descriptor.id)
            do { try await installService.rollback(installation) }
            catch { failures.append("Package rollback: " + error.localizedDescription) }
        }
        if let existing {
            var restored = false
            do {
                _ = try await registryStore.upsert(existing)
                restored = true
            } catch { failures.append("Registry restoration: " + error.localizedDescription) }
            if restart, restored {
                do { try await controller.start(existing) }
                catch { failures.append("Previous server restart: " + error.localizedDescription) }
            }
        } else if let installation {
            do { _ = try await registryStore.remove(id: installation.descriptor.id) }
            catch { failures.append("Registry removal: " + error.localizedDescription) }
        }
        do { servers = try await registryStore.load() }
        catch { failures.append("Registry readback: " + error.localizedDescription) }
        await refreshSnapshots()
        return failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    private func relativeEntryPoint(of server: MCPServerDescriptor) -> String? {
        if let relative = server.entryPointRelativePath {
            return relative
        }
        let root = URL(fileURLWithPath: server.packageRoot, isDirectory: true).standardizedFileURL.path
        let entry = URL(fileURLWithPath: server.entryPoint).standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard entry.hasPrefix(prefix) else { return nil }
        return String(entry.dropFirst(prefix.count))
    }

    func cancelInstall() async {
        guard let installationID = activeInstallationID else { return }
        installationCancellationRequested = true
        guard let operationID = activeInstallOperationID else { return }
        await cancelInstallationIfRequested(installationID: installationID, operationID: operationID)
    }

    private func cancelInstallationIfRequested(installationID: UUID, operationID: UUID) async {
        guard activeInstallationID == installationID, installationCancellationRequested else { return }
        await installService.cancel(operationID: operationID)
        // Completion/new work can interleave with the original cancellation RPC.
        guard activeInstallationID == installationID else { return }
        installState = .cancelled
    }

    func preview(spec: MCPPackageSpec) async throws -> MCPPackageManifestPreview {
        try requirePersistentStorage()
        return try await reportOperation { try await installService.preview(spec) }
    }

    func update(_ server: MCPServerDescriptor) async {
        do {
            if servers.contains(where: { $0.id == server.id }) {
                _ = try await updateSettingsReporting(.init(server: server), for: server.id)
            } else {
                try requirePersistentStorage()
                try await reportOperation { servers = try await registryStore.upsert(server) }
            }
        } catch { lastError = error.localizedDescription }
    }

    func updateSettingsReporting(
        _ settings: MCPServerSettings, for id: UUID
    ) async throws -> MCPServerDescriptor {
        try requirePersistentStorage()
        return try await reportOperation {
            let committed = try await registryStore.updateSettings(for: id, settings: settings)
            servers = committed
            guard let result = committed.first(where: { $0.id == id }) else {
                throw MCPError.serverNotFound
            }
            return result
        }
    }

    func updateEnvironment(_ drafts: [MCPEnvironmentDraft], for server: MCPServerDescriptor) async {
        _ = try? await updateEnvironmentReporting(drafts, for: server)
    }

    func updateEnvironmentReporting(
        _ drafts: [MCPEnvironmentDraft], for server: MCPServerDescriptor
    ) async throws -> MCPServerDescriptor {
        try requirePersistentStorage()
        return try await reportOperation {
            let committed = try await Self.persistEnvironment(
                drafts, for: server, registryStore: registryStore, secretStore: secretStore)
            servers = committed
            guard let result = committed.first(where: { $0.id == server.id }) else {
                throw MCPError.serverNotFound
            }
            return result
        }
    }

    /// The original provider stages new Keychain items, commits their references,
    /// and only then removes values no longer used by any saved server.
    static func persistEnvironment(
        _ drafts: [MCPEnvironmentDraft],
        for server: MCPServerDescriptor,
        registryStore: MCPServerRegistryStore,
        secretStore: MCPSecretStore
    ) async throws -> [MCPServerDescriptor] {
        // Validate every original normalized name before staging any Keychain
        // value. Duplicate names otherwise trap runtime Dictionary construction.
        var names = Set<String>()
        for draft in drafts {
            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { continue }
            guard names.insert(name).inserted else {
                throw MCPError.duplicateEnvironmentName(name)
            }
        }
        var values: [MCPEnvironmentVariable] = []
        var stagedReferences: Set<String> = []
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
                        reference = try await secretStore.set(draft.value)
                        stagedReferences.insert(reference)
                    }
                    values.append(.init(name: name, value: nil, secretReference: reference))
                } else {
                    values.append(.init(name: name, value: draft.value, secretReference: nil))
                }
            }
            let committed = try await registryStore.replaceEnvironment(
                for: server.id, matching: server.environment, with: values
            )
            let retained = Set(committed.flatMap(\.environment).compactMap(\.secretReference))
            let previous = Set(server.environment.compactMap(\.secretReference))
            for reference in previous.subtracting(retained) {
                await secretStore.remove(reference: reference)
            }
            return committed
        } catch {
            // save() writes its verified backup first. An error can therefore
            // mean that a new generation is durable in just one copy. Unknown
            // reachability also retains the value instead of losing credentials.
            if let retained = try? await registryStore.retainedSecretReferences() {
                for reference in stagedReferences.subtracting(retained) {
                    await secretStore.remove(reference: reference)
                }
            }
            throw error
        }
    }

    func uninstall(_ server: MCPServerDescriptor) async {
        do { try await uninstallReporting(server) }
        catch { lastError = error.localizedDescription }
    }

    func uninstallReporting(_ server: MCPServerDescriptor) async throws {
        try requirePersistentStorage()
        try await reportOperation {
            await controller.forgetInstalledServer(id: server.id)
            if let connection = try? await nodeRuntime.currentConnection() {
                _ = try? await connection.data(
                    path: "/v1/servers/\(server.id.uuidString.lowercased())",
                    method: "DELETE"
                )
            }
            let mutation = try await selectionStore.removeServer(server.id)
            publishSelectionMutation(mutation)
            servers = try await registryStore.remove(id: server.id)
        }
    }

    func requestScope(chatID: UUID?, temporary: Bool = false) async -> AssistantToolRequestScope {
        guard persistentLoadState == .loaded else {
            return AssistantToolRequestScope(
                chatID: chatID,
                mcpServerIDs: [],
                mcpGloballyEnabled: false,
                isTemporaryChat: temporary
            )
        }
        let ids: Set<UUID>
        if let chatID {
            do {
                ids = try await readSelection(chatID: chatID, temporary: temporary)
            } catch {
                // A damaged selection is not an absent preference. Never admit
                // default MCP servers after an actual persistent read failure.
                lastError = error.localizedDescription
                return AssistantToolRequestScope(chatID: chatID, mcpServerIDs: [],
                    mcpGloballyEnabled: false, isTemporaryChat: temporary)
            }
        } else {
            ids = Set(servers.filter(\.isEnabledForNewChats).map(\.id))
        }
        return AssistantToolRequestScope(
            chatID: chatID,
            mcpServerIDs: ids,
            mcpGloballyEnabled: configuration.isEnabled,
            isTemporaryChat: temporary
        )
    }

    func synchronizeRuntimeState() async {
        if let persistedServers = try? await registryStore.load() {
            servers = persistedServers
        }
        await refreshSnapshots()
    }

    func handleScenePhase(_ phase: ScenePhase) async {
        switch phase {
        case .active:
            let preloadID = UUID()
            foregroundPreloadID = preloadID
            await loadIfNeeded()
            guard foregroundPreloadID == preloadID,
                  persistentLoadState == .loaded, configuration.isEnabled else { return }
            let administrationID: UUID
            do { administrationID = try admitAdministration() }
            catch { return } // Optional preload never supersedes an admitted user operation.
            defer { finishAdministration(administrationID) }
            for server in servers where server.preloadOnLaunch && server.isGloballyEnabled {
                guard foregroundPreloadID == preloadID, configuration.isEnabled else { break }
                do {
                    _ = try await controller.ensureRunning(server, reason: .preload)
                } catch {
                    lastError = error.localizedDescription
                }
            }
            await refreshSnapshots()
        case .background:
            // Invalidate pending foreground work even when an existing user
            // operation legitimately retains its OS background continuation.
            foregroundPreloadID = nil
            guard !RuntimeBackgroundContinuation.shared.isKeepingUserWorkAlive else { return }
            // Do not wait for/revoke an administration lease: original controller
            // stop cancels the currently observed startup and remains responsive.
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
