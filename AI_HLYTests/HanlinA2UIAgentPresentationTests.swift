#if HANLIN_A2UI_POC
import A2UICore
import AISDKProvider
import BasicCatalogSwiftUI
import Foundation
import HanlinAgentCore
import HanlinChatCore
import HanlinHostContracts
import HanlinPersistenceAdapters
import HanlinPlatformContracts
import Testing
@testable import AI_Hanlin

struct PresentationModel: LanguageModelV3 {
    let provider = "fixture"
    let modelId = "structured"
    let parts: [LanguageModelV3StreamPart]
    func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        throw HanlinHostError.unsupportedProviderCapability
    }
    func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        .init(stream: AsyncThrowingStream { output in
            for part in parts { output.yield(part) }
            output.yield(.finish(finishReason: .init(unified: .stop), usage: .init(), providerMetadata: nil))
            output.finish()
        })
    }
}

/// Test-only host. It authorizes one input shape and performs no native business effects.
actor PresentationHost: HanlinHostIntegration, HanlinHostInteractionSource {
    nonisolated let apiVersion = HanlinAPIVersion(major: 1, minor: 0)
    let captured: HanlinHostContext
    private(set) var prepared = 0
    init(_ context: HanlinHostContext) { captured = context }
    func context(for session: HanlinHostSession) async -> HanlinHostContext { captured }
    func catalog(for context: HanlinHostContext) async -> HanlinHostCatalog {
        .init(revision: .init(1), context: context, tools: [])
    }
    func execute(_ invocation: HanlinHostInvocation,
                 progress: @escaping @Sendable (HanlinToolProgressEvent) async -> Void) async throws -> HanlinHostExecutionResult {
        throw HanlinHostError.denied
    }
    func cancel(_ invocation: HanlinToolInvocationID) async {}
    func open(_ destination: HanlinHostDestination) async throws -> HanlinHostNavigationResult { throw HanlinHostError.denied }
    func prepareInteraction(_ request: HanlinHostInteractionRequest) async throws -> HanlinHostInteractionContinuation {
        guard request.origin.session.context == captured, request.actionID == "submit",
              case .object = request.arguments else { throw HanlinHostError.denied }
        prepared += 1
        return .init(userMessage: "Synthetic form submission")
    }
}

@MainActor
private final class PresentationFixture {
    let messageID: UUID, surfacePartID: UUID
    let secondMessageID: UUID
    let host: PresentationHost
    let persistence: HanlinInMemoryConversationStore
    let session: HanlinAgentSession
    let adapter: HanlinA2UIAgentPresentationAdapter
    let completed: AsyncStream<HanlinAgentRunCompletion>
    let actions: AsyncStream<HanlinHostInteractionRequest>
    static let model = HanlinModelReference(provider: "fixture", modelID: "structured")

    init(malformed: Bool = false, duplicatePartIDAcrossMessages: Bool = false) throws {
        let messageID = UUID(), surfacePartID = UUID()
        self.messageID = messageID; self.surfacePartID = surfacePartID
        let secondMessageID = UUID()
        self.secondMessageID = secondMessageID
        let persistence = HanlinInMemoryConversationStore()
        self.persistence = persistence
        let namespace = try HanlinConversationNamespace(app: "consumer-proof", account: "a", workspace: "w", space: "s")
        let context = HanlinHostContext(namespace: namespace, sceneID: UUID(), generation: UUID())
        let host = PresentationHost(context)
        self.host = host
        let identity = HanlinHostSession(conversationID: UUID(), context: context)
        let url = try #require(Bundle.module.url(forResource: "form", withExtension: "jsonl", subdirectory: "A2UIFixtures"))
        let frames = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        var canonical = [try HanlinChatStructuredPart(messageID: messageID, partID: UUID(), sequence: 0, payload: .textDelta("Before"))]
        for (index, frame) in frames.enumerated() {
            canonical.append(try .init(messageID: messageID, partID: surfacePartID, sequence: UInt64(index + 1),
                payload: .a2uiMessage(protocolVersion: "1.0", json: Data((malformed && index == 0 ? "{" : frame).utf8))))
        }
        canonical.append(try .init(messageID: messageID, partID: UUID(), sequence: 4, payload: .textDelta("After")))
        if duplicatePartIDAcrossMessages {
            for (index, frame) in frames.enumerated() {
                canonical.append(try .init(messageID: secondMessageID, partID: surfacePartID, sequence: UInt64(index),
                    payload: .a2uiMessage(protocolVersion: "1.0", json: Data(frame.utf8))))
            }
        }
        let engine = HanlinAISDKAgentEngine(
            configuration: .init(modelID: "fixture", endpoint: URL(filePath: "/fixture"), apiKey: ""),
            model: .v3(PresentationModel(parts: try canonical.map { .custom(try $0.providerContent()) })),
            descriptor: .init(kind: .openAICompatible, modelID: "structured", baseURL: URL(filePath: "/fixture"),
                              structuredPartChannel: HanlinChatStructuredPart.channel))
        let session = HanlinAgentSession(identity: identity, host: host, engine: engine, store: persistence)
        self.session = session
        let completionPair = AsyncStream<HanlinAgentRunCompletion>.makeStream()
        let actionPair = AsyncStream<HanlinHostInteractionRequest>.makeStream()
        completed = completionPair.stream; actions = actionPair.stream
        let consumer = HanlinA2UIAgentPresentationAdapter(session: session) { request, _ in actionPair.continuation.yield(request) }
        adapter = consumer
        session.onRunCompletion = { value in consumer.completed(value); completionPair.continuation.yield(value) }
        session.onSessionInvalidated = { consumer.invalidate($0) }
    }

    /// Intentionally waits for the producer callback BEFORE reading its buffered stream.
    func firstRun() async throws -> (UUID, [HanlinAgentEvent]) {
        let stream = try await session.stream(messages: [.init(role: .user, text: "Synthetic form")], modelReference: Self.model)
        var iterator = completed.makeAsyncIterator()
        let end = try #require(await iterator.next())
        var events: [HanlinAgentEvent] = []
        for try await event in stream { events.append(event); _ = try adapter.receive(event) }
        let content = try #require(adapter.source?.projection(runID: end.runID, messageID: messageID, text: "BeforeAfter"))
        #expect(content.parts.count == 3)
        #expect(adapter.producerStreamDrained(runID: end.runID))
        #expect(!adapter.producerStreamDrained(runID: end.runID))
        return (end.runID, events)
    }

    func projection(_ run: UUID) throws -> HanlinA2UIResultProjection {
        let message = try #require(adapter.source?.projection(runID: run, messageID: messageID, text: "BeforeAfter"))
        return try #require(message.surface(for: message.parts[1]))
    }

    func node(_ projection: HanlinA2UIResultProjection, id: String) throws -> Node {
        var pending = [try #require(projection.surface("form-a")?.rootNode)]
        while let item = pending.popLast() {
            if item.id == id { return item }
            pending.append(contentsOf: item.allChildNodes)
        }
        throw HanlinHostError.invalidRecord
    }
}

@Suite(.serialized) @MainActor
struct HanlinA2UIAgentPresentationTests {
    @Test(.timeLimit(.minutes(1)))
    func bufferedEOFRetainsRealRendererActionAndSeparateRunIdentity() async throws {
        let f = try PresentationFixture()
        let (run, events) = try await f.firstRun()
        let projection = try f.projection(run)
        #expect(projection.isReceivingFinished && !projection.isReadOnly)
        #expect(f.adapter.isCurrent(projection.key))
        #expect(projection.key.callID == nil)
        A2UITextField(node: try f.node(projection, id: "name")).valueBinding.wrappedValue = "After EOF"
        let action = try #require(try f.node(projection, id: "submit").action(for: "action", userActivation: true))
        action()
        var actions = f.actions.makeAsyncIterator()
        let request = try #require(await actions.next())
        #expect(request.origin == .init(session: f.session.identity, runID: run, messageID: f.messageID, partID: f.surfacePartID))
        let json = try JSONSerialization.jsonObject(with: request.arguments.canonicalJSONData()) as? [String: Any]
        #expect((json?["context"] as? [String: Any])?["name"] as? String == "After EOF")
        let next = try await f.session.continueInteraction(request, messages: [], modelReference: PresentationFixture.model)
        var newRun: UUID?
        for try await event in next {
            #expect(event.runID != run && event.interactionOrigin == request.origin)
            newRun = event.runID; _ = try f.adapter.receive(event)
        }
        let second = try #require(newRun)
        #expect(f.adapter.producerStreamDrained(runID: second))
        #expect(try f.projection(second).key != projection.key)
        #expect(try f.projection(run).key == projection.key)
        #expect(await f.host.prepared == 1)
        let old = try #require(events.first { if case .structuredPart = $0.event { return true }; return false })
        #expect(throws: HanlinA2UIAgentPresentationAdapter.AdmissionError.endedRun) { try f.adapter.receive(old) }
        await f.session.invalidate()
    }

    @Test(.timeLimit(.minutes(1)))
    func canonicalRecordReplayKeepsBytesAndCannotRestoreActions() async throws {
        let f = try PresentationFixture()
        let (run, _) = try await f.firstRun()
        let saved = try #require(await f.persistence.load(f.session.identity.conversationID, namespace: f.session.identity.context.namespace))
        let restored = try JSONDecoder().decode(HanlinConversationRecord.self, from: JSONEncoder().encode(saved))
        #expect(restored == saved)
        let engine = HanlinAISDKAgentEngine(configuration: .init(modelID: "fixture", endpoint: URL(filePath: "/fixture"), apiKey: ""),
                                             model: .v3(PresentationModel(parts: [])))
        let reopened = HanlinAgentSession(identity: f.session.identity, host: f.host, engine: engine, store: f.persistence)
        let replay = HanlinA2UIAgentPresentationAdapter(session: reopened) { _, _ in Issue.record("Replay forwarded an action") }
        try replay.replay(restored, runID: run, messageID: f.messageID)
        try replay.replay(restored, runID: run, messageID: f.messageID)
        let message = try #require(replay.source?.projection(runID: run, messageID: f.messageID, text: "BeforeAfter"))
        let surface = try #require(message.surface(for: message.parts[1]))
        #expect(surface.isReadOnly && !replay.isCurrent(surface.key))
        let action = try f.node(surface, id: "submit").action(for: "action", userActivation: true)
        action?()
        let origin = HanlinHostInteractionOrigin(session: reopened.identity, runID: run, messageID: f.messageID, partID: f.surfacePartID)
        do {
            _ = try await reopened.continueInteraction(.init(origin: origin, actionID: "submit", arguments: .object([:])),
                messages: [], modelReference: PresentationFixture.model)
            Issue.record("Reopened record restored native authority")
        } catch { #expect(error as? HanlinHostError == .staleContext) }
        #expect(await f.host.prepared == 0)
        await reopened.invalidate()
        await f.session.invalidate()
    }

    @Test(.timeLimit(.minutes(1)))
    func invalidationRejectsQueuedOriginalEventsAndKeys() async throws {
        let f = try PresentationFixture()
        let (run, events) = try await f.firstRun()
        let projection = try f.projection(run)
        await f.session.invalidate()
        #expect(!f.adapter.isCurrent(projection.key) && projection.isClosed)
        let old = try #require(events.first)
        #expect(throws: HanlinA2UIAgentPresentationAdapter.AdmissionError.foreignSession) { try f.adapter.receive(old) }
        #expect(f.adapter.source?.projection(runID: run, messageID: f.messageID, text: "BeforeAfter")?.plainText == "BeforeAfter")
        #expect(await f.host.prepared == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func malformedCompletePartStaysUnavailableAndPreservesAdjacentText() async throws {
        let f = try PresentationFixture(malformed: true)
        let (run, _) = try await f.firstRun()
        let message = try #require(f.adapter.source?.projection(runID: run, messageID: f.messageID, text: "BeforeAfter"))
        guard case .unavailable = message.parts[1].content else { Issue.record("Malformed Surface revived"); return }
        #expect(message.surface(for: message.parts[1]) == nil)
        #expect(await f.host.prepared == 0)
        let saved = try #require(await f.persistence.load(f.session.identity.conversationID, namespace: f.session.identity.context.namespace))
        #expect(try saved.structuredEntries(runID: run, messageID: f.messageID).count == 5)
        await f.session.invalidate()
    }

    @Test(.timeLimit(.minutes(1)))
    func completedRunBudgetRevokesBeforeUnboundedIdentityGrowth() async throws {
        let f = try PresentationFixture()
        let (firstRun, _) = try await f.firstRun()
        let original = try f.projection(firstRun)
        // Producer completion alone must consume the budget too, even when a caller never
        // forwards structured events. Only actual Session callbacks can construct completions.
        for _ in 1..<65 {
            let stream = try await f.session.stream(messages: [.init(role: .user, text: "Synthetic budget control")],
                                                    modelReference: PresentationFixture.model)
            var done = f.completed.makeAsyncIterator()
            _ = try #require(await done.next())
            for try await _ in stream {}
        }
        #expect(original.isClosed && !f.adapter.isCurrent(original.key))
        #expect(f.adapter.source?.projection(runID: firstRun, messageID: f.messageID, text: "BeforeAfter")?.plainText == "BeforeAfter")
        #expect(await f.host.prepared == 0)
        await f.session.invalidate()
    }

    @Test(.timeLimit(.minutes(1)))
    func canonicalMessagesCanReusePartIDWithoutSharingFormState() async throws {
        let f = try PresentationFixture(duplicatePartIDAcrossMessages: true)
        let (run, _) = try await f.firstRun()
        let first = try f.projection(run)
        let secondMessage = try #require(f.adapter.source?.projection(runID: run, messageID: f.secondMessageID, text: ""))
        let second = try #require(secondMessage.surface(for: secondMessage.parts[0]))
        #expect(first.key.resultID == second.key.resultID && first.key.origin != second.key.origin)
        A2UITextField(node: try f.node(first, id: "name")).valueBinding.wrappedValue = "Only first message"
        #expect(try f.node(second, id: "greeting").string(for: "text") == "Ada")
        #expect(f.adapter.discard(first.key))
        #expect(first.isClosed && !second.isClosed && f.adapter.isCurrent(second.key))
        let oldOrigin = HanlinHostInteractionOrigin(session: f.session.identity, runID: run,
                                                   messageID: f.messageID, partID: f.surfacePartID)
        do {
            _ = try await f.session.continueInteraction(.init(origin: oldOrigin, actionID: "submit", arguments: .object([:])),
                messages: [], modelReference: PresentationFixture.model)
            Issue.record("Deleted exact message retained native admission")
        } catch { #expect(error as? HanlinHostError == .staleContext) }
        #expect(await f.host.prepared == 0)
        await f.session.invalidate()
    }
}
#endif
