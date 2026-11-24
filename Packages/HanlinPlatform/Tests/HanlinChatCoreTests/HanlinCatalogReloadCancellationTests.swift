import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AISDKProviderUtils
@testable import HanlinChatCore
import Testing

@Suite("Cancellation at a host catalog reload")
struct HanlinCatalogReloadCancellationTests {
    @Test("Cancellation during final catalog lookup cannot start another provider step")
    func cancellationDuringFinalCatalogLookupStopsBeforeAnotherProviderStep() async throws {
        let state = FixtureState()
        let fetch: FetchFunction = { request in
            let number = await state.request()
            let delta: [String: Any] = number == 1
                ? ["tool_calls": [["index": 0, "id": "call_owned_cancel", "type": "function",
                    "function": ["name": "create_page", "arguments": "{}"]]]]
                : ["content": "UNEXPECTED_CONTINUATION"]
            let data = try JSONSerialization.data(withJSONObject: ["id": "step_\(number)",
                "choices": [["index": 0, "delta": delta, "finish_reason": number == 1 ? "tool_calls" : "stop"]]])
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
            guard callID == "call_owned_cancel" else { throw FixtureError.changedIdentity }
            await state.execute()
            return HanlinAISDKToolExecutionOutput(modelText: "", resultReference: "owned-original-receipt")
        }
        let stream = try await engine.stream(messages: [.init(role: .user, text: "Create the owned test page")],
            baseSystemPrompt: nil, tools: [tool], maxSteps: 4,
            dynamicTools: {
                let read = await state.readCatalog()
                if read == 2 {
                    // This is the engine's awaited finish lookup, after the first
                    // lookup stopped the SDK. Cancel that owned task precisely at
                    // the reload boundary; no sleeps or external jobs are involved.
                    withUnsafeCurrentTask { $0?.cancel() }
                    #expect(Task.isCancelled)
                }
                return []
            },
            prepareStep: { (index: Int) async in
                await state.prepare(index)
                return HanlinAISDKStepPreparation(activeToolAliases: index == 0 ? ["create_page"] : [])
            })
        var cancelledEvent = false, caughtCancellation = false
        do {
            for try await event in stream {
                if case .cancelled = event { cancelledEvent = true }
            }
        } catch HanlinChatError.cancelled {
            caughtCancellation = true
        }
        let observations = await state.observations()
        #expect(observations.requests == 1)
        #expect(observations.executions == 1)
        #expect(observations.catalogReads == 2)
        #expect(observations.preparedSteps == [0])
        #expect(cancelledEvent)
        #expect(caughtCancellation)
    }

    private actor FixtureState {
        private var requests = 0, executions = 0, catalogReads = 0
        private var preparedSteps: [Int] = []
        func request() -> Int { requests += 1; return requests }
        func execute() { executions += 1 }
        func readCatalog() -> Int { catalogReads += 1; return catalogReads }
        func prepare(_ index: Int) { preparedSteps.append(index) }
        func observations() -> (requests: Int, executions: Int, catalogReads: Int, preparedSteps: [Int]) {
            (requests, executions, catalogReads, preparedSteps)
        }
    }
    private enum FixtureError: Error { case invalidRequest, changedIdentity }
}
