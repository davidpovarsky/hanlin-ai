import Foundation
import HanlinMiniAppCore
import HanlinParityMiniApp
import HanlinPlatformContracts
import HanlinScriptStore
import HanlinProductSplit
import Observation
import SwiftUI

actor HanlinMiniAppAuthorizationPolicy {
    private var descriptors: [HanlinAppID: HanlinAppDescriptor] = [:]

    func replace(with items: [HanlinMiniAppCatalogItem]) {
        descriptors = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.descriptor) })
    }

    func authorize(_ request: HanlinMiniAppRequest) -> Bool {
        if request.caller.rawValue == "hanlin.host" {
            guard let target = descriptors[request.target] else { return false }
            let targetCapabilities = Set(target.capabilities.map(\.id))
            return targetCapabilities.contains(request.capability)
        }
        guard request.caller != request.target,
              let caller = descriptors[request.caller],
              let target = descriptors[request.target] else { return false }
        let callerCapabilities = Set(caller.capabilities.map(\.id))
        let targetCapabilities = Set(target.capabilities.map(\.id))
        return callerCapabilities.contains(request.capability)
            && targetCapabilities.contains(request.capability)
    }
}

@MainActor
@Observable
final class HanlinMiniAppHost {
    struct SwiftDestination: Identifiable {
        let id = UUID()
        let appID: HanlinAppID
        let view: AnyView
    }

    static let shared = HanlinMiniAppHost()

    private(set) var items: [HanlinMiniAppCatalogItem] = []
    private(set) var lastError: String?
    private(set) var hiddenAppIDs: Set<HanlinAppID> = []

    let dataStore: HanlinMiniAppDataStore
    let requestBroker: HanlinMiniAppRequestBroker
    private let authorization: HanlinMiniAppAuthorizationPolicy
    private let defaults: UserDefaults
    private let hiddenKey = "hanlin.canonical-mini-apps.hidden.v1"
    private var registeredRouteTargets: Set<HanlinAppID> = []

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        authorization = HanlinMiniAppAuthorizationPolicy()
        let policy = authorization
        requestBroker = HanlinMiniAppRequestBroker(limits: .personalHost) { request in
            await policy.authorize(request)
        }
        do {
            dataStore = try HanlinMiniAppDataStore(root: HanlinMiniAppDataStore.applicationSupportRoot())
        } catch {
            preconditionFailure("Canonical Mini App storage is unavailable: \(error)")
        }
        if let data = defaults.data(forKey: hiddenKey),
           let rawIDs = try? JSONDecoder().decode([String].self, from: data) {
            hiddenAppIDs = Set(rawIDs.compactMap(HanlinAppID.init(rawValue:)))
        }
        Task {
            await registerFallbackRoutes()
        }
    }

    public func registerFallbackRoutes() async {
        let broker = requestBroker
        let store = dataStore
        let currentTargets = Set(items.map(\.id))
        for target in registeredRouteTargets.union(currentTargets) {
            await broker.unregisterAll(target: target)
        }
        registeredRouteTargets = currentTargets
        let swiftParityID = SwiftParityMiniAppRegistration().appID
        registeredRouteTargets.insert(swiftParityID)
        await SwiftParityMiniAppSharing.register(on: broker,
            storage: HanlinMiniAppStorageContext(appID: swiftParityID, store: store))

        // NativeScript actions keep a stable broker route. The JavaScript bundle
        // registers its implementation with the active host provider; it never
        // replaces this authorization boundary.
        for item in items {
            let targetID = item.id
            let capabilities = Set(item.descriptor.capabilities.map(\.id))

            for action in item.descriptor.actions {
                guard action.handler != nil else { continue }
                for cap in action.capabilities {
                    guard capabilities.contains(cap) else { continue }
                    let actionID = action.id
                    await broker.register(target: targetID, action: actionID, capability: cap) { request in
                        return try await HanlinScriptingPlatform.shared.executeHeadlessAction(
                            caller: request.caller,
                            targetAppID: targetID,
                            action: actionID,
                            capability: cap,
                            payload: request.payload,
                            invocationID: request.id
                        )
                    }
                }
            }
        }
    }

    var visibleItems: [HanlinMiniAppCatalogItem] {
        items.filter { !hiddenAppIDs.contains($0.id) }
    }

    /// Use the same validated foreground launch contract as the canonical catalog.
    /// Discovery needs no host instance, global store or runtime initialization.
    static func packageDiscovery(installedPackages: [HanlinStoredPackageSnapshot]) -> HanlinScriptPackageDiscovery {
        let eligible = installedPackages.filter { package in
            guard package.enabled, package.hasLaunchableApp || package.entrypoints.isEmpty else { return false }
            if let runtime = package.manifest?.hanlinRuntime {
                guard HanlinRuntimeProfile(rawValue: runtime) != nil else { return false }
            } else if let runtime = package.manifest?.unknownFields["hanlinRuntime"] {
                guard case let .string(value) = runtime, HanlinRuntimeProfile(rawValue: value) != nil else { return false }
            }
            guard let descriptor = try? package.appDescriptor(),
                  (try? HanlinMiniAppLaunchPlan(descriptor: descriptor)) != nil else { return false }
            return true
        }
        return HanlinScriptPackageDiscovery(snapshots: eligible)
    }

    func authorize(_ request: HanlinMiniAppRequest) async -> Bool {
        await authorization.authorize(request)
    }

    func refresh(installedPackages: [HanlinStoredPackageSnapshot]) async {
        do {
            BuiltinCanonicalRegistrations.ensureRegistered()
            let discovery = HanlinCompositeMiniAppDiscovery(providers: [
                HanlinCompiledMiniAppDiscovery(),
                Self.packageDiscovery(installedPackages: installedPackages)
            ])
            let refreshed = try await HanlinCanonicalMiniAppCatalog(discovery: discovery).items()
            items = refreshed
            await authorization.replace(with: refreshed)
            await registerFallbackRoutes()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setHidden(_ hidden: Bool, appID: HanlinAppID) {
        if hidden { hiddenAppIDs.insert(appID) } else { hiddenAppIDs.remove(appID) }
        let values = hiddenAppIDs.map(\.rawValue).sorted()
        defaults.set(try? JSONEncoder().encode(values), forKey: hiddenKey)
    }

    func isHidden(_ appID: HanlinAppID) -> Bool { hiddenAppIDs.contains(appID) }

    func swiftDestination(for item: HanlinMiniAppCatalogItem) throws -> SwiftDestination {
        guard !HanlinScriptingPlatform.shared.isTransferringProductData else {
            throw HanlinProductTransferError.busy
        }
        let plan = try HanlinMiniAppLaunchPlan(descriptor: item.descriptor)
        guard plan.engine == .swift else {
            throw HanlinMiniAppCatalogError.unsupportedImplementation(item.id)
        }
        BuiltinCanonicalRegistrations.ensureRegistered()
        guard let provider = HanlinCompiledMiniAppRegistry.shared.provider(for: item.id) else {
            throw HanlinMiniAppCatalogError.unsupportedImplementation(item.id)
        }
        let store = dataStore
        let broker = requestBroker
        let context = HanlinMiniAppHostContext(
            appID: item.id,
            storage: HanlinMiniAppStorageContext(appID: item.id, store: store),
            requestBroker: broker,
            network: Self.fetchStatus,
            dismiss: {},
            requestWidgetRefresh: {
                Task { @MainActor in
                    try? await HanlinScriptingPlatform.shared.refreshExtensionSnapshot()
                }
            }
        )
        return SwiftDestination(
            appID: item.id,
            view: provider.makeRootView(context: context)
        )
    }

    func launchNativeScript(
        _ item: HanlinMiniAppCatalogItem,
        platform: HanlinScriptingPlatform
    ) async throws {
        let plan = try HanlinMiniAppLaunchPlan(descriptor: item.descriptor)
        guard plan.engine == .nativeScript else {
            throw HanlinMiniAppCatalogError.unsupportedImplementation(item.id)
        }
        guard case let .nativeScript(packageID) = item.descriptor.implementation,
              let package = platform.installedPackages.first(where: { $0.record.packageID == packageID }),
              package.enabled else {
            throw HanlinMiniAppCatalogError.unsupportedImplementation(item.id)
        }
        await platform.launch(package.record.installedPackageID)
    }

    func launchExpo(
        _ item: HanlinMiniAppCatalogItem,
        platform: HanlinScriptingPlatform
    ) async throws {
        let plan = try HanlinMiniAppLaunchPlan(descriptor: item.descriptor)
        guard plan.engine == .expo else {
            throw HanlinMiniAppCatalogError.unsupportedImplementation(item.id)
        }
        guard let package = platform.installedPackages.first(where: { $0.appID == item.id || $0.record.packageID.rawValue == item.id.rawValue }),
              package.enabled else {
            throw HanlinMiniAppCatalogError.unsupportedImplementation(item.id)
        }
        await platform.launch(package.record.installedPackageID)
    }

    func launchScriptingJSC(
        _ item: HanlinMiniAppCatalogItem,
        platform: HanlinScriptingPlatform
    ) async throws {
        let plan = try HanlinMiniAppLaunchPlan(descriptor: item.descriptor)
        guard plan.engine == .scriptingJSC else {
            throw HanlinMiniAppCatalogError.unsupportedImplementation(item.id)
        }
        guard let package = platform.installedPackages.first(where: { $0.appID == item.id || $0.record.packageID.rawValue == item.id.rawValue }),
              package.enabled else {
            throw HanlinMiniAppCatalogError.unsupportedImplementation(item.id)
        }
        await platform.launch(package.record.installedPackageID)
    }

    private static func fetchStatus(_ url: URL) async throws -> String {
        guard url.scheme?.lowercased() == "https" else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              data.count <= 1_048_576 else { throw URLError(.badServerResponse) }
        return "HTTPS \(http.statusCode), \(data.count) bytes"
    }
}

@MainActor
struct HanlinMiniAppTransferView: View {
    enum Mode: Equatable { case send, receive }
    let mode: Mode
    @Environment(\.openURL) private var openURL
    @State private var receipt: HanlinProductTransferReceipt?
    @State private var committed: HanlinProductTransferReceipt?
    @State private var working = false
    @State private var status: String?
    @State private var failure: String?
    @State private var confirmsRollback = false

    var body: some View {
        Form {
            Section {
                if mode == .send {
                    Text("Copy your installed mini apps and their saved data to Hanlin MiniApps.")
                    Text("Your original mini apps and AI conversations remain available in Hanlin.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Prepare a copy in Hanlin, then import it here.")
                    Text("Existing data is kept. Conflicting data must be resolved before a copy can be imported.")
                        .foregroundStyle(.secondary)
                }
            }
            if let receipt {
                Section("Transfer copy") {
                    LabeledContent("Installed packages", value: receipt.packageCount.formatted())
                    LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: receipt.byteCount,
                                                                            countStyle: .file))
                }
            }
            Section {
                if mode == .send {
                    Button("Prepare copy") { Task { await send() } }
                        .accessibilityIdentifier("hanlin-transfer-prepare")
                    if receipt != nil {
                        Button("Open Hanlin MiniApps") {
                            openURL(SplitCompanionCatalogRoute.url) { accepted in
                                if !accepted {
                                    failure = String(localized: "Install Hanlin MiniApps to receive this copy.")
                                }
                            }
                        }
                        .accessibilityIdentifier("hanlin-transfer-open-companion")
                    }
                } else {
                    Button("Import copy") { Task { await receive() } }
                        .disabled(receipt == nil)
                        .accessibilityIdentifier("hanlin-transfer-import")
                    Button("Refresh") { Task { await load() } }
                    if committed != nil {
                        Button("Restore data from before the transfer", role: .destructive) {
                            confirmsRollback = true
                        }
                        .accessibilityIdentifier("hanlin-transfer-rollback")
                    }
                }
                if working { ProgressView("Transferring mini apps…") }
                if let status {
                    Text(status).accessibilityIdentifier("hanlin-transfer-status")
                }
                if let failure {
                    Text(failure).foregroundStyle(.red)
                        .accessibilityIdentifier("hanlin-transfer-error")
                }
            }
            .disabled(working)
        }
        .navigationTitle(mode == .send ? Text("Transfer mini apps") : Text("Transfer from Hanlin"))
        .navigationBarBackButtonHidden(working)
        .interactiveDismissDisabled(working)
        .task { if mode == .receive { await load() } }
        .confirmationDialog("Restore the data that was present before this transfer?",
                            isPresented: $confirmsRollback, titleVisibility: .visible) {
            Button("Restore previous data", role: .destructive) { Task { await rollback() } }
        } message: {
            Text("Restoration is available only while the imported data has not been changed.")
        }
    }

    private func send() async {
        working = true
        failure = nil
        status = nil
        defer { working = false }
        do {
            receipt = try await HanlinScriptingPlatform.shared.createProductTransfer()
            status = String(localized: "Copy ready. Open Hanlin MiniApps and choose Transfer from Hanlin.")
        } catch { failure = message(error) }
    }

    private func load() async {
        working = true
        failure = nil
        defer { working = false }
        do {
            let outbox = try HanlinScriptingPlatform.productTransferOutbox()
            let transactions = try HanlinScriptingPlatform.productTransferTransactionRoot()
            let result = try await Task.detached(priority: .userInitiated) {
                let latest = outbox.appending(path: "latest.json")
                let pending: HanlinProductTransferReceipt?
                if FileManager.default.fileExists(atPath: latest.path) {
                    let index = try JSONDecoder().decode(HanlinProductTransferReceipt.self,
                        from: Data(contentsOf: latest))
                    let verified = try HanlinProductTransferRecovery.checkpointReceipt(
                        at: outbox.appending(path: index.id.uuidString.lowercased()))
                    guard index == verified else { throw HanlinProductTransferError.invalidCheckpoint }
                    pending = verified
                } else {
                    pending = nil
                }
                return (pending, try HanlinProductTransferRecovery.committedReceipt(at: transactions))
            }.value
            receipt = result.0
            committed = result.1
        } catch {
            receipt = nil
            failure = message(error)
        }
    }

    private func receive() async {
        guard let receipt else { return }
        working = true
        failure = nil
        status = nil
        defer { working = false }
        do {
            try await HanlinScriptingPlatform.shared.receiveProductTransfer(receipt)
            committed = receipt
            status = String(localized: "Transfer complete. Your mini apps are ready.")
        } catch { failure = message(error) }
    }

    private func rollback() async {
        working = true
        failure = nil
        status = nil
        defer { working = false }
        do {
            try await HanlinScriptingPlatform.shared.rollbackProductTransfer()
            committed = nil
            status = String(localized: "Previous data restored. The original copy in Hanlin is unchanged.")
        } catch { failure = message(error) }
    }

    private func message(_ error: Error) -> String {
        switch error {
        case HanlinProductTransferError.restartRequired:
            String(localized: "Close and reopen this app, then transfer before opening a mini app or running an action.")
        case HanlinProductTransferError.busy:
            String(localized: "Close open mini apps and wait for active actions or imports to finish, then try again.")
        case HanlinProductTransferError.destinationConflict:
            String(localized: "Some existing mini app data differs from this copy. Your existing data has been kept.")
        case HanlinProductTransferError.rollbackWouldLoseChanges:
            String(localized: "Your mini app data has changed since the transfer. Restoration stopped to preserve your work.")
        case HanlinProductTransferError.anotherTransferPending:
            String(localized: "A transfer has already been recorded. Its data and recovery copy have been kept.")
        case SplitAppStorageLayout.LayoutError.appGroupUnavailable:
            String(localized: "Shared app storage is unavailable. Install both Hanlin apps from the same release and try again.")
        default:
            String(localized: "The transfer could not be completed. Your original data has been kept. Try again or prepare a new copy.")
        }
    }
}
