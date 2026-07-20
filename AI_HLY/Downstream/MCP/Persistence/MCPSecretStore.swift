import Foundation
import Security

actor MCPSecretStore {
    private let service = "cherryai.com.AI-Hanlin.mcp"

    func set(_ secret: String, reference: String = UUID().uuidString) throws -> String {
        guard let data = secret.data(using: .utf8) else { throw MCPError.secretUnavailable }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference
        ]
        SecItemDelete(base as CFDictionary)
        var query = base
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            throw MCPError.secretUnavailable
        }
        return reference
    }

    func value(reference: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw MCPError.secretUnavailable
        }
        return value
    }

    func remove(reference: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference
        ]
        SecItemDelete(query as CFDictionary)
    }
}
