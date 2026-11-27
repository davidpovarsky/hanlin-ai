import Foundation
import OSLog
import HanlinLocalization
import HanlinMiniAppCore
import HanlinMiniAppsUI
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

    #if DEBUG || HANLIN_TESTING
    private static let catalogLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.hanlin", category: "MiniAppsCatalog")
    #endif

    enum Failure: LocalizedError {
        case unavailable(String), staleSelection, launchInProgress, launchDidNotProduceApplication

        var errorDescription: String? {
            switch self {
            case .unavailable(let message): message
            case .staleSelection: String(localized: "This app changed. Refresh the library and try again.", bundle: HanlinLocalization.bundle)
            case .launchInProgress: String(localized: "Another app is still opening.", bundle: HanlinLocalization.bundle)
            case .launchDidNotProduceApplication: String(localized: "The app could not be opened.", bundle: HanlinLocalization.bundle)
            }
        }
    }

    init(host: HanlinMiniAppHost = .shared, platform: HanlinScriptingPlatform = .shared) {
        self.host = host
        self.platform = platform
    }

    func catalog() async throws -> [HanlinMiniAppCatalogItem] {
        try await refreshCatalog()
        return host.visibleItems
    }

    func refreshCatalog() async throws {
        #if DEBUG || HANLIN_TESTING
        let traceID = UUID().uuidString
        let traceStart = ProcessInfo.processInfo.systemUptime
        func trace(_ phase: String) {
            let elapsed = ProcessInfo.processInfo.systemUptime - traceStart
            Self.catalogLogger.notice("miniapps.catalog.refresh id=\(traceID, privacy: .public) pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public) elapsed=\(elapsed, privacy: .public) phase=\(phase, privacy: .public)")
        }
        trace("begin")
        defer { trace("exit") }
        trace("platform.restore.begin")
        #endif
        await platform.restore()
        #if DEBUG || HANLIN_TESTING
        trace("platform.restore.end")
        trace("package-services.require.begin")
        #endif
        try requirePackageServices()
        #if DEBUG || HANLIN_TESTING
        trace("package-services.require.end")
        trace("host.refresh.begin")
        #endif
        await host.refresh(installedPackages: platform.installedPackages)
        #if DEBUG || HANLIN_TESTING
        trace("host.refresh.end")
        #endif
        if let error = host.lastError { throw Failure.unavailable(error) }
        if Bundle.main.bundleIdentifier == SplitAppStorageLayout.miniAppsBundleIdentifier {
            #if DEBUG || HANLIN_TESTING
            trace("live-catalog.export.begin")
            #endif
            try? HanlinSplitLiveTarget.exportCatalog()
            #if DEBUG || HANLIN_TESTING
            trace("live-catalog.export.end")
            trace("external-catalog.publish.begin")
            #endif
            try HanlinExternalMiniAppCatalog.publish(host.items)
            #if DEBUG || HANLIN_TESTING
            trace("external-catalog.publish.end")
            #endif
        }
        #if DEBUG || HANLIN_TESTING
        trace("success")
        #endif
    }

    func launch(_ selected: HanlinMiniAppCatalogItem, includesDismissControl: Bool = true,
                sharedInput: HanlinValue? = nil,
                completeSharedRequest: (@MainActor @Sendable (HanlinValue) async throws -> Void)? = nil) async throws -> AnyView {
        guard !launching else { throw Failure.launchInProgress }
        launching = true
        defer { launching = false }
        // Visibility is a catalog preference. An authorized foreground request
        // still resolves against the current canonical registrations.
        try await refreshCatalog()
        try platform.requireLaunchAdmission()
        guard let item = host.items.first(where: { $0 == selected }) else { throw Failure.staleSelection }
        switch item.engine {
        case .swift:
            let view = try host.swiftDestination(for: item, sharedInput: sharedInput,
                                                 completeSharedRequest: completeSharedRequest).view
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
            return AnyView(ScriptingApplicationContainerView(
                platform: platform, ownsApplicationLifetime: includesDismissControl))
        }
    }

    func launch(packageID: HanlinInstalledPackageID) async throws -> AnyView {
        guard !launching else { throw Failure.launchInProgress }
        launching = true
        defer { launching = false }

        await platform.restore()
        try platform.requireLaunchAdmission()
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

    func packageManagement() throws -> AnyView {
        try requirePackageServices()
        return AnyView(HanlinMiniAppsPackageManagement(platform: platform))
    }

    private func requirePackageServices() throws {
        if let error = platform.bootstrapError { throw Failure.unavailable(error) }
    }
}

@MainActor
private struct HanlinMiniAppsPackageManagement: View {
    let platform: HanlinScriptingPlatform
    @State private var importing = false

    var body: some View {
        List {
            ForEach(platform.installedPackages, id: \.record.installedPackageID) { package in
                NavigationLink {
                    ScriptingInstalledPackageDetailView(
                        packageID: package.record.installedPackageID, platform: platform
                    )
                } label: {
                    Text(package.manifest?.name ?? package.record.packageID.rawValue)
                }
            }
        }
        .navigationTitle(Text("Packages", bundle: HanlinLocalization.bundle))
        .accessibilityIdentifier("hanlin-miniapps-package-management")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(hanlin: "Import package", systemImage: "square.and.arrow.down") { importing = true }
                    .accessibilityIdentifier("hanlin-miniapps-package-import")
            }
        }
        .sheet(isPresented: $importing) {
            NavigationStack { ScriptingPackageImportView(platform: platform) }
        }
        .task { await platform.restore() }
    }
}

// The application adapters supply the same original provider and transfer view.
// The independent library module never initializes an engine or App Group store.
extension HanlinMiniAppsServices {
    /// Activated by the app composition root only after the existing services
    /// dependency cut and target graph have been delivered and verified.
    static func connected(to provider: HanlinMiniAppsProvider) -> Self {
        Self(catalog: { try await provider.catalog() },
             launch: { try await provider.launch($0) },
             packageManagement: { try provider.packageManagement() })
    }

}

public extension HanlinMiniAppsServices {
    /// Use after preparing the original application runtime for the host process.
    /// Reuses its catalog, grants, installed registry and launch implementation.
    @MainActor
    static func connectedToHanlin() -> Self {
        .connected(to: HanlinMiniAppsProvider())
    }
}

public extension HanlinMiniAppsLibrary {
    /// Compose the original library with Hanlin's existing transfer screen and
    /// live transfer lock. Runtime preparation stays with the composition root.
    @MainActor
    init(services: HanlinMiniAppsServices) {
        self.init(services: services,
                  transferView: { AnyView(HanlinMiniAppTransferView(mode: .receive)) },
                  isTransferringProductData: { HanlinScriptingPlatform.shared.isTransferringProductData })
    }
}
