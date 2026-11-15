import SwiftUI

@main
struct HanlinMiniAppsApplication: App {
    @State private var services: MiniAppsServices?
    @State private var startupError: String?
    @State private var showsImport = false
    @State private var foreground = MiniAppsForegroundBridge()

    var body: some Scene {
        WindowGroup {
            Group {
                if let services {
                    MiniAppsLibrary(services: services)
                } else if let startupError {
                    ContentUnavailableView("MiniApps unavailable", systemImage: "exclamationmark.triangle",
                                           description: Text(startupError))
                } else {
                    ProgressView().task {
                        HanlinNativeScriptProductionBootstrap.prepareEmbeddedProviders()
                        do { services = try await MiniAppsComposition.makeServices() }
                        catch { startupError = error.localizedDescription }
                    }
                }
            }
            .onOpenURL { url in
                Task {
                    if url.isFileURL {
                        await HanlinScriptingPlatform.shared.importPackage(from: url)
                        showsImport = true
                    } else {
                        HanlinNativeScriptProductionBootstrap.prepareEmbeddedProviders()
                        await foreground.open(url)
                    }
                }
            }
            .sheet(isPresented: $showsImport) {
                NavigationStack { ScriptingPackageImportView(platform: .shared) }
            }
            .fullScreenCover(item: $foreground.presentation) { destination in
                NavigationStack {
                    destination.view.toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { Task { await foreground.cancelAndClose() } }
                                .disabled(foreground.returning)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Return to Hanlin") { Task { await foreground.returnToOrigin() } }
                                .disabled(foreground.returning)
                                .accessibilityIdentifier("miniapps.return-to-origin")
                        }
                    }
                }
                .interactiveDismissDisabled()
            }
            .alert("Hanlin request unavailable", isPresented: Binding(
                get: { foreground.error != nil }, set: { if !$0 { foreground.error = nil } }
            )) { Button("OK") { foreground.error = nil } } message: { Text(foreground.error ?? "") }
        }
    }
}
