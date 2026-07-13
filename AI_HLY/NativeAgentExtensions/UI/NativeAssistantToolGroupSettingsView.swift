import SwiftUI

@MainActor
struct NativeAssistantToolGroupSettingsView: View {
    let groupID: String

    @State private var isGroupEnabled = true
    @State private var individualEnabled: [String: Bool] = [:]

    private var group: NativeAssistantToolGroup? {
        NativeToolCatalog.shared.settingsGroups().first { $0.id == groupID }
    }

    var body: some View {
        Group {
            if let group {
                Form {
                    Section {
                        VStack(alignment: .center, spacing: 10) {
                            Image(systemName: group.systemImage)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.hlBluefont)
                                .padding(.top)

                            Text(group.title)
                                .font(.title2.bold())

                            Text(group.summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.bottom)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }

                    Section {
                        Toggle(
                            String(format: String(localized: "Enable %@"), group.title),
                            isOn: groupEnabledBinding(for: group)
                        )
                    } footer: {
                        Text(
                            isGroupEnabled
                                ? String(localized: "This app's enabled functions are available to the model")
                                : String(localized: "This app is disabled; function preferences are preserved")
                        )
                    }

                    Section(String(localized: "Functions")) {
                        ForEach(group.toolEntries) { entry in
                            Toggle(isOn: toolEnabledBinding(for: entry)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title)
                                    Text(entry.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if entry.isSensitive {
                                        Label(String(localized: "Sensitive"), systemImage: "hand.raised.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                            .disabled(!isGroupEnabled)
                            .accessibilityHint(entry.summary)
                        }
                    }
                }
                .navigationTitle(group.title)
                .onAppear {
                    loadState(for: group)
                    NativeToolTraceLogger.shared.log(
                        "native_assistant_tool_group_settings_opened",
                        [
                            "groupID": group.id,
                            "toolNames": group.toolEntries.map(\.name),
                            "groupEnabled": isGroupEnabled,
                            "individualStates": group.toolEntries.map {
                                "\($0.name):\(individualEnabled[$0.name] ?? $0.isEnabledByDefault)"
                            },
                            "effectiveEnabledToolNames": group.toolEntries.filter {
                                NativeToolCatalog.shared.isEffectivelyEnabled($0)
                            }.map(\.name)
                        ]
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
                        "native_assistant_tool_group_settings_missing",
                        ["groupID": groupID]
                    )
                }
            }
        }
    }

    private func loadState(for group: NativeAssistantToolGroup) {
        isGroupEnabled = NativeToolCatalog.shared.isGroupEnabled(group)
        individualEnabled = Dictionary(uniqueKeysWithValues: group.toolEntries.map {
            ($0.name, NativeToolCatalog.shared.isEnabled($0))
        })
    }

    private func groupEnabledBinding(for group: NativeAssistantToolGroup) -> Binding<Bool> {
        Binding(
            get: { isGroupEnabled },
            set: { enabled in
                isGroupEnabled = enabled
                NativeToolCatalog.shared.setGroupEnabled(enabled, for: group)
            }
        )
    }

    private func toolEnabledBinding(for entry: NativeToolCatalogEntry) -> Binding<Bool> {
        Binding(
            get: { individualEnabled[entry.name] ?? entry.isEnabledByDefault },
            set: { enabled in
                individualEnabled[entry.name] = enabled
                NativeToolCatalog.shared.setEnabled(enabled, for: entry)
            }
        )
    }
}
