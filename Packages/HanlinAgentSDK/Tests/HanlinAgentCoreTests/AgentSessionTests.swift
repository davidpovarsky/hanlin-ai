import AISDKProvider
import Foundation
import HanlinAgentCore
import HanlinChatCore
import HanlinHostContracts
import HanlinPersistenceAdapters
import HanlinPlatformContracts
import HanlinSDKTestFixtures
import Testing

private actor StepCounter {
    private var index = 0
    func next() -> Int { index += 1; return index }
}
private struct ToolScriptModel: LanguageModelV3 {
    let provider = "fixture"
    let modelId = "scripted"
    let counter = StepCounter()
    let toolName: String
    let arguments: String
    init(toolName: String = "fixture_create", arguments: String = #"{"text":"test"}"#) {
        self.toolName = toolName; self.arguments = arguments
    }
    func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult { throw HanlinHostError.unsupportedProviderCapability }
    func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let index = await counter.next()
        return .init(stream: AsyncThrowingStream { c in
            if index == 1 {
                c.yield(.toolCall(.init(toolCallId: "opaque/fixture-call", toolName: toolName, input: arguments)))
                c.yield(.finish(finishReason: .init(unified: .toolCalls), usage: .init(), providerMetadata: nil))
            } else {
                c.yield(.textStart(id: "answer", providerMetadata: nil))
                c.yield(.textDelta(id: "answer", delta: "Fixture completed", providerMetadata: nil))
                c.yield(.textEnd(id: "answer", providerMetadata: nil))
                c.yield(.finish(finishReason: .init(unified: .stop), usage: .init(), providerMetadata: nil))
            }
            c.finish()
        }, request: nil, response: nil)
    }
}

private enum SessionFixtureError: Error { case unsupportedNavigation }

private actor GeneralMutationFixtureHost: HanlinHostIntegration {
    nonisolated let apiVersion = HanlinAPIVersion(major: 1, minor: 1)
    let base: SyntheticFixtureHost
    init(context: HanlinHostContext) { base = SyntheticFixtureHost(context: context) }
    func context(for session: HanlinHostSession) async -> HanlinHostContext { await base.context(for: session) }
    func catalog(for context: HanlinHostContext) async throws -> HanlinHostCatalog {
        let original = try await base.catalog(for: context)
        return .init(apiVersion: apiVersion, revision: original.revision, context: context, tools: original.tools.map {
            .init(route: $0.route, descriptor: $0.descriptor,
                writeGuarantee: $0.writeGuarantee == .readOnly ? .readOnly : .hostManagedMutation)
        })
    }
    func execute(_ invocation: HanlinHostInvocation, progress: @escaping @Sendable (HanlinToolProgressEvent) async -> Void) async throws -> HanlinHostExecutionResult {
        guard invocation.writeGuarantee == .hostManagedMutation else { throw HanlinHostError.invalidArguments }
        return try await base.execute(invocation, progress: progress)
    }
    func cancel(_ id: HanlinToolInvocationID) async { await base.cancel(id) }
    func open(_ destination: HanlinHostDestination) async throws -> HanlinHostNavigationResult { try await base.open(destination) }
}

private actor MutationProgress {
    var values: [HanlinToolProgressEvent] = []
    func receive(_ event: HanlinToolProgressEvent) { values.append(event) }
}

private struct StructuredScriptModel: LanguageModelV3 {
    let provider = "fixture"
    let modelId = "structured"
    let parts: [LanguageModelV3StreamPart]
    func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult { throw HanlinHostError.unsupportedProviderCapability }
    func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        .init(stream: AsyncThrowingStream { c in
            for part in parts { c.yield(part) }
            c.yield(.finish(finishReason: .init(unified: .stop), usage: .init(), providerMetadata: nil))
            c.finish()
        })
    }
}

private func structuredDescriptor() -> HanlinAISDKProviderDescriptor {
    .init(kind: .openAICompatible, modelID: "structured", baseURL: URL(filePath: "/fixture"),
          structuredPartChannel: HanlinChatStructuredPart.channel)
}

private actor InteractionFixtureHost: HanlinHostIntegration, HanlinHostInteractionSource {
    nonisolated let apiVersion = HanlinAPIVersion(major: 1, minor: 0)
    let base: SyntheticFixtureHost
    private(set) var prepared = 0
    private var shouldHold = false
    private var held: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    init(context: HanlinHostContext) { base = SyntheticFixtureHost(context: context) }
    func context(for session: HanlinHostSession) async -> HanlinHostContext { await base.context(for: session) }
    func catalog(for context: HanlinHostContext) async throws -> HanlinHostCatalog { try await base.catalog(for: context) }
    func execute(_ invocation: HanlinHostInvocation, progress: @escaping @Sendable (HanlinToolProgressEvent) async -> Void) async throws -> HanlinHostExecutionResult {
        try await base.execute(invocation, progress: progress)
    }
    func cancel(_ id: HanlinToolInvocationID) async { await base.cancel(id) }
    func open(_ destination: HanlinHostDestination) async throws -> HanlinHostNavigationResult { try await base.open(destination) }
    func prepareInteraction(_ request: HanlinHostInteractionRequest) async throws -> HanlinHostInteractionContinuation {
        guard request.actionID == "fixture_submit", request.origin.session.context == (await base.context(for: request.origin.session)) else { throw HanlinHostError.denied }
        prepared += 1
        if shouldHold { await withCheckedContinuation { held = $0; waiter?.resume(); waiter = nil } }
        return .init(userMessage: "The user submitted the synthetic form.")
    }
    func holdPreparation() { shouldHold = true }
    func waitUntilHeld() async { if held == nil { await withCheckedContinuation { waiter = $0 } } }
    func release() { held?.resume(); held = nil }
}

private actor ExactNumericHost: HanlinHostIntegration {
    nonisolated let apiVersion = HanlinAPIVersion(major: 1, minor: 0)
    let original: HanlinHostContext
    private(set) var arguments: [HanlinJSONValue] = []
    init(context: HanlinHostContext) { original = context }
    func context(for session: HanlinHostSession) -> HanlinHostContext { original }
    func catalog(for context: HanlinHostContext) throws -> HanlinHostCatalog {
        guard context == original else { throw HanlinHostError.staleContext }
        let base = try SyntheticFixtureHost.tool("fixture_numeric", risk: .read, guarantee: .readOnly)
        let schema = try HanlinJSONSchemaDocument.decodeCanonicalJSON(Data(#"{"type":"object"}"#.utf8), defaultDialect: .draft2020_12)
        let descriptor = HanlinToolDescriptor(logicalID: base.descriptor.logicalID, descriptorRevision: base.descriptor.descriptorRevision,
            owner: .system, title: base.descriptor.title, summary: base.descriptor.summary, inputSchema: schema, risk: .read, presentation: .init())
        return .init(revision: .init(1), context: context, tools: [.init(route: base.route, descriptor: descriptor, writeGuarantee: .readOnly)])
    }
    func execute(_ invocation: HanlinHostInvocation, progress: @escaping @Sendable (HanlinToolProgressEvent) async -> Void) throws -> HanlinHostExecutionResult {
        guard invocation.session.context == original, invocation.request.aliasUsed == "fixture_numeric",
              case .object = invocation.request.arguments else { throw HanlinHostError.invalidArguments }
        arguments.append(invocation.request.arguments)
        return .init(result: .init(invocationID: invocation.request.id, logicalToolID: invocation.request.logicalToolID,
            outcome: .completed([.text("Synthetic numeric read")]), completedAt: .now), effectState: .confirmedNoEffect, context: original)
    }
    // Reads complete synchronously on this actor; cancellation cannot undo a completed read.
    func cancel(_ invocation: HanlinToolInvocationID) async {}
    func open(_ destination: HanlinHostDestination) async throws -> HanlinHostNavigationResult {
        throw SessionFixtureError.unsupportedNavigation
    }
}

private actor AssociationStore: HanlinConversationStore {
    let base = HanlinInMemoryConversationStore()
    let rejectAssociation: Bool
    init(rejectAssociation: Bool = false) { self.rejectAssociation = rejectAssociation }
    func load(_ id: UUID, namespace: HanlinConversationNamespace) async throws -> HanlinConversationRecord? {
        try await base.load(id, namespace: namespace)
    }
    func save(_ record: HanlinConversationRecord, replacing revision: UInt64?) async throws {
        if rejectAssociation, record.entries.contains(where: {
            if case .presentationReference(_, let reference) = $0.payload { return reference == "fixture.origin.v1:original" }
            return false
        }) { throw HanlinHostError.storeConflict }
        try await base.save(record, replacing: revision)
    }
    func delete(_ id: UUID, namespace: HanlinConversationNamespace, replacing revision: UInt64) async throws {
        try await base.delete(id, namespace: namespace, replacing: revision)
    }
}

@MainActor private final class AssociationHost: HanlinHostIntegration {
    nonisolated let apiVersion = HanlinAPIVersion(major: 1, minor: 0)
    let base: SyntheticFixtureHost
    let store: AssociationStore
    weak var session: HanlinAgentSession?
    var externalEffects = 0
    var reservedResultID: UUID?
    var rejectedForgedIdentity = false
    init(context: HanlinHostContext, store: AssociationStore) { base = .init(context: context); self.store = store }
    func context(for session: HanlinHostSession) async -> HanlinHostContext { await base.context(for: session) }
    func catalog(for context: HanlinHostContext) async throws -> HanlinHostCatalog { try await base.catalog(for: context) }
    func execute(_ invocation: HanlinHostInvocation, progress: @escaping @Sendable (HanlinToolProgressEvent) async -> Void) async throws -> HanlinHostExecutionResult {
        let session = try #require(session)
        let forged = HanlinHostInvocation(request: invocation.request, session: invocation.session,
            runID: invocation.runID, step: invocation.step, providerCallID: invocation.providerCallID,
            writeGuarantee: invocation.writeGuarantee, originalArgumentsJSON: invocation.originalArgumentsJSON, resultID: UUID())
        do { try await session.associateHostInvocation(forged, opaqueReference: "fixture.origin.v1:forged") }
        catch { rejectedForgedIdentity = error as? HanlinHostError == .resultMismatch }
        try await session.associateHostInvocation(invocation, opaqueReference: "fixture.origin.v1:original")
        try await session.associateHostInvocation(invocation, opaqueReference: "fixture.origin.v1:original")
        let loaded = try await store.load(invocation.session.conversationID, namespace: invocation.session.context.namespace)
        let saved = try #require(loaded)
        let references = saved.entries.compactMap { entry -> String? in
            if case .presentationReference(_, let reference) = entry.payload { return reference }; return nil
        }
        #expect(references == ["fixture.origin.v1:original"])
        #expect(saved.entries.contains { if case .toolCall = $0.payload { return true }; return false })
        reservedResultID = invocation.resultID
        externalEffects += 1
        return try await base.execute(invocation, progress: progress)
    }
    func cancel(_ id: HanlinToolInvocationID) async { await base.cancel(id) }
    func open(_ destination: HanlinHostDestination) async throws -> HanlinHostNavigationResult { try await base.open(destination) }
}

private actor SessionEvents {
    private(set) var texts = 0
    private var sawStep = false
    private var stepWaiter: CheckedContinuation<Void, Never>?
    private var sawTool = false
    private var toolWaiter: CheckedContinuation<Void, Never>?
    func record(_ event: HanlinAISDKStreamEvent) {
        if case .textDelta = event { texts += 1 }
        if case .stepStarted = event { sawStep = true; stepWaiter?.resume(); stepWaiter = nil }
        if case .toolCall = event { sawTool = true; toolWaiter?.resume(); toolWaiter = nil }
    }
    func waitForStep() async {
        if sawStep { return }
        await withCheckedContinuation { stepWaiter = $0 }
    }
    func waitForTool() async {
        if sawTool { return }
        await withCheckedContinuation { toolWaiter = $0 }
    }
}

private actor ExecutionGateHost: HanlinHostIntegration {
    nonisolated let apiVersion = HanlinAPIVersion(major: 1, minor: 0)
    let contexts: GatedContextHost
    private var held: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    init(context: HanlinHostContext) { contexts = GatedContextHost(context: context) }
    func context(for session: HanlinHostSession) async throws -> HanlinHostContext { try await contexts.context(for: session) }
    func catalog(for context: HanlinHostContext) async throws -> HanlinHostCatalog { try await contexts.catalog(for: context) }
    func execute(_ invocation: HanlinHostInvocation, progress: @escaping @Sendable (HanlinToolProgressEvent) async -> Void) async throws -> HanlinHostExecutionResult {
        await withCheckedContinuation { held = $0; waiter?.resume(); waiter = nil }
        return try await contexts.execute(invocation, progress: progress)
    }
    // Record cancellation without releasing either gate: the test explicitly releases
    // captured work so Session revocation must suppress delivery even for a late host.
    func cancel(_ invocation: HanlinToolInvocationID) async { await contexts.cancel(invocation) }
    func open(_ destination: HanlinHostDestination) async throws -> HanlinHostNavigationResult {
        throw SessionFixtureError.unsupportedNavigation
    }
    func waitForExecution() async {
        if held != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func releaseExecution() { held?.resume(); held = nil }
}

private actor ReceiptGateStore: HanlinConversationStore {
    let base = HanlinInMemoryConversationStore()
    let contexts: GatedContextHost
    private var armed = true
    init(contexts: GatedContextHost) { self.contexts = contexts }
    func load(_ id: UUID, namespace: HanlinConversationNamespace) async throws -> HanlinConversationRecord? { await base.load(id, namespace: namespace) }
    func save(_ record: HanlinConversationRecord, replacing revision: UInt64?) async throws {
        try await base.save(record, replacing: revision)
        if armed, case .toolResult = record.entries.last?.payload {
            armed = false
            await contexts.gateContext()
        }
    }
    func delete(_ id: UUID, namespace: HanlinConversationNamespace, replacing revision: UInt64) async throws { try await base.delete(id, namespace: namespace, replacing: revision) }
}

private actor ControlledTextSource {
    private var continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation?
    private var installedWaiter: CheckedContinuation<Void, Never>?
    func install() -> LanguageModelV3StreamResult {
        let pair = AsyncThrowingStream<LanguageModelV3StreamPart, Error>.makeStream()
        continuation = pair.continuation
        installedWaiter?.resume(); installedWaiter = nil
        return .init(stream: pair.stream)
    }
    func waitUntilInstalled() async {
        if continuation != nil { return }
        await withCheckedContinuation { installedWaiter = $0 }
    }
    func emitText() {
        continuation?.yield(.textStart(id: "held", providerMetadata: nil))
        continuation?.yield(.textDelta(id: "held", delta: "must not be delivered", providerMetadata: nil))
        continuation?.yield(.textEnd(id: "held", providerMetadata: nil))
    }
    func finish() {
        continuation?.yield(.finish(finishReason: .init(unified: .stop), usage: .init(), providerMetadata: nil))
        continuation?.finish()
    }
}

private struct ControlledTextModel: LanguageModelV3 {
    let provider = "fixture"
    let modelId = "controlled"
    let source: ControlledTextSource
    func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult { throw HanlinHostError.unsupportedProviderCapability }
    func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult { await source.install() }
}

@Suite struct AgentSessionTests {
    @Test func generalMutationDuplicateAndChangedArgumentsCannotRedispatch() async throws {
        let ns = try HanlinConversationNamespace(app: "fixture", account: "a", workspace: "w", space: "s")
        let context = HanlinHostContext(namespace: ns, sceneID: UUID(), generation: UUID())
        let session = HanlinHostSession(conversationID: UUID(), context: context)
        let host = GeneralMutationFixtureHost(context: context)
        let dispatcher = HanlinHostDispatcher(host: host), run = UUID()
        let catalog = try await host.catalog(for: context)
        let first = try await dispatcher.dispatchEvent(alias: "fixture_create", argumentsJSON: #"{"text":"one"}"#,
            providerCallID: "original-provider-id", runID: run, step: 3, session: session, catalog: catalog, limits: .init())
        let replay = try await dispatcher.dispatchEvent(alias: "fixture_create", argumentsJSON: #"{"text":"one"}"#,
            providerCallID: "original-provider-id", runID: run, step: 3, session: session, catalog: catalog, limits: .init())
        #expect(first.call == replay.call && first.resultID == replay.resultID)
        #expect(first.result.effectState == .confirmedCommitted)
        do {
            _ = try await dispatcher.dispatch(alias: "fixture_create", argumentsJSON: #"{"text":"changed"}"#,
                providerCallID: "original-provider-id", runID: run, step: 3, session: session, catalog: catalog, limits: .init())
            Issue.record("Changed input was redispatched")
        } catch { #expect(error as? HanlinHostError == .idempotencyConflict) }
        do {
            _ = try await dispatcher.dispatch(alias: "fixture_create", argumentsJSON: #"{"text":"one"}"#,
                providerCallID: "conditional", runID: run, step: 3, session: session, catalog: catalog,
                expectedRevision: "invented-cas", limits: .init())
            Issue.record("Host-managed mutation pretended to offer CAS")
        } catch { #expect(error as? HanlinHostError == .unsupportedConditionalWrite) }
        #expect(await host.base.executions == 1)
        #expect(await host.base.nativeWrites == 1)
    }

    @Test func generalMutationPolicyDenialAndPostDispatchUncertaintyStayDistinct() async throws {
        for mode in [SyntheticFixtureHost.Mode.deny, .uncertainAfterDispatch] {
            let ns = try HanlinConversationNamespace(app: "fixture", account: "a", workspace: "w", space: "s")
            let context = HanlinHostContext(namespace: ns, sceneID: UUID(), generation: UUID())
            let session = HanlinHostSession(conversationID: UUID(), context: context)
            let host = GeneralMutationFixtureHost(context: context)
            await host.base.setMode(mode)
            let dispatcher = HanlinHostDispatcher(host: host), run = UUID()
            let catalog = try await host.catalog(for: context)
            let result = try await dispatcher.dispatch(alias: "fixture_create", argumentsJSON: #"{"text":"one"}"#,
                providerCallID: "same", runID: run, step: 0, session: session, catalog: catalog, limits: .init())
            _ = try await dispatcher.dispatch(alias: "fixture_create", argumentsJSON: #"{"text":"one"}"#,
                providerCallID: "same", runID: run, step: 0, session: session, catalog: catalog, limits: .init())
            #expect(await host.base.executions == 1)
            if mode == .deny { #expect(result.effectState == .notDispatched); #expect(await host.base.nativeWrites == 0) }
            else { #expect(result.effectState == .uncertain); #expect(await host.base.nativeWrites == 1); #expect(result.reconciliationReference != nil) }
        }
    }

    @Test func generalMutationProgressAndReceiptKeepOriginalContextAndStep() async throws {
        let ns = try HanlinConversationNamespace(app: "fixture", account: "a", workspace: "w", space: "s")
        let context = HanlinHostContext(namespace: ns, sceneID: UUID(), generation: UUID())
        let session = HanlinHostSession(conversationID: UUID(), context: context)
        let host = GeneralMutationFixtureHost(context: context)
        let dispatcher = HanlinHostDispatcher(host: host), run = UUID(), events = MutationProgress()
        let catalog = try await host.catalog(for: context)
        let result = try await dispatcher.dispatchEvent(alias: "fixture_create", argumentsJSON: #"{"text":"one"}"#,
            providerCallID: "original", runID: run, step: 7, session: session,
            catalog: catalog, limits: .init(), progress: { await events.receive($0) })
        #expect(result.call.session == session && result.call.runID == run && result.call.step == 7)
        #expect(result.call.providerCallID == "original")
        let progress = await events.values
        #expect(progress.count == 1 && progress.first?.invocationID == result.call.invocationID)
        #expect(progress.first?.sequence == 2)
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func nativeSchemaPartsPersistBeforeDeliveryWithOriginalSessionIdentity() async throws {
        let ns = try HanlinConversationNamespace(app: "fixture", account: "a", workspace: "w", space: "s")
        let context = HanlinHostContext(namespace: ns, sceneID: UUID(), generation: UUID())
        let identity = HanlinHostSession(conversationID: UUID(), context: context)
        let host = SyntheticFixtureHost(context: context)
        let messageID = UUID()
        let wire = #"{"parts":[{"part":"text","kind":"text","text":"Canonical answer","a2uiJSON":null}]}"#
        let config = HanlinChatModelConfiguration(modelID: HanlinNativeStructuredResponse.modelID, company: "OPENAI",
            apiType: "openai-responses", endpoint: "https://api.openai.com/v1/responses", credential: "fixture-only")
        // Session/persistence contract proof. The Core tests separately execute the real HTTP adapter.
        let engine = HanlinAISDKAgentEngine(configuration: config, model: .v3(StructuredScriptModel(parts: [
            .textStart(id: "fixture", providerMetadata: nil), .textDelta(id: "fixture", delta: wire, providerMetadata: nil),
            .textEnd(id: "fixture", providerMetadata: nil)
        ])))
        let store = HanlinInMemoryConversationStore()
        let session = HanlinAgentSession(identity: identity, host: host, engine: engine, store: store)
        let source = try await session.stream(messages: [.init(role: .user, text: "Fixture")],
            modelReference: .init(provider: "openai-responses", modelID: config.modelID),
            structuredResponse: .init(messageID: messageID, validateCompleteParts: { _ in }),
            presentationReference: "fixture-original-row-binding")
        var observed = 0
        for try await event in source {
            #expect(event.session == identity)
            if case .textDelta = event.event { Issue.record("Schema JSON persisted as prose") }
            if case .structuredPart(let part) = event.event {
                observed += 1
                let saved = try #require(await store.load(identity.conversationID, namespace: ns))
                let replay = try saved.structuredEntries(runID: event.runID, messageID: messageID)
                #expect(saved.entries.contains {
                    if case .presentationReference(1, "fixture-original-row-binding") = $0.payload { return $0.runID == event.runID }
                    return false
                })
                #expect(replay.contains {
                    if case .structuredPart(let savedPart, let savedContext) = $0.payload {
                        return savedPart == part && savedContext == context
                    }
                    return false
                })
                #expect(part.payload == .textDelta("Canonical answer"))
            }
        }
        #expect(observed == 1)
        #expect(await host.executions == 0)
    }

    /// Requires the separately frozen producer and Tomer's temporary/final pin window.
    /// NOT_RUN on Windows: do not infer this chain from either isolated proof.
    @Test(.timeLimit(.minutes(1))) @MainActor
    func originalNumericInputSurvivesCanonicalEngineSessionAndScopedReceipt() async throws {
        for json in [#"{"n":9007199254740991}"#, #"{"n":9007199254740992}"#, #"{"n":9007199254740993}"#,
                     #"{"n":9223372036854775807}"#, #"{"n":-9223372036854775808}"#, #"{"n":1.0}"#,
                     #"{"n":1e0}"#, #"{"a":[{"n":9007199254740993},0.5,1e0],"s":"123"}"#] {
            let namespace = try HanlinConversationNamespace(app: "fixture", account: "a", workspace: "w", space: "s")
            let context = HanlinHostContext(namespace: namespace, sceneID: UUID(), generation: UUID())
            let identity = HanlinHostSession(conversationID: UUID(), context: context)
            let host = ExactNumericHost(context: context)
            let store = HanlinInMemoryConversationStore()
            let config = HanlinChatModelConfiguration(modelID: "fixture", endpoint: URL(filePath: "/fixture"), apiKey: "")
            let engine = HanlinAISDKAgentEngine(configuration: config, model: .v3(ToolScriptModel(toolName: "fixture_numeric", arguments: json)))
            let session = HanlinAgentSession(identity: identity, host: host, engine: engine, store: store)
            let stream = try await session.stream(messages: [.init(role: .user, text: "Synthetic read")], modelReference: .init(provider: "fixture", modelID: "scripted"))
            for try await _ in stream {}
            let expected = try HanlinJSONValue.decodeCanonicalJSON(Data(json.utf8))
            #expect(await host.arguments == [expected])
            let receipts = await session.dispatcher.receipts(for: identity)
            #expect(receipts.count == 1 && receipts.first?.effectState == .confirmedNoEffect)
            let saved = try #require(await store.load(identity.conversationID, namespace: namespace))
            #expect(saved.entries.contains { if case .toolCall("opaque/fixture-call", "fixture_numeric", .null) = $0.payload { return true }; return false })
        }
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func unsupportedOriginalNumericInputNeverCreatesPendingOrHostEffect() async throws {
        for json in [#"{"n":18446744073709551615}"#, #"{"n":0.10000000000000000001}"#, #"{"n":9007199254740993.0}"#] {
            let namespace = try HanlinConversationNamespace(app: "fixture", account: "a", workspace: "w", space: "s")
            let context = HanlinHostContext(namespace: namespace, sceneID: UUID(), generation: UUID())
            let identity = HanlinHostSession(conversationID: UUID(), context: context)
            let host = ExactNumericHost(context: context)
            let store = HanlinInMemoryConversationStore()
            let config = HanlinChatModelConfiguration(modelID: "fixture", endpoint: URL(filePath: "/fixture"), apiKey: "")
            let engine = HanlinAISDKAgentEngine(configuration: config, model: .v3(ToolScriptModel(toolName: "fixture_numeric", arguments: json)))
            let session = HanlinAgentSession(identity: identity, host: host, engine: engine, store: store)
            let stream = try await session.stream(messages: [.init(role: .user, text: "Synthetic read")], modelReference: .init(provider: "fixture", modelID: "scripted"), maxSteps: 2)
            do { for try await _ in stream {} } catch { /* Model/tool failure is acceptable; effects are not. */ }
            #expect(await host.arguments.isEmpty)
            #expect(await session.dispatcher.receipts(for: identity).isEmpty)
            let saved = try #require(await store.load(identity.conversationID, namespace: namespace))
            #expect(!saved.entries.contains { if case .toolCall = $0.payload { return true }; return false })
        }
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func invalidationDuringPostReceiptContextSuppressesCallbackButKeepsReceipt() async throws {
        let namespace = try HanlinConversationNamespace(app: "fixture", account: "a", workspace: "w", space: "s")
        let context = HanlinHostContext(namespace: namespace, sceneID: UUID(), generation: UUID())
        let identity = HanlinHostSession(conversationID: UUID(), context: context)
        let host = ExecutionGateHost(context: context)
        let contexts = await host.contexts
        let store = ReceiptGateStore(contexts: contexts)
        let events = SessionEvents()
        let config = HanlinChatModelConfiguration(modelID: "fixture", endpoint: URL(filePath: "/fixture"), apiKey: "")
        let engine = HanlinAISDKAgentEngine(configuration: config, model: .v3(ToolScriptModel()))
        let session = HanlinAgentSession(identity: identity, host: host, engine: engine, store: store)
        var callbacks = 0
        session.onHostResult = { _ in callbacks += 1 }
        let stream = try await session.stream(messages: [.init(role: .user, text: "test")], modelReference: .init(provider: "fixture", modelID: "scripted"))
        let consumer = Task { @MainActor in
            do { for try await item in stream { await events.record(item.event) } }
            catch { /* Revoked after native completion. */ }
        }
        await host.waitForExecution()
        await events.waitForTool()
        await host.releaseExecution()
        await contexts.waitUntilContextIsSuspended()
        await session.invalidate()
        await contexts.releaseCapturedContext()
        await consumer.value
        #expect(callbacks == 0)
        let receipts = await session.dispatcher.receipts(for: identity)
        #expect(receipts.count == 1 && receipts.first?.effectState == .confirmedCommitted)
        let saved = try #require(await store.load(identity.conversationID, namespace: namespace))
        #expect(saved.entries.contains { if case .toolResult(_, let receipt) = $0.payload { return receipt.effectState == .confirmedCommitted }; return false })
    }
    /// Real Session + canonical engine test. Source-only on Windows until Apple
    /// compilation runs; portable dispatcher/helper tests do not stand in for it.
    @Test(.timeLimit(.minutes(1))) @MainActor
    func invalidationDuringCapturedEventContextSuppressesDelivery() async throws {
        let namespace = try HanlinConversationNamespace(app: "fixture", account: "a", workspace: "w", space: "s")
        let context = HanlinHostContext(namespace: namespace, sceneID: UUID(), generation: UUID())
        let identity = HanlinHostSession(conversationID: UUID(), context: context)
        let host = GatedContextHost(context: context)
        let source = ControlledTextSource()
        let events = SessionEvents()
        let config = HanlinChatModelConfiguration(modelID: "fixture", endpoint: URL(filePath: "/fixture"), apiKey: "")
        let engine = HanlinAISDKAgentEngine(configuration: config, model: .v3(ControlledTextModel(source: source)))
        let session = HanlinAgentSession(identity: identity, host: host, engine: engine, store: HanlinInMemoryConversationStore())
        let stream = try await session.stream(messages: [.init(role: .user, text: "test")], modelReference: .init(provider: "fixture", modelID: "controlled"))
        let consumer = Task { @MainActor in
            do { for try await item in stream { await events.record(item.event) } }
            catch { /* Revoked source terminates. */ }
        }
        await source.waitUntilInstalled()
        await events.waitForStep()
        await host.gateContext()
        await source.emitText()
        await host.waitUntilContextIsSuspended()
        await session.invalidate()
        await host.releaseCapturedContext()
        await source.finish()
        await consumer.value
        #expect(await events.texts == 0)
        #expect(await host.base.executions == 0)
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func concurrentStartIsReservedBeforeInitialContextAwait() async throws {
        let namespace = try HanlinConversationNamespace(app: "fixture", account: "a", workspace: "w", space: "s")
        let context = HanlinHostContext(namespace: namespace, sceneID: UUID(), generation: UUID())
        let identity = HanlinHostSession(conversationID: UUID(), context: context)
        let host = GatedContextHost(context: context)
        let config = HanlinChatModelConfiguration(modelID: "fixture", endpoint: URL(filePath: "/fixture"), apiKey: "")
        let engine = HanlinAISDKAgentEngine(configuration: config, model: .v3(ToolScriptModel()))
        let session = HanlinAgentSession(identity: identity, host: host, engine: engine, store: HanlinInMemoryConversationStore())
        await host.gateContext()
        let first = Task { @MainActor in
            try await session.stream(messages: [.init(role: .user, text: "first")], modelReference: .init(provider: "fixture", modelID: "scripted"))
        }
        await host.waitUntilContextIsSuspended()
        do {
            _ = try await session.stream(messages: [.init(role: .user, text: "second")], modelReference: .init(provider: "fixture", modelID: "scripted"))
            Issue.record("Concurrent start entered a reserved run")
        } catch { #expect(error as? HanlinHostError == .duplicateInvocation) }
        await session.invalidate()
        await host.releaseCapturedContext()
        do { _ = try await first.value; Issue.record("Revoked initial context was accepted") }
        catch { /* Expected cancellation/stale context. */ }
        #expect(await host.base.executions == 0)
    }

    @Test func nativeSnapshotsEmitOnlyNewSuffixAndRejectRevision() throws {
        var delta = HanlinAppleTextDelta()
        #expect(try delta.append(snapshot: "Hello") == "Hello")
        #expect(try delta.append(snapshot: "Hello world") == " world")
        #expect(try delta.append(snapshot: "Hello world") == "")
        #expect(throws: HanlinAppleProviderError.inconsistentSnapshot) { try delta.append(snapshot: "changed") }
    }

    @Test @MainActor func existingEngineRunsHostToolOnceAndPersistsCorrelation() async throws {
        let namespace = try HanlinConversationNamespace(app: "fixture", account: "a", workspace: "w", space: "s")
        let context = HanlinHostContext(namespace: namespace, sceneID: UUID(), generation: UUID())
        let identity = HanlinHostSession(conversationID: UUID(), context: context)
        let host = SyntheticFixtureHost(context: context)
        let config = HanlinChatModelConfiguration(modelID: "fixture", endpoint: URL(filePath: "/fixture"), apiKey: "")
        let engine = HanlinAISDKAgentEngine(configuration: config, model: .v3(ToolScriptModel()))
        let store = HanlinInMemoryConversationStore()
        let session = HanlinAgentSession(identity: identity, host: host, engine: engine, store: store)
        var callbacks: [HanlinHostResultEvent] = []
        var progress: [HanlinHostProgressEvent] = []
        session.onHostResult = { callbacks.append($0) }
        session.onHostProgress = { progress.append($0) }
        let stream = try await session.stream(messages: [.init(role: .user, text: "Create a synthetic note")], modelReference: .init(provider: "fixture", modelID: "scripted"))
        var results = 0
        var runID: UUID?
        for try await event in stream {
            #expect(event.session == identity)
            runID = event.runID
            if case .toolResult = event.event { results += 1 }
        }
        #expect(results == 1)
        #expect(await host.nativeWrites == 1)
        let callback = try #require(callbacks.first)
        #expect(callbacks.count == 1 && callback.call.session == identity && callback.call.runID == runID)
        #expect(callback.call.providerCallID == "opaque/fixture-call")
        #expect(callback.call.invocationID == callback.result.result.invocationID)
        #expect(callback.call.session.context.generation == context.generation)
        #expect(progress.count == 1 && progress.first?.call == callback.call)
        let changed = HanlinHostContext(namespace: namespace, sceneID: context.sceneID, generation: UUID())
        let staleCall = HanlinHostCallIdentity(session: .init(id: identity.id, conversationID: identity.conversationID, context: changed),
            runID: callback.call.runID, step: callback.call.step, providerCallID: callback.call.providerCallID,
            invocationID: callback.call.invocationID, logicalToolID: callback.call.logicalToolID)
        #expect(throws: HanlinHostError.resultMismatch) {
            try HanlinHostResultEvent(resultID: callback.resultID, call: staleCall, result: callback.result)
        }
        let record = try #require(await store.load(identity.conversationID, namespace: namespace))
        #expect(record.formatVersion == 2)
        #expect(record.entries.contains { if case .hostResultIdentity(let id, let call) = $0.payload { return id == callback.resultID && call == callback.call }; return false })
        #expect(record.entries.contains { if case .toolResult("opaque/fixture-call", _) = $0.payload { return true }; return false })
    }

    @Test @MainActor func duplicateReceiptRetainsIdentityAndNewRunSeparatesProviderCallID() async throws {
        let ns = try HanlinConversationNamespace(app: "fixture", account: "a", workspace: "w", space: "s")
        let context = HanlinHostContext(namespace: ns, sceneID: UUID(), generation: UUID())
        let session = HanlinHostSession(conversationID: UUID(), context: context)
        let host = SyntheticFixtureHost(context: context)
        let dispatcher = HanlinHostDispatcher(host: host)
        let catalog = try await host.catalog(for: context)
        let run = UUID()
        func invoke(_ run: UUID, step: Int = 0) async throws -> HanlinHostResultEvent {
            try await dispatcher.dispatchEvent(alias: "fixture_create", argumentsJSON: #"{"text":"test"}"#,
                providerCallID: "opaque/fixture-call", runID: run, step: step, session: session,
                catalog: catalog, limits: .init())
        }
        let first = try await invoke(run)
        let replay = try await invoke(run)
        #expect(first.resultID == replay.resultID && first.call == replay.call)
        #expect(await host.nativeWrites == 1)
        do { _ = try await invoke(run, step: 1); Issue.record("Call moved to a different step") }
        catch { #expect(error as? HanlinHostError == .idempotencyConflict) }
        let next = try await invoke(UUID())
        #expect(next.resultID != first.resultID && next.call.invocationID != first.call.invocationID)
        #expect(next.call.runID != first.call.runID && next.call.providerCallID == first.call.providerCallID)
        await dispatcher.invalidate(session)
        do { _ = try await invoke(run); Issue.record("Revoked receipt delivered") }
        catch { #expect(error as? HanlinHostError == .staleContext) }
        #expect(await host.nativeWrites == 2)
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func structuredChannelPreservesInterleavingAndDeduplicatesExactReplay() async throws {
        let ns = try HanlinConversationNamespace(app: "fixture", account: "a", workspace: "w", space: "s")
        let context = HanlinHostContext(namespace: ns, sceneID: UUID(), generation: UUID())
        let identity = HanlinHostSession(conversationID: UUID(), context: context)
        let messageID = UUID(), textPartID = UUID(), surfacePartID = UUID()
        let parts = try [
            HanlinChatStructuredPart(messageID: messageID, partID: textPartID, sequence: 0, payload: .textDelta("Before")),
            HanlinChatStructuredPart(messageID: messageID, partID: surfacePartID, sequence: 1,
                payload: .a2uiMessage(protocolVersion: "v0.9", json: Data(#"{"createSurface":{"surfaceId":"test"}}"#.utf8))),
            HanlinChatStructuredPart(messageID: messageID, partID: textPartID, sequence: 2, payload: .textDelta("After"))
        ]
        var source = try parts.map { LanguageModelV3StreamPart.custom(try $0.providerContent()) }
        source.insert(try .custom(parts[1].providerContent()), at: 2)
        let config = HanlinChatModelConfiguration(modelID: "fixture", endpoint: URL(filePath: "/fixture"), apiKey: "")
        let engine = HanlinAISDKAgentEngine(configuration: config, model: .v3(StructuredScriptModel(parts: source)), descriptor: structuredDescriptor())
        let session = HanlinAgentSession(identity: identity, host: SyntheticFixtureHost(context: context), engine: engine, store: HanlinInMemoryConversationStore())
        let stream = try await session.stream(messages: [.init(role: .user, text: "test")], modelReference: .init(provider: "fixture", modelID: "structured"))
        var observed: [HanlinChatStructuredPart] = []
        for try await event in stream {
            #expect(event.session == identity)
            if case .structuredPart(let part) = event.event { observed.append(part) }
        }
        #expect(observed == parts)
        let restored = try JSONDecoder().decode([HanlinChatStructuredPart].self, from: JSONEncoder().encode(observed))
        var replay = HanlinChatStructuredPartSequence()
        for part in restored { #expect(try replay.admit(part)) }
        for part in restored { #expect(try !replay.admit(part)) }
    }

    @Test func structuredChannelRejectsConflictingReplayOrderAndInvalidVersion() throws {
        let messageID = UUID(), partID = UUID()
        let part = try HanlinChatStructuredPart(messageID: messageID, partID: partID, sequence: UInt64.max, payload: .textDelta("safe"))
        let encoded = try part.providerContent()
        #expect(try HanlinChatStructuredPart.decodeProviderContent(kind: encoded.kind, metadata: encoded.providerMetadata) == part)
        var sequence = HanlinChatStructuredPartSequence()
        #expect(try sequence.admit(part))
        let conflicting = try HanlinChatStructuredPart(messageID: messageID, partID: partID, sequence: UInt64.max, payload: .textDelta("changed"))
        #expect(throws: HanlinChatStructuredPartError.conflictingReplay) { try sequence.admit(conflicting) }
        let old = try HanlinChatStructuredPart(messageID: messageID, partID: partID, sequence: 0, payload: .textDelta("old"))
        #expect(throws: HanlinChatStructuredPartError.outOfOrder) { try sequence.admit(old) }
        #expect(throws: HanlinChatStructuredPartError.invalidEnvelope) {
            try HanlinChatStructuredPart(version: 2, messageID: messageID, partID: partID, sequence: 0, payload: .textDelta("future"))
        }
        #expect(throws: HanlinChatStructuredPartError.invalidEnvelope) {
            try HanlinChatStructuredPart.decodeProviderContent(kind: HanlinChatStructuredPart.channel, metadata: nil)
        }
        #expect(try HanlinChatStructuredPart.decodeProviderContent(kind: "other", metadata: nil) == nil)
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func providerMustAdvertiseStructuredChannelAndProseCannotEnterIt() async throws {
        let part = try HanlinChatStructuredPart(messageID: UUID(), partID: UUID(), sequence: 0, payload: .textDelta("Explicit"))
        let config = HanlinChatModelConfiguration(modelID: "fixture", endpoint: URL(filePath: "/fixture"), apiKey: "")
        let unadvertised = HanlinAISDKAgentEngine(configuration: config,
            model: .v3(StructuredScriptModel(parts: [try .custom(part.providerContent())])))
        let rejected = try await unadvertised.stream(messages: [.init(role: .user, text: "test")], baseSystemPrompt: nil, tools: [], prepareStep: { .init(activeToolAliases: []) })
        do { for try await _ in rejected {}; Issue.record("Unadvertised channel was delivered") }
        catch { #expect(error as? HanlinChatStructuredPartError == .unadvertisedChannel) }
        let prose = #"```json {"createSurface":{"surfaceId":"prose"}} ```"#
        let plain = HanlinAISDKAgentEngine(configuration: config, model: .v3(StructuredScriptModel(parts: [
            .textStart(id: "text", providerMetadata: nil), .textDelta(id: "text", delta: prose, providerMetadata: nil),
            .textEnd(id: "text", providerMetadata: nil)
        ])))
        let stream = try await plain.stream(messages: [.init(role: .user, text: "test")], baseSystemPrompt: nil, tools: [], prepareStep: { .init(activeToolAliases: []) })
        var text = "", structured = 0
        for try await event in stream {
            if case .textDelta(let value) = event { text += value }
            if case .structuredPart = event { structured += 1 }
        }
        #expect(text == prose && structured == 0)
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func interruptedStructuredOutputIsDurableButCannotRestoreLiveAdmission() async throws {
        let ns = try HanlinConversationNamespace(app: "fixture", account: "a", workspace: "w", space: "s")
        let context = HanlinHostContext(namespace: ns, sceneID: UUID(), generation: UUID())
        let identity = HanlinHostSession(conversationID: UUID(), context: context)
        let host = InteractionFixtureHost(context: context)
        let part = try HanlinChatStructuredPart(messageID: UUID(), partID: UUID(), sequence: 0,
            payload: .a2uiMessage(protocolVersion: "v0.9", json: Data("{}".utf8)))
        let config = HanlinChatModelConfiguration(modelID: "fixture", endpoint: URL(filePath: "/fixture"), apiKey: "")
        let engine = HanlinAISDKAgentEngine(configuration: config, model: .v3(StructuredScriptModel(parts: [
            try .custom(part.providerContent()), .error(error: .string("Synthetic interruption"))
        ])), descriptor: structuredDescriptor())
        let store = HanlinInMemoryConversationStore()
        let session = HanlinAgentSession(identity: identity, host: host, engine: engine, store: store)
        let model = HanlinModelReference(provider: "fixture", modelID: "structured")
        let stream = try await session.stream(messages: [.init(role: .user, text: "Form")], modelReference: model)
        var original: HanlinHostInteractionOrigin?
        do {
            for try await event in stream {
                if case .structuredPart = event.event { original = .init(session: identity, runID: event.runID, messageID: part.messageID, partID: part.partID) }
            }
            Issue.record("Synthetic provider error was accepted as completion")
        } catch { /* Partial content is retained while interaction admission is revoked. */ }
        let origin = try #require(original)
        let record = try #require(await store.load(identity.conversationID, namespace: ns))
        let replay = try record.structuredEntries(runID: origin.runID, messageID: part.messageID)
        #expect(replay.count == 1)
        #expect(throws: HanlinHostError.staleContext) { try session.admitInteraction(origin) }
        #expect(await host.prepared == 0)
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func interactionAfterProducerEOFCreatesNewTurnAndReplayCannotRestoreAuthority() async throws {
        let ns = try HanlinConversationNamespace(app: "fixture", account: "a", workspace: "w", space: "s")
        let context = HanlinHostContext(namespace: ns, sceneID: UUID(), generation: UUID())
        let identity = HanlinHostSession(conversationID: UUID(), context: context)
        let host = InteractionFixtureHost(context: context)
        let part = try HanlinChatStructuredPart(messageID: UUID(), partID: UUID(), sequence: 0,
            payload: .a2uiMessage(protocolVersion: "v0.9", json: Data(#"{"createSurface":{"surfaceId":"test"}}"#.utf8)))
        let config = HanlinChatModelConfiguration(modelID: "fixture", endpoint: URL(filePath: "/fixture"), apiKey: "")
        let engine = HanlinAISDKAgentEngine(configuration: config, model: .v3(StructuredScriptModel(parts: [try .custom(part.providerContent())])), descriptor: structuredDescriptor())
        let session = HanlinAgentSession(identity: identity, host: host, engine: engine, store: HanlinInMemoryConversationStore())
        var origin: HanlinHostInteractionOrigin?
        var completed = 0
        session.onRunCompletion = { if case .completed = $0.outcome { completed += 1 } }
        let model = HanlinModelReference(provider: "fixture", modelID: "structured")
        let first = try await session.stream(messages: [.init(role: .user, text: "Form")], modelReference: model)
        for try await event in first {
            if case .structuredPart(let value) = event.event {
                origin = .init(session: event.session, runID: event.runID, messageID: value.messageID, partID: value.partID)
            }
        }
        let live = try #require(origin)
        #expect(completed == 1)
        do { _ = try await session.continueInteraction(.init(origin: live, actionID: "fixture_submit", arguments: .null), messages: [], modelReference: model); Issue.record("Model bytes alone enabled interaction") }
        catch { #expect(error as? HanlinHostError == .staleContext) }
        // Synthetic presentation admission, not proof of a real renderer/UI mount.
        try session.admitInteraction(live)
        let request = HanlinHostInteractionRequest(origin: live, actionID: "fixture_submit", arguments: .object([:]))
        let next = try await session.continueInteraction(request, messages: [], modelReference: model)
        for try await event in next {
            #expect(event.runID != live.runID && event.interactionOrigin == live && event.session == identity)
        }
        #expect(completed == 2)
        #expect(await host.prepared == 1)
        do { _ = try await session.continueInteraction(request, messages: [], modelReference: model); Issue.record("Duplicate action request repeated") }
        catch { #expect(error as? HanlinHostError == .duplicateInvocation) }
        session.revokeInteraction(live)
        do { _ = try await session.continueInteraction(.init(origin: live, actionID: "fixture_submit", arguments: .null), messages: [], modelReference: model); Issue.record("Deleted surface continued") }
        catch { #expect(error as? HanlinHostError == .staleContext) }
        let replay = try JSONDecoder().decode(HanlinHostInteractionOrigin.self, from: JSONEncoder().encode(live))
        let restored = HanlinAgentSession(identity: identity, host: host, engine: engine, store: HanlinInMemoryConversationStore())
        do { _ = try await restored.continueInteraction(.init(origin: replay, actionID: "fixture_submit", arguments: .null), messages: [], modelReference: model); Issue.record("Replay restored live admission") }
        catch { #expect(error as? HanlinHostError == .staleContext) }
        #expect(await host.prepared == 1)
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func invalidationDuringInteractionPreparationRejectsCapturedAdmission() async throws {
        let ns = try HanlinConversationNamespace(app: "fixture", account: "a", workspace: "w", space: "s")
        let context = HanlinHostContext(namespace: ns, sceneID: UUID(), generation: UUID())
        let identity = HanlinHostSession(conversationID: UUID(), context: context)
        let host = InteractionFixtureHost(context: context)
        let part = try HanlinChatStructuredPart(messageID: UUID(), partID: UUID(), sequence: 0,
            payload: .a2uiMessage(protocolVersion: "v0.9", json: Data("{}".utf8)))
        let config = HanlinChatModelConfiguration(modelID: "fixture", endpoint: URL(filePath: "/fixture"), apiKey: "")
        let engine = HanlinAISDKAgentEngine(configuration: config, model: .v3(StructuredScriptModel(parts: [try .custom(part.providerContent())])), descriptor: structuredDescriptor())
        let session = HanlinAgentSession(identity: identity, host: host, engine: engine, store: HanlinInMemoryConversationStore())
        let model = HanlinModelReference(provider: "fixture", modelID: "structured")
        var origin: HanlinHostInteractionOrigin?
        let first = try await session.stream(messages: [.init(role: .user, text: "Form")], modelReference: model)
        for try await event in first {
            if case .structuredPart = event.event { origin = .init(session: identity, runID: event.runID, messageID: part.messageID, partID: part.partID) }
        }
        let request = HanlinHostInteractionRequest(origin: try #require(origin), actionID: "fixture_submit", arguments: .null)
        try session.admitInteraction(request.origin)
        await host.holdPreparation()
        let continuation = Task { @MainActor in try await session.continueInteraction(request, messages: [], modelReference: model) }
        await host.waitUntilHeld()
        var invalidations = 0
        session.onSessionInvalidated = { #expect($0 == identity); invalidations += 1 }
        await session.invalidate(); await session.invalidate()
        await host.release()
        do { _ = try await continuation.value; Issue.record("Revoked captured admission created a turn") }
        catch { #expect(error as? HanlinHostError == .staleContext) }
        #expect(invalidations == 1)
        #expect(await host.prepared == 1)
    }
    @Test @MainActor func hostAssociationUsesOrderedSaveBeforeEffectAndOriginalReceiptIdentity() async throws {
        let ns = try HanlinConversationNamespace(app: "a", account: "a", workspace: "w", space: "s")
        let context = HanlinHostContext(namespace: ns, sceneID: UUID(), generation: UUID())
        let identity = HanlinHostSession(conversationID: UUID(), context: context)
        let store = AssociationStore(), host = AssociationHost(context: context, store: store)
        let config = HanlinChatModelConfiguration(modelID: "fixture", endpoint: URL(filePath: "/fixture"), apiKey: "")
        let engine = HanlinAISDKAgentEngine(configuration: config, model: .v3(ToolScriptModel()))
        let session = HanlinAgentSession(identity: identity, host: host, engine: engine, store: store)
        host.session = session
        var callback: HanlinHostResultEvent?
        session.onHostResult = { callback = $0 }
        let stream = try await session.stream(messages: [.init(role: .user, text: "Original dispatch")],
            modelReference: .init(provider: "fixture", modelID: "fixture"))
        for try await _ in stream {}
        #expect(host.externalEffects == 1 && host.rejectedForgedIdentity)
        let event = try #require(callback)
        #expect(event.resultID == host.reservedResultID && event.call.session == identity)
        let messageID = UUID()
        let origin = try session.admitHostResultInteraction(event, messageID: messageID)
        #expect(origin.session == identity && origin.runID == event.call.runID && origin.partID == event.resultID)
        let forged = try HanlinHostResultEvent(resultID: UUID(), call: event.call, result: event.result)
        do { _ = try session.admitHostResultInteraction(forged, messageID: messageID); Issue.record("Forged receipt authorized a control") }
        catch { #expect(error as? HanlinHostError == .staleContext) }

        let loaded = try await store.load(identity.conversationID, namespace: ns)
        let record = try #require(loaded)
        #expect(record.entries.contains { if case .hostResultIdentity(let id, let call) = $0.payload { return id == event.resultID && call == event.call }; return false })
        #expect(record.entries.contains { if case .toolResult(_, let result) = $0.payload { return result.result.invocationID == event.call.invocationID }; return false })
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func inlinePresentationUsesOriginalWriterAndCannotRestoreOrReuseAuthority() async throws {
        let ns = try HanlinConversationNamespace(app: "inline-fixture", account: "a", workspace: "w", space: "s")
        let context = HanlinHostContext(namespace: ns, sceneID: UUID(), generation: UUID())
        let identity = HanlinHostSession(conversationID: UUID(), context: context)
        let store = AssociationStore(), host = AssociationHost(context: context, store: store)
        let config = HanlinChatModelConfiguration(modelID: "fixture", endpoint: URL(filePath: "/fixture"), apiKey: "")
        let engine = HanlinAISDKAgentEngine(configuration: config, model: .v3(StructuredScriptModel(parts: [
            .textStart(id: "answer", providerMetadata: nil),
            .textDelta(id: "answer", delta: "A live inline block", providerMetadata: nil),
            .textEnd(id: "answer", providerMetadata: nil)
        ])))
        let session = HanlinAgentSession(identity: identity, host: host, engine: engine, store: store)
        host.session = session
        var runID: UUID?
        let stream = try await session.stream(messages: [.init(role: .user, text: "Render")],
            modelReference: .init(provider: "fixture", modelID: "fixture"))
        for try await event in stream { runID = event.runID }
        let origin = HanlinHostInteractionOrigin(session: identity, runID: try #require(runID), messageID: UUID(), partID: UUID())
        let request = HanlinHostInteractionRequest(origin: origin, actionID: "openui.query", arguments: .null)
        do { _ = try await session.executePresentationTool(request, alias: "fixture_create", argumentsJSON: #"{"text":"test"}"#); Issue.record("Unadmitted inline content executed") }
        catch { #expect(error as? HanlinHostError == .staleContext) }
        try session.admitInlinePresentation(origin)
        let admitted = HanlinHostInteractionRequest(origin: origin, actionID: "openui.query", arguments: .null)
        var receipt: HanlinHostResultEvent?
        session.onHostResult = { receipt = $0 }
        var started: HanlinAgentEvent?
        _ = try await session.executePresentationTool(admitted, alias: "fixture_create", argumentsJSON: #"{"text":"test"}"#,
            onStarted: { event in
                #expect(host.externalEffects == 0)
                #expect(event.session == identity && event.interactionOrigin == origin)
                started = event
            })
        #expect(host.externalEffects == 1 && host.rejectedForgedIdentity)
        let event = try #require(receipt)
        #expect(event.call.providerCallID == admitted.requestID.uuidString)
        #expect(event.call.runID == started?.runID)
        #expect(event.call.session == identity && event.call.runID != origin.runID)
        let saved = try #require(await store.load(identity.conversationID, namespace: ns))
        #expect(saved.entries.contains { if case .hostResultIdentity(let id, let call) = $0.payload { return id == event.resultID && call == event.call }; return false })
        do { _ = try await session.executePresentationTool(admitted, alias: "fixture_create", argumentsJSON: #"{"text":"test"}"#); Issue.record("Repeated query request executed twice") }
        catch { #expect(error as? HanlinHostError == .duplicateInvocation) }
        let restored = HanlinAgentSession(identity: identity, host: host, engine: engine, store: store)
        #expect(throws: HanlinHostError.staleContext) { try restored.admitInlinePresentation(origin) }
        await session.invalidate()
        #expect(throws: HanlinHostError.staleContext) { try session.admitInlinePresentation(origin) }
        #expect(host.externalEffects == 1 && !session.isRunning)
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func inlinePresentationFailedDurableAssociationPreventsHostEffect() async throws {
        let ns = try HanlinConversationNamespace(app: "inline-fixture", account: "a", workspace: "w", space: "s")
        let context = HanlinHostContext(namespace: ns, sceneID: UUID(), generation: UUID())
        let identity = HanlinHostSession(conversationID: UUID(), context: context)
        let store = AssociationStore(rejectAssociation: true), host = AssociationHost(context: context, store: store)
        let config = HanlinChatModelConfiguration(modelID: "fixture", endpoint: URL(filePath: "/fixture"), apiKey: "")
        let engine = HanlinAISDKAgentEngine(configuration: config, model: .v3(StructuredScriptModel(parts: [
            .textStart(id: "answer", providerMetadata: nil),
            .textDelta(id: "answer", delta: "A live inline block", providerMetadata: nil),
            .textEnd(id: "answer", providerMetadata: nil)
        ])))
        let session = HanlinAgentSession(identity: identity, host: host, engine: engine, store: store)
        host.session = session
        var runID: UUID?
        let stream = try await session.stream(messages: [.init(role: .user, text: "Render")],
            modelReference: .init(provider: "fixture", modelID: "fixture"))
        for try await event in stream { runID = event.runID }
        let origin = HanlinHostInteractionOrigin(session: identity, runID: try #require(runID), messageID: UUID(), partID: UUID())
        try session.admitInlinePresentation(origin)
        do {
            _ = try await session.executePresentationTool(.init(origin: origin, actionID: "openui.query", arguments: .null),
                alias: "fixture_create", argumentsJSON: #"{"text":"test"}"#)
            Issue.record("Failed durable association was accepted")
        } catch { /* Original writer prevents the external effect. */ }
        #expect(host.externalEffects == 0 && !session.isRunning)
    }

    @Test @MainActor func failedAssociationSaveNeverStartsExternalEffect() async throws {
        let ns = try HanlinConversationNamespace(app: "a", account: "a", workspace: "w", space: "s")
        let context = HanlinHostContext(namespace: ns, sceneID: UUID(), generation: UUID())
        let identity = HanlinHostSession(conversationID: UUID(), context: context)
        let store = AssociationStore(rejectAssociation: true), host = AssociationHost(context: context, store: store)
        let config = HanlinChatModelConfiguration(modelID: "fixture", endpoint: URL(filePath: "/fixture"), apiKey: "")
        let engine = HanlinAISDKAgentEngine(configuration: config, model: .v3(ToolScriptModel()))
        let session = HanlinAgentSession(identity: identity, host: host, engine: engine, store: store)
        host.session = session
        var callbacks = 0
        session.onHostResult = { _ in callbacks += 1 }
        do {
            let stream = try await session.stream(messages: [.init(role: .user, text: "Do not dispatch after failed save")],
                modelReference: .init(provider: "fixture", modelID: "fixture"))
            for try await _ in stream {}
            Issue.record("Failed association save was reported successful")
        } catch { /* Original writer fails closed; no external effect and no persisted-result callback. */ }
        #expect(host.externalEffects == 0 && callbacks == 0)
        let loaded = try await store.load(identity.conversationID, namespace: ns)
        let record = try #require(loaded)
        #expect(!record.entries.contains { if case .presentationReference = $0.payload { return true }; return false })
    }

}
