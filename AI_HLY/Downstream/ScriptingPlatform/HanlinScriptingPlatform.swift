import SwiftUI
import HanlinLocalization
import CryptoKit
import CoreFoundation
import Foundation
import HanlinPlatformContracts
import HanlinScriptCompiler
import HanlinScriptContracts
import HanlinScriptExtensions
import HanlinScriptDeviceServices
import HanlinScriptStore
import HanlinScriptUI
import HanlinScriptingApplicationRuntime
import HanlinScriptingSDK
import HanlinNativeScriptRuntime
import HanlinExpoRuntime
import ExpoWidgets
import HanlinExpoNativeAPI
import HanlinMiniAppCore
import HanlinProductSplit
import Observation
import OSLog
import UIKit
import UserNotifications
import WidgetKit

/// Application-owned services; the runtime carries no model/credential store.
/// Permission checks remain in the existing SDK and broker admission paths.
@MainActor
protocol HanlinScriptingApplicationServices: AnyObject {
    var assistantServiceFactory: HanlinMiniAppAssistantServiceFactory? { get }
    func publishCompactAgentConfig() throws
    func loadAssistant(
        _ request: HanlinScriptingAssistantRequest
    ) async throws -> AsyncThrowingStream<HanlinScriptingAssistantChunk, Error>
}

extension HanlinScriptingApplicationServices {
    var assistantServiceFactory: HanlinMiniAppAssistantServiceFactory? { nil }
}

@MainActor
@Observable
final class HanlinScriptingPlatform {
    var assistantServiceFactory: HanlinMiniAppAssistantServiceFactory? {
        applicationServices?.assistantServiceFactory
    }

    /// Production defaults preserve bootstrap behavior; unit fixtures own their store and queue.
    @MainActor
    struct Initialization {
        var registerExpoDefines: () -> Void
        var makeExtensionStore: () throws -> HanlinScriptExtensionStore
        var enqueuePublication: (@escaping @MainActor () -> Void) -> Void

        static var live: Self {
            .init(
                registerExpoDefines: { HanlinExpoSession.ensureAppDefinesLoaded() },
                makeExtensionStore: { try HanlinScriptingPlatform.productExtensionStore() },
                enqueuePublication: { work in Task { @MainActor in work() } }
            )
        }
    }

    enum Activity: Equatable {
        case idle
        case importing
        case previewReady
        case installing
        case failed(String)
    }

    static let shared = HanlinScriptingPlatform()

    // The canonical broker still owns authorization. It returns an admitted
    // invocation to the scene/session that submitted it, not a global current UI.
    private static var invocationPlatforms: [UUID: HanlinScriptingPlatform] = [:]

    static func platform(forInvocationID id: UUID) -> HanlinScriptingPlatform {
        invocationPlatforms[id] ?? shared
    }

    private(set) var activity: Activity = .idle
    private(set) var preview: HanlinImportPreview?
    private(set) var authoringReport: HanlinMiniAppAuthoringReport?
    private(set) var importAttemptID = UUID()
    private var importOperationID: UUID?
    private var retainedImportArchive: URL?
    private var repairWakeURL: URL?
    private var importPresentations: Set<UUID> = []

    var hasImportPresentation: Bool { !importPresentations.isEmpty }

    func setImportPresentation(_ id: UUID, visible: Bool) {
        if visible { importPresentations.insert(id) }
        else { importPresentations.remove(id) }
    }

    var canInstallPreview: Bool {
        preview?.canInstall == true && (authoringReport?.succeeded ?? true)
    }

    var canRepairImport: Bool {
        (stagedPackage?.archiveURL ?? retainedImportArchive) != nil
    }

    var importDiagnostics: [HanlinMiniAppAuthoringDiagnostic] {
        var rows = (preview?.findings ?? []).map { finding in
            HanlinMiniAppAuthoringDiagnostic(
                code: finding.code ?? "PACKAGE_COMPATIBILITY",
                category: finding.severity.rawValue,
                message: finding.message, file: finding.sourcePath, remediation: finding.rationale)
        }
        rows.append(contentsOf: authoringReport?.diagnostics ?? [])
        if case .failed(let message) = activity, !rows.contains(where: { $0.message == message }) {
            rows.append(.init(code: "PACKAGE_IMPORT", category: "error", message: message))
        }
        return rows
    }

    func importDiagnosticJSON() throws -> Data {
        let report = HanlinMiniAppAuthoringReport(
            engine: authoringReport?.engine ?? preview?.manifest?.hanlinRuntime ?? "unknown",
            operation: "import", succeeded: canInstallPreview,
            diagnostics: importDiagnostics, sourceRoot: authoringReport?.sourceRoot,
            sdk: authoringReport?.sdk)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(report)
    }

    func prepareImportRepair() throws -> URL {
        if let repairWakeURL { return repairWakeURL }
        guard let archive = stagedPackage?.archiveURL ?? retainedImportArchive else {
            throw MiniAppAuthoringTransferStore.StoreError.missingPayload
        }
        let url = try MiniAppAuthoringDelivery.prepareRepair(
            archive: archive,
            originalFileName: preview?.source.originalFileName ?? archive.lastPathComponent,
            diagnostics: importDiagnosticJSON())
        repairWakeURL = url
        return url
    }
    private(set) var installedPackages: [HanlinStoredPackageSnapshot] = []
    private(set) var bootstrapError: String?
    private(set) var pendingResumeCommands: [HanlinScriptResumeCommand] = []
    private(set) var resumeCommandRejections: [HanlinInvocationQueueRejection] = []
    private(set) var capabilityApprovals = HanlinCapabilityApprovalState(requests: [])
    var approvedCapabilities: Set<HanlinCapabilityID> { capabilityApprovals.approvedCapabilities }
    private(set) var activeApplicationID: HanlinInstalledPackageID?
    private(set) var activeApplicationModel: HanlinScriptUIModel?
    private(set) var activeNativeScriptController: UIViewController?
    private(set) var activeExpoController: UIViewController?
    /// Presented by the owning foreground scene when an external action opens a runtime.
    private(set) var presentsForegroundAction = false
    struct ShortcutPresentation {
        let id: UUID
        let platform: HanlinScriptingPlatform
        let store: HanlinScriptExtensionStore
        var completed = false
    }
    /// The existing foreground scene presents this invocation's original Host.
    /// Its provider/progress callbacks never replace a visible app's handler.
    private(set) var shortcutPresentation: ShortcutPresentation?
    var foregroundPresentationPlatform: HanlinScriptingPlatform {
        shortcutPresentation?.platform ?? self
    }

    func admitShortcutPresentation(_ platform: HanlinScriptingPlatform,
                                   command: HanlinScriptResumeCommand,
                                   store: HanlinScriptExtensionStore) throws {
        try Task.checkCancellation()
        guard actionPresentationAllowed, platform.actionPresentationAllowed,
              command.invocation.delivery?.source == .shortcuts,
              command.invocation.delivery?.canPresentUI == true,
              command.invocation.continueInForeground,
              UIApplication.shared.applicationState == .active,
              !isTransferringProductData, !isLaunching,
              activeApplicationID == nil, shortcutPresentation == nil,
              !hasImportPresentation, systemUIPresentation == nil,
              extensionStore?.root == store.root, platform.extensionStore?.root == store.root,
              try store.command(for: command.id) == command,
              let receipt = try store.receipt(for: command.id),
              receipt.status == .running, receipt.leaseID != nil, !receipt.cancellationRequested,
              receipt.leaseExpiresAt.map({ $0 > .now }) == true else {
            throw HanlinInvocationDispatchError(.needsForeground, .unavailableHost)
        }
        shortcutPresentation = .init(id: command.id, platform: platform, store: store)
        // A dedicated provider can touch the same product storage as this
        // owner. Preserve the existing fresh-process transfer boundary.
        needsFreshProcessForTransfer = true
    }

    func dismissShortcutPresentation(_ invocationID: UUID, executionFinished: Bool = false) {
        guard let owned = shortcutPresentation, owned.id == invocationID else { return }
        // Keep an actual running result authoritative. The executor observes this
        // cancellation request, drains its work and records the terminal outcome.
        let receipt = try? owned.store.requestCancellation(invocationID)
        shortcutPresentation = nil
        owned.platform.presentsForegroundAction = false
        if executionFinished || owned.completed || receipt?.status.isTerminal == true {
            owned.platform.dismissActiveApplication()
        }
        Task { @MainActor [weak self] in try? await self?.processPendingResumeCommands() }
    }

    func settleShortcutPresentation(_ receipt: HanlinInvocationReceipt) {
        guard var owned = shortcutPresentation, owned.id == receipt.invocationID,
              receipt.status.isTerminal else { return }
        if receipt.status == .succeeded, owned.platform.presentsForegroundAction {
            owned.completed = true
            shortcutPresentation = owned
        } else {
            // Terminal success without a surface is a normal result. Detach it
            // here, after execution, without requesting cancellation.
            shortcutPresentation = nil
            owned.platform.dismissActiveApplication()
            Task { @MainActor [weak self] in try? await self?.processPendingResumeCommands() }
        }
    }
    private(set) var systemUIPresentation: HanlinScriptingSystemUIPresentation?
    private(set) var installedRoot: URL?
    private(set) var widgetPublicationDiagnostics: [HanlinInstalledPackageID: HanlinWidgetStorageDiagnostic] = [:]
    private(set) var lastWidgetStorageDiagnostic: HanlinWidgetStorageDiagnostic?

    private let packageCenter = HanlinPackageCenter()
    private var stagedPackage: HanlinStagedPackage?
    private var analyzer: HanlinScriptAnalyzer?
    private var store: HanlinAtomicScriptStore?
    private var bundler: HanlinScriptingBundler?
    private var extensionStore: HanlinScriptExtensionStore?
    private var invocationExecutor: HanlinInvocationExecutor?
    /// Supplied by the owning MiniApps scene; never a process-global current request.
    var externalMiniAppOperation: HanlinMiniAppExternalOperation?
    var externalMiniAppCanLaunch: (@MainActor @Sendable () -> Bool)?

    func requireLaunchAdmission() throws {
        try Task.checkCancellation()
        if let externalMiniAppCanLaunch, !externalMiniAppCanLaunch() {
            throw CancellationError()
        }
        guard shortcutPresentation == nil else {
            throw HanlinInvocationNotStarted()
        }
    }
    private var applicationSession: HanlinScriptingApplicationSession?
    private var nativeScriptSession: HanlinNativeScriptSession?
    private var nativeScriptWindowSession: HanlinNativeScriptWindowSession?
    private var nativeScriptHostServices: NativeScriptHostServicesAdapter?
    private var hasNativeScriptApplicationSession: Bool {
        nativeScriptSession != nil || nativeScriptWindowSession != nil
    }
    private var expoSession: HanlinExpoSession?
    private var expoHostServices: ExpoHostServicesAdapter?
    private(set) var isTransferringProductData = false
    private var activeStoreOperations = 0
    private var scriptingStorageCheckpoint: UUID?
    // Native engine teardown can finish on another thread.
    // A fresh process gives transfer an observable quiescence boundary.
    private var needsFreshProcessForTransfer = false
    private var isLaunching = false
    private var isExecutingHeadlessNativeScriptAction = false
    private var isProcessingResumeCommands = false
    private var resumeDrainRequested = false
    private var pendingNotificationEvents: [UUID: HanlinNotificationEvent] = [:]
    private var queuedNativeScriptAdmissions: Set<UUID> = []
    private var systemUIContinuation: CheckedContinuation<HanlinScriptingSystemUIResult, any Error>?
    private var applicationServices: (any HanlinScriptingApplicationServices)?
    private var applicationServicesGeneration = UUID()
    private let initialization: Initialization
    private let actionPresentationAllowed: Bool
    private let registersForegroundContinuation: Bool
    private let locationService = HanlinAppleLocationService()
    private let healthService = HanlinAppleHealthService()
    private let notificationService = HanlinAppleNotificationService()
    private let calendarService = HanlinAppleCalendarService()
    private var liveActivityRevisions: [String: UInt64] = [:]
    private let stagingRoot: URL?
    private static let logger = Logger(subsystem: "com.hanlin.ai", category: "ScriptPackageInstall")

    init(rootOverride: URL? = nil, initialization: Initialization = .live,
         actionPresentationAllowed: Bool = true, registersForegroundContinuation: Bool = true) {
        self.initialization = initialization
        self.actionPresentationAllowed = actionPresentationAllowed
        self.registersForegroundContinuation = registersForegroundContinuation
        initialization.registerExpoDefines()
        do {
            let metadata = try HanlinScriptingSDK.metadata()
            analyzer = HanlinScriptAnalyzer(inventory: .init(
                baselineID: metadata.baselineID,
                baselineDigest: metadata.baselineDigest,
                symbols: try metadata.records.map { record in
                    .init(
                        symbol: record.symbol,
                        state: record.state,
                        requiredCapability: try record.capability.map(HanlinCapabilityID.init(validating:)),
                        allowedContexts: record.contexts.contains("all")
                            ? Set(HanlinExecutionContext.allCases)
                            : Set(record.contexts.compactMap(HanlinExecutionContext.init(rawValue:)))
                    )
                }
            ))
            bundler = HanlinScriptingBundler(
                baseline: .init(
                    baselineID: metadata.baselineID,
                    baselineDigest: metadata.baselineDigest,
                    symbols: try metadata.records.map { record in
                        .init(
                            symbol: record.symbol,
                            state: record.state,
                            requiredCapability: try record.capability.map(HanlinCapabilityID.init(validating:)),
                            allowedContexts: record.contexts.contains("all")
                                ? Set(HanlinExecutionContext.allCases)
                                : Set(record.contexts.compactMap(HanlinExecutionContext.init(rawValue:)))
                        )
                    }
                ),
                abiVersion: HanlinScriptContractSupport.multiRuntime.abiVersion.description,
                scriptingDeclarations: try HanlinScriptingSDK.declarationFiles().map {
                    HanlinVirtualSourceFile(
                        logicalPath: "virtual/\($0.name)",
                        bytes: $0.data
                    )
                },
                compiler: HanlinNodeMobileScriptingCompiler()
            )
            let platformRoot = try rootOverride ?? Self.applicationSupportDirectory().appending(
                path: "ScriptingPlatform",
                directoryHint: .isDirectory
            )
            let staging = platformRoot.appending(path: "ImportStaging", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let installed = platformRoot.appending(path: "Installed", directoryHint: .isDirectory)
            if rootOverride == nil, Bundle.main.bundleIdentifier == SplitAppStorageLayout.miniAppsBundleIdentifier {
                try Self.prepareProductTransferRecovery()
            }
            store = try HanlinAtomicScriptStore(root: installed)
            do {
                let sharedStore = try initialization.makeExtensionStore()
                extensionStore = sharedStore
                invocationExecutor = HanlinInvocationExecutor(store: sharedStore)
            } catch {
                Self.logger.warning("extension_unavailable: App Group extension store unavailable: \(Self.safeMessage(error), privacy: .public)")
                extensionStore = nil
            }
            stagingRoot = staging
        } catch {
            stagingRoot = nil
            bootstrapError = Self.safeMessage(error)
        }
        registerWidgetHostActionContinuation()
    }

    private func registerWidgetHostActionContinuation() {
        guard registersForegroundContinuation, let extensionStore else { return }
        HanlinWidgetHostActionContinuation.register(owner: self, storeRoot: extensionStore.root) { [weak self] in
            await self?.resumePendingInvocations()
        }
    }

    static func productTransferOutbox() throws -> URL {
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: HanlinScriptExtensionStore.appGroupIdentifier)
        return try SplitAppStorageLayout.productTransferRoot(appGroupContainer: container)
    }

    static func productTransferTransactionRoot() throws -> URL {
        try applicationSupportDirectory().appending(path: "ProductTransfer/current", directoryHint: .isDirectory)
    }

    static func prepareProductTransferRecovery() throws {
        let installed = try applicationSupportDirectory()
            .appending(path: "ScriptingPlatform/Installed", directoryHint: .isDirectory)
        try HanlinProductTransferRecovery.recover(installedRoot: installed,
            dataRoot: HanlinMiniAppDataStore.applicationSupportRoot(),
            transactionRoot: productTransferTransactionRoot())
    }

    func recordCompiledMiniAppStorageUse() {
        needsFreshProcessForTransfer = true
    }

    private func beginProductTransfer() throws {
        try HanlinMiniAppHost.shared.validateVisibilityStorage()
        guard !needsFreshProcessForTransfer else { throw HanlinProductTransferError.restartRequired }
        let idle: Bool
        switch activity {
        case .idle, .failed: idle = true
        case .importing, .previewReady, .installing: idle = false
        }
        guard idle, !isTransferringProductData, activeStoreOperations == 0,
              !HanlinScriptingApplicationSession.hasPendingDisposals,
              !isLaunching, !isExecutingHeadlessNativeScriptAction, !isProcessingResumeCommands,
              queuedNativeScriptAdmissions.isEmpty, activeApplicationID == nil, shortcutPresentation == nil,
              applicationSession == nil, !hasNativeScriptApplicationSession, expoSession == nil,
              systemUIContinuation == nil else { throw HanlinProductTransferError.busy }
        do {
            scriptingStorageCheckpoint = try HanlinScriptingApplicationSession.beginStorageCheckpoint(
                dataRoot: HanlinMiniAppDataStore.applicationSupportRoot())
        } catch {
            throw HanlinProductTransferError.busy
        }
        isTransferringProductData = true
    }

    private func endProductTransfer() {
        if let token = scriptingStorageCheckpoint {
            HanlinScriptingApplicationSession.endStorageCheckpoint(token)
            scriptingStorageCheckpoint = nil
        }
        isTransferringProductData = false
        Task { @MainActor [weak self] in try? await self?.processPendingResumeCommands() }
    }

    func createProductTransfer() async throws -> HanlinProductTransferReceipt {
        guard Bundle.main.bundleIdentifier == "com.itorah.chavrusachat",
              let store else { throw HanlinProductTransferError.invalidCheckpoint }
        try beginProductTransfer()
        defer { endProductTransfer() }
        return try await store.createProductTransfer(dataRoot: HanlinMiniAppDataStore.applicationSupportRoot(),
                                                     outbox: Self.productTransferOutbox())
    }

    func receiveProductTransfer(_ receipt: HanlinProductTransferReceipt) async throws {
        guard Bundle.main.bundleIdentifier == SplitAppStorageLayout.miniAppsBundleIdentifier,
              let store else { throw HanlinProductTransferError.invalidCheckpoint }
        try beginProductTransfer()
        do {
            let checkpoint = try Self.productTransferOutbox().appending(path: receipt.id.uuidString.lowercased())
            let verified = try await Task.detached(priority: .userInitiated) {
                try HanlinProductTransferRecovery.checkpointReceipt(at: checkpoint)
            }.value
            guard verified == receipt else { throw HanlinProductTransferError.invalidCheckpoint }
            let accepted = try await store.receiveProductTransfer(from: checkpoint,
                dataRoot: HanlinMiniAppDataStore.applicationSupportRoot(),
                transactionRoot: Self.productTransferTransactionRoot())
            guard accepted == receipt else { throw HanlinProductTransferError.invalidCheckpoint }
            installedPackages = try await store.restore()
            endProductTransfer()
        } catch {
            // Reconcile a durable intent before allowing engine admission. If
            // recovery itself fails, keep admission closed until a safe restart.
            do {
                try Self.prepareProductTransferRecovery()
                installedPackages = try await store.restore()
                endProductTransfer()
            } catch {
                bootstrapError = Self.safeMessage(error)
            }
            throw error
        }
        try await refreshExtensionSnapshot()
        await HanlinMiniAppHost.shared.refresh(installedPackages: installedPackages)
    }

    func rollbackProductTransfer() async throws {
        guard Bundle.main.bundleIdentifier == SplitAppStorageLayout.miniAppsBundleIdentifier,
              let store else { throw HanlinProductTransferError.invalidCheckpoint }
        try beginProductTransfer()
        do {
            try await store.rollbackProductTransfer(dataRoot: HanlinMiniAppDataStore.applicationSupportRoot(),
                transactionRoot: Self.productTransferTransactionRoot())
            installedPackages = try await store.restore()
            endProductTransfer()
        } catch {
            do {
                try Self.prepareProductTransferRecovery()
                installedPackages = try await store.restore()
                endProductTransfer()
            } catch {
                bootstrapError = Self.safeMessage(error)
            }
            throw error
        }
        try await refreshExtensionSnapshot()
        await HanlinMiniAppHost.shared.refresh(installedPackages: installedPackages)
    }

    static func productExtensionStore() throws -> HanlinScriptExtensionStore {
        guard Bundle.main.bundleIdentifier == SplitAppStorageLayout.miniAppsBundleIdentifier else {
            return try HanlinScriptExtensionStore()
        }
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: HanlinScriptExtensionStore.appGroupIdentifier
        )
        let root = try SplitAppStorageLayout.extensionStoreRoot(
            trustedBundleIdentifier: Bundle.main.bundleIdentifier, appGroupContainer: container
        )
        return HanlinScriptExtensionStore(root: root)
    }

    func restore() async {
        guard !isTransferringProductData else { return }
        persistPendingNotificationEvents()
        activeStoreOperations += 1
        defer { activeStoreOperations -= 1 }
        guard let store else { return }
        do {
            await HanlinHostCapabilityAuthority.shared.usePackageGrantStore(store)
            installedPackages = try await store.restore()
            let scan = try extensionStore?.scanPendingCommands(limit: 128)
            pendingResumeCommands = scan?.commands ?? []
            resumeCommandRejections = scan?.rejections ?? []
            if !resumeCommandRejections.isEmpty {
                NativeToolTraceLogger.shared.log("miniapp.invocation.records_unreadable", [
                    "count": resumeCommandRejections.count,
                    "invocationIDs": resumeCommandRejections.compactMap { $0.invocationID?.uuidString }
                ])
            }
            try await refreshExtensionSnapshot()
            try await processPendingResumeCommands()
        } catch {
            bootstrapError = Self.safeMessage(error)
        }
    }

    /// Share the established store/transfer lifetime with request-owned tool sessions.
    func withAssistantToolExecution(
        _ operation: @MainActor () async throws -> HanlinValue
    ) async throws -> HanlinValue {
        guard !isTransferringProductData else { throw HanlinProductTransferError.busy }
        activeStoreOperations += 1
        defer { activeStoreOperations -= 1 }
        return try await operation()
    }

    /// Read-only admission snapshot; unlike restore(), this never processes queued actions.
    func assistantToolPackages() async throws -> [HanlinStoredPackageSnapshot] {
        guard !isTransferringProductData else { throw HanlinProductTransferError.busy }
        guard let store else { throw HanlinMiniAppRequestError.routeNotFound }
        return try await store.snapshots()
    }

    func activeArtifactURL(for package: HanlinStoredPackageSnapshot) -> URL? {
        guard let storeRoot = store?.root else { return nil }
        return storeRoot
            .appending(path: "packages/\(package.record.installedPackageID.rawValue)/generations/\(package.record.activeGeneration)", directoryHint: .isDirectory)
    }

    /// System surfaces use the same installed action queue/receipts as existing
    /// Host invocations. The locked process never executes a package or enqueues.
    @discardableResult
    func openSystemEntrypoint(
        installedPackageID: HanlinInstalledPackageID, entrypointID: String, generation: UInt64,
        parameters: HanlinValue, invocationID: UUID = UUID(), createdAt: Date = .now
    ) async throws -> UUID? {
        guard !isTransferringProductData, let store else { throw HanlinMiniAppSystemEntrypointError.unavailable }
        try requireLaunchAdmission()
        // Other app-owned store actors can commit while this platform is alive.
        // Reload the persisted registry at admission, not only this actor's cache.
        installedPackages = try await store.restore()
        guard let package = installedPackages.first(where: { $0.record.installedPackageID == installedPackageID }),
              package.enabled else { throw HanlinMiniAppSystemEntrypointError.unavailable }
        guard package.record.activeGeneration == generation else { throw HanlinMiniAppSystemEntrypointError.staleGeneration }
        guard let entry = package.entrypoints.first(where: { $0.id == entrypointID &&
            ($0.kind == .spotlight || $0.kind == .capture) }),
              entry.supportedContexts.contains(.mainApplication),
              let app = package.entrypoints.first(where: { $0.kind == .app &&
                  ($0.runtimeProfile == .hanlinExpo || $0.runtimeProfile == .hanlinNativeScript) }),
              entry.runtimeProfile == app.runtimeProfile, entry.sourcePath == app.sourcePath else {
            throw HanlinMiniAppSystemEntrypointError.unavailable
        }
        if let symbol = entry.exportedSymbol {
            let actions = try package.appDescriptor().actions.filter { $0.id.rawValue == symbol }
            guard actions.count == 1, actions[0].handler == entry.sourcePath,
                  !actions[0].capabilities.isEmpty else { throw HanlinMiniAppSystemEntrypointError.invalidAction }
            if activeApplicationID != installedPackageID {
                await launch(installedPackageID)
            }
            guard activeApplicationID == installedPackageID,
                  activeExpoController != nil || activeNativeScriptController != nil else {
                throw HanlinMiniAppSystemEntrypointError.applicationUnavailable
            }
            let latest = try await store.restore()
            guard latest.contains(where: { $0.record.installedPackageID == installedPackageID &&
                $0.enabled && $0.record.activeGeneration == generation && $0.entrypoints.contains(entry) }) else {
                throw HanlinMiniAppSystemEntrypointError.staleGeneration
            }
            presentsForegroundAction = true
            let command = HanlinScriptResumeCommand(id: invocationID, createdAt: createdAt,
                invocation: .init(identity: .init(installedPackageID: installedPackageID,
                    packageID: package.record.packageID, generation: generation, entrypointID: entrypointID),
                    entityID: symbol, parameters: parameters, continueInForeground: true))
            // enqueue preserves the original command/lease/receipt on an exact retry.
            try submitResumeCommand(command)
            await resumePendingInvocations()
            return command.id
        }
        guard entry.kind == .spotlight else { throw HanlinMiniAppSystemEntrypointError.invalidAction }
        await launch(installedPackageID)
        let latest = try await store.restore()
        guard latest.contains(where: { $0.record.installedPackageID == installedPackageID &&
            $0.enabled && $0.record.activeGeneration == generation && $0.entrypoints.contains(entry) }) else {
            dismissActiveApplication()
            throw HanlinMiniAppSystemEntrypointError.staleGeneration
        }
        guard activeApplicationID == installedPackageID,
              activeExpoController != nil || activeNativeScriptController != nil else {
            throw HanlinMiniAppSystemEntrypointError.applicationUnavailable
        }
        presentsForegroundAction = true
        return nil
    }

    func submitResumeCommand(_ command: HanlinScriptResumeCommand) throws {
        guard let extensionStore else { throw HanlinScriptExtensionStoreError.appGroupUnavailable }
        try extensionStore.enqueue(command)
        try reloadPendingResumeCommands()
        Task { @MainActor [weak self] in try? await self?.processPendingResumeCommands() }
    }

    /// Delivery and a later tap use the same sender-owned event ID. Persist,
    /// retaining transient failures for retry; action execution continues apart
    /// from the notification presentation deadline and obeys Host admission.
    func receiveNotificationEvent(_ event: HanlinNotificationEvent) throws {
        if let previous = pendingNotificationEvents[event.id], previous != event {
            throw HanlinInvocationQueueError.duplicateIdentity
        }
        // A tapped notification may already have left the OS delivered list.
        // Keep its decoded value until canonical storage is actually available.
        pendingNotificationEvents[event.id] = event
        persistPendingNotificationEvents()
        Task { @MainActor [weak self] in await self?.resumePendingInvocations() }
    }

    private func persistPendingNotificationEvents() {
        guard !pendingNotificationEvents.isEmpty, !isTransferringProductData else { return }
        if extensionStore == nil {
            do {
                let sharedStore = try initialization.makeExtensionStore()
                extensionStore = sharedStore
                invocationExecutor = HanlinInvocationExecutor(store: sharedStore)
                registerWidgetHostActionContinuation()
            } catch {
                Self.logger.error("Notification ingress retained until its App Group is available.")
                return
            }
        }
        guard let extensionStore else { return }
        for event in pendingNotificationEvents.values.sorted(by: { $0.createdAt < $1.createdAt }) {
            do {
                try HanlinNotificationInvocation.enqueue(event, in: extensionStore)
                pendingNotificationEvents.removeValue(forKey: event.id)
            } catch HanlinInvocationQueueError.duplicateIdentity {
                pendingNotificationEvents.removeValue(forKey: event.id)
                Self.logger.error("Conflicting notification identity rejected; original event retained.")
            } catch {
                // Locked/busy/unavailable storage is retried by the normal
                // preparation/foreground path, without a parallel disk inbox.
                Self.logger.error("Notification ingress retained until canonical storage can be written.")
            }
        }
    }

    /// Called by both products' existing foreground lifecycle. Persisted
    /// extension events remain queued while the Host is inactive/unavailable.
    func resumePendingInvocations(recoverDeliveredNotifications: Bool = false) async {
        guard UIApplication.shared.applicationState == .active, !isTransferringProductData else { return }
        persistPendingNotificationEvents()
        if recoverDeliveredNotifications {
            // Local/nonmutable background notifications have no service
            // extension callback. Recover the OS's actual delivered envelopes
            // once on foreground, including delivery while storage was locked.
            for notification in await UNUserNotificationCenter.current().deliveredNotifications() {
                do {
                    if let event = try HanlinNotificationEvent.decode(userInfo: notification.request.content.userInfo) {
                        if let previous = pendingNotificationEvents[event.id], previous != event {
                            throw HanlinInvocationQueueError.duplicateIdentity
                        }
                        pendingNotificationEvents[event.id] = event
                    }
                } catch {
                    Self.logger.error("Delivered notification event could not be enqueued.")
                }
            }
        }
        persistPendingNotificationEvents()
        do {
            try reloadPendingResumeCommands()
            try await processPendingResumeCommands()
        } catch {
            Self.logger.error("Foreground invocation queue could not be read.")
        }
    }

    /// Direct Shortcuts delivery uses the existing durable queue and executor.
    /// A session owned by this call cannot replace a visible MiniApp's controller
    /// or seize the foreground widget drain. No unrelated queued action is run.
    func executeShortcutCommand(_ command: HanlinScriptResumeCommand) async throws -> HanlinValue {
        activeStoreOperations += 1
        defer { activeStoreOperations -= 1 }
        try await prepareShortcutDispatch(command, allowsUI: false)
        guard let extensionStore, let invocationExecutor else {
            throw HanlinInvocationDispatchError(.failed, .invalidEnvelope)
        }
        try extensionStore.enqueue(command)
        let receipt = try await invocationExecutor.execute(command.id) { [weak self] command in
            guard let self else { throw HanlinInvocationDispatchError(.failed, .unavailableHost) }
            return try await self.dispatchResumeCommand(command)
        }
        guard let receipt else { throw HanlinInvocationQueueError.missingCommand }
        if receipt.status == .succeeded { return receipt.value ?? .null }
        if receipt.status == .queued {
            // An unavailable one-isolate runtime has not executed anything.
            // Do not run it unexpectedly after Shortcuts reports an error.
            _ = try extensionStore.requestCancellation(command.id)
            throw HanlinInvocationDispatchError(.needsForeground, .unavailableHost)
        }
        if receipt.status == .cancelled { throw CancellationError() }
        throw HanlinInvocationDispatchError(receipt.status, receipt.failure ?? .actionFailed)
    }

    /// The live AppIntent's existing executor already owns the durable lease.
    /// Revalidate that ownership after preparation before invoking package code.
    func executeClaimedShortcutCommand(_ command: HanlinScriptResumeCommand) async throws -> HanlinValue {
        activeStoreOperations += 1
        defer { activeStoreOperations -= 1 }
        guard let extensionStore, try extensionStore.command(for: command.id) == command,
              let original = try extensionStore.receipt(for: command.id),
              original.status == .running, let leaseID = original.leaseID else {
            throw HanlinInvocationQueueError.staleLease
        }
        try await prepareShortcutDispatch(command, allowsUI: command.invocation.delivery?.canPresentUI == true)
        try Task.checkCancellation()
        guard let current = try extensionStore.receipt(for: command.id),
              current.status == .running, current.leaseID == leaseID,
              current.leaseExpiresAt.map({ $0 > .now }) == true else {
            throw HanlinInvocationQueueError.staleLease
        }
        if current.cancellationRequested { throw CancellationError() }
        return try await dispatchResumeCommand(command)
    }

    private func prepareShortcutDispatch(_ command: HanlinScriptResumeCommand, allowsUI: Bool) async throws {
        guard command.invocation.delivery?.source == .shortcuts,
              command.invocation.delivery?.canPresentUI == allowsUI,
              command.invocation.continueInForeground == allowsUI,
              actionPresentationAllowed == allowsUI,
              !isTransferringProductData, let store else {
            throw HanlinInvocationDispatchError(.failed, .invalidEnvelope)
        }
        if allowsUI, UIApplication.shared.applicationState != .active {
            throw HanlinInvocationDispatchError(.needsForeground, .unavailableHost)
        }
        await HanlinHostCapabilityAuthority.shared.usePackageGrantStore(store)
        installedPackages = try await store.restore()
        // This surface exposes only the two active package engines.
        guard let package = installedPackages.first(where: {
            $0.record.installedPackageID == command.invocation.identity.installedPackageID
        }), package.entrypoints.contains(where: {
            $0.id == command.invocation.identity.entrypointID
                && [.hanlinExpo, .hanlinNativeScript].contains($0.runtimeProfile)
        }) else { throw HanlinInvocationDispatchError(.failed, .unsupportedEntrypoint) }
    }

    func resumeReceipt(_ id: UUID) throws -> HanlinInvocationReceipt? {
        try extensionStore?.receipt(for: id)
    }

    func submittedResumeCommand(_ id: UUID) throws -> HanlinScriptResumeCommand? {
        try extensionStore?.command(for: id)
    }

    func cancelResumeCommand(_ id: UUID) throws {
        guard let extensionStore else { throw HanlinScriptExtensionStoreError.appGroupUnavailable }
        _ = try extensionStore.requestCancellation(id)
        try reloadPendingResumeCommands()
    }

    private func reloadPendingResumeCommands() throws {
        let scan = try extensionStore?.scanPendingCommands(limit: 128)
        pendingResumeCommands = scan?.commands ?? []
        resumeCommandRejections = scan?.rejections ?? []
    }

    func configure(applicationServices: (any HanlinScriptingApplicationServices)?) {
        self.applicationServices = applicationServices
        let generation = UUID()
        applicationServicesGeneration = generation
        guard let applicationServices else { return }
        initialization.enqueuePublication { [weak self] in
            guard let self, self.applicationServicesGeneration == generation else { return }
            self.commitCompactAgentConfig(using: applicationServices)
        }
    }

    func acknowledgeResumeCommand(_ command: HanlinScriptResumeCommand) {
        do {
            try extensionStore?.acknowledge(command.id)
            pendingResumeCommands.removeAll { $0.id == command.id }
        } catch {
            activity = .failed(Self.safeMessage(error))
        }
    }

    public func resolveResourceURL(packageID: HanlinPackageID, relativePath: String) -> URL? {
        guard let package = installedPackages.first(where: { $0.record.packageID == packageID && $0.enabled }),
              let storeRoot = store?.root else {
            return nil
        }
        let clean = relativePath.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !clean.isEmpty, !clean.contains("\0"), !clean.hasPrefix("/") else {
            return nil
        }
        let components = clean.split(separator: "/")
        guard !components.contains(".."), !components.contains(".") else {
            return nil
        }
        let generation = package.record.activeGeneration
        let packageDir = package.record.installedPackageID.rawValue
        let genRoot = storeRoot
            .appending(path: "packages/\(packageDir)/generations/\(generation)")
        let candidate = genRoot.appending(path: clean)
        if FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            return candidate
        }
        let sourceCandidate = genRoot.appending(path: "source/\(clean)")
        if FileManager.default.fileExists(atPath: sourceCandidate.path(percentEncoded: false)) {
            return sourceCandidate
        }
        return nil
    }

    func importPackage(from sourceURL: URL) async {
        guard !isTransferringProductData else { return }
        activeStoreOperations += 1
        defer { activeStoreOperations -= 1 }
        print("HANLIN_IMPORT_PACKAGE_STARTED: url=\(sourceURL.path(percentEncoded: false))")
        discardPreview()
        let operationID = UUID()
        importOperationID = operationID
        importAttemptID = operationID
        guard let analyzer, let stagingRoot else {
            let message = bootstrapError ?? "Scripting platform is unavailable."
            print("HANLIN_IMPORT_PACKAGE_BOOTSTRAP_GUARD_FAILED: \(message)")
            activity = .failed(message)
            return
        }
        activity = .importing
        do {
            let copyRoot = stagingRoot.appending(path: "repair-input-\(operationID.uuidString.lowercased())",
                directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: copyRoot, withIntermediateDirectories: true)
            let ownedArchive = copyRoot.appending(path: sourceURL.lastPathComponent)
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
            try FileManager.default.copyItem(at: sourceURL, to: ownedArchive)
            retainedImportArchive = ownedArchive
            let center = packageCenter
            let result = try await Task.detached(priority: .userInitiated) {
                let staged = try center.stageAndInspect(
                    sourceURL: ownedArchive,
                    stagingParent: stagingRoot
                )
                do {
                    return (staged, try analyzer.analyze(staged))
                } catch {
                    try? center.discard(staged)
                    throw error
                }
            }.value
            guard importOperationID == operationID else {
                try? center.discard(result.0)
                return
            }
            var checkedReport: HanlinMiniAppAuthoringReport?
            if FileManager.default.fileExists(atPath:
                result.0.packageRoot.appending(path: "hanlin.authoring.json").path) {
                let engine: String
                if result.1.entrypoints.contains(where: { $0.runtimeProfile == .hanlinExpo }) {
                    engine = "expo"
                } else if result.1.entrypoints.contains(where: { $0.runtimeProfile == .hanlinNativeScript }) {
                    engine = "nativescript"
                } else {
                    engine = result.1.entrypoints.contains(where: { $0.widgetEngine == .scriptwidget })
                        ? "scriptwidget" : "unknown"
                }
                do {
                    checkedReport = try await MiniAppAuthoringService.validate(project: result.0.packageRoot, engine: engine)
                } catch {
                    checkedReport = .init(engine: engine, operation: "validate", succeeded: false,
                        diagnostics: [.init(code: "AUTHORING_VALIDATION", category: "error",
                            message: error.localizedDescription)])
                }
            }
            guard importOperationID == operationID else {
                try? center.discard(result.0)
                return
            }
            authoringReport = checkedReport
            stagedPackage = result.0
            preview = result.1
            capabilityApprovals = .init(requests: result.1.requestedCapabilities)
            activity = .previewReady
            print("HANLIN_IMPORT_PACKAGE_PREVIEW: canInstall=\(canInstallPreview) entrypoints=\(result.1.entrypoints.count)")
        } catch {
            guard importOperationID == operationID else { return }
            let message = Self.safeMessage(error)
            print("HANLIN_IMPORT_PACKAGE_CATCH_ERROR: \(message)")
            activity = .failed(message)
        }
    }

    func installPreview() async {
        guard !isTransferringProductData else { return }
        activeStoreOperations += 1
        defer { activeStoreOperations -= 1 }
        guard activity != .installing else { return }
        print("HANLIN_INSTALL_PREVIEW_STARTED: canInstall=\(canInstallPreview)")
        guard let preview, canInstallPreview, let stagedPackage,
              let store, let bundler, let stagingRoot else {
            activity = .failed("This package did not pass Import Preview.")
            return
        }
        activity = .installing
        let artifactRoot = stagingRoot.appending(
            path: "artifact-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        var allCaps = Set(capabilityApprovals.approvedCapabilities)
        allCaps.formUnion(preview.requestedCapabilities.map(\.capabilityID))
        if let manifestCaps = preview.manifest?.declaredCapabilities {
            allCaps.formUnion(manifestCaps)
        }
        let grantedCapabilities = allCaps.sorted { $0.rawValue < $1.rawValue }
        do {
            if preview.entrypoints.contains(where: { $0.kind == .widget }), extensionStore == nil {
                throw HanlinScriptExtensionStoreError.appGroupUnavailable
            }
            let publicationStore = extensionStore
            let installed = try await Task.detached(priority: .userInitiated) {
                defer { try? FileManager.default.removeItem(at: artifactRoot) }
                let contexts = Set(preview.entrypoints
                    .filter { ![.hanlinPython, .hanlinNativeScript, .hanlinExpo].contains($0.runtimeProfile)
                        && !($0.kind == .widget && $0.widgetEngine == .scriptwidget)
                        && !($0.kind == .widget && $0.widgetEngine == .legacy && URL(filePath: $0.sourcePath).pathExtension.lowercased() == "json") }
                    .map(\.kind))
                    .sorted { $0.rawValue < $1.rawValue }
                guard !preview.entrypoints.isEmpty else {
                    throw HanlinScriptingBundlerError.previewRejected
                }
                var bundles: [HanlinScriptingBundle] = []
                for context in contexts {
                    bundles.append(try await bundler.bundle(
                        package: stagedPackage,
                        preview: preview,
                        context: context
                    ))
                }
                let compiled = if preview.entrypoints.contains(where: { $0.runtimeProfile == .hanlinNativeScript }) {
                    try Self.nativeScriptSourceBundle(preview: preview)
                } else if preview.entrypoints.contains(where: { $0.runtimeProfile == .hanlinExpo }) {
                    try Self.preparedSourceBundle(preview: preview, compilerVersion: "Expo-\(HanlinExpoBridgeMetadata.runtimeVersion)-prepared")
                } else if preview.entrypoints.contains(where: { $0.widgetEngine == .scriptwidget }) && bundles.isEmpty {
                    try Self.preparedSourceBundle(preview: preview, compilerVersion: "ScriptWidget-\(HanlinMiniAppHostVersions.scriptWidgetRevision)-prepared")
                } else if bundles.isEmpty && preview.entrypoints.allSatisfy({ $0.kind == .widget && $0.widgetEngine == .legacy && URL(filePath: $0.sourcePath).pathExtension.lowercased() == "json" }) {
                    try Self.preparedSourceBundle(preview: preview, compilerVersion: "Hanlin-widget-json-v1")
                } else if bundles.isEmpty {
                    try Self.pythonSourceBundle(preview: preview)
                } else {
                    try bundler.merged(bundles)
                }
                let completeManifest = try bundler.writeInstallArtifact(
                    compiled,
                    packageRoot: stagedPackage.packageRoot,
                    to: artifactRoot,
                    preparedWidgetPrograms: try HanlinWidgetPackagePreparation.programs(packageRoot: stagedPackage.packageRoot, preview: preview)
                )
                let packageID = try Self.stablePackageID(for: preview.manifest ?? stagedPackage.manifest)
                let installedID = try HanlinInstalledPackageID(validating: "install-\(packageID.rawValue)")
                let version = try HanlinPackageVersion(validating: stagedPackage.manifest.version)
                let entrypoints = HanlinWidgetPackagePreparation.installedEntrypoints(preview: preview, artifactDigest: completeManifest.cacheFingerprint)
                let plan = HanlinInstallPlan(
                    installedPackageID: installedID,
                    packageID: packageID,
                    version: version,
                    sourceDigest: preview.source.contentSHA256,
                    entrypoints: entrypoints,
                    requestedCapabilities: preview.requestedCapabilities,
                    grantedCapabilities: grantedCapabilities,
                    manifest: stagedPackage.manifest
                )
                if try await store.snapshots().contains(where: { $0.record.installedPackageID == installedID }) {
                    try publicationStore?.invalidateWidgetActions(installedPackageID: installedID)
                    return try await store.update(
                        plan: plan,
                        artifactDirectory: artifactRoot,
                        artifactManifest: completeManifest
                    )
                }
                return try await store.install(
                    plan: plan,
                    artifactDirectory: artifactRoot,
                    artifactManifest: completeManifest
                )
            }.value
            installedPackages = try await store.snapshots()
            discardPreview()
            do {
                try await refreshExtensionSnapshot()
                activity = .idle
            } catch {
                print("HANLIN_INSTALL_PREVIEW_PUBLICATION_FAILED: \(error)")
                let diag = Self.makePublicationDiagnostic(
                    for: installed.installedPackageID,
                    phase: .hostPublishSnapshot,
                    error: error,
                    storeDiagnostic: extensionStore?.lastDiagnostic
                )
                widgetPublicationDiagnostics[installed.installedPackageID] = diag
                lastWidgetStorageDiagnostic = diag
                activity = .idle
            }
        } catch {
            print("HANLIN_INSTALL_PREVIEW_FAILED: \(error)")
            activity = .failed(Self.safeMessage(error))
        }
    }

    func setCapabilityApproved(_ approved: Bool, capability: HanlinCapabilityID) {
        var updated = capabilityApprovals
        updated.setApproved(approved, capability: capability)
        capabilityApprovals = updated
    }

    func discardPreview() {
        importOperationID = nil
        authoringReport = nil
        repairWakeURL = nil
        if let retainedImportArchive {
            try? FileManager.default.removeItem(at: retainedImportArchive.deletingLastPathComponent())
        }
        retainedImportArchive = nil
        if let stagedPackage { try? packageCenter.discard(stagedPackage) }
        stagedPackage = nil
        preview = nil
        capabilityApprovals = .init(requests: [])
        if case .failed = activity {} else { activity = .idle }
    }

    func reportImportFailure(_ error: Error) {
        discardPreview()
        activity = .failed(Self.safeMessage(error))
    }

    func clearFailure() {
        if case .failed = activity { activity = .idle }
    }

    func uninstall(_ id: HanlinInstalledPackageID) async {
        guard !isTransferringProductData else { return }
        activeStoreOperations += 1
        defer { activeStoreOperations -= 1 }
        guard let store else { return }
        do {
            try invalidateExtensionWidgets(for: id)
            if activeApplicationID == id { dismissActiveApplication() }
            try await store.uninstall(id)
            widgetPublicationDiagnostics[id] = nil
            installedPackages = try await store.snapshots()
            try await refreshExtensionSnapshot()
        } catch {
            activity = .failed(Self.safeMessage(error))
        }
    }

    func rollback(_ id: HanlinInstalledPackageID, to generation: UInt64) async {
        guard !isTransferringProductData else { return }
        activeStoreOperations += 1
        defer { activeStoreOperations -= 1 }
        guard let store else { return }
        do {
            try invalidateExtensionWidgets(for: id)
            if activeApplicationID == id { dismissActiveApplication() }
            _ = try await store.rollback(id, to: generation)
            installedPackages = try await store.snapshots()
            try await refreshExtensionSnapshot()
        } catch {
            activity = .failed(Self.safeMessage(error))
        }
    }

    func setEnabled(_ enabled: Bool, for id: HanlinInstalledPackageID) async {
        guard !isTransferringProductData else { return }
        activeStoreOperations += 1
        defer { activeStoreOperations -= 1 }
        guard let store else { return }
        do {
            try invalidateExtensionWidgets(for: id)
            if !enabled, activeApplicationID == id { dismissActiveApplication() }
            try await store.setEnabled(enabled, for: id)
            if !enabled { widgetPublicationDiagnostics[id] = nil }
            installedPackages = try await store.snapshots()
            try await refreshExtensionSnapshot()
        } catch {
            activity = .failed(Self.safeMessage(error))
        }
    }

    private func invalidateExtensionWidgets(for id: HanlinInstalledPackageID) throws {
        guard installedPackages.contains(where: { $0.record.installedPackageID == id && $0.entrypoints.contains(where: { $0.kind == .widget }) }) else { return }
        guard let extensionStore else { throw HanlinScriptExtensionStoreError.appGroupUnavailable }
        try extensionStore.invalidateWidgetActions(installedPackageID: id)
    }

    @ViewBuilder
    func scriptWidgetServicesView(for entityID: String) -> some View {
        if let extensionStore {
            HanlinScriptWidgetServicesView(store: extensionStore, entityID: entityID)
        } else {
            ContentUnavailableView("Widget Services", systemImage: "externaldrive.badge.exclamationmark",
                description: Text("The shared widget store is unavailable."))
        }
    }

    func startScriptWidgetLiveActivity(for entityID: String) async throws {
#if os(iOS)
        guard let extensionStore, let snapshot = try extensionStore.load(),
              let instance = snapshot.widgetInstances.first(where: { $0.entityID == entityID && $0.engine == .scriptwidget }),
              let widget = snapshot.widgets.first(where: { $0.identity == instance.identity && $0.engine == .scriptwidget }) else {
            throw HanlinWidgetActionError.inactiveInstance
        }
        _ = try await HanlinScriptWidgetLiveActivityController.start(store: extensionStore,
            entityID: entityID, family: widget.family, title: widget.displayName)
#else
        throw HanlinHostServiceError.invalidRequest("Live Activities are unavailable on this platform.")
#endif
    }

    func endScriptWidgetLiveActivities(for entityID: String) async throws {
#if os(iOS)
        guard let extensionStore, let instance = try extensionStore.load()?.widgetInstances.first(where: {
            $0.entityID == entityID && $0.engine == .scriptwidget
        }) else { throw HanlinWidgetActionError.inactiveInstance }
        try await HanlinScriptWidgetLiveActivityController.endActivities(store: extensionStore, identity: instance.identity)
#else
        throw HanlinHostServiceError.invalidRequest("Live Activities are unavailable on this platform.")
#endif
    }

    func widgetInstances(for id: HanlinInstalledPackageID) throws -> [HanlinWidgetInstance] {
        guard let extensionStore else { throw HanlinScriptExtensionStoreError.appGroupUnavailable }
        return try extensionStore.load()?.widgetInstances.filter { $0.identity.installedPackageID == id } ?? []
    }

    func widgetPublicationDiagnostic(for id: HanlinInstalledPackageID) -> HanlinWidgetStorageDiagnostic? {
        widgetPublicationDiagnostics[id] ?? extensionStore?.latestDurableQueryDiagnostic
    }

    func storageConsistencyReport() -> HanlinStorageConsistencyReport? {
        extensionStore?.generateConsistencyReport()
    }

    @discardableResult
    func republishWidgets(for id: HanlinInstalledPackageID) async -> Bool {
        do {
            try await refreshExtensionSnapshot()
            if widgetPublicationDiagnostics[id] != nil {
                return false
            }
            let instances = (try? widgetInstances(for: id).filter { $0.engine != .legacy }) ?? []
            return !instances.isEmpty
        } catch {
            let diag = Self.makePublicationDiagnostic(
                for: id,
                phase: .hostPublishSnapshot,
                error: error,
                storeDiagnostic: extensionStore?.lastDiagnostic
            )
            widgetPublicationDiagnostics[id] = diag
            lastWidgetStorageDiagnostic = diag
            return false
        }
    }

    func createWidgetInstance(from entityID: String, name: String) throws {
        guard let extensionStore else { throw HanlinScriptExtensionStoreError.appGroupUnavailable }
        try extensionStore.createWidgetInstance(from: entityID, displayName: name)
        WidgetCenter.shared.reloadTimelines(ofKind: HanlinWidgetActionExecutor.widgetKind)
        ControlCenter.shared.reloadControls(ofKind: HanlinScriptWidgetControlCatalog.buttonKind)
        ControlCenter.shared.reloadControls(ofKind: HanlinScriptWidgetControlCatalog.toggleKind)
    }

    func setCapabilityGranted(
        _ granted: Bool,
        capability: HanlinCapabilityID,
        for id: HanlinInstalledPackageID
    ) async {
        guard !isTransferringProductData else { return }
        activeStoreOperations += 1
        defer { activeStoreOperations -= 1 }
        guard let store else { return }
        do {
            await HanlinHostCapabilityAuthority.shared.usePackageGrantStore(store)
            try await store.setCapabilityGranted(granted, capability: capability, for: id)
            installedPackages = try await store.snapshots()
            try await refreshExtensionSnapshot()
        } catch {
            activity = .failed(Self.safeMessage(error))
        }
    }

    func launch(_ id: HanlinInstalledPackageID) async {
        guard !isTransferringProductData else { return }
        guard !isLaunching else { return }
        if activeApplicationID == id { return }
        isLaunching = true
        defer {
            isLaunching = false
            Task { @MainActor [weak self] in try? await self?.processPendingResumeCommands() }
        }

        guard let store,
              let package = installedPackages.first(where: { $0.record.installedPackageID == id }) else {
            activity = .failed("The installed package could not be found.")
            return
        }
        await HanlinHostCapabilityAuthority.shared.usePackageGrantStore(store)
        guard package.enabled else {
            activity = .failed("Enable this package before launching it.")
            return
        }
        guard let entrypoint = package.entrypoints.first(where: { $0.kind == .app }) else {
            activity = .failed("This package does not contain an app entrypoint.")
            return
        }
        if entrypoint.runtimeProfile == .hanlinNativeScript {
            guard !isExecutingHeadlessNativeScriptAction else {
                activity = .failed("A MiniApp action is still running. Try opening this app after it finishes.")
                return
            }
            do {
                let artifactRoot = try await store.activeArtifactURL(for: id)
                let entrypointURL = artifactRoot.appending(path: entrypoint.sourcePath, directoryHint: .notDirectory)

                let appID = package.appID
                let dataStore = HanlinMiniAppHost.shared.dataStore
                let container = try await dataStore.container(for: appID)
                try requireLaunchAdmission()
                dismissActiveApplication()
                let dataRootStr = container.root.path(percentEncoded: false)
                let stateDirStr = container.state.path(percentEncoded: false)
                let docsDirStr = container.documents.path(percentEncoded: false)
                let cacheDirStr = container.cache.path(percentEncoded: false)

                let env: [String: String] = [
                    "HANLIN_APP_ID": appID.rawValue,
                    "HANLIN_MINIAPP_DATA_ROOT": dataRootStr,
                    "HANLIN_MINIAPP_STATE_DIR": stateDirStr,
                    "HANLIN_MINIAPP_DOCUMENTS_DIR": docsDirStr,
                    "HANLIN_MINIAPP_CACHE_DIR": cacheDirStr
                ]

                let applicationRoot = entrypointURL.deletingLastPathComponent()
                if try HanlinNativeScriptWindowSession.supportsWindowFactory(applicationRoot: applicationRoot) {
                    let capabilities = Set(package.grantedCapabilities.map(\.rawValue))
                    let installedPackageID = package.record.installedPackageID
                    let operation = externalMiniAppOperation
                    var windowAdapter: NativeScriptHostServicesAdapter?
                    let windowSession = try HanlinNativeScriptWindowSession.open(
                        applicationRoot: applicationRoot,
                        environment: env,
                        makeWindowProvider: { windowID in
                            let adapter = NativeScriptHostServicesAdapter(
                                appID: appID, installedPackageID: installedPackageID,
                                grantedCapabilities: capabilities, sessionID: windowID,
                                isolatesWindowStorage: true,
                                externalMiniAppOperation: operation)
                            windowAdapter = adapter
                            return adapter
                        })
                    nativeScriptWindowSession = windowSession
                    nativeScriptHostServices = windowAdapter
                    needsFreshProcessForTransfer = true
                    activeApplicationID = id
                    activeNativeScriptController = windowSession.containerController
                    activity = .idle
                    return
                }

                let sessionID = UUID().uuidString.lowercased()
                let adapter = NativeScriptHostServicesAdapter(
                    appID: appID,
                    installedPackageID: package.record.installedPackageID,
                    grantedCapabilities: Set(package.grantedCapabilities.map(\.rawValue)),
                    sessionID: sessionID,
                    externalMiniAppOperation: externalMiniAppOperation,
                    assistantServiceFactory: assistantServiceFactory
                )
                // The pinned NativeScript main VM is process-wide. Check before
                // changing a legacy provider belonging to another scene.
                guard HanlinNativeScriptSession.activeSessionIdentifier == nil else {
                    throw NSError(domain: "HanlinMiniApps.NativeScript", code: 1,
                        userInfo: [NSLocalizedDescriptionKey:
                            "Another NativeScript app is open. Its runtime is preserved in its existing window."])
                }
                let session = try HanlinNativeScriptSession(
                    applicationRoot: entrypointURL.deletingLastPathComponent(),
                    environment: env,
                    sessionID: sessionID
                )
                nativeScriptSession = session
                nativeScriptHostServices = adapter
                HanlinNativeServicesHostProvider.setActiveContainer(
                    appID: appID.rawValue,
                    dataRoot: dataRootStr,
                    stateDir: stateDirStr,
                    docsDir: docsDirStr,
                    cacheDir: cacheDirStr,
                    grantedCapabilities: package.grantedCapabilities.map(\.rawValue),
                    sessionID: sessionID
                )
                HanlinNativeServicesBridge.register(adapter, forSessionID: sessionID)
                HanlinNativeServicesBridge.register(adapter)

                needsFreshProcessForTransfer = true
                try session.start()
                activeApplicationID = id
                activeNativeScriptController = session.containerController
                activity = .idle
            } catch {
                NSLog("[HanlinScriptingPlatform] NativeScript launch failed for %@: %@", id.rawValue, String(describing: error))
                dismissActiveApplication()
                activity = .failed(Self.safeMessage(error))
            }
            return
        }
        if entrypoint.runtimeProfile == .hanlinExpo {
            do {
                let artifactRoot = try await store.activeArtifactURL(for: id)
                let entrypointURL = artifactRoot.appending(path: entrypoint.sourcePath, directoryHint: .notDirectory)
                try requireLaunchAdmission()
                dismissActiveApplication()
                let sessionID = UUID().uuidString.lowercased()
                let adapter = ExpoHostServicesAdapter(
                    appID: package.appID,
                    installedPackageID: package.record.installedPackageID,
                    grantedCapabilities: Set(package.grantedCapabilities.map(\.rawValue)),
                    sessionID: sessionID,
                    canPresentUI: actionPresentationAllowed,
                    externalMiniAppOperation: externalMiniAppOperation,
                    assistantServiceFactory: assistantServiceFactory,
                    preparedWidgetPublisher: { [weak self] entrypointID, variantID, props in
                        guard let self else { throw HanlinWidgetActionError.inactiveInstance }
                        return try await self.publishPreparedExpoWidget(
                            installedPackageID: package.record.installedPackageID,
                            appID: package.appID, expectedGeneration: package.record.activeGeneration,
                            sessionID: sessionID, entrypointID: entrypointID, variantID: variantID, props: props)
                    }
                )
                expoHostServices = adapter
                HanlinExpoHostServicesBridge.register(provider: adapter, forSessionID: sessionID)
                let isNativeAPIGranted = true // Native API access follows the active runtime, not legacy grants.
                needsFreshProcessForTransfer = true
                let session = try HanlinExpoSession(
                    applicationRoot: entrypointURL.deletingLastPathComponent(),
                    sessionID: sessionID,
                    packageID: package.record.packageID.rawValue,
                    installedPackageID: package.record.installedPackageID.rawValue,
                    packageGeneration: package.record.activeGeneration,
                    isNativeAPIGranted: isNativeAPIGranted
                )
                expoSession = session
                try session.start()
                activeApplicationID = id
                activeExpoController = session.containerController
                activity = .idle
            } catch {
                NSLog("[HanlinScriptingPlatform] Expo launch failed for %@: %@", id.rawValue, String(describing: error))
                dismissActiveApplication()
                activity = .failed(Self.safeMessage(error))
            }
            return
        }
        guard entrypoint.runtimeProfile == .scriptingJSC else {
            activity = .failed("This interactive entrypoint does not have a foreground runtime.")
            return
        }
        do {
            let artifactRoot = try await store.activeArtifactURL(for: id)
            let compiledPath = try Self.compiledPath(for: entrypoint.sourcePath)
            let compiledURL = artifactRoot.appending(path: compiledPath, directoryHint: .notDirectory)
            let attributes = try FileManager.default.attributesOfItem(
                atPath: compiledURL.path(percentEncoded: false)
            )
            guard let bytes = attributes[.size] as? NSNumber, bytes.intValue <= 4 * 1_024 * 1_024 else {
                throw HanlinScriptingPlatformError.compiledEntrypointTooLarge
            }
            let program = try String(contentsOf: compiledURL, encoding: .utf8)
            try requireLaunchAdmission()
            dismissActiveApplication()


            let session = try HanlinScriptingApplicationSession(
                installedPackageID: id,
                canonicalAppID: package.appID,
                program: program,
                filename: compiledPath,
                storageAllowed: true,
                filesAllowed: true,
                networkAllowed: true,
                packageSourceDirectory: artifactRoot.appending(path: "source", directoryHint: .isDirectory),
                locationAllowed: true,
                locationLoader: { [weak self] request in
                    guard let self else { throw CancellationError() }
                    return try await self.performLocation(request)
                },
                healthAllowed: true,
                healthDataAvailable: HanlinAppleHealthService.isHealthDataAvailable,
                healthStatisticsLoader: { [weak self] request in
                    guard let self else { throw CancellationError() }
                    return try await self.performHealthStatistics(request)
                },
                healthActivitySummariesLoader: { [weak self] request in
                    guard let self else { throw CancellationError() }
                    return try await self.performHealthActivitySummaries(request)
                },
                healthWorkoutsLoader: { [weak self] request in
                    guard let self else { throw CancellationError() }
                    return try await self.performHealthWorkouts(request)
                },
                notificationsAllowed: true,
                notificationLoader: { [weak self] request in
                    guard let self else { throw CancellationError() }
                    return try await self.performNotification(request, installedPackageID: id)
                },
                remindersAllowed: true,
                reminderLoader: { [weak self] request in
                    guard let self else { throw CancellationError() }
                    return try await self.performReminder(request)
                },
                photosAllowed: true,
                pasteboardAllowed: true,
                openURLAllowed: true,
                assistantAllowed: true,
                assistantLoader: { [weak self] request in
                    guard let self else { throw CancellationError() }
                    return try await self.performAssistant(request)
                },
                liveActivityAllowed: true,
                liveActivityLoader: { [weak self] request in
                    guard let self else { throw CancellationError() }
                    return try await self.performLiveActivity(request, installedPackageID: id)
                },
                deviceSnapshot: HanlinAppleDeviceSnapshotProvider.snapshot(),
                systemLoader: { [weak self] operation, payloadJSON in
                    guard let self else { throw CancellationError() }
                    return try await self.performSystemOperation(operation, payloadJSON: payloadJSON)
                },
                systemUILoader: { [weak self] request in
                    guard let self else { throw CancellationError() }
                    return try await self.presentSystemUI(request)
                },
                imageJPEGEncoder: Self.encodeJPEG
            )
            applicationSession = session
            activeApplicationID = id
            activeApplicationModel = session.model
            activity = .idle
        } catch {
            dismissActiveApplication()
            activity = .failed(Self.safeMessage(error))
        }
    }

    func dismissActiveApplication() {
        cancelSystemUI()
        applicationSession?.dismiss()
        applicationSession = nil
        if let windowSession = nativeScriptWindowSession {
            // A single invocation releases only its own view/provider. The
            // coordinator retains the shared VM until its last window closes.
            windowSession.shutdown()
            nativeScriptWindowSession = nil
            NSLog("HANLIN_NS_WINDOW_RELEASE_OK")
        }
        if nativeScriptSession != nil {
            NSLog("HANLIN_NS_PRODUCTION_SHUTDOWN_OK")
        }
        if let session = nativeScriptSession {
            HanlinNativeServicesBridge.unregisterProvider(forSessionID: session.sessionID)
            HanlinNativeServicesHostProvider.clearActiveContainer(forSessionID: session.sessionID)
            if let adapter = nativeScriptHostServices {
                HanlinNativeServicesBridge.clearLegacyProvider(ifMatches: adapter)
            }
            session.shutdown()
        }
        nativeScriptSession = nil
        nativeScriptHostServices = nil
        if expoSession != nil {
            NSLog("HANLIN_EXPO_PRODUCTION_SHUTDOWN_OK")
        }
        expoHostServices?.invalidateAssistantRequests()
        expoSession?.shutdown()
        if let session = expoSession {
            HanlinExpoNativeAPIManager.revokeSession(sessionID: session.sessionID)
            HanlinExpoHostServicesBridge.unregister(sessionID: session.sessionID)
        }
        expoSession = nil
        if let adapter = expoHostServices { Task { await adapter.actionChannel.close() } }
        expoHostServices = nil
        activeApplicationID = nil
        activeApplicationModel = nil
        activeNativeScriptController = nil
        activeExpoController = nil
        presentsForegroundAction = false
        Task { @MainActor [weak self] in try? await self?.processPendingResumeCommands() }
    }

    func executeHeadlessAction(
        caller: HanlinAppID,
        targetAppID: HanlinAppID,
        action: HanlinActionID,
        capability: HanlinCapabilityID,
        payload: HanlinValue,
        invocationID: UUID? = nil
    ) async throws -> HanlinValue {
        guard !isTransferringProductData else { throw HanlinProductTransferError.busy }
        activeStoreOperations += 1
        defer { activeStoreOperations -= 1 }
        guard let store else {
            throw HanlinMiniAppRequestError.routeNotFound
        }

        guard let package = installedPackages.first(where: {
            ($0.manifest?.hanlinAppID == targetAppID.rawValue || $0.record.packageID.rawValue == targetAppID.rawValue)
                && $0.enabled
        }) else {
            throw HanlinMiniAppRequestError.routeNotFound
        }

        let descriptor = try package.appDescriptor()
        guard let declaredAction = descriptor.actions.first(where: { $0.id == action }),
              declaredAction.capabilities.contains(capability),
              let handlerPath = declaredAction.handler else {
            throw HanlinMiniAppRequestError.routeNotFound
        }

        if let appEntry = package.entrypoints.first(where: { $0.kind == .app && $0.runtimeProfile == .hanlinExpo }) {
            guard handlerPath == appEntry.sourcePath else { throw HanlinMiniAppRequestError.routeNotFound }
            if activeApplicationID != package.record.installedPackageID {
                guard !isLaunching else { throw HanlinInvocationNotStarted() }
                await launch(package.record.installedPackageID)
                if actionPresentationAllowed, activeApplicationID == package.record.installedPackageID, activeExpoController != nil {
                    presentsForegroundAction = true
                }
            }
            guard activeApplicationID == package.record.installedPackageID,
                  expoSession != nil, let adapter = expoHostServices else {
                throw HanlinInvocationDispatchError(.needsForeground, .unavailableHost)
            }
            return try await adapter.actionChannel.invoke(id: invocationID ?? UUID(), action: action.rawValue,
                caller: caller.rawValue, parameters: payload)
        }

        if hasNativeScriptApplicationSession, activeApplicationID == package.record.installedPackageID {
            guard let nativeScriptHostServices else {
                throw HanlinMiniAppRequestError.routeNotFound
            }
            return try await nativeScriptHostServices.invokeRegisteredAction(
                action,
                capability: capability,
                caller: caller,
                payload: payload
            )
        }

        guard !hasNativeScriptApplicationSession,
              !isExecutingHeadlessNativeScriptAction, !isLaunching else {
            // A platform never lends its foreground provider to another action.
            if let invocationID, queuedNativeScriptAdmissions.contains(invocationID) {
                throw HanlinInvocationNotStarted()
            }
            throw HanlinMiniAppRequestError.unauthorized
        }

        // Reserve this platform before the first suspension point. Independent
        // Shortcuts platforms may still join the original cooperating-window VM.
        // Global legacy/runtime admission is rechecked immediately before start.
        isExecutingHeadlessNativeScriptAction = true
        defer {
            isExecutingHeadlessNativeScriptAction = false
            Task { @MainActor [weak self] in try? await self?.processPendingResumeCommands() }
        }

        let artifactRoot = try await store.activeArtifactURL(for: package.record.installedPackageID)
        let handlerURL = artifactRoot
            .appending(path: handlerPath, directoryHint: .notDirectory)
            .standardizedFileURL
        let artifactPath = artifactRoot.standardizedFileURL.path(percentEncoded: false)
        let handlerFilePath = handlerURL.path(percentEncoded: false)
        guard handlerFilePath.hasPrefix(artifactPath + "/"),
              handlerURL.lastPathComponent == "bundle.mjs",
              (try? handlerURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]))
                .map({ $0.isRegularFile == true && $0.isSymbolicLink != true }) == true else {
            throw HanlinMiniAppRequestError.routeNotFound
        }

        let applicationRoot = handlerURL.deletingLastPathComponent()
        let usesWindowFactory = try HanlinNativeScriptWindowSession.supportsWindowFactory(
            applicationRoot: applicationRoot)
        let appID = targetAppID
        let container = try await HanlinMiniAppDataStore(root: HanlinMiniAppDataStore.applicationSupportRoot())
            .container(for: appID)

        let dataRootStr = container.root.path(percentEncoded: false)
        let stateDirStr = container.state.path(percentEncoded: false)
        let docsDirStr = container.documents.path(percentEncoded: false)
        let cacheDirStr = container.cache.path(percentEncoded: false)

        // Another scene or Shortcut owns a different store actor. Refresh the
        // persisted registry instead of trusting this actor's earlier snapshot.
        let currentPackages = try await store.restore()
        guard let current = currentPackages.first(where: { $0.record.installedPackageID == package.record.installedPackageID }),
              current.enabled, current.record.activeGeneration == package.record.activeGeneration else {
            throw HanlinInvocationDispatchError(.stale, .staleGeneration)
        }

        let env: [String: String] = [
            "HANLIN_APP_ID": appID.rawValue,
            "HANLIN_MINIAPP_DATA_ROOT": dataRootStr,
            "HANLIN_MINIAPP_STATE_DIR": stateDirStr,
            "HANLIN_MINIAPP_DOCUMENTS_DIR": docsDirStr,
            "HANLIN_MINIAPP_CACHE_DIR": cacheDirStr,
            "HANLIN_EXECUTION_MODE": "headless-action",
            "HANLIN_ACTION_ID": action.rawValue
        ]

        try Task.checkCancellation()
        let activeRuntimeID = HanlinNativeScriptSession.activeSessionIdentifier
        guard activeRuntimeID == nil || (usesWindowFactory
            && HanlinNativeScriptWindowSession.activeRuntimeSessionIdentifier == activeRuntimeID) else {
            // Legacy whole-application entries still own the single upstream VM.
            // Do not leave a rejected Shortcut queued for unexpected later replay.
            if let invocationID, queuedNativeScriptAdmissions.contains(invocationID) {
                throw HanlinInvocationNotStarted()
            }
            throw HanlinMiniAppRequestError.unauthorized
        }

        needsFreshProcessForTransfer = true
        if usesWindowFactory {
            var windowAdapter: NativeScriptHostServicesAdapter?
            let session = try HanlinNativeScriptWindowSession.open(
                applicationRoot: applicationRoot, environment: env
            ) { sessionID in
                let adapter = NativeScriptHostServicesAdapter(
                    appID: appID,
                    installedPackageID: package.record.installedPackageID,
                    grantedCapabilities: Set(package.grantedCapabilities.map(\.rawValue)),
                    sessionID: sessionID,
                    isolatesWindowStorage: true,
                    canPresentUI: false,
                    externalMiniAppOperation: self.externalMiniAppOperation,
                    assistantServiceFactory: self.assistantServiceFactory
                )
                windowAdapter = adapter
                return adapter
            }
            // The container stays unattached. Closing this owned action invalidates
            // only its bridge, handlers and callbacks; other windows retain the VM.
            defer { session.shutdown() }
            guard let adapter = windowAdapter else {
                throw HanlinMiniAppRequestError.routeNotFound
            }
            await Task.yield()
            try Task.checkCancellation()
            guard adapter.allRegisteredActionIDs.contains(action) else {
                throw HanlinMiniAppRequestError.routeNotFound
            }
            return try await adapter.invokeRegisteredAction(
                action, capability: capability, caller: caller, payload: payload)
        }

        let session = try HanlinNativeScriptSession(
            applicationRoot: applicationRoot,
            environment: env,
            sessionID: UUID().uuidString.lowercased()
        )

        let adapter = NativeScriptHostServicesAdapter(
            appID: appID,
            installedPackageID: package.record.installedPackageID,
            grantedCapabilities: Set(package.grantedCapabilities.map(\.rawValue)),
            sessionID: session.sessionID,
            canPresentUI: false,
            externalMiniAppOperation: externalMiniAppOperation,
            assistantServiceFactory: assistantServiceFactory
        )

        HanlinNativeServicesBridge.register(adapter, forSessionID: session.sessionID)
        defer {
            // Release JS-owned callbacks before the legacy VM is stopped.
            HanlinNativeServicesBridge.unregisterProvider(forSessionID: session.sessionID)
            session.shutdown()
        }

        try session.start()
        await Task.yield()
        try Task.checkCancellation()

        guard adapter.allRegisteredActionIDs.contains(action) else {
            throw HanlinMiniAppRequestError.routeNotFound
        }

        return try await adapter.invokeRegisteredAction(
            action,
            capability: capability,
            caller: caller,
            payload: payload
        )
    }

    func completeSystemUI(
        id: UUID,
        result: Result<HanlinScriptingSystemUIResult, any Error>
    ) {
        guard systemUIPresentation?.id == id, let continuation = systemUIContinuation else { return }
        systemUIPresentation = nil
        systemUIContinuation = nil
        continuation.resume(with: result)
    }

    func cancelSystemUI() {
        guard let continuation = systemUIContinuation else {
            systemUIPresentation = nil
            return
        }
        systemUIPresentation = nil
        systemUIContinuation = nil
        continuation.resume(throwing: CancellationError())
    }

    private func presentSystemUI(
        _ request: HanlinScriptingSystemUIRequest
    ) async throws -> HanlinScriptingSystemUIResult {
        guard systemUIContinuation == nil else {
            throw HanlinScriptingNativeError(
                name: "Error", code: "system_ui_busy",
                message: "Another system interface is already presented."
            )
        }
        if case let .previewImage(data) = request, UIImage(data: data) == nil {
            throw HanlinScriptingNativeError(
                name: "Error", code: "image_decode_failed",
                message: "The image could not be decoded for preview."
            )
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                systemUIContinuation = continuation
                systemUIPresentation = .init(id: UUID(), request: request)
            }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.cancelSystemUI() }
        }
    }

    /// Commit props to the existing prepared Expo program. The receipt states
    /// persistence/catalog/reload facts; WidgetKit rendering is not observed here.
    private func publishPreparedExpoWidget(
        installedPackageID: HanlinInstalledPackageID, appID: HanlinAppID,
        expectedGeneration: UInt64, sessionID: String,
        entrypointID: String, variantID: String, props: [String: HanlinValue]
    ) async throws -> String {
        guard !isTransferringProductData else { throw HanlinProductTransferError.busy }
        activeStoreOperations += 1
        defer { activeStoreOperations -= 1 }
        guard let store, let extensionStore,
              let session = expoSession, session.isActive, session.sessionID == sessionID,
              session.installedPackageID == installedPackageID.rawValue,
              session.packageGeneration == expectedGeneration else {
            throw HanlinWidgetActionError.inactiveInstance
        }
        guard let package = try await store.snapshots().first(where: {
            $0.record.installedPackageID == installedPackageID && $0.appID == appID
        }), package.enabled, package.record.activeGeneration == expectedGeneration,
           package.entrypoints.contains(where: {
               $0.id == entrypointID && $0.kind == .widget && $0.widgetEngine == .expo
                   && $0.runtimeProfile == .hanlinExpo
           }) else {
            throw HanlinHostServiceError.invalidRequest("Prepared widget publication requires this session's current installed generation and an explicitly declared Expo widget entrypoint")
        }
        // A suspension above must not admit an already-replaced owning session.
        guard expoSession === session, session.isActive else { throw HanlinWidgetActionError.inactiveInstance }
        let identity = HanlinScriptExtensionIdentity(installedPackageID: installedPackageID,
            packageID: package.record.packageID, generation: expectedGeneration,
            entrypointID: entrypointID, variantID: variantID)
        let receipt = try extensionStore.publishExpoWidgetProps(identity: identity, props: props)
        WidgetCenter.shared.reloadTimelines(ofKind: HanlinWidgetActionExecutor.widgetKind)
        guard var response = try JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt)) as? [String: Any] else {
            throw HanlinWidgetActionError.invalidState
        }
        response["ok"] = true
        response["published"] = true
        response["publication"] = "prepared-expo-state"
        response["engine"] = "expo"
        response["stateCommitted"] = true
        response["catalogVisible"] = true
        response["reloadRequested"] = true
        response["osRendered"] = NSNull()
        return String(decoding: try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]), as: UTF8.self)
    }

    struct ExpoWidgetPersistedExposure: Codable, Sendable {
        let validUntil: Date?
        let root: HanlinScriptUINode
    }

    @MainActor
    func publishExpoWidget(
        installedPackageID: HanlinInstalledPackageID,
        appID: HanlinAppID,
        entrypointID: String,
        family: String,
        root: HanlinScriptUINode,
        validUntil: Date?
    ) async throws {
        guard !isTransferringProductData else { throw HanlinProductTransferError.busy }
        activeStoreOperations += 1
        defer { activeStoreOperations -= 1 }
        guard let package = installedPackages.first(where: {
            $0.record.installedPackageID == installedPackageID && ($0.appID == appID || $0.record.packageID.rawValue == appID.rawValue)
        }), package.enabled else {
            throw HanlinHostServiceError.invalidRequest("Package is not installed or enabled: \(installedPackageID.rawValue)")
        }

        guard !entrypointID.isEmpty,
              !entrypointID.contains("/"),
              !entrypointID.contains("\\"),
              !entrypointID.contains(".."),
              !entrypointID.contains("\0") else {
            throw HanlinHostServiceError.invalidRequest("Invalid entrypoint ID format or traversal attempt: '\(entrypointID)'")
        }

        guard let entrypoint = package.entrypoints.first(where: {
            $0.runtimeProfile == .hanlinExpo && $0.kind == .widget && $0.id == entrypointID
        }) else {
            throw HanlinHostServiceError.invalidRequest("No matching Expo widget entrypoint: \(entrypointID)")
        }

        // Ordinary widget publishing without capability grant gating per owner policy

        let allowedFamilies = ["systemSmall", "systemMedium", "systemLarge", "systemExtraLarge"]
        guard allowedFamilies.contains(family) else {
            throw HanlinHostServiceError.invalidRequest("Invalid widget family: \(family)")
        }

        guard root.maxDepth <= 32 else {
            throw HanlinHostServiceError.invalidRequest("Widget UI tree exceeds maximum depth limit of 32")
        }

        let exposure = ExpoWidgetPersistedExposure(validUntil: validUntil, root: root)
        let data = try JSONEncoder().encode(exposure)
        guard data.count <= 256 * 1024 else {
            throw HanlinHostServiceError.invalidRequest("Widget UI payload exceeds maximum size limit of 256KiB")
        }

        let storeRoot = try HanlinMiniAppDataStore.applicationSupportRoot()
        let dataStore = try HanlinMiniAppDataStore(root: storeRoot)
        let relativePath = "widget-exposures/gen_\(package.record.activeGeneration)_\(entrypointID)_\(family).json"
        try await dataStore.write(data, appID: appID, area: .state, path: relativePath)

        try await refreshExtensionSnapshot()
    }

    func refreshExtensionSnapshot() async throws {
        guard !isTransferringProductData else { throw HanlinProductTransferError.busy }
        activeStoreOperations += 1
        defer { activeStoreOperations -= 1 }
        guard let store, let extensionStore else { return }

        // Original Expo registrations share the same installed catalog lifecycle.
        // Keep disabled choices, remove uninstalled data, and invalidate old
        // generation layouts before any asynchronous extension publication.
        HanlinExpoWidgetsIntegration.reconcileRegistrations(
            installedIDs: Set(installedPackages.map { $0.record.installedPackageID.rawValue }),
            activeGenerations: Dictionary(uniqueKeysWithValues: installedPackages.filter(\.enabled).map {
                ($0.record.installedPackageID.rawValue, $0.record.activeGeneration)
            }))

        var widgets: [HanlinScriptWidgetSnapshot] = []
        var intentEntities: [HanlinScriptIntentEntityRecord] = []
        var translationApps: [HanlinScriptTranslationUISnapshot] = []
        var nativePresentations: [HanlinNativePresentationSnapshot] = []
        var packageDiagnostics: [HanlinInstalledPackageID: HanlinWidgetStorageDiagnostic] = [:]
        var failedWidgetPackageIDs = Set<HanlinInstalledPackageID>()

        for package in installedPackages where package.enabled {
            do {
                let artifactRoot = try await store.activeArtifactURL(for: package.record.installedPackageID)
                let displayName = package.manifest?.name ?? package.record.packageID.rawValue
                let nativeDeclarations = try package.manifest.map(HanlinNativePresentationMetadata.declarations) ?? [:]
                func publishNativePresentation(_ entrypointID: String) throws -> HanlinNativePresentationDescriptor? {
                    guard let declaration = nativeDeclarations[entrypointID] else { return nil }
                    let path = HanlinNativePresentationMetadata.artifactPath(for: entrypointID)
                    let bytes = try Data(contentsOf: artifactRoot.appending(path: path))
                    let program = try JSONDecoder().decode(HanlinWidgetProgram.self, from: bytes)
                    try program.validate(engine: declaration.engine)
                    let artifact = try extensionStore.storeArtifact(data: bytes,
                        installedPackageID: package.record.installedPackageID, generation: package.record.activeGeneration)
                    return .init(engine: declaration.engine, programRef: artifact.ref,
                        programSHA256: artifact.sha256, input: declaration.input)
                }

                // Keyboard and notification panels use the same compiled original
                // native programs as snippets, without requiring a widget instance.
                for entrypoint in package.entrypoints where [.keyboard, .notificationUI].contains(entrypoint.kind) {
                    guard let descriptor = try publishNativePresentation(entrypoint.id) else {
                        throw HanlinNativePresentationError.unavailable
                    }
                    let identity = HanlinScriptExtensionIdentity(
                        installedPackageID: package.record.installedPackageID,
                        packageID: package.record.packageID,
                        generation: package.record.activeGeneration,
                        entrypointID: entrypoint.id)
                    nativePresentations.append(.init(identity: identity, displayName: displayName,
                        kind: entrypoint.kind == .keyboard ? .keyboard : .notificationUI,
                        nativePresentation: descriptor))
                }

                // Translation UI Discovery
                let translationEntrypoints = package.entrypoints.filter { $0.kind == .translationUI }
                for entrypoint in translationEntrypoints {
                    let fileURL = artifactRoot.appending(path: entrypoint.sourcePath)
                    let nativePresentation = try publishNativePresentation(entrypoint.id)
                    let rootNode: HanlinScriptUINode?
                    if nativePresentation != nil {
                        rootNode = nil
                    } else if entrypoint.sourcePath.hasSuffix(".json"),
                       let data = try? Data(contentsOf: fileURL),
                       let snapshot = try? JSONDecoder().decode(HanlinScriptUINode.self, from: data) {
                        rootNode = snapshot
                    } else if [.hanlinNativeScript, .hanlinExpo].contains(entrypoint.runtimeProfile),
                              let action = try package.appDescriptor().actions.first(where: {
                                  $0.handler == entrypoint.sourcePath &&
                                      (entrypoint.exportedSymbol == nil || $0.id.rawValue == entrypoint.exportedSymbol)
                              }) {
                        // This native extension carries the selected text to the
                        // prepared app. It never pretends to run React Native or
                        // a NativeScript VM inside a declarative snapshot.
                        rootNode = .init(kind: .vStack, children: [
                            .init(kind: .text, properties: ["text": .string("{{selectedText}}")]),
                            .init(kind: .button, properties: ["intent": .object([
                                "__hanlinAppIntent": .bool(true), "name": .string(action.id.rawValue),
                                "parameters": .object(["query": .string("{{selectedText}}"),
                                    "source": .string("translationUI")])
                            ])], children: [.init(kind: .text, properties: ["text": .string(action.title.resolved(locale: .current))])])
                        ])
                    } else {
                        Self.logger.info("Translation entrypoint has no executable action or valid snapshot")
                        continue
                    }
                    let identity = HanlinScriptExtensionIdentity(
                        installedPackageID: package.record.installedPackageID,
                        packageID: package.record.packageID,
                        generation: package.record.activeGeneration,
                        entrypointID: entrypoint.id
                    )
                    let summary = package.manifest?.description ?? "Hanlin Script Translation Mini App"
                    let iconSymbol = package.manifest?.unknownFields["icon"].flatMap {
                        if case let .string(s) = $0 { return s } else { return nil }
                    } ?? "doc.text.magnifyingglass"
                    let accentHex = package.manifest?.unknownFields["color"].flatMap {
                        if case let .string(s) = $0 { return s } else { return nil }
                    } ?? "#5CB88A"
                    let isBeta = package.manifest?.unknownFields["isBeta"].flatMap {
                        if case let .bool(b) = $0 { return b } else { return nil }
                    } ?? false

                    translationApps.append(.init(
                        identity: identity,
                        appID: package.record.packageID.rawValue,
                        displayName: displayName,
                        summary: summary,
                        iconSymbol: iconSymbol,
                        accentHex: accentHex,
                        isBeta: isBeta,
                        entrypointID: entrypoint.id,
                        rootNode: rootNode,
                        nativePresentation: nativePresentation
                    ))
                }

                let extensionEntrypoints = package.entrypoints.filter {
                    ($0.runtimeProfile == .scriptingJSC || $0.runtimeProfile == .hanlinNativeScript || $0.runtimeProfile == .hanlinExpo)
                        && ($0.kind == .widget || $0.kind == .appIntent)
                }
                guard !extensionEntrypoints.isEmpty else { continue }

                for entrypoint in extensionEntrypoints {
                    let identity = HanlinScriptExtensionIdentity(
                        installedPackageID: package.record.installedPackageID,
                        packageID: package.record.packageID,
                        generation: package.record.activeGeneration,
                        entrypointID: entrypoint.id,
                        variantID: "default"
                    )

                    if entrypoint.kind == .widget {
                        // Records predating the explicit engine contract are legacy.
                        // A filename is never authority to execute another engine.
                        let engine = entrypoint.widgetEngine ?? .legacy

                        let widgetURL = artifactRoot.appending(path: entrypoint.sourcePath)
                        let widgetData = try? Data(contentsOf: widgetURL)

                        switch engine {
                        case .expo, .scriptwidget:
                            guard let widgetData else { throw HanlinWidgetProgramError.invalidProgram }
                            let program = try JSONDecoder().decode(HanlinWidgetProgram.self, from: widgetData)
                            try program.validate(engine: engine)
                            let artifact = try extensionStore.storeArtifact(data: widgetData,
                                installedPackageID: package.record.installedPackageID, generation: package.record.activeGeneration)
                            let payload: HanlinWidgetPayload = engine == .expo
                                ? .expo(.init(layout: "", layoutRef: artifact.ref, layoutSHA256: artifact.sha256))
                                : .scriptwidget(.init(script: "", scriptRef: artifact.ref, scriptSHA256: artifact.sha256))
                            let fallback = HanlinScriptUINode(kind: .text, properties: ["text": .string("Open Hanlin to configure this native widget")])
                            for family in program.families {
                                widgets.append(.init(identity: identity, displayName: displayName, family: family,
                                    actionIdentity: identity, validUntil: .distantFuture, engine: engine, payload: payload, root: fallback))
                            }

                        case .legacy:
                            if entrypoint.sourcePath.hasSuffix(".json"),
                               let data = widgetData,
                               let rootNode = try? JSONDecoder().decode(HanlinScriptUINode.self, from: data) {
                                for family in ["systemSmall", "systemMedium", "systemLarge", "systemExtraLarge"] {
                                    widgets.append(.init(
                                        identity: identity,
                                        displayName: displayName,
                                        family: family,
                                        actionIdentity: identity,
                                        validUntil: .now.addingTimeInterval(900),
                                        engine: .legacy,
                                        payload: .legacy(rootNode),
                                        root: rootNode
                                    ))
                                }
                            } else if let compiledPath = try? Self.compiledPath(for: entrypoint.sourcePath) {
                                let compiledURL = artifactRoot.appending(path: compiledPath, directoryHint: .notDirectory)
                                if let program = try? String(contentsOf: compiledURL, encoding: .utf8) {
                                    for family in ["systemSmall", "systemMedium", "systemLarge", "systemExtraLarge"] {
                                        let presentation = try? {
                                            let session = try HanlinScriptingApplicationSession(
                                                installedPackageID: package.record.installedPackageID,
                                                canonicalAppID: package.appID,
                                                program: program,
                                                filename: compiledPath,
                                                entrypointContext: .widget(family: family),
                                                storageAllowed: true,
                                                filesAllowed: true,
                                                packageSourceDirectory: artifactRoot.appending(path: "source", directoryHint: .isDirectory)
                                            )
                                            defer { session.dispose() }
                                            return session.widgetPresentation
                                        }()
                                        if let presentation {
                                            widgets.append(.init(
                                                identity: identity,
                                                displayName: displayName,
                                                family: family,
                                                actionIdentity: identity,
                                                validUntil: max(presentation.reloadDate ?? Date.now.addingTimeInterval(900), Date.now.addingTimeInterval(60)),
                                                engine: .legacy,
                                                payload: .legacy(presentation.root),
                                                root: presentation.root
                                            ))
                                        }
                                    }
                                }
                            }
                        }
                        continue
                    }

                    let nativePresentation = try publishNativePresentation(entrypoint.id)
                    if entrypoint.runtimePolicyID == "native-presentation-v1", let nativePresentation {
                        intentEntities.append(.init(identity: identity, id: entrypoint.exportedSymbol ?? entrypoint.id,
                            displayName: displayName, appID: package.appID, nativePresentation: nativePresentation))
                        continue
                    }
                    if entrypoint.runtimeProfile == .hanlinNativeScript || entrypoint.runtimeProfile == .hanlinExpo {
                        var actionIDs: [(id: String, title: String)] = []
                        let intentURL = artifactRoot.appending(path: entrypoint.sourcePath)
                        if entrypoint.sourcePath.hasSuffix(".json"),
                           let intentData = try? Data(contentsOf: intentURL),
                           let intentJSON = try? JSONSerialization.jsonObject(with: intentData) as? [String: Any] {
                            let action = (intentJSON["action"] as? String) ?? (intentJSON["name"] as? String)
                            let title = (intentJSON["title"] as? String) ?? displayName
                            if let action {
                                actionIDs.append((id: action, title: title))
                            }
                        }
                        for action in try package.appDescriptor().actions {
                            if let symbol = entrypoint.exportedSymbol, symbol != action.id.rawValue { continue }
                            if entrypoint.runtimePolicyID == "prepared-foreground-action-v1",
                               action.handler != entrypoint.sourcePath { continue }
                            if !actionIDs.contains(where: { $0.id == action.id.rawValue }) {
                                actionIDs.append((id: action.id.rawValue, title: action.title.resolved(locale: .current)))
                            }
                        }
                        if nativePresentation != nil && actionIDs.isEmpty {
                            actionIDs.append((id: entrypoint.exportedSymbol ?? entrypoint.id, title: displayName))
                        }
                        let declaredActions = try package.appDescriptor().actions
                        for item in actionIDs {
                            let matching = declaredActions.filter {
                                $0.id.rawValue == item.id &&
                                    (entrypoint.exportedSymbol == nil || entrypoint.exportedSymbol == $0.id.rawValue) &&
                                    (entrypoint.runtimePolicyID != "prepared-foreground-action-v1" ||
                                        $0.handler == entrypoint.sourcePath)
                            }
                            // Optional presentation does not replace a real registered action.
                            // Presentation-only entries were published separately above.
                            let hostActionHandler = matching.count == 1
                                ? matching.first?.handler : nil
                            intentEntities.append(.init(identity: identity, id: item.id, displayName: item.title,
                                appID: package.appID, hostActionHandler: hostActionHandler,
                                nativePresentation: nativePresentation))
                        }
                        continue
                    }

                    let compiledPath = try Self.compiledPath(for: entrypoint.sourcePath)
                    let compiledURL = artifactRoot.appending(path: compiledPath, directoryHint: .notDirectory)
                    let attributes = try FileManager.default.attributesOfItem(
                        atPath: compiledURL.path(percentEncoded: false)
                    )
                    guard let bytes = attributes[.size] as? NSNumber, bytes.intValue <= 4 * 1_024 * 1_024 else {
                        throw HanlinScriptingPlatformError.compiledEntrypointTooLarge
                    }
                    let program = try String(contentsOf: compiledURL, encoding: .utf8)

                    if entrypoint.kind == .widget {
                        for family in ["systemSmall", "systemMedium", "systemLarge", "systemExtraLarge"] {
                            let presentation = try {
                                let session = try HanlinScriptingApplicationSession(
                                    installedPackageID: package.record.installedPackageID,
                                    canonicalAppID: package.appID,
                                    program: program,
                                    filename: compiledPath,
                                    entrypointContext: .widget(family: family),
                                    storageAllowed: true,
                                    filesAllowed: true,
                                    packageSourceDirectory: artifactRoot.appending(path: "source", directoryHint: .isDirectory)
                                )
                                defer { session.dispose() }
                                return session.widgetPresentation
                            }()
                            guard let presentation else { continue }
                            let minimumRefresh = Date.now.addingTimeInterval(60)
                            widgets.append(.init(
                                identity: identity,
                                displayName: displayName,
                                family: family,
                                actionIdentity: package.entrypoints.first(where: {
                                    $0.kind == .appIntent && $0.runtimeProfile == .scriptingJSC
                                }).map {
                                    .init(
                                        installedPackageID: package.record.installedPackageID,
                                        packageID: package.record.packageID,
                                        generation: package.record.activeGeneration,
                                        entrypointID: $0.id
                                    )
                                },
                                validUntil: max(presentation.reloadDate ?? Date.now.addingTimeInterval(900), minimumRefresh),
                                root: presentation.root
                            ))
                        }
                    } else {
                        let registrations = try {
                            let session = try HanlinScriptingApplicationSession(
                                installedPackageID: package.record.installedPackageID,
                                canonicalAppID: package.appID,
                                program: program,
                                filename: compiledPath,
                                entrypointContext: .appIntentRegistration,
                                storageAllowed: true,
                                filesAllowed: true,
                                packageSourceDirectory: artifactRoot.appending(path: "source", directoryHint: .isDirectory)
                            )
                            defer { session.dispose() }
                            return session.appIntentRegistrations
                        }()
                        intentEntities.append(contentsOf: registrations.map {
                            .init(identity: identity, id: $0.name, displayName: $0.name, appID: package.appID)
                        })
                    }
                }
            } catch {
                let diag = Self.makePublicationDiagnostic(
                    for: package.record.installedPackageID,
                    phase: .hostPublishWidgetProgram,
                    error: error,
                    storeDiagnostic: extensionStore.lastDiagnostic
                )
                if package.hasWidgetEntrypoint {
                    packageDiagnostics[package.record.installedPackageID] = diag
                    failedWidgetPackageIDs.insert(package.record.installedPackageID)
                }
                Self.logger.error(
                    "extension-refresh package=\(package.record.installedPackageID.rawValue, privacy: .public) phase=artifact-resolution diag=\(diag.redactedReportString, privacy: .public)"
                )
            }
        }

        for provider in CompiledMiniAppExposureRegistry.all {
            let descriptor = provider.descriptor
            if let widgetEntrypoint = descriptor.entryPoints.first(where: { $0.kind == .widget }) {
                let widgetIdentity = try provider.identity(entrypoint: widgetEntrypoint)
                let intentIdentity = try descriptor.entryPoints
                    .first(where: { $0.kind == .appIntentBridge })
                    .map(provider.identity(entrypoint:))
                let displayName = descriptor.name.preferredValue(forLocale: Locale.current.identifier)
                for family in ["systemSmall", "systemMedium", "systemLarge", "systemExtraLarge"] {
                    do {
                        let rootNode = try await provider.widget(family)
                        widgets.append(.init(
                            identity: widgetIdentity,
                            displayName: displayName,
                            family: family,
                            actionIdentity: intentIdentity,
                            validUntil: .now.addingTimeInterval(900),
                            root: rootNode
                        ))
                    } catch {
                        Self.logger.info("Widget provider \(provider.descriptor.id.rawValue) did not produce widget for \(family): \(Self.safeMessage(error))")
                    }
                }
            }
            if let intentEntrypoint = descriptor.entryPoints.first(where: { $0.kind == .appIntentBridge }) {
                if !provider.intentNames.isEmpty {
                    let identity = try provider.identity(entrypoint: intentEntrypoint)
                    intentEntities.append(contentsOf: provider.intentNames.map {
                        .init(identity: identity, id: $0, displayName: $0, appID: descriptor.id)
                    })
                }
            }
        }

        let previousSnapshot: HanlinScriptExtensionSnapshot?
        do {
            previousSnapshot = try extensionStore.load()
        } catch {
            let diag = Self.makePublicationDiagnostic(
                for: nil,
                phase: .hostPublishSnapshot,
                error: error,
                storeDiagnostic: extensionStore.lastDiagnostic
            )
            lastWidgetStorageDiagnostic = diag
            for pkg in installedPackages where pkg.enabled && pkg.hasWidgetEntrypoint {
                packageDiagnostics[pkg.record.installedPackageID] = diag
            }
            widgetPublicationDiagnostics = packageDiagnostics
            throw error
        }

        if let previousSnapshot, !failedWidgetPackageIDs.isEmpty {
            let activeGenerations = Dictionary(
                uniqueKeysWithValues: installedPackages.map { ($0.record.installedPackageID, $0.record.activeGeneration) }
            )
            for existingWidget in previousSnapshot.widgets {
                let pkgID = existingWidget.identity.installedPackageID
                if failedWidgetPackageIDs.contains(pkgID),
                   activeGenerations[pkgID] == existingWidget.identity.generation,
                   !widgets.contains(where: { $0.identity == existingWidget.identity && $0.family == existingWidget.family }) {
                    widgets.append(existingWidget)
                }
            }
        }

        let newSnapshot: HanlinScriptExtensionSnapshot
        do {
            newSnapshot = try extensionStore.publishWidgetTemplates(
                widgets,
                intentEntities: intentEntities,
                translationApps: translationApps,
                nativePresentations: nativePresentations,
                installedPackageIDs: Set(installedPackages.map { $0.record.installedPackageID })
            )
        } catch {
            let diag = Self.makePublicationDiagnostic(
                for: nil,
                phase: .hostPublishSnapshot,
                error: error,
                storeDiagnostic: extensionStore.lastDiagnostic
            )
            lastWidgetStorageDiagnostic = diag
            for pkg in installedPackages where pkg.enabled && pkg.hasWidgetEntrypoint {
                packageDiagnostics[pkg.record.installedPackageID] = diag
            }
            widgetPublicationDiagnostics = packageDiagnostics
            throw error
        }

        await HanlinScriptWidgetLiveActivityController.reconcile(snapshot: newSnapshot)

        for package in installedPackages where package.enabled {
            let hasNativeWidget = package.entrypoints.contains {
                $0.kind == .widget && $0.widgetEngine != nil && $0.widgetEngine != .legacy
            }
            guard hasNativeWidget else { continue }
            let hasPublishedDefault = newSnapshot.widgetInstances.contains {
                $0.identity.installedPackageID == package.record.installedPackageID
                    && $0.identity.generation == package.record.activeGeneration
                    && $0.engine != .legacy
            }
            if !hasPublishedDefault, packageDiagnostics[package.record.installedPackageID] == nil {
                packageDiagnostics[package.record.installedPackageID] = HanlinWidgetStorageDiagnostic(
                    phase: .hostPublishSnapshot,
                    decisionPoint: .instancePublication,
                    relativePath: "Packages/\(package.record.installedPackageID.rawValue)/generations/\(package.record.activeGeneration)",
                    errorDomain: "HanlinWidgetPublication",
                    errorCode: 1,
                    summary: "Default widget instance was not published for active generation."
                )
            }
        }

        widgetPublicationDiagnostics = packageDiagnostics
        lastWidgetStorageDiagnostic = packageDiagnostics.values.first
        if previousSnapshot?.widgets != newSnapshot.widgets || previousSnapshot?.widgetInstances != newSnapshot.widgetInstances {
            WidgetCenter.shared.reloadTimelines(ofKind: HanlinWidgetActionExecutor.widgetKind)
            ControlCenter.shared.reloadControls(ofKind: HanlinScriptWidgetControlCatalog.buttonKind)
            ControlCenter.shared.reloadControls(ofKind: HanlinScriptWidgetControlCatalog.toggleKind)
        }
        if HanlinMiniAppSystemEntrypoints.isAvailableForCurrentProduct {
            await HanlinMiniAppSystemEntrypoints.shared.reconcile(packages: installedPackages, platform: self)
        }
        await publishCompactAgentConfig()
    }

    nonisolated static func makePublicationDiagnostic(
        for installedPackageID: HanlinInstalledPackageID?,
        phase: HanlinWidgetStorageDiagnostic.Phase,
        error: Error,
        storeDiagnostic: HanlinWidgetStorageDiagnostic?
    ) -> HanlinWidgetStorageDiagnostic {
        if let storeDiagnostic {
            return HanlinWidgetStorageDiagnostic(
                correlationID: storeDiagnostic.correlationID,
                phase: phase,
                decisionPoint: storeDiagnostic.decisionPoint,
                relativePath: storeDiagnostic.relativePath,
                failingComponentIndex: storeDiagnostic.failingComponentIndex,
                failingComponentName: storeDiagnostic.failingComponentName,
                errorDomain: storeDiagnostic.errorDomain,
                errorCode: storeDiagnostic.errorCode,
                posixErrno: storeDiagnostic.posixErrno,
                summary: storeDiagnostic.summary
            )
        }
        let nsError = error as NSError
        let relPath = installedPackageID.map { "Packages/\($0.rawValue)" } ?? "."
        return HanlinWidgetStorageDiagnostic(
            phase: phase,
            decisionPoint: .instancePublication,
            relativePath: relPath,
            errorDomain: nsError.domain,
            errorCode: nsError.code,
            summary: Self.safeMessage(error)
        )
    }

    func publishCompactAgentConfig() async {
        guard let applicationServices else { return }
        commitCompactAgentConfig(using: applicationServices)
    }

    /// A commit cannot suspend between checking the generation and writing its configuration.
    private func commitCompactAgentConfig(using applicationServices: any HanlinScriptingApplicationServices) {
        do {
            try applicationServices.publishCompactAgentConfig()
        } catch {
            Self.logger.error("Failed to publish compact agent config: \(Self.safeMessage(error), privacy: .public)")
        }
    }

    private func processPendingResumeCommands() async throws {
        guard !isTransferringProductData, shortcutPresentation == nil else { return }
        guard let invocationExecutor else { return }
        guard !isProcessingResumeCommands else {
            resumeDrainRequested = true
            return
        }
        isProcessingResumeCommands = true
        defer { isProcessingResumeCommands = false }
        repeat {
            resumeDrainRequested = false
            for command in pendingResumeCommands {
                let expiresAt = command.invocation.delivery?.expiresAt
                    ?? command.createdAt.addingTimeInterval(86_400)
                // Background Shortcuts owns its live intent invocation. A UI
                // foreground drain must never steal it or replay abandoned work.
                // Expired commands still reach the queue's terminal transition.
                if expiresAt > .now, command.invocation.delivery?.source == .shortcuts,
                   command.invocation.delivery?.canPresentUI == false,
                   !command.invocation.continueInForeground { continue }
                if expiresAt > .now,
                   let source = command.invocation.delivery?.source,
                   [.notification, .widget, .liveActivity].contains(source),
                   UIApplication.shared.applicationState != .active {
                    continue
                }
                if let package = installedPackages.first(where: {
                    $0.record.installedPackageID == command.invocation.identity.installedPackageID
                }), package.entrypoints.contains(where: {
                    $0.id == command.invocation.identity.entrypointID &&
                        ($0.kind == .spotlight || $0.kind == .capture)
                }), UIApplication.shared.applicationState != .active {
                    continue
                }
                // Leave unstarted work queued while the only NS VM is owned.
                // Expired records still reach the queue's terminal transition.
                if expiresAt > .now,
                   let package = installedPackages.first(where: {
                       $0.record.installedPackageID == command.invocation.identity.installedPackageID
                   }), package.entrypoints.contains(where: {
                       $0.id == command.invocation.identity.entrypointID && $0.runtimeProfile == .hanlinNativeScript
                   }), isExecutingHeadlessNativeScriptAction || (hasNativeScriptApplicationSession
                       && (command.invocation.delivery?.source == .share || activeApplicationID != package.record.installedPackageID)) {
                    continue
                }
                do {
                    let receipt = try await invocationExecutor.execute(command.id) { [weak self] command in
                        guard let self else { throw HanlinInvocationDispatchError(.needsForeground, .unavailableHost) }
                        return try await self.dispatchResumeCommand(command)
                    }
                    if receipt?.status.isTerminal == true {
                        HanlinInvocationSnippetIntent.reload()
                        pendingResumeCommands.removeAll { $0.id == command.id }
                    }
                } catch {
                    // Keep unresolved records and actual receipts; never acknowledge
                    // a failed write or persist runtime error text in the App Group.
                    Self.logger.error("Invocation delivery failed: \(command.id, privacy: .public)")
                }
            }
            if resumeDrainRequested { try reloadPendingResumeCommands() }
        } while resumeDrainRequested
    }

    private func validateForegroundHostAction(_ command: HanlinScriptResumeCommand) throws {
        guard let source = command.invocation.delivery?.source,
              source == .widget || source == .liveActivity else { return }
        guard UIApplication.shared.applicationState == .active, let extensionStore else {
            throw HanlinInvocationNotStarted()
        }
        if command.invocation.delivery?.widgetOrigin != nil || source == .widget {
            try HanlinWidgetHostActionExecutor.validateCurrentOrigin(command, store: extensionStore)
        } else {
            try HanlinWidgetHostActionExecutor.validateLiveActivityTarget(command, store: extensionStore)
        }
    }

    func dispatchResumeCommand(_ command: HanlinScriptResumeCommand) async throws -> HanlinValue {
        guard !isTransferringProductData else { throw HanlinProductTransferError.busy }
        activeStoreOperations += 1
        defer { activeStoreOperations -= 1 }
        guard let store else { throw HanlinInvocationDispatchError(.needsForeground, .unavailableHost) }
        installedPackages = try await store.restore()
        let identity = command.invocation.identity
        if command.invocation.delivery?.source == .notification {
            try HanlinNotificationInvocation.validateTarget(command, packages: installedPackages,
                                                             hostIsActive: UIApplication.shared.applicationState == .active)
        }
        try validateForegroundHostAction(command)
        if command.invocation.delivery?.source != .notification,
           let provider = CompiledMiniAppExposureRegistry.provider(packageID: identity.packageID) {
            guard let actionName = command.invocation.entityID,
                  let expectedInstalledID = try? provider.installedPackageID,
                  identity.installedPackageID == expectedInstalledID,
                  identity.generation == 0,
                  let intentEntrypoint = provider.descriptor.entryPoints.first(where: { $0.kind == .appIntentBridge }),
                  identity.entrypointID == intentEntrypoint.handler,
                  provider.intentNames.contains(actionName),
                  command.invocation.delivery == nil || command.invocation.delivery?.appID == provider.descriptor.id else {
                throw HanlinInvocationDispatchError(.stale, .invalidTarget)
            }
            let value = try await provider.performIntent(actionName, command.invocation.parameters)
            WidgetCenter.shared.reloadTimelines(ofKind: "com.hanlin.scripting.widget")
            return value
        }
        guard let package = installedPackages.first(where: {
            $0.record.installedPackageID == identity.installedPackageID && $0.record.packageID == identity.packageID
        }) else { throw HanlinInvocationDispatchError(.stale, .invalidTarget) }
        guard package.enabled else { throw HanlinInvocationDispatchError(.stale, .disabledPackage) }
        guard package.record.activeGeneration == identity.generation else {
            throw HanlinInvocationDispatchError(.stale, .staleGeneration)
        }
        guard command.invocation.delivery == nil || command.invocation.delivery?.appID == package.appID,
              let entrypoint = package.entrypoints.first(where: {
                  $0.id == identity.entrypointID && (command.invocation.delivery?.source == .share
                      ? ($0.kind == .app || $0.kind == .share) : ($0.kind == .appIntent || $0.kind == .translationUI || $0.kind == .spotlight || $0.kind == .capture))
              }),
              let actionName = command.invocation.entityID else {
            throw HanlinInvocationDispatchError(.failed, .unsupportedEntrypoint)
        }
        if entrypoint.runtimeProfile == .hanlinNativeScript || entrypoint.runtimeProfile == .hanlinExpo {
            Self.invocationPlatforms[command.id] = self
            defer {
                if Self.invocationPlatforms[command.id] === self {
                    Self.invocationPlatforms.removeValue(forKey: command.id)
                }
            }
            let cleanActionName = actionName.components(separatedBy: "::").last ?? actionName
            guard let targetID = (try? HanlinAppID(validating: package.manifest?.hanlinAppID ?? identity.packageID.rawValue))
                    ?? (try? HanlinAppID(validating: identity.packageID.rawValue)),
                  let actionID = try? HanlinActionID(validating: cleanActionName),
                  let descriptor = try? package.appDescriptor(),
                  let declaredAction = descriptor.actions.first(where: { $0.id == actionID }),
                  let capability = declaredAction.capabilities.first ?? (try? HanlinCapabilityID(validating: "inter-app.share")) else {
                throw HanlinInvocationDispatchError(.failed, .invalidTarget)
            }
            if let symbol = entrypoint.exportedSymbol, symbol != actionID.rawValue {
                throw HanlinInvocationDispatchError(.failed, .invalidTarget)
            }
            if (entrypoint.runtimePolicyID == "prepared-foreground-action-v1" ||
                entrypoint.kind == .spotlight || entrypoint.kind == .capture),
               declaredAction.handler != entrypoint.sourcePath {
                throw HanlinInvocationDispatchError(.failed, .invalidTarget)
            }
            if entrypoint.kind == .spotlight || entrypoint.kind == .capture {
                guard command.invocation.continueInForeground,
                      UIApplication.shared.applicationState == .active else { throw HanlinInvocationNotStarted() }
            }
            let parameters: HanlinValue
            let requestCapability: HanlinCapabilityID
            if command.invocation.delivery?.source == .share {
                guard declaredAction.handler == entrypoint.sourcePath,
                      let shareCapability = declaredAction.capabilities.first(where: { $0.rawValue == "inter-app.share" }) else {
                    throw HanlinInvocationDispatchError(.failed, .invalidTarget)
                }
                requestCapability = shareCapability
                parameters = try await ChavrusaShareInbox.shared.actionPayload(command)
            } else {
                requestCapability = capability
                parameters = command.invocation.parameters
            }
            // Preserve the one-isolate invariant. Queue policy must not start a
            // second NativeScript VM while another package owns the first.
            if entrypoint.runtimeProfile == .hanlinNativeScript {
                guard !hasNativeScriptApplicationSession || activeApplicationID == identity.installedPackageID,
                      !isExecutingHeadlessNativeScriptAction else {
                    throw HanlinInvocationNotStarted()
                }
                if command.invocation.delivery?.source == .share, hasNativeScriptApplicationSession {
                    throw HanlinInvocationNotStarted()
                }
                if command.invocation.continueInForeground, !hasNativeScriptApplicationSession,
                   let appEntry = package.entrypoints.first(where: {
                       $0.kind == .app && $0.runtimeProfile == .hanlinNativeScript
                   }), declaredAction.handler == appEntry.sourcePath {
                    guard !isLaunching else { throw HanlinInvocationNotStarted() }
                    await launch(identity.installedPackageID)
                    guard activeApplicationID == identity.installedPackageID,
                          activeNativeScriptController != nil else {
                        throw HanlinInvocationDispatchError(.needsForeground, .unavailableHost)
                    }
                    presentsForegroundAction = true
                }
            }
            await HanlinMiniAppHost.shared.refresh(installedPackages: installedPackages)
            // Refresh/foreground launch can suspend; recheck the originating
            // variant and published target before calling any package handler.
            try validateForegroundHostAction(command)
            if entrypoint.kind == .spotlight || entrypoint.kind == .capture {
                let latest = try await store.restore()
                guard latest.contains(where: { $0.record.installedPackageID == identity.installedPackageID &&
                    $0.record.packageID == identity.packageID && $0.enabled &&
                    $0.record.activeGeneration == identity.generation && $0.entrypoints.contains(entrypoint) }) else {
                    throw HanlinInvocationDispatchError(.stale, .staleGeneration)
                }
            }
            queuedNativeScriptAdmissions.insert(command.id)
            defer { queuedNativeScriptAdmissions.remove(command.id) }
            let response = try await HanlinMiniAppHost.shared.requestBroker.request(.init(
                id: command.id, caller: try HanlinAppID(validating: "hanlin.host"), target: targetID,
                action: actionID, capability: requestCapability, payload: parameters))
            WidgetCenter.shared.reloadTimelines(ofKind: "com.hanlin.scripting.widget")
            return response.value
        }
        let artifactRoot = try await store.activeArtifactURL(for: identity.installedPackageID)
        let compiledPath = try Self.compiledPath(for: entrypoint.sourcePath)
        let program = try String(contentsOf: artifactRoot.appending(path: compiledPath, directoryHint: .notDirectory), encoding: .utf8)
        let session = try HanlinScriptingApplicationSession(
            installedPackageID: identity.installedPackageID, canonicalAppID: package.appID,
            program: program, filename: compiledPath, entrypointContext: .appIntentRegistration,
            storageAllowed: true, filesAllowed: true,
            packageSourceDirectory: artifactRoot.appending(path: "source", directoryHint: .isDirectory))
        defer { session.dispose() }
        let value = try await session.invokeAppIntent(name: actionName, parameters: command.invocation.parameters) ?? .null
        if session.requestedWidgetReload {
            try await refreshExtensionSnapshot()
            WidgetCenter.shared.reloadTimelines(ofKind: "com.hanlin.scripting.widget")
        }
        return value
    }

    private func performSystemOperation(
        _ operation: String,
        payloadJSON: String
    ) async throws -> HanlinScriptingSystemResult {
        if operation.hasPrefix("miniapps."), let externalMiniAppOperation {
            return .string(try await externalMiniAppOperation(operation, payloadJSON))
        }
        guard payloadJSON.utf8.count <= 24 * 1_024 * 1_024,
              let data = payloadJSON.data(using: .utf8),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HanlinScriptingPlatformError.invalidSystemServicePayload
        }
        let pasteboard = UIPasteboard.general
        switch operation {
        case "pasteboard.changeCount": return .integer(pasteboard.changeCount)
        case "pasteboard.hasStrings": return .bool(pasteboard.hasStrings)
        case "pasteboard.hasImages": return .bool(pasteboard.hasImages)
        case "pasteboard.hasURLs": return .bool(pasteboard.hasURLs)
        case "pasteboard.numberOfItems": return .integer(pasteboard.numberOfItems)
        case "pasteboard.getString": return .string(pasteboard.string)
        case "pasteboard.getStrings": return .strings(pasteboard.strings)
        case "pasteboard.getURL": return .string(pasteboard.url?.absoluteString)
        case "pasteboard.getURLs": return .strings(pasteboard.urls?.map(\.absoluteString))
        case "pasteboard.getImage":
            return .string(try pasteboard.image.map(Self.encodedPasteboardImage)?.base64EncodedString())
        case "pasteboard.getImages":
            return .strings(try pasteboard.images?.prefix(16).map {
                try Self.encodedPasteboardImage($0).base64EncodedString()
            })
        case "pasteboard.setString":
            pasteboard.string = try Self.optionalBoundedString(payload["value"], limit: 1_048_576)
            return .null
        case "pasteboard.setStrings":
            pasteboard.strings = try Self.optionalBoundedStrings(payload["value"])
            return .null
        case "pasteboard.setURL":
            pasteboard.url = try Self.optionalURL(payload["value"])
            return .null
        case "pasteboard.setURLs":
            pasteboard.urls = try Self.optionalURLs(payload["value"])
            return .null
        case "pasteboard.setImage":
            pasteboard.image = try Self.optionalPasteboardImage(payload["value"])
            return .null
        case "pasteboard.setImages":
            guard let values = payload["values"] else {
                pasteboard.images = nil
                return .null
            }
            guard let values = values as? [Any], values.count <= 16 else {
                throw HanlinScriptingPlatformError.invalidSystemServicePayload
            }
            var totalBytes = 0
            pasteboard.images = try values.map { value in
                guard let encoded = value as? String,
                      encoded.utf8.count <= 24 * 1_024 * 1_024,
                      let data = Data(base64Encoded: encoded) else {
                    throw HanlinScriptingPlatformError.invalidSystemServicePayload
                }
                totalBytes += data.count
                guard totalBytes <= 16 * 1_024 * 1_024, let image = UIImage(data: data) else {
                    throw HanlinScriptingPlatformError.invalidSystemServicePayload
                }
                return image
            }
            return .null
        case "pasteboard.addItems":
            pasteboard.addItems(try Self.pasteboardItems(from: payload["items"]))
            return .null
        case "pasteboard.setItems":
            let items = try Self.pasteboardItems(from: payload["items"])
            var options: [UIPasteboard.OptionsKey: Any] = [:]
            if let localOnly = try Self.optionalBoolean(payload["localOnly"]) {
                options[.localOnly] = localOnly
            }
            if let milliseconds = try Self.optionalFiniteNumber(payload["expirationMilliseconds"]) {
                options[.expirationDate] = Date(timeIntervalSince1970: milliseconds / 1_000)
            }
            pasteboard.setItems(items, options: options)
            return .null
        case "pasteboard.getItems":
            return .pasteboardItems(try Self.encodedPasteboardItems(pasteboard.items))
        case "safari.openURL":
            guard let urlString = try Self.optionalBoundedString(payload["url"], limit: 8_192),
                  let url = URL(string: urlString), url.scheme != nil else {
                throw HanlinScriptingPlatformError.invalidSystemServicePayload
            }
            return .bool(await UIApplication.shared.open(url, options: [:]))
        default:
            throw HanlinScriptingPlatformError.invalidSystemServicePayload
        }
    }

    private static func encodeJPEG(_ encodedImage: Data, compressionQuality: Double) throws -> Data {
        guard let image = UIImage(data: encodedImage),
              let data = image.jpegData(compressionQuality: compressionQuality) else {
            throw HanlinScriptingNativeError(
                name: "Error", code: "image_encoding_failed",
                message: "The image could not be encoded as JPEG."
            )
        }
        return data
    }

    private static func encodedPasteboardImage(_ image: UIImage) throws -> Data {
        guard let data = image.pngData(), data.count <= 16 * 1_024 * 1_024 else {
            throw HanlinScriptingPlatformError.invalidSystemServicePayload
        }
        return data
    }

    private static func optionalPasteboardImage(_ value: Any?) throws -> UIImage? {
        guard let value, !(value is NSNull) else { return nil }
        guard let encoded = value as? String,
              encoded.utf8.count <= 24 * 1_024 * 1_024,
              let data = Data(base64Encoded: encoded), data.count <= 16 * 1_024 * 1_024,
              let image = UIImage(data: data) else {
            throw HanlinScriptingPlatformError.invalidSystemServicePayload
        }
        return image
    }

    private static func pasteboardItems(from value: Any?) throws -> [[String: Any]] {
        guard let wireItems = value as? [Any], wireItems.count <= 64 else {
            throw HanlinScriptingPlatformError.invalidSystemServicePayload
        }
        var totalBytes = 0
        return try wireItems.map { wireItem in
            guard let representations = wireItem as? [String: Any], representations.count <= 64 else {
                throw HanlinScriptingPlatformError.invalidSystemServicePayload
            }
            return try representations.reduce(into: [String: Any]()) { item, entry in
                let identifier = entry.key
                guard !identifier.isEmpty, identifier.utf8.count <= 512, !identifier.contains("\0"),
                      let wireValue = entry.value as? [String: Any],
                      let kind = wireValue["kind"] as? String,
                      let encodedValue = wireValue["value"] as? String else {
                    throw HanlinScriptingPlatformError.invalidSystemServicePayload
                }
                switch kind {
                case "string":
                    let byteCount = encodedValue.utf8.count
                    guard byteCount <= 1_048_576 else {
                        throw HanlinScriptingPlatformError.invalidSystemServicePayload
                    }
                    totalBytes += byteCount
                    item[identifier] = encodedValue
                case "data", "image":
                    guard encodedValue.utf8.count <= 24 * 1_024 * 1_024,
                          let data = Data(base64Encoded: encodedValue) else {
                        throw HanlinScriptingPlatformError.invalidSystemServicePayload
                    }
                    totalBytes += data.count
                    if kind == "image" {
                        guard let image = UIImage(data: data) else {
                            throw HanlinScriptingPlatformError.invalidSystemServicePayload
                        }
                        item[identifier] = image
                    } else {
                        item[identifier] = data
                    }
                default:
                    throw HanlinScriptingPlatformError.invalidSystemServicePayload
                }
                guard totalBytes <= 16 * 1_024 * 1_024 else {
                    throw HanlinScriptingPlatformError.invalidSystemServicePayload
                }
            }
        }
    }

    private static func encodedPasteboardItems(
        _ items: [[String: Any]]
    ) throws -> [HanlinScriptingPasteboardItem] {
        guard items.count <= 64 else {
            throw HanlinScriptingPlatformError.invalidSystemServicePayload
        }
        var totalBytes = 0
        return try items.map { item in
            guard item.count <= 64 else {
                throw HanlinScriptingPlatformError.invalidSystemServicePayload
            }
            var representations: [String: HanlinScriptingPasteboardItem.Representation] = [:]
            for (identifier, value) in item {
                guard !identifier.isEmpty, identifier.utf8.count <= 512, !identifier.contains("\0") else {
                    throw HanlinScriptingPlatformError.invalidSystemServicePayload
                }
                let representation: HanlinScriptingPasteboardItem.Representation?
                if let string = value as? String {
                    let byteCount = string.utf8.count
                    guard byteCount <= 1_048_576 else {
                        throw HanlinScriptingPlatformError.invalidSystemServicePayload
                    }
                    totalBytes += byteCount
                    representation = .string(string)
                } else if let image = value as? UIImage {
                    let data = try encodedPasteboardImage(image)
                    totalBytes += data.count
                    representation = .image(data)
                } else if let data = value as? Data {
                    totalBytes += data.count
                    representation = .data(data)
                } else if let url = value as? URL {
                    let string = url.absoluteString
                    totalBytes += string.utf8.count
                    representation = .string(string)
                } else {
                    representation = nil
                }
                guard totalBytes <= 16 * 1_024 * 1_024 else {
                    throw HanlinScriptingPlatformError.invalidSystemServicePayload
                }
                if let representation { representations[identifier] = representation }
            }
            return HanlinScriptingPasteboardItem(representations: representations)
        }
    }

    private static func optionalBoolean(_ value: Any?) throws -> Bool? {
        if value == nil || value is NSNull { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw HanlinScriptingPlatformError.invalidSystemServicePayload
        }
        return number.boolValue
    }

    private static func optionalFiniteNumber(_ value: Any?) throws -> Double? {
        if value == nil || value is NSNull { return nil }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else {
            throw HanlinScriptingPlatformError.invalidSystemServicePayload
        }
        return number.doubleValue
    }

    nonisolated private static func optionalBoundedString(_ value: Any?, limit: Int) throws -> String? {
        if value == nil || value is NSNull { return nil }
        guard let value = value as? String, value.utf8.count <= limit, !value.contains("\0") else {
            throw HanlinScriptingPlatformError.invalidSystemServicePayload
        }
        return value
    }

    nonisolated private static func optionalBoundedStrings(_ value: Any?) throws -> [String]? {
        if value == nil || value is NSNull { return nil }
        guard let values = value as? [Any], values.count <= 128 else {
            throw HanlinScriptingPlatformError.invalidSystemServicePayload
        }
        return try values.map {
            guard let value = try optionalBoundedString($0, limit: 1_048_576) else {
                throw HanlinScriptingPlatformError.invalidSystemServicePayload
            }
            return value
        }
    }

    nonisolated private static func optionalURL(_ value: Any?) throws -> URL? {
        guard let string = try optionalBoundedString(value, limit: 8_192) else { return nil }
        guard let url = URL(string: string), url.scheme != nil else {
            throw HanlinScriptingPlatformError.invalidSystemServicePayload
        }
        return url
    }

    nonisolated private static func optionalURLs(_ value: Any?) throws -> [URL]? {
        guard let strings = try optionalBoundedStrings(value) else { return nil }
        return try strings.map {
            guard $0.utf8.count <= 8_192, let url = URL(string: $0), url.scheme != nil else {
                throw HanlinScriptingPlatformError.invalidSystemServicePayload
            }
            return url
        }
    }

    private func performLocation(
        _ request: HanlinScriptingLocationRequest
    ) async throws -> HanlinScriptingLocationResult {
        switch request.action {
        case .requestCurrent:
            let value = try await locationService.currentLocation(forceRequest: request.forceRequest)
            return .location(Self.scriptingLocation(value))
        case .geocodeAddress:
            guard let address = request.address else {
                throw HanlinScriptingPlatformError.invalidLocationPayload
            }
            let values = try await locationService.geocodeAddress(
                address,
                localeIdentifier: request.localeIdentifier
            )
            return .placemarks(values.map(Self.scriptingPlacemark))
        case .reverseGeocode:
            guard let latitude = request.latitude, let longitude = request.longitude else {
                throw HanlinScriptingPlatformError.invalidLocationPayload
            }
            let values = try await locationService.reverseGeocode(
                latitude: latitude,
                longitude: longitude,
                localeIdentifier: request.localeIdentifier
            )
            return .placemarks(values.map(Self.scriptingPlacemark))
        case .setAccuracy:
            guard let accuracy = request.accuracy else {
                throw HanlinScriptingPlatformError.invalidLocationPayload
            }
            try locationService.setAccuracy(accuracy)
            return .success
        }
    }

    func performAssistant(
        _ request: HanlinScriptingAssistantRequest
    ) async throws -> AsyncThrowingStream<HanlinScriptingAssistantChunk, Error> {
        guard let applicationServices else {
            throw HanlinScriptingNativeError(
                name: "Error",
                code: "assistant_configuration_unavailable",
                message: "The Assistant configuration is unavailable."
            )
        }
        return try await applicationServices.loadAssistant(request)
    }

    private func performHealthStatistics(
        _ request: HanlinScriptingHealthStatisticsRequest
    ) async throws -> HanlinScriptingHealthStatisticsResult? {
        let metric: HanlinScriptHealthMetric = switch request.metric {
        case .stepCount: .steps
        case .distanceWalkingRunning: .walkingRunningDistance
        case .activeEnergyBurned: .activeEnergy
        case .heartRate: .heartRate
        }
        let options = Set(request.options.map { option -> HanlinScriptHealthStatisticsOption in
            switch option {
            case .cumulativeSum: .cumulativeSum
            case .discreteAverage: .discreteAverage
            }
        })
        guard let result = try await healthService.statistics(
            metric,
            from: request.startDate,
            to: request.endDate,
            options: options
        ) else { return nil }
        return .init(
            metric: request.metric,
            unit: result.unit,
            startDate: result.startDate,
            endDate: result.endDate,
            sum: result.sum,
            average: result.average
        )
    }

    private func performHealthActivitySummaries(
        _ request: HanlinScriptingHealthActivitySummariesRequest
    ) async throws -> [HanlinScriptingHealthActivitySummaryResult] {
        let start = Self.dateComponents(request.startComponents)
        let end = Self.dateComponents(request.endComponents)
        return try await healthService.activitySummaries(from: start, to: end).map { value in
            .init(
                dateComponents: value.dateComponents,
                activityMoveMode: value.activityMoveMode,
                activeEnergyBurned: value.activeEnergyBurned,
                activeEnergyBurnedGoal: value.activeEnergyBurnedGoal,
                appleMoveTime: value.appleMoveTime,
                appleMoveTimeGoal: value.appleMoveTimeGoal,
                appleExerciseTime: value.appleExerciseTime,
                appleExerciseTimeGoal: value.appleExerciseTimeGoal,
                appleStandHours: value.appleStandHours,
                appleStandHoursGoal: value.appleStandHoursGoal
            )
        }
    }

    private func performHealthWorkouts(
        _ request: HanlinScriptingHealthWorkoutsRequest
    ) async throws -> [HanlinScriptingHealthWorkoutResult] {
        try await healthService.workouts(
            from: request.startDate,
            to: request.endDate,
            limit: request.limit,
            reversed: request.reversed
        ).map { workout in
            var statistics: [HanlinScriptingHealthMetric: HanlinScriptingHealthStatisticsResult] = [:]
            for (metric, value) in workout.statistics {
                let runtimeMetric = Self.runtimeHealthMetric(metric)
                statistics[runtimeMetric] = .init(
                    metric: runtimeMetric,
                    unit: value.unit,
                    startDate: value.startDate,
                    endDate: value.endDate,
                    sum: value.sum,
                    average: value.average
                )
            }
            return .init(
                uuid: workout.uuid,
                workoutActivityType: workout.workoutActivityType,
                startDate: workout.startDate,
                endDate: workout.endDate,
                duration: workout.duration,
                statistics: statistics
            )
        }
    }

    private static func dateComponents(_ values: [String: Int]) -> DateComponents {
        var components = DateComponents()
        components.calendar = .current
        components.era = values["era"]
        components.year = values["year"]
        components.month = values["month"]
        components.day = values["day"]
        return components
    }

    private static func runtimeHealthMetric(
        _ metric: HanlinScriptHealthMetric
    ) -> HanlinScriptingHealthMetric {
        switch metric {
        case .steps: .stepCount
        case .walkingRunningDistance: .distanceWalkingRunning
        case .activeEnergy: .activeEnergyBurned
        case .heartRate: .heartRate
        }
    }

    private func performNotification(
        _ request: HanlinScriptingNotificationRequest,
        installedPackageID: HanlinInstalledPackageID
    ) async throws -> Bool {
        let identifierPrefix = "hanlin.\(installedPackageID.rawValue)."
        switch request.action {
        case .removeAllPendingsOfCurrentScript:
            await notificationService.removePending(identifierPrefix: identifierPrefix)
            return true
        case .schedule:
            guard let title = request.title, let trigger = request.trigger else {
                throw HanlinScriptingPlatformError.invalidNotificationPayload
            }
            let nativeTrigger: HanlinScriptLocalNotificationTrigger = switch trigger {
            case .immediate:
                .immediate
            case let .timeInterval(seconds, repeats):
                .timeInterval(seconds: seconds, repeats: repeats)
            case let .calendar(components, timeZoneIdentifier, repeats):
                .calendar(
                    components: components,
                    timeZoneIdentifier: timeZoneIdentifier,
                    repeats: repeats
                )
            }
            try await notificationService.schedule(.init(
                id: identifierPrefix + UUID().uuidString.lowercased(),
                title: title,
                subtitle: request.subtitle ?? "",
                body: request.body ?? "",
                badge: request.badge,
                silent: request.silent,
                interruptionLevel: request.interruptionLevel,
                threadIdentifier: request.threadIdentifier ?? "",
                userInfoJSON: request.userInfoJSON,
                trigger: nativeTrigger
            ))
            return true
        }
    }

    private func performReminder(
        _ request: HanlinScriptingReminderRequest
    ) async throws -> HanlinScriptingReminderResult {
        switch request {
        case let .save(value):
            return .identifier(try await calendarService.saveReminder(
                identifier: value.identifier,
                calendarIdentifier: value.calendarIdentifier,
                title: value.title,
                notes: value.notes,
                priority: value.priority,
                isCompleted: value.isCompleted,
                completionDate: value.completionDateMilliseconds.map {
                    Date(timeIntervalSince1970: $0 / 1_000)
                },
                dueDateComponentValues: value.dueDateComponents,
                timeZoneIdentifier: value.timeZoneIdentifier
            ))
        case let .remove(identifier):
            try await calendarService.removeReminder(identifier: identifier)
            return .completed
        case let .get(identifier):
            return .reminder(try await calendarService.reminder(identifier: identifier).map(Self.scriptingReminder))
        case let .fetch(query):
            let completed: Bool? = switch query.kind {
            case .all: nil
            case .incomplete: false
            case .completed: true
            }
            let values = try await calendarService.reminders(
                completed: completed,
                startDate: query.startMilliseconds.map { Date(timeIntervalSince1970: $0 / 1_000) },
                endDate: query.endMilliseconds.map { Date(timeIntervalSince1970: $0 / 1_000) },
                calendarIdentifiers: query.calendarIdentifiers
            )
            return .reminders(values.map(Self.scriptingReminder))
        case .calendars:
            return .calendars(try await calendarService.reminderCalendars().map(Self.scriptingCalendar))
        case .defaultCalendar:
            return .calendar(try await calendarService.defaultReminderCalendar().map(Self.scriptingCalendar))
        }
    }

    private static func scriptingCalendar(_ value: HanlinScriptReminderCalendar) -> HanlinScriptingCalendarValue {
        .init(identifier: value.identifier, title: value.title, type: value.type,
              allowsContentModifications: value.allowsContentModifications)
    }

    private static func scriptingReminder(_ value: HanlinScriptReminderItem) -> HanlinScriptingReminderValue {
        .init(
            identifier: value.identifier, calendar: scriptingCalendar(value.calendar),
            title: value.title, notes: value.notes, priority: value.priority,
            isCompleted: value.isCompleted,
            completionDateMilliseconds: value.completionDate.map { $0.timeIntervalSince1970 * 1_000 },
            dueDateComponents: value.dueDateComponentValues,
            timeZoneIdentifier: value.timeZoneIdentifier
        )
    }

    private static func scriptingLocation(
        _ value: HanlinScriptLocationValue
    ) -> HanlinScriptingLocationInfo {
        .init(
            latitude: value.latitude,
            longitude: value.longitude,
            timestampMilliseconds: value.timestamp.timeIntervalSince1970 * 1_000
        )
    }

    private static func scriptingPlacemark(
        _ value: HanlinScriptPlacemarkValue
    ) -> HanlinScriptingLocationPlacemark {
        .init(
            location: scriptingLocation(value.location),
            timeZoneIdentifier: value.timeZoneIdentifier,
            name: value.name,
            locality: value.locality,
            isoCountryCode: value.isoCountryCode,
            country: value.country
        )
    }

    /// Shared ActivityKit adapter for active Expo and NativeScript sessions.
    /// The native system owns scheduling and presentation; this returns its real
    /// identifiers/results and uses the existing extension renderer.
    func invokeLiveActivity(
        operation: String, payloadJSON: String, context: HanlinHostCallContext
    ) async throws -> String {
#if os(iOS)
        guard let installedID = context.installedPackageID, let appID = context.appID, let store,
              let package = try await store.snapshots().first(where: {
                  $0.record.installedPackageID == installedID && $0.appID == appID && $0.enabled
              }) else {
            throw HanlinHostServiceError.invalidRequest("The MiniApp session is no longer installed.")
        }
        func encoded(_ value: [String: Any]) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
        }
        if operation == "liveActivities.areEnabled" {
            return try encoded(["enabled": HanlinScriptLiveActivityController.areActivitiesEnabled])
        }
        if operation == "liveActivities.list" {
            return try encoded(["activityIDs": HanlinScriptLiveActivityController.activityIDs(installedPackageID: installedID.rawValue) + HanlinScriptWidgetLiveActivityController.activityIDs(installedPackageID: installedID.rawValue)])
        }
        guard ["liveActivities.start", "liveActivities.update", "liveActivities.end"].contains(operation),
              let payload = try JSONSerialization.jsonObject(with: Data(payloadJSON.utf8)) as? [String: Any] else {
            throw HanlinHostServiceError.invalidRequest("Unknown Live Activity operation or invalid JSON payload.")
        }
        func finiteNumber(_ name: String) throws -> Double? {
            guard let value = payload[name] else { return nil }
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite else {
                throw HanlinHostServiceError.invalidRequest("\(name) must be a finite number.")
            }
            return number.doubleValue
        }
        let activityID = payload["activityID"] as? String
        let startsOriginal = operation == "liveActivities.start" &&
            (payload["scriptWidgetEntrypointID"] != nil || payload["widgetInstanceID"] != nil)
        let updatesOriginal = activityID.map {
            HanlinScriptWidgetLiveActivityController.contains(systemActivityID: $0, installedPackageID: installedID.rawValue)
        } ?? false
        if startsOriginal || updatesOriginal {
            guard let extensionStore else { throw HanlinScriptExtensionStoreError.appGroupUnavailable }
            var values: [String: HanlinValue] = [:]
            if let supplied = payload["state"] {
                guard let dictionary = supplied as? [String: Any] else {
                    throw HanlinHostServiceError.invalidRequest("A ScriptWidget Live Activity state must be a JSON object.")
                }
                values = try dictionary.mapValues(ExpoHostServicesAdapter.toHanlinValue)
            }
            let staleDate = try finiteNumber("staleDateEpochMilliseconds").map { Date(timeIntervalSince1970: $0 / 1_000) }
            let relevance = try finiteNumber("relevanceScore") ?? 0
            if startsOriginal {
                let requestedEntrypoint = payload["scriptWidgetEntrypointID"] as? String
                let requestedInstance = payload["widgetInstanceID"] as? String
                guard let snapshot = try extensionStore.load(),
                      let instance = snapshot.widgetInstances.first(where: { instance in
                          instance.identity.installedPackageID == installedID && instance.engine == .scriptwidget &&
                          instance.identity.generation == package.record.activeGeneration &&
                          (requestedEntrypoint == nil || instance.identity.entrypointID == requestedEntrypoint) &&
                          (requestedInstance.map { $0 == instance.entityID } ?? instance.isDefault)
                      }) else {
                    throw HanlinHostServiceError.invalidRequest("The package does not have that installed ScriptWidget entrypoint or instance.")
                }
                let family = payload["family"] as? String ?? snapshot.widgets.first {
                    $0.identity == instance.identity && $0.engine == .scriptwidget
                }?.family ?? "systemMedium"
                let id = try await HanlinScriptWidgetLiveActivityController.start(
                    store: extensionStore, entityID: instance.entityID, family: family,
                    title: payload["title"] as? String ?? package.manifest?.name ?? "MiniApp",
                    values: values, staleDate: staleDate, relevanceScore: relevance)
                return try encoded(["activityID": id])
            }
            if operation == "liveActivities.update" {
                let updated = try await HanlinScriptWidgetLiveActivityController.update(
                    store: extensionStore, systemActivityID: activityID!, installedPackageID: installedID.rawValue,
                    title: payload["title"] as? String, values: values, staleDate: staleDate, relevanceScore: relevance)
                return try encoded(["ok": updated])
            }
            let ended = try await HanlinScriptWidgetLiveActivityController.end(
                store: extensionStore, systemActivityID: activityID!, installedPackageID: installedID.rawValue,
                title: payload["title"] as? String, values: values, dismissAfterSeconds: try finiteNumber("dismissAfterSeconds"))
            return try encoded(["ok": ended])
        }
        let previous = activityID.flatMap {
            HanlinScriptLiveActivityController.contentState(systemActivityID: $0, installedPackageID: installedID.rawValue)
        }
        if operation != "liveActivities.start", previous == nil {
            return try encoded(["ok": false])
        }
        let root: HanlinScriptUINode
        if let supplied = payload["root"] as? [String: Any] {
            root = try ExpoHostServicesAdapter.parseUntaggedNode(supplied)
        } else if let previous {
            root = previous.root
        } else {
            throw HanlinHostServiceError.invalidRequest("Starting a Live Activity requires its native root layout.")
        }
        let state = try payload["state"].map(ExpoHostServicesAdapter.toHanlinValue) ?? previous?.state ?? .null
        let title = payload["title"] as? String ?? previous?.title ?? package.manifest?.name ?? "MiniApp"
        let content = HanlinGenericLiveActivityAttributes.ContentState(
            revision: (previous?.revision ?? 0) + 1, title: title, state: state, root: root)
        let staleDate = try finiteNumber("staleDateEpochMilliseconds").map { Date(timeIntervalSince1970: $0 / 1_000) }
        let relevance = try finiteNumber("relevanceScore") ?? 0
        switch operation {
        case "liveActivities.start":
            let requestedEntrypoint = payload["actionEntrypointID"] as? String
            let actionEntrypoint = package.entrypoints.first {
                $0.kind == .appIntent && (requestedEntrypoint == nil || $0.id == requestedEntrypoint)
            }
            if requestedEntrypoint != nil, actionEntrypoint == nil {
                throw HanlinHostServiceError.invalidRequest("The package does not declare that Live Activity action entrypoint.")
            }
            let identity = actionEntrypoint.map {
                HanlinScriptExtensionIdentity(installedPackageID: installedID,
                    packageID: package.record.packageID, generation: package.record.activeGeneration, entrypointID: $0.id)
            }
            let id = try HanlinScriptLiveActivityController.start(
                attributes: .init(installedPackageID: installedID.rawValue, activityID: UUID().uuidString,
                                  actionIdentity: identity),
                state: content, staleDate: staleDate, relevanceScore: relevance)
            return try encoded(["activityID": id])
        case "liveActivities.update":
            let updated = await HanlinScriptLiveActivityController.update(
                systemActivityID: activityID!, installedPackageID: installedID.rawValue,
                state: content, staleDate: staleDate, relevanceScore: relevance)
            return try encoded(["ok": updated])
        default:
            let ended = await HanlinScriptLiveActivityController.end(
                systemActivityID: activityID!, installedPackageID: installedID.rawValue,
                finalState: content, dismissTimeInterval: try finiteNumber("dismissAfterSeconds"))
            return try encoded(["ok": ended])
        }
#else
        throw HanlinHostServiceError.invalidRequest("Live Activities are unavailable on this platform.")
#endif
    }

    private func performLiveActivity(
        _ request: HanlinScriptingLiveActivityRequest,
        installedPackageID: HanlinInstalledPackageID
    ) async throws -> HanlinScriptingLiveActivityResult {
#if os(iOS)
        if request.action == .areActivitiesEnabled {
            return .success(HanlinScriptLiveActivityController.areActivitiesEnabled)
        }
        guard let root = request.root, let stateJSON = request.stateJSON else {
            throw HanlinScriptingPlatformError.invalidLiveActivityPayload
        }
        let state = try HanlinValue(jsonValue: HanlinJSONValue.decodeCanonicalJSON(stateJSON))
        let title = request.name ?? "Live Activity"
        switch request.action {
        case .start:
            let logicalID = UUID().uuidString.lowercased()
            let content = HanlinGenericLiveActivityAttributes.ContentState(
                revision: 1, title: title, state: state, root: root
            )
            let systemID = try HanlinScriptLiveActivityController.start(
                attributes: .init(installedPackageID: installedPackageID.rawValue, activityID: logicalID),
                state: content,
                staleDate: request.staleDate,
                relevanceScore: request.relevanceScore ?? 0
            )
            liveActivityRevisions[systemID] = 1
            return .started(activityID: systemID)
        case .update:
            guard let activityID = request.activityID else {
                throw HanlinScriptingPlatformError.invalidLiveActivityPayload
            }
            let revision = (liveActivityRevisions[activityID] ?? 0) + 1
            let success = await HanlinScriptLiveActivityController.update(
                systemActivityID: activityID,
                state: .init(revision: revision, title: title, state: state, root: root),
                staleDate: request.staleDate,
                relevanceScore: request.relevanceScore ?? 0
            )
            if success { liveActivityRevisions[activityID] = revision }
            return .success(success)
        case .end:
            guard let activityID = request.activityID else {
                throw HanlinScriptingPlatformError.invalidLiveActivityPayload
            }
            let revision = (liveActivityRevisions[activityID] ?? 0) + 1
            let success = await HanlinScriptLiveActivityController.end(
                systemActivityID: activityID,
                finalState: .init(revision: revision, title: title, state: state, root: root),
                dismissTimeInterval: request.dismissTimeInterval
            )
            if success { liveActivityRevisions[activityID] = nil }
            return .success(success)
        case .areActivitiesEnabled:
            return .success(HanlinScriptLiveActivityController.areActivitiesEnabled)
        }
#else
        _ = installedPackageID
        throw HanlinScriptingPlatformError.invalidLiveActivityPayload
#endif
    }

    nonisolated static func stablePackageID(for manifest: HanlinScriptingManifest) throws -> HanlinPackageID {
        if let explicitID = manifest.hanlinAppID {
            return try HanlinPackageID(validating: explicitID)
        }
        if case let .string(explicitID)? = manifest.unknownFields["hanlinAppID"] {
            return try HanlinPackageID(validating: explicitID)
        }
        let digest = SHA256.hash(data: Data(manifest.name.precomposedStringWithCanonicalMapping.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return try HanlinPackageID(validating: "script-\(digest.prefix(24))")
    }

    private static func applicationSupportDirectory() throws -> URL {
        guard let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw HanlinPackageCenterError.stagingFailed
        }
        return url.appending(path: "Hanlin", directoryHint: .isDirectory)
    }

    nonisolated private static func safeMessage(_ error: Error) -> String {
        if let storeError = error as? HanlinAtomicScriptStoreError,
           case .generationMetadataUnavailable = storeError {
            return String(localized: "This saved version is missing its launch metadata. Import that version's package again to restore it.", bundle: HanlinLocalization.bundle)
        }
        if let storageError = error as? HanlinScriptExtensionStoreError,
           storageError == .appGroupUnavailable {
            return String(localized: "Hanlin cannot access shared storage. This action is unavailable in this installation.", bundle: HanlinLocalization.bundle)
        }
        return String(String(describing: error).prefix(512))
    }

    nonisolated private static func compiledPath(for sourcePath: String) throws -> String {
        guard sourcePath.hasPrefix("source/"), !sourcePath.contains(".."), !sourcePath.contains("\\") else {
            throw HanlinScriptingPlatformError.invalidEntrypointPath
        }
        let relative = String(sourcePath.dropFirst("source/".count))
        guard let dot = relative.lastIndex(of: "."), dot > relative.startIndex else {
            throw HanlinScriptingPlatformError.invalidEntrypointPath
        }
        let extensionName = relative[relative.index(after: dot)...].lowercased()
        guard ["ts", "tsx", "js", "jsx"].contains(extensionName) else {
            throw HanlinScriptingPlatformError.invalidEntrypointPath
        }
        return "compiled/\(relative[..<dot]).js"
    }

    nonisolated private static func pythonSourceBundle(
        preview: HanlinImportPreview
    ) throws -> HanlinScriptingBundle {
        let metadata = try HanlinScriptingSDK.metadata()
        let optionsHash = SHA256.hash(data: Data("python-source-v1".utf8))
            .map { String(format: "%02x", $0) }.joined()
        let fingerprint = SHA256.hash(data: Data([
            preview.source.contentSHA256,
            "CPython-3.14.6",
            "200ef60eb67be0483ceb638daa9048f84f41a9a952707a5ad4c3198037c7b583",
            metadata.baselineID,
            metadata.baselineDigest,
            optionsHash,
        ].joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
        return .init(
            manifest: .init(
                compilerVersion: "CPython-3.14.6",
                compilerIntegrity: "200ef60eb67be0483ceb638daa9048f84f41a9a952707a5ad4c3198037c7b583",
                compilerOptionsHash: optionsHash,
                baselineID: metadata.baselineID,
                baselineDigest: metadata.baselineDigest,
                hanlinABIVersion: HanlinScriptContractSupport.multiRuntime.abiVersion.description,
                packageContentDigest: preview.source.contentSHA256,
                cacheFingerprint: fingerprint,
                files: []
            ),
            modules: [],
            diagnostics: []
        )
    }

    nonisolated private static func nativeScriptSourceBundle(
        preview: HanlinImportPreview
    ) throws -> HanlinScriptingBundle {
        let metadata = try HanlinScriptingSDK.metadata()
        let runtimeIdentity = "NativeScript-\(HanlinMiniAppHostVersions.nativeScriptRuntimeVersion)"
        let optionsHash = SHA256.hash(data: Data("nativescript-source-v1".utf8))
            .map { String(format: "%02x", $0) }.joined()
        let fingerprint = SHA256.hash(data: Data([
            preview.source.contentSHA256,
            runtimeIdentity,
            metadata.baselineID,
            metadata.baselineDigest,
            optionsHash,
        ].joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
        return .init(
            manifest: .init(
                compilerVersion: "\(runtimeIdentity)-prepared",
                compilerIntegrity: preview.source.contentSHA256,
                compilerOptionsHash: optionsHash,
                baselineID: metadata.baselineID,
                baselineDigest: metadata.baselineDigest,
                hanlinABIVersion: HanlinScriptContractSupport.multiRuntime.abiVersion.description,
                packageContentDigest: preview.source.contentSHA256,
                cacheFingerprint: fingerprint,
                files: []
            ),
            modules: [],
            diagnostics: []
        )
    }

    nonisolated private static func preparedSourceBundle(
        preview: HanlinImportPreview,
        compilerVersion: String
    ) throws -> HanlinScriptingBundle {
        let metadata = try HanlinScriptingSDK.metadata()
        let optionsHash = SHA256.hash(data: Data(compilerVersion.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let fingerprint = SHA256.hash(data: Data([
            preview.source.contentSHA256,
            compilerVersion,
            metadata.baselineID,
            metadata.baselineDigest,
            optionsHash,
        ].joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
        return .init(
            manifest: .init(
                compilerVersion: compilerVersion,
                compilerIntegrity: preview.source.contentSHA256,
                compilerOptionsHash: optionsHash,
                baselineID: metadata.baselineID,
                baselineDigest: metadata.baselineDigest,
                hanlinABIVersion: HanlinScriptContractSupport.multiRuntime.abiVersion.description,
                packageContentDigest: preview.source.contentSHA256,
                cacheFingerprint: fingerprint,
                files: []
            ),
            modules: [],
            diagnostics: []
        )
    }
}

private enum HanlinScriptingPlatformError: Error {
    case artifactEnumerationFailed
    case compiledEntrypointTooLarge
    case invalidEntrypointPath
    case invalidLiveActivityPayload
    case invalidLocationPayload
    case invalidNotificationPayload
    case invalidSystemServicePayload
}

private extension JSONEncoder {
    static var canonical: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
