import Foundation
import HanlinPlatformContracts
@testable import HanlinScriptExtensions
import Testing

@Suite("Durable invocation delivery")
struct HanlinInvocationQueueTests {
    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "hanlin-invocations-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func command(id: UUID = UUID(), app: String = "demo.one", at now: Date = .now,
                         idempotent: Bool = false, maximumAttempts: Int = 1,
                         payload: HanlinValue = .string("שלום🙂")) throws -> HanlinScriptResumeCommand {
        .init(id: id, createdAt: now, invocation: .init(identity: .init(
            installedPackageID: try .init(validating: "installed.\(app)"), packageID: try .init(validating: app),
            generation: 7, entrypointID: "intents.main"), entityID: "action.run", parameters: payload,
            delivery: .init(appID: try .init(validating: app), source: .shortcuts,
                            expiresAt: now.addingTimeInterval(600), idempotent: idempotent, maximumAttempts: maximumAttempts)))
    }

    @Test func legacyEnvelopeAndBinaryValuesRoundTripThroughTheSameQueue() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root)
        let modern = try command(payload: .data(Data([0, 255, 128, 10])))
        let legacy = HanlinScriptResumeCommand(id: modern.id, createdAt: modern.createdAt,
            invocation: .init(identity: modern.invocation.identity, entityID: "action.run", parameters: modern.invocation.parameters))
        // The historical three-field command has neither receipt nor delivery.
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        let directory = root.appending(path: "ResumeQueue", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "\(legacy.id.uuidString.lowercased()).json")
        try encoder.encode(legacy).write(to: file)
        let claim = try #require(try store.claim(legacy.id))
        #expect(claim.command.invocation.parameters == legacy.invocation.parameters)
        try store.complete(claim, status: .succeeded, value: legacy.invocation.parameters)
        #expect(try HanlinScriptExtensionStore(root: root).receipt(for: legacy.id)?.value == legacy.invocation.parameters)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let completed = directory.appending(path: "Receipts/\(legacy.id.uuidString.lowercased()).json")
        let historicalRead = try decoder.decode(HanlinScriptResumeCommand.self, from: Data(contentsOf: completed))
        #expect(historicalRead.id == legacy.id && historicalRead.invocation.delivery == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try store.pendingCommands().isEmpty)
    }

    @Test func duplicateDeliveryNeverOverwritesACompletedReceiptOrPayload() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root), now = Date(timeIntervalSince1970: 1_000)
        let input = try command(at: now)
        try store.enqueue(input)
        let claim = try #require(try store.claim(input.id, now: now))
        try store.complete(claim, status: .succeeded, value: .integer(42), now: now)
        try store.enqueue(input)
        #expect(try store.receipt(for: input.id)?.value == .integer(42))
        #expect(throws: HanlinInvocationQueueError.duplicateIdentity) {
            try store.enqueue(command(id: input.id, at: now, payload: .string("replacement")))
        }
        #expect(try store.claim(input.id, now: now) == nil)
    }

    @Test func concurrentClaimsAcrossStoreInstancesHaveOnlyOneOwner() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let input = try command(); try HanlinScriptExtensionStore(root: root).enqueue(input)
        let count = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<32 { group.addTask { try HanlinScriptExtensionStore(root: root).claim(input.id) == nil ? 0 : 1 } }
            var count = 0
            for try await result in group { count += result }
            return count
        }
        #expect(count == 1)
        #expect(try HanlinScriptExtensionStore(root: root).receipt(for: input.id)?.attempt == 1)
    }

    @Test func interruptedNonIdempotentWorkIsDeferredWithoutReplay() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_000), store = HanlinScriptExtensionStore(root: root)
        let input = try command(at: now, idempotent: true, maximumAttempts: 2)
        try store.enqueue(input)
        _ = try #require(try store.claim(input.id, now: now, leaseSeconds: 1))
        // Even a forged incoming idempotency flag cannot authorize recovery.
        #expect(try store.claim(input.id, now: now.addingTimeInterval(2)) == nil)
        let receipt = try #require(try store.receipt(for: input.id))
        #expect(receipt.status == .deferred && receipt.failure == .interruptedOutcomeUnknown && receipt.attempt == 1)
    }

    @Test func registeredIdempotentRecoveryFencesOutTheOriginalOwner() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_000), store = HanlinScriptExtensionStore(root: root)
        let input = try command(at: now, idempotent: true, maximumAttempts: 2)
        try store.enqueue(input)
        let old = try #require(try store.claim(input.id, now: now, leaseSeconds: 1))
        let fresh = try #require(try store.claim(input.id, now: now.addingTimeInterval(2), registeredActionIsIdempotent: true))
        #expect(old.leaseID != fresh.leaseID)
        #expect(throws: HanlinInvocationQueueError.staleLease) {
            try store.complete(old, status: .succeeded, value: .string("stale"), now: now.addingTimeInterval(2))
        }
        try store.complete(fresh, status: .succeeded, value: .string("current"), now: now.addingTimeInterval(3))
        #expect(try store.receipt(for: input.id)?.value == .string("current"))
    }

    @Test func expiredQueuedAndCancelledQueuedCommandsNeverStart() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_000), store = HanlinScriptExtensionStore(root: root)
        let expired = try command(at: now), cancelled = try command(at: now)
        try store.enqueue(expired); try store.enqueue(cancelled)
        _ = try store.requestCancellation(cancelled.id, now: now)
        #expect(try store.claim(expired.id, now: now.addingTimeInterval(601)) == nil)
        #expect(try store.claim(cancelled.id, now: now) == nil)
        #expect(try store.receipt(for: expired.id)?.status == .expired)
        #expect(try store.receipt(for: cancelled.id)?.status == .cancelled)
    }

    @Test func runningCancellationIsARequestUntilTheActualExecutorReturns() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root), input = try command()
        try store.enqueue(input)
        let claim = try #require(try store.claim(input.id))
        let requested = try store.requestCancellation(input.id)
        #expect(requested.status == .running && requested.cancellationRequested)
        try store.complete(claim, status: .succeeded, value: .string("completed before cancellation"))
        let receipt = try #require(try store.receipt(for: input.id))
        #expect(receipt.status == .succeeded && receipt.cancellationRequested)
    }

    @Test func malformedAndPoisonedRecordsFailWithoutReadingOutsideTheStore() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root), input = try command()
        try store.enqueue(input)
        let file = root.appending(path: "ResumeQueue/\(input.id.uuidString.lowercased()).json")
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json["deliverySchemaVersion"] = 999
        try JSONSerialization.data(withJSONObject: json).write(to: file, options: .atomic)
        #expect(throws: HanlinInvocationQueueError.invalidEnvelope) { try store.receipt(for: input.id) }
        try FileManager.default.removeItem(at: file)
        let outside = root.deletingLastPathComponent().appending(path: "outside-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: outside) }
        let privateBytes = Data("PRIVATE_OUTSIDE".utf8); try privateBytes.write(to: outside)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
        #expect(throws: HanlinScriptExtensionStoreError.invalidArtifactReference) { try store.receipt(for: input.id) }
        #expect(try Data(contentsOf: outside) == privateBytes)
    }

    @Test func twoPackagesReceiveTheirOwnDurableResultsAndFailures() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root), executor = HanlinInvocationExecutor(store: store)
        let first = try command(app: "demo.one"), second = try command(app: "demo.two")
        try store.enqueue(first); try store.enqueue(second)
        async let one = executor.execute(first.id) { .string($0.invocation.identity.packageID.rawValue) }
        async let two = executor.execute(second.id) { _ in throw HanlinInvocationDispatchError(.stale, .staleGeneration) }
        let results = try await (one, two)
        #expect(results.0?.value == .string("demo.one") && results.0?.status == .succeeded)
        #expect(results.1?.value == nil && results.1?.status == .stale && results.1?.failure == .staleGeneration)
    }

    @Test func actualAsyncHandlerIsCancelledBeforeItsTerminalReceipt() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root), executor = HanlinInvocationExecutor(store: store)
        let input = try command(); try store.enqueue(input)
        let started = InvocationStartSignal()
        let execution = Task {
            try await executor.execute(input.id) { _ in
                await started.signal()
                try await Task.sleep(for: .seconds(30))
                return .string("MUST_NOT_COMPLETE")
            }
        }
        await started.wait()
        _ = try store.requestCancellation(input.id)
        let result = try await execution.value
        #expect(result?.status == .cancelled && result?.value == nil && result?.cancellationRequested == true)
    }
}

private actor InvocationStartSignal {
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    func signal() { started = true; continuation?.resume(); continuation = nil }
    func wait() async {
        if started { return }
        await withCheckedContinuation { continuation = $0 }
    }
}
