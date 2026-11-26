import Foundation
import HanlinPlatformContracts

/// The versioned data in a notification's "hanlin-miniapp-event" custom key.
/// It names an already installed action; it never contains executable source.
public struct HanlinNotificationEvent: Codable, Hashable, Sendable {
    public static let userInfoKey = "hanlin-miniapp-event"
    public static let deliveryInfoKey = "hanlin-miniapp-delivery"

    public let schemaVersion: UInt32
    public let id: UUID
    public let createdAt: Date
    public let expiresAt: Date
    public let appID: HanlinAppID
    public let identity: HanlinScriptExtensionIdentity
    public let actionID: HanlinActionID
    public let parameters: HanlinJSONValue

    public init(schemaVersion: UInt32 = 1, id: UUID, createdAt: Date, expiresAt: Date,
                appID: HanlinAppID, identity: HanlinScriptExtensionIdentity,
                actionID: HanlinActionID, parameters: HanlinJSONValue = .null) throws {
        // Whole Unix milliseconds are stable across APNs JSON, Swift Date,
        // service delivery and a later Host response for the same event ID.
        let createdMilliseconds = (createdAt.timeIntervalSince1970 * 1_000).rounded()
        let expiryMilliseconds = (expiresAt.timeIntervalSince1970 * 1_000).rounded()
        guard schemaVersion == 1, createdMilliseconds.isFinite, expiryMilliseconds.isFinite,
              expiryMilliseconds > createdMilliseconds,
              expiryMilliseconds - createdMilliseconds <= HanlinInvocationDelivery.maximumLifetime * 1_000,
              !identity.entrypointID.isEmpty else {
            throw HanlinInvocationQueueError.invalidEnvelope
        }
        _ = try parameters.canonicalJSONData(limits: .unbounded)
        self.schemaVersion = schemaVersion
        self.id = id
        self.createdAt = Date(timeIntervalSince1970: createdMilliseconds / 1_000)
        self.expiresAt = Date(timeIntervalSince1970: expiryMilliseconds / 1_000)
        self.appID = appID
        self.identity = identity
        self.actionID = actionID
        self.parameters = parameters
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, id, createdAtUnixMilliseconds, expiresAtUnixMilliseconds
        case appID, identity, actionID, parameters
    }

    private struct Field: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: Field.self)
        guard Set(fields.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.rawValue)) else {
            throw HanlinInvocationQueueError.invalidEnvelope
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let created = try values.decode(Double.self, forKey: .createdAtUnixMilliseconds)
        let expiry = try values.decode(Double.self, forKey: .expiresAtUnixMilliseconds)
        guard created.isFinite, expiry.isFinite, created == created.rounded(), expiry == expiry.rounded() else {
            throw HanlinInvocationQueueError.invalidEnvelope
        }
        try self.init(
            schemaVersion: values.decode(UInt32.self, forKey: .schemaVersion),
            id: values.decode(UUID.self, forKey: .id),
            createdAt: Date(timeIntervalSince1970: created / 1_000),
            expiresAt: Date(timeIntervalSince1970: expiry / 1_000),
            appID: values.decode(HanlinAppID.self, forKey: .appID),
            identity: values.decode(HanlinScriptExtensionIdentity.self, forKey: .identity),
            actionID: values.decode(HanlinActionID.self, forKey: .actionID),
            parameters: values.decode(HanlinJSONValue.self, forKey: .parameters))
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(id, forKey: .id)
        try values.encode((createdAt.timeIntervalSince1970 * 1_000).rounded(), forKey: .createdAtUnixMilliseconds)
        try values.encode((expiresAt.timeIntervalSince1970 * 1_000).rounded(), forKey: .expiresAtUnixMilliseconds)
        try values.encode(appID, forKey: .appID)
        try values.encode(identity, forKey: .identity)
        try values.encode(actionID, forKey: .actionID)
        try values.encode(parameters, forKey: .parameters)
    }

    /// Untagged notifications are unrelated. A malformed tagged event is an
    /// explicit ingress error, never a fallback to some other package/action.
    public static func decode(userInfo: [AnyHashable: Any]) throws -> Self? {
        guard let value = userInfo[userInfoKey] else { return nil }
        guard var object = value as? [String: Any], JSONSerialization.isValidJSONObject(object),
              let rawParameters = object[CodingKeys.parameters.rawValue] else {
            throw HanlinInvocationQueueError.invalidEnvelope
        }
        // APNs carries plain JSON; HanlinJSONValue's Codable representation is
        // tagged for internal storage. Convert only this external boundary.
        let parameters = try HanlinJSONValue.decodeCanonicalJSON(
            JSONSerialization.data(withJSONObject: rawParameters, options: [.fragmentsAllowed]),
            limits: .unbounded)
        object[CodingKeys.parameters.rawValue] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(parameters))
        return try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: object))
    }

    public func userInfo() throws -> [AnyHashable: Any] {
        guard var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as? [String: Any] else {
            throw HanlinInvocationQueueError.invalidEnvelope
        }
        object[CodingKeys.parameters.rawValue] = try JSONSerialization.jsonObject(
            with: parameters.canonicalJSONData(limits: .unbounded), options: [.fragmentsAllowed])
        return [Self.userInfoKey: object]
    }
}
