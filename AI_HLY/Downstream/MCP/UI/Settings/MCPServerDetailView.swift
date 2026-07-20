import SwiftUI

struct MCPServerDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var provider = MCPRuntimeProvider.shared
    @State private var draft: MCPServerDescriptor
    @State private var environment: [MCPEnvironmentDraft]
    @State private var replacingPackage = false

    init(server: MCPServerDescriptor) {
        _draft = State(initialValue: server)
        _environment = State(initialValue: server.environment.map {
            MCPEnvironmentDraft(name: $0.name, value: $0.value ?? "", isSecret: $0.isSecret)
        })
    }

    var body: some View {
        Form {
            Section(MCPL10n.string("Server")) {
                TextField(MCPL10n.string("Display name"), text: $draft.displayName)
                LabeledContent(MCPL10n.string("Package"), value: draft.packageName)
                LabeledContent(MCPL10n.string("Version"), value: draft.resolvedVersion)
                if let options = draft.entryPointOptions, options.count > 1 {
                    Picker(MCPL10n.string("Bin"), selection: $draft.entryPoint) {
                        ForEach(options) { option in
                            Text(option.binName ?? option.entryPoint).tag(option.entryPoint)
                        }
                    }
                    .onChange(of: draft.entryPoint) { _, entryPoint in
                        draft.binName = options.first(where: { $0.entryPoint == entryPoint })?.binName
                    }
                }
                TextField(MCPL10n.string("Entry point"), text: $draft.entryPoint)
                TextField(
                    MCPL10n.string("Arguments"),
                    text: Binding(
                        get: { draft.arguments.joined(separator: " ") },
                        set: { draft.arguments = $0.split { $0.isWhitespace }.map(String.init) }
                    )
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Toggle(MCPL10n.string("Enabled globally"), isOn: $draft.isGloballyEnabled)
                Toggle(MCPL10n.string("Enabled for new chats"), isOn: $draft.isEnabledForNewChats)
                Toggle(MCPL10n.string("Auto-start"), isOn: $draft.autoStart)
                NavigationLink(MCPL10n.string("Environment")) {
                    MCPServerEnvironmentView(variables: $environment)
                }
            }
            Section(MCPL10n.string("Runtime")) {
                HStack {
                    Button(MCPL10n.string("Start")) { Task { await provider.start(draft) } }
                    Button(MCPL10n.string("Stop")) { Task { await provider.stop(draft) } }
                    Button(MCPL10n.string("Restart")) { Task { await provider.restart(draft) } }
                }
                Button(MCPL10n.string("Refresh tools")) { Task { await provider.refreshTools(draft) } }
                NavigationLink(MCPL10n.string("View tools")) { MCPServerToolsView(server: draft) }
                NavigationLink(MCPL10n.string("View logs")) { MCPServerLogsView(server: draft) }
            }
            Section(MCPL10n.string("Package management")) {
                Button(MCPL10n.string("Update")) { replacePackage(latestCompatible: true) }
                    .disabled(replacingPackage)
                Button(MCPL10n.string("Reinstall")) { replacePackage(latestCompatible: false) }
                    .disabled(replacingPackage)
                if replacingPackage { MCPInstallProgressView(state: provider.installState) }
                if let error = provider.lastError { Text(error).foregroundStyle(.red) }
            }
            Section(MCPL10n.string("Compatibility")) {
                ForEach(draft.compatibility.findings) { finding in
                    Label(finding.message, systemImage: finding.severity == .unsupported ? "xmark.octagon" : "exclamationmark.triangle")
                }
                LabeledContent(MCPL10n.string("Runtime probe"), value: draft.compatibility.runtimeProbePassed ? MCPL10n.string("Passed") : MCPL10n.string("Pending"))
            }
            Section {
                Button(MCPL10n.string("Uninstall"), role: .destructive) { Task { await provider.uninstall(draft) } }
            }
        }
        .navigationTitle(draft.displayName)
        .toolbar {
            Button(MCPL10n.string("Save")) {
                Task {
                    await provider.update(draft)
                    await provider.updateEnvironment(environment, for: draft)
                }
            }
        }
    }

    private func replacePackage(latestCompatible: Bool) {
        replacingPackage = true
        Task {
            await provider.replacePackage(draft, latestCompatible: latestCompatible)
            replacingPackage = false
            if provider.lastError == nil { dismiss() }
        }
    }
}
