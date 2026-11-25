import Foundation
import HanlinNativeScriptCoreSupport
import UIKit

/// One provider, immutable package/module namespace and original NativeWindow.
/// NativeScript's original main VM remains process-wide; only cooperating
/// factory entries are admitted. Legacy whole-application ownership is preserved.
@MainActor
public final class HanlinNativeScriptWindowSession {
    public typealias ProviderFactory = @MainActor (String) -> any HanlinNativeServicesProvider

    private static var activeOwner: RuntimeOwner?
    private var owner: RuntimeOwner?
    private let context: HanlinNativeScriptWindowContext
    public let sessionID: String
    public let runtimeSessionID: String
    public let containerController: UIViewController
    public private(set) var isActive = true

    public static func supportsWindowFactory(applicationRoot: URL) throws -> Bool {
        let data = try Data(contentsOf: applicationRoot.appendingPathComponent("package.json"))
        let metadata = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let options = metadata?["hanlinNativeScript"] as? [String: Any]
        return options?["windowFactory"] as? Int == 1
    }

    public static func open(
        applicationRoot: URL,
        environment: [String: String] = [:],
        makeWindowProvider: ProviderFactory
    ) throws -> HanlinNativeScriptWindowSession {
        let root = try HanlinNativeScriptSession.validatePreparedApplication(applicationRoot)
        guard try supportsWindowFactory(applicationRoot: root) else {
            throw failure("This entry does not declare a cooperating NativeScript window factory.")
        }

        let runtimeOwner: RuntimeOwner
        if let current = activeOwner {
            runtimeOwner = current
        } else {
            guard HanlinNativeScriptSession.activeSessionIdentifier == nil else {
                throw failure("A legacy NativeScript application owns the active runtime.")
            }
            runtimeOwner = try RuntimeOwner()
            activeOwner = runtimeOwner
        }

        let windowID = UUID().uuidString.lowercased()
        let provider = makeWindowProvider(windowID)
        HanlinNativeServicesBridge.register(provider, forSessionID: windowID)
        do {
            // Keep the package environment explicit; never mutate process globals
            // when a second package opens. Storage paths come from its provider.
            var scopedEnvironment = environment
            scopedEnvironment["HANLIN_MINIAPP_DATA_ROOT"] = provider.dataRootDirectory()
            scopedEnvironment["HANLIN_MINIAPP_STATE_DIR"] = provider.stateDirectory()
            scopedEnvironment["HANLIN_MINIAPP_DOCUMENTS_DIR"] = provider.documentsDirectory()
            scopedEnvironment["HANLIN_MINIAPP_CACHE_DIR"] = provider.cacheDirectory()
            let package = try HanlinNativeScriptWindowPackage.stage(
                source: root, hostRoot: runtimeOwner.hostRoot, windowID: windowID,
                environment: scopedEnvironment, sharedRuntime: runtimeOwner.sharedRuntime)
            guard HanlinNativeScriptWindowFactoryRegistry.loadPackage(
                windowID: windowID, configurationJSON: package.loaderConfigurationJSON) else {
                throw failure(HanlinNativeScriptWindowFactoryRegistry.lastFailure()
                              ?? "The original NativeScript loader could not load this window's entry.")
            }
            guard let token = HanlinNativeServicesPrepareSessionBootstrap(windowID),
                  let bridge = HanlinNativeServicesBridge.claimSessionBridge(withToken: token) else {
                throw failure("The window's Host Services bridge could not be created.")
            }
            guard let context = HanlinNativeScriptWindowFactoryRegistry.openWindow(
                id: windowID, bridge: bridge, packageID: package.packageID,
                applicationRoot: package.root.path, environmentJSON: package.environmentJSON,
                styleSheetPath: package.styleSheetPath) else {
                bridge.invalidate()
                throw failure(HanlinNativeScriptWindowFactoryRegistry.lastFailure()
                              ?? "The NativeScript window factory did not open its view.")
            }
            runtimeOwner.windowIDs.insert(windowID)
            return HanlinNativeScriptWindowSession(owner: runtimeOwner, context: context)
        } catch {
            HanlinNativeScriptWindowFactoryRegistry.closeWindow(id: windowID)
            HanlinNativeServicesBridge.unregisterProvider(forSessionID: windowID)
            if runtimeOwner.windowIDs.isEmpty {
                runtimeOwner.stop()
                if activeOwner === runtimeOwner { activeOwner = nil }
            }
            throw error
        }
    }

    private init(owner: RuntimeOwner, context: HanlinNativeScriptWindowContext) {
        self.owner = owner
        self.context = context
        sessionID = context.windowID
        runtimeSessionID = owner.session.sessionID
        containerController = context.containerController
    }

    public func shutdown() {
        guard isActive, let owner else { return }
        isActive = false
        HanlinNativeScriptWindowFactoryRegistry.closeWindow(id: sessionID)
        HanlinNativeServicesBridge.unregisterProvider(forSessionID: sessionID)
        owner.windowIDs.remove(sessionID)
        self.owner = nil
        if owner.windowIDs.isEmpty {
            owner.stop()
            if Self.activeOwner === owner { Self.activeOwner = nil }
        }
    }

    deinit { MainActor.assumeIsolated { shutdown() } }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "HanlinNativeScript.WindowFactory", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    @MainActor
    private final class RuntimeOwner {
        let hostRoot: URL
        let sharedRuntime: URL
        let session: HanlinNativeScriptSession
        let provider: any HanlinNativeServicesProvider
        var windowIDs: Set<String> = []
        private var stopped = false

        init() throws {
            guard let shared = HanlinNativeScriptSession.sharedRuntimeURL else {
                throw HanlinNativeScriptWindowSession.failure("The original NativeScript libraries are unavailable.")
            }
            sharedRuntime = shared
            hostRoot = try HanlinNativeScriptWindowPackage.makeHostRoot(sharedRuntime: shared)
            session = try HanlinNativeScriptSession(applicationRoot: hostRoot)
            provider = HanlinNativeScriptWindowFactoryRegistry.neutralRuntimeProvider()
            // Global Host Services deliberately cannot pick the first or focused
            // package. Every privileged call must use its explicit window bridge.
            HanlinNativeServicesBridge.register(provider, forSessionID: session.sessionID)
            HanlinNativeServicesBridge.register(provider)
            do {
                guard HanlinNativeScriptWindowFactoryRegistry.beginRuntime(sessionID: session.sessionID) else {
                    throw HanlinNativeScriptWindowSession.failure(
                        HanlinNativeScriptWindowFactoryRegistry.lastFailure() ?? "Window factory ownership is unavailable.")
                }
                try session.start()
                guard HanlinNativeScriptWindowFactoryRegistry.hasFactory(sessionID: session.sessionID) else {
                    throw HanlinNativeScriptWindowSession.failure(
                        "The neutral original NativeScript entry did not register its package loader.")
                }
            } catch {
                stop()
                throw error
            }
        }

        func stop() {
            guard !stopped else { return }
            stopped = true
            HanlinNativeScriptWindowFactoryRegistry.endRuntime(sessionID: session.sessionID)
            HanlinNativeServicesBridge.unregisterProvider(forSessionID: session.sessionID)
            HanlinNativeServicesBridge.clearLegacyProvider(ifMatches: provider)
            session.shutdown()
            // Keep all module files/scopes until the VM and every window have
            // retired; closing one window cannot break another's delayed import.
            try? FileManager.default.removeItem(at: hostRoot.deletingLastPathComponent())
        }

        deinit { MainActor.assumeIsolated { stop() } }
    }
}
