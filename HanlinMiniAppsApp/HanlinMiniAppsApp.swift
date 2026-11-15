import SwiftUI

@main
struct HanlinMiniAppsApplication: App {
    @State private var services: MiniAppsServices?
    @State private var startupError: String?
    @State private var showsImport = false

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
                guard url.isFileURL else { return }
                Task {
                    await HanlinScriptingPlatform.shared.importPackage(from: url)
                    showsImport = true
                }
            }
            .sheet(isPresented: $showsImport) {
                NavigationStack { ScriptingPackageImportView(platform: .shared) }
            }
        }
    }
}
