import SwiftUI

struct ShellCapabilitiesView: View {
    @State private var discovered: Set<String> = []
    @State private var error: String?

    var body: some View {
        List {
            Section(RuntimeL10n.string("ios_system runtime")) {
                LabeledContent(RuntimeL10n.string("Version"), value: "3.0.5")
                LabeledContent(RuntimeL10n.string("Source"), value: "holzschu/ios_system")
                Text(RuntimeL10n.string("Commands run in-process inside an app-scoped miniRoot. This is not Linux and there is no interactive terminal."))
                    .font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }

            Section(RuntimeL10n.string("Verified commands")) {
                ForEach(ShellRuntimeService.capabilities) { capability in
                    Label {
                        VStack(alignment: .leading) {
                            HStack { Text(capability.name).font(.system(.body, design: .monospaced)); Spacer(); Text(RuntimeL10n.string(discovered.contains(capability.name) ? "Linked" : "Unavailable")) .font(.caption).foregroundStyle(discovered.contains(capability.name) ? .green : .red) }
                            Text(RuntimeL10n.string(capability.summary)).font(.caption).foregroundStyle(.secondary)
                            if capability.requiresNetwork { Text(RuntimeL10n.string("Uses HTTPS network access")) .font(.caption2).foregroundStyle(.orange) }
                        }
                    } icon: { Image(systemName: capability.requiresNetwork ? "network" : "doc") }
                }
            }
        }
        .navigationTitle(RuntimeL10n.string("Shell Capabilities"))
        .task {
            do {
                _ = try await AppRuntimeCore.shared.shell.healthCheck()
                discovered = Set(ShellRuntimeService.capabilities.map(\.name))
            } catch { self.error = error.localizedDescription }
        }
    }
}
