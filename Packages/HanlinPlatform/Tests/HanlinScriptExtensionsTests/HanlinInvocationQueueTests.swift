import Foundation
import HanlinPlatformContracts
@testable import HanlinScriptExtensions
import Testing

@Suite("Durable invocation delivery")
struct HanlinInvocationQueueTests {
    @Test func busyAdmissionCanQueueAgainOnlyBeforeActionExecutionAndWithoutConsumingAnAttempt() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root), input = try command()
        try store.enqueue(input)
        let executor = HanlinInvocationExecutor(store: store)
        let waiting = try await executor.execute(input.id) { _ in throw HanlinInvocationNotStarted() }
        #expect(waiting?.status == .queued && waiting?.attempt == 0 && waiting?.value == nil && waiting?.leaseID == nil)
        #expect(try store.pendingCommands().map(\.id) == [input.id])
        #expect(try store.command(for: input.id)?.invocation.parameters == input.invocation.parameters)
        let actual = try await executor.execute(input.id) { _ in .string("ACTUALLY_EXECUTED_ONCE") }
        #expect(actual?.status == .succeeded && actual?.attempt == 1 && actual?.value == .string("ACTUALLY_EXECUTED_ONCE"))
        let duplicate = try await executor.execute(input.id) { _ in Issue.record("Completed action replayed"); return .null }
        #expect(duplicate == actual)
    }

    @Test func unstartedReleaseRetainsCancellationExpiryAndFencesOldLeases() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root), at = Date()
        let cancelled = try command(at: at), expired = try command(at: at), replaced = try command(at: at, idempotent: true, maximumAttempts: 2)
        for input in [cancelled, expired, replaced] { try store.enqueue(input) }
        let cancelClaim = try #require(try store.claim(cancelled.id, now: at))
        _ = try store.requestCancellation(cancelled.id, now: at.addingTimeInterval(1))
        try store.releaseUnstarted(cancelClaim, now: at.addingTimeInterval(2))
        #expect(try store.receipt(for: cancelled.id)?.status == .cancelled)
        let expiryClaim = try #require(try store.claim(expired.id, now: at))
        try store.releaseUnstarted(expiryClaim, now: at.addingTimeInterval(601))
        #expect(try store.receipt(for: expired.id)?.status == .expired)
        let old = try #require(try store.claim(replaced.id, now: at, leaseSeconds: 1, registeredActionIsIdempotent: true))
        let newer = try #require(try store.claim(replaced.id, now: at.addingTimeInterval(2), registeredActionIsIdempotent: true))
        #expect(throws: HanlinInvocationQueueError.staleLease) { try store.releaseUnstarted(old, now: at.addingTimeInterval(2)) }
        #expect(try store.receipt(for: replaced.id)?.leaseID == newer.leaseID)
    }

    @Test func damagedItemsDoNotBlockHealthyDeliveryOrEraseTheirOriginalBytes() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root), first = try command()
        try store.enqueue(first)
        let directory = store.root.appending(path: "ResumeQueue", directoryHint: .isDirectory)
        let brokenID = UUID(), linkedID = UUID()
        let broken = directory.appending(path: "\(brokenID.uuidString.lowercased()).json")
        let unknown = directory.appending(path: "PRIVATE_UNTRUSTED_FILENAME.json")
        let brokenBytes = Data("{\"PRIVATE_UNTRUSTED_PAYLOAD\":".utf8)
        try brokenBytes.write(to: broken); try brokenBytes.write(to: unknown)
        let outside = root.deletingLastPathComponent().appending(path: "outside-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: outside) }
        let outsideBytes = Data("PRIVATE_OUTSIDE".utf8); try outsideBytes.write(to: outside)
        try FileManager.default.createSymbolicLink(at: directory.appending(path: "\(linkedID.uuidString.lowercased()).json"), withDestinationURL: outside)
        let second = try command()
        try store.enqueue(second)
        let scan = try store.scanPendingCommands(limit: 128)
        #expect(Set(scan.commands.map(\.id)) == [first.id, second.id])
        #expect(scan.rejections.count == 3 && scan.rejections.allSatisfy { $0.failure == .invalidEnvelope })
        #expect(Set(scan.rejections.compactMap(\.invocationID)) == [brokenID, linkedID])
        #expect(scan.rejections.filter { $0.invocationID == nil }.count == 1)
        #expect(throws: (any Error).self) { _ = try store.pendingCommands() }
        let executor = HanlinInvocationExecutor(store: store)
        let receipt = try await executor.execute(first.id) { _ in .string("ACTUAL_HEALTHY_VALUE") }
        #expect(receipt?.status == .succeeded && receipt?.value == .string("ACTUAL_HEALTHY_VALUE"))
        let reopened = try HanlinScriptExtensionStore(root: root).scanPendingCommands(limit: 128)
        #expect(reopened.commands.map(\.id) == [second.id] && reopened.rejections.count == 3)
        let retainedBroken = try Data(contentsOf: broken), retainedUnknown = try Data(contentsOf: unknown)
        #expect(retainedBroken == brokenBytes && retainedUnknown == brokenBytes)
        #expect(try Data(contentsOf: outside) == outsideBytes)
    }

    @Test func unreadableRecordsCannotBlockAdmissionAndRetainTheirOriginalBytes() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root), healthy = try command()
        try store.enqueue(healthy)
        for _ in 0..<127 {
            let file = store.root.appending(path: "ResumeQueue/\(UUID().uuidString.lowercased()).json")
            try Data("malformed".utf8).write(to: file)
        }
        let next = try command()
        try store.enqueue(next)
        #expect(try store.command(for: next.id)?.invocation.parameters == next.invocation.parameters)
        let executor = HanlinInvocationExecutor(store: store)
        let receipt = try await executor.execute(healthy.id) { _ in .integer(42) }
        #expect(receipt?.status == .succeeded)
        try store.enqueue(next)
        let scan = try store.scanPendingCommands(limit: 128)
        #expect(scan.commands.map(\.id) == [next.id] && scan.rejections.count == 127)
        for rejection in scan.rejections {
            let id = try #require(rejection.invocationID)
            let file = store.root.appending(path: "ResumeQueue/\(id.uuidString.lowercased()).json")
            #expect(try Data(contentsOf: file) == Data("malformed".utf8))
        }
    }

    @Test func atomicOwnedAdmissionHasOneLeaseAndPreservesExactRetriesAndConflicts() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let input = try command()
        let claims = try await withThrowingTaskGroup(of: HanlinInvocationClaim?.self) { group in
            for _ in 0..<16 {
                group.addTask { try HanlinScriptExtensionStore(root: root).enqueueAndClaim(input) }
            }
            var claims: [HanlinInvocationClaim] = []
            for try await claim in group { if let claim { claims.append(claim) } }
            return claims
        }
        #expect(claims.count == 1)
        let claim = try #require(claims.first), store = HanlinScriptExtensionStore(root: root)
        #expect(try store.command(for: input.id) == claim.command)
        let running = try #require(try store.receipt(for: input.id))
        #expect(running.status == .running && running.attempt == 1 && running.leaseID == claim.leaseID)
        #expect(try store.enqueueAndClaim(input) == nil)
        #expect(try store.receipt(for: input.id) == running)
        let conflicting = try command(id: input.id, at: input.createdAt, payload: .string("DO_NOT_REPLACE"))
        #expect(throws: HanlinInvocationQueueError.duplicateIdentity) {
            _ = try store.enqueueAndClaim(conflicting)
        }
        #expect(try store.command(for: input.id) == claim.command)
        try store.complete(claim, status: .succeeded, value: .object(["nested": .array([.integer(7), .null])]))
        let completed = try store.receipt(for: input.id)
        #expect(try store.enqueueAndClaim(input) == nil)
        #expect(try store.receipt(for: input.id) == completed)
        #expect(try store.pendingCommands().isEmpty)
    }

    @Test func lostOwnedAdmissionIsDeferredAndCannotReplayAfterAProcessRestart() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_000), input = try command(at: now)
        let claim = try #require(try HanlinScriptExtensionStore(root: root).enqueueAndClaim(input, now: now, leaseSeconds: 1))
        let reopened = HanlinScriptExtensionStore(root: root)
        #expect(try reopened.claim(input.id, now: now.addingTimeInterval(0.5)) == nil)
        #expect(try reopened.claim(input.id, now: now.addingTimeInterval(2)) == nil)
        let receipt = try #require(try reopened.receipt(for: input.id))
        #expect(receipt.status == .deferred && receipt.failure == .interruptedOutcomeUnknown)
        #expect(receipt.attempt == 1 && receipt.value == nil && receipt.leaseID == nil)
        #expect(throws: HanlinInvocationQueueError.staleLease) {
            try reopened.complete(claim, status: .succeeded, value: .string("LATE"),
                                  now: now.addingTimeInterval(2))
        }
        #expect(try reopened.enqueueAndClaim(input, now: now.addingTimeInterval(3)) == nil)
        #expect(try reopened.receipt(for: input.id) == receipt)
        #expect(try reopened.pendingCommands().isEmpty)
    }

    @Test func ownedExecutorKeepsForegroundDrainsOutAndReturnsTheOriginalReceiptOnRetry() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root), input = try command()
        let owner = HanlinInvocationExecutor(store: store), entered = InvocationStartSignal()
        let release = InvocationStartSignal()
        let task = Task {
            try await owner.execute(input) { command in
                let persistedCommand = try store.command(for: input.id)
                #expect(persistedCommand == command)
                await entered.signal()
                await release.wait()
                return .string("ORIGINAL_RESULT")
            }
        }
        await entered.wait()
        let running = try #require(try store.receipt(for: input.id))
        let drain = try await HanlinInvocationExecutor(store: store).execute(input.id) { _ in
            Issue.record("Foreground drain stole an owned command")
            return .string("WRONG")
        }
        #expect(drain?.status == .running && drain?.leaseID == running.leaseID)
        await release.signal()
        let completed = try await task.value
        #expect(completed?.status == .succeeded && completed?.value == .string("ORIGINAL_RESULT"))
        let repeated = try await HanlinInvocationExecutor(store: store).execute(input) { _ in
            Issue.record("A completed owned command executed twice")
            return .null
        }
        #expect(repeated == completed)
    }

    @Test func ownedAdmissionFailureIsTerminalWhileLegacyQueuedAdmissionRemainsRetryable() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root), input = try command()
        let executor = HanlinInvocationExecutor(store: store)
        let denied = try await executor.execute(input) { _ in throw HanlinInvocationNotStarted() }
        #expect(denied?.status == .needsForeground && denied?.failure == .unavailableHost)
        #expect(try store.pendingCommands().isEmpty)
        let retried = try await executor.execute(input.id) { _ in
            Issue.record("An abandoned Shortcuts action replayed")
            return .null
        }
        #expect(retried == denied)
        let legacy = HanlinScriptResumeCommand(invocation: .init(identity: input.invocation.identity,
            entityID: input.invocation.entityID, parameters: .string("legacy"), continueInForeground: true))
        try store.enqueue(legacy)
        let deferred = try await executor.execute(legacy.id) { _ in throw HanlinInvocationNotStarted() }
        #expect(deferred?.status == .queued && deferred?.attempt == 0)
        let result = try await executor.execute(legacy.id) { .string($0.invocation.delivery == nil ? "LEGACY" : "WRONG") }
        #expect(result?.status == .succeeded && result?.value == .string("LEGACY"))
    }

    @Test func ownedCancellationDrainsTheActualHandlerBeforeKeepingItsTerminalReceipt() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root), input = try command()
        let entered = InvocationStartSignal(), drained = InvocationStartSignal()
        let task = Task {
            try await HanlinInvocationExecutor(store: store).execute(input) { _ in
                await entered.signal()
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    await drained.signal()
                    throw error
                }
                return .string("MUST_NOT_COMPLETE")
            }
        }
        await entered.wait()
        let requested = try store.requestCancellation(input.id)
        #expect(requested.status == .running && requested.cancellationRequested)
        let terminal = try await task.value
        await drained.wait()
        #expect(terminal?.status == .cancelled && terminal?.value == nil)
        let retry = try await HanlinInvocationExecutor(store: store).execute(input) { _ in
            Issue.record("Cancelled action replayed")
            return .null
        }
        #expect(retry == terminal)
    }

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
