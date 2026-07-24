import SwiftUI

struct MCPChatServerSheet: View {
    let chatID: UUID
    let temporary: Bool
    let onSelectionChanged: (Int) -> Void
    @State private var provider = MCPRuntimeProvider.shared
    @State private var selected: Set<UUID> = []

    var body: some View {
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
                                var next = selected
                                if enabled { next.insert(server.id) } else { next.remove(server.id) }
                                update(next)
                            }
                        )) {
                            VStack(alignment: .leading) {
                                Text(server.displayName)
                                if selected.contains(server.id) {
                                    Text(MCPL10n.string("Selected for this chat"))
                                        .font(.caption)
                                }
                                Text(statusText(for: server))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section { NavigationLink(MCPL10n.string("Open MCP settings")) { MCPServersSettingsView() } }
            }
            .navigationTitle(MCPL10n.string("MCP Servers"))
            .task {
                await provider.loadIfNeeded()
                selected = await provider.selection(chatID: chatID, temporary: temporary)
                onSelectionChanged(selected.count)
            }
        }
    }

    private var available: [MCPServerDescriptor] {
        guard provider.configuration.isEnabled else { return [] }
        return provider.servers.filter(\.isGloballyEnabled)
    }

    private func update(_ next: Set<UUID>) {
        selected = next
        onSelectionChanged(next.count)
        Task { await provider.setSelection(next, chatID: chatID, temporary: temporary) }
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
