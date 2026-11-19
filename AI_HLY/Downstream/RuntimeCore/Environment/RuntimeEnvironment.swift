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
    private let service = "com.itorah.chavrusachat.runtime"

    func set(_ secret: String, reference: String = UUID().uuidString) throws -> String {
        guard let data = secret.data(using: .utf8) else { throw RuntimeCoreError.runtimeFailure("The secret could not be encoded.") }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference
        ]
        var query = base
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        var status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Replacing an existing item must not delete its value before the
            // replacement has succeeded.
            let replacement: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            status = SecItemUpdate(base as CFDictionary, replacement as CFDictionary)
        }
        guard status == errSecSuccess else {
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
        _ = try RuntimePolicy.validatedEnvironment([validName: value])
        let itemID = id ?? UUID()
        let original = try items().first { $0.id == itemID }
        var stagedReference: String?
        let reference: String?
        if isSecret {
            if value.isEmpty, let saved = original?.secretReference {
                reference = saved
            } else {
                let staged = try await secrets.set(value)
                stagedReference = staged
                reference = staged
            }
        } else {
            reference = nil
        }
        let item = RuntimeEnvironmentItem(
            id: itemID,
            name: validName,
            isEnabled: isEnabled,
            scope: scope,
            value: isSecret ? nil : value,
            secretReference: reference
        )
        do {
            // Secret staging suspends this actor. Merge into the latest collection,
            // and refuse a stale edit of this same item instead of losing an edit.
            var all = try items()
            guard all.first(where: { $0.id == itemID }) == original else {
                throw RuntimeCoreError.runtimeFailure("The saved environment changed. Reload it before saving again.")
            }
            if let index = all.firstIndex(where: { $0.id == itemID }) {
                all[index] = item
            } else {
                all.append(item)
            }
            try persist(all)
        } catch {
            // A failed write can leave its completion uncertain. Only remove a
            // staged value when the persisted registry proves it is unreferenced.
            if let stagedReference,
               let retained = try? persistedSecretReferences(),
               !retained.contains(stagedReference) {
                await secrets.remove(reference: stagedReference)
            }
            throw error
        }
        if let previous = original?.secretReference, previous != reference,
           !(try items()).contains(where: { $0.secretReference == previous }) {
            await secrets.remove(reference: previous)
        }
        return item
    }

    func delete(id: UUID) async throws {
        var all = try items()
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        let reference = all.remove(at: index).secretReference
        try persist(all)
        if let reference, !all.contains(where: { $0.secretReference == reference }) {
            await secrets.remove(reference: reference)
        }
    }

    private func persistedSecretReferences() throws -> Set<String> {
        let url = fileLayout.environmentRegistry
        // A directory cannot contain an environment document. Other read or
        // decode failures remain uncertain and must retain staged Keychain data.
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return []
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain,
               failure.code == NSFileReadNoSuchFileError || failure.code == NSFileNoSuchFileError {
                return []
            }
            throw error
        }
        return Set(try JSONDecoder().decode([RuntimeEnvironmentItem].self, from: data)
            .compactMap(\.secretReference))
    }

    /// Requested scope order is precedence, independent of saved-item ordering.
    func resolved(scopes: [RuntimeEnvironmentScope], overrides: [String: String] = [:]) async throws -> [String: String] {
        // Imported code receives only its explicit invocation environment. Shared Keychain
        // values and another engine's configured secrets are never implicitly inherited.
        if overrides["SKILL_ID"] != nil { return try RuntimePolicy.validatedEnvironment(overrides) }
        var result: [String: String] = [:]
        let all = try items()
        for scope in scopes {
            for item in all where item.isEnabled && item.scope == scope {
                if let value = item.value { result[item.name] = value }
                else if let reference = item.secretReference { result[item.name] = try await secrets.value(reference: reference) }
            }
        }
        result.merge(overrides) { _, explicit in explicit }
        return try RuntimePolicy.validatedEnvironment(result)
    }

    private func persist(_ items: [RuntimeEnvironmentItem]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(items).write(to: fileLayout.environmentRegistry, options: [.atomic, .completeFileProtection])
        cached = items
    }
}
