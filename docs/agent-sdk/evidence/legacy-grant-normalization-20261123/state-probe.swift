import Foundation
import HanlinPlatformContracts
import HanlinScriptServices

@main
struct LegacyStorageStateProbe {
    static func grant(id: String = "grant.shared", package: String, capability: String = "storage",
                      expiresAt: Date?) throws -> HanlinPermissionGrant {
        .init(id: try HanlinGrantID(validating: id),
              requestID: try HanlinPermissionRequestID(validating: "request.\(package)"),
              subject: .package(try HanlinInstalledPackageID(validating: package)),
              scope: .init(capabilityID: try HanlinCapabilityID(validating: capability),
                           constraints: .object(["path": .string(package)])),
              conditions: [.init(origin: .scriptPackage, requiresUserGesture: true, expiresAt: expiresAt)],
              source: .user, policyVersion: .init(major: 1, minor: 0),
              issuedAt: Date(timeIntervalSince1970: 1))
    }

    static func require(_ valid: Bool, _ label: String) throws {
        if !valid { throw Failure(label: label) }
    }

    static func main() async throws {
        let first = try grant(package: "first", expiresAt: Date(timeIntervalSince1970: 5))
        let second = try grant(package: "second", capability: "files", expiresAt: nil)
        let old = try grant(id: "grant.old", package: "old", expiresAt: nil)
        let unrelatedRevoked = try HanlinGrantID(validating: "grant.revoked.unrelated")
        let revoked: Set<HanlinGrantID> = [first.id, unrelatedRevoked]
        for (mode, last) in [("identical", first), ("conflicting", second)] {
            let initialized = HanlinScriptPermissionAuthority(
                grants: [first, last], revokedGrantIDs: revoked,
                now: { Date(timeIntervalSince1970: 10) })
            let initialState = await initialized.boundaryProbeLegacySnapshot()
            try require(initialState.grants == [first.id: last], "init \(mode) whole-record normalization")
            try require(initialState.revoked == revoked, "init \(mode) explicit revocations")
            print("PASS: init-\(mode)-whole-record-and-revocations")

            let replaced = HanlinScriptPermissionAuthority(grants: [old], revokedGrantIDs: [old.id])
            await replaced.replace(grants: [first, last], revokedGrantIDs: revoked)
            let replacementState = await replaced.boundaryProbeLegacySnapshot()
            try require(replacementState.grants == [first.id: last], "replace \(mode) replaces old snapshot")
            try require(replacementState.revoked == revoked, "replace \(mode) explicit revocations")
            print("PASS: replace-\(mode)-whole-record-and-revocations")

            await replaced.upsert(first)
            let upserted = await replaced.boundaryProbeLegacySnapshot()
            try require(upserted.grants == [first.id: first], "original upsert complete record")
            try require(upserted.revoked == [unrelatedRevoked], "original upsert clears only matching revocation")
            await replaced.revoke(first.id)
            let revokedAgain = await replaced.boundaryProbeLegacySnapshot()
            try require(revokedAgain.revoked == revoked, "original revoke inserts matching ID")
            await replaced.replace(grants: [], revokedGrantIDs: revoked)
            let cleared = await replaced.boundaryProbeLegacySnapshot()
            try require(cleared.grants.isEmpty && cleared.revoked == revoked, "empty replacement preserves supplied revocations")
            print("PASS: \(mode)-original-upsert-revoke-and-empty-replace")
        }
    }

    struct Failure: Error { let label: String }
}
