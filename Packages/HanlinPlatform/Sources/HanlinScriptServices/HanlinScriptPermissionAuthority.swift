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
        for id in context.grantIDs.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let grant = grants[id], grant.subject == context.subject else { continue }
            if revoked.contains(id) { continue }
            guard grant.scope.capabilityID == capability else { continue }
            var valid = true
            for condition in grant.conditions {
                if let origin = condition.origin, origin != context.permissionContext.origin { valid = false }
                if condition.requiresUserGesture, !context.permissionContext.userGesturePresent { valid = false }
                if let expiry = condition.expiresAt, expiry <= now() { valid = false }
            }
            if valid { return .allowed }
        }
        return .missingGrant
    }
}
