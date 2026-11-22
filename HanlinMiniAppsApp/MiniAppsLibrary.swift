import SwiftUI

/// Presents companion-owned launches separately from requests arriving from Hanlin AI.
struct MiniAppsLibrary: View {
    let provider: HanlinMiniAppsProvider
    @State private var presentation: PresentedApp?
    @State private var isLaunching = false
    @State private var showsTransfer = false
    @State private var catalogReady = false
    @State private var catalogError: String?
    @State private var launchError: String?

    private struct PresentedApp: Identifiable {
        let id = UUID()
        let view: AnyView
    }

    var body: some View {
        Group {
            if catalogReady {
                catalog
            } else if let catalogError {
                ContentUnavailableView {
                    Label("MiniApps unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(catalogError)
                } actions: {
                    Button("Retry") { Task { await refreshCatalog() } }
                }
            } else {
                ProgressView("Loading apps…")
            }
        }
        .task {
            if !catalogReady { await refreshCatalog() }
        }
    }

    private var catalog: some View {
        NativeAppsCatalogView(
            refreshCatalog: refreshCatalog,
            onLaunch: { item in open { try await provider.launch(item) } },
            onLaunchPackage: { packageID in open { try await provider.launch(packageID: packageID) } },
            presentsSourceReader: true
        ) {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Transfer from Hanlin", systemImage: "arrow.down.doc") { showsTransfer = true }
                    .accessibilityIdentifier("hanlin-miniapps-transfer")
            }
        }
        .refreshable { await refreshCatalog() }
        .sheet(isPresented: $showsTransfer, onDismiss: {
            Task { await refreshCatalog() }
        }) {
            NavigationStack {
                HanlinMiniAppTransferView(mode: .receive)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsTransfer = false }
                                .disabled(provider.platform.isTransferringProductData)
                        }
                    }
            }
        }
        .fullScreenCover(item: $presentation, onDismiss: {
            Task { await refreshCatalog() }
        }) { app in
            app.view
        }
        .alert("MiniApps unavailable", isPresented: Binding(
            get: { launchError != nil },
            set: { if !$0 { launchError = nil } }
        )) {
            Button("OK") { launchError = nil }
        } message: {
            Text(launchError ?? "")
        }
    }

    private func open(_ launch: @escaping @MainActor () async throws -> AnyView) {
        guard !isLaunching, presentation == nil else { return }
        isLaunching = true
        Task {
            defer { isLaunching = false }
            do {
                presentation = PresentedApp(view: try await launch())
            } catch {
                launchError = error.localizedDescription
            }
        }
    }

    private func refreshCatalog() async {
        do {
            try await provider.refreshCatalog()
            catalogError = nil
            // Display the library after the canonical catalog is available to Hanlin AI.
            catalogReady = true
        } catch {
            catalogError = error.localizedDescription
        }
    }
}
