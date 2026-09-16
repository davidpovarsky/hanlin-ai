import Foundation
import HanlinPlatformContracts
#if canImport(UIKit)
import UIKit
#endif

/// Narrow native bridge exposing Node and Python runtimes to NativeScript
/// via Objective-C metadata. NativeScript discovers `@objc` classes through
/// runtime reflection, so marking this class `@objc` and `@objcMembers`
/// allows NativeScript Core code to call these methods directly without
/// a separate RPC or broker layer.
///
/// Each method preserves the underlying runtime's cancellation, lifecycle,
/// and error semantics. No duplicate runtime is created.
@objc(HanlinNativeServicesBridge)
@objcMembers
public final class HanlinNativeServicesBridge: NSObject {

    // MARK: - Canonical Roots

    public private(set) static var activeAppID: String?
    public private(set) static var activeDataRoot: String?
    public private(set) static var activeStateDirectory: String?
    public private(set) static var activeDocumentsDirectory: String?
    public private(set) static var activeCacheDirectory: String?

    public static func setActiveContainer(
        appID: String,
        dataRoot: String,
        stateDir: String,
        docsDir: String,
        cacheDir: String
    ) {
        activeAppID = appID
        activeDataRoot = dataRoot
        activeStateDirectory = stateDir
        activeDocumentsDirectory = docsDir
        activeCacheDirectory = cacheDir
    }

    public static func clearActiveContainer() {
        activeAppID = nil
        activeDataRoot = nil
        activeStateDirectory = nil
        activeDocumentsDirectory = nil
        activeCacheDirectory = nil
    }

    /// The root data directory for the active Mini App.
    public static func dataRootDirectory() -> String? { activeDataRoot }

    /// The private state directory for the active Mini App.
    public static func stateDirectory() -> String? { activeStateDirectory }

    /// The user documents directory for the active Mini App.
    public static func documentsDirectory() -> String? { activeDocumentsDirectory }

    /// The cache directory for the active Mini App.
    public static func cacheDirectory() -> String? { activeCacheDirectory }

    // MARK: - Node Runtime

    /// Execute JavaScript source via the embedded Node runtime.
    ///
    /// - Parameters:
    ///   - source: JavaScript source code string.
    ///   - completion: Called on main thread with (result JSON string, error description).
    public static func executeNode(
        _ source: String,
        completion: @escaping (String?, String?) -> Void
    ) {
        Task { @MainActor in
            do {
                let node = AppRuntimeCore.shared.node
                let result = try await node.executeJavaScript(source: source)
                completion(result.stdout, nil)
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
                let healthy = try await node.healthCheck()
                completion(healthy, nil)
            } catch {
                completion(false, error.localizedDescription)
            }
        }
    }

    // MARK: - Python Runtime

    /// Execute Python source via the embedded Python runtime.
    ///
    /// - Parameters:
    ///   - source: Python source code string.
    ///   - completion: Called on main thread with (result JSON string, error description).
    public static func executePython(
        _ source: String,
        completion: @escaping (String?, String?) -> Void
    ) {
        Task { @MainActor in
            do {
                let python = AppRuntimeCore.shared.python
                let result = try await python.execute(source: source)
                completion(result.stdout, nil)
            } catch {
                completion(nil, error.localizedDescription)
            }
        }
    }

    /// Returns the embedded Python runtime version, or nil if unavailable.
    public static func pythonVersion() -> String? {
        AppRuntimeCore.shared.python.version
    }

    // MARK: - Inter-App Request Broker

    /// Send a canonical inter-app request from NativeScript to another Mini App.
    ///
    /// - Parameters:
    ///   - callerID: The calling app's HanlinAppID raw value.
    ///   - targetID: The target app's HanlinAppID raw value.
    ///   - action: The action identifier raw value.
    ///   - capability: The capability identifier raw value.
    ///   - payloadJSON: JSON-encoded payload string.
    ///   - completion: Called with (response JSON string, error description).
    public static func sendRequest(
        callerID: String,
        targetID: String,
        action: String,
        capability: String,
        payloadJSON: String,
        completion: @escaping (String?, String?) -> Void
    ) {
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
}
