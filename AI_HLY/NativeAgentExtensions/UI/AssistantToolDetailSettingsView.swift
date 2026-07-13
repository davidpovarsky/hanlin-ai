import SwiftUI

@MainActor
struct NativeAssistantToolSettingsRow: View {
    let entry: NativeToolCatalogEntry

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                if let sourceAppTitle = entry.sourceAppTitle {
                    Text(sourceAppTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: entry.systemImage)
        }
        .accessibilityHint(entry.summary)
    }
}

@MainActor
struct AssistantToolDetailSettingsView: View {
    let toolName: String

    @State private var isEnabled = false

    private var entry: NativeToolCatalogEntry? {
        NativeToolCatalog.shared.entry(named: toolName)
    }

    var body: some View {
        Group {
            if let entry {
                Form {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title)
                                    .font(.headline)
                                Text(entry.summary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: entry.systemImage)
                                .font(.title2)
                                .foregroundStyle(.tint)
                        }
                    }

                    Section {
                        Toggle(String(localized: "Enabled"), isOn: enabledBinding(for: entry))
                    } footer: {
                        Text(
                            isEnabled
                                ? String(localized: "This tool is shared with the model when enabled")
                                : String(localized: "This tool is disabled and is neither shared with the model nor available for execution")
                        )
                    }

                    Section(String(localized: "Details")) {
                        detailRow(String(localized: "Tool Name"), value: entry.name)
                        detailRow(String(localized: "Source App"), value: entry.sourceAppTitle ?? String(localized: "Hanlin"))
                        if let sourceAppID = entry.sourceAppID {
                            detailRow(String(localized: "Source App ID"), value: sourceAppID)
                        }
                        detailRow(
                            String(localized: "Sensitive"),
                            value: entry.isSensitive ? String(localized: "Yes") : String(localized: "No")
                        )
                    }

                    if !entry.categories.isEmpty {
                        valuesSection(String(localized: "Categories"), values: entry.categories)
                    }

                    if !entry.keywords.isEmpty {
                        valuesSection(String(localized: "Keywords"), values: entry.keywords)
                    }

                    if !entry.examples.isEmpty {
                        valuesSection(String(localized: "Examples"), values: entry.examples)
                    }
                }
                .navigationTitle(entry.title)
                .onAppear {
                    isEnabled = NativeToolCatalog.shared.isEnabled(entry)
                    NativeToolTraceLogger.shared.log(
                        "assistant_tool_settings_opened",
                        ["toolName": toolName, "sourceAppID": entry.sourceAppID as Any]
                    )
                }
            } else {
                ContentUnavailableView(
                    String(localized: "Assistant Tool Unavailable"),
                    systemImage: "wrench.and.screwdriver",
                    description: Text(String(localized: "The requested assistant tool could not be found."))
                )
                .navigationTitle(String(localized: "Assistant Tool"))
                .onAppear {
                    NativeToolTraceLogger.shared.log(
                        "assistant_tool_settings_missing",
                        ["toolName": toolName]
                    )
                }
            }
        }
    }

    private func enabledBinding(for entry: NativeToolCatalogEntry) -> Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { enabled in
                isEnabled = enabled
                NativeToolCatalog.shared.setEnabled(enabled, for: entry)
            }
        )
    }

    private func detailRow(_ title: String, value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func valuesSection(_ title: String, values: [String]) -> some View {
        Section(title) {
            ForEach(values, id: \.self) { value in
                Text(value)
                    .textSelection(.enabled)
            }
        }
    }
}
