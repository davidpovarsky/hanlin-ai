import SwiftUI

struct MCPServersSettingsView: View {
    @State private var provider = MCPRuntimeProvider.shared

    var body: some View {
        List {
            Section(MCPL10n.string("Runtime")) {
                MCPRuntimeStatusView(snapshot: provider.runtimeSnapshot)
                HStack {
                    Button(MCPL10n.string("Restart workers")) { Task { await restartWorkers() } }
                    NavigationLink(MCPL10n.string("View runtime logs")) { MCPServerLogsView(server: nil) }
                }
            }
            Section {
                Toggle(MCPL10n.string("Enable MCP Servers"), isOn: Binding(
                    get: { provider.configuration.isEnabled },
                    set: { value in Task { await provider.setEnabled(value) } }
                ))
            }
            Section {
                NavigationLink {
                    MCPServerInstallView()
                } label: {
                    Label(MCPL10n.string("Add MCP Server"), systemImage: "plus.circle")
                }
            }
            Section(MCPL10n.string("Installed servers")) {
                if provider.servers.isEmpty {
                    ContentUnavailableView(
                        MCPL10n.string("No MCP servers installed"),
                        systemImage: "server.rack",
                        description: Text(MCPL10n.string("Install a trusted JavaScript MCP package to begin."))
                    )
                }
                ForEach(provider.servers) { server in
                    NavigationLink {
                        MCPServerDetailView(server: server)
                    } label: {
                        HStack {
                            Image(systemName: status(for: server).state == .running ? "server.rack" : "server.rack")
                            VStack(alignment: .leading) {
                                Text(server.displayName)
                                Text("\(server.packageName) @ \(server.resolvedVersion)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(statusTitle(status(for: server).state)).font(.caption)
                                Text(MCPL10n.format("%d tools", status(for: server).toolCount)).font(.caption2)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if let error = provider.lastError { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle(MCPL10n.string("MCP Servers"))
        .task { await provider.loadIfNeeded(startHost: true) }
    }

    private func status(for server: MCPServerDescriptor) -> MCPServerStatus {
        provider.statuses[server.id] ?? .init(id: server.id, state: .stopped, toolCount: server.cachedToolCount)
    }

    private func statusTitle(_ state: MCPServerRuntimeState) -> String {
        switch state {
        case .stopped: MCPL10n.string("Stopped")
        case .starting: MCPL10n.string("Starting")
        case .running: MCPL10n.string("Running")
        case .failed: MCPL10n.string("Failed")
        }
    }

    private func restartWorkers() async {
        for server in provider.servers where status(for: server).state == .running {
            await provider.restart(server)
        }
    }
}
