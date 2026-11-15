import Foundation
import HanlinMiniAppCore
import HanlinPlatformContracts
import HanlinProductSplit
import Testing

/// Tests the exported leaf product against the real canonical broker. These
/// synthetic records never open a user store or authenticate an OS transport.
@Suite struct RegisteredSplitIntegrationTests {
    private func request() throws -> SplitBridgeRequest {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return try SplitBridgeRequest(
            caller: HanlinAppID(validating: "hanlin.ai"),
            target: HanlinAppID(validating: "hanlin.fixture"),
            installedPackage: HanlinInstalledPackageID(validating: "fixture.package"),
            session: HanlinAppSessionID(validating: "fixture.session"),
            chat: UUID(), generation: 7,
            action: HanlinActionID(validating: "fixture.read"),
            capability: HanlinCapabilityID(validating: "fixture.read"),
            issuedAt: now, expiresAt: now.addingTimeInterval(60),
            payload: .object(["text": .string("שלום")])
        )
    }

    @Test func canonicalBrokerRoundTripPreservesOriginAndConsumesReturn() async throws {
        let request = try request()
        let canonical = request.canonicalRequest()
        let broker = HanlinMiniAppRequestBroker { candidate in candidate == canonical }
        await broker.register(target: request.target, action: request.action,
                              capability: request.capability) { $0.payload }
        var ledger = SplitBridgeLedger()
        try ledger.begin(request, now: request.issuedAt, routeAvailable: true, authorized: true)
        try ledger.dispatch(request.id, now: request.issuedAt, currentGeneration: 7,
                            authorized: true, companionInstalled: true,
                            transportReady: true, online: true)
        let response = try await broker.request(canonical)
        let returned = try request.canonicalReturn(response)
        let origin = try ledger.accept(returned, now: request.issuedAt,
                                       currentGeneration: 7, authenticatedSender: request.target,
                                       authorized: true)
        #expect(origin == request)
        #expect(ledger.record(request.id)?.outcome == .result(request.payload))
        #expect(throws: SplitBridgeFailure.duplicate) {
            _ = try ledger.accept(returned, now: request.issuedAt, currentGeneration: 7,
                                  authenticatedSender: request.target, authorized: true)
        }
    }

    @Test func canonicalAuthorityDenialIsNotBypassedByAdapter() async throws {
        let request = try request()
        let broker = HanlinMiniAppRequestBroker { _ in false }
        await broker.register(target: request.target, action: request.action,
                              capability: request.capability) { _ in .string("must not run") }
        await #expect(throws: HanlinMiniAppRequestError.unauthorized) {
            _ = try await broker.request(request.canonicalRequest())
        }
    }

    @Test func absentTransportCannotAdvanceToDispatched() throws {
        let request = try request()
        var ledger = SplitBridgeLedger()
        try ledger.begin(request, now: request.issuedAt, routeAvailable: true, authorized: true)
        #expect(throws: SplitBridgeFailure.transportUnavailable) {
            try ledger.dispatch(request.id, now: request.issuedAt, currentGeneration: 7,
                                authorized: true, companionInstalled: true,
                                transportReady: false, online: true)
        }
        #expect(ledger.record(request.id)?.phase == .pending)
    }

    @Test func registeredMigrationIsPureAndPreservesIdentityBytes() throws {
        let bytes = Data("fixture identity and permission bytes".utf8)
        let source = try SplitStoreSnapshot(storeID: "fixture.source", revision: 1,
                                            files: ["identity.json": bytes])
        let destination = try SplitStoreSnapshot(storeID: "fixture.destination", revision: 0, files: [:])
        let plan = try SplitMigrationPlan(id: HanlinMigrationID(validating: "fixture.copy"),
                                          source: source, destination: destination,
                                          copies: ["identity.json": "identity.json"])
        let output = try plan.dryRun(source: source, destination: destination)
        #expect(output.files["identity.json"] == bytes)
        #expect(source.files["identity.json"] == bytes)
        #expect(destination.files.isEmpty)
    }
}
