import HanlinMiniAppCore
import HanlinPlatformContracts
import SwiftUI

struct NativeAppsAddSheet: View {
    let items: [HanlinMiniAppCatalogItem]
    let host: HanlinMiniAppHost
    let scriptingPlatform: HanlinScriptingPlatform
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Swift apps are compiled into Hanlin. NativeScript packages are dynamically importable.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        ScriptingPackageImportView(platform: scriptingPlatform)
                    } label: {
                        Label("Import NativeScript Package", systemImage: "doc.badge.plus")
                    }
                    .accessibilityIdentifier("hanlin-import-script-package")
                }

                let hidden = items.filter { host.isHidden($0.id) }
                if !hidden.isEmpty {
                    Section("Hidden Apps") {
                        ForEach(hidden) { item in
                            Button {
                                host.setHidden(false, appID: item.id)
                            } label: {
                                Label(
                                    item.descriptor.name.preferredValue(forLocale: Locale.current.identifier),
                                    systemImage: "eye"
                                )
                            }
                        }
                    }
                }

                Section("Bundled Swift Apps") {
                    ForEach(items.filter({ $0.engine == .swift })) { item in
                        Label(
                            item.descriptor.name.preferredValue(forLocale: Locale.current.identifier),
                            systemImage: "swift"
                        )
                    }
                }
            }
            .navigationTitle("Add Apps")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
