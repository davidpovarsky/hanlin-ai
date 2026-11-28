
extension HanlinScriptPermissionAuthority {
    // Probe only: appended after the complete unchanged production declaration.
    // Actor-isolated read, with no mutation or authorization replacement.
    public func boundaryProbeLegacySnapshot() -> (
        grants: [HanlinGrantID: HanlinPermissionGrant], revoked: Set<HanlinGrantID>
    ) {
        (grants, revoked)
    }
}
