import SwiftUI

struct ShellCapabilitiesView: View {
    @State private var discovered: Set<String> = []
    @State private var error: String?
    @State private var shellTool: NativeToolCatalogEntry?

    var body: some View {
        List {
            Section(RuntimeL10n.string("ios_system runtime")) {
                LabeledContent(RuntimeL10n.string("Version"), value: "3.0.5")
                LabeledContent(RuntimeL10n.string("Source"), value: "holzschu/ios_system")
                Text(RuntimeL10n.string("Commands run in-process inside an app-scoped miniRoot. This is not Linux and there is no interactive terminal."))
                    .font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }

            if let shellTool {
                Section(RuntimeL10n.string("Assistant access")) {
                    Toggle(RuntimeL10n.string("Enable sensitive shell tool"), isOn: Binding(
                        get: { NativeToolCatalog.shared.isEnabled(shellTool) },
                        set: { NativeToolCatalog.shared.setEnabled($0, for: shellTool) }
                    ))
                    Text(RuntimeL10n.string("Disabled by default. Only one structurally parsed command from the verified catalog is accepted; pipes, redirection, substitution and chaining are rejected."))
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Section(RuntimeL10n.string("Verified commands")) {
                ForEach(ShellRuntimeService.capabilities) { capability in
                    Label {
                        VStack(alignment: .leading) {
                            HStack { Text(capability.name).font(.system(.body, design: .monospaced)); Spacer(); Text(RuntimeL10n.string(discovered.contains(capability.name) ? "Linked" : "Unavailable")) .font(.caption).foregroundStyle(discovered.contains(capability.name) ? .green : .red) }
                            Text(RuntimeL10n.string(capability.summary)).font(.caption).foregroundStyle(.secondary)
                            if capability.requiresNetwork { Text(RuntimeL10n.string("Requires explicit HTTPS network permission")) .font(.caption2).foregroundStyle(.orange) }
                        }
                    } icon: { Image(systemName: capability.requiresNetwork ? "network" : "doc") }
                }
            }
        }
        .navigationTitle(RuntimeL10n.string("Shell Capabilities"))
        .task {
            shellTool = NativeToolCatalog.shared.entry(named: "execute_shell_command")
            do {
                _ = try await AppRuntimeCore.shared.shell.healthCheck()
                discovered = Set(ShellRuntimeService.capabilities.map(\.name))
            } catch { self.error = error.localizedDescription }
        }
    }
}
