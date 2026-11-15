#if HANLIN_A2UI_POC
import A2UICore
import AISDKProvider
import Foundation
import HanlinAgentCore
import HanlinChatCore
import HanlinHostContracts
import HanlinPersistenceAdapters
import HanlinPlatformContracts
import Observation
import Testing
@testable import AI_Hanlin

@MainActor
private final class AppPresentationFixture {
    let reference: HanlinAppAgentRowReference
    let session: HanlinAgentSession
    let consumer: HanlinA2UIAppPresentation
    let persistence: HanlinInMemoryConversationStore
    let host: PresentationHost
    let completions: AsyncStream<HanlinAgentRunCompletion>
    let text: String

    init(leading: String = "Before", trailing: String = "After") throws {
        let row = UUID(), part = UUID()
        reference = .init(rowID: row, uiRunID: UUID(), messageID: row)
        text = leading + trailing
        let namespace = try HanlinConversationNamespace(app: "app-consumer-proof", account: "a", workspace: "w", space: "s")
        let identity = HanlinHostSession(conversationID: UUID(), context: .init(namespace: namespace, sceneID: UUID(), generation: UUID()))
        let persistence = HanlinInMemoryConversationStore()
        self.persistence = persistence
        let host = PresentationHost(identity.context)
        self.host = host
        let consumer = HanlinA2UIAppPresentation()
        self.consumer = consumer
        let url = try #require(Bundle.module.url(forResource: "form", withExtension: "jsonl", subdirectory: "A2UIFixtures"))
        let frames = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        var parts: [HanlinChatStructuredPart] = []
        if !leading.isEmpty { parts.append(try .init(messageID: row, partID: UUID(), sequence: 0, payload: .textDelta(leading))) }
        for json in frames {
            parts.append(try .init(messageID: row, partID: part, sequence: UInt64(parts.count),
                payload: .a2uiMessage(protocolVersion: "1.0", json: Data(json.utf8))))
        }
        if !trailing.isEmpty {
            parts.append(try .init(messageID: row, partID: UUID(), sequence: UInt64(parts.count), payload: .textDelta(trailing)))
        }
        let requiredConsumer: any HanlinAppAgentPresentationConsumer = consumer
        try requiredConsumer.validateCompleteParts(parts) // Pure callback needs no installed live Session.
        let engine = HanlinAISDKAgentEngine(configuration: .init(modelID: "fixture", endpoint: URL(filePath: "/fixture"), apiKey: ""),
            model: .v3(PresentationModel(parts: try parts.map { .custom(try $0.providerContent()) })),
            descriptor: .init(kind: .openAICompatible, modelID: "structured", baseURL: URL(filePath: "/fixture"),
                              structuredPartChannel: HanlinChatStructuredPart.channel))
        let session = HanlinAgentSession(identity: identity, host: host, engine: engine, store: persistence)
        self.session = session
        let pair = AsyncStream<HanlinAgentRunCompletion>.makeStream()
        completions = pair.stream
        consumer.installed(session: session)
        session.onRunCompletion = { value in consumer.completed(value); pair.continuation.yield(value) }
        session.onSessionInvalidated = { consumer.invalidated($0) }
    }

    func binding(_ event: HanlinAgentEvent) -> HanlinAppAgentRowBinding {
        .init(reference: reference, session: event.session, canonicalRunID: event.runID)
    }

    func bufferedEvents() async throws -> (HanlinAgentRunCompletion, [HanlinAgentEvent]) {
        let stream = try await session.stream(messages: [.init(role: .user, text: "Synthetic app form")],
                                              modelReference: .init(provider: "fixture", modelID: "structured"))
        var completion = completions.makeAsyncIterator()
        let end = try #require(await completion.next())
        var events: [HanlinAgentEvent] = []
        for try await event in stream { events.append(event) }
        return (end, events)
    }

    func run() async throws -> [HanlinAgentEvent] {
        let (end, events) = try await bufferedEvents()
        for event in events { try consumer.receive(event, binding: binding(event)) }
        consumer.producerStreamDrained(runID: end.runID)
        return events
    }

    func surface() throws -> HanlinA2UIResultProjection {
        let message = try #require(consumer.projection(uiRunID: reference.uiRunID, rowID: reference.rowID, text: text))
        let part = try #require(message.parts.first { if case .surface = $0.content { return true }; return false })
        return try #require(message.surface(for: part))
    }

    func button(_ surface: HanlinA2UIResultProjection) throws -> Node {
        var pending = [try #require(surface.surface("form-a")?.rootNode)]
        while let node = pending.popLast() {
            if node.id == "submit" { return node }
            pending.append(contentsOf: node.allChildNodes)
        }
        throw HanlinHostError.invalidRecord
    }
}

@Suite(.serialized) @MainActor
struct HanlinA2UIAppPresentationTests {
    @Test(.timeLimit(.minutes(1)))
    func originalRowAndUIRunMapToCanonicalSurfaceWithoutTextInference() async throws {
        let f = try AppPresentationFixture(leading: "", trailing: "")
        let events = try await f.run()
        let first = try #require(events.first)
        #expect(first.runID != f.reference.uiRunID)
        #expect(f.consumer.hasStructuredContent(uiRunID: f.reference.uiRunID, rowID: f.reference.rowID, text: ""))
        #expect(f.consumer.projection(uiRunID: first.runID, rowID: f.reference.rowID, text: "") == nil)
        #expect(f.consumer.projection(uiRunID: UUID(), rowID: f.reference.rowID, text: "") == nil)
        #expect(f.consumer.projection(uiRunID: f.reference.uiRunID, rowID: UUID(), text: "") == nil)
        await f.session.invalidate()
        let whitespace = try AppPresentationFixture(leading: "  Before\n", trailing: "\nAfter  ")
        _ = try await whitespace.run()
        #expect(whitespace.consumer.projection(uiRunID: whitespace.reference.uiRunID,
            rowID: whitespace.reference.rowID, text: whitespace.text) != nil)
        #expect(whitespace.consumer.projection(uiRunID: whitespace.reference.uiRunID,
            rowID: whitespace.reference.rowID, text: whitespace.text.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
        await whitespace.session.invalidate()
    }

    @Test(.timeLimit(.minutes(1)))
    func foreignAndAmbiguousBindingsCannotRetargetAnExistingRow() async throws {
        let f = try AppPresentationFixture()
        let events = try await f.run()
        let event = try #require(events.first { if case .structuredPart = $0.event { return true }; return false })
        let correct = f.binding(event)
        let wrongRun = HanlinAppAgentRowBinding(reference: correct.reference, session: correct.session, canonicalRunID: UUID())
        #expect(throws: HanlinA2UIAppPresentation.BindingError.mismatch) { try f.consumer.receive(event, binding: wrongRun) }
        let wrongUI = HanlinAppAgentRowBinding(reference: .init(rowID: correct.reference.rowID, uiRunID: UUID(), messageID: correct.reference.messageID),
                                              session: correct.session, canonicalRunID: correct.canonicalRunID)
        #expect(throws: HanlinA2UIAppPresentation.BindingError.ambiguous) { try f.consumer.receive(event, binding: wrongUI) }
        let wrongMessage = HanlinAppAgentRowBinding(reference: .init(rowID: correct.reference.rowID, uiRunID: correct.reference.uiRunID, messageID: UUID()),
                                                   session: correct.session, canonicalRunID: correct.canonicalRunID)
        #expect(throws: HanlinA2UIAppPresentation.BindingError.mismatch) { try f.consumer.receive(event, binding: wrongMessage) }
        let foreign = HanlinHostSession(conversationID: correct.session.conversationID, context: correct.session.context)
        #expect(throws: HanlinA2UIAppPresentation.BindingError.mismatch) {
            try f.consumer.receive(event, binding: .init(reference: correct.reference, session: foreign, canonicalRunID: correct.canonicalRunID))
        }
        #expect(try f.surface().isReceivingFinished)
        await f.session.invalidate()
    }

    @Test(.timeLimit(.minutes(1)))
    func realRendererActionQueuesOriginalBindingAndRevokesBeforeAsyncContinuation() async throws {
        let f = try AppPresentationFixture()
        let events = try await f.run()
        let surface = try f.surface()
        let changed = AsyncStream<Void>.makeStream()
        withObservationTracking { _ = f.consumer.pendingAction?.request.requestID }
            onChange: { changed.continuation.yield(()) }
        let submit = try #require(try f.button(surface).action(for: "action", userActivation: true))
        submit()
        var changes = changed.stream.makeAsyncIterator()
        _ = try #require(await changes.next())
        let action = try #require(f.consumer.takePendingAction())
        #expect(f.consumer.isCurrent(action) && action.key == surface.key)
        #expect(action.binding.reference == f.reference && action.binding.canonicalRunID == events.first?.runID)
        #expect(action.request.origin.session == f.session.identity && action.request.origin.messageID == f.reference.rowID)
        f.consumer.invalidated(f.session.identity) // The owner revokes UI authority before awaiting Session cleanup.
        #expect(!f.consumer.isCurrent(action))
        do {
            _ = try await f.session.continueInteraction(action.request, messages: [], modelReference: .init(provider: "fixture", modelID: "structured"))
            Issue.record("Revoked original action entered host preparation")
        } catch { #expect(error as? HanlinHostError == .staleContext) }
        #expect(await f.host.prepared == 0)
        await f.session.invalidate()
    }

    @Test(.timeLimit(.minutes(1)))
    func canonicalHistoryKeepsOriginalDisplayBindingWithoutRestoringAuthority() async throws {
        let f = try AppPresentationFixture()
        let events = try await f.run()
        let first = try #require(events.first)
        let record = try #require(await f.persistence.load(f.session.identity.conversationID, namespace: f.session.identity.context.namespace))
        let history = HanlinA2UIAppPresentation()
        try history.replay(record, bindings: [f.binding(first)])
        let message = try #require(history.projection(uiRunID: f.reference.uiRunID, rowID: f.reference.rowID, text: f.text))
        let surface = try #require(message.parts.compactMap { message.surface(for: $0) }.first)
        #expect(surface.isReadOnly && history.takePendingAction() == nil)
        let ambiguous = HanlinAppAgentRowBinding(reference: .init(rowID: f.reference.rowID, uiRunID: UUID(), messageID: f.reference.messageID),
                                                session: first.session, canonicalRunID: first.runID)
        #expect(throws: HanlinA2UIAppPresentation.BindingError.ambiguous) {
            try history.replay(record, bindings: [f.binding(first), ambiguous])
        }
        #expect(history.projection(uiRunID: f.reference.uiRunID, rowID: f.reference.rowID, text: f.text) != nil)
        #expect(await f.host.prepared == 0)
        await f.session.invalidate()
    }

    @Test(.timeLimit(.minutes(1)))
    func sourceReplacementIsObservedOutsideViewBody() async throws {
        let f = try AppPresentationFixture()
        let (end, events) = try await f.bufferedEvents()
        let structured = events.filter { if case .structuredPart = $0.event { return true }; return false }
        let before = try #require(structured.first)
        try f.consumer.receive(before, binding: f.binding(before))
        let changed = AsyncStream<Void>.makeStream()
        withObservationTracking {
            _ = f.consumer.projection(uiRunID: f.reference.uiRunID, rowID: f.reference.rowID, text: "Before")
        } onChange: { changed.continuation.yield(()) }
        let next = try #require(structured.dropFirst().first)
        try f.consumer.receive(next, binding: f.binding(next))
        var changes = changed.stream.makeAsyncIterator()
        _ = try #require(await changes.next())
        for event in structured.dropFirst(2) { try f.consumer.receive(event, binding: f.binding(event)) }
        f.consumer.producerStreamDrained(runID: end.runID)
        #expect(try f.surface().isReceivingFinished)
        await f.session.invalidate()
    }
}
#endif
