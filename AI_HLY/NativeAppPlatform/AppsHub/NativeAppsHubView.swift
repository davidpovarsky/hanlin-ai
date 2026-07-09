import SwiftUI
import SwiftData

struct NativeAppsHubView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    private var context: NativeAppContext {
        NativeAppContext(
            localeIdentifier: Locale.current.identifier,
            modelContext: modelContext,
            openURL: { url in openURL(url) }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedCategories, id: \.0) { category, modules in
                    Section(category.title) {
                        ForEach(modules, id: \.manifest.id) { module in
                            NavigationLink {
                                NativeAppDetailView(module: module, context: context)
                            } label: {
                                NativeAppCardView(manifest: module.manifest)
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Apps"))
            .overlay {
                if NativeAppRegistry.shared.allModules().isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "No Apps"))
                            .font(.headline)
                        Text("Native app modules will appear here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
        }
    }

    private var groupedCategories: [(NativeAppCategory, [NativeAppModule])] {
        let modules = NativeAppRegistry.shared.allModules()
        let grouped = Dictionary(grouping: modules, by: { $0.manifest.category })
        return grouped.keys.sorted { $0.title < $1.title }.map { key in
            (key, grouped[key] ?? [])
        }
    }
}
