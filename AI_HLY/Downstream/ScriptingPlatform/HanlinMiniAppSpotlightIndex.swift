import AppIntents
import CoreSpotlight
import Foundation
import HanlinPlatformContracts
import HanlinProductSplit
import HanlinScriptStore
import Observation
#if DEBUG || HANLIN_TESTING
import OSLog
#endif

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
    @ObservationIgnored private var spotlightReconciliationTask: Task<Void, Never>?
    @ObservationIgnored private var spotlightReconciliationRequested = false
    @ObservationIgnored private var activeIndexWrites = 0
    @ObservationIgnored private let publicationProductIdentifier: String
    @ObservationIgnored private let isProductTransferActive: @MainActor () -> Bool
    @ObservationIgnored private let indexOperation: (@MainActor ([HanlinMiniAppSystemRecord]) async throws -> Void)?
    @ObservationIgnored private let reconcileCapture: @MainActor ([HanlinMiniAppSystemRecord]) async -> Void

    init(productIdentifier: String? = nil,
         isProductTransferActive: @escaping @MainActor () -> Bool = { HanlinScriptingPlatform.shared.isTransferringProductData },
         indexOperation: (@MainActor ([HanlinMiniAppSystemRecord]) async throws -> Void)? = nil,
         reconcileCapture: @escaping @MainActor ([HanlinMiniAppSystemRecord]) async -> Void = {
             await HanlinMiniAppCaptureCoordinator.shared.reconcile(records: $0)
         }) {
        publicationProductIdentifier = productIdentifier ?? Self.productIdentifier
        self.isProductTransferActive = isProductTransferActive
        self.indexOperation = indexOperation
        self.reconcileCapture = reconcileCapture
    }

    /// A completed write remains the serialization tail, so its mere presence is
    /// not a transfer barrier. Only an owned caller, worker or pending write is.
    var hasPendingWork: Bool {
        reconciling || spotlightReconciliationTask != nil || activeIndexWrites > 0
    }

    /// Explicit draining for an owner that needs quiescence; catalog readiness
    /// never calls this. It does not cancel an in-flight system operation.
    func waitForPendingSpotlightReconciliation() async {
        while let task = spotlightReconciliationTask { await task.value }
    }
    #if DEBUG || HANLIN_TESTING
    // Observation UUIDs identify these Swift call/task spans, not native OS operations.
    @ObservationIgnored private var indexWriteObservationID: String?
    @ObservationIgnored private var reconciliationObservationID: String?

    private static func traceCatalog(_ phase: String, observationID: String, start: TimeInterval, relatedID: String = "none") {
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let logger = Logger(subsystem: "com.hanlin.ai", category: "MiniAppsCatalog")
        logger.notice("miniapps.catalog.spotlight id=\(observationID, privacy: .public) related=\(relatedID, privacy: .public) pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public) elapsed=\(elapsed, privacy: .public) phase=\(phase, privacy: .public)")
    }
    #endif

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
        await reconcile(packages: packages, artifactRoot: platform.activeArtifactURL(for:))
    }

    func reconcile(packages: [HanlinStoredPackageSnapshot],
                   artifactRoot: (HanlinStoredPackageSnapshot) -> URL?) async {
        #if DEBUG || HANLIN_TESTING
        let traceID = UUID().uuidString
        let traceStart = ProcessInfo.processInfo.systemUptime
        Self.traceCatalog("reconcile.begin", observationID: traceID, start: traceStart)
        defer { Self.traceCatalog("reconcile.exit", observationID: traceID, start: traceStart) }
        #endif
        guard Self.supportsProduct(identifier: publicationProductIdentifier), !isProductTransferActive() else { return }
        records = HanlinMiniAppSystemCatalog.records(packages: packages,
            productIdentifier: publicationProductIdentifier, artifactRoot: artifactRoot)
        requestSpotlightReconciliation()
        if reconciling {
            reconciliationRequested = true
            #if DEBUG || HANLIN_TESTING
            Self.traceCatalog("reconcile.coalesced-return", observationID: traceID, start: traceStart, relatedID: reconciliationObservationID ?? "none")
            #endif
            return
        }
        reconciling = true
        #if DEBUG || HANLIN_TESTING
        reconciliationObservationID = traceID
        #endif
        #if DEBUG || HANLIN_TESTING
        Self.traceCatalog("reconcile.owner.acquired", observationID: traceID, start: traceStart, relatedID: "none")
        #endif
        defer {
            reconciling = false
            #if DEBUG || HANLIN_TESTING
            reconciliationObservationID = nil
            #endif
            #if DEBUG || HANLIN_TESTING
            Self.traceCatalog("reconcile.owner.released", observationID: traceID, start: traceStart, relatedID: "none")
            #endif
        }
        repeat {
            reconciliationRequested = false
            #if DEBUG || HANLIN_TESTING
            let iterationObservationID = UUID().uuidString
            #endif
            #if DEBUG || HANLIN_TESTING
            Self.traceCatalog("reconcile.iteration.begin", observationID: traceID, start: traceStart, relatedID: iterationObservationID)
            #endif
            #if DEBUG || HANLIN_TESTING
            Self.traceCatalog("reconcile.capture.begin", observationID: traceID, start: traceStart, relatedID: iterationObservationID)
            #endif
            await reconcileCapture(captureRecords)
            #if DEBUG || HANLIN_TESTING
            Self.traceCatalog("reconcile.capture.returned", observationID: traceID, start: traceStart, relatedID: iterationObservationID)
            #endif
            #if DEBUG || HANLIN_TESTING
            Self.traceCatalog("reconcile.iteration.returned", observationID: traceID, start: traceStart, relatedID: iterationObservationID)
            #endif
        } while reconciliationRequested
        #if DEBUG || HANLIN_TESTING
        Self.traceCatalog("reconcile.return.ready", observationID: traceID, start: traceStart, relatedID: "none")
        #endif
    }

    /// Records are published synchronously above. Exactly one process-owned
    /// worker projects their latest value into Spotlight; a scene or catalog
    /// caller does not own the lifetime of a system indexing roundtrip.
    private func requestSpotlightReconciliation() {
        spotlightReconciliationRequested = true
        guard spotlightReconciliationTask == nil else { return }
        spotlightReconciliationTask = Task {
            #if DEBUG || HANLIN_TESTING
            let traceID = UUID().uuidString
            let traceStart = ProcessInfo.processInfo.systemUptime
            Self.traceCatalog("worker.begin", observationID: traceID, start: traceStart)
            #endif
            defer {
                spotlightReconciliationTask = nil
                #if DEBUG || HANLIN_TESTING
                Self.traceCatalog("worker.exit", observationID: traceID, start: traceStart)
                #endif
            }
            repeat {
                spotlightReconciliationRequested = false
                let desired = spotlightRecords
                do {
                    if indexedRecords != desired {
                        #if DEBUG || HANLIN_TESTING
                        Self.traceCatalog("worker.replace-index.begin", observationID: traceID, start: traceStart)
                        #endif
                        try await replaceIndex(with: desired)
                        #if DEBUG || HANLIN_TESTING
                        Self.traceCatalog("worker.replace-index.returned", observationID: traceID, start: traceStart)
                        #endif
                    }
                    spotlightError = nil
                } catch {
                    spotlightError = error.localizedDescription
                    #if DEBUG || HANLIN_TESTING
                    Self.traceCatalog("worker.replace-index.error", observationID: traceID, start: traceStart)
                    #endif
                }
            } while spotlightReconciliationRequested
        }
    }

    func claimPresentation(windowID: UUID) {
        if presentationWindowID == nil { presentationWindowID = windowID }
    }

    func releasePresentation(windowID: UUID) {
        if presentationWindowID == windowID { presentationWindowID = nil }
    }

    func reindexSpotlight() async throws {
        #if DEBUG || HANLIN_TESTING
        let traceID = UUID().uuidString
        let traceStart = ProcessInfo.processInfo.systemUptime
        Self.traceCatalog("reindex.begin", observationID: traceID, start: traceStart)
        defer { Self.traceCatalog("reindex.exit", observationID: traceID, start: traceStart) }
        #endif
        guard Self.supportsProduct(identifier: publicationProductIdentifier) else { throw HanlinMiniAppSystemEntrypointError.unavailable }
        guard !isProductTransferActive() else { throw HanlinProductTransferError.busy }
        #if DEBUG || HANLIN_TESTING
        Self.traceCatalog("reindex.replace-index.begin", observationID: traceID, start: traceStart, relatedID: "none")
        #endif
        // The callback acknowledges a real completed projection. If publication
        // advanced while it waited, also complete the then-current generation.
        while true {
            let desired = spotlightRecords
            try await replaceIndex(with: desired)
            if desired == spotlightRecords { break }
        }
        #if DEBUG || HANLIN_TESTING
        Self.traceCatalog("reindex.replace-index.returned", observationID: traceID, start: traceStart, relatedID: "none")
        #endif
    }

    private func replaceIndex(with desired: [HanlinMiniAppSystemRecord]) async throws {
        guard !isProductTransferActive() else { throw HanlinProductTransferError.busy }
        activeIndexWrites += 1
        defer { activeIndexWrites -= 1 }
        // The named index belongs only to this product and entity type. Deleting
        // the type first guarantees stale disabled/uninstalled entries are removed,
        // including after a crash before the prior reconciliation completed.
        let previous = indexWrite
        #if DEBUG || HANLIN_TESTING
        let writeObservationID = UUID().uuidString
        let writeObservationStart = ProcessInfo.processInfo.systemUptime
        let predecessorObservationID = indexWriteObservationID ?? "none"
        Self.traceCatalog("write.begin", observationID: writeObservationID, start: writeObservationStart, relatedID: predecessorObservationID)
        defer { Self.traceCatalog("write.exit", observationID: writeObservationID, start: writeObservationStart, relatedID: predecessorObservationID) }
        #endif
        let write = Task {
            #if DEBUG || HANLIN_TESTING
            Self.traceCatalog("write.task.begin", observationID: writeObservationID, start: writeObservationStart, relatedID: predecessorObservationID)
            defer { Self.traceCatalog("write.task.exit", observationID: writeObservationID, start: writeObservationStart, relatedID: predecessorObservationID) }
            #endif
            // Reindex callbacks and install publications can overlap at awaits.
            // Serialize the real index operations so an older write cannot win.
            if let previous {
                #if DEBUG || HANLIN_TESTING
                Self.traceCatalog("write.wait-previous.begin", observationID: writeObservationID, start: writeObservationStart, relatedID: predecessorObservationID)
                #endif
                _ = try? await previous.value
                #if DEBUG || HANLIN_TESTING
                Self.traceCatalog("write.wait-previous.returned", observationID: writeObservationID, start: writeObservationStart, relatedID: predecessorObservationID)
                #endif
            }
            // A failed delete/index may leave a partial projection. Do not keep
            // a prior success cache that could suppress its required repair.
            indexedRecords = nil
            if let indexOperation {
                try await indexOperation(desired)
            } else {
                let index = CSSearchableIndex(name: publicationProductIdentifier + ".installed-miniapps.v1")
                #if DEBUG || HANLIN_TESTING
                Self.traceCatalog("write.delete.begin", observationID: writeObservationID, start: writeObservationStart, relatedID: predecessorObservationID)
                #endif
                try await index.deleteAppEntities(ofType: HanlinInstalledMiniAppEntity.self)
                #if DEBUG || HANLIN_TESTING
                Self.traceCatalog("write.delete.returned", observationID: writeObservationID, start: writeObservationStart, relatedID: predecessorObservationID)
                #endif
                if !desired.isEmpty {
                    #if DEBUG || HANLIN_TESTING
                    Self.traceCatalog("write.index.begin", observationID: writeObservationID, start: writeObservationStart, relatedID: predecessorObservationID)
                    #endif
                    try await index.indexAppEntities(desired.map(HanlinInstalledMiniAppEntity.init))
                    #if DEBUG || HANLIN_TESTING
                    Self.traceCatalog("write.index.returned", observationID: writeObservationID, start: writeObservationStart, relatedID: predecessorObservationID)
                    #endif
                }
            }
            // Commit within the serialized task, before its successor proceeds.
            // An older caller resuming later cannot overwrite a newer success.
            indexedRecords = desired
            #if DEBUG || HANLIN_TESTING
            Self.traceCatalog("write.records.committed", observationID: writeObservationID, start: writeObservationStart, relatedID: predecessorObservationID)
            #endif
            #if DEBUG || HANLIN_TESTING
            Self.traceCatalog("write.task.return.ready", observationID: writeObservationID, start: writeObservationStart, relatedID: predecessorObservationID)
            #endif
        }
        indexWrite = write
        #if DEBUG || HANLIN_TESTING
        indexWriteObservationID = writeObservationID
        #endif
        #if DEBUG || HANLIN_TESTING
        Self.traceCatalog("write.value.begin", observationID: writeObservationID, start: writeObservationStart, relatedID: predecessorObservationID)
        #endif
        try await write.value
        #if DEBUG || HANLIN_TESTING
        Self.traceCatalog("write.value.returned", observationID: writeObservationID, start: writeObservationStart, relatedID: predecessorObservationID)
        #endif
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
