import Foundation
import HanlinPlatformContracts
import HanlinScriptServices

@main
struct OriginalBoundaryProbe {
    static func grant(package: String, expiresAt: Date?) throws -> HanlinPermissionGrant {
        .init(id: try HanlinGrantID(validating: "grant.shared"),
              requestID: try HanlinPermissionRequestID(validating: "request.\(package)"),
              subject: .package(try HanlinInstalledPackageID(validating: package)),
              scope: .init(capabilityID: try HanlinCapabilityID(validating: "storage"),
                           constraints: .object(["path": .string(package)])),
              conditions: [.init(origin: .scriptPackage, requiresUserGesture: true, expiresAt: expiresAt)],
              source: .user, policyVersion: .init(major: 1, minor: 0),
              issuedAt: Date(timeIntervalSince1970: 1))
    }

    static func main() async throws {
        let first = try grant(package: "first", expiresAt: Date(timeIntervalSince1970: 5))
        let second = try grant(package: "second", expiresAt: nil)
        let mode = CommandLine.arguments[1]
        let authority: HanlinScriptPermissionAuthority
        if mode == "init-identical" {
            authority = HanlinScriptPermissionAuthority(grants: [first, first], revokedGrantIDs: [first.id])
        } else if mode == "replace-conflicting" {
            authority = HanlinScriptPermissionAuthority(grants: [first])
            await authority.replace(grants: [first, second], revokedGrantIDs: [first.id])
        } else {
            throw ProbeError.unknownMode
        }
        let context = HanlinScriptServiceContext(
            subject: .package(try HanlinInstalledPackageID(validating: "unrelated")),
            permissionContext: .init(origin: .scriptPackage, userGesturePresent: false, canPresentUI: false),
            grantIDs: [first.id], sessionID: try HanlinSessionID(validating: "session.probe"))
        let result = await authority.authorize(capability: try HanlinCapabilityID(validating: "storage"), context: context)
        guard result == .allowed else { throw ProbeError.changedLegacyAuthorization }
        print("PASS: \(mode)")
    }

    enum ProbeError: Error { case unknownMode, changedLegacyAuthorization }
}
