import SwiftUI

public struct MCPChatServerSheet: View {
    let chatID: UUID
    let temporary: Bool
    let onSelectionChanged: (Int) -> Void
    private let service: HanlinApplicationMCP?
    @State private var provider = MCPRuntimeProvider.shared
    @State private var selected: Set<UUID> = []
    @State private var selectionError: String?

    init(chatID: UUID, temporary: Bool, onSelectionChanged: @escaping (Int) -> Void) {
        self.chatID = chatID; self.temporary = temporary
        self.onSelectionChanged = onSelectionChanged; self.service = nil
    }

    /// Uses the original validated facade, so a retained embedding sheet cannot
    /// admit new selection writes after its conversation owner is revoked.
    public init(service: HanlinApplicationMCP, conversationID: UUID,
                onSelectionChanged: @escaping (Int) -> Void) {
        self.chatID = conversationID; self.temporary = false
        self.onSelectionChanged = onSelectionChanged; self.service = service
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(MCPL10n.string("MCP master switch"), value: provider.configuration.isEnabled ? MCPL10n.string("Enabled") : MCPL10n.string("Disabled"))
                }
                Section {
                    HStack {
                        Button(MCPL10n.string("Select All")) { update(Set(available.map(\.id))) }
                        Spacer()
                        Button(MCPL10n.string("Disable All for This Chat")) { update([]) }
                    }
                }
                Section(MCPL10n.string("Servers")) {
                    ForEach(available) { server in
                        Toggle(isOn: Binding(
                            get: { selected.contains(server.id) },
                            set: { enabled in
                                update(server.id, enabled: enabled)
                            }
                        )) {
                            VStack(alignment: .leading) {
                                Text(server.displayName)
                                if selected.contains(server.id) {
                                    Text(MCPL10n.string("Selected for this chat"))
                                        .font(HanlinTypography.caption)
                                }
                                Text(statusText(for: server))
                                    .font(HanlinTypography.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section { NavigationLink(MCPL10n.string("Open MCP settings")) { MCPServersSettingsView() } }
                if let selectionError {
                    Section { Text(selectionError).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(MCPL10n.string("MCP Servers"))
            .task {
                do {
                    if let service {
                        selected = try await service.selectedServers(for: chatID)
                    } else {
                        await provider.loadIfNeeded()
                        selected = await provider.selection(chatID: chatID, temporary: temporary)
                    }
                    onSelectionChanged(selected.count)
                } catch { selectionError = error.localizedDescription }
            }
        }
    }

    private var available: [MCPServerDescriptor] {
        guard provider.configuration.isEnabled else { return [] }
        return provider.servers.filter(\.isGloballyEnabled)
    }

    private func update(_ next: Set<UUID>) {
        if let service {
            let intents = available.map { ($0.id, next.contains($0.id)) }
            Task {
                do {
                    for (id, enabled) in intents {
                        try Task.checkCancellation()
                        selected = try await service.setServer(id, selected: enabled, for: chatID)
                    }
                    selectionError = nil
                    onSelectionChanged(selected.count)
                } catch { selectionError = error.localizedDescription }
            }
            return
        }
        selected = next
        onSelectionChanged(next.count)
        Task { await provider.setSelection(next, chatID: chatID, temporary: temporary) }
    }

    private func update(_ id: UUID, enabled: Bool) {
        guard let service else {
            var next = selected
            if enabled { next.insert(id) } else { next.remove(id) }
            update(next)
            return
        }
        Task {
            do {
                selected = try await service.setServer(id, selected: enabled, for: chatID)
                selectionError = nil
                onSelectionChanged(selected.count)
            } catch { selectionError = error.localizedDescription }
        }
    }

    private func statusText(for server: MCPServerDescriptor) -> String {
        guard let status = provider.statuses[server.id] else {
            return server.cachedToolCount > 0
                ? MCPL10n.format("Last known: %d tools", server.cachedToolCount)
                : MCPL10n.string("Not started yet")
        }
        switch status.state {
        case .starting:
            return MCPL10n.string("Connecting")
        case .running:
            return MCPL10n.format("Connected — %d tools", status.toolCount)
        case .stopping:
            return MCPL10n.string("Stopping")
        case .failed:
            if status.failure?.kind == .packageInstallationMissing
                || status.failure?.kind == .packagePathInvalid
                || status.failure?.kind == .entryPointInvalid
                || status.failure?.kind == .entryPointMissing
                || status.failure?.kind == .registryMigrationFailed {
                return MCPL10n.string("Installation requires repair")
            }
            return MCPL10n.string("Failed")
        case .stopped:
            return server.cachedToolCount > 0
                ? MCPL10n.format("Last known: %d tools", server.cachedToolCount)
                : MCPL10n.string("Not started yet")
        }
    }
}
