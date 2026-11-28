import Foundation
import HanlinPlatformContracts

public struct HanlinScriptServiceContext: Sendable {
    public let subject: HanlinPermissionSubject
    public let permissionContext: HanlinPermissionRequestContext
    public let grantIDs: Set<HanlinGrantID>
    public let sessionID: HanlinSessionID

    public init(
        subject: HanlinPermissionSubject,
        permissionContext: HanlinPermissionRequestContext,
        grantIDs: Set<HanlinGrantID>,
        sessionID: HanlinSessionID
    ) {
        self.subject = subject
        self.permissionContext = permissionContext
        self.grantIDs = grantIDs
        self.sessionID = sessionID
    }
}

public enum HanlinScriptServiceError: Error, Equatable, Sendable {
    case permissionDenied(String)
    case quotaExceeded(String)
    case invalidPath(String)
    case insecureURL
    case redirectLimit
    case responseTooLarge
    case unavailable(String)
    case cancelled
}

public struct HanlinScriptNetworkRequest: Codable, Hashable, Sendable {
    public let url: URL
    public let method: String
    public let headers: [String: String]
    public let body: Data?

    public init(url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct HanlinScriptNetworkResponse: Codable, Hashable, Sendable {
    public let finalURL: URL
    public let status: Int
    public let headers: [String: String]
    public let body: Data
    public let redirectCount: Int

    public init(finalURL: URL, status: Int, headers: [String: String], body: Data, redirectCount: Int) {
        self.finalURL = finalURL
        self.status = status
        self.headers = headers
        self.body = body
        self.redirectCount = redirectCount
    }
}

public protocol HanlinScriptNetworkTransport: Sendable {
    func fetch(_ request: HanlinScriptNetworkRequest) async throws -> HanlinScriptNetworkResponse
}

public protocol HanlinScriptAssistantTransport: Sendable {
    func stream(prompt: String, schema: HanlinValue?, sessionID: HanlinSessionID) -> AsyncThrowingStream<HanlinValue, Error>
}

public struct HanlinScriptDialogRequest: Codable, Hashable, Sendable {
    public let title: String
    public let message: String?
    public let actions: [String]
    public init(title: String, message: String? = nil, actions: [String]) {
        self.title = title
        self.message = message
        self.actions = actions
    }
}

public protocol HanlinScriptDialogTransport: Sendable {
    func present(_ request: HanlinScriptDialogRequest) async throws -> String?
}

public protocol HanlinScriptOpenURLTransport: Sendable {
    func open(_ url: URL) async -> Bool
}

public protocol HanlinScriptPasteboardTransport: Sendable {
    func readText() async -> String?
    func writeText(_ value: String) async
}

public struct HanlinScriptDeviceSnapshot: Codable, Hashable, Sendable {
    public let localeIdentifier: String
    public let timeZoneIdentifier: String
    public let batteryLevel: Double?
    public let isLowPowerModeEnabled: Bool

    public init(
        localeIdentifier: String,
        timeZoneIdentifier: String,
        batteryLevel: Double?,
        isLowPowerModeEnabled: Bool
    ) {
        self.localeIdentifier = localeIdentifier
        self.timeZoneIdentifier = timeZoneIdentifier
        self.batteryLevel = batteryLevel
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
    }
}

public protocol HanlinScriptDeviceTransport: Sendable {
    func snapshot() async -> HanlinScriptDeviceSnapshot
}

public struct HanlinScriptServiceAuditEvent: Codable, Hashable, Sendable {
    public let sequence: UInt64
    public let timestamp: Date
    public let sessionID: HanlinSessionID
    public let operation: String
    public let capability: String
    public let allowed: Bool
    public let safeDetail: String

    public init(
        sequence: UInt64,
        timestamp: Date,
        sessionID: HanlinSessionID,
        operation: String,
        capability: String,
        allowed: Bool,
        safeDetail: String
    ) {
        self.sequence = sequence
        self.timestamp = timestamp
        self.sessionID = sessionID
        self.operation = operation
        self.capability = capability
        self.allowed = allowed
        self.safeDetail = safeDetail
    }
}
