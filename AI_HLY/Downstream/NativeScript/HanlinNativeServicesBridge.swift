import Foundation
import HanlinMiniAppCore
@_exported import HanlinNativeScriptCoreSupport
import HanlinPlatformContracts
#if canImport(UIKit)
import UIKit
#endif

/// Production host provider implementing `HanlinNativeServicesProvider` for NativeScript.
///
/// Security & Architectural Rules:
import Foundation
import HanlinMiniAppCore
@_exported import HanlinNativeScriptCoreSupport
import HanlinPlatformContracts
#if canImport(UIKit)
import UIKit
#endif

/// Production host provider implementing `HanlinNativeServicesProvider` for NativeScript.
///
/// Security & Architectural Rules:
/// 1. Caller identity is strictly HOST-BOUND to the active session (`activeAppID`).
///    Untrusted scripts cannot supply or spoof their caller identity.
/// 2. All privileged operations (Node, Python, JavaScript, Network, Inter-App)
///    are capability-gated against `activeGrantedCapabilities`.
/// 3. Visible to NativeScript JavaScript because the Objective-C shim
///    `HanlinNativeServicesBridge` lives in `HanlinNativeScriptCoreSupport`.
public final class HanlinNativeServicesHostProvider: NSObject, @unchecked Sendable, HanlinNativeServicesProvider {
    nonisolated(unsafe) public static let shared = HanlinNativeServicesHostProvider()

    private let lock = NSLock()
    private var activeAdapter: NativeScriptHostServicesAdapter?
    private var overrideDirs: (data: String?, state: String?, docs: String?, cache: String?)?

    public static var activeAppID: String? {
        shared.lock.lock()
        defer { shared.lock.unlock() }
        return shared.activeAdapter?.context.appID?.rawValue
    }

    public static var activeDataRoot: String? {
        shared.lock.lock()
        defer { shared.lock.unlock() }
        return shared.overrideDirs?.data ?? shared.activeAdapter?.dataRootDirectory()
    }

    public static var activeStateDirectory: String? {
        shared.lock.lock()
        defer { shared.lock.unlock() }
        return shared.overrideDirs?.state ?? shared.activeAdapter?.stateDirectory()
    }

    public static var activeDocumentsDirectory: String? {
        shared.lock.lock()
        defer { shared.lock.unlock() }
        return shared.overrideDirs?.docs ?? shared.activeAdapter?.documentsDirectory()
    }

    public static var activeCacheDirectory: String? {
        shared.lock.lock()
        defer { shared.lock.unlock() }
        return shared.overrideDirs?.cache ?? shared.activeAdapter?.cacheDirectory()
    }

    public static var activeGrantedCapabilities: Set<String> {
        shared.lock.lock()
        defer { shared.lock.unlock() }
        return shared.activeAdapter?.context.effectiveCapabilities ?? []
    }

    public static var registeredActionIDs: Set<HanlinActionID> {
        shared.lock.lock()
        defer { shared.lock.unlock() }
        return shared.activeAdapter?.allRegisteredActionIDs ?? []
    }

    public static func setActiveContainer(
        appID: String,
        dataRoot: String,
        stateDir: String,
        docsDir: String,
        cacheDir: String,
        grantedCapabilities: [String] = []
    ) {
        let validAppID = (try? HanlinAppID(validating: appID)) ?? (try! HanlinAppID(validating: "unknown-miniapp"))
        let adapter = NativeScriptHostServicesAdapter(
            appID: validAppID,
            grantedCapabilities: Set(grantedCapabilities),
            sessionID: appID
        )

        shared.lock.lock()
        shared.activeAdapter = adapter
        shared.overrideDirs = (dataRoot, stateDir, docsDir, cacheDir)
        shared.lock.unlock()

        HanlinNativeServicesBridge.register(adapter, forSessionID: appID)
        HanlinNativeServicesBridge.register(adapter)
    }

    public static func clearActiveContainer() {
        shared.lock.lock()
        let oldAppID = shared.activeAdapter?.sessionID
        shared.activeAdapter = nil
        shared.overrideDirs = nil
        shared.lock.unlock()

        if let oldAppID {
            HanlinNativeServicesBridge.unregisterProvider(forSessionID: oldAppID)
        }
        HanlinNativeServicesBridge.register(nil)
    }

    // MARK: - HanlinNativeServicesProvider Conformance

    public func dataRootDirectory() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return overrideDirs?.data ?? activeAdapter?.dataRootDirectory()
    }

    public func stateDirectory() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return overrideDirs?.state ?? activeAdapter?.stateDirectory()
    }

    public func documentsDirectory() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return overrideDirs?.docs ?? activeAdapter?.documentsDirectory()
    }

    public func cacheDirectory() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return overrideDirs?.cache ?? activeAdapter?.cacheDirectory()
    }

    public func executeJavaScript(
        _ source: String,
        completion: @escaping (String?, String?) -> Void
    ) {
        lock.lock()
        let adapter = activeAdapter
        lock.unlock()
        guard let adapter else {
            completion(nil, "Unauthorized: No active Mini App session context.")
            return
        }
        adapter.executeJavaScript(source, completion: completion)
    }

    public func executeNode(
        _ source: String,
        completion: @escaping (String?, String?) -> Void
    ) {
        lock.lock()
        let adapter = activeAdapter
        lock.unlock()
        guard let adapter else {
            completion(nil, "Unauthorized: No active Mini App session context.")
            return
        }
        adapter.executeNode(source, completion: completion)
    }

    @objc(nodeHealthCheckWithCompletion:)
    public func nodeHealthCheck(
        completion: @escaping (Bool, String?) -> Void
    ) {
        lock.lock()
        let adapter = activeAdapter
        lock.unlock()
        guard let adapter else {
            completion(false, "Unauthorized: No active Mini App session context.")
            return
        }
        adapter.nodeHealthCheck(completion: completion)
    }

    public func executePython(
        _ source: String,
        completion: @escaping (String?, String?) -> Void
    ) {
        lock.lock()
        let adapter = activeAdapter
        lock.unlock()
        guard let adapter else {
            completion(nil, "Unauthorized: No active Mini App session context.")
            return
        }
        adapter.executePython(source, completion: completion)
    }

    public func pythonVersion() -> String? {
        lock.lock()
        let adapter = activeAdapter
        lock.unlock()
        return adapter?.pythonVersion() ?? (try? PythonRuntimeBridge.version())
    }

    public func fetchURL(
        _ urlString: String,
        completion: @escaping (String?, String?) -> Void
    ) {
        lock.lock()
        let adapter = activeAdapter
        lock.unlock()
        guard let adapter else {
            completion(nil, "Unauthorized: No active Mini App session context.")
            return
        }
        adapter.fetchURL(urlString, completion: completion)
    }

    public func sendRequest(
        _ targetID: String,
        action: String,
        capability: String,
        payloadJSON: String,
        completion: @escaping (String?, String?) -> Void
    ) {
        lock.lock()
        let adapter = activeAdapter
        lock.unlock()
        guard let adapter else {
            completion(nil, "Unauthorized: No active Mini App session context.")
            return
        }
        adapter.sendRequest(targetID, action: action, capability: capability, payloadJSON: payloadJSON, completion: completion)
    }

    public func registerRequestHandler(
        _ action: String,
        capability: String,
        handler: @escaping (String, String, @escaping (String?, String?) -> Void) -> Void
    ) {
        lock.lock()
        let adapter = activeAdapter
        lock.unlock()
        guard let adapter else {
            return
        }
        nonisolated(unsafe) let safeHandler = handler
        adapter.registerRequestHandler(action, capability: capability, handler: safeHandler)
    }

    @MainActor
    static func invokeRegisteredAction(
        _ action: HanlinActionID,
        capability: HanlinCapabilityID,
        caller: HanlinAppID,
        payload: HanlinValue
    ) async throws -> HanlinValue {
        let adapter = shared.lock.withLock { shared.activeAdapter }
        guard let adapter else {
            throw HanlinMiniAppRequestError.routeNotFound
        }
        return try await adapter.invokeRegisteredAction(action, capability: capability, caller: caller, payload: payload)
    }
}

// MARK: - Backward-Compatible Swift API on HanlinNativeServicesBridge

extension HanlinNativeServicesBridge {
    public static var activeAppID: String? {
        HanlinNativeServicesHostProvider.activeAppID
    }

    public static var activeDataRoot: String? {
        HanlinNativeServicesHostProvider.activeDataRoot
    }

    public static var activeStateDirectory: String? {
        HanlinNativeServicesHostProvider.activeStateDirectory
    }

    public static var activeDocumentsDirectory: String? {
        HanlinNativeServicesHostProvider.activeDocumentsDirectory
    }

    public static var activeCacheDirectory: String? {
        HanlinNativeServicesHostProvider.activeCacheDirectory
    }

    public static var activeGrantedCapabilities: Set<String> {
        HanlinNativeServicesHostProvider.activeGrantedCapabilities
    }

    public static var registeredActionIDs: Set<HanlinActionID> {
        HanlinNativeServicesHostProvider.registeredActionIDs
    }

    public static func setActiveContainer(
        appID: String,
        dataRoot: String,
        stateDir: String,
        docsDir: String,
        cacheDir: String,
        grantedCapabilities: [String] = []
    ) {
        HanlinNativeServicesHostProvider.setActiveContainer(
            appID: appID,
            dataRoot: dataRoot,
            stateDir: stateDir,
            docsDir: docsDir,
            cacheDir: cacheDir,
            grantedCapabilities: grantedCapabilities
        )
    }

    public static func clearActiveContainer() {
        HanlinNativeServicesHostProvider.clearActiveContainer()
    }

    public static func registerHostProvider() {
        HanlinNativeServicesBridge.register(HanlinNativeServicesHostProvider.shared)
    }

    public static func sendRequest(
        targetID: String,
        action: String,
        capability: String,
        payloadJSON: String,
        completion: @escaping (String?, String?) -> Void
    ) {
        HanlinNativeServicesBridge.sendRequest(
            targetID,
            action: action,
            capability: capability,
            payloadJSON: payloadJSON,
            completion: completion
        )
    }

    public static func registerRequestHandler(
        action: String,
        capability: String,
        handler: @escaping (String, String, @escaping (String?, String?) -> Void) -> Void
    ) {
        HanlinNativeServicesBridge.registerRequestHandler(
            action,
            capability: capability,
            handler: handler
        )
    }
}

