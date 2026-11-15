import Foundation
import HanlinPlatformContracts

private struct CorrectionFailure: Error { let message: String }
private func requireCorrection(_ value: @autoclosure () throws -> Bool) throws {
    if try value() == false { throw CorrectionFailure(message: "assertion failed") }
}
private func rejectsCorrection<E: Error & Equatable>(_ expected: E, _ operation: () throws -> Void) throws {
    do { try operation() }
    catch let error as E { try requireCorrection(error == expected); return }
    throw CorrectionFailure(message: "expected \(expected)")
}

@main
private enum DurabilityCorrectionTests {
    static let slots: [SplitFixtureStore.Slot] = [.source, .destination, .journal, .receiver, .migrationIntent, .effect, .delivery]
    static func main() {
        do {
            if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--recover-next" {
                try processContinuation(); return
            }
            try run()
        } catch { output(["status": "FAILED", "error": String(describing: error)]) }
    }
    static func output(_ value: [String: Any]) {
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print(data.flatMap { String(data: $0, encoding: .utf8) } ?? "{\"status\":\"FAILED\"}")
    }
    static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    static func plan(sourceID: String = "source.fixture", bytes: Data = Data([0, 255, 10]), empty: Bool = false) throws -> SplitMigrationPlan {
        let source = try SplitStoreSnapshot(storeID: sourceID, revision: 2, files: empty ? [:] : ["package/original": bytes])
        let destination = try SplitStoreSnapshot(storeID: "destination.fixture", revision: 0, files: [:])
        return try SplitMigrationPlan(id: .init(validating: "correction.fixture.v1"), source: source,
            destination: destination, copies: empty ? [:] : ["package/original": "package/original"])
    }
    static func currentBytes(_ store: SplitFixtureStore) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for slot in slots {
            let url = try store.url(slot)
            if FileManager.default.fileExists(atPath: url.path) { result[slot.rawValue] = try Data(contentsOf: url) }
        }
        return result
    }

    static func processContinuation() throws {
        let store = try SplitFixtureStore(root: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true))
        let sourceBytes = try Data(contentsOf: store.url(.source))
        let expectedBefore = try store.read(SplitStoreSnapshot.self, from: .effect)
        let migration = SplitDurableFixtureMigration(store: store)
        try rejectsCorrection(SplitDurabilityError.interrupted) {
            if CommandLine.arguments[3] == "apply" { _ = try migration.apply(interruptAt: .afterIntent) }
            else if CommandLine.arguments[3] == "rollback" { _ = try migration.rollback(interruptAt: .afterIntent) }
            else { throw CorrectionFailure(message: "unknown continuation") }
        }
        let nextIntent = try store.read(SplitMigrationIntent.self, from: .migrationIntent)
        try requireCorrection(nextIntent.before.output == expectedBefore)
        let settled = try SplitDurableFixtureMigration(store: store).recover(policy: .finishIntent)
        try requireCorrection(settled == nextIntent.after.output)
        try requireCorrection(try Data(contentsOf: store.url(.source)) == sourceBytes)
        output(["status": "RECOVERED", "before_revision": nextIntent.before.output.revision,
                "after_revision": settled.revision, "source_bytes_preserved": true])
    }

    static func run() throws {
        guard CommandLine.arguments.count == 2 else { throw CorrectionFailure(message: "owned fixture root required") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        var passed: [String] = []
        var measurements: [String: Int] = [:]
        func test(_ name: String, _ operation: () throws -> Void) throws {
            do { try operation(); passed.append(name) }
            catch { throw CorrectionFailure(message: "\(name): \(error)") }
        }
        func fresh() throws -> (URL, SplitFixtureStore) {
            let path = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
            try Data(SplitFixtureStore.marker.utf8).write(to: path.appendingPathComponent(".hanlin-product-split-fixture"))
            return (path, try SplitFixtureStore(root: path))
        }
        func interrupted(_ store: SplitFixtureStore, rollback: Bool) throws -> SplitMigrationIntent {
            let migration = SplitDurableFixtureMigration(store: store)
            try migration.initialize(plan: plan())
            if rollback { _ = try migration.apply() }
            try rejectsCorrection(SplitDurabilityError.interrupted) {
                if rollback { _ = try migration.rollback(interruptAt: .afterDestination) }
                else { _ = try migration.apply(interruptAt: .afterDestination) }
            }
            return try store.read(SplitMigrationIntent.self, from: .migrationIntent)
        }

        for rollback in [false, true] {
            for restoring in [false, true] {
                for boundary in SplitRecoveryInterruption.allCases {
                    for explicitRecovery in [false, true] {
                        let name = "recovery.\(rollback ? "rollback" : "apply").\(restoring ? "restore" : "finish").\(boundary.rawValue).\(explicitRecovery ? "explicitRestart" : "nextTransition")"
                        try test(name) {
                            let (path, store) = try fresh()
                            let original = try interrupted(store, rollback: rollback)
                            let expected = restoring ? original.before : original.after
                            let sourceBytes = try Data(contentsOf: store.url(.source))
                            let migration = SplitDurableFixtureMigration(store: store)
                            try rejectsCorrection(SplitDurabilityError.interrupted) {
                                _ = try migration.recover(policy: restoring ? .restoreBeforeIntent : .finishIntent, interruptAt: boundary)
                            }
                            let decision = try store.read(SplitMigrationIntent.self, from: .migrationIntent)
                            if boundary == .afterCheckpoint {
                                try requireCorrection(decision.kind == .checkpoint && decision.before == expected && decision.after == expected)
                            } else {
                                try requireCorrection(decision.recoveryTarget == (restoring ? .before : .after))
                            }
                            let reopenedStore = try SplitFixtureStore(root: path)
                            let restarted = SplitDurableFixtureMigration(store: reopenedStore)
                            if explicitRecovery {
                                // Deliberately request the opposite direction: an already
                                // durable choice must win until its checkpoint is settled.
                                let actual = try restarted.recover(policy: restoring ? .finishIntent : .restoreBeforeIntent)
                                try requireCorrection(actual == expected.output)
                            }
                            // Inspect the *before* journal of a subsequent operation.
                            // Checking only its final output would miss a hidden reversal.
                            try rejectsCorrection(SplitDurabilityError.interrupted) {
                                if rollback { _ = try restarted.apply(interruptAt: .afterIntent) }
                                else { _ = try restarted.rollback(interruptAt: .afterIntent) }
                            }
                            let next = try reopenedStore.read(SplitMigrationIntent.self, from: .migrationIntent)
                            try requireCorrection(next.before == expected)
                            let result = try SplitDurableFixtureMigration(store: try SplitFixtureStore(root: path)).recover(policy: .finishIntent)
                            try requireCorrection(result == next.after.output)
                            try requireCorrection(try Data(contentsOf: store.url(.source)) == sourceBytes)
                        }
                    }
                }
            }
        }

        let limit = SplitFixtureStore.maximumSlotBytes
        try requireCorrection(limit == 16_777_216)
        try test("budget.asciiExactLimitAndOneByteOverPreserveEverySlot") {
            let (_, store) = try fresh()
            let exact = String(repeating: "a", count: limit - 2)
            let tooLarge = exact + "a"
            try requireCorrection(try encoded(exact).count == limit)
            try requireCorrection(try encoded(tooLarge).count == limit + 1)
            try store.write(exact, to: .source)
            try requireCorrection(try store.read(String.self, from: .source) == exact)
            for slot in slots {
                if slot != .source { try store.write("previous valid slot", to: slot) }
                let before = try Data(contentsOf: store.url(slot))
                try rejectsCorrection(SplitDurabilityError.encodedSizeExceeded) { try store.write(tooLarge, to: slot) }
                try requireCorrection(try Data(contentsOf: store.url(slot)) == before)
                let readback = try store.read(String.self, from: slot)
                try requireCorrection(readback == (slot == .source ? exact : "previous valid slot"))
            }
            measurements["ascii_exact_encoded"] = try encoded(exact).count
            measurements["ascii_rejected_encoded"] = try encoded(tooLarge).count
        }
        try test("budget.utf8ExactLimitAndOneByteOverUseEncodedBytes") {
            let (_, store) = try fresh()
            let exact = String(repeating: "א", count: (limit - 2) / 2)
            let tooLarge = exact + "x"
            try requireCorrection(exact.count < exact.utf8.count)
            try requireCorrection(try encoded(exact).count == limit)
            try requireCorrection(try encoded(tooLarge).count == limit + 1)
            try store.write(exact, to: .destination)
            let before = try Data(contentsOf: store.url(.destination))
            try rejectsCorrection(SplitDurabilityError.encodedSizeExceeded) { try store.write(tooLarge, to: .destination) }
            try requireCorrection(try Data(contentsOf: store.url(.destination)) == before)
            try requireCorrection(try store.read(String.self, from: .destination) == exact)
            measurements["utf8_character_count"] = exact.count
            measurements["utf8_exact_encoded"] = try encoded(exact).count
            measurements["utf8_rejected_encoded"] = try encoded(tooLarge).count
        }
        func initialJournal(ofSize size: Int) throws -> SplitMigrationJournal {
            let base = try SplitMigrationJournal(plan: plan(sourceID: "s", empty: true))
            let padding = size - (try encoded(base).count)
            let result = try SplitMigrationJournal(plan: plan(sourceID: "s" + String(repeating: "p", count: padding), empty: true))
            try requireCorrection(try encoded(result).count == size)
            return result
        }
        try test("budget.initializeExactJournalLimitAndRejectOneByteOverBeforeAnyWrite") {
            let (_, store) = try fresh()
            let exact = try initialJournal(ofSize: limit)
            try SplitDurableFixtureMigration(store: store).initialize(plan: exact.plan)
            try requireCorrection(try store.read(SplitMigrationJournal.self, from: .journal) == exact)
            try requireCorrection(try store.read(SplitStoreSnapshot.self, from: .source) == exact.plan.source)
            let (_, rejectedStore) = try fresh()
            let over = try initialJournal(ofSize: limit + 1)
            let before = try currentBytes(rejectedStore)
            try rejectsCorrection(SplitDurabilityError.encodedSizeExceeded) { try SplitDurableFixtureMigration(store: rejectedStore).initialize(plan: over.plan) }
            try requireCorrection(try currentBytes(rejectedStore) == before)
            measurements["initial_journal_accepted"] = try encoded(exact).count
            measurements["initial_journal_rejected"] = try encoded(over).count
        }
        try test("budget.transitionRejectsExpandedIntentWithoutReplacingAnyState") {
            let (_, store) = try fresh()
            let largePlan = try plan(bytes: Data(repeating: 7, count: 4_500_000))
            let beforeJournal = try SplitMigrationJournal(plan: largePlan)
            var afterJournal = beforeJournal
            _ = try afterJournal.apply(source: largePlan.source, current: largePlan.destination)
            let oversized = SplitMigrationIntent(kind: .apply, before: beforeJournal, after: afterJournal)
            try requireCorrection(try encoded(beforeJournal).count <= limit)
            try requireCorrection(try encoded(afterJournal).count <= limit)
            try requireCorrection(try encoded(oversized).count > limit)
            let migration = SplitDurableFixtureMigration(store: store)
            try migration.initialize(plan: largePlan)
            let original = try currentBytes(store)
            try rejectsCorrection(SplitDurabilityError.encodedSizeExceeded) { _ = try migration.apply() }
            try requireCorrection(try currentBytes(store) == original)
            try requireCorrection(try store.read(SplitMigrationJournal.self, from: .journal) == beforeJournal)
            try requireCorrection(try store.read(SplitStoreSnapshot.self, from: .destination) == largePlan.destination)
            measurements["expanded_intent_rejected"] = try encoded(oversized).count
        }
        func nearLimitIntent(reserve: Int) throws -> SplitMigrationIntent {
            func make(_ sourceID: String) throws -> SplitMigrationIntent {
                let before = try SplitMigrationJournal(plan: plan(sourceID: sourceID, empty: true))
                var after = before
                _ = try after.apply(source: before.plan.source, current: before.output)
                return SplitMigrationIntent(kind: .apply, before: before, after: after)
            }
            let base = try make("s")
            let padding = (limit - reserve - (try encoded(base).count)) / 2
            let result = try make("s" + String(repeating: "p", count: padding))
            let size = try encoded(result).count
            try requireCorrection(size <= limit - reserve && size >= limit - reserve - 1)
            return result
        }
        func seedLegacy(_ intent: SplitMigrationIntent, store: SplitFixtureStore) throws {
            try SplitDurableFixtureMigration(store: store).initialize(plan: intent.before.plan)
            try store.write(intent, to: .migrationIntent)
            try store.write(intent.after.output, to: .destination)
        }
        try test("budget.recoveryDecisionExpansionRejectedBeforeReplacingOldIntentOrState") {
            let (_, store) = try fresh()
            let intent = try nearLimitIntent(reserve: 0)
            try requireCorrection(try encoded(intent.selecting(.before)).count > limit)
            try seedLegacy(intent, store: store)
            let original = try currentBytes(store)
            try rejectsCorrection(SplitDurabilityError.encodedSizeExceeded) { _ = try SplitDurableFixtureMigration(store: store).recover(policy: .restoreBeforeIntent) }
            try requireCorrection(try currentBytes(store) == original)
            try requireCorrection(try store.read(SplitMigrationIntent.self, from: .migrationIntent) == intent)
            measurements["legacy_intent_fits"] = try encoded(intent).count
            measurements["recovery_decision_rejected"] = try encoded(intent.selecting(.before)).count
        }
        try test("budget.nearLimitRecoveryPreflightWritesReadableConsistentCheckpoint") {
            let small = try nearLimitIntent(reserve: 4096)
            let overhead = try encoded(small.selecting(.before)).count - encoded(small).count
            let intent = try nearLimitIntent(reserve: overhead)
            let selectedBytes = try encoded(intent.selecting(.before)).count
            try requireCorrection(selectedBytes <= limit && selectedBytes >= limit - 1)
            let (_, store) = try fresh()
            try seedLegacy(intent, store: store)
            let migration = SplitDurableFixtureMigration(store: store)
            let result = try migration.recover(policy: .restoreBeforeIntent)
            try requireCorrection(result == intent.before.output)
            let checkpoint = try store.read(SplitMigrationIntent.self, from: .migrationIntent)
            try requireCorrection(checkpoint.kind == .checkpoint && checkpoint.before == intent.before && checkpoint.after == intent.before)
            try requireCorrection(try store.read(SplitMigrationJournal.self, from: .journal) == intent.before)
            try requireCorrection(try migration.recover(policy: .finishIntent) == result)
            measurements["recovery_decision_accepted"] = selectedBytes
            measurements["recovery_checkpoint_readable"] = try encoded(checkpoint).count
        }

        var processFixtures: [[String: String]] = []
        for rollback in [false, true] {
            for boundary in SplitRecoveryInterruption.allCases {
                let (path, store) = try fresh()
                let original = try interrupted(store, rollback: rollback)
                try store.write(original.before.output, to: .effect)
                try rejectsCorrection(SplitDurabilityError.interrupted) {
                    _ = try SplitDurableFixtureMigration(store: store).recover(policy: .restoreBeforeIntent, interruptAt: boundary)
                }
                processFixtures.append(["root": path.path, "next": rollback ? "apply" : "rollback",
                    "name": "recovery.processRestart.\(rollback ? "rollback" : "apply").restore.\(boundary.rawValue).nextTransition"])
            }
        }
        output(["status": "EXECUTED_PASS", "count": passed.count, "tests": passed,
                "encoded_byte_measurements": measurements, "recovery_process_fixtures": processFixtures])
    }
}
