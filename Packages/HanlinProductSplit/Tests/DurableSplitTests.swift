import Foundation
import HanlinPlatformContracts

private struct DurableTestFailure: Error { let message: String }
private func check(_ value: @autoclosure () throws -> Bool) throws {
    if try value() == false { throw DurableTestFailure(message: "assertion failed") }
}
private func expecting<E: Error & Equatable>(_ expected: E, _ action: () async throws -> Void) async throws {
    do { try await action() }
    catch let error as E { try check(error == expected); return }
    throw DurableTestFailure(message: "expected \(expected)")
}
private func expectingSync<E: Error & Equatable>(_ expected: E, _ action: () throws -> Void) throws {
    do { try action() }
    catch let error as E { try check(error == expected); return }
    throw DurableTestFailure(message: "expected \(expected)")
}

/// Synthetic source only. This type is not a production transport or an integrity verifier.
private struct FixtureVerifiedSource: SplitTrustedRequestSource {
    let request: SplitBridgeRequest
    var unavailable = false
    func verifiedRequest(reference: UUID) async throws -> SplitBridgeRequest {
        if unavailable { throw SplitBridgeFailure.transportUnavailable }
        return request
    }
}

/// Inject loss of the acknowledgement after the actual disk transaction commits.
private struct LostAcknowledgementStore: SplitReceiverPersistence {
    let base: SplitFixtureStore
    func transaction(_ operation: @Sendable (inout SplitReceiverDatabase) throws -> SplitReceiverRecord) throws -> SplitReceiverRecord {
        _ = try base.transaction(operation)
        throw SplitDurabilityError.interrupted
    }
}

private func context(_ request: SplitBridgeRequest, generation: UInt64? = nil,
                     chat: UUID? = nil, authorized: Bool = true, online: Bool = true) -> SplitReceiverContext {
    SplitReceiverContext(caller: request.caller, target: request.target, package: request.installedPackage,
                         session: request.session, chat: chat ?? request.chat,
                         generation: generation ?? request.generation, authorized: authorized,
                         routeAvailable: true, online: online)
}

@main
private enum DurableSplitTests {
    static func main() async {
        do {
            if CommandLine.arguments.count == 5, CommandLine.arguments[1] == "--claim" {
                try await childClaim(); return
            }
            try await run()
        } catch {
            output(["status": "FAILED", "error": String(describing: error)])
        }
    }

    static func output(_ value: [String: Any]) {
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print(data.flatMap { String(data: $0, encoding: .utf8) } ?? "{\"status\":\"FAILED\"}")
    }

    static func childClaim() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let request = try JSONDecoder().decode(SplitBridgeRequest.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])))
        guard let time = TimeInterval(CommandLine.arguments[4]) else { throw DurableTestFailure(message: "bad child clock") }
        let receiver = SplitDurableReceiver(persistence: try SplitFixtureStore(root: root), source: FixtureVerifiedSource(request: request))
        do {
            let started = try await receiver.start(reference: request.id, context: context(request), now: Date(timeIntervalSince1970: time))
            output(["status": "CLAIMED", "attempt": started.attempt?.uuidString ?? ""])
        } catch SplitDurabilityError.busy { output(["status": "BUSY"]) }
        catch SplitBridgeFailure.outOfOrder { output(["status": "OUT_OF_ORDER"]) }
    }

    static func run() async throws {
        guard CommandLine.arguments.count == 2 else { throw DurableTestFailure(message: "owned fixture root required") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var passed: [String] = []
        func test(_ name: String, _ action: () async throws -> Void) async throws {
            do { try await action(); passed.append(name) }
            catch { throw DurableTestFailure(message: "\(name): \(error)") }
        }
        func store() throws -> (URL, SplitFixtureStore) {
            let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            try Data(SplitFixtureStore.marker.utf8).write(to: directory.appendingPathComponent(".hanlin-product-split-fixture"))
            return (directory, try SplitFixtureStore(root: directory))
        }
        func request(id: UUID = UUID(), chat: UUID = UUID()) throws -> SplitBridgeRequest {
            SplitBridgeRequest(id: id, caller: try .init(validating: "hanlin.ai"), target: try .init(validating: "fixture.app"),
                installedPackage: try .init(validating: "fixture.package"), session: try .init(validating: "fixture.session"),
                chat: chat, generation: 8, action: try .init(validating: "app.open"),
                capability: try .init(validating: "app.present"), issuedAt: now,
                expiresAt: now.addingTimeInterval(60), payload: .string("synthetic payload"))
        }
        func receiver(_ persistence: SplitFixtureStore, _ request: SplitBridgeRequest) -> SplitDurableReceiver {
            SplitDurableReceiver(persistence: persistence, source: FixtureVerifiedSource(request: request))
        }

        try await test("receiver.unconfiguredAndUnavailableTransportNeverReserve") {
            let (path, persistence) = try store(); let r = try request()
            let empty = SplitDurableReceiver(persistence: persistence)
            try await expecting(SplitBridgeFailure.transportUnavailable) { _ = try await empty.receive(reference: r.id, context: context(r), now: now) }
            let unavailable = SplitDurableReceiver(persistence: persistence, source: FixtureVerifiedSource(request: r, unavailable: true))
            try await expecting(SplitBridgeFailure.transportUnavailable) { _ = try await unavailable.receive(reference: r.id, context: context(r), now: now) }
            try check(!FileManager.default.fileExists(atPath: path.appendingPathComponent("receiver.json").path))
        }
        try await test("receiver.rejectReferenceOriginAndCurrentGenerationMismatch") {
            let (_, persistence) = try store(); let r = try request(); let service = receiver(persistence, r)
            try await expecting(SplitBridgeFailure.correlationMismatch) { _ = try await service.receive(reference: UUID(), context: context(r), now: now) }
            try await expecting(SplitBridgeFailure.correlationMismatch) { _ = try await service.receive(reference: r.id, context: context(r, chat: UUID()), now: now) }
            try await expecting(SplitBridgeFailure.staleGeneration) { _ = try await service.receive(reference: r.id, context: context(r, generation: 9), now: now) }
        }
        try await test("receiver.reservationSurvivesStoreAndReceiverRestart") {
            let (path, persistence) = try store(); let r = try request()
            let initial = try await receiver(persistence, r).receive(reference: r.id, context: context(r), now: now)
            let restarted = receiver(try SplitFixtureStore(root: path), r)
            let repeated = try await restarted.receive(reference: r.id, context: context(r), now: now)
            try check(initial == repeated && repeated.phase == .reserved)
            let start = try await restarted.start(reference: r.id, context: context(r), now: now)
            try check(start.phase == .executing && start.attempt != nil && start.request.chat == r.chat)
        }
        try await test("receiver.lostReservationAcknowledgementReloadsSameReservation") {
            let (path, persistence) = try store(); let r = try request()
            let lost = SplitDurableReceiver(persistence: LostAcknowledgementStore(base: persistence), source: FixtureVerifiedSource(request: r))
            try await expecting(SplitDurabilityError.interrupted) { _ = try await lost.receive(reference: r.id, context: context(r), now: now) }
            let restarted = receiver(try SplitFixtureStore(root: path), r)
            let reservation = try await restarted.receive(reference: r.id, context: context(r), now: now)
            try check(reservation.phase == .reserved && reservation.attempt == nil)
            let started = try await restarted.start(reference: r.id, context: context(r), now: now)
            try check(started.attempt != nil)
        }
        try await test("receiver.lostStartAcknowledgementNeverGrantsAnotherAttempt") {
            let (path, persistence) = try store(); let r = try request()
            _ = try await receiver(persistence, r).receive(reference: r.id, context: context(r), now: now)
            let lost = SplitDurableReceiver(persistence: LostAcknowledgementStore(base: persistence), source: FixtureVerifiedSource(request: r))
            try await expecting(SplitDurabilityError.interrupted) { _ = try await lost.start(reference: r.id, context: context(r), now: now) }
            let restarted = receiver(try SplitFixtureStore(root: path), r)
            let unknown = try await restarted.interrupt(reference: r.id, reason: .timedOut, context: context(r))
            try check(unknown.phase == .outcomeUnknown && unknown.attempt != nil)
            try await expecting(SplitDurabilityError.outcomeUnknown) { _ = try await restarted.start(reference: r.id, context: context(r), now: now) }
        }
        try await test("receiver.lostResultAcknowledgementReplaysPersistedOutcome") {
            let (path, persistence) = try store(); let r = try request(); let service = receiver(persistence, r)
            _ = try await service.receive(reference: r.id, context: context(r), now: now)
            let started = try await service.start(reference: r.id, context: context(r), now: now)
            guard let attempt = started.attempt else { throw DurableTestFailure(message: "missing attempt") }
            let lost = SplitDurableReceiver(persistence: LostAcknowledgementStore(base: persistence), source: FixtureVerifiedSource(request: r))
            try await expecting(SplitDurabilityError.interrupted) { _ = try await lost.complete(reference: r.id, attempt: attempt, outcome: .result(.string("durable")), context: context(r)) }
            let result = try await receiver(try SplitFixtureStore(root: path), r).receive(reference: r.id, context: context(r), now: now)
            try check(result.phase == .completed && result.outcome == .result(.string("durable")) && result.attempt == attempt)
        }
        try await test("receiver.sameIDChangedTrustedRecordRejectedWithoutOverwrite") {
            let (_, persistence) = try store(); let r = try request()
            let before = try await receiver(persistence, r).receive(reference: r.id, context: context(r), now: now)
            let conflicting = try request(id: r.id)
            try await expecting(SplitBridgeFailure.correlationMismatch) { _ = try await receiver(persistence, conflicting).receive(reference: r.id, context: context(conflicting), now: now) }
            let after = try await receiver(persistence, r).receive(reference: r.id, context: context(r), now: now)
            try check(before == after)
        }
        try await test("receiver.concurrentInstancesGrantOneAttempt") {
            let (path, persistence) = try store(); let r = try request()
            _ = try await receiver(persistence, r).receive(reference: r.id, context: context(r), now: now)
            let starts = try await withThrowingTaskGroup(of: Bool.self) { group in
                for _ in 0..<16 {
                    group.addTask {
                        let service = SplitDurableReceiver(persistence: try SplitFixtureStore(root: path), source: FixtureVerifiedSource(request: r))
                        do { _ = try await service.start(reference: r.id, context: context(r), now: now); return true }
                        catch SplitDurabilityError.busy { return false }
                        catch SplitBridgeFailure.outOfOrder { return false }
                    }
                }
                var granted = 0
                for try await won in group { if won { granted += 1 } }
                return granted
            }
            try check(starts == 1)
        }
        for performedEffect in [false, true] {
            try await test("receiver.crashExecuting.effectPerformed=\(performedEffect).unknownWithoutReplay") {
                let (path, persistence) = try store(); let r = try request(); let service = receiver(persistence, r)
                _ = try await service.receive(reference: r.id, context: context(r), now: now)
                let running = try await service.start(reference: r.id, context: context(r), now: now)
                if performedEffect { try persistence.write(1, to: .effect) }
                let restarted = receiver(try SplitFixtureStore(root: path), r)
                let unknown = try await restarted.interrupt(reference: r.id, reason: .timedOut, context: context(r))
                try check(unknown.phase == .outcomeUnknown && unknown.attempt == running.attempt && unknown.outcome == nil)
                try await expecting(SplitDurabilityError.outcomeUnknown) { _ = try await restarted.start(reference: r.id, context: context(r), now: now) }
                let repeatDelivery = try await restarted.receive(reference: r.id, context: context(r), now: now)
                try check(repeatDelivery.phase == .outcomeUnknown && repeatDelivery.request == r)
                if performedEffect { try check(try persistence.read(Int.self, from: .effect) == 1) }
            }
        }
        try await test("receiver.persistedResultReplayedAfterRestartNoSecondExecution") {
            let (path, persistence) = try store(); let r = try request(); let service = receiver(persistence, r)
            _ = try await service.receive(reference: r.id, context: context(r), now: now)
            let running = try await service.start(reference: r.id, context: context(r), now: now)
            guard let attempt = running.attempt else { throw DurableTestFailure(message: "missing attempt") }
            let complete = try await service.complete(reference: r.id, attempt: attempt, outcome: .result(.string("known result")), context: context(r))
            let restarted = receiver(try SplitFixtureStore(root: path), r)
            let replay = try await restarted.receive(reference: r.id, context: context(r), now: now.addingTimeInterval(61))
            try check(replay == complete && replay.request.chat == r.chat && replay.request.session == r.session)
            try await expecting(SplitBridgeFailure.outOfOrder) { _ = try await restarted.start(reference: r.id, context: context(r), now: now) }
            let repeatedCompletion = try await restarted.complete(reference: r.id, attempt: attempt, outcome: .result(.string("known result")), context: context(r))
            try check(repeatedCompletion == complete)
        }
        try await test("receiver.reconcileUnknownRequiresSameAttemptAndCurrentAuthority") {
            let (_, persistence) = try store(); let r = try request(); let service = receiver(persistence, r)
            _ = try await service.receive(reference: r.id, context: context(r), now: now)
            let running = try await service.start(reference: r.id, context: context(r), now: now)
            guard let attempt = running.attempt else { throw DurableTestFailure(message: "missing attempt") }
            _ = try await service.interrupt(reference: r.id, reason: .cancelled, context: context(r))
            try await expecting(SplitBridgeFailure.outOfOrder) { _ = try await service.complete(reference: r.id, attempt: attempt, outcome: .result(.null), context: context(r)) }
            try await expecting(SplitDurabilityError.attemptMismatch) { _ = try await service.reconcile(reference: r.id, attempt: UUID(), outcome: .result(.null), context: context(r)) }
            try await expecting(SplitBridgeFailure.denied) { _ = try await service.reconcile(reference: r.id, attempt: attempt, outcome: .result(.null), context: context(r, authorized: false)) }
            let result = try await service.reconcile(reference: r.id, attempt: attempt, outcome: .result(.string("externally reconciled fixture result")), context: context(r))
            try check(result.phase == .completed && result.request == r)
            try await expecting(SplitDurabilityError.recoveryConflict) { _ = try await service.reconcile(reference: r.id, attempt: attempt, outcome: .result(.string("different")), context: context(r)) }
        }
        for reason in [SplitBridgeFailure.denied, .offline, .timedOut, .cancelled] {
            try await test("receiver.preExecution.\(reason).retainsOriginAndIsTerminal") {
                let (_, persistence) = try store(); let r = try request(); let service = receiver(persistence, r)
                var record = try await service.receive(reference: r.id,
                    context: context(r, authorized: reason != .denied, online: reason != .offline),
                    now: reason == .timedOut ? now.addingTimeInterval(61) : now)
                if reason == .cancelled { record = try await service.interrupt(reference: r.id, reason: reason, context: context(r)) }
                try check(record.phase == .completed && record.attempt == nil && record.outcome == .failure(reason) && record.request == r)
                try await expecting(SplitBridgeFailure.outOfOrder) { _ = try await service.start(reference: r.id, context: context(r), now: now) }
            }
        }
        try await test("receiver.outOfOrderCompletionRejected") {
            let (_, persistence) = try store(); let r = try request(); let service = receiver(persistence, r)
            _ = try await service.receive(reference: r.id, context: context(r), now: now)
            try await expecting(SplitDurabilityError.attemptMismatch) { _ = try await service.complete(reference: r.id, attempt: UUID(), outcome: .result(.null), context: context(r)) }
        }
        try await test("receiver.corruptPersistencePreservedAndNeverReset") {
            let (path, persistence) = try store(); let r = try request()
            let bytes = Data("{broken state".utf8)
            try bytes.write(to: path.appendingPathComponent("receiver.json"))
            do { _ = try await receiver(persistence, r).receive(reference: r.id, context: context(r), now: now) }
            catch { try check(try Data(contentsOf: path.appendingPathComponent("receiver.json")) == bytes); return }
            throw DurableTestFailure(message: "corrupt state reset")
        }
        try await test("fixture.exclusiveLockBusyDoesNotStealOrOverwrite") {
            let (_, persistence) = try store()
            try persistence.locked {
                try expectingSync(SplitDurabilityError.busy) { _ = try persistence.locked { 1 } }
            }
            try check(try persistence.locked { 2 } == 2)
        }

        let source = try SplitStoreSnapshot(storeID: "source.fixture", revision: 2,
            files: ["package/ids": Data([0, 255, 10]), "grants/original": Data("preserve".utf8)])
        let destination = try SplitStoreSnapshot(storeID: "target.fixture", revision: 0, files: ["existing/user": Data([1, 2])])
        let plan = try SplitMigrationPlan(id: .init(validating: "durable.fixture.v1"), source: source,
            destination: destination, copies: ["package/ids": "package/ids", "grants/original": "grants/original"])

        for interruption in SplitMigrationInterruption.allCases {
            for rollingBack in [false, true] {
                try await test("migration.recover.\(rollingBack ? "rollback" : "apply").\(interruption.rawValue)") {
                    let (path, persistence) = try store(); let migration = SplitDurableFixtureMigration(store: persistence)
                    try migration.initialize(plan: plan)
                    if rollingBack { _ = try migration.apply() }
                    let originalBytes = try Data(contentsOf: path.appendingPathComponent("source.json"))
                    try expectingSync(SplitDurabilityError.interrupted) {
                        if rollingBack { _ = try migration.rollback(interruptAt: interruption) }
                        else { _ = try migration.apply(interruptAt: interruption) }
                    }
                    let restarted = SplitDurableFixtureMigration(store: try SplitFixtureStore(root: path))
                    let output = try restarted.recover(policy: .finishIntent)
                    let expected = rollingBack ? destination : try plan.dryRun(source: source, destination: destination)
                    try check(output == expected)
                    try check(try restarted.recover(policy: .finishIntent) == expected)
                    try check(try Data(contentsOf: path.appendingPathComponent("source.json")) == originalBytes)
                }
            }
        }
        try await test("migration.restoreBeforeIntentRemainsStableAcrossRestart") {
            let (path, persistence) = try store(); let migration = SplitDurableFixtureMigration(store: persistence)
            try migration.initialize(plan: plan)
            try expectingSync(SplitDurabilityError.interrupted) { _ = try migration.apply(interruptAt: .afterDestination) }
            try check(try migration.recover(policy: .restoreBeforeIntent) == destination)
            let restarted = SplitDurableFixtureMigration(store: try SplitFixtureStore(root: path))
            try check(try restarted.recover(policy: .finishIntent) == destination)
            try check(try restarted.apply() == plan.dryRun(source: source, destination: destination))
        }
        try await test("migration.externalDestinationEditBlocksRecoveryWithoutOverwrite") {
            let (_, persistence) = try store(); let migration = SplitDurableFixtureMigration(store: persistence)
            try migration.initialize(plan: plan)
            try expectingSync(SplitDurabilityError.interrupted) { _ = try migration.apply(interruptAt: .afterIntent) }
            let changed = try SplitStoreSnapshot(storeID: destination.storeID, revision: 9, files: ["user/new": Data([8])])
            try persistence.write(changed, to: .destination)
            try expectingSync(SplitDurabilityError.recoveryConflict) { _ = try migration.recover(policy: .finishIntent) }
            try check(try persistence.read(SplitStoreSnapshot.self, from: .destination) == changed)
            try check(try persistence.read(SplitStoreSnapshot.self, from: .source) == source)
        }
        try await test("migration.changedSourceAndCorruptIntentFailClosed") {
            let (path, persistence) = try store(); let migration = SplitDurableFixtureMigration(store: persistence)
            try migration.initialize(plan: plan)
            try expectingSync(SplitDurabilityError.interrupted) { _ = try migration.apply(interruptAt: .afterIntent) }
            let changed = try SplitStoreSnapshot(storeID: source.storeID, revision: 3, files: source.files)
            try persistence.write(changed, to: .source)
            try expectingSync(SplitDurabilityError.recoveryConflict) { _ = try migration.recover(policy: .finishIntent) }
            try persistence.write(source, to: .source)
            let corrupt = Data("invalid intent".utf8)
            try corrupt.write(to: path.appendingPathComponent("migrationIntent.json"))
            do { _ = try migration.recover(policy: .finishIntent) }
            catch { try check(try Data(contentsOf: path.appendingPathComponent("migrationIntent.json")) == corrupt); return }
            throw DurableTestFailure(message: "corrupt intent accepted")
        }
        try await test("migration.existingFixtureNeverReinitialized") {
            let (_, persistence) = try store(); let migration = SplitDurableFixtureMigration(store: persistence)
            try migration.initialize(plan: plan)
            try expectingSync(SplitDurabilityError.recoveryConflict) { try migration.initialize(plan: plan) }
        }

        // Separate OS processes will race this same durable reservation in Python.
        let (processRoot, processStore) = try store(); let processRequest = try request()
        _ = try await receiver(processStore, processRequest).receive(reference: processRequest.id, context: context(processRequest), now: now)
        try processStore.write(processRequest, to: .delivery)
        output(["status": "EXECUTED_PASS", "count": passed.count, "tests": passed,
                "cross_process_fixture": ["root": processRoot.path,
                    "request": processRoot.appendingPathComponent("delivery.json").path,
                    "time": now.timeIntervalSince1970]])
    }
}
