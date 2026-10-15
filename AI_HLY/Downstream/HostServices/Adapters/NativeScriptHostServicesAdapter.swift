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

    private struct RegisteredActionHandler {
        typealias InvokeFn = (String, String, @escaping (String?, String?) -> Void) -> Void
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

    /// Compute app container paths using the same layout as HanlinMiniAppDataStore,
    /// without requiring actor isolation. This is safe because the layout is fixed
    /// (applicationSupport/Hanlin/MiniApps/{appID}/{area}) and directories are
    /// created lazily by the store on first actual read/write.
    private func containerPath(for appID: HanlinAppID, area: String) -> String? {
        guard let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = support
            .appending(path: "Hanlin/MiniApps", directoryHint: .isDirectory)
            .appending(path: appID.rawValue, directoryHint: .isDirectory)
            .appending(path: area, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path(percentEncoded: false)
    }

    @objc(dataRootDirectory)
    public func dataRootDirectory() -> String? {
        guard let appID = context.appID else { return nil }
        return containerPath(for: appID, area: "Data")
    }

    @objc(stateDirectory)
    public func stateDirectory() -> String? {
        guard let appID = context.appID else { return nil }
        return containerPath(for: appID, area: "State")
    }

    @objc(documentsDirectory)
    public func documentsDirectory() -> String? {
        guard let appID = context.appID else { return nil }
        return containerPath(for: appID, area: "Documents")
    }

    @objc(cacheDirectory)
    public func cacheDirectory() -> String? {
        guard let appID = context.appID else { return nil }
        return containerPath(for: appID, area: "Cache")
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
                safeCompletion(output, nil)
            } catch {
                safeCompletion(nil, error.localizedDescription)
            }
        }
    }

    @objc(pythonVersion)
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

    // MARK: - JSON Value Bridging

    private static func decodeJSONPayload(_ payloadJSON: String) throws -> HanlinValue {
        let trimmed = payloadJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "{}" {
            return .object([:])
        }
        guard let data = trimmed.data(using: .utf8) else {
            return .object([:])
        }
        // First try standard untagged JSON via HanlinJSONValue
        if let jsonVal = try? HanlinJSONValue.decodeCanonicalJSON(data),
           let hanlinVal = try? HanlinValue(jsonValue: jsonVal) {
            return hanlinVal
        }
        // Then try tagged JSON representation
        if let taggedVal = try? HanlinValue.decodeCanonicalJSON(data) {
            return taggedVal
        }
        if let decodedVal = try? JSONDecoder().decode(HanlinValue.self, from: data) {
            return decodedVal
        }
        // Fall back to attempting parse with full diagnostic throw
        let jsonVal = try HanlinJSONValue.decodeCanonicalJSON(data)
        return try HanlinValue(jsonValue: jsonVal)
    }

    private static func serializeUntaggedJSON(_ value: HanlinValue) throws -> String {
        if let jsonVal = try? value.jsonValue() {
            let data = try jsonVal.canonicalJSONData()
            if let str = String(data: data, encoding: .utf8) {
                return str
            }
        }
        let fallbackData = try value.canonicalJSONData()
        return String(data: fallbackData, encoding: .utf8) ?? "{}"
    }

    public func sendRequest(
        _ targetID: String,
        action: String,
        capability: String,
        payloadJSON: String,
        completion: @escaping (String?, String?) -> Void
    ) {
        nonisolated(unsafe) let safeCompletion = completion
        guard let caller = context.appID else {
            safeCompletion(nil, "Unauthorized: No active Mini App session context.")
            return
        }
        let ctx = context
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
                let payload = try Self.decodeJSONPayload(payloadJSON)

                // When target is the caller itself, handle directly via locally registered actions.
                // An unregistered action MUST fail closed with routeNotFound (never synthesize a self-echo!).
                if target == caller {
                    guard self.hasRegisteredAction(actionID) else {
                        throw HanlinMiniAppRequestError.routeNotFound
                    }
                    let responseValue = try await self.invokeRegisteredAction(
                        actionID,
                        capability: capabilityID,
                        caller: caller,
                        payload: payload
                    )
                    let responseString = try Self.serializeUntaggedJSON(responseValue)
                    safeCompletion(responseString, nil)
                    return
                }

                let broker = await MainActor.run { HanlinMiniAppHost.shared.requestBroker }
                let request = HanlinMiniAppRequest(
                    caller: caller,
                    target: target,
                    action: actionID,
                    capability: capabilityID,
                    payload: payload
                )
                let response = try await broker.request(request)
                let responseString = try Self.serializeUntaggedJSON(response.value)
                safeCompletion(responseString, nil)
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
        guard let actionID = try? HanlinActionID(validating: action),
              let capabilityID = try? HanlinCapabilityID(validating: capability) else {
            return
        }
        // NSLock.withLock{} guards the dictionary mutation.
        // nonisolated(unsafe) suppresses Swift 6 Sendable warning on the closure capture;
        // the lock ensures no concurrent access to registeredActionHandlers.
        nonisolated(unsafe) let safeHandler = handler
        lock.withLock {
            registeredActionIDs.insert(actionID)
            registeredActionHandlers[actionID] = RegisteredActionHandler(
                capability: capabilityID,
                invoke: safeHandler
            )
        }
        if let appID = context.appID {
            Task { [weak self] in
                guard let self else { return }
                let broker = await MainActor.run { HanlinMiniAppHost.shared.requestBroker }
                await broker.register(target: appID, action: actionID, capability: capabilityID) { [weak self] req in
                    guard let self else { throw HanlinMiniAppRequestError.routeNotFound }
                    return try await self.invokeRegisteredAction(
                        req.action,
                        capability: req.capability,
                        caller: req.caller,
                        payload: req.payload
                    )
                }
            }
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

        let payloadJSON = try Self.serializeUntaggedJSON(payload)
        return try await withCheckedThrowingContinuation { continuation in
            invokeHandler(caller.rawValue, payloadJSON) { responseJSON, errorString in
                if let errorString {
                    continuation.resume(throwing: NSError(
                        domain: "HanlinMiniAppRequest",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: errorString]
                    ))
                } else if let responseJSON {
                    do {
                        let value = try Self.decodeJSONPayload(responseJSON)
                        continuation.resume(returning: value)
                    } catch {
                        continuation.resume(returning: .null)
                    }
                } else {
                    continuation.resume(returning: .null)
                }
            }
        }
    }
}
