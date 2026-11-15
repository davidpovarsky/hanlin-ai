import AISDKProvider
import Foundation
import HanlinAgentCore
import HanlinChatCore
import HanlinHostContracts
import HanlinPersistenceAdapters
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
    func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult { throw HanlinHostError.unsupportedProviderCapability }
    func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let index = await counter.next()
        return .init(stream: AsyncThrowingStream { c in
            if index == 1 {
                c.yield(.toolCall(.init(toolCallId: "opaque/fixture-call", toolName: "fixture_create", input: #"{"text":"test"}"#)))
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

@Suite struct AgentSessionTests {
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
        let stream = try await session.stream(messages: [.init(role: .user, text: "Create a synthetic note")], modelReference: .init(provider: "fixture", modelID: "scripted"))
        var results = 0
        for try await event in stream { if case .toolResult = event.event { results += 1 } }
        #expect(results == 1)
        #expect(await host.nativeWrites == 1)
        let record = try #require(await store.load(identity.conversationID, namespace: namespace))
        #expect(record.entries.contains { if case .toolResult("opaque/fixture-call", _) = $0.payload { return true }; return false })
    }
}
