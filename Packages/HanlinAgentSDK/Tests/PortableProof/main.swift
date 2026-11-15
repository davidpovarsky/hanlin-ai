import Foundation
import AISDKProvider
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
@MainActor private func rejectsCancellation(_ body: @MainActor () async throws -> Void) async throws {
    do { try await body() }
    catch is CancellationError { return }
    throw ProofFailure(detail: "Expected task cancellation after captured-context await")
}
@MainActor private func rejectsNumericModelInput(_ body: @MainActor () async throws -> Void) async throws {
    do { try await body() }
    catch HanlinModelToolInputError.numericArgumentsUnsupported { return }
    throw ProofFailure(detail: "Expected explicit numeric model-input rejection")
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

private struct GatedFixture: Sendable {
    let host: GatedContextHost
    let dispatcher: HanlinHostDispatcher
    let session: HanlinHostSession
    let catalog: HanlinHostCatalog
    let run: UUID
    static func make(forwardProgress: Bool = false) async throws -> Self {
        let fixture = try await Fixture.make()
        let host = GatedContextHost(context: fixture.session.context, forwardProgress: forwardProgress)
        return .init(host: host, dispatcher: HanlinHostDispatcher(host: host), session: fixture.session,
                     catalog: fixture.catalog, run: fixture.run)
    }
    func call(progress: @escaping @Sendable (HanlinToolProgressEvent) async -> Void = { _ in }) async throws -> HanlinHostExecutionResult {
        try await dispatcher.dispatch(alias: "fixture_create", argumentsJSON: #"{"text":"gated input"}"#,
            providerCallID: "gated-call", runID: run, step: 0, session: session, catalog: catalog,
            limits: .init(), progress: progress)
    }
    var destination: HanlinHostDestination { .init(context: session.context, objectReference: "gated-object", blockReference: "gated-block") }
}

/// Isolated guard-body fixture, NOT an AgentSession replacement/pass. Actual production guard
/// encloses real store/dispatcher side effects to prove the rejected body cannot create a pending call.
@MainActor private func guardBoundaryCall(_ input: String, fixture: Fixture,
                                         store: HanlinInMemoryConversationStore) async throws -> HanlinHostExecutionResult {
    try await HanlinModelToolInputGuard.withValidatedArguments(input) { _ in
        let pending = HanlinTranscriptEntry(runID: fixture.run, step: 0, sequence: 0,
            payload: .toolCall(providerCallID: "guard-call", alias: "fixture_create", arguments: .null))
        let context = fixture.session.context
        try await store.save(.init(namespace: context.namespace, conversationID: fixture.session.conversationID,
            revision: 0, entries: [pending]), replacing: nil)
        let result = try await fixture.call("fixture_create", arguments: input, id: "guard-call")
        let completed = HanlinTranscriptEntry(runID: fixture.run, step: 0, sequence: 1,
            payload: .toolResult(providerCallID: "guard-call", result: result.metadataReceipt()))
        try await store.save(.init(namespace: context.namespace, conversationID: fixture.session.conversationID,
            revision: 1, entries: [pending, completed]), replacing: 0)
        return result
    }
}

/// Synthetic native caller with a real integer schema. Demonstrates that the DIRECT dispatcher
/// still accepts original canonical integer bytes; it does not claim model-path numeric fidelity.
private actor CanonicalIntegerHost: HanlinHostIntegration {
    nonisolated let apiVersion = HanlinAPIVersion(major: 1, minor: 0)
    let original: HanlinHostContext
    private(set) var received: Int64?
    init(context: HanlinHostContext) { original = context }
    func context(for session: HanlinHostSession) -> HanlinHostContext { original }
    func catalog(for context: HanlinHostContext) throws -> HanlinHostCatalog {
        guard context == original else { throw HanlinHostError.staleContext }
        let base = try SyntheticFixtureHost.tool("fixture_integer_read", risk: .read, guarantee: .readOnly)
        let schema = try HanlinJSONSchemaDocument.decodeCanonicalJSON(Data(#"{"type":"object","properties":{"count":{"type":"integer"}},"required":["count"],"additionalProperties":false}"#.utf8), defaultDialect: .draft2020_12)
        let descriptor = HanlinToolDescriptor(logicalID: base.descriptor.logicalID, descriptorRevision: base.descriptor.descriptorRevision,
            owner: .system, title: base.descriptor.title, summary: base.descriptor.summary, inputSchema: schema, risk: .read, presentation: .init())
        return .init(revision: .init(1), context: context, tools: [.init(route: base.route, descriptor: descriptor, writeGuarantee: .readOnly)])
    }
    func execute(_ invocation: HanlinHostInvocation, progress: @escaping @Sendable (HanlinToolProgressEvent) async -> Void) throws -> HanlinHostExecutionResult {
        guard invocation.session.context == original, invocation.request.aliasUsed == "fixture_integer_read",
              case .object(let fields) = invocation.request.arguments, fields.count == 1,
              case .integer(let value)? = fields["count"] else { throw HanlinHostError.invalidArguments }
        received = value
        return .init(result: .init(invocationID: invocation.request.id, logicalToolID: invocation.request.logicalToolID,
            outcome: .completed([.text("Validated original canonical integer")]), completedAt: .now), effectState: .confirmedNoEffect, context: original)
    }
    func cancel(_ invocation: HanlinToolInvocationID) {}
    func open(_ destination: HanlinHostDestination) throws -> HanlinHostNavigationResult { throw HanlinHostError.unsupportedProviderCapability }
}

@main struct PortableProof {
    static func main() async throws {
        var passed: [String] = []
        let cases: [(String, () async throws -> Void)] = [
            ("model guard rejects actual pinned numeric roundtrips before pending or host effects", {
                for token in ["1.0", "1e0", "9007199254740993", "9223372036854775807"] {
                    let f = try await Fixture.make(); let store = HanlinInMemoryConversationStore()
                    let original = Data(("{\"count\":" + token + "}").utf8)
                    let normalized = try JSONEncoder().encode(JSONDecoder().decode(AISDKProvider.JSONValue.self, from: original))
                    try await rejectsNumericModelInput { _ = try await guardBoundaryCall(String(decoding: normalized, as: UTF8.self), fixture: f, store: store) }
                    try require(await f.host.executions == 0, "Numeric input reached host")
                    try require(await f.host.nativeWrites == 0, "Numeric input wrote")
                    try require(await store.load(f.session.conversationID, namespace: f.session.context.namespace) == nil, "Rejected input left pending record")
                    try require(await f.dispatcher.receipts(for: f.session).isEmpty, "Rejected input reserved host invocation")
                }
            }),
            ("model guard rejects every numeric leaf including nested small exact numbers", {
                for input in ["0", "1", "-1", "0.0", "-0.0", "2.5", #"{"outer":[true,{"inner":0}]}"#, #"[null,{"items":["1",1.0]}]"#] {
                    let f = try await Fixture.make(); let store = HanlinInMemoryConversationStore()
                    let normalized = try JSONEncoder().encode(JSONDecoder().decode(AISDKProvider.JSONValue.self, from: Data(input.utf8)))
                    try await rejectsNumericModelInput { _ = try await guardBoundaryCall(String(decoding: normalized, as: UTF8.self), fixture: f, store: store) }
                    try require(await f.host.executions == 0, "Nested number reached host")
                    try require(await store.load(f.session.conversationID, namespace: f.session.context.namespace) == nil, "Nested rejection left pending call")
                }
            }),
            ("model guard preserves digits in strings booleans and null without coercion", {
                let input = #"{"id":"9007199254740993","decimal":"1.0","exponent":"1e0","values":[true,false,null,{"json":"{\"n\":1}"}]}"#
                let expected = try HanlinJSONValue.decodeCanonicalJSON(Data(input.utf8))
                let actual = try await HanlinModelToolInputGuard.withValidatedArguments(input) { value in value }
                try require(actual == expected, "Nonnumeric values were coerced")
            }),
            ("nonnumeric model guard body executes and resolves its fixture pending call", {
                let f = try await Fixture.make(); let store = HanlinInMemoryConversationStore()
                let result = try await guardBoundaryCall(#"{"text":"1.0 1e0 9007199254740993"}"#, fixture: f, store: store)
                try require(result.effectState == .confirmedCommitted, "Nonnumeric tool failed")
                try require(await f.host.nativeWrites == 1, "Nonnumeric host call did not run once")
                let record = await store.load(f.session.conversationID, namespace: f.session.context.namespace)
                try require(record?.entries.count == 2 && record?.revision == 1, "Nonnumeric call did not resolve pending metadata")
            }),
            ("isolated verified-original guard preserves Int64 and decimal categories", {
                for input in [#"{"n":9007199254740993}"#, #"{"n":9223372036854775807}"#, #"{"n":-9223372036854775808}"#, #"{"n":1.0}"#, #"{"n":1e0}"#, #"{"a":[{"n":9007199254740993},0.5,1e0]}"#] {
                    let actual = try HanlinModelToolInputGuard.validate(input, originalInputVerified: true)
                    try require(actual == HanlinJSONValue.decodeCanonicalJSON(Data(input.utf8)), "Original guard changed canonical category")
                }
                guard case .object(let integer) = try HanlinModelToolInputGuard.validate(#"{"n":9007199254740993}"#, originalInputVerified: true),
                      case .integer(9007199254740993)? = integer["n"],
                      case .object(let decimal) = try HanlinModelToolInputGuard.validate(#"{"n":1.0}"#, originalInputVerified: true),
                      case .number(1)? = decimal["n"] else { throw ProofFailure(detail: "Original categories lost") }
            }),
            ("isolated verified-original guard rejects unsupported numeric precision before body", {
                for input in [#"{"n":18446744073709551615}"#, #"{"n":9223372036854775808}"#, #"{"n":9007199254740993.0}"#, #"{"n":0.10000000000000000001}"#, #"{"n":1e-400}"#, #"{"n":1e400}"#, #"{"n":1,"n":2}"#] {
                    var entered = false
                    do {
                        _ = try await HanlinModelToolInputGuard.withValidatedArguments(input, originalInputVerified: true) { value in
                            entered = true; return value
                        }
                        throw ProofFailure(detail: "Unsupported numeric input accepted")
                    } catch is ProofFailure { throw ProofFailure(detail: "Unsupported numeric input accepted") }
                    catch { try require(!entered, "Unsupported input entered persistence/dispatch body") }
                }
            }),
            ("direct canonical dispatcher preserves original Int64 without model guard", {
                let f = try await Fixture.make(); let host = CanonicalIntegerHost(context: f.session.context)
                let dispatcher = HanlinHostDispatcher(host: host)
                _ = try await dispatcher.dispatch(alias: "fixture_integer_read", argumentsJSON: #"{"count":9223372036854775807}"#,
                    providerCallID: "native-original-bytes", runID: f.run, step: 0, session: f.session,
                    catalog: host.catalog(for: f.session.context), limits: .init())
                try require(await host.received == Int64.max, "Direct canonical integer was changed or rejected")
            }),
            ("revoke during captured context rejects cached write receipt", {
                let f = try await GatedFixture.make()
                let original = try await f.call()
                await f.host.gateContext()
                let duplicate = Task { try await f.call() }
                await f.host.waitUntilContextIsSuspended()
                await f.dispatcher.invalidate(f.session)
                await f.host.releaseCapturedContext()
                try await rejects(.staleContext) { _ = try await duplicate.value }
                try require(await f.host.base.nativeWrites == 1, "Cached write repeated")
                try require(await f.dispatcher.receipts(for: f.session) == [original], "Original receipt lost after revoke")
            }),
            ("revoke during post-execute context blocks delivery and retains committed or uncertain receipt", {
                for mode in [SyntheticFixtureHost.Mode.complete, .uncertainAfterDispatch] {
                    let f = try await GatedFixture.make()
                    await f.host.base.setMode(mode)
                    await f.host.gateContext(after: 2)
                    let execution = Task { try await f.call() }
                    await f.host.waitUntilContextIsSuspended()
                    let beforeRevoke = await f.dispatcher.receipts(for: f.session)
                    try require(beforeRevoke.count == 1, "Receipt was not recorded before post-effect context")
                    try require(beforeRevoke[0].context == f.session.context, "Receipt retargeted")
                    try require(beforeRevoke[0].effectState == (mode == .complete ? .confirmedCommitted : .uncertain), "Effect certainty changed")
                    await f.dispatcher.invalidate(f.session)
                    await f.host.releaseCapturedContext()
                    try await rejects(.staleContext) { _ = try await execution.value }
                    try require(await f.dispatcher.receipts(for: f.session) == beforeRevoke, "Receipt lost on stale delivery")
                    try await rejects(.staleContext) { _ = try await f.call() }
                    try require(await f.host.base.nativeWrites == 1, "Revoked uncertain operation retried")
                }
            }),
            ("revoke during initial open context forbids host navigation", {
                let f = try await GatedFixture.make()
                await f.host.gateContext()
                let navigation = Task { try await f.dispatcher.open(f.destination, session: f.session) }
                await f.host.waitUntilContextIsSuspended()
                await f.dispatcher.invalidate(f.session)
                await f.host.releaseCapturedContext()
                try await rejects(.staleContext) { _ = try await navigation.value }
                try require(await f.host.openCalls == 0, "Host open dispatched after revoke")
            }),
            ("revoke during post-open context suppresses scripted exact-target acknowledgement", {
                let f = try await GatedFixture.make()
                await f.host.gateContext(after: 2)
                let navigation = Task { try await f.dispatcher.open(f.destination, session: f.session) }
                await f.host.waitUntilContextIsSuspended()
                try require(await f.host.openCalls == 1, "Scripted open not reached")
                await f.dispatcher.invalidate(f.session)
                await f.host.releaseCapturedContext()
                try await rejects(.staleContext) { _ = try await navigation.value }
                try require(await f.host.openCalls == 1, "Open repeated after revoke")
            }),
            ("revoke during progress context suppresses stale progress and preserves receipt", {
                let f = try await GatedFixture.make(forwardProgress: true)
                let log = ProgressLog()
                await f.host.gateContext(after: 2)
                let execution = Task { try await f.call(progress: { await log.record($0) }) }
                await f.host.waitUntilContextIsSuspended()
                await f.dispatcher.invalidate(f.session)
                await f.host.releaseCapturedContext()
                try await rejects(.staleContext) { _ = try await execution.value }
                try require(await log.values.isEmpty, "Stale progress delivered")
                try require(await f.host.base.cancellations == 1, "In-flight host cancellation missing")
                try require(await f.dispatcher.receipts(for: f.session).count == 1, "Post-cancel receipt lost")
                try require(await f.host.base.nativeWrites == 1, "Progress race repeated write")
            }),
            ("task cancellation during cached context rejects old receipt", {
                let f = try await GatedFixture.make()
                let original = try await f.call()
                await f.host.gateContext()
                let duplicate = Task { try await f.call() }
                await f.host.waitUntilContextIsSuspended()
                duplicate.cancel()
                await f.host.releaseCapturedContext()
                try await rejectsCancellation { _ = try await duplicate.value }
                try require(await f.dispatcher.receipts(for: f.session) == [original], "Cancelled cache lost receipt")
                try require(await f.host.base.nativeWrites == 1, "Cancelled duplicate repeated write")
            }),
            ("task cancellation during post-execute context retains effect without delivery", {
                let f = try await GatedFixture.make()
                await f.host.gateContext(after: 2)
                let execution = Task { try await f.call() }
                await f.host.waitUntilContextIsSuspended()
                execution.cancel()
                await f.host.releaseCapturedContext()
                try await rejectsCancellation { _ = try await execution.value }
                let receipts = await f.dispatcher.receipts(for: f.session)
                try require(receipts.count == 1 && receipts[0].effectState == .confirmedCommitted, "Cancellation erased effect")
                try require(await f.host.base.nativeWrites == 1, "Cancellation repeated effect")
            }),
            ("task cancellation during initial open context forbids host navigation", {
                let f = try await GatedFixture.make()
                await f.host.gateContext()
                let navigation = Task { try await f.dispatcher.open(f.destination, session: f.session) }
                await f.host.waitUntilContextIsSuspended()
                navigation.cancel()
                await f.host.releaseCapturedContext()
                try await rejectsCancellation { _ = try await navigation.value }
                try require(await f.host.openCalls == 0, "Cancelled open dispatched")
            }),
            ("task cancellation during post-open context suppresses scripted acknowledgement", {
                let f = try await GatedFixture.make()
                await f.host.gateContext(after: 2)
                let navigation = Task { try await f.dispatcher.open(f.destination, session: f.session) }
                await f.host.waitUntilContextIsSuspended()
                navigation.cancel()
                await f.host.releaseCapturedContext()
                try await rejectsCancellation { _ = try await navigation.value }
                try require(await f.host.openCalls == 1, "Cancelled open repeated")
            }),
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
