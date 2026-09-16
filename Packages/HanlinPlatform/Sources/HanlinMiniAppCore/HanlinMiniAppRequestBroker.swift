import Foundation
import HanlinPlatformContracts

public struct HanlinMiniAppRequest: Codable, Hashable, Sendable {
    public let id: UUID
    public let caller: HanlinAppID
    public let target: HanlinAppID
    public let action: HanlinActionID
    public let capability: HanlinCapabilityID
    public let payload: HanlinValue

    public init(
        id: UUID = UUID(),
        caller: HanlinAppID,
        target: HanlinAppID,
        action: HanlinActionID,
        capability: HanlinCapabilityID,
        payload: HanlinValue
    ) {
        self.id = id
        self.caller = caller
        self.target = target
        self.action = action
        self.capability = capability
        self.payload = payload
    }
}

public struct HanlinMiniAppResponse: Codable, Hashable, Sendable {
    public let requestID: UUID
    public let value: HanlinValue

    public init(requestID: UUID, value: HanlinValue) {
        self.requestID = requestID
        self.value = value
    }
}

public enum HanlinMiniAppRequestError: Error, Equatable, Sendable {
    case routeNotFound
    case capabilityMismatch
    case unauthorized
    case payloadTooLarge
    case responseTooLarge
    case timedOut
    case cancelled
}

public struct HanlinMiniAppRequestAuditEvent: Codable, Hashable, Sendable {
    public let timestamp: Date
    public let requestID: UUID
    public let caller: HanlinAppID
    public let target: HanlinAppID
    public let action: HanlinActionID
    public let allowed: Bool
    public let outcome: String
    public let payloadBytes: Int

    public init(
        timestamp: Date,
        requestID: UUID,
        caller: HanlinAppID,
        target: HanlinAppID,
        action: HanlinActionID,
        allowed: Bool,
        outcome: String,
        payloadBytes: Int
    ) {
        self.timestamp = timestamp
        self.requestID = requestID
        self.caller = caller
        self.target = target
        self.action = action
        self.allowed = allowed
        self.outcome = outcome
        self.payloadBytes = payloadBytes
    }
}

public actor HanlinMiniAppRequestBroker {
    public typealias Handler = @Sendable (HanlinMiniAppRequest) async throws -> HanlinValue
    public typealias Authorizer = @Sendable (HanlinMiniAppRequest) async -> Bool

    public struct Limits: Hashable, Sendable {
        public let maximumPayloadBytes: Int
        public let maximumResponseBytes: Int
        public let timeout: Duration
        public let maximumAuditEvents: Int

        public init(
            maximumPayloadBytes: Int = 1_048_576,
            maximumResponseBytes: Int = 4_194_304,
            timeout: Duration = .seconds(15),
            maximumAuditEvents: Int = 1_000
        ) {
            self.maximumPayloadBytes = maximumPayloadBytes
            self.maximumResponseBytes = maximumResponseBytes
            self.timeout = timeout
            self.maximumAuditEvents = maximumAuditEvents
        }
    }

    private struct RouteRegistration {
        let capability: HanlinCapabilityID
        let handler: Handler
    }

    private struct RouteKey: Hashable {
        let target: HanlinAppID
        let action: HanlinActionID
    }

    private var routes: [RouteKey: RouteRegistration] = [:]
    private var auditLog: [HanlinMiniAppRequestAuditEvent] = []
    private let limits: Limits
    private let authorizer: Authorizer?

    public init(limits: Limits = .init(), authorizer: Authorizer? = nil) {
        self.limits = limits
        self.authorizer = authorizer
    }

    public func register(
        target: HanlinAppID,
        action: HanlinActionID,
        capability: HanlinCapabilityID,
        handler: @escaping Handler
    ) {
        routes[RouteKey(target: target, action: action)] = RouteRegistration(
            capability: capability,
            handler: handler
        )
    }

    public func unregister(target: HanlinAppID, action: HanlinActionID) {
        routes.removeValue(forKey: RouteKey(target: target, action: action))
    }

    public func request(_ request: HanlinMiniAppRequest) async throws -> HanlinMiniAppResponse {
        let payloadBytes = try estimatedBytes(request.payload)
        guard payloadBytes <= limits.maximumPayloadBytes else {
            recordAudit(request: request, allowed: false, outcome: "payload_too_large", bytes: payloadBytes)
            throw HanlinMiniAppRequestError.payloadTooLarge
        }
        guard let registration = routes[RouteKey(target: request.target, action: request.action)] else {
            recordAudit(request: request, allowed: false, outcome: "route_not_found", bytes: payloadBytes)
            throw HanlinMiniAppRequestError.routeNotFound
        }
        guard registration.capability == request.capability else {
            recordAudit(request: request, allowed: false, outcome: "capability_mismatch", bytes: payloadBytes)
            throw HanlinMiniAppRequestError.capabilityMismatch
        }
        if let authorizer, await !authorizer(request) {
            recordAudit(request: request, allowed: false, outcome: "unauthorized", bytes: payloadBytes)
            throw HanlinMiniAppRequestError.unauthorized
        }

        let handler = registration.handler
        do {
            let responseValue = try await withThrowingTaskGroup(of: HanlinValue.self) { group in
                group.addTask {
                    try await handler(request)
                }
                group.addTask { [timeout = limits.timeout] in
                    try await Task.sleep(for: timeout)
                    throw HanlinMiniAppRequestError.timedOut
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            let responseBytes = try estimatedBytes(responseValue)
            guard responseBytes <= limits.maximumResponseBytes else {
                recordAudit(request: request, allowed: true, outcome: "response_too_large", bytes: payloadBytes)
                throw HanlinMiniAppRequestError.responseTooLarge
            }
            recordAudit(request: request, allowed: true, outcome: "success", bytes: payloadBytes)
            return HanlinMiniAppResponse(requestID: request.id, value: responseValue)
        } catch let error as HanlinMiniAppRequestError {
            recordAudit(request: request, allowed: true, outcome: "\(error)", bytes: payloadBytes)
            throw error
        } catch {
            recordAudit(request: request, allowed: true, outcome: "failure: \(error)", bytes: payloadBytes)
            throw error
        }
    }

    public func auditEvents() -> [HanlinMiniAppRequestAuditEvent] {
        auditLog
    }

    private func recordAudit(request: HanlinMiniAppRequest, allowed: Bool, outcome: String, bytes: Int) {
        let event = HanlinMiniAppRequestAuditEvent(
            timestamp: .now,
            requestID: request.id,
            caller: request.caller,
            target: request.target,
            action: request.action,
            allowed: allowed,
            outcome: outcome,
            payloadBytes: bytes
        )
        auditLog.append(event)
        if auditLog.count > limits.maximumAuditEvents {
            auditLog.removeFirst(auditLog.count - limits.maximumAuditEvents)
        }
    }

    private func estimatedBytes(_ value: HanlinValue) throws -> Int {
        try JSONEncoder().encode(value).count
    }
}
