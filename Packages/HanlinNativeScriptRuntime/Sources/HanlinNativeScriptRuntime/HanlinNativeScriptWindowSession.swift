import Foundation
import HanlinNativeScriptCoreSupport
import UIKit

/// A cooperating package's window, with its own provider and presentation.
/// The original NativeScriptSession remains the sole owner of the package VM.
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
        makeRuntimeProvider: ProviderFactory,
        makeWindowProvider: ProviderFactory,
        configureRuntime: @escaping @MainActor (String) -> Void = { _ in },
        releaseRuntime: @escaping @MainActor (String) -> Void = { _ in }
    ) throws -> HanlinNativeScriptWindowSession {
        let root = applicationRoot.standardizedFileURL
        guard try supportsWindowFactory(applicationRoot: root) else {
            throw failure("This entry does not declare a cooperating NativeScript window factory.")
        }

        let runtimeOwner: RuntimeOwner
        if let current = activeOwner {
            guard current.applicationRoot == root, current.environment == environment else {
                throw failure("The open NativeScript runtime belongs to a different package or generation.")
            }
            runtimeOwner = current
        } else {
            // Legacy whole-application sessions keep their existing ownership.
            guard HanlinNativeScriptSession.activeSessionIdentifier == nil else {
                throw failure("A legacy NativeScript application owns the active runtime.")
            }
            runtimeOwner = try RuntimeOwner(
                applicationRoot: root, environment: environment,
                makeProvider: makeRuntimeProvider, configure: configureRuntime, release: releaseRuntime)
            activeOwner = runtimeOwner
        }

        let windowID = UUID().uuidString.lowercased()
        let provider = makeWindowProvider(windowID)
        HanlinNativeServicesBridge.register(provider, forSessionID: windowID)
        do {
            guard let token = HanlinNativeServicesPrepareSessionBootstrap(windowID),
                  let bridge = HanlinNativeServicesBridge.claimSessionBridge(withToken: token) else {
                throw failure("The window's Host Services bridge could not be created.")
            }
            guard let context = HanlinNativeScriptWindowFactoryRegistry.openWindow(id: windowID, bridge: bridge) else {
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
        // Close native/JS view ownership while the VM is still live, then revoke
        // only this window's pending operations/provider.
        HanlinNativeScriptWindowFactoryRegistry.closeWindow(id: sessionID)
        HanlinNativeServicesBridge.unregisterProvider(forSessionID: sessionID)
        owner.windowIDs.remove(sessionID)
        self.owner = nil
        if owner.windowIDs.isEmpty {
            owner.stop()
            if Self.activeOwner === owner { Self.activeOwner = nil }
        }
    }

    deinit {
        MainActor.assumeIsolated { shutdown() }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "HanlinNativeScript.WindowFactory", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    @MainActor
    private final class RuntimeOwner {
        let applicationRoot: URL
        let environment: [String: String]
        let session: HanlinNativeScriptSession
        let provider: any HanlinNativeServicesProvider
        let release: @MainActor (String) -> Void
        var windowIDs: Set<String> = []
        private var stopped = false

        init(applicationRoot: URL, environment: [String: String],
             makeProvider: ProviderFactory,
             configure: @MainActor (String) -> Void,
             release: @escaping @MainActor (String) -> Void) throws {
            self.applicationRoot = applicationRoot
            self.environment = environment
            self.release = release
            session = try HanlinNativeScriptSession(
                applicationRoot: applicationRoot, environment: environment)
            provider = makeProvider(session.sessionID)
            // The app's existing container helper also installs a default
            // provider. Run it first, then bind our explicitly neutral provider.
            configure(session.sessionID)
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
                        "The declared NativeScript entry did not register its window factory.")
                }
            } catch {
                stop()
                throw error
            }
        }

        func stop() {
            guard !stopped else { return }
            stopped = true
            // Registry callbacks, neutral-provider handlers and pending bridge
            // completions can own JS blocks. Retire them while their VM is live.
            HanlinNativeScriptWindowFactoryRegistry.endRuntime(sessionID: session.sessionID)
            HanlinNativeServicesBridge.unregisterProvider(forSessionID: session.sessionID)
            HanlinNativeServicesBridge.clearLegacyProvider(ifMatches: provider)
            release(session.sessionID)
            session.shutdown()
        }

        deinit { MainActor.assumeIsolated { stop() } }
    }
}
