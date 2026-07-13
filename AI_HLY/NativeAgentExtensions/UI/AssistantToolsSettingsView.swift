import SwiftUI

@MainActor
struct AssistantToolsSettingsView: View {
    @State private var enabledStates: [String: Bool] = [:]

    private var entries: [NativeToolCatalogEntry] {
        NativeToolCatalog.shared.allEntries()
    }

    var body: some View {
        List {
            Section {
                ForEach(entries) { entry in
                    Toggle(isOn: binding(for: entry)) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: entry.systemImage)
                                .font(.title3)
                                .foregroundStyle(.tint)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title)
                                    .font(.headline)
                                Text(entry.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Label(entry.sourceAppTitle ?? "Hanlin", systemImage: "app")
                                    if let category = entry.categories.first {
                                        Label(category, systemImage: "tag")
                                    }
                                    if entry.isSensitive {
                                        Label("Sensitive", systemImage: "hand.raised.fill")
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityHint(entry.summary)
                }
            } footer: {
                Text("Disabled tools are neither shared with the model nor available for execution.")
            }
        }
        .navigationTitle("Assistant Tools")
        .onAppear {
            enabledStates = Dictionary(uniqueKeysWithValues: entries.map {
                ($0.name, NativeToolCatalog.shared.isEnabled($0))
            })
        }
    }

    private func binding(for entry: NativeToolCatalogEntry) -> Binding<Bool> {
        Binding(
            get: { enabledStates[entry.name] ?? NativeToolCatalog.shared.isEnabled(entry) },
            set: { enabled in
                enabledStates[entry.name] = enabled
                NativeToolCatalog.shared.setEnabled(enabled, for: entry)
            }
        )
    }
}
