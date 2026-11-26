import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AISDKProviderUtils
@testable import HanlinChatCore
import Testing

@Suite("Transient host tool catalog continuation")
struct HanlinTransientToolCatalogTests {
    @Test("A catalog restored after the stop decision still delivers the original empty tool result")
    func restoredCatalogContinuesTheOriginalEmptyToolResult() async throws {
        let state = FixtureState()
        let fetch: FetchFunction = { request in
            let number = await state.request()
            let delta: [String: Any]
            let finish: String
            if number == 1 {
                delta = ["tool_calls": [["index": 0, "id": "call_owned_create", "type": "function",
                    "function": ["name": "create_page", "arguments": "{}"]]]]
                finish = "tool_calls"
            } else {
                let data = request.httpBody ?? Data()
                let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let messages = body?["messages"] as? [[String: Any]] ?? []
                let results = messages.filter { $0["role"] as? String == "tool" }
                let paired = results.count == 1 && results[0]["tool_call_id"] as? String == "call_owned_create"
                let empty = results.count == 1 && results[0]["content"] as? String == ""
                await state.observeContinuation(originalIdentity: paired, emptyResult: empty)
                delta = ["content": "ORIGINAL_EMPTY_RESULT_CONTINUED"]
                finish = "stop"
            }
            let data = try JSONSerialization.data(withJSONObject: ["id": "step_\(number)",
                "choices": [["index": 0, "delta": delta, "finish_reason": finish]]])
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                continuation.yield(Data(("data: " + String(decoding: data, as: UTF8.self) + "\n\n").utf8))
                continuation.yield(Data("data: [DONE]\n\n".utf8))
                continuation.finish()
            }
            guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"]) else {
                throw FixtureError.invalidRequest
            }
            return FetchResponse(body: .stream(stream), urlResponse: response)
        }
        let configuration = HanlinChatModelConfiguration(modelID: "gpt-4o", company: "OpenAI",
            apiType: "openai", endpoint: "https://api.openai.com/v1/chat/completions", credential: "owned-test-only")
        let engine = try HanlinAISDKAgentEngine(configuration: configuration, fetch: fetch)
        let tool = HanlinAISDKToolDefinition(name: "create_page", description: "An owned empty-result operation",
            inputSchemaData: Data(#"{"type":"object","properties":{}}"#.utf8)) { _, callID in
            guard callID == "call_owned_create" else { throw FixtureError.changedIdentity }
            await state.execute()
            return HanlinAISDKToolExecutionOutput(modelText: "", resultReference: "owned-original-receipt")
        }
        let stream = try await engine.stream(messages: [.init(role: .user, text: "Create the owned test page")],
            baseSystemPrompt: nil, tools: [tool], maxSteps: 4,
            dynamicTools: { await state.catalogIsAvailable() ? [tool] : [] },
            prepareStep: { (_: Int) async in HanlinAISDKStepPreparation(activeToolAliases: ["create_page"]) })
        var answer = "", toolResults = 0
        var stepIndices: [Int] = []
        for try await event in stream {
            if case .textDelta(let value) = event { answer += value }
            if case .toolResult(let id, _, let text, let reference, let isError) = event {
                toolResults += 1
                #expect(id == "call_owned_create")
                #expect(text.isEmpty)
                #expect(reference == "owned-original-receipt")
                #expect(!isError)
            }
            if case .stepStarted(let index, _) = event { stepIndices.append(index) }
        }
        let observations = await state.observations()
        #expect(observations.requests == 2)
        #expect(observations.executions == 1)
        #expect(observations.catalogReads >= 2)
        #expect(observations.originalIdentity)
        #expect(observations.emptyResult)
        #expect(toolResults == 1)
        #expect(stepIndices == [0, 1])
        #expect(answer == "ORIGINAL_EMPTY_RESULT_CONTINUED")
    }

    private actor FixtureState {
        private var requests = 0, executions = 0, catalogReads = 0
        private var originalIdentity = false, emptyResult = false
        func request() -> Int { requests += 1; return requests }
        func execute() { executions += 1 }
        func catalogIsAvailable() -> Bool {
            catalogReads += 1
            // The native receipt has committed, while its owned worker is still
            // draining. It finishes before the engine's second catalog read.
            return !(executions == 1 && catalogReads == 1)
        }
        func observeContinuation(originalIdentity: Bool, emptyResult: Bool) {
            self.originalIdentity = originalIdentity; self.emptyResult = emptyResult
        }
        func observations() -> (requests: Int, executions: Int, catalogReads: Int,
                                originalIdentity: Bool, emptyResult: Bool) {
            (requests, executions, catalogReads, originalIdentity, emptyResult)
        }
    }
    private enum FixtureError: Error { case invalidRequest, changedIdentity }
}
