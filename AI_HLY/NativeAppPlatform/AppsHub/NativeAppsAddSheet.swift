import SwiftUI

struct NativeAppsAddSheet: View {
    let modules: [NativeAppModule]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Compiled Native Apps", systemImage: "shippingbox")
                        .font(.headline)
                    Text("Native Apps are compiled into Hanlin. The plus button is the future entry point for adding approved packages; this test build lists every package already bundled in the app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
