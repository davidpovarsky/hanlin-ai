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

    nonisolated(unsafe) public private(set) static var activeAppID: String?
    nonisolated(unsafe) public private(set) static var activeDataRoot: String?
    nonisolated(unsafe) public private(set) static var activeStateDirectory: String?
    nonisolated(unsafe) public private(set) static var activeDocumentsDirectory: String?
    nonisolated(unsafe) public private(set) static var activeCacheDirectory: String?
    nonisolated(unsafe) public private(set) static var activeGrantedCapabilities: Set<String> = []
    nonisolated(unsafe) public private(set) static var registeredActionIDs: Set<HanlinActionID> = []
    nonisolated(unsafe) private static var registeredActionHandlers: [HanlinActionID: RegisteredActionHandler] = [:]

    private struct RegisteredActionHandler {
        let capability: HanlinCapabilityID
        let invoke: (String, String, @escaping (String?, String?) -> Void) -> Void
    }

    public static func setActiveContainer(
        appID: String,
        dataRoot: String,
        stateDir: String,
        docsDir: String,
        cacheDir: String,
        grantedCapabilities: [String] = []
    ) {
        activeAppID = appID
        activeDataRoot = dataRoot
        activeStateDirectory = stateDir
        activeDocumentsDirectory = docsDir
        activeCacheDirectory = cacheDir
        activeGrantedCapabilities = Set(grantedCapabilities)
        registeredActionIDs.removeAll()
        registeredActionHandlers.removeAll()
        HanlinNativeServicesBridge.register(shared)
    }

    public static func clearActiveContainer() {
        activeAppID = nil
        activeDataRoot = nil
        activeStateDirectory = nil
        activeDocumentsDirectory = nil
        activeCacheDirectory = nil
        activeGrantedCapabilities.removeAll()
        registeredActionIDs.removeAll()
        registeredActionHandlers.removeAll()
    }

    /// Checks whether the active session has been granted the required capability.
    private static func hasCapability(_ capability: String) -> Bool {
        activeGrantedCapabilities.contains(capability)
            || activeGrantedCapabilities.contains("all")
    }

    // MARK: - HanlinNativeServicesProvider Conformance

    public func dataRootDirectory() -> String? {
        Self.activeDataRoot
    }

    public func stateDirectory() -> String? {
        Self.activeStateDirectory
    }

    public func documentsDirectory() -> String? {
        Self.activeDocumentsDirectory
    }

    public func cacheDirectory() -> String? {
        Self.activeCacheDirectory
    }

    public func executeJavaScript(
        _ source: String,
        completion: @escaping (String?, String?) -> Void
    ) {
        guard Self.hasCapability("javascript") || Self.hasCapability("runtime.javascript") else {
            completion(nil, "Permission denied: 'javascript' capability not granted to this Mini App.")
            return
        }
        nonisolated(unsafe) let safeCompletion = completion
        Task { @MainActor in
            do {
                let layout = RuntimeFileLayout.default
                let workspace = try layout.workspace(client: .tools, identifier: "nativescript-jsc")
                let request = RuntimeExecutionRequest(
                    source: source,
                    workspace: workspace
                )
                let result = try await AppRuntimeCore.shared.javaScriptCore.execute(request)
                var output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if output.isEmpty, let val = result.value {
                    switch val {
                    case let .string(s): output = s
                    case let .number(n): output = n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int64(n)) : String(n)
                    case let .boolean(b): output = String(b)
                    case .null: output = "null"
                    default: break
                    }
                }
                safeCompletion(output.isEmpty ? "OK" : output, nil)
            } catch {
                safeCompletion(nil, error.localizedDescription)
            }
        }
    }

    public func executeNode(
        _ source: String,
        completion: @escaping (String?, String?) -> Void
    ) {
        guard Self.hasCapability("node") || Self.hasCapability("runtime.node") else {
            completion(nil, "Permission denied: 'node' capability not granted to this Mini App.")
            return
        }
        nonisolated(unsafe) let safeCompletion = completion
        Task { @MainActor in
            do {
                let node = AppRuntimeCore.shared.node
                let layout = RuntimeFileLayout.default
                let workspace = try layout.workspace(client: .tools, identifier: "nativescript-node")
                let request = RuntimeExecutionRequest(
                    source: source,
                    workspace: workspace
                )
                let result = try await node.executeJavaScript(request)
                let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                safeCompletion(output, nil)
            } catch {
                safeCompletion(nil, error.localizedDescription)
            }
        }
    }

    @objc(nodeHealthCheckWithCompletion:)
    public func nodeHealthCheck(
        completion: @escaping (Bool, String?) -> Void
    ) {
        nonisolated(unsafe) let safeCompletion = completion
        Task { @MainActor in
            do {
                let node = AppRuntimeCore.shared.node
                let snapshot = try await node.healthCheck()
                safeCompletion(snapshot.state == .ready, nil)
            } catch {
                safeCompletion(false, error.localizedDescription)
            }
        }
    }

    public func executePython(
        _ source: String,
        completion: @escaping (String?, String?) -> Void
    ) {
        guard Self.hasCapability("python") || Self.hasCapability("runtime.python") else {
            completion(nil, "Permission denied: 'python' capability not granted to this Mini App.")
            return
        }
        nonisolated(unsafe) let safeCompletion = completion
        Task { @MainActor in
            do {
                let python = AppRuntimeCore.shared.python
                let layout = RuntimeFileLayout.default
                let workspace = try layout.workspace(client: .tools, identifier: "nativescript-python")
                let request = RuntimeExecutionRequest(
                    source: source,
                    workspace: workspace
                )
                let result = try await python.execute(request)
                let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                safeCompletion(output, nil)
            } catch {
                safeCompletion(nil, error.localizedDescription)
            }
        }
    }

    public func pythonVersion() -> String? {
        try? PythonRuntimeBridge.version()
    }

    public func fetchURL(
        _ urlString: String,
        completion: @escaping (String?, String?) -> Void
    ) {
        guard Self.hasCapability("network") || Self.hasCapability("network.fetch") else {
            completion(nil, "Permission denied: 'network' capability not granted to this Mini App.")
            return
        }
        guard let url = URL(string: urlString), url.scheme?.lowercased() == "https" else {
            completion(nil, "Invalid or non-HTTPS URL: \(urlString)")
            return
        }
        nonisolated(unsafe) let safeCompletion = completion
        Task { @MainActor in
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    safeCompletion(nil, "Invalid server response.")
                    return
                }
                guard (200...299).contains(http.statusCode) else {
                    safeCompletion(nil, "HTTP \(http.statusCode) error")
                    return
                }
                safeCompletion("HTTPS \(http.statusCode), \(data.count) bytes", nil)
            } catch {
                safeCompletion(nil, error.localizedDescription)
            }
        }
    }

    public func sendRequest(
        _ targetID: String,
        action: String,
        capability: String,
        payloadJSON: String,
        completion: @escaping (String?, String?) -> Void
    ) {
        guard let callerID = Self.activeAppID else {
            completion(nil, "Unauthorized: No active Mini App session context.")
            return
        }
        guard Self.hasCapability(capability) else {
            completion(nil, "Permission denied: Mini App does not have '\(capability)' capability.")
            return
        }
        nonisolated(unsafe) let safeCompletion = completion
        Task { @MainActor in
            do {
                let caller = try HanlinAppID(validating: callerID)
                let target = try HanlinAppID(validating: targetID)
                let actionID = try HanlinActionID(validating: action)
                let capabilityID = try HanlinCapabilityID(validating: capability)
                let payloadData = payloadJSON.data(using: .utf8) ?? Data()
                let payload = try JSONDecoder().decode(HanlinValue.self, from: payloadData)

                let broker = HanlinMiniAppHost.shared.requestBroker
                let request = HanlinMiniAppRequest(
                    caller: caller,
                    target: target,
                    action: actionID,
                    capability: capabilityID,
                    payload: payload
                )
                let response = try await broker.request(request)
                let responseData = try response.value.canonicalJSONData()
                safeCompletion(String(data: responseData, encoding: .utf8), nil)
            } catch {
                safeCompletion(nil, error.localizedDescription)
            }
        }
    }

    public func registerRequestHandler(
        _ action: String,
        capability: String,
        handler: @escaping (String, String, @escaping (String?, String?) -> Void) -> Void
    ) {
        guard Self.activeAppID != nil,
              let actionID = try? HanlinActionID(validating: action),
              let capabilityID = try? HanlinCapabilityID(validating: capability) else {
            return
        }
        nonisolated(unsafe) let safeHandler = handler
        Self.registeredActionIDs.insert(actionID)
        Self.registeredActionHandlers[actionID] = RegisteredActionHandler(
            capability: capabilityID,
            invoke: safeHandler
        )
    }

    @MainActor
    static func invokeRegisteredAction(
        _ action: HanlinActionID,
        capability: HanlinCapabilityID,
        caller: HanlinAppID,
        payload: HanlinValue
    ) async throws -> HanlinValue {
        guard let registration = registeredActionHandlers[action] else {
            throw HanlinMiniAppRequestError.routeNotFound
        }
        guard registration.capability == capability else {
            throw HanlinMiniAppRequestError.capabilityMismatch
        }
        let payloadJSON = try String(data: payload.canonicalJSONData(), encoding: .utf8)
            ?? "{}"
        return try await withCheckedThrowingContinuation { continuation in
            registration.invoke(caller.rawValue, payloadJSON) { responseJSON, errorString in
                if let errorString {
                    continuation.resume(throwing: NSError(
                        domain: "HanlinMiniAppRequest",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: errorString]
                    ))
                } else if let responseJSON,
                          let data = responseJSON.data(using: .utf8),
                          let value = try? JSONDecoder().decode(HanlinValue.self, from: data) {
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(returning: .null)
                }
            }
        }
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

