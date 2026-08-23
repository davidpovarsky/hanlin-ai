import Foundation
import HanlinPlatformContracts

public actor HanlinScriptServiceBroker {
    public struct Limits: Hashable, Sendable {
        public let storageBytesPerPackage: Int
        public let filesBytesPerPackage: Int
        public let maximumNetworkResponseBytes: Int
        public let maximumRedirects: Int
        public let maximumAuditEvents: Int

        public init(
            storageBytesPerPackage: Int = 4 << 20,
            filesBytesPerPackage: Int = 16 << 20,
            maximumNetworkResponseBytes: Int = 8 << 20,
            maximumRedirects: Int = 5,
            maximumAuditEvents: Int = 1_000
        ) {
            self.storageBytesPerPackage = storageBytesPerPackage
            self.filesBytesPerPackage = filesBytesPerPackage
            self.maximumNetworkResponseBytes = maximumNetworkResponseBytes
            self.maximumRedirects = maximumRedirects
            self.maximumAuditEvents = maximumAuditEvents
        }
    }

    private let permissions: HanlinScriptPermissionAuthority
    private let network: any HanlinScriptNetworkTransport
    private let assistant: any HanlinScriptAssistantTransport
    private let dialogs: any HanlinScriptDialogTransport
    private let openURLTransport: any HanlinScriptOpenURLTransport
    private let pasteboard: any HanlinScriptPasteboardTransport
    private let device: any HanlinScriptDeviceTransport
    private let limits: Limits
    private let now: @Sendable () -> Date
    private var storage: [String: [String: HanlinValue]] = [:]
    private var files: [String: [String: Data]] = [:]
    private var audit: [HanlinScriptServiceAuditEvent] = []
    private var auditSequence: UInt64 = 1

    public init(
        permissions: HanlinScriptPermissionAuthority,
        network: any HanlinScriptNetworkTransport,
        assistant: any HanlinScriptAssistantTransport,
        dialogs: any HanlinScriptDialogTransport,
        openURL: any HanlinScriptOpenURLTransport,
        pasteboard: any HanlinScriptPasteboardTransport,
        device: any HanlinScriptDeviceTransport,
        limits: Limits = .init(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.permissions = permissions
        self.network = network
        self.assistant = assistant
        self.dialogs = dialogs
        openURLTransport = openURL
        self.pasteboard = pasteboard
        self.device = device
        self.limits = limits
        self.now = now
    }

    public func storageValue(for key: String, context: HanlinScriptServiceContext) async throws -> HanlinValue? {
        try await authorize("storage", operation: "storage.get", context: context)
        return storage[namespace(context)]?[key]
    }

    public func setStorageValue(_ value: HanlinValue?, for key: String, context: HanlinScriptServiceContext) async throws {
        try await authorize("storage", operation: "storage.set", context: context)
        let namespace = namespace(context)
        var values = storage[namespace] ?? [:]
        values[key] = value
        let size = try values.reduce(0) { try $0 + $1.key.utf8.count + $1.value.canonicalJSONData().count }
        guard size <= limits.storageBytesPerPackage else { throw HanlinScriptServiceError.quotaExceeded("storage") }
        storage[namespace] = values
    }

    public func readFile(_ path: String, context: HanlinScriptServiceContext) async throws -> Data? {
        try await authorize("files", operation: "files.read", context: context)
        return files[namespace(context)]?[try normalized(path)]
    }

    public func writeFile(_ data: Data, path: String, context: HanlinScriptServiceContext) async throws {
        try await authorize("files", operation: "files.write", context: context)
        let namespace = namespace(context)
        var values = files[namespace] ?? [:]
        values[try normalized(path)] = data
        guard values.values.reduce(0, { $0 + $1.count }) <= limits.filesBytesPerPackage else {
            throw HanlinScriptServiceError.quotaExceeded("files")
        }
        files[namespace] = values
    }

    public func fetch(_ request: HanlinScriptNetworkRequest, context: HanlinScriptServiceContext) async throws -> HanlinScriptNetworkResponse {
        try await authorize("network", operation: "network.fetch", context: context)
        guard request.url.scheme?.lowercased() == "https" else { throw HanlinScriptServiceError.insecureURL }
        try Task.checkCancellation()
        do {
            let response = try await network.fetch(request)
            try Task.checkCancellation()
            guard response.redirectCount <= limits.maximumRedirects else { throw HanlinScriptServiceError.redirectLimit }
            guard response.finalURL.scheme?.lowercased() == "https" else { throw HanlinScriptServiceError.insecureURL }
            guard response.body.count <= limits.maximumNetworkResponseBytes else { throw HanlinScriptServiceError.responseTooLarge }
            return response
        } catch is CancellationError {
            throw HanlinScriptServiceError.cancelled
        }
    }

    public func assistantStream(
        prompt: String,
        schema: HanlinValue?,
        context: HanlinScriptServiceContext
    ) async throws -> AsyncThrowingStream<HanlinValue, Error> {
        try await authorize("assistant", operation: "assistant.stream", context: context)
        return assistant.stream(prompt: prompt, schema: schema, sessionID: context.sessionID)
    }

    public func presentDialog(_ request: HanlinScriptDialogRequest, context: HanlinScriptServiceContext) async throws -> String? {
        try await authorize("dialog", operation: "dialog.present", context: context)
        guard context.permissionContext.canPresentUI else { throw HanlinScriptServiceError.unavailable("presentation") }
        return try await dialogs.present(request)
    }

    public func deviceSnapshot(context: HanlinScriptServiceContext) async throws -> HanlinScriptDeviceSnapshot {
        try await authorize("device", operation: "device.snapshot", context: context)
        return await device.snapshot()
    }

    public func openURL(_ url: URL, context: HanlinScriptServiceContext) async throws -> Bool {
        try await authorize("open-url", operation: "openURL", context: context)
        guard context.permissionContext.userGesturePresent else { throw HanlinScriptServiceError.permissionDenied("user_gesture") }
        return await openURLTransport.open(url)
    }

    public func readPasteboard(context: HanlinScriptServiceContext) async throws -> String? {
        try await authorize("pasteboard", operation: "pasteboard.read", context: context)
        return await pasteboard.readText()
    }

    public func writePasteboard(_ value: String, context: HanlinScriptServiceContext) async throws {
        try await authorize("pasteboard", operation: "pasteboard.write", context: context)
        await pasteboard.writeText(value)
    }

    public func auditSnapshot() -> [HanlinScriptServiceAuditEvent] { audit }

    private func authorize(_ rawCapability: String, operation: String, context: HanlinScriptServiceContext) async throws {
        let capability: HanlinCapabilityID
        do { capability = try HanlinCapabilityID(validating: rawCapability) }
        catch { throw HanlinScriptServiceError.permissionDenied("invalid_capability") }
        let result = await permissions.authorize(capability: capability, context: context)
        let allowed = result == .allowed
        record(operation: operation, capability: rawCapability, allowed: allowed, detail: result.rawValue, context: context)
        guard allowed else { throw HanlinScriptServiceError.permissionDenied(rawCapability) }
    }

    private func record(
        operation: String,
        capability: String,
        allowed: Bool,
        detail: String,
        context: HanlinScriptServiceContext
    ) {
        audit.append(.init(
            sequence: auditSequence,
            timestamp: now(),
            sessionID: context.sessionID,
            operation: operation,
            capability: capability,
            allowed: allowed,
            safeDetail: detail
        ))
        auditSequence &+= 1
        if audit.count > limits.maximumAuditEvents { audit.removeFirst(audit.count - limits.maximumAuditEvents) }
    }

    private func namespace(_ context: HanlinScriptServiceContext) -> String {
        switch context.subject {
        case let .package(id): id.rawValue
        case let .app(id, package): "\(package?.rawValue ?? "native"):\(id.rawValue)"
        case let .provider(id): "provider:\(id.rawValue)"
        }
    }

    private func normalized(_ path: String) throws -> String {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else {
            throw HanlinScriptServiceError.invalidPath(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(".."), !components.contains("") else { throw HanlinScriptServiceError.invalidPath(path) }
        return components.joined(separator: "/")
    }
}
