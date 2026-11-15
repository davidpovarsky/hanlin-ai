import Foundation
import HanlinPlatformContracts
import HanlinMiniAppCore

private struct TestFailure: Error { let message: String }
private func require(_ value: @autoclosure () throws -> Bool, _ message: String = "assertion failed") throws {
    if try value() == false { throw TestFailure(message: message) }
}
private func expect<E: Error & Equatable>(_ expected: E, _ operation: () throws -> Void) throws {
    do { try operation() }
    catch let error as E { try require(error == expected, "wrong error: \(error)"); return }
    throw TestFailure(message: "expected \(expected)")
}

@main
private enum PortableSplitTests {
    static func main() {
        do { try run() }
        catch {
            let data = try? JSONSerialization.data(withJSONObject: ["status": "FAILED", "error": String(describing: error)], options: [.sortedKeys])
            print(data.flatMap { String(data: $0, encoding: .utf8) } ?? "{\"status\":\"FAILED\"}")
        }
    }
    static func run() throws {
        var passed: [String] = []
        func test(_ name: String, _ operation: () throws -> Void) throws {
            do { try operation(); passed.append(name) }
            catch { throw TestFailure(message: "\(name): \(error)") }
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let caller = try HanlinAppID(validating: "hanlin.ai")
        let target = try HanlinAppID(validating: "hanlin.sample")
        let package = try HanlinInstalledPackageID(validating: "package.sample")
        let session = try HanlinAppSessionID(validating: "session.one")
        let action = try HanlinActionID(validating: "app.open")
        let capability = try HanlinCapabilityID(validating: "app.present")
        let request = SplitBridgeRequest(caller: caller, target: target, installedPackage: package,
                                         session: session, chat: UUID(), generation: 7, action: action,
                                         capability: capability, issuedAt: now, expiresAt: now.addingTimeInterval(60),
                                         payload: .object(["text": .string("שלום")]))
        func pending() throws -> SplitBridgeLedger {
            var ledger = SplitBridgeLedger()
            try ledger.begin(request, now: now, routeAvailable: true, authorized: true)
            return ledger
        }
        func dispatched() throws -> SplitBridgeLedger {
            var ledger = try pending()
            try ledger.dispatch(request.id, now: now, currentGeneration: 7, authorized: true,
                                companionInstalled: true, transportReady: true, online: true)
            return ledger
        }
        func mutate(_ field: String, _ value: Any) throws -> SplitBridgeRequest {
            guard var object = try JSONSerialization.jsonObject(with: SplitBridgeCodec.encode(request)) as? [String: Any]
            else { throw TestFailure(message: "request fixture encoding") }
            object[field] = value
            return try SplitBridgeCodec.decode(SplitBridgeRequest.self, from: JSONSerialization.data(withJSONObject: object))
        }
        try test("bridge.codec.roundTripTypedIdentifiersAndUnicode") {
            let decoded = try SplitBridgeCodec.decode(SplitBridgeRequest.self, from: SplitBridgeCodec.encode(request))
            try require(decoded == request)
        }
        try test("bridge.codec.rejectMalformed") {
            try expect(SplitBridgeFailure.malformed) {
                _ = try SplitBridgeCodec.decode(SplitBridgeRequest.self, from: Data("{}".utf8))
            }
        }
        try test("bridge.codec.rejectOversizeBeforeParsing") {
            try expect(SplitBridgeFailure.oversized) {
                _ = try SplitBridgeCodec.decode(SplitBridgeRequest.self, from: Data(repeating: 32, count: 65_537))
            }
        }
        try test("bridge.codec.rejectInvalidCanonicalIdentity") {
            try expect(SplitBridgeFailure.malformed) { _ = try mutate("target", "../escape") }
        }
        try test("bridge.canonicalAdapter.preservesIdentityAndRejectsWrongResponse") {
            let canonical = request.canonicalRequest()
            try require(canonical.id == request.id && canonical.caller == caller && canonical.target == target)
            try require(canonical.action == action && canonical.capability == capability && canonical.payload == request.payload)
            let response = HanlinMiniAppResponse(requestID: request.id, value: .string("result"))
            try require(try request.canonicalReturn(response).outcome == .result(.string("result")))
            try expect(SplitBridgeFailure.correlationMismatch) {
                _ = try request.canonicalReturn(HanlinMiniAppResponse(requestID: UUID(), value: .null))
            }
        }
        let label = try LocalizedValue(["en": "Fixture"])
        let descriptor = HanlinAppDescriptor(
            schemaVersion: .init(major: 1, minor: 0), descriptorRevision: try .init(1), id: target,
            name: label, summary: label, description: label, version: try .init(major: 1, minor: 0, patch: 0),
            apiVersion: .init(major: 1, minor: 0), icon: .systemSymbol(name: "app"), category: .utilities,
            implementation: .native(moduleID: try .init(validating: "fixture.module")),
            entryPoints: [.init(kind: .app, handler: "fixture", allowedContexts: [.mainApplication])],
            actions: [.init(id: action, title: label,
                            inputSchema: try .init(dialect: .draft2020_12, root: .object([:])),
                            capabilities: [capability], risk: .read)],
            capabilities: [.init(id: capability, reason: label, constraints: .object([:]), optional: false,
                                 risk: .read, requiresSystemAuthorization: false)],
            authors: [], distribution: .init(sourceVisible: true, sourceEditable: false,
                                             remoteUpdates: false, allowedModes: [.personalDevelopment]))
        try test("bridge.canonicalLaunch.realDescriptorAndEngine") {
            let plan = try request.launchPlan(descriptor: descriptor, installedPackageID: package, currentGeneration: 7)
            try require(plan.appID == target && plan.engine == .swift && plan.entryPoint.kind == .app)
        }
        try test("bridge.canonicalLaunch.rejectsUnknownActionPackageGeneration") {
            let wrongAction = try mutate("action", "not.declared")
            try expect(SplitBridgeFailure.unsupportedRoute) { _ = try wrongAction.launchPlan(descriptor: descriptor, installedPackageID: package, currentGeneration: 7) }
            try expect(SplitBridgeFailure.correlationMismatch) { _ = try request.launchPlan(descriptor: descriptor, installedPackageID: .init(validating: "other.package"), currentGeneration: 7) }
            try expect(SplitBridgeFailure.staleGeneration) { _ = try request.launchPlan(descriptor: descriptor, installedPackageID: package, currentGeneration: 8) }
        }
        try test("bridge.wakeHintContainsOnlyOpaqueRequestID") {
            let url = try SplitBridgeCodec.wakeURL(requestID: request.id, host: "fixture.invalid", returning: false)
            let id = try SplitBridgeCodec.wakeRequestID(url, allowedHost: "fixture.invalid", returning: false)
            try require(id == request.id && url.query == nil && !url.absoluteString.contains(session.rawValue))
        }
        for bad in ["http://fixture.invalid/hanlin/split/v1/open/", "https://attacker.invalid/hanlin/split/v1/open/",
                    "https://fixture.invalid:443/hanlin/split/v1/open/", "https://user@fixture.invalid/hanlin/split/v1/open/"] {
            try test("bridge.wake.reject.\(bad)") {
                guard let url = URL(string: bad + request.id.uuidString.lowercased()) else { throw TestFailure(message: "bad fixture") }
                try expect(SplitBridgeFailure.malformed) { _ = try SplitBridgeCodec.wakeRequestID(url, allowedHost: "fixture.invalid", returning: false) }
            }
        }
        try test("bridge.wake.rejectQueryFragmentAndWrongDirection") {
            let url = try SplitBridgeCodec.wakeURL(requestID: request.id, host: "fixture.invalid", returning: false)
            for suffix in ["?payload=secret", "#fragment", "/extra", "%2f"] {
                guard let altered = URL(string: url.absoluteString + suffix) else { throw TestFailure(message: "bad fixture") }
                try expect(SplitBridgeFailure.malformed) { _ = try SplitBridgeCodec.wakeRequestID(altered, allowedHost: "fixture.invalid", returning: false) }
            }
            try expect(SplitBridgeFailure.malformed) { _ = try SplitBridgeCodec.wakeRequestID(url, allowedHost: "fixture.invalid", returning: true) }
        }
        try test("bridge.begin.rejectDeniedUnsupportedAndDuplicate") {
            var ledger = SplitBridgeLedger()
            try expect(SplitBridgeFailure.denied) { try ledger.begin(request, now: now, routeAvailable: true, authorized: false) }
            try expect(SplitBridgeFailure.unsupportedRoute) { try ledger.begin(request, now: now, routeAvailable: false, authorized: true) }
            try ledger.begin(request, now: now, routeAvailable: true, authorized: true)
            try expect(SplitBridgeFailure.duplicate) { try ledger.begin(request, now: now, routeAvailable: true, authorized: true) }
        }
        try test("bridge.begin.rejectVersionExpiredAndFuture") {
            for altered in [try mutate("version", 2), try mutate("expiresAt", request.issuedAt.timeIntervalSinceReferenceDate),
                            try mutate("issuedAt", now.addingTimeInterval(5).timeIntervalSinceReferenceDate)] {
                var ledger = SplitBridgeLedger()
                try expect(SplitBridgeFailure.expired) { try ledger.begin(altered, now: now, routeAvailable: true, authorized: true) }
            }
        }
        for failure in [SplitBridgeFailure.denied, .companionMissing, .transportUnavailable, .offline, .staleGeneration, .timedOut] {
            try test("bridge.dispatch.\(failure.rawValue)") {
                var ledger = try pending()
                try expect(failure) {
                    try ledger.dispatch(request.id, now: failure == .timedOut ? now.addingTimeInterval(60) : now,
                                        currentGeneration: failure == .staleGeneration ? 8 : 7,
                                        authorized: failure != .denied, companionInstalled: failure != .companionMissing,
                                        transportReady: failure != .transportUnavailable, online: failure != .offline)
                }
                try require(ledger.record(request.id)?.phase == .pending)
            }
        }
        try test("bridge.return.exactOriginAndOneUseAcrossSerializedRestart") {
            var ledger = try dispatched()
            ledger = try JSONDecoder().decode(SplitBridgeLedger.self, from: JSONEncoder().encode(ledger))
            let response = SplitBridgeReturn(request: request, outcome: .result(.string("returned")))
            let origin = try ledger.accept(response, now: now, currentGeneration: 7, authenticatedSender: target, authorized: true)
            try require(origin.chat == request.chat && origin.session == request.session)
            try expect(SplitBridgeFailure.duplicate) { _ = try ledger.accept(response, now: now, currentGeneration: 7, authenticatedSender: target, authorized: true) }
        }
        for (field, value) in [("caller", "other.caller"), ("target", "other.target"),
                               ("installedPackage", "package.other"), ("session", "session.other"),
                               ("chat", UUID().uuidString), ("action", "other.action"), ("capability", "other.capability")] {
            try test("bridge.return.rejectMismatch.\(field)") {
                var ledger = try dispatched()
                let response = SplitBridgeReturn(request: try mutate(field, value), outcome: .result(.null))
                try expect(SplitBridgeFailure.correlationMismatch) { _ = try ledger.accept(response, now: now, currentGeneration: 7, authenticatedSender: target, authorized: true) }
            }
        }
        try test("bridge.return.rejectUnknownOutOfOrderSenderRevocationAndTimeout") {
            let response = SplitBridgeReturn(request: request, outcome: .result(.null))
            var unknown = SplitBridgeLedger()
            try expect(SplitBridgeFailure.correlationMismatch) { _ = try unknown.accept(response, now: now, currentGeneration: 7, authenticatedSender: target, authorized: true) }
            var ledger = try pending()
            try expect(SplitBridgeFailure.outOfOrder) { _ = try ledger.accept(response, now: now, currentGeneration: 7, authenticatedSender: target, authorized: true) }
            ledger = try dispatched()
            try expect(SplitBridgeFailure.correlationMismatch) { _ = try ledger.accept(response, now: now, currentGeneration: 7, authenticatedSender: caller, authorized: true) }
            try expect(SplitBridgeFailure.denied) { _ = try ledger.accept(response, now: now, currentGeneration: 7, authenticatedSender: target, authorized: false) }
            try expect(SplitBridgeFailure.staleGeneration) { _ = try ledger.accept(response, now: now, currentGeneration: 8, authenticatedSender: target, authorized: true) }
            try expect(SplitBridgeFailure.timedOut) { _ = try ledger.accept(response, now: now.addingTimeInterval(60), currentGeneration: 7, authenticatedSender: target, authorized: true) }
        }
        for failure in [SplitBridgeFailure.cancelled, .denied, .timedOut, .offline, .companionMissing] {
            try test("bridge.localFailure.consumesOnce.\(failure.rawValue)") {
                var ledger = try pending()
                try ledger.finish(request.id, failure: failure)
                try require(ledger.record(request.id)?.outcome == .failure(failure))
                try expect(SplitBridgeFailure.duplicate) { try ledger.finish(request.id, failure: failure) }
            }
        }

        let bytes = Data([0, 255, 13, 10, 0, 128])
        let source = try SplitStoreSnapshot(storeID: "old.fixture", revision: 3,
                                           files: ["registry/ids.json": bytes, "grants/data.json": Data("no elevated grants".utf8)])
        let destination = try SplitStoreSnapshot(storeID: "new.fixture", revision: 0, files: [:])
        let migrationID = try HanlinMigrationID(validating: "split.fixture.v1")
        let copies = ["registry/ids.json": "registry/ids.json", "grants/data.json": "grants/data.json"]
        let plan = try SplitMigrationPlan(id: migrationID, source: source, destination: destination, copies: copies)
        try test("migration.dryRun.bytePreservingAndNoInputMutation") {
            let before = try JSONEncoder().encode(source)
            let output = try plan.dryRun(source: source, destination: destination)
            try require(output.files == source.files && destination.files.isEmpty)
            let after = try JSONDecoder().decode(SplitStoreSnapshot.self, from: before)
            try require(source == after)
            try require(try plan.dryRun(source: source, destination: destination) == output)
        }
        try test("migration.applyIdempotentResumeBackupAndRollback") {
            var journal = try SplitMigrationJournal(plan: plan)
            try expect(SplitMigrationError.interrupted) { _ = try journal.apply(source: source, current: destination, interruptAfter: 1) }
            try require(journal.output.files.count == 1 && !journal.complete)
            journal = try JSONDecoder().decode(SplitMigrationJournal.self, from: JSONEncoder().encode(journal))
            let output = try journal.apply(source: source, current: journal.output)
            try require(output.files == source.files && journal.complete)
            try require(try journal.apply(source: source, current: output) == output)
            try require(try journal.rollback(current: output) == destination)
            try require(source.files["registry/ids.json"] == bytes)
        }
        try test("migration.rejectChangedSourceAndDestination") {
            let changed = try SplitStoreSnapshot(storeID: source.storeID, revision: 4, files: source.files)
            try expect(SplitMigrationError.sourceChanged) { _ = try plan.dryRun(source: changed, destination: destination) }
            let conflicting = try SplitStoreSnapshot(storeID: destination.storeID, revision: 1, files: ["other": bytes])
            try expect(SplitMigrationError.destinationConflict) { _ = try plan.dryRun(source: source, destination: conflicting) }
        }
        try test("migration.rejectUnsupportedSerializedVersion") {
            guard var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any]
            else { throw TestFailure(message: "plan fixture encoding") }
            object["version"] = 2
            let future = try JSONDecoder().decode(SplitMigrationPlan.self, from: JSONSerialization.data(withJSONObject: object))
            try expect(SplitMigrationError.unsupportedVersion) { _ = try future.dryRun(source: source, destination: destination) }
        }
        try test("migration.rejectConflictingExistingBytesAndDuplicateDestinations") {
            let conflict = try SplitStoreSnapshot(storeID: destination.storeID, revision: 0, files: ["registry/ids.json": Data([1])])
            try expect(SplitMigrationError.destinationConflict) { _ = try SplitMigrationPlan(id: migrationID, source: source, destination: conflict, copies: copies) }
            try expect(SplitMigrationError.duplicateDestination) { _ = try SplitMigrationPlan(id: migrationID, source: source, destination: destination, copies: ["registry/ids.json": "same", "grants/data.json": "same"]) }
            try expect(SplitMigrationError.overlappingStores) { _ = try SplitMigrationPlan(id: migrationID, source: source, destination: source, copies: copies) }
        }
        for path in ["../outside", "/absolute", "C:/private", "a\\b", "a//b", "a/./b", "a/../b", "a/%2e%2e/b", "a\u{0}b", "a.", "a "] {
            try test("migration.rejectUnsafePath.\(path.debugDescription)") {
                try expect(SplitMigrationError.unsafePath) { _ = try SplitStoreSnapshot(storeID: "fixture", revision: 0, files: [path: bytes]) }
            }
        }
        try test("migration.rollbackRejectsPostCopyEdits") {
            var journal = try SplitMigrationJournal(plan: plan)
            _ = try journal.apply(source: source, current: destination)
            let external = try SplitStoreSnapshot(storeID: destination.storeID, revision: 2, files: ["user.edit": bytes])
            try expect(SplitMigrationError.rollbackConflict) { _ = try journal.rollback(current: external) }
        }
        try test("migration.rejectTamperedSerializedJournal") {
            var journal = try SplitMigrationJournal(plan: plan)
            _ = try journal.apply(source: source, current: destination)
            guard var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(journal)) as? [String: Any]
            else { throw TestFailure(message: "journal fixture encoding") }
            object["copied"] = []
            let corrupt = try JSONSerialization.data(withJSONObject: object)
            journal = try JSONDecoder().decode(SplitMigrationJournal.self, from: corrupt)
            try expect(SplitMigrationError.snapshotMismatch) { _ = try journal.rollback(current: journal.output) }
            try expect(SplitMigrationError.snapshotMismatch) { _ = try journal.apply(source: source, current: journal.output) }
        }
        try test("migration.fixtureDisk.backupDryRunInterruptionResumeAndRollback") {
            guard CommandLine.arguments.count == 2 else { throw TestFailure(message: "fixture root required") }
            let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            let store = try SplitFixtureStore(root: root)
            try store.write(source, to: .source)
            try store.write(destination, to: .destination)
            let before = try Data(contentsOf: root.appendingPathComponent("source.json"))
            _ = try plan.dryRun(source: source, destination: destination)
            try require(try Data(contentsOf: root.appendingPathComponent("source.json")) == before)
            try require(try store.read(SplitStoreSnapshot.self, from: .destination) == destination)
            var journal = try SplitMigrationJournal(plan: plan)
            try expect(SplitMigrationError.interrupted) { _ = try journal.apply(source: source, current: destination, interruptAfter: 1) }
            try store.write(journal, to: .journal)
            try store.write(journal.output, to: .destination)
            journal = try store.read(SplitMigrationJournal.self, from: .journal)
            let partial = try store.read(SplitStoreSnapshot.self, from: .destination)
            let result = try journal.apply(source: store.read(SplitStoreSnapshot.self, from: .source), current: partial)
            try store.write(result, to: .destination)
            try store.write(journal.rollback(current: result), to: .destination)
            try require(try store.read(SplitStoreSnapshot.self, from: .destination) == destination)
            try require(try Data(contentsOf: root.appendingPathComponent("source.json")) == before)
            let files = try Set(FileManager.default.contentsOfDirectory(atPath: root.path))
            try require(files == [".hanlin-product-split-fixture", "source.json", "destination.json", "journal.json"])
        }
        try test("migration.fixtureDisk.refusesUnmarkedRoot") {
            guard CommandLine.arguments.count == 2 else { throw TestFailure(message: "fixture root required") }
            let parent = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).deletingLastPathComponent()
            do { _ = try SplitFixtureStore(root: parent) }
            catch { return }
            throw TestFailure(message: "unmarked root accepted")
        }
        let data = try JSONSerialization.data(withJSONObject: ["status": "EXECUTED_PASS", "count": passed.count, "tests": passed], options: [.sortedKeys])
        guard let report = String(data: data, encoding: .utf8) else { throw TestFailure(message: "report encoding") }
        print(report)
    }
}
