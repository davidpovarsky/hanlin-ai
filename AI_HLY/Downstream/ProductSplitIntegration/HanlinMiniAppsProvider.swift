import HanlinMiniAppCore
import HanlinPlatformContracts
import HanlinProductSplit
import HanlinScriptStore
import SwiftUI

/// Composition around the same Host and package implementation used by AI.
/// No authority, registry, runtime implementation or store is reimplemented.
@MainActor
final class HanlinMiniAppsProvider {
    private let host: HanlinMiniAppHost
    let platform: HanlinScriptingPlatform
    private var launching = false

    enum Failure: LocalizedError {
        case unavailable(String), staleSelection, launchInProgress, launchDidNotProduceApplication

        var errorDescription: String? {
            switch self {
            case .unavailable(let message): message
            case .staleSelection: String(localized: "This app changed. Refresh the library and try again.")
            case .launchInProgress: String(localized: "Another app is still opening.")
            case .launchDidNotProduceApplication: String(localized: "The app could not be opened.")
            }
        }
    }

    init(host: HanlinMiniAppHost = .shared, platform: HanlinScriptingPlatform = .shared) {
        self.host = host
        self.platform = platform
    }

    func catalog() async throws -> [HanlinMiniAppCatalogItem] {
        await platform.restore()
        try requirePackageServices()
        await host.refresh(installedPackages: platform.installedPackages)
        if let error = host.lastError { throw Failure.unavailable(error) }
        if Bundle.main.bundleIdentifier == SplitAppStorageLayout.miniAppsBundleIdentifier {
            try? HanlinSplitLiveTarget.exportCatalog()
        }
        return host.visibleItems
    }

    func launch(_ selected: HanlinMiniAppCatalogItem, includesDismissControl: Bool = true) async throws -> AnyView {
        guard !launching else { throw Failure.launchInProgress }
        launching = true
        defer { launching = false }
        // Refresh canonical descriptors/authorization before using a retained row.
        let current = try await catalog()
        guard let item = current.first(where: { $0 == selected }) else { throw Failure.staleSelection }
        switch item.engine {
        case .swift:
            let view = try host.swiftDestination(for: item).view
            return AnyView(view.environment(\.hanlinMiniAppShowsDismissControl, includesDismissControl))
        case .nativeScript, .expo, .scriptingJSC:
            guard let package = platform.installedPackages.first(where: {
                $0.appID == item.id || $0.record.packageID.rawValue == item.id.rawValue
            }), package.enabled else { throw Failure.staleSelection }
            switch item.engine {
            case .nativeScript: try await host.launchNativeScript(item, platform: platform)
            case .expo: try await host.launchExpo(item, platform: platform)
            case .scriptingJSC: try await host.launchScriptingJSC(item, platform: platform)
            case .swift: preconditionFailure("Swift destination handled above")
            }
            if case .failed(let message) = platform.activity { throw Failure.unavailable(message) }
            guard platform.activeApplicationID == package.record.installedPackageID else {
                throw Failure.launchDidNotProduceApplication
            }
            let producedApplication = switch item.engine {
            case .nativeScript: platform.activeNativeScriptController != nil
            case .expo: platform.activeExpoController != nil
            case .scriptingJSC: platform.activeApplicationModel != nil
            case .swift: false
            }
            guard producedApplication else { throw Failure.launchDidNotProduceApplication }
            return AnyView(ScriptingApplicationContainerView(platform: platform))
        }
    }

    func launch(packageID: HanlinInstalledPackageID) async throws -> AnyView {
        guard !launching else { throw Failure.launchInProgress }
        launching = true
        defer { launching = false }

        await platform.restore()
        try requirePackageServices()
        await platform.launch(packageID)
        if case .failed(let message) = platform.activity { throw Failure.unavailable(message) }
        guard platform.activeApplicationID == packageID,
              platform.activeApplicationModel != nil || platform.activeNativeScriptController != nil
                || platform.activeExpoController != nil else {
            throw Failure.launchDidNotProduceApplication
        }
        return AnyView(ScriptingApplicationContainerView(platform: platform))
    }

    private func requirePackageServices() throws {
        if let error = platform.bootstrapError { throw Failure.unavailable(error) }
    }
}
