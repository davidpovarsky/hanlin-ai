import Foundation
import HanlinAgentCore
import HanlinHostContracts
import HanlinPersistenceAdapters
import HanlinPlatformContracts
import HanlinSDKTestFixtures

private struct ProofFailure: Error { let detail: String }
private func require(_ condition: Bool, _ detail: String) throws {
    if !condition { throw ProofFailure(detail: detail) }
}
@MainActor private func rejects(_ expected: HanlinHostError? = nil, _ body: @MainActor () async throws -> Void) async throws {
    do { try await body() }
    catch {
        if let expected { try require((error as? HanlinHostError) == expected, "Unexpected error: \(error)") }
        return
    }
    throw ProofFailure(detail: "Expected rejection")
}
private actor ProgressLog {
    var values: [UInt64] = []
    func record(_ event: HanlinToolProgressEvent) { values.append(event.sequence) }
}
private struct Fixture {
    let host: SyntheticFixtureHost
    let dispatcher: HanlinHostDispatcher
    let session: HanlinHostSession
    let catalog: HanlinHostCatalog
    let run = UUID()
    static func make() async throws -> Fixture {
        let namespace = try HanlinConversationNamespace(app: "fixture", account: "account", workspace: "workspace", space: "space")
        let context = HanlinHostContext(namespace: namespace, sceneID: UUID(), generation: UUID(), sourceRevision: "snapshot-1")
        let host = SyntheticFixtureHost(context: context)
        return try await .init(host: host, dispatcher: HanlinHostDispatcher(host: host),
            session: .init(conversationID: UUID(), context: context), catalog: host.catalog(for: context))
    }
    func call(_ alias: String = "fixture_read", arguments: String = #"{"text":"input"}"#,
              id: String = "opaque-call/1", expectedRevision: String? = nil,
              limits: HanlinToolInvocationLimits? = nil) async throws -> HanlinHostExecutionResult {
        try await dispatcher.dispatch(alias: alias, argumentsJSON: arguments, providerCallID: id, runID: run,
            step: 0, session: session, catalog: catalog, expectedRevision: expectedRevision, limits: limits ?? .init())
    }
}

@main struct PortableProof {
    static func main() async throws {
        var passed: [String] = []
        let cases: [(String, () async throws -> Void)] = [
            ("native cumulative snapshots and combining marks emit exact suffix once", {
                var delta = HanlinAppleTextDelta()
                try require(try delta.append(snapshot: "ש") == "ש", "Initial snapshot")
                try require(try delta.append(snapshot: "ש\u{05b8}") == "\u{05b8}", "Combining mark lost")
                try require(try delta.append(snapshot: "ש\u{05b8}") == "", "Duplicate snapshot repeated")
                do { _ = try delta.append(snapshot: "changed") }
                catch HanlinAppleProviderError.inconsistentSnapshot { return }
                throw ProofFailure(detail: "Non-prefix native snapshot was accepted")
            }),
            ("opaque namespace identities do not merge Unicode byte sequences", {
                let one = try HanlinConversationNamespace(app: "fixture", account: "\u{00e9}", workspace: "w", space: "s")
                let two = try HanlinConversationNamespace(app: "fixture", account: "e\u{0301}", workspace: "w", space: "s")
                try require(one != two && Set([one, two]).count == 2, "Opaque identity normalized")
            }),
            ("namespace rejects empty decoded identity", {
                try await rejects(.invalidContext) { _ = try JSONDecoder().decode(HanlinConversationNamespace.self, from: Data(#"{"app":"","account":"a","workspace":"w","space":"s"}"#.utf8)) }
            }),
            ("scoped read through host", {
                let f = try await Fixture.make(); let result = try await f.call()
                try require(result.effectState == .confirmedNoEffect, "Read effect")
                try require(await f.host.executions == 1, "Read dispatch")
                try require(await f.host.nativeWrites == 0, "Read mutation")
            }),
            ("unknown tool never dispatches", {
                let f = try await Fixture.make()
                try await rejects(.unknownTool) { _ = try await f.call("unknown") }
                try require(await f.host.executions == 0, "Unknown dispatched")
            }),
            ("duplicate catalog aliases rejected", {
                let f = try await Fixture.make()
                try await rejects(.duplicateAlias) {
                    let catalog = HanlinHostCatalog(revision: f.catalog.revision, context: f.session.context, tools: f.catalog.tools + f.catalog.tools)
                    try catalog.validate()
                }
            }),
            ("duplicate JSON member rejected before host", {
                let f = try await Fixture.make()
                try await rejects { _ = try await f.call(arguments: #"{"text":"a","text":"b"}"#) }
                try require(await f.host.executions == 0, "Invalid JSON dispatched")
            }),
            ("actual fixture schema rejects extra field", {
                let f = try await Fixture.make(); let r = try await f.call("fixture_create", arguments: #"{"text":"input","extra":true}"#)
                try require(r.effectState == .uncertain, "Conservative write failure")
                try require(await f.host.nativeWrites == 0, "Schema bypass")
            }),
            ("denied consent has no effect", {
                let f = try await Fixture.make(); await f.host.setMode(.deny)
                let r = try await f.call("fixture_create")
                try require(r.effectState == .notDispatched, "Denial effect")
                try require(await f.host.nativeWrites == 0, "Denied write")
            }),
            ("duplicate write returns one authoritative receipt", {
                let f = try await Fixture.make(); let one = try await f.call("fixture_create"); let two = try await f.call("fixture_create")
                try require(one == two && one.effectState == .confirmedCommitted, "Receipt changed")
                try require(await f.host.nativeWrites == 1, "Repeated write")
            }),
            ("idempotency conflict never repeats write", {
                let f = try await Fixture.make(); _ = try await f.call("fixture_create")
                try await rejects(.idempotencyConflict) { _ = try await f.call("fixture_create", arguments: #"{"text":"changed"}"#) }
                try require(await f.host.nativeWrites == 1, "Conflict repeated")
            }),
            ("conditional edit unsupported without CAS", {
                let f = try await Fixture.make()
                try await rejects(.unsupportedConditionalWrite) { _ = try await f.call("fixture_create", expectedRevision: "snapshot-1") }
                try require(await f.host.executions == 0, "Unsupported CAS dispatched")
            }),
            ("stale scene generation rejected", {
                let f = try await Fixture.make()
                await f.host.setContext(.init(namespace: f.session.context.namespace, sceneID: UUID(), generation: UUID()))
                try await rejects(.staleContext) { _ = try await f.call() }
                try require(await f.host.executions == 0, "Stale scene dispatched")
            }),
            ("cancellation after dispatched write is uncertain and not retried", {
                let f = try await Fixture.make(); await f.host.setMode(.uncertainAfterDispatch)
                let r = try await f.call("fixture_create"); let duplicate = try await f.call("fixture_create")
                try require(r.effectState == .uncertain && r == duplicate, "Uncertainty lost")
                try require(await f.host.nativeWrites == 1, "Uncertain write retried")
            }),
            ("context switch suppresses delivery but retains original receipt", {
                let f = try await Fixture.make(); await f.host.setMode(.changeContextAfterDispatch)
                try await rejects(.staleContext) { _ = try await f.call("fixture_create") }
                let receipts = await f.dispatcher.receipts(for: f.session)
                try require(receipts.count == 1 && receipts[0].context == f.session.context, "Original receipt lost")
                try require(await f.host.nativeWrites == 1, "Effect missing")
            }),
            ("out-of-order progress suppressed", {
                let f = try await Fixture.make(); let log = ProgressLog()
                _ = try await f.dispatcher.dispatch(alias: "fixture_read", argumentsJSON: #"{"text":"input"}"#,
                    providerCallID: "call", runID: f.run, step: 0, session: f.session, catalog: f.catalog,
                    limits: .init(), progress: { await log.record($0) })
                try require(await log.values == [2], "Progress order")
            }),
            ("revoked presentation cannot dispatch", {
                let f = try await Fixture.make(); await f.dispatcher.invalidate(f.session)
                try await rejects(.staleContext) { _ = try await f.call() }
                try require(await f.host.executions == 0, "Revoked dispatch")
            }),
            ("output budget rejects delivery without losing receipt", {
                let f = try await Fixture.make()
                try await rejects(.outputLimitExceeded) { _ = try await f.call("fixture_create", limits: .init(maximumOutputBytes: 1)) }
                try require(await f.dispatcher.receipts(for: f.session).count == 1, "Budget lost receipt")
                try require(await f.host.nativeWrites == 1, "Budget repeat")
                try await rejects(.outputLimitExceeded) { _ = try await f.call("fixture_create", limits: .init(maximumOutputBytes: 1)) }
                try require(await f.host.nativeWrites == 1, "Cached budget repeat")
            }),
            ("queued navigation is not a native UI acknowledgement", {
                let f = try await Fixture.make()
                let target = HanlinHostDestination(context: f.session.context, objectReference: "exact-object", blockReference: "exact-block")
                let result = try await f.dispatcher.open(target, session: f.session)
                try require(!result.presentationAcknowledged, "Queue claimed actual UI")
                try await rejects(.resultMismatch) {
                    try HanlinHostNavigationResult.presented(requestID: target.requestID, context: target.context, objectReference: "wrong-object", blockReference: target.blockReference).validate(for: target)
                }
            }),
            ("metadata receipt excludes business payload and raw error details", {
                let f = try await Fixture.make(); let r = try await f.call()
                let input = HanlinHostExecutionResult(result: .init(invocationID: r.result.invocationID, logicalToolID: r.result.logicalToolID,
                    outcome: .failed(.init(code: .nativeFailure, userMessage: "SYNTHETIC_SECRET", diagnosticMessage: "SYNTHETIC_SECRET")), completedAt: .now),
                    effectState: .uncertain, context: r.context, reconciliationReference: "opaque-receipt")
                let data = try JSONEncoder().encode(input.metadataReceipt())
                try require(!String(decoding: data, as: UTF8.self).contains("SYNTHETIC_SECRET"), "Raw error persisted")
                let completed = HanlinHostExecutionResult(result: .init(invocationID: r.result.invocationID, logicalToolID: r.result.logicalToolID,
                    outcome: .completed([.text("SYNTHETIC_SECRET")]), completedAt: .now), effectState: .confirmedNoEffect, context: r.context)
                try require(!String(decoding: JSONEncoder().encode(completed.metadataReceipt()), as: UTF8.self).contains("SYNTHETIC_SECRET"), "Raw business result persisted")
            }),
            ("ephemeral store isolates namespaces and enforces revision", {
                let store = HanlinInMemoryConversationStore(); let f = try await Fixture.make()
                let other = try HanlinConversationNamespace(app: "fixture", account: "another", workspace: "workspace", space: "space")
                let r = HanlinConversationRecord(namespace: f.session.context.namespace, conversationID: f.session.conversationID, revision: 0, draft: "original")
                try await store.save(r, replacing: nil)
                try require(await store.load(r.conversationID, namespace: other) == nil, "Cross-account read")
                try await rejects(.storeConflict) { try await store.save(r, replacing: nil) }
            }),
            ("replay rejects newer version and non-monotonic events", {
                let f = try await Fixture.make(); let ns = f.session.context.namespace
                try await rejects(.unsupportedVersion) { try HanlinConversationRecord(formatVersion: 99, namespace: ns, conversationID: UUID(), revision: 0).validate() }
                try await rejects(.invalidRecord) {
                    let e = HanlinTranscriptEntry(runID: UUID(), step: 0, sequence: 1, payload: .cancelled)
                    try HanlinConversationRecord(namespace: ns, conversationID: UUID(), revision: 0, entries: [e, e]).validate()
                }
            }),
            ("private store roundtrip checkpoint and rollback preserve namespaces", {
                let f = try await Fixture.make(); let ns = f.session.context.namespace
                let root = FileManager.default.temporaryDirectory.appending(path: "hanlin-sdk-proof-" + UUID().uuidString, directoryHint: .isDirectory)
                defer { try? FileManager.default.removeItem(at: root) } // Owned newly generated synthetic root only.
                let store = try HanlinPrivateConversationStore(directory: root)
                let r = HanlinConversationRecord(namespace: ns, conversationID: UUID(), revision: 0, draft: "before")
                try await store.save(r, replacing: nil)
                let checkpoint = try await store.checkpoint(r.conversationID, namespace: ns)
                try await store.save(.init(namespace: ns, conversationID: r.conversationID, revision: 1, draft: "after"), replacing: 0)
                try await store.restoreCheckpoint(checkpoint, namespace: ns, replacing: 1)
                let restored = try await store.load(r.conversationID, namespace: ns)
                try require(restored?.draft == "before" && restored?.revision == 2, "Rollback changed bytes")
                let other = try HanlinConversationNamespace(app: "fixture", account: "other", workspace: "workspace", space: "space")
                try require(try await store.load(r.conversationID, namespace: other) == nil, "Private store leaked account")
                try await rejects(.invalidRecord) { try await store.restoreCheckpoint(checkpoint, namespace: other, replacing: 2) }
                try await store.delete(r.conversationID, namespace: ns, replacing: 2)
                try require(try await store.load(r.conversationID, namespace: ns) == nil, "Delete failed")
            })
        ]
        for (name, body) in cases {
            do { try await body(); passed.append(name); print("PASS: \(name)") }
            catch { print("FAIL: \(name): \(error)"); throw error }
        }
        let report: [String: Any] = ["scope": "Actual portable host contracts, dispatcher, stores and synthetic host; excludes AgentSession/SwiftAISDK/FoundationModels/native UI", "passed": passed, "count": passed.count]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self))
    }
}
