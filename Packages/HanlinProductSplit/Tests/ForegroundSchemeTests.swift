import Foundation
import HanlinPlatformContracts

private struct Failure: Error { let detail: String }
private func check(_ value: @autoclosure () throws -> Bool) throws {
    guard try value() else { throw Failure(detail: "assertion failed") }
}

@main
private enum ForegroundSchemeTests {
    static func main() throws {
        var names: [String] = []
        func test(_ name: String, _ body: () throws -> Void) throws {
            do { try body(); names.append(name) }
            catch { throw Failure(detail: "\(name): \(error)") }
        }
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        for route in SplitForegroundRoute.allCases {
            let canonical = route.url(reference: id)
            try test("scheme.\(route).opaqueUUIDRoundTrip") {
                try check(route.reference(in: canonical) == id)
                try check(canonical.absoluteString.hasSuffix(id.uuidString.lowercased()))
            }
            let other: SplitForegroundRoute = route == .openMiniApps ? .returnToAI : .openMiniApps
            let original = canonical.absoluteString
            let variants: [(String, String)] = [
                ("wrongProduct", other.url(reference: id).absoluteString),
                ("wrongHost", original.replacingOccurrences(of: "://split/", with: "://untrusted/")),
                ("wrongVersion", original.replacingOccurrences(of: "/v1/", with: "/v2/")),
                ("uppercaseUUID", original.replacingOccurrences(of: id.uuidString.lowercased(), with: id.uuidString)),
                ("userinfo", original.replacingOccurrences(of: "://split", with: "://caller@split")),
                ("password", original.replacingOccurrences(of: "://split", with: "://caller:secret@split")),
                ("port", original.replacingOccurrences(of: "://split", with: "://split:443")),
                ("payload", original + "?payload=execute"), ("emptyQuery", original + "?"),
                ("fragment", original + "#chat"), ("emptyFragment", original + "#"),
                ("trailingSlash", original + "/"), ("extraPath", original + "/execute"),
                ("encodedPath", original.replacingOccurrences(of: "/v1/", with: "/%761/")),
                ("shortID", original.replacingOccurrences(of: id.uuidString.lowercased(), with: "a")),
                ("oversize", original + String(repeating: "x", count: 129))
            ]
            for (name, input) in variants {
                try test("scheme.\(route).reject.\(name)") {
                    guard let url = URL(string: input) else { throw Failure(detail: "test URL could not be constructed") }
                    do { _ = try route.reference(in: url) }
                    catch SplitBridgeFailure.malformed { return }
                    throw Failure(detail: "accepted non-canonical route")
                }
            }
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let request = SplitBridgeRequest(id: id, caller: try .init(validating: "hanlin.host"),
            target: try .init(validating: "fixture.target"), installedPackage: try .init(validating: "fixture.package"),
            session: try .init(validating: "fixture.session"), chat: UUID(), generation: 7,
            action: try .init(validating: "share.value"), capability: try .init(validating: "inter-app.share"),
            issuedAt: now, expiresAt: now.addingTimeInterval(60), payload: .string("original"))
        var ledger = SplitBridgeLedger()
        try test("senderDatabase.validatesPendingAndDispatched") {
            try ledger.validate()
            try ledger.begin(request, now: now, routeAvailable: true, authorized: true)
            try ledger.validate()
            try ledger.dispatch(id, now: now, currentGeneration: 7, authorized: true,
                                companionInstalled: true, transportReady: true, online: true)
            try ledger.validate()
        }
        try test("senderDatabase.returnUsesImmutableOriginAndConsumesOnce") {
            let decoded = try JSONDecoder().decode(SplitBridgeLedger.self, from: JSONEncoder().encode(ledger))
            var restored = decoded
            let response = SplitBridgeReturn(request: request, outcome: .result(.string("result")))
            let origin = try restored.accept(response, now: now, currentGeneration: 7,
                                             authenticatedSender: request.target, authorized: true)
            try check(origin.chat == request.chat && origin.session == request.session)
            try restored.validate()
            do { _ = try restored.accept(response, now: now, currentGeneration: 7,
                                          authenticatedSender: request.target, authorized: true) }
            catch SplitBridgeFailure.duplicate { return }
            throw Failure(detail: "duplicate return accepted")
        }
        for mutation in ["version", "outcome"] {
            try test("senderDatabase.rejectDecodedCorruption.\(mutation)") {
                var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as! [String: Any]
                var records = object["records"] as! [Any]
                var record = records[1] as! [String: Any]
                if mutation == "version" {
                    var changed = record["request"] as! [String: Any]; changed["version"] = 99; record["request"] = changed
                } else { record["phase"] = "finished" }
                records[1] = record; object["records"] = records
                let corrupted = try JSONDecoder().decode(SplitBridgeLedger.self, from: JSONSerialization.data(withJSONObject: object))
                do { try corrupted.validate() }
                catch SplitDurabilityError.corruptState { return }
                throw Failure(detail: "corrupt decoded state accepted")
            }
        }
        try test("senderCancellation.missingReceiverDoesNotReserve") {
            var database = SplitReceiverDatabase()
            try check(database.interruptIfPresent(request, reason: .cancelled) == nil)
            try check(database.records.isEmpty)
            try database.validate()
        }
        try test("senderCancellation.reservedAttemptCannotStart") {
            var database = SplitReceiverDatabase()
            _ = try database.reserve(request)
            let cancelled = try database.interruptIfPresent(request, reason: .cancelled)
            try check(cancelled?.phase == .completed && cancelled?.outcome == .failure(.cancelled) && cancelled?.attempt == nil)
            do { _ = try database.update(request) { try $0.start() } }
            catch SplitBridgeFailure.outOfOrder { return }
            throw Failure(detail: "cancelled reservation started")
        }
        try test("senderCancellation.executingAttemptStaysUnknownWithoutReplay") {
            var database = SplitReceiverDatabase()
            _ = try database.reserve(request)
            let started = try database.update(request) { try $0.start() }
            let cancelled = try database.interruptIfPresent(request, reason: .cancelled)
            try check(cancelled?.phase == .outcomeUnknown && cancelled?.attempt == started.attempt && cancelled?.outcome == nil)
            try database.validate()
            do { _ = try database.update(request) { try $0.start() } }
            catch SplitDurabilityError.outcomeUnknown { return }
            throw Failure(detail: "interrupted attempt replayed")
        }
        try test("senderCancellation.wrongImmutableOriginPreservesRecord") {
            var database = SplitReceiverDatabase()
            _ = try database.reserve(request)
            let original = database
            let wrong = SplitBridgeRequest(id: request.id, caller: request.caller, target: request.target,
                installedPackage: request.installedPackage, session: request.session, chat: UUID(), generation: request.generation,
                action: request.action, capability: request.capability, issuedAt: request.issuedAt,
                expiresAt: request.expiresAt, payload: request.payload)
            do { _ = try database.interruptIfPresent(wrong, reason: .cancelled) }
            catch SplitBridgeFailure.correlationMismatch { try check(database == original); return }
            throw Failure(detail: "wrong-origin cancellation accepted")
        }
        let report: [String: Any] = ["status": "EXECUTED_PASS", "count": names.count, "tests": names]
        print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
