import Foundation
import Security

/// A Keychain mechanism, with service, sharing and synchronization chosen by the host.
/// Stored handles are ordinary versioned identifiers, never SecItem persistent references.
public struct HanlinKeychainCredentialStore: Sendable {
    public enum Kind: String, Codable, Sendable {
        case model, search, tool
    }

    public enum Accessibility: Sendable {
        case whenUnlocked, afterFirstUnlock

        fileprivate var value: CFString {
            switch self {
            case .whenUnlocked: kSecAttrAccessibleWhenUnlocked
            case .afterFirstUnlock: kSecAttrAccessibleAfterFirstUnlock
            }
        }
    }

    public enum Failure: LocalizedError, Sendable {
        case invalidReference, unavailable(OSStatus), invalidPayload, verificationFailed

        public var errorDescription: String? {
            switch self {
            case .invalidReference:
                "The stored credential reference is not supported."
            case .unavailable:
                "The saved credential is not available on this device. Unlock the device or allow Keychain synchronization to finish."
            case .invalidPayload:
                "The saved credential could not be read."
            case .verificationFailed:
                "The credential could not be verified after saving."
            }
        }
    }

    private struct Payload: Codable {
        let version: Int
        let reference: String
        let kind: Kind
        let value: String
        // Kept inside the protected Keychain payload for explicit migration rollback.
        // This may be a legacy value or another immutable Keychain handle.
        let previousStoredValue: String?
    }

    private static let reservedPrefix = "hanlin-keychain:"
    private static let versionPrefix = "hanlin-keychain:v1:"
    private let service: String
    private let accessGroup: String?
    private let synchronizable: Bool
    private let accessibility: Accessibility

    public init(service: String, accessGroup: String?, synchronizable: Bool,
                accessibility: Accessibility) {
        self.service = service
        self.accessGroup = accessGroup
        self.synchronizable = synchronizable
        self.accessibility = accessibility
    }

    public static func isReference(_ storedValue: String) -> Bool {
        storedValue.hasPrefix(reservedPrefix)
    }

    /// Legacy values remain readable until an explicit host save replaces them.
    /// An unavailable or malformed handle is never returned as a provider secret.
    public func resolve(_ storedValue: String?, kind: Kind) throws -> String? {
        guard let storedValue else { return nil }
        guard Self.isReference(storedValue) else { return storedValue }
        return try readPayload(storedValue, kind: kind).value
    }

    /// Stages one immutable generation, verifies the whole payload, and only then
    /// returns a handle the host may commit to its original record.
    /// No old item is updated or deleted. Failed/uncertain commits keep generations.
    public func stage(_ value: String, kind: Kind, previousStoredValue: String?) throws -> String {
        let reference = Self.versionPrefix + kind.rawValue + ":" + UUID().uuidString.lowercased()
        let payload = Payload(version: 1, reference: reference, kind: kind,
                              value: value, previousStoredValue: previousStoredValue)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        var attributes = try query(reference, kind: kind)
        attributes[kSecAttrAccessible as String] = accessibility.value
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.unavailable(status) }
        // Compare exact bytes, including the recovery representation. String
        // canonical equivalence is not sufficient for an opaque provider secret.
        guard try readData(reference, kind: kind) == data else {
            throw Failure.verificationFailed
        }
        return reference
    }

    /// Used only by an explicit host rollback. Retains the current generation.
    public func previousStoredValue(for reference: String, kind: Kind) throws -> String? {
        try readPayload(reference, kind: kind).previousStoredValue
    }

    private func query(_ reference: String, kind: Kind) throws -> [String: Any] {
        let parts = reference.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "hanlin-keychain", parts[1] == "v1",
              parts[2] == Substring(kind.rawValue),
              let id = UUID(uuidString: String(parts[3])),
              id.uuidString.lowercased() == String(parts[3]), !service.isEmpty else {
            throw Failure.invalidReference
        }
        var result: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference,
            kSecAttrSynchronizable as String: synchronizable,
            kSecUseDataProtectionKeychain as String: true
        ]
        if let accessGroup { result[kSecAttrAccessGroup as String] = accessGroup }
        return result
    }

    private func readPayload(_ reference: String, kind: Kind) throws -> Payload {
        let data = try readData(reference, kind: kind)
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == 1, payload.reference == reference,
              payload.kind == kind else { throw Failure.invalidPayload }
        return payload
    }

    private func readData(_ reference: String, kind: Kind) throws -> Data {
        var attributes = try query(reference, kind: kind)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        guard status == errSecSuccess else { throw Failure.unavailable(status) }
        guard let data = result as? Data else { throw Failure.invalidPayload }
        return data
    }
}
