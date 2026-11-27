import AppIntents
import CoreSpotlight
import Foundation
import HanlinPlatformContracts
import HanlinProductSplit
import HanlinScriptStore
import Observation

@MainActor
@Observable
final class HanlinMiniAppSystemEntrypoints {
    static let shared = HanlinMiniAppSystemEntrypoints()
    private(set) var records: [HanlinMiniAppSystemRecord] = []
    private(set) var spotlightError: String?
    private(set) var presentationWindowID: UUID?
    @ObservationIgnored private var indexWrite: Task<Void, any Error>?
    @ObservationIgnored private var indexedRecords: [HanlinMiniAppSystemRecord]?
    @ObservationIgnored private var reconciling = false
    @ObservationIgnored private var reconciliationRequested = false

    var spotlightRecords: [HanlinMiniAppSystemRecord] { records.filter { $0.entrypoint.kind == .spotlight } }
    var captureRecords: [HanlinMiniAppSystemRecord] { records.filter { $0.entrypoint.kind == .capture } }
    static var productIdentifier: String { Bundle.main.bundleIdentifier ?? "" }
    static var isAvailableForCurrentProduct: Bool { supportsProduct(identifier: productIdentifier) }

    static func supportsProduct(identifier: String) -> Bool {
        identifier == SplitAppStorageLayout.miniAppsBundleIdentifier
    }
    static var indexName: String { productIdentifier + ".installed-miniapps.v1" }

    /// Called by the existing successful install/update/disable/uninstall/startup
    /// publication path. No native widget instance is necessary for discovery.
    func reconcile(packages: [HanlinStoredPackageSnapshot], platform: HanlinScriptingPlatform) async {
        guard Self.isAvailableForCurrentProduct else { return }
        records = HanlinMiniAppSystemCatalog.records(packages: packages,
            productIdentifier: Self.productIdentifier, artifactRoot: platform.activeArtifactURL(for:))
        if reconciling { reconciliationRequested = true; return }
        reconciling = true
        defer { reconciling = false }
        repeat {
            reconciliationRequested = false
            let desired = spotlightRecords
            do {
                if indexedRecords != desired { try await replaceIndex(with: desired) }
                spotlightError = nil
            } catch { spotlightError = error.localizedDescription }
            await HanlinMiniAppCaptureCoordinator.shared.reconcile(records: captureRecords)
        } while reconciliationRequested
    }

    func claimPresentation(windowID: UUID) {
        if presentationWindowID == nil { presentationWindowID = windowID }
    }

    func releasePresentation(windowID: UUID) {
        if presentationWindowID == windowID { presentationWindowID = nil }
    }

    func reindexSpotlight() async throws {
        guard Self.isAvailableForCurrentProduct else { throw HanlinMiniAppSystemEntrypointError.unavailable }
        try await replaceIndex(with: spotlightRecords)
    }

    private func replaceIndex(with desired: [HanlinMiniAppSystemRecord]) async throws {
        // The named index belongs only to this product and entity type. Deleting
        // the type first guarantees stale disabled/uninstalled entries are removed,
        // including after a crash before the prior reconciliation completed.
        let previous = indexWrite
        let write = Task {
            // Reindex callbacks and install publications can overlap at awaits.
            // Serialize the real index operations so an older write cannot win.
            if let previous { _ = try? await previous.value }
            let index = CSSearchableIndex(name: Self.indexName)
            try await index.deleteAppEntities(ofType: HanlinInstalledMiniAppEntity.self)
            if !desired.isEmpty { try await index.indexAppEntities(desired.map(HanlinInstalledMiniAppEntity.init)) }
        }
        indexWrite = write
        try await write.value
        indexedRecords = desired
    }

    func openSpotlightEntity(id: String) async throws {
        guard Self.isAvailableForCurrentProduct else { throw HanlinMiniAppSystemEntrypointError.unavailable }
        let platform = HanlinScriptingPlatform.shared
        await platform.restore()
        guard let current = spotlightRecords.first(where: { $0.id == id }) else {
            throw HanlinMiniAppSystemEntrypointError.unavailable
        }
        // Resolve the current generation at the moment of opening. A stale title
        // cannot select another installation, product, source file or action.
        _ = try await platform.openSystemEntrypoint(installedPackageID: current.installedPackageID,
            entrypointID: current.entrypoint.id, generation: current.generation,
            parameters: .object(["source": .string("spotlight")]))
    }
}

enum HanlinMiniAppSystemEntrypointError: LocalizedError {
    case unavailable, staleGeneration, invalidAction, applicationUnavailable
    var errorDescription: String? {
        switch self {
        case .unavailable: "This mini app entrypoint is no longer available. Open the app library to choose an installed package."
        case .staleGeneration: "This package changed after the capture was created. Choose its current capture action before continuing."
        case .invalidAction: "This entrypoint does not identify a declared action in the installed package."
        case .applicationUnavailable: "The mini app could not open its prepared application."
        }
    }
}
