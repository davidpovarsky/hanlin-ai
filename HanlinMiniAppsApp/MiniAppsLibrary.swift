import HanlinMiniAppCore
import HanlinPlatformContracts
import SwiftUI

struct MiniAppsLibrary: View {
    let services: MiniAppsServices
    @Environment(\.locale) private var locale
    @State private var items: [HanlinMiniAppCatalogItem] = []
    @State private var selection: HanlinAppID?
    @State private var search = ""
    @State private var loading = false
    @State private var catalogError: String?
    @State private var error: String?
    @State private var presentation: PresentedContent?

    private struct PresentedContent: Identifiable {
        let id = UUID()
        let view: AnyView
    }

    private var filtered: [HanlinMiniAppCatalogItem] {
        items.filter {
            search.isEmpty || [$0.descriptor.name.resolved(locale: locale),
                               $0.descriptor.summary.resolved(locale: locale), $0.id.rawValue]
                .contains { $0.localizedStandardContains(search) }
        }.sorted { $0.descriptor.name.resolved(locale: locale)
            .localizedStandardCompare($1.descriptor.name.resolved(locale: locale)) == .orderedAscending }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(filtered) { item in
                    NavigationLink(value: item.id) {
                        LabeledContent(item.descriptor.name.resolved(locale: locale)) {
                            Text(item.descriptor.summary.resolved(locale: locale))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("MiniApps")
            .searchable(text: $search, prompt: "Search apps")
            .refreshable { await reload() }
            .toolbar {
                Button("Manage packages", systemImage: "shippingbox") {
                    do { presentation = PresentedContent(view: try services.packageManagement()) }
                    catch { self.error = error.localizedDescription }
                }
            }
            .overlay {
                if loading { ProgressView() }
                else if let catalogError {
                    ContentUnavailableView {
                        Label("MiniApps unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(catalogError)
                    } actions: {
                        Button("Retry") { Task { await reload() } }
                    }
                } else if items.isEmpty {
                    ContentUnavailableView("No installed apps", systemImage: "square.grid.2x2",
                                           description: Text("Import an app using package management."))
                }
            }
        } detail: {
            if let item = items.first(where: { $0.id == selection }) {
                Form {
                    Section(item.descriptor.name.resolved(locale: locale)) {
                        Text(item.descriptor.description.resolved(locale: locale))
                        LabeledContent("Runtime", value: item.engine.displayName)
                        LabeledContent("App identity", value: item.id.rawValue)
                        Button("Open app", systemImage: "arrow.up.forward.app") {
                            Task {
                                do { presentation = PresentedContent(view: try await services.launch(item)) }
                                catch { self.error = error.localizedDescription }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("Select an app", systemImage: "square.grid.2x2")
            }
        }
        .task { await reload() }
        .fullScreenCover(item: $presentation) { destination in
            NavigationStack {
                destination.view.toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { presentation = nil }
                    }
                }
            }
        }
        .alert("MiniApps unavailable", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            items = try await services.catalog()
            catalogError = nil
        } catch {
            catalogError = error.localizedDescription
        }
    }
}
