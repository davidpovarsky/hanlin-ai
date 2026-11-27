import Foundation
import HanlinPlatformContracts

/// Independent UI selection for a notification. The existing event envelope
/// continues to identify its prepared Host action; UI and action entrypoints
/// intentionally have different entrypoint IDs within the same installation.
public struct HanlinNotificationPresentationPayload: Codable, Hashable, Sendable {
    public static let userInfoKey = "hanlin-miniapp-presentation"
    public let schemaVersion: UInt32
    public let identity: HanlinScriptExtensionIdentity
    public let parameters: HanlinJSONValue

    public init(schemaVersion: UInt32 = 1, identity: HanlinScriptExtensionIdentity,
                parameters: HanlinJSONValue = .null) throws {
        guard schemaVersion == 1, identity.generation > 0, !identity.entrypointID.isEmpty else {
            throw HanlinNativePresentationError.invalidRequest
        }
        _ = try HanlinInstalledPackageID(validating: identity.installedPackageID.rawValue)
        _ = try HanlinPackageID(validating: identity.packageID.rawValue)
        _ = try parameters.canonicalJSONData(limits: .unbounded)
        self.schemaVersion = schemaVersion
        self.identity = identity
        self.parameters = parameters
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, identity, parameters }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(schemaVersion: values.decode(UInt32.self, forKey: .schemaVersion),
            identity: values.decode(HanlinScriptExtensionIdentity.self, forKey: .identity),
            parameters: values.decodeIfPresent(HanlinJSONValue.self, forKey: .parameters) ?? .null)
    }

    public static func decode(userInfo: [AnyHashable: Any]) throws -> Self? {
        guard let value = userInfo[userInfoKey] else { return nil }
        guard var object = value as? [String: Any], JSONSerialization.isValidJSONObject(object),
              Set(object.keys).isSubset(of: ["schemaVersion", "identity", "parameters"]) else {
            throw HanlinNativePresentationError.invalidRequest
        }
        let plain = object["parameters"] ?? NSNull()
        let parameters = try HanlinJSONValue.decodeCanonicalJSON(
            JSONSerialization.data(withJSONObject: plain, options: [.fragmentsAllowed]), limits: .unbounded)
        object["parameters"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(parameters))
        return try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: object))
    }

    public func userInfo() throws -> [AnyHashable: Any] {
        guard var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as? [String: Any] else {
            throw HanlinNativePresentationError.invalidRequest
        }
        object["parameters"] = try JSONSerialization.jsonObject(
            with: parameters.canonicalJSONData(limits: .unbounded), options: [.fragmentsAllowed])
        return [Self.userInfoKey: object]
    }

    public func request(sessionID: UUID = UUID()) throws -> HanlinNativePresentationRequest {
        .init(identity: identity, kind: .notificationUI, sessionID: sessionID,
              parameters: try HanlinValue(jsonValue: parameters))
    }

    public func validateContinuation(_ event: HanlinNotificationEvent) throws {
        guard event.identity.installedPackageID == identity.installedPackageID,
              event.identity.packageID == identity.packageID,
              event.identity.generation == identity.generation else {
            throw HanlinNativePresentationError.invalidRequest
        }
    }

    /// Returns the canonical receipt, which may still be queued. Calling this
    /// method never executes a Host handler and never promotes a receipt status.
    public func enqueueContinuation(_ event: HanlinNotificationEvent,
                                    in store: HanlinScriptExtensionStore,
                                    now: Date = .now) throws -> HanlinInvocationReceipt {
        try validateContinuation(event)
        guard let snapshot = try store.loadReadOnly() else { throw HanlinNativePresentationError.unavailable }
        _ = try HanlinNativePresentationExecutor.descriptor(for: request(), in: snapshot)
        return try HanlinNotificationInvocation.enqueue(event, in: store, now: now)
    }
}
