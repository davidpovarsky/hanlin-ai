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
        self.grants = Self.indexLegacyGrants(grants)
        revoked = revokedGrantIDs
        self.now = now
    }

    public func replace(grants: [HanlinPermissionGrant], revokedGrantIDs: Set<HanlinGrantID> = []) {
        self.grants = Self.indexLegacyGrants(grants)
        revoked = revokedGrantIDs
    }

    // Bulk legacy metadata follows the same ordered, whole-record assignment as upsert.
    // Identical repeats coalesce; a later same-ID record replaces all earlier fields.
    // The caller's explicit revocation set is assigned separately and is never cleared here.
    static func indexLegacyGrants(_ grants: [HanlinPermissionGrant]) -> [HanlinGrantID: HanlinPermissionGrant] {
        grants.reduce(into: [:]) { indexed, grant in
            indexed[grant.id] = grant
        }
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
