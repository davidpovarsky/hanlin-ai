import Foundation
import HanlinChatCore
import SwiftData
import Testing
@testable import AI_Hanlin

// MARK: - Controllable Gate for Conformance Testing

private actor ProductionGate {
    static let shared = ProductionGate()
    private var toolStartedContinuation: CheckedContinuation<Void, Never>?
    private var gateContinuation: CheckedContinuation<Void, Never>?

    func reset() {
        toolStartedContinuation = nil
        gateContinuation = nil
    }

    func waitForToolStarted() async {
        await withCheckedContinuation { cont in
            toolStartedContinuation = cont
        }
    }

    func recordToolStarted() {
        let started = toolStartedContinuation
        toolStartedContinuation = nil
        started?.resume()
    }

    func waitForGate() async {
        await withCheckedContinuation { cont in
            gateContinuation = cont
        }
    }

    func releaseGate() {
        let cont = gateContinuation
        gateContinuation = nil
        cont?.resume()
    }
}

private final class ProductionDelayedTool: NativeTool, @unchecked Sendable {
    let name = "production_delayed_tool"

    static func reset() async {
        await ProductionGate.shared.reset()
    }

    static func waitForToolStarted() async {
        await ProductionGate.shared.waitForToolStarted()
    }

    static func releaseGate() async {
        await ProductionGate.shared.releaseGate()
    }

    var catalogEntry: NativeToolCatalogEntry {
        .init(
            name: name,
            title: "Production Delayed Tool",
            summary: "Gate-controlled delay for production conformance testing",
            categories: ["test"],
            keywords: ["delayed"],
            examples: [],
            systemImage: "clock",
            presentationProfile: .generic(toolName: name)
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Waits on a gate before completing.",
            parameters: NativeToolSchema.object(properties: [:])
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        await ProductionGate.shared.recordToolStarted()
        await ProductionGate.shared.waitForGate()
        return NativeToolResult(
            modelText: "production_delayed_tool_finished",
            userText: "Delayed tool finished",
            outcome: .succeeded
        )
    }
}

// MARK: - Production Path Conformance Test Suite (Section 14)

@MainActor
@Suite("Production Provider Conformance Tests (APIManager Integration)", .serialized)
struct ProductionProviderConformanceTests {

    private struct ConversationResult {
        var answer: String
        var events: [AgentEvent]
        var requests: [Data]
        var diagnostics: AgentDiagnosticsSession
    }

    private func runProductionConversation(
        responses: [Data],
        validators: [Int: ProductionConformanceURLProtocol.RequestValidator] = [:],
        modelName: String = "conformance-model",
        preResponseHook: (@Sendable (Int) async -> Void)? = nil
    ) async throws -> (result: ConversationResult, manager: APIManager) {
        ProductionConformanceURLProtocol.configure(
            responses: responses,
            validators: validators,
            preResponseHook: preResponseHook
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProductionConformanceURLProtocol.self]

        let container = try ProductionConformanceFixtures.makeContainer()
        let context = container.mainContext
        context.insert(AllModels(
            name: modelName,
            displayName: "Conformance Model",
            position: 0,
            company: "CONFORMANCE",
            supportsTextGen: true,
            supportsToolUse: true
        ))
        context.insert(APIKeys(
            name: "Conformance",
            company: "CONFORMANCE",
            key: ProductionConformanceFixtures.secretAPIKey,
            requestURL: ProductionConformanceFixtures.endpointURL,
            apiType: .openAI
        ))
        try context.save()

        let catalog = NativeToolCatalog.shared
        catalog.ensureBuiltinsRegistered()

        let manager = APIManager(
            context: context,
            chatEngineFactory: { HanlinChatEngine(sessionConfiguration: configuration) }
        )

        let stream = try await manager.sendStreamRequest(
            messages: [RequestMessage(
                role: "user",
                text: "Run conformance conversation.",
                modelName: modelName,
                modelDisplayName: "Conformance Model"
            )],
            modelName: modelName,
            groupID: UUID(),
            runID: UUID(),
            ifSearch: false,
            ifKnowledge: false,
            ifToolUse: true,
            assistantToolScope: .nativeOnly,
            ifThink: false,
            ifAudio: false,
            ifPlanning: false,
            thinkingLength: 0,
            isObservation: false,
            temperature: 0,
            topP: 1,
            maxTokens: 1024,
            canvasData: CanvasData(),
            selectedURLs: nil,
            selectedPromptsContent: nil,
            systemMessage: "Conformance test.",
            selectedImageSize: "1024x1024",
            imageReversePrompt: ""
        )

        var answer = ""
        var events: [AgentEvent] = []
        for try await item in stream {
            answer += item.content ?? ""
            events.append(contentsOf: item.agentEvents)
        }

        let diagnostics = try #require(await manager.diagnosticsSnapshot())
        return (
            result: ConversationResult(
                answer: answer,
                events: events,
                requests: ProductionConformanceURLProtocol.allBodies(),
                diagnostics: diagnostics
            ),
            manager: manager
        )
    }

    // MARK: - P01: Production Skill Activation + Local Python

    @Test("P01: Production Skill activation loads skill and executes local Python in one turn")
    func testP01SkillActivationLocalPython() async throws {
        let responses = [
            ProductionConformanceFixtures.sseToolCall(id: "call-load-1", name: "load_skill", arguments: ["skill_id": "code"]),
            ProductionConformanceFixtures.sseToolCall(id: "call-py-2", name: "execute_local_python_code", arguments: ["source": "print(6 * 7)"]),
            ProductionConformanceFixtures.sseFinalAnswer("42 / LOCAL_PYTHON_COMPLETE")
        ]

        let validators: [Int: ProductionConformanceURLProtocol.RequestValidator] = [
            0: { _, req, body in
                let bodyStr = String(decoding: body, as: UTF8.self)
                #expect(bodyStr.contains("load_skill"))
                #expect(!bodyStr.contains("execute_local_python_code"))
            },
            1: { _, req, body in
                let bodyStr = String(decoding: body, as: UTF8.self)
                #expect(bodyStr.contains("execute_local_python_code"))
                #expect(bodyStr.contains("call-load-1"))
            },
            2: { _, req, body in
                let bodyStr = String(decoding: body, as: UTF8.self)
                #expect(bodyStr.contains("call-py-2"))
                #expect(bodyStr.contains("42"))
            }
        ]

        let (res, _) = try await runProductionConversation(responses: responses, validators: validators)
        #expect(res.answer.contains("42"))
        #expect(res.answer.contains("LOCAL_PYTHON_COMPLETE"))
        #expect(res.diagnostics.status == "completed")
        #expect(res.diagnostics.efficiency.toolCallCount == 2)
    }

    // MARK: - P02: Failure Recovery

    @Test("P02: Non-fatal tool failure recovers and completes in same turn")
    func testP02FailureRecovery() async throws {
        let responses = [
            ProductionConformanceFixtures.sseToolCall(id: "call-bad-1", name: "execute_shell_command", arguments: ["program": "nonexistent_binary_xyz"]),
            ProductionConformanceFixtures.sseToolCall(id: "call-good-2", name: "quick_calculate", arguments: ["expression": "10 + 20"]),
            ProductionConformanceFixtures.sseFinalAnswer("RECOVERED_30")
        ]

        let (res, _) = try await runProductionConversation(responses: responses)
        #expect(res.answer.contains("RECOVERED_30"))
        #expect(res.diagnostics.status == "completed")
        #expect(res.diagnostics.efficiency.failedToolCount == 1)
        #expect(res.diagnostics.efficiency.succeededToolCount == 1)
    }

    // MARK: - P03: 5-Step Sequential Tools

    @Test("P03: 5-step sequential production tool chain")
    func testP03FiveStepSequentialTools() async throws {
        let responses = [
            ProductionConformanceFixtures.sseToolCall(id: "c-1", name: "quick_calculate", arguments: ["expression": "1 + 1"]),
            ProductionConformanceFixtures.sseToolCall(id: "c-2", name: "quick_calculate", arguments: ["expression": "2 + 2"]),
            ProductionConformanceFixtures.sseToolCall(id: "c-3", name: "quick_calculate", arguments: ["expression": "4 + 4"]),
            ProductionConformanceFixtures.sseToolCall(id: "c-4", name: "quick_calculate", arguments: ["expression": "8 + 8"]),
            ProductionConformanceFixtures.sseToolCall(id: "c-5", name: "quick_calculate", arguments: ["expression": "16 + 16"]),
            ProductionConformanceFixtures.sseFinalAnswer("CHAIN_COMPLETE_32")
        ]

        let (res, _) = try await runProductionConversation(responses: responses)
        #expect(res.answer.contains("CHAIN_COMPLETE_32"))
        #expect(res.diagnostics.efficiency.succeededToolCount == 5)
        #expect(res.requests.count == 6)
    }

    // MARK: - P04: Parallel Tools

    @Test("P04: Parallel tools in single model step through production loop")
    func testP04ParallelTools() async throws {
        let responses = [
            ProductionConformanceFixtures.sseParallelToolCalls(calls: [
                (id: "par-1", name: "quick_calculate", arguments: ["expression": "2 * 3"]),
                (id: "par-2", name: "quick_calculate", arguments: ["expression": "4 * 5"])
            ]),
            ProductionConformanceFixtures.sseFinalAnswer("PARALLEL_DONE_6_20")
        ]

        let (res, _) = try await runProductionConversation(responses: responses)
        #expect(res.answer.contains("PARALLEL_DONE_6_20"))
        #expect(res.diagnostics.efficiency.toolCallCount == 2)
        #expect(res.diagnostics.efficiency.succeededToolCount == 2)
    }

    // MARK: - P06: 20-Step Production Loop

    @Test("P06: 20-step production tool loop")
    func testP06TwentyStepProductionLoop() async throws {
        var responses: [Data] = []
        for i in 0..<19 {
            responses.append(ProductionConformanceFixtures.sseToolCall(
                id: "c20-\(i)",
                name: "quick_calculate",
                arguments: ["expression": "\(i) + 1"]
            ))
        }
        responses.append(ProductionConformanceFixtures.sseFinalAnswer("20_STEPS_PRODUCTION_COMPLETE"))

        let (res, _) = try await runProductionConversation(responses: responses)
        #expect(res.answer.contains("20_STEPS_PRODUCTION_COMPLETE"))
        #expect(res.diagnostics.efficiency.succeededToolCount == 19)
        #expect(res.requests.count == 20)
    }

    // MARK: - P07: Provider Abrupt Close Failure

    @Test("P07: Provider abrupt close failure surfaces error without completing")
    func testP07AbruptCloseFailure() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProductionConformanceURLProtocol.self]
        ProductionConformanceURLProtocol.configure(responses: [])
        ProductionConformanceURLProtocol.injectErrorForNextRound(URLError(.networkConnectionLost))

        let container = try ProductionConformanceFixtures.makeContainer()
        let context = container.mainContext
        context.insert(AllModels(name: "m1", displayName: "M1", position: 0, company: "TEST", supportsTextGen: true, supportsToolUse: true))
        context.insert(APIKeys(name: "K1", company: "TEST", key: "key", requestURL: ProductionConformanceFixtures.endpointURL, apiType: .openAI))
        try context.save()

        let manager = APIManager(
            context: context,
            chatEngineFactory: { HanlinChatEngine(sessionConfiguration: configuration) }
        )

        var didThrow = false
        do {
            let stream = try await manager.sendStreamRequest(
                messages: [RequestMessage(role: "user", text: "Hi", modelName: "m1", modelDisplayName: "M1")],
                modelName: "m1",
                groupID: UUID(),
                runID: UUID(),
                ifSearch: false,
                ifKnowledge: false,
                ifToolUse: true,
                assistantToolScope: .nativeOnly,
                ifThink: false,
                ifAudio: false,
                ifPlanning: false,
                thinkingLength: 0,
                isObservation: false,
                temperature: 0,
                topP: 1,
                maxTokens: 1024,
                canvasData: CanvasData(),
                selectedURLs: nil,
                selectedPromptsContent: nil,
                systemMessage: "",
                selectedImageSize: "1024x1024",
                imageReversePrompt: ""
            )
            for try await _ in stream {}
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }

    // MARK: - P08: Provider Finish-Only / Other Failure Characterization

    @Test("P08: Provider HTTP 200 with finish_reason='other' and 0 content is characterized")
    func testP08FinishOtherNoContent() async throws {
        let responses = [
            ProductionConformanceFixtures.sseFinishOnly(finishReason: "other")
        ]

        let (res, _) = try await runProductionConversation(responses: responses)
        #expect(res.answer.isEmpty, "Characterization finding: 0 content was produced.")
        #expect(res.diagnostics.status == "completed" || res.diagnostics.status == "failed")
    }

    // MARK: - P09 & P10: Cancellation During Running Tool

    @Test("P10: Cancellation during running tool cancels run and suppresses late output")
    func testP10CancelRunningTool() async throws {
        await ProductionDelayedTool.reset()
        let delayedTool = ProductionDelayedTool()
        if NativeToolCatalog.shared.entry(named: delayedTool.name) == nil {
            NativeToolCatalog.shared.register(delayedTool)
        }
        if let entry = NativeToolCatalog.shared.entry(named: delayedTool.name) {
            NativeToolCatalog.shared.setEnabled(true, for: entry)
        }

        let responses = [
            ProductionConformanceFixtures.sseToolCall(id: "del-1", name: delayedTool.name, arguments: [:]),
            ProductionConformanceFixtures.sseFinalAnswer("LATE_FORBIDDEN_TEXT")
        ]
        ProductionConformanceURLProtocol.configure(responses: responses)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProductionConformanceURLProtocol.self]

        let container = try ProductionConformanceFixtures.makeContainer()
        let context = container.mainContext
        context.insert(AllModels(name: "m-del", displayName: "MDel", position: 0, company: "TEST", supportsTextGen: true, supportsToolUse: true))
        context.insert(APIKeys(name: "KDel", company: "TEST", key: "key", requestURL: ProductionConformanceFixtures.endpointURL, apiType: .openAI))
        try context.save()

        let manager = APIManager(
            context: context,
            chatEngineFactory: { HanlinChatEngine(sessionConfiguration: configuration) }
        )

        let runTask = Task { @MainActor () -> (String, Error?) in
            var text = ""
            do {
                let stream = try await manager.sendStreamRequest(
                    messages: [RequestMessage(role: "user", text: "Run delayed", modelName: "m-del", modelDisplayName: "MDel")],
                    modelName: "m-del",
                    groupID: UUID(),
                    runID: UUID(),
                    ifSearch: false,
                    ifKnowledge: false,
                    ifToolUse: true,
                    assistantToolScope: .nativeOnly,
                    ifThink: false,
                    ifAudio: false,
                    ifPlanning: false,
                    thinkingLength: 0,
                    isObservation: false,
                    temperature: 0,
                    topP: 1,
                    maxTokens: 1024,
                    canvasData: CanvasData(),
                    selectedURLs: nil,
                    selectedPromptsContent: nil,
                    systemMessage: "",
                    selectedImageSize: "1024x1024",
                    imageReversePrompt: ""
                )
                for try await item in stream { text += item.content ?? "" }
                return (text, nil)
            } catch {
                return (text, error)
            }
        }

        await ProductionDelayedTool.waitForToolStarted()
        manager.cancelCurrentRequest()
        await ProductionDelayedTool.releaseGate()

        let (text, _) = await runTask.value
        #expect(!text.contains("LATE_FORBIDDEN_TEXT"))
    }

    // MARK: - P11: Overlapping Run A -> B

    @Test("P11: Run B supersedes Run A on the same APIManager")
    func testP11OverlappingRunBSupercedesA() async throws {
        await ProductionDelayedTool.reset()
        let delayedTool = ProductionDelayedTool()
        if NativeToolCatalog.shared.entry(named: delayedTool.name) == nil {
            NativeToolCatalog.shared.register(delayedTool)
        }
        if let entry = NativeToolCatalog.shared.entry(named: delayedTool.name) {
            NativeToolCatalog.shared.setEnabled(true, for: entry)
        }

        ProductionConformanceURLProtocol.configure(responses: [
            ProductionConformanceFixtures.sseToolCall(id: "del-a", name: delayedTool.name, arguments: [:]),
            ProductionConformanceFixtures.sseFinalAnswer("LATE_A")
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProductionConformanceURLProtocol.self]

        let container = try ProductionConformanceFixtures.makeContainer()
        let context = container.mainContext
        context.insert(AllModels(name: "m-overlap", displayName: "MOverlap", position: 0, company: "TEST", supportsTextGen: true, supportsToolUse: true))
        context.insert(APIKeys(name: "KOverlap", company: "TEST", key: "key", requestURL: ProductionConformanceFixtures.endpointURL, apiType: .openAI))
        try context.save()

        let manager = APIManager(
            context: context,
            chatEngineFactory: { HanlinChatEngine(sessionConfiguration: configuration) }
        )

        let runAID = UUID()
        let runATask = Task { @MainActor () -> (String, Error?) in
            var text = ""
            do {
                let stream = try await manager.sendStreamRequest(
                    messages: [RequestMessage(role: "user", text: "Start A", modelName: "m-overlap", modelDisplayName: "MOverlap")],
                    modelName: "m-overlap",
                    groupID: UUID(),
                    runID: runAID,
                    ifSearch: false,
                    ifKnowledge: false,
                    ifToolUse: true,
                    assistantToolScope: .nativeOnly,
                    ifThink: false,
                    ifAudio: false,
                    ifPlanning: false,
                    thinkingLength: 0,
                    isObservation: false,
                    temperature: 0,
                    topP: 1,
                    maxTokens: 1024,
                    canvasData: CanvasData(),
                    selectedURLs: nil,
                    selectedPromptsContent: nil,
                    systemMessage: "",
                    selectedImageSize: "1024x1024",
                    imageReversePrompt: ""
                )
                for try await item in stream { text += item.content ?? "" }
                return (text, nil)
            } catch {
                return (text, error)
            }
        }

        await ProductionDelayedTool.waitForToolStarted()

        // Configure Run B responses while A is blocked on tool
        ProductionConformanceURLProtocol.configure(responses: [
            ProductionConformanceFixtures.sseToolCall(id: "b-calc", name: "quick_calculate", arguments: ["expression": "7 * 7"]),
            ProductionConformanceFixtures.sseFinalAnswer("RUN_B_FINAL_49")
        ])

        let streamB = try await manager.sendStreamRequest(
            messages: [RequestMessage(role: "user", text: "Start B", modelName: "m-overlap", modelDisplayName: "MOverlap")],
            modelName: "m-overlap",
            groupID: UUID(),
            runID: UUID(),
            ifSearch: false,
            ifKnowledge: false,
            ifToolUse: true,
            assistantToolScope: .nativeOnly,
            ifThink: false,
            ifAudio: false,
            ifPlanning: false,
            thinkingLength: 0,
            isObservation: false,
            temperature: 0,
            topP: 1,
            maxTokens: 1024,
            canvasData: CanvasData(),
            selectedURLs: nil,
            selectedPromptsContent: nil,
            systemMessage: "",
            selectedImageSize: "1024x1024",
            imageReversePrompt: ""
        )

        var runBText = ""
        for try await item in streamB { runBText += item.content ?? "" }

        #expect(runBText.contains("RUN_B_FINAL_49"))

        // Release A's gate
        await ProductionDelayedTool.releaseGate()
        let (runAText, _) = await runATask.value

        #expect(!runAText.contains("LATE_A"))
        #expect(!runBText.contains("LATE_A"))
    }

    // MARK: - P12: Long History Second User Turn

    @Test("P12: Long history second user turn preserves prior tool output")
    func testP12LongHistorySecondUserTurn() async throws {
        let responsesTurn1 = [
            ProductionConformanceFixtures.sseToolCall(id: "calc-1", name: "quick_calculate", arguments: ["expression": "100 + 200"]),
            ProductionConformanceFixtures.sseFinalAnswer("Result is 300.")
        ]

        let (res1, manager) = try await runProductionConversation(responses: responsesTurn1)
        #expect(res1.answer.contains("300"))

        // Turn 2 on same APIManager
        ProductionConformanceURLProtocol.configure(
            responses: [
                ProductionConformanceFixtures.sseFinalAnswer("I remember the result was 300.")
            ],
            validators: [
                0: { _, req, body in
                    let bodyStr = String(decoding: body, as: UTF8.self)
                    #expect(bodyStr.contains("calc-1"), "Prior tool call must be preserved in history.")
                    #expect(bodyStr.contains("300"), "Prior tool result must be preserved in history.")
                }
            ]
        )

        let stream2 = try await manager.sendStreamRequest(
            messages: [
                RequestMessage(role: "user", text: "Calculate 100 + 200", modelName: "conformance-model", modelDisplayName: "Conformance Model"),
                RequestMessage(role: "assistant", text: "Result is 300.", modelName: "conformance-model", modelDisplayName: "Conformance Model"),
                RequestMessage(role: "user", text: "What was the previous result?", modelName: "conformance-model", modelDisplayName: "Conformance Model")
            ],
            modelName: "conformance-model",
            groupID: UUID(),
            runID: UUID(),
            ifSearch: false,
            ifKnowledge: false,
            ifToolUse: true,
            assistantToolScope: .nativeOnly,
            ifThink: false,
            ifAudio: false,
            ifPlanning: false,
            thinkingLength: 0,
            isObservation: false,
            temperature: 0,
            topP: 1,
            maxTokens: 1024,
            canvasData: CanvasData(),
            selectedURLs: nil,
            selectedPromptsContent: nil,
            systemMessage: "",
            selectedImageSize: "1024x1024",
            imageReversePrompt: ""
        )

        var ans2 = ""
        for try await item in stream2 { ans2 += item.content ?? "" }
        #expect(ans2.contains("300"))
    }
}
