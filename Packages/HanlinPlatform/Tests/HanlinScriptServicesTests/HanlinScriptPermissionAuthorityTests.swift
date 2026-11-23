import Foundation
import HanlinPlatformContracts
@testable import HanlinScriptServices
import Testing

@Suite("Legacy scripting grant input normalization")
struct HanlinScriptPermissionAuthorityTests {
    @Test("Identical repeated legacy grants coalesce")
    func identicalLegacyRowsCoalesce() throws {
        let grant = try grant(package: "first", expiresAt: Date(timeIntervalSince1970: 5))
        let indexed = HanlinScriptPermissionAuthority.indexLegacyGrants([grant, grant])
        #expect(indexed.count == 1)
        #expect(indexed[grant.id] == grant)
    }

    @Test("Conflicting IDs retain the last complete record without merging fields")
    func conflictingLegacyRowsRetainLastCompleteRecord() throws {
        let first = try grant(package: "first", expiresAt: Date(timeIntervalSince1970: 5))
        let second = try grant(package: "second", capability: "files", expiresAt: nil)
        let unrelated = try grant(id: "grant.unrelated", package: "third", expiresAt: nil)
        let indexed = HanlinScriptPermissionAuthority.indexLegacyGrants([first, unrelated, second])
        #expect(indexed.count == 2)
        #expect(indexed[first.id] == second)
        #expect(indexed[unrelated.id] == unrelated)
        #expect(HanlinScriptPermissionAuthority.indexLegacyGrants([second, first])[first.id] == first)
    }

    @Test("The public initializer accepts repeated rows without adding a legacy permission gate",
          arguments: [false, true])
    func publicInitializerAcceptsDuplicates(conflicting: Bool) async throws {
        let first = try grant(package: "first", expiresAt: Date(timeIntervalSince1970: 5))
        let last = conflicting ? try grant(package: "second", capability: "files", expiresAt: nil) : first
        let authority = HanlinScriptPermissionAuthority(
            grants: [first, last], revokedGrantIDs: [first.id],
            now: { Date(timeIntervalSince1970: 10) })
        #expect(await authority.authorize(
            capability: try HanlinCapabilityID(validating: "storage"),
            context: try context(grantID: first.id)) == .allowed)
    }

    @Test("Public replacement accepts repeated rows without changing the existing authorization path",
          arguments: [false, true])
    func publicReplacementAcceptsDuplicates(conflicting: Bool) async throws {
        let first = try grant(package: "first", expiresAt: Date(timeIntervalSince1970: 5))
        let last = conflicting ? try grant(package: "second", capability: "files", expiresAt: nil) : first
        let authority = HanlinScriptPermissionAuthority(grants: [first])
        await authority.replace(grants: [first, last], revokedGrantIDs: [first.id])
        #expect(await authority.authorize(
            capability: try HanlinCapabilityID(validating: "storage"),
            context: try context(grantID: first.id)) == .allowed)
    }

    private func grant(id: String = "grant.shared", package: String,
                       capability: String = "storage", expiresAt: Date?) throws -> HanlinPermissionGrant {
        .init(id: try HanlinGrantID(validating: id),
              requestID: try HanlinPermissionRequestID(validating: "request.\(package)"),
              subject: .package(try HanlinInstalledPackageID(validating: package)),
              scope: .init(capabilityID: try HanlinCapabilityID(validating: capability),
                           constraints: .object(["path": .string(package)])),
              conditions: [.init(origin: .scriptPackage, requiresUserGesture: true, expiresAt: expiresAt)],
              source: .user, policyVersion: .init(major: 1, minor: 0),
              issuedAt: Date(timeIntervalSince1970: 1))
    }

    private func context(grantID: HanlinGrantID) throws -> HanlinScriptServiceContext {
        .init(subject: .package(try HanlinInstalledPackageID(validating: "unrelated")),
              permissionContext: .init(origin: .scriptPackage, userGesturePresent: false, canPresentUI: false),
              grantIDs: [grantID], sessionID: try HanlinSessionID(validating: "session.probe"))
    }
}
