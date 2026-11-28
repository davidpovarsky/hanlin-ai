import Foundation
import Testing
@testable import HanlinPlatformContracts

@Test
func logicalToolIdentityIsProviderQualifiedAndAliasesAreNotIdentity() throws {
    let toolID = try HanlinToolID(validating: "search")
    let first = HanlinLogicalToolID(
        providerInstanceID: try HanlinProviderInstanceID(validating: "native.system"),
        localToolID: toolID
    )
    let second = HanlinLogicalToolID(
        providerInstanceID: try HanlinProviderInstanceID(validating: "mcp.123e4567-e89b-12d3-a456-426614174000"),
        localToolID: toolID
    )
    #expect(first != second)

    let revision = try HanlinDescriptorRevision(1)
    let table = try HanlinToolRoutingTable(
        revision: HanlinCatalogRevision(7),
        routes: [
            .init(alias: "search", logicalToolID: first, descriptorRevision: revision),
            .init(alias: "mcp__server__search", logicalToolID: second, descriptorRevision: revision)
        ]
    )
    #expect(table.route(alias: "search")?.logicalToolID == first)
    #expect(table.route(alias: "mcp__server__search")?.logicalToolID == second)

    #expect(throws: HanlinContractError.self) {
        try HanlinToolRoutingTable(
            revision: HanlinCatalogRevision(8),
            routes: [
                .init(alias: "search", logicalToolID: first, descriptorRevision: revision),
                .init(alias: "search", logicalToolID: second, descriptorRevision: revision)
            ]
        )
    }
}

@Test
func permissionValuesKeepDeclarationDecisionGrantAndEffectivenessSeparate() throws {
    let capability = try HanlinCapabilityID(validating: "network.fetch")
    let subject = HanlinPermissionSubject.provider(
        try HanlinProviderInstanceID(validating: "native.system")
    )
    let scope = HanlinPermissionScope(
        capabilityID: capability,
        constraints: .object(["host": .string("example.com")])
    )
    let requestID = try HanlinPermissionRequestID(validating: "permission.request.1")
    let request = HanlinPermissionRequest(
        id: requestID,
        subject: subject,
        scopes: [scope],
        purpose: "Fetch public data",
        context: .init(
            origin: .nativeModule,
            userGesturePresent: true,
            canPresentUI: true
        ),
        desiredDuration: .persistentLocalDevice,
        createdAt: Date(timeIntervalSince1970: 1)
    )
    let grantID = try HanlinGrantID(validating: "grant.1")
    let grant = HanlinPermissionGrant(
        id: grantID,
        requestID: requestID,
        subject: subject,
        scope: scope,
        source: .user,
        policyVersion: .init(major: 1, minor: 0),
        issuedAt: Date(timeIntervalSince1970: 2)
    )
    let decision = HanlinPermissionDecision(
        id: try HanlinPermissionDecisionID(validating: "decision.1"),
        requestID: requestID,
        outcome: .granted,
        grantIDs: [grantID],
        decidedAt: Date(timeIntervalSince1970: 2),
        safeReason: "User approved"
    )
    let effective = HanlinEffectivePermission(
        subject: subject,
        scope: scope,
        result: .allowed,
        grantID: grantID,
        policyEvaluationID: try HanlinPolicyEvaluationID(validating: "evaluation.1"),
        evaluatedAt: Date(timeIntervalSince1970: 3)
    )

    #expect(request.id == grant.requestID)
    #expect(decision.grantIDs == [grant.id])
    #expect(effective.grantID == grant.id)
    #expect(grant.storageScope == .localDevice)
}

@Test
func appAndRuntimeSessionSnapshotsRemainPortableValues() throws {
    let appSession = HanlinAppSessionDescriptor(
        id: try HanlinAppSessionID(validating: "session.app.1"),
        appID: try HanlinAppID(validating: "nativeapp.textstudio"),
        presentation: .fullScreen,
        state: .active,
        createdAt: Date(timeIntervalSince1970: 1),
        stateChangedAt: Date(timeIntervalSince1970: 2)
    )
    let runtimeSession = HanlinRuntimeSessionDescriptor(
        id: try HanlinRuntimeSessionID(validating: "session.runtime.1"),
        providerInstanceID: try HanlinProviderInstanceID(validating: "runtimecore.node"),
        parentAppSessionID: appSession.id,
        kind: .node,
        runtimeVersion: "24.5.0",
        state: .ready,
        createdAt: Date(timeIntervalSince1970: 1),
        stateChangedAt: Date(timeIntervalSince1970: 2),
        activeExecutionCount: 0
    )

    let data = try JSONEncoder().encode(runtimeSession)
    #expect(try JSONDecoder().decode(HanlinRuntimeSessionDescriptor.self, from: data) == runtimeSession)
    #expect(runtimeSession.parentAppSessionID == appSession.id)
}
