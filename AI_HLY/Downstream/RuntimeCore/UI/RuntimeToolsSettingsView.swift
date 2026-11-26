import SwiftUI

// The full application keeps its original native tool catalogue. Component
// hosts supply their actual action catalogue to the same runtime screen.
extension RuntimeCenterView where ToolSettings == RuntimeToolsSettingsView {
    init() { self.init { RuntimeToolsSettingsView() } }
}

extension RuntimePackagesView where ToolSettings == RuntimeToolsSettingsView {
    init() { self.init { RuntimeToolsSettingsView() } }
}

struct RuntimeToolsSettingsView: View {
    @State private var entries: [NativeToolCatalogEntry] = NativeToolCatalog.shared.allEntries().filter {
        ["execute_local_python_code", "execute_javascript_code", "execute_typescript_code", "execute_shell_command"].contains($0.name)
    }

    var body: some View {
        ForEach(entries) { entry in
            Toggle(isOn: Binding(
                get: { NativeToolCatalog.shared.isEnabled(entry) },
                set: { NativeToolCatalog.shared.setEnabled($0, for: entry) }
            )) {
                Label {
                    VStack(alignment: .leading) {
                        Text(entry.title)
                        Text(entry.summary).font(HanlinTypography.caption).foregroundStyle(.secondary)
                        if entry.isSensitive { Text(RuntimeL10n.string("Sensitive capability — review every command")) .font(HanlinTypography.caption2).foregroundStyle(.orange) }
                    }
                } icon: { Image(systemName: entry.systemImage) }
            }
            .accessibilityIdentifier("hanlin-tool-permission-\(entry.name)")
        }
        .task {
            let names = Set(["execute_local_python_code", "execute_javascript_code", "execute_typescript_code", "execute_shell_command"])
            entries = NativeToolCatalog.shared.allEntries().filter { names.contains($0.name) }
        }
    }
}

