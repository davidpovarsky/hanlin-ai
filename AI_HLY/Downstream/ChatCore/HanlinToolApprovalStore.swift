import Foundation

/// Durable grant identity deliberately excludes conversation/run/call IDs.
/// A provider, account, manifest, or permission change produces a different scope.
struct HanlinToolApprovalScope: Codable, Hashable, Sendable {
    let app: String
    let account: String
    let workspace: String
    let providerID: String
    let toolID: String
    let manifestFingerprint: String
    let permissionFingerprint: String

    var isValid: Bool {
        [app, account, workspace, providerID, toolID].allSatisfy {
            !$0.isEmpty && $0.utf8.count <= 512
        } && [manifestFingerprint, permissionFingerprint].allSatisfy {
            $0.utf8.count == 64 && $0.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
    }
}

/// Local-device consent records. Existing allow-once history is never imported.
/// Every lookup reloads storage, so revocation affects all conversation owners.
@MainActor
final class HanlinToolApprovalStore {
    struct Grant: Codable, Hashable, Identifiable, Sendable {
        let id: UUID
        let scope: HanlinToolApprovalScope
        let toolTitle: String
        let createdAt: Date
    }
    private struct Document: Codable {
        let version: Int
        let grants: [Grant]
    }

    static let shared = HanlinToolApprovalStore()
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "hanlin.tool-consent.scoped-grants.v1") {
        self.defaults = defaults
        self.key = key
    }

    var grants: [Grant] {
        guard let data = defaults.data(forKey: key), data.count <= 2_097_152,
              let document = try? JSONDecoder().decode(Document.self, from: data),
              document.version == 1, document.grants.count <= 4_096,
              document.grants.allSatisfy({ $0.scope.isValid }) else { return [] }
        return document.grants.sorted { $0.createdAt > $1.createdAt }
    }

    func allows(_ scope: HanlinToolApprovalScope) -> Bool {
        scope.isValid && grants.contains { $0.scope == scope }
    }

    @discardableResult
    func remember(_ scope: HanlinToolApprovalScope, title: String, now: Date = .now) -> Bool {
        guard scope.isValid else { return false }
        var updated = grants
        if updated.contains(where: { $0.scope == scope }) { return true }
        // Superseded grants never authorize a changed manifest. Remove them only
        // after a new explicit decision, keeping the revocation list understandable.
        updated.removeAll {
            $0.scope.app == scope.app && $0.scope.account == scope.account
                && $0.scope.workspace == scope.workspace && $0.scope.providerID == scope.providerID
                && $0.scope.toolID == scope.toolID
                && $0.scope.permissionFingerprint == scope.permissionFingerprint
        }
        guard updated.count < 4_096 else { return false }
        updated.append(.init(id: UUID(), scope: scope, toolTitle: String(title.prefix(512)), createdAt: now))
        return persist(updated) && allows(scope)
    }

    @discardableResult
    func revoke(id: UUID) -> Bool {
        persist(grants.filter { $0.id != id })
    }

    @discardableResult
    func revokeAll() -> Bool {
        persist([])
    }

    private func persist(_ grants: [Grant]) -> Bool {
        guard let data = try? JSONEncoder().encode(Document(version: 1, grants: grants)),
              data.count <= 2_097_152 else { return false }
        defaults.set(data, forKey: key)
        return defaults.data(forKey: key) == data
    }
}
