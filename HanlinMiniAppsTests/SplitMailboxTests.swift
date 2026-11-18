import Foundation
import HanlinPlatformContracts
import HanlinProductSplit
import HanlinScriptExtensions
import XCTest
@testable import HanlinMiniApps

@MainActor
final class SplitMailboxTests: XCTestCase {
    func testColdReopenReturnsOriginalChatAndConsumesOnce() async throws {
        let group = try fixture()
        defer { try? FileManager.default.removeItem(at: group) }
        let mailbox = try HanlinSplitMailbox(trustedGroupContainer: group), request = try request()
        try prepare(request, mailbox)
        let receiver = SplitDurableReceiver(persistence: mailbox, source: mailbox)
        _ = try await receiver.receive(reference: request.id, context: context(request), now: .now)
        let started = try await receiver.start(reference: request.id, context: context(request), now: .now)
        let attempt = try XCTUnwrap(started.attempt)
        _ = try await receiver.complete(reference: request.id, attempt: attempt, outcome: .result(.string("actual-unit-result")), context: context(request))
        let reopened = try HanlinSplitMailbox(trustedGroupContainer: group)
        let response = try reopened.acceptCompleted(request.id, context: context(request), now: .now)
        XCTAssertEqual(response.request, request)
        XCTAssertEqual(response.outcome, .result(.string("actual-unit-result")))
        XCTAssertThrowsError(try reopened.acceptCompleted(request.id, context: context(request), now: .now))
    }

    func testWrongImmutableOriginAndMissingRecordCannotExecute() async throws {
        let group = try fixture()
        defer { try? FileManager.default.removeItem(at: group) }
        let mailbox = try HanlinSplitMailbox(trustedGroupContainer: group), request = try request()
        XCTAssertThrowsError(try mailbox.original(request.id))
        try prepare(request, mailbox)
        let receiver = SplitDurableReceiver(persistence: mailbox, source: mailbox)
        let wrong = context(request, chat: UUID())
        do {
            _ = try await receiver.receive(reference: request.id, context: wrong, now: .now)
            XCTFail("Wrong original chat was accepted")
        } catch SplitBridgeFailure.correlationMismatch {}
        XCTAssertThrowsError(try mailbox.acceptCompleted(request.id, context: context(request), now: .now))
        XCTAssertEqual(try mailbox.original(request.id), request)
    }

    func testInterruptedAttemptNeverReexecutesOnColdReopen() async throws {
        let group = try fixture()
        defer { try? FileManager.default.removeItem(at: group) }
        let mailbox = try HanlinSplitMailbox(trustedGroupContainer: group), request = try request()
        try prepare(request, mailbox)
        let receiver = SplitDurableReceiver(persistence: mailbox, source: mailbox)
        _ = try await receiver.receive(reference: request.id, context: context(request), now: .now)
        _ = try await receiver.start(reference: request.id, context: context(request), now: .now)
        _ = try await receiver.interrupt(reference: request.id, reason: .cancelled, context: context(request))
        let reopened = try HanlinSplitMailbox(trustedGroupContainer: group)
        let coldReceiver = SplitDurableReceiver(persistence: reopened, source: reopened)
        do {
            _ = try await coldReceiver.start(reference: request.id, context: context(request), now: .now)
            XCTFail("Ambiguous attempt was repeated")
        } catch SplitDurabilityError.outcomeUnknown {}
        XCTAssertThrowsError(try reopened.acceptCompleted(request.id, context: context(request), now: .now))
    }

    func testConcurrentReceiverInstancesGrantOneAttempt() async throws {
        let group = try fixture()
        defer { try? FileManager.default.removeItem(at: group) }
        let mailbox = try HanlinSplitMailbox(trustedGroupContainer: group), request = try request()
        try prepare(request, mailbox)
        let receiver = SplitDurableReceiver(persistence: mailbox, source: mailbox)
        let context = context(request)
        _ = try await receiver.receive(reference: request.id, context: context, now: .now)
        let results = try await withThrowingTaskGroup(of: Bool.self, returning: [Bool].self) { tasks in
            for _ in 0..<2 {
                tasks.addTask {
                    let other = try HanlinSplitMailbox(trustedGroupContainer: group)
                    let receiver = SplitDurableReceiver(persistence: other, source: other)
                    do { _ = try await receiver.start(reference: request.id, context: context, now: .now); return true }
                    catch SplitBridgeFailure.outOfOrder { return false }
                }
            }
            var results: [Bool] = []
            for try await result in tasks { results.append(result) }
            return results
        }
        XCTAssertEqual(results.filter { $0 }.count, 1)
    }

    func testCompanionMissingNeverCreatesDispatchedAuthority() throws {
        let group = try fixture()
        defer { try? FileManager.default.removeItem(at: group) }
        let mailbox = try HanlinSplitMailbox(trustedGroupContainer: group), request = try request()
        XCTAssertThrowsError(try mailbox.prepareDispatch(request, now: .now, currentGeneration: 7,
            authorized: true, routeAvailable: true, handlerAvailable: false)) { error in
            XCTAssertEqual(error as? SplitBridgeFailure, .companionMissing)
        }
        XCTAssertThrowsError(try mailbox.original(request.id))
    }

    func testCorruptMailboxBytesArePreservedAndNeverReset() throws {
        let group = try fixture()
        defer { try? FileManager.default.removeItem(at: group) }
        let mailbox = try HanlinSplitMailbox(trustedGroupContainer: group), request = try request()
        try prepare(request, mailbox)
        let path = try SplitAppStorageLayout.transportRoot(appGroupContainer: group).appending(path: "mailbox.json")
        let corrupt = Data("{broken-original".utf8)
        try corrupt.write(to: path)
        XCTAssertThrowsError(try mailbox.original(request.id))
        XCTAssertEqual(try Data(contentsOf: path), corrupt)
    }

    func testNamespaceAndSlotLinksCannotTouchAIBytes() throws {
        for component in ["HanlinSplit", "HanlinSplit/v1", "HanlinSplit/v1/mailbox.json"] {
            let group = try fixture()
            defer { try? FileManager.default.removeItem(at: group) }
            let ai = group.appending(path: "ScriptingExtensions", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: ai, withIntermediateDirectories: true)
            let sentinel = ai.appending(path: "mailbox.json"), original = Data("AI-retained".utf8)
            try original.write(to: sentinel)
            let link = group.appending(path: component)
            try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: component.hasSuffix(".json") ? sentinel : ai)
            if !component.hasSuffix(".json") {
                XCTAssertThrowsError(try SplitAppStorageLayout.transportRoot(appGroupContainer: group))
                XCTAssertThrowsError(try SplitAppStorageLayout.productTransferRoot(appGroupContainer: group))
            }
            XCTAssertThrowsError(try HanlinSplitMailbox(trustedGroupContainer: group).original(UUID()))
            XCTAssertEqual(try Data(contentsOf: sentinel), original)
        }
    }

    func testBoundedTransactionPreservesOldBytesAndRejectsTraversal() throws {
        let group = try fixture()
        defer { try? FileManager.default.removeItem(at: group) }
        let store = HanlinScriptExtensionStore(root: group.appending(path: "managed", directoryHint: .isDirectory))
        try store.transactManagedState(fileName: "test.json", maximumBytes: 128) { $0 = Data(repeating: 1, count: 128) }
        XCTAssertThrowsError(try store.transactManagedState(fileName: "test.json", maximumBytes: 128) { $0 = Data(repeating: 2, count: 129) })
        let actual = try store.transactManagedState(fileName: "test.json", maximumBytes: 128) { $0 }
        XCTAssertEqual(actual, Data(repeating: 1, count: 128))
        XCTAssertThrowsError(try store.transactManagedState(fileName: "../outside.json", maximumBytes: 128) { $0 = Data() })
        XCTAssertThrowsError(try store.transactManagedState(fileName: ".transaction.lock", maximumBytes: 128) { $0 = Data() })
    }

    func testCanonicalCatalogExportPreservesOriginalActionAndGeneration() async throws {
        let group = try fixture()
        defer { try? FileManager.default.removeItem(at: group) }
        let host = HanlinMiniAppHost.shared
        await host.refresh(installedPackages: [])
        let item = try XCTUnwrap(host.items.first { $0.id.rawValue == "hanlin.demo.swift-parity" })
        let registration = try HanlinSplitLiveTarget.registration(for: item, platform: .shared)
        XCTAssertEqual(registration.installedPackage.rawValue, "compiled.hanlin.demo.swift-parity")
        XCTAssertEqual(registration.generation, 0)
        XCTAssertTrue(registration.descriptor.actions.contains { $0.id.rawValue == "share.value" })
        let mailbox = try HanlinSplitMailbox(trustedGroupContainer: group)
        try mailbox.publishCatalog([registration])
        XCTAssertEqual(try HanlinSplitMailbox(trustedGroupContainer: group).registration(for: item.id), registration)
        XCTAssertThrowsError(try mailbox.publishCatalog([registration, registration]))
        XCTAssertEqual(try mailbox.registration(for: item.id), registration)
    }

    func testOriginInvalidationFencesExecutingReceiverInOneTransaction() async throws {
        let group = try fixture()
        defer { try? FileManager.default.removeItem(at: group) }
        let mailbox = try HanlinSplitMailbox(trustedGroupContainer: group), request = try request()
        try prepare(request, mailbox)
        let receiver = SplitDurableReceiver(persistence: mailbox, source: mailbox)
        _ = try await receiver.receive(reference: request.id, context: context(request), now: .now)
        let started = try await receiver.start(reference: request.id, context: context(request), now: .now)
        try mailbox.cancelDispatch(request.id)
        XCTAssertThrowsError(try mailbox.original(request.id))
        let path = try SplitAppStorageLayout.transportRoot(appGroupContainer: group).appending(path: "mailbox.json")
        let persisted = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        let receiverJSON = try XCTUnwrap(persisted["receiver"])
        let database = try JSONDecoder().decode(SplitReceiverDatabase.self,
            from: JSONSerialization.data(withJSONObject: receiverJSON))
        XCTAssertEqual(database.records[request.id]?.phase, .outcomeUnknown)
        XCTAssertEqual(database.records[request.id]?.attempt, started.attempt)
        do { _ = try await receiver.start(reference: request.id, context: context(request), now: .now); XCTFail("Revoked source granted a second attempt") }
        catch SplitBridgeFailure.outOfOrder {}
    }

    func testConversationSaveFailurePreservesReturnForIdempotentRetry() async throws {
        let group = try fixture()
        defer { try? FileManager.default.removeItem(at: group) }
        let mailbox = try HanlinSplitMailbox(trustedGroupContainer: group), request = try request()
        try await complete(request, mailbox)
        let origin = OriginFixture(request: request, context: context(request))
        origin.failSave = true
        let transport = HanlinSplitForegroundTransport(mailbox: mailbox, openURL: { _ in false })
        let url = SplitForegroundRoute.returnToAI.url(reference: request.id)
        do { try await transport.receiveReturn(url, origin: origin); XCTFail("Failed conversation save consumed result") }
        catch OriginFixture.SaveError.failed {}
        XCTAssertEqual(try mailbox.original(request.id), request)
        XCTAssertTrue(origin.navigation.isEmpty)
        origin.failSave = false
        try await transport.receiveReturn(url, origin: origin)
        XCTAssertEqual(origin.navigation, [request.chat])
        XCTAssertEqual(origin.saved.count, 1)
        do { try await transport.receiveReturn(url, origin: origin); XCTFail("Duplicate return delivered") }
        catch SplitBridgeFailure.outOfOrder {}
        XCTAssertEqual(origin.saved.count, 1)
        XCTAssertEqual(origin.navigation, [request.chat])
    }

    func testRevocationDuringConversationSavePreventsNavigationAndAcceptance() async throws {
        let group = try fixture()
        defer { try? FileManager.default.removeItem(at: group) }
        let mailbox = try HanlinSplitMailbox(trustedGroupContainer: group), request = try request()
        try await complete(request, mailbox)
        let origin = OriginFixture(request: request, context: context(request))
        origin.afterSave = { try mailbox.cancelDispatch(request.id) }
        let transport = HanlinSplitForegroundTransport(mailbox: mailbox, openURL: { _ in false })
        do {
            try await transport.receiveReturn(SplitForegroundRoute.returnToAI.url(reference: request.id), origin: origin)
            XCTFail("Revoked origin was navigated")
        } catch SplitBridgeFailure.duplicate {}
        XCTAssertTrue(origin.navigation.isEmpty)
        XCTAssertThrowsError(try mailbox.original(request.id))
    }

    private func complete(_ request: SplitBridgeRequest, _ mailbox: HanlinSplitMailbox) async throws {
        try prepare(request, mailbox)
        let receiver = SplitDurableReceiver(persistence: mailbox, source: mailbox)
        _ = try await receiver.receive(reference: request.id, context: context(request), now: .now)
        let started = try await receiver.start(reference: request.id, context: context(request), now: .now)
        let attempt = try XCTUnwrap(started.attempt)
        _ = try await receiver.complete(reference: request.id, attempt: attempt, outcome: .result(.string("original-result")), context: context(request))
    }

    private func prepare(_ request: SplitBridgeRequest, _ mailbox: HanlinSplitMailbox) throws {
        try mailbox.prepareDispatch(request, now: .now, currentGeneration: 7,
                                    authorized: true, routeAvailable: true, handlerAvailable: true)
    }

    private func request() throws -> SplitBridgeRequest {
        .init(caller: try .init(validating: "hanlin.host"), target: try .init(validating: "fixture.target"),
            installedPackage: try .init(validating: "fixture.package"), session: try .init(validating: "fixture.session"),
            chat: UUID(), generation: 7, action: try .init(validating: "share.value"),
            capability: try .init(validating: "inter-app.share"), issuedAt: .now, expiresAt: .now.addingTimeInterval(240), payload: .null)
    }

    private func context(_ request: SplitBridgeRequest, chat: UUID? = nil) -> SplitReceiverContext {
        .init(caller: request.caller, target: request.target, package: request.installedPackage,
            session: request.session, chat: chat ?? request.chat, generation: request.generation,
            authorized: true, routeAvailable: true, online: true)
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "split-mailbox-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root.resolvingSymlinksInPath().standardizedFileURL
    }
}

/// Protocol failure injection only; this is not a production conversation store.
@MainActor
private final class OriginFixture: HanlinSplitOriginalOrigin {
    enum SaveError: Error { case failed, wrongOrigin }
    let request: SplitBridgeRequest
    let context: SplitReceiverContext
    var failSave = false
    var afterSave: (() throws -> Void)?
    var saved: [UUID: SplitBridgeReturn] = [:]
    var navigation: [UUID] = []

    init(request: SplitBridgeRequest, context: SplitReceiverContext) {
        self.request = request; self.context = context
    }
    func currentContext(for request: SplitBridgeRequest) async throws -> SplitReceiverContext {
        guard request == self.request else { throw SaveError.wrongOrigin }
        return context
    }
    func persistVerifiedResult(_ response: SplitBridgeReturn) async throws {
        guard response.request == request, saved[request.id] == nil || saved[request.id] == response else { throw SaveError.wrongOrigin }
        if failSave { throw SaveError.failed }
        saved[request.id] = response
        try afterSave?()
    }
    func navigateToOriginalConversation(_ request: SplitBridgeRequest) {
        navigation.append(request.chat)
    }
}
