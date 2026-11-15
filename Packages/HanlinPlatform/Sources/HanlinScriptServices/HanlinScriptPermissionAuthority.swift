import Foundation
import HanlinPlatformContracts

public actor HanlinScriptPermissionAuthority {
    private var grants: [HanlinGrantID: HanlinPermissionGrant] = [:]
    private var revoked = Set<HanlinGrantID>()
    private let now: @Sendable () -> Date

    public init(
        grants: [HanlinPermissionGrant] = [],
        revokedGrantIDs: Set<HanlinGrantID> = [],
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.grants = Dictionary(uniqueKeysWithValues: grants.map { ($0.id, $0) })
        revoked = revokedGrantIDs
        self.now = now
    }

    public func replace(grants: [HanlinPermissionGrant], revokedGrantIDs: Set<HanlinGrantID> = []) {
        self.grants = Dictionary(uniqueKeysWithValues: grants.map { ($0.id, $0) })
        revoked = revokedGrantIDs
    }

    public func revoke(_ id: HanlinGrantID) { revoked.insert(id) }

    public func upsert(_ grant: HanlinPermissionGrant) {
        grants[grant.id] = grant
        revoked.remove(grant.id)
    }

    public func authorize(
        capability: HanlinCapabilityID,
        context: HanlinScriptServiceContext
    ) -> HanlinEffectivePermissionResult {
        // Legacy grant payloads remain decodable; device services enforce iOS
        // authorization themselves. No extra Hanlin approval is required.
        .allowed
    }
}
