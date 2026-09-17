import Foundation
import HanlinMiniAppCore
import HanlinPlatformContracts
#if canImport(UIKit)
import UIKit
#endif

/// Narrow native bridge exposing Node, Python, JavaScript, Network, and Inter-App
/// request services to HanlinScript (NativeScript) via Objective-C metadata.
///
/// Security & Architectural Rules:
/// 1. Caller identity is strictly HOST-BOUND to the active session (`activeAppID`).
///    Untrusted scripts cannot supply or spoof their caller identity.
/// 2. All privileged operations (Node, Python, JavaScript, Network, Inter-App)
///    are capability-gated against `activeGrantedCapabilities`.
/// 3. Preserves runtime lifecycle, cancellation, and error semantics.
@objc(HanlinNativeServicesBridge)
@objcMembers
public final class HanlinNativeServicesBridge: NSObject {

    // MARK: - Active Host Session Context

    public private(set) static var activeAppID: String?
    public private(set) static var activeDataRoot: String?
    public private(set) static var activeStateDirectory: String?
    public private(set) static var activeDocumentsDirectory: String?
    public private(set) static var activeCacheDirectory: String?
    public private(set) static var activeGrantedCapabilities: Set<String> = []

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
    }

    public static func clearActiveContainer() {
        if let appID = activeAppID, let parsedID = try? HanlinAppID(validating: appID) {
            Task { @MainActor in
                await HanlinMiniAppHost.shared.requestBroker.unregisterAll(target: parsedID)
            }
        }
        activeAppID = nil
        activeDataRoot = nil
        activeStateDirectory = nil
        activeDocumentsDirectory = nil
        activeCacheDirectory = nil
        activeGrantedCapabilities.removeAll()
    }

    /// Checks whether the active session has been granted the required capability.
    private static func hasCapability(_ capability: String) -> Bool {
        activeGrantedCapabilities.contains(capability)
            || activeGrantedCapabilities.contains("all")
    }

    // MARK: - Canonical Roots

    /// The root data directory for the active Mini App.
    public static func dataRootDirectory() -> String? { activeDataRoot }

    /// The private state directory for the active Mini App.
    public static func stateDirectory() -> String? { activeStateDirectory }

    /// The user documents directory for the active Mini App.
    public static func documentsDirectory() -> String? { activeDocumentsDirectory }

    /// The cache directory for the active Mini App.
    public static func cacheDirectory() -> String? { activeCacheDirectory }

    // MARK: - JavaScript Runtime Service

    /// Execute JavaScript source code via the host JavaScriptCore engine service.
    ///
    /// - Parameters:
    ///   - source: JavaScript source code string.
    ///   - completion: Called on main thread with (result output string, error description).
    public static func executeJavaScript(
        _ source: String,
        completion: @escaping (String?, String?) -> Void
    ) {
        guard hasCapability("javascript") || hasCapability("runtime.javascript") else {
            completion(nil, "Permission denied: 'javascript' capability not granted to this Mini App.")
            return
        }
        Task { @MainActor in
            do {
                let layout = RuntimeFileLayout.default
                let workspace = try layout.workspace(client: .tools, identifier: "nativescript-jsc")
                let request = RuntimeExecutionRequest(
                    source: source,
                    workspace: workspace
                )
                let result = try await AppRuntimeCore.shared.javaScriptCore.execute(request)
                let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                completion(output.isEmpty ? "OK" : output, nil)
            } catch {
                completion(nil, error.localizedDescription)
            }
        }
    }

    // MARK: - Node Runtime

    /// Execute JavaScript source via the embedded Node runtime.
    public static func executeNode(
        _ source: String,
        completion: @escaping (String?, String?) -> Void
    ) {
        guard hasCapability("node") || hasCapability("runtime.node") else {
            completion(nil, "Permission denied: 'node' capability not granted to this Mini App.")
            return
        }
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
                completion(output, nil)
            } catch {
                completion(nil, error.localizedDescription)
            }
        }
    }

    /// Check whether the Node runtime is available and healthy.
    public static func nodeHealthCheck(
        completion: @escaping (Bool, String?) -> Void
    ) {
        Task { @MainActor in
            do {
                let node = AppRuntimeCore.shared.node
                let snapshot = try await node.healthCheck()
                completion(snapshot.state == .ready, nil)
            } catch {
                completion(false, error.localizedDescription)
            }
        }
    }

    // MARK: - Python Runtime

    /// Execute Python source via the embedded Python runtime.
    public static func executePython(
        _ source: String,
        completion: @escaping (String?, String?) -> Void
    ) {
        guard hasCapability("python") || hasCapability("runtime.python") else {
            completion(nil, "Permission denied: 'python' capability not granted to this Mini App.")
            return
        }
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
                completion(output, nil)
            } catch {
                completion(nil, error.localizedDescription)
            }
        }
    }

    /// Returns the embedded Python runtime version, or nil if unavailable.
    public static func pythonVersion() -> String? {
        try? PythonRuntimeBridge.version()
    }

    // MARK: - Real Network / HTTPS Fetch

    /// Perform a real HTTPS request from the Mini App.
    ///
    /// - Parameters:
    ///   - urlString: HTTPS URL string.
    ///   - completion: Called on main thread with (response metadata string, error description).
    public static func fetchURL(
        _ urlString: String,
        completion: @escaping (String?, String?) -> Void
    ) {
        guard hasCapability("network") || hasCapability("network.fetch") else {
            completion(nil, "Permission denied: 'network' capability not granted to this Mini App.")
            return
        }
        guard let url = URL(string: urlString), url.scheme?.lowercased() == "https" else {
            completion(nil, "Invalid or non-HTTPS URL: \(urlString)")
            return
        }
        Task { @MainActor in
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    completion(nil, "Invalid server response.")
                    return
                }
                completion("HTTPS \(http.statusCode), \(data.count) bytes", nil)
            } catch {
                completion(nil, error.localizedDescription)
            }
        }
    }

    // MARK: - Inter-App Request Broker (Host-Bound Caller Identity)

    /// Send an authorized inter-app request to another Mini App.
    /// Caller identity is strictly bound to `activeAppID`.
    @objc(sendRequest:action:capability:payloadJSON:completion:)
    public static func sendRequest(
        targetID: String,
        action: String,
        capability: String,
        payloadJSON: String,
        completion: @escaping (String?, String?) -> Void
    ) {
        guard let callerID = activeAppID else {
            completion(nil, "Unauthorized: No active Mini App session context.")
            return
        }
        guard hasCapability(capability) else {
            completion(nil, "Permission denied: Mini App does not have '\(capability)' capability.")
            return
        }
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
                completion(String(data: responseData, encoding: .utf8), nil)
            } catch {
                completion(nil, error.localizedDescription)
            }
        }
    }

    /// Register a handler in HanlinScript for incoming inter-app requests.
    @objc(registerRequestHandler:capability:handler:)
    public static func registerRequestHandler(
        action: String,
        capability: String,
        handler: @escaping (String, String, @escaping (String?, String?) -> Void) -> Void
    ) {
        guard let callerID = activeAppID,
              let appID = try? HanlinAppID(validating: callerID),
              let actionID = try? HanlinActionID(validating: action),
              let capabilityID = try? HanlinCapabilityID(validating: capability) else {
            return
        }
        Task { @MainActor in
            let broker = HanlinMiniAppHost.shared.requestBroker
            await broker.register(target: appID, action: actionID, capability: capabilityID) { request in
                try await withCheckedThrowingContinuation { continuation in
                    let payloadStr = (try? String(data: request.payload.canonicalJSONData(), encoding: .utf8)) ?? "{}"
                    handler(request.caller.rawValue, payloadStr) { responseJSON, errorStr in
                        if let errorStr {
                            continuation.resume(throwing: NSError(domain: "HanlinMiniAppRequest", code: 1, userInfo: [NSLocalizedDescriptionKey: errorStr]))
                        } else if let responseJSON, let data = responseJSON.data(using: .utf8),
                                  let value = try? JSONDecoder().decode(HanlinValue.self, from: data) {
                            continuation.resume(returning: value)
                        } else {
                            continuation.resume(returning: .null)
                        }
                    }
                }
            }
        }
    }
}
