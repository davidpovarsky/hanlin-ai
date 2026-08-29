import SwiftUI

struct NativeAppsAddSheet: View {
    let modules: [NativeAppModule]
    let scriptingPlatform: HanlinScriptingPlatform
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Compiled Native Apps", systemImage: "shippingbox")
                        .font(.headline)
                    Text("Native Apps are compiled into Hanlin. Script packages are inspected without execution before installation is offered.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        ScriptingPackageImportView(platform: scriptingPlatform)
                    } label: {
                        Label("Import Script Package", systemImage: "doc.badge.plus")
                    }
                    .accessibilityIdentifier("hanlin-import-script-package")
                }

                Section("Bundled Apps") {
                    ForEach(modules, id: \.manifest.id) { module in
                        Label(module.manifest.title, systemImage: module.manifest.systemImage)
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
