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
