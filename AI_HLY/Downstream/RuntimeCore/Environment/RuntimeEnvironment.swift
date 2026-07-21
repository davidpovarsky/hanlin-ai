import Foundation
import Security

enum RuntimeEnvironmentScope: Hashable, Sendable, Codable, Identifiable {
    case shared
    case node
    case python
    case javaScriptCore
    case shell
    case mcpServer(UUID)
    case execution(UUID)

    var id: String {
        switch self {
        case .shared: "shared"
        case .node: "node"
        case .python: "python"
        case .javaScriptCore: "javascriptcore"
        case .shell: "shell"
        case .mcpServer(let id): "mcp:\(id.uuidString.lowercased())"
        case .execution(let id): "execution:\(id.uuidString.lowercased())"
        }
    }
}

struct RuntimeEnvironmentItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var scope: RuntimeEnvironmentScope
    var value: String?
    var secretReference: String?

    var isSecret: Bool { secretReference != nil }

    init(id: UUID = UUID(), name: String, isEnabled: Bool = true, scope: RuntimeEnvironmentScope, value: String? = nil, secretReference: String? = nil) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.scope = scope
        self.value = value
        self.secretReference = secretReference
    }
}

actor RuntimeSecretStore {
    private let service = "cherryai.com.AI-Hanlin.runtime"

    func set(_ secret: String, reference: String = UUID().uuidString) throws -> String {
        guard let data = secret.data(using: .utf8) else { throw RuntimeCoreError.runtimeFailure("The secret could not be encoded.") }
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
            throw RuntimeCoreError.runtimeFailure("The secret could not be saved in Keychain.")
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
            throw RuntimeCoreError.runtimeFailure("The saved secret is unavailable.")
        }
        return value
    }

    func remove(reference: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference
        ] as CFDictionary)
    }
}

actor RuntimeEnvironmentStore {
    private let fileLayout: RuntimeFileLayout
    private let secrets: RuntimeSecretStore
    private var cached: [RuntimeEnvironmentItem]?

    init(fileLayout: RuntimeFileLayout = .default, secrets: RuntimeSecretStore = RuntimeSecretStore()) {
        self.fileLayout = fileLayout
        self.secrets = secrets
    }

    func items() throws -> [RuntimeEnvironmentItem] {
        if let cached { return cached }
        try fileLayout.prepareIfNeeded()
        guard FileManager.default.fileExists(atPath: fileLayout.environmentRegistry.path) else {
            cached = []
            return []
        }
        let decoded = try JSONDecoder().decode([RuntimeEnvironmentItem].self, from: Data(contentsOf: fileLayout.environmentRegistry))
        cached = decoded
        return decoded
    }

    @discardableResult
    func save(name: String, value: String, scope: RuntimeEnvironmentScope, isEnabled: Bool, isSecret: Bool, replacing id: UUID? = nil) async throws -> RuntimeEnvironmentItem {
        let validName = try RuntimePolicy.validateEnvironmentName(name.trimmingCharacters(in: .whitespacesAndNewlines))
        var all = try items()
        let existingIndex = id.flatMap { requested in all.firstIndex { $0.id == requested } }
        if let existingIndex, let reference = all[existingIndex].secretReference, !isSecret { await secrets.remove(reference: reference) }
        let reference: String?
        if isSecret {
            if value.isEmpty, let existingIndex, let saved = all[existingIndex].secretReference { reference = saved }
            else {
                if let existingIndex, let saved = all[existingIndex].secretReference { await secrets.remove(reference: saved) }
                reference = try await secrets.set(value)
            }
        } else { reference = nil }
        let item = RuntimeEnvironmentItem(
            id: id ?? UUID(),
            name: validName,
            isEnabled: isEnabled,
            scope: scope,
            value: isSecret ? nil : value,
            secretReference: reference
        )
        if let existingIndex { all[existingIndex] = item } else { all.append(item) }
        try persist(all)
        return item
    }

    func delete(id: UUID) async throws {
        var all = try items()
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        if let reference = all[index].secretReference { await secrets.remove(reference: reference) }
        all.remove(at: index)
        try persist(all)
    }

    func resolved(scopes: [RuntimeEnvironmentScope]) async throws -> [String: String] {
        var result: [String: String] = [:]
        let wanted = Set(scopes)
        for item in try items() where item.isEnabled && wanted.contains(item.scope) {
            if let value = item.value { result[item.name] = value }
            else if let reference = item.secretReference { result[item.name] = try await secrets.value(reference: reference) }
        }
        return result
    }

    private func persist(_ items: [RuntimeEnvironmentItem]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(items).write(to: fileLayout.environmentRegistry, options: [.atomic, .completeFileProtection])
        cached = items
    }
}
