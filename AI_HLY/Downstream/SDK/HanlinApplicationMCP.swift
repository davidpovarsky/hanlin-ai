import Foundation

/// Public access to the same MCP provider, registry, Keychain writer, installer
/// and lifecycle used by the original Hanlin settings and conversation UI.
/// Retain this service or its application context for the host's lifetime.
@MainActor
public final class HanlinApplicationMCP {
    private let provider: MCPRuntimeProvider
    private let validateConversation: @MainActor (UUID) throws -> Void

    #if !HANLIN_ASSISTANT_CAPABILITIES_SDK
    init(context: HanlinApplicationContext) {
        provider = .shared
        validateConversation = { [context] id in _ = try context.record(id) }
    }

    #endif

    /// Bind the original MCP service to an embedding host's live conversation
    /// authority. This callback is revalidated around every asynchronous access.
    public init(validateConversation: @escaping @MainActor (UUID) throws -> Void) {
        self.provider = .shared
        self.validateConversation = validateConversation
    }

    // Internal boundary for native tests using the real isolated provider/store.
    init(provider: MCPRuntimeProvider,
         validateConversation: @escaping @MainActor (UUID) throws -> Void) {
        self.provider = provider
        self.validateConversation = validateConversation
    }

    /// These getters observe the original provider's @Observable properties.
    public var servers: [MCPServerDescriptor] { provider.servers }
    public var statuses: [UUID: MCPServerStatus] { provider.statuses }
    public var configuration: MCPFeatureConfiguration { provider.configuration }
    public var runtime: MCPRuntimeSnapshot { provider.runtimeSnapshot }
    public var installState: MCPInstallState { provider.installState }
    public var persistentLoadState: MCPPersistentLoadState { provider.persistentLoadState }
    public var lastError: String? { provider.lastError }
    public var isPerformingAdministration: Bool { provider.isPerformingAdministration }

    /// Read the original registry without starting Node or installing anything.
    public func load(retryFailedLoad: Bool = false) async throws {
        if retryFailedLoad { await provider.retryPersistentLoad() }
        await provider.loadIfNeeded(startHost: false)
        try provider.requirePersistentStorage()
    }

    public func setEnabled(_ enabled: Bool) async throws {
        try await load()
        try await provider.setEnabledReporting(enabled)
    }

    public func setDebugLoggingEnabled(_ enabled: Bool) async throws {
        try await load()
        try await provider.configureReporting(debugLogging: enabled)
    }

    public func preview(_ spec: MCPPackageSpec) async throws -> MCPPackageManifestPreview {
        try await load()
        return try await provider.preview(spec: spec)
    }

    public func install(
        _ spec: MCPPackageSpec, entryPointOverride: String? = nil
    ) async throws -> MCPServerDescriptor {
        try await load()
        return try await provider.installReporting(spec: spec, entryPointOverride: entryPointOverride)
    }

    /// Use false to repair/reinstall the exact original installed version.
    public func replacePackage(
        _ serverID: UUID, latestCompatible: Bool
    ) async throws -> MCPServerDescriptor {
        try await load()
        return try await provider.replacePackageReporting(
            server(serverID), latestCompatible: latestCompatible)
    }

    public func cancelInstall() async { await provider.cancelInstall() }

    public func start(_ serverID: UUID) async throws {
        try await load()
        try await provider.startReporting(server(serverID))
    }

    /// Returns the actual observed state; a runtime stop failure is not success.
    @discardableResult
    public func stop(_ serverID: UUID) async throws -> MCPServerStatus? {
        try await load()
        try await provider.stopReporting(server(serverID))
        return provider.statuses[serverID]
    }

    public func restart(_ serverID: UUID) async throws {
        try await load()
        try await provider.restartReporting(server(serverID))
    }

    public func refreshTools(_ serverID: UUID) async throws {
        try await load()
        try await provider.refreshToolsReporting(server(serverID))
    }

    public func tools(for serverID: UUID) async throws -> [MCPToolDescriptor] {
        try await load()
        return try await provider.toolsReporting(for: server(serverID))
    }

    /// Edit the current installed row. Package identity and environment secrets
    /// are preserved by the original registry. A changed installed package
    /// rejects a stale settings snapshot instead of restoring its old entry point.
    @discardableResult
    public func updateServer(
        _ serverID: UUID, settings: MCPServerSettings
    ) async throws -> MCPServerDescriptor {
        try await load()
        _ = try server(serverID)
        return try await provider.updateSettingsReporting(settings, for: serverID)
    }

    /// Secret values are staged by the original Keychain writer. An empty secret
    /// draft preserves its existing reference, matching the original editor.
    @discardableResult
    public func updateEnvironment(
        _ values: [MCPEnvironmentDraft], for serverID: UUID
    ) async throws -> MCPServerDescriptor {
        try await load()
        return try await provider.updateEnvironmentReporting(values, for: server(serverID))
    }

    public func uninstall(_ serverID: UUID) async throws {
        try await load()
        try await provider.uninstallReporting(server(serverID))
    }

    public func selectedServers(for conversationID: UUID) async throws -> Set<UUID> {
        try validateConversation(conversationID)
        try await load()
        try validateConversation(conversationID)
        let selected = try await provider.readSelection(chatID: conversationID, temporary: false)
        try validateConversation(conversationID)
        return selected
    }

    /// Commit one intent against the current original store, preserving explicit
    /// empty selections and concurrent edits to other servers or conversations.
    @discardableResult
    public func setServer(
        _ serverID: UUID, selected: Bool, for conversationID: UUID
    ) async throws -> Set<UUID> {
        try validateConversation(conversationID)
        try await load()
        try validateConversation(conversationID)
        if selected { _ = try server(serverID) }
        let committed = try await provider.applySelectionIntent(
            .init(serverID: serverID, isSelected: selected),
            chatID: conversationID, temporary: false)
        try validateConversation(conversationID)
        return committed
    }

    private func server(_ id: UUID) throws -> MCPServerDescriptor {
        guard let result = provider.servers.first(where: { $0.id == id }) else {
            throw MCPError.serverNotFound
        }
        return result
    }
}

#if !HANLIN_ASSISTANT_CAPABILITIES_SDK
extension HanlinApplicationContext {
    /// The original full-runtime MCP services. All returned facades share the
    /// same process-owned provider; no second registry, runtime or engine exists.
    public var mcp: HanlinApplicationMCP { HanlinApplicationMCP(context: self) }
}

#endif
