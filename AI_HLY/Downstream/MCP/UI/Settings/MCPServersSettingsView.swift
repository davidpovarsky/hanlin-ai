import SwiftUI

struct MCPServersSettingsView: View {
    @State private var provider = MCPRuntimeProvider.shared

    var body: some View {
        List {
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
                                Text(MCPL10n.string("Installed")).font(.caption)
                                Text(server.isGloballyEnabled ? MCPL10n.string("Enabled in app") : MCPL10n.string("Disabled"))
                                    .font(.caption2)
                                Text(server.isEnabledForNewChats ? MCPL10n.string("Included by default in new chats") : MCPL10n.string("Not included by default"))
                                    .font(.caption2)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Section {
                NavigationLink(MCPL10n.string("Advanced & Diagnostics")) {
                    MCPDiagnosticsView()
                }
            }
            if case .failed = provider.persistentLoadState {
                Section {
                    Button(MCPL10n.string("Retry loading server registry")) {
                        Task { await provider.retryPersistentLoad() }
                    }
                }
            }
            if let error = provider.lastError { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle(MCPL10n.string("MCP Servers"))
        .task { await provider.loadIfNeeded(startHost: false) }
    }
}
