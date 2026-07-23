import SwiftUI

struct MCPDiagnosticsView: View {
    @State private var provider = MCPRuntimeProvider.shared

    var body: some View {
        List {
            Section(MCPL10n.string("Node host status")) {
                MCPRuntimeStatusView(snapshot: provider.runtimeSnapshot)
                NavigationLink(MCPL10n.string("View runtime logs")) {
                    MCPServerLogsView(server: nil)
                }
            }
            Section(MCPL10n.string("Servers")) {
                ForEach(provider.servers) { server in
                    NavigationLink(server.displayName) {
                        MCPServerDiagnosticsView(server: server)
                    }
                }
            }
            Section {
                Button(MCPL10n.string("Restart workers")) {
                    Task {
                        for server in provider.servers
                        where provider.statuses[server.id]?.state == .running {
                            await provider.restart(server)
                        }
                    }
                }
            }
            if case .failed = provider.persistentLoadState {
                Section {
                    Button(MCPL10n.string("Retry loading server registry")) {
                        Task { await provider.retryPersistentLoad() }
                    }
                }
            }
        }
        .navigationTitle(MCPL10n.string("Advanced & Diagnostics"))
        .task { await provider.loadIfNeeded(startHost: false) }
    }
}

struct MCPServerDiagnosticsView: View {
    @State private var provider = MCPRuntimeProvider.shared
    @State private var preloadOnLaunch: Bool

    let server: MCPServerDescriptor

    init(server: MCPServerDescriptor) {
        self.server = server
        _preloadOnLaunch = State(initialValue: server.preloadOnLaunch)
    }

    var body: some View {
        Form {
            Section(MCPL10n.string("Runtime phase")) {
                LabeledContent(MCPL10n.string("Runtime phase"), value: phaseTitle)
                LabeledContent(MCPL10n.string("Generation"), value: "\(status.generation)")
                if let message = status.message {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Button(MCPL10n.string("Start")) { Task { await provider.start(server) } }
                        .disabled(!canStart)
                    Button(MCPL10n.string("Stop")) { Task { await provider.stop(server) } }
                        .disabled(!canStop)
                    Button(MCPL10n.string("Restart")) { Task { await provider.restart(server) } }
                        .disabled(!canRestart)
                }
                Button(MCPL10n.string("Refresh tools")) {
                    Task { await provider.refreshTools(server) }
                }
                .disabled(status.state != .running)
                NavigationLink(MCPL10n.string("View tools")) {
                    MCPServerToolsView(server: server)
                }
                NavigationLink(MCPL10n.string("View logs")) {
                    MCPServerLogsView(server: server)
                }
            }
            Section {
                Toggle(MCPL10n.string("Preload when the app opens"), isOn: $preloadOnLaunch)
                    .onChange(of: preloadOnLaunch) { _, value in
                        var updated = server
                        updated.preloadOnLaunch = value
                        Task { await provider.update(updated) }
                    }
                Text(MCPL10n.string("Preloading shortens the first-use wait. It is not required to use the server in a chat."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(server.displayName)
    }

    private var status: MCPServerStatus {
        provider.statuses[server.id] ?? MCPServerStatus(
            id: server.id,
            state: .stopped,
            toolCount: 0
        )
    }

    private var canStart: Bool {
        status.state == .stopped || status.state == .failed
    }

    private var canStop: Bool {
        status.state == .running || status.state == .failed
    }

    private var canRestart: Bool {
        status.state == .running || status.state == .failed
    }

    private var phaseTitle: String {
        switch status.state {
        case .stopped: MCPL10n.string("Stopped")
        case .starting: MCPL10n.string("Starting")
        case .running: MCPL10n.string("Running")
        case .stopping: MCPL10n.string("Stopping")
        case .failed: MCPL10n.string("Failed")
        }
    }
}
