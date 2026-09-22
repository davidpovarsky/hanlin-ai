import Foundation
import HanlinPlatformContracts
import HanlinMiniAppCore
import HanlinNativeScriptCoreSupport

/// Session-bound host provider implementing `HanlinNativeServicesProvider` for NativeScript.
///
/// Security & Architectural Rules:
/// 1. Caller identity is strictly HOST-BOUND to the session context (`context.appID`).
///    Untrusted scripts cannot supply or spoof their caller identity.
/// 2. All privileged operations (Node, Python, JavaScript, Shell, Network, Inter-App)
///    are capability-gated through `HanlinHostCapabilityAuthority` dynamically.
/// 3. Zero reliance on process-global mutable activeAppID / activeGrantedCapabilities.
public final class NativeScriptHostServicesAdapter: NSObject, @unchecked Sendable, HanlinNativeServicesProvider {
    public let sessionID: String
    public let context: HanlinHostCallContext

    private struct RegisteredActionHandler: Sendable {
        typealias InvokeFn = @Sendable (String, String, @escaping (String?, String?) -> Void) -> Void
        let capability: HanlinCapabilityID
        let invoke: InvokeFn
    }

    private let lock = NSLock()
    private var registeredActionIDs: Set<HanlinActionID> = []
    private var registeredActionHandlers: [HanlinActionID: RegisteredActionHandler] = [:]

    public init(
        appID: HanlinAppID,
        installedPackageID: HanlinInstalledPackageID? = nil,
        grantedCapabilities: Set<String>,
        sessionID: String = UUID().uuidString.lowercased()
    ) {
        self.sessionID = sessionID
        let appSession = try! HanlinAppSessionID(validating: sessionID)
        self.context = HanlinHostCallContext.forMiniApp(
            appID: appID,
            installedPackageID: installedPackageID,
            origin: .nativeModule,
            capabilities: grantedCapabilities,
            sessionID: appSession,
            canPresentUI: true
        )
        super.init()
    }

    // MARK: - Directory Resolution

    public func dataRootDirectory() -> String? {
        guard let appID = context.appID else { return nil }
        return try? MainActor.assumeIsolated {
            try HanlinMiniAppHost.shared.dataStore.prepareContainer(for: appID).data.path(percentEncoded: false)
        }
    }

    public func stateDirectory() -> String? {
        guard let appID = context.appID else { return nil }
        return try? MainActor.assumeIsolated {
            try HanlinMiniAppHost.shared.dataStore.prepareContainer(for: appID).state.path(percentEncoded: false)
        }
    }

    public func documentsDirectory() -> String? {
        guard let appID = context.appID else { return nil }
        return try? MainActor.assumeIsolated {
            try HanlinMiniAppHost.shared.dataStore.prepareContainer(for: appID).documents.path(percentEncoded: false)
        }
    }

    public func cacheDirectory() -> String? {
        guard let appID = context.appID else { return nil }
        return try? MainActor.assumeIsolated {
            try HanlinMiniAppHost.shared.dataStore.prepareContainer(for: appID).cache.path(percentEncoded: false)
        }
    }

    // MARK: - Runtime Execution

    public func executeJavaScript(
        _ source: String,
        completion: @escaping (String?, String?) -> Void
    ) {
        let ctx = context
        nonisolated(unsafe) let safeCompletion = completion
        Task {
            do {
                let result = try await HanlinRuntimeBroker.shared.execute(
                    kind: .javaScriptCore,
                    source: source,
                    context: ctx
                )
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
        let ctx = context
        nonisolated(unsafe) let safeCompletion = completion
        Task {
            do {
                let result = try await HanlinRuntimeBroker.shared.execute(
                    kind: .node,
                    source: source,
                    context: ctx
                )
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
        Task {
            do {
                let snapshot = try await AppRuntimeCore.shared.node.healthCheck()
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
        let ctx = context
        nonisolated(unsafe) let safeCompletion = completion
        Task {
            do {
                let result = try await HanlinRuntimeBroker.shared.execute(
                    kind: .localPython,
                    source: source,
                    context: ctx
                )
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
        let ctx = context
        nonisolated(unsafe) let safeCompletion = completion
        Task {
            do {
                try await HanlinHostServicesBroker.shared.requireCapability("network", context: ctx)
                guard let url = URL(string: urlString), url.scheme?.lowercased() == "https" else {
                    safeCompletion(nil, "Invalid or non-HTTPS URL: \(urlString)")
                    return
                }
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
        guard let caller = context.appID else {
            completion(nil, "Unauthorized: No active Mini App session context.")
            return
        }
        let ctx = context
        nonisolated(unsafe) let safeCompletion = completion
        Task {
            do {
                let canonical = HanlinHostCapabilityAuthority.canonicalCapabilityID(capability)
                let auth = await HanlinHostCapabilityAuthority.shared.authorize(capability: canonical, context: ctx)
                guard auth == .allowed else {
                    safeCompletion(nil, "Permission denied: Mini App does not have '\(capability)' capability.")
                    return
                }
                let target = try HanlinAppID(validating: targetID)
                let actionID = try HanlinActionID(validating: action)
                let capabilityID = try HanlinCapabilityID(validating: canonical)
                let payloadData = payloadJSON.data(using: .utf8) ?? Data()
                let payload = try JSONDecoder().decode(HanlinValue.self, from: payloadData)

                let broker = await MainActor.run { HanlinMiniAppHost.shared.requestBroker }
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
        handler: @escaping @Sendable (String, String, @escaping (String?, String?) -> Void) -> Void
    ) {
        guard let actionID = try? HanlinActionID(validating: action),
              let capabilityID = try? HanlinCapabilityID(validating: capability) else {
            return
        }
        lock.withLock {
            registeredActionIDs.insert(actionID)
            registeredActionHandlers[actionID] = RegisteredActionHandler(
                capability: capabilityID,
                invoke: handler
            )
        }
    }

    public func hasRegisteredAction(_ action: HanlinActionID) -> Bool {
        lock.withLock { registeredActionIDs.contains(action) }
    }

    public var allRegisteredActionIDs: Set<HanlinActionID> {
        lock.withLock { registeredActionIDs }
    }

    public func invokeRegisteredAction(
        _ action: HanlinActionID,
        capability: HanlinCapabilityID,
        caller: HanlinAppID,
        payload: HanlinValue
    ) async throws -> HanlinValue {
        // Extract handler synchronously before any suspension — NSLock requires no await while held
        let invokeHandler: RegisteredActionHandler.InvokeFn = try lock.withLock {
            guard let registration = registeredActionHandlers[action] else {
                throw HanlinMiniAppRequestError.routeNotFound
            }
            guard registration.capability == capability else {
                throw HanlinMiniAppRequestError.capabilityMismatch
            }
            return registration.invoke
        }

        let payloadJSON = try String(data: payload.canonicalJSONData(), encoding: .utf8) ?? "{}"
        return try await withCheckedThrowingContinuation { continuation in
            invokeHandler(caller.rawValue, payloadJSON) { responseJSON, errorString in
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
