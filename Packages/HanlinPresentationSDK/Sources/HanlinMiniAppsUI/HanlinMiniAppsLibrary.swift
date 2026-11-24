import HanlinLocalization
#if canImport(SwiftUI) && canImport(UIKit)
import HanlinMiniAppCore
import HanlinPlatformContracts
import SwiftUI

@MainActor
public struct HanlinMiniAppsLibrary: View {
    private let services: HanlinMiniAppsServices
    private let transferView: () -> AnyView
    private let isTransferringProductData: () -> Bool
    @Environment(\.locale) private var locale
    @State private var items: [HanlinMiniAppCatalogItem] = []
    @State private var selection: HanlinAppID?
    @State private var search = ""
    @State private var loading = false
    @State private var catalogError: String?
    @State private var error: String?
    @State private var presentation: PresentedContent?
    @State private var showsTransfer = false

    private struct PresentedContent: Identifiable {
        nonisolated let id = UUID()
        let view: AnyView
        var ownsNavigation = false
    }

    private var filtered: [HanlinMiniAppCatalogItem] {
        items.filter {
            search.isEmpty || [$0.descriptor.name.resolved(locale: locale),
                               $0.descriptor.summary.resolved(locale: locale), $0.id.rawValue]
                .contains { $0.localizedStandardContains(search) }
        }.sorted { $0.descriptor.name.resolved(locale: locale)
            .localizedStandardCompare($1.descriptor.name.resolved(locale: locale)) == .orderedAscending }
    }

    /// Mount the original library with the host's existing services and transfer UI.
    /// The callbacks retain the host's transfer authority and live busy state.
    public init(services: HanlinMiniAppsServices,
                transferView: @escaping () -> AnyView,
                isTransferringProductData: @escaping () -> Bool) {
        self.services = services
        self.transferView = transferView
        self.isTransferringProductData = isTransferringProductData
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(filtered) { item in
                    NavigationLink(value: item.id) {
                        LabeledContent(item.descriptor.name.resolved(locale: locale)) {
                            Text(item.descriptor.summary.resolved(locale: locale))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("hanlin-miniapp-\(item.id.rawValue)")
                }
            }
            .navigationTitle(Text("MiniApps", bundle: HanlinLocalization.bundle))
            .searchable(text: $search, prompt: Text("Search apps", bundle: HanlinLocalization.bundle))
            .refreshable { await reload() }
            .toolbar {
                Button(hanlin: "Manage packages", systemImage: "shippingbox") {
                    do { presentation = PresentedContent(view: try services.packageManagement()) }
                    catch { self.error = error.localizedDescription }
                }
                .accessibilityIdentifier("hanlin-miniapps-management")
                Button(hanlin: "Transfer from Hanlin", systemImage: "arrow.down.doc") {
                    showsTransfer = true
                }
                .accessibilityIdentifier("hanlin-miniapps-transfer")
            }
            .overlay {
                if loading { ProgressView() }
                else if let catalogError {
                    ContentUnavailableView {
                        Label(hanlin: "MiniApps unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(catalogError)
                    } actions: {
                        Button(hanlin: "Retry") { Task { await reload() } }
                    }
                } else if items.isEmpty {
                    ContentUnavailableView(hanlin: "No installed apps", systemImage: "square.grid.2x2",
                                           description: Text("Import an app using package management.", bundle: HanlinLocalization.bundle))
                }
            }
        } detail: {
            if let item = items.first(where: { $0.id == selection }) {
                Form {
                    Section(item.descriptor.name.resolved(locale: locale)) {
                        Text(item.descriptor.description.resolved(locale: locale))
                        LabeledContent(hanlin: "Runtime", value: item.engine.displayName)
                        LabeledContent(hanlin: "App identity", value: item.id.rawValue)
                        Button(hanlin: "Open app", systemImage: "arrow.up.forward.app") {
                            Task {
                                do {
                                    presentation = PresentedContent(view: try await services.launch(item),
                                                                    ownsNavigation: true)
                                }
                                catch { self.error = error.localizedDescription }
                            }
                        }
                        .accessibilityIdentifier("hanlin-miniapps-open")
                    }
                }
            } else {
                ContentUnavailableView(hanlin: "Select an app", systemImage: "square.grid.2x2")
            }
        }
        .task { await reload() }
        .sheet(isPresented: $showsTransfer, onDismiss: { Task { await reload() } }) {
            NavigationStack {
                transferView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(hanlin: "Done") { showsTransfer = false }
                                .disabled(isTransferringProductData())
                        }
                    }
            }
        }
        .fullScreenCover(item: $presentation, onDismiss: {
            Task { await reload() }
        }) { destination in
            if destination.ownsNavigation {
                destination.view
            } else {
                NavigationStack {
                    destination.view.toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(hanlin: "Done") { presentation = nil }
                                .accessibilityIdentifier("hanlin-miniapps-management-close")
                        }
                    }
                }
            }
        }
        .alert(Text("MiniApps unavailable", bundle: HanlinLocalization.bundle), isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) { Button(hanlin: "OK") { error = nil } } message: { Text(error ?? "") }
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
#endif
