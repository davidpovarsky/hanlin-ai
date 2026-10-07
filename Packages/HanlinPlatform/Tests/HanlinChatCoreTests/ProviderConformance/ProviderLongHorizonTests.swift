import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AISDKProvider
import AISDKProviderUtils
import SwiftAISDK
@testable import HanlinChatCore
import Testing

@Suite("Provider Long Horizon & Investigation Tests")
struct ProviderLongHorizonTests {

    private static func makeEngine(emulator: StatefulProviderEmulator) throws -> HanlinAISDKAgentEngine {
        let config = HanlinChatModelConfiguration(
            modelID: "gpt-4o",
            company: "OpenAI",
            apiType: "openai",
            endpoint: "https://api.openai.com/v1/chat/completions",
            credential: "test-openai-key"
        )
        return try HanlinAISDKAgentEngine(configuration: config, fetch: emulator.makeFetchFunction())
    }

    // MARK: - S04: Sequential 5-Tool Chain

    @Test("S04: Sequential 5-tool chain executing 6 provider steps with monotonic history")
    func testS04SequentialFiveToolChain() async throws {
        let ledger = ToolExecutionLedger()
        let tools: [HanlinAISDKToolDefinition] = (1...5).map { idx in
            let name = "step_tool_\(idx)"
            return HanlinAISDKToolDefinition(
                name: name,
                description: "Tool step \(idx)",
                inputSchemaData: try! JSONSerialization.data(withJSONObject: ["type": "object"]),
                execute: { args, callID in
                    ledger.recordStart(toolName: name, callID: callID, arguments: args)
                    ledger.recordCompletion(callID: callID, resultText: "result_\(idx)")
                    return HanlinAISDKToolExecutionOutput(modelText: "result_\(idx)")
                }
            )
        }

        var expectations: [Int: RoundExpectation] = [:]
        var responses: [Int: ProviderResponseEmission] = [:]

        for i in 0..<5 {
            let nextToolIndex = i + 1
            let callID = "call-step-\(nextToolIndex)"
            let toolName = "step_tool_\(nextToolIndex)"

            responses[i] = .sseChunks(ProviderResponseFixtures.openAIChatToolCallChunks(
                calls: [(id: callID, name: toolName, arguments: "{}")],
                id: "c-\(i)"
            ))

            if i == 0 {
                expectations[0] = RoundExpectation()
            } else {
                // Assert prior tool call and result are preserved
                let prevToolIndex = i
                let prevCallID = "call-step-\(prevToolIndex)"
                let prevToolName = "step_tool_\(prevToolIndex)"
                expectations[i] = RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: prevCallID, name: prevToolName)],
                    expectedToolResults: [ExpectedToolResult(callID: prevCallID, name: prevToolName, expectedSubstring: "result_\(prevToolIndex)")]
                )
            }
        }

        // Final round 5: emits text answer
        responses[5] = .sseChunks(ProviderResponseFixtures.openAIChatTextChunks(text: "All 5 tools executed successfully.", id: "c-5"))
        expectations[5] = RoundExpectation(
            expectedAssistantToolCalls: [ExpectedToolCall(id: "call-step-5", name: "step_tool_5")],
            expectedToolResults: [ExpectedToolResult(callID: "call-step-5", name: "step_tool_5", expectedSubstring: "result_5")]
        )

        let emulator = StatefulProviderEmulator(
            profile: .openAINativeChat,
            scenarioName: "S04_SequentialFiveTools",
            roundExpectations: expectations,
            roundResponses: responses,
            ledger: ledger
        )
        let engine = try Self.makeEngine(emulator: emulator)

        let activeAliases = (1...5).map { "step_tool_\($0)" }
        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Execute 5 steps in sequence")],
            baseSystemPrompt: "Assistant",
            tools: tools,
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: activeAliases) }
        )

        var finalAns = ""
        for try await event in stream {
            if case .textDelta(let t) = event { finalAns += t }
        }

        #expect(finalAns.contains("All 5 tools executed"))
        #expect(emulator.requestCount == 6)
        try ledger.assertSingleExecutions()
    }

    // MARK: - S11: 20-Step Run

    @Test("S11: Long 20-step tool-heavy run with strict per-round request validation")
    func testS11TwentyStepRun() async throws {
        let ledger = ToolExecutionLedger()
        let repeatTool = HanlinAISDKToolDefinition(
            name: "counter_step",
            description: "Count step",
            inputSchemaData: try! JSONSerialization.data(withJSONObject: [
                "type": "object",
                "properties": ["step": ["type": "integer"]]
            ]),
            execute: { args, callID in
                ledger.recordStart(toolName: "counter_step", callID: callID, arguments: args)
                ledger.recordCompletion(callID: callID, resultText: "ack_\(callID)")
                return HanlinAISDKToolExecutionOutput(modelText: "ack_\(callID)")
            }
        )

        var expectations: [Int: RoundExpectation] = [:]
        var responses: [Int: ProviderResponseEmission] = [:]

        // 19 tool steps followed by 1 text step = 20 model steps
        for step in 0..<19 {
            let callID = "call-20step-\(step)"
            responses[step] = .sseChunks(ProviderResponseFixtures.openAIChatToolCallChunks(
                calls: [(id: callID, name: "counter_step", arguments: "{\"step\":\(step)}")],
                id: "c-20-\(step)"
            ))

            if step == 0 {
                expectations[0] = RoundExpectation()
            } else {
                let prevID = "call-20step-\(step - 1)"
                expectations[step] = RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: prevID, name: "counter_step")],
                    expectedToolResults: [ExpectedToolResult(callID: prevID, name: "counter_step", expectedSubstring: "ack_\(prevID)")]
                )
            }
        }

        // Round 19 (step 20) emits final answer
        responses[19] = .sseChunks(ProviderResponseFixtures.openAIChatTextChunks(text: "Finished 20 steps successfully.", id: "c-20-final"))
        let lastCallID = "call-20step-18"
        expectations[19] = RoundExpectation(
            expectedAssistantToolCalls: [ExpectedToolCall(id: lastCallID, name: "counter_step")],
            expectedToolResults: [ExpectedToolResult(callID: lastCallID, name: "counter_step", expectedSubstring: "ack_\(lastCallID)")]
        )

        let emulator = StatefulProviderEmulator(
            profile: .openAINativeChat,
            scenarioName: "S11_TwentyStepRun",
            roundExpectations: expectations,
            roundResponses: responses,
            ledger: ledger
        )
        let engine = try Self.makeEngine(emulator: emulator)

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Run 20 steps")],
            baseSystemPrompt: "Long runner",
            tools: [repeatTool],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: ["counter_step"]) }
        )

        var finalAns = ""
        for try await event in stream {
            if case .textDelta(let t) = event { finalAns += t }
        }

        #expect(finalAns.contains("Finished 20 steps successfully"))
        #expect(emulator.requestCount == 20)
        try ledger.assertSingleExecutions()
    }

    // MARK: - S12: Step-Limit Boundary

    @Test("S12: Engine step limit boundary (configured stopWhen: stepCountIs(32)) terminates cleanly")
    func testS12StepLimitBoundary() async throws {
        // In HanlinAISDKAgentEngine: stopWhen: [stepCountIs(32)]
        // If the model continuously issues tool calls, step 32 triggers stopWhen and stops loop.
        let loopingTool = HanlinAISDKToolDefinition(
            name: "looping_tool",
            description: "Loops forever",
            inputSchemaData: try! JSONSerialization.data(withJSONObject: ["type": "object"]),
            execute: { _, _ in HanlinAISDKToolExecutionOutput(modelText: "continue") }
        )

        var expectations: [Int: RoundExpectation] = [:]
        var responses: [Int: ProviderResponseEmission] = [:]
        for step in 0...36 {
            let callID = "call-limit-\(step)"
            responses[step] = .sseChunks(ProviderResponseFixtures.openAIChatToolCallChunks(
                calls: [(id: callID, name: "looping_tool", arguments: "{}")],
                id: "c-lim-\(step)"
            ))
            expectations[step] = RoundExpectation()
        }

        let emulator = StatefulProviderEmulator(
            profile: .openAINativeChat,
            scenarioName: "S12_StepLimitBoundary",
            roundExpectations: expectations,
            roundResponses: responses
        )
        let engine = try Self.makeEngine(emulator: emulator)

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Loop until boundary")],
            baseSystemPrompt: nil,
            tools: [loopingTool],
            maxSteps: 32,
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: ["looping_tool"]) }
        )

        var stepFinishedCount = 0
        for try await event in stream {
            if case .stepFinished = event { stepFinishedCount += 1 }
        }

        #expect(stepFinishedCount == 32, "Engine must terminate when stepCountIs(32) triggers.")
        #expect(emulator.requestCount <= 32, "No request should be made beyond the configured step limit.")
    }

    // MARK: - S13: Long History & Second User Turn

    @Test("S13: Multi-turn conversation preserves prior tool and answer history without stale run state")
    func testS13SecondUserTurnWithHistory() async throws {
        // First turn: User asks for a calc -> model calls calc -> answers 42.
        // Second turn: User asks "What was the previous number?" -> model receives full history and answers "It was 42".
        let firstTurnTool = HanlinAISDKToolDefinition(
            name: "calc_tool",
            description: "Calc",
            inputSchemaData: try! JSONSerialization.data(withJSONObject: ["type": "object"]),
            execute: { _, _ in HanlinAISDKToolExecutionOutput(modelText: "42") }
        )

        let emulatorTurn1 = StatefulProviderEmulator(
            profile: .openAINativeChat,
            scenarioName: "S13_Turn1",
            roundExpectations: [
                0: RoundExpectation(),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-t1", name: "calc_tool")],
                    expectedToolResults: [ExpectedToolResult(callID: "call-t1", name: "calc_tool", expectedSubstring: "42")]
                )
            ],
            roundResponses: [
                0: .sseChunks(ProviderResponseFixtures.openAIChatToolCallChunks(calls: [(id: "call-t1", name: "calc_tool", arguments: "{}")])),
                1: .sseChunks(ProviderResponseFixtures.openAIChatTextChunks(text: "The computed answer is 42."))
            ]
        )
        let engineTurn1 = try Self.makeEngine(emulator: emulatorTurn1)

        let stream1 = try await engineTurn1.stream(
            messages: [.init(role: .user, text: "Compute value")],
            baseSystemPrompt: "Assistant",
            tools: [firstTurnTool],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: ["calc_tool"]) }
        )
        for try await _ in stream1 {}

        // Second turn messages: contains user1, assistant1, and user2!
        let turn2Messages: [HanlinAISDKMessage] = [
            .init(role: .user, text: "Compute value"),
            .init(role: .assistant, text: "The computed answer is 42."),
            .init(role: .user, text: "What was the number you computed?")
        ]

        let emulatorTurn2 = StatefulProviderEmulator(
            profile: .openAINativeChat,
            scenarioName: "S13_Turn2",
            roundExpectations: [
                0: RoundExpectation(
                    customValidator: { req, _, _ in
                        let body = String(decoding: ProviderRequestValidators.extractBody(from: req), as: UTF8.self)
                        #expect(body.contains("The computed answer is 42"), "History must be retained in second turn.")
                        #expect(body.contains("What was the number you computed?"), "New user turn must be present.")
                    }
                )
            ],
            roundResponses: [
                0: .sseChunks(ProviderResponseFixtures.openAIChatTextChunks(text: "The number was 42."))
            ]
        )
        let engineTurn2 = try Self.makeEngine(emulator: emulatorTurn2)

        let stream2 = try await engineTurn2.stream(
            messages: turn2Messages,
            baseSystemPrompt: "Assistant",
            tools: [firstTurnTool],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: ["calc_tool"]) }
        )

        var turn2Answer = ""
        for try await event in stream2 {
            if case .textDelta(let text) = event { turn2Answer += text }
        }

        #expect(turn2Answer == "The number was 42.")
        #expect(emulatorTurn2.requestCount == 1)
    }

    // MARK: - Section 19: Special Investigation: Current TestFlight Failure Class

    @Test("Section 19: Offline reproduction of OpenRouter reasoning_details and finish=other failure class")
    func testSection19OpenRouterFailureClassReproduction() async throws {
        // Construct OpenRouter scenario:
        // Round 0: Model returns reasoning_details structure + tool call load_skill("code")
        // Round 1: Model request sent to OpenRouter
        // We verify whether reasoning_details is preserved or dropped by the pinned swift-ai-sdk adapter.

        let reasoningDetailsJSON = ProviderResponseFixtures.richOpaqueReasoningDetailsObject
        let expectedJSONValue = ProviderResponseFixtures.richOpaqueReasoningDetailsJSONValue

        let emulator = StatefulProviderEmulator(
            profile: .openRouterReasoningDetails,
            scenarioName: "Section19_OpenRouter_ReasoningDetails",
            roundExpectations: [
                0: RoundExpectation(),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-load-code", name: "load_skill")],
                    // We expect reasoning_details to be preserved with exact structural equality:
                    expectedReasoningDetailsPresent: true,
                    expectedReasoningDetails: expectedJSONValue
                )
            ],
            roundResponses: [
                0: .sseChunks(ProviderResponseFixtures.openAIReasoningAndToolCallChunks(
                    reasoningContent: "Plan: I need to load the code skill first",
                    reasoningDetails: reasoningDetailsJSON,
                    calls: [(id: "call-load-code", name: "load_skill", arguments: "{\"skill\":\"code\"}")],
                    id: "c-or-1"
                )),
                1: .sseChunks(ProviderResponseFixtures.openAIChatTextChunks(text: "Skill loaded.", id: "c-or-2"))
            ]
        )

        let config = HanlinChatModelConfiguration(
            modelID: "nvidia/llama-3.1-nemotron-70b-instruct",
            company: "OpenRouter",
            apiType: "openai",
            endpoint: "https://openrouter.ai/api/v1/chat/completions",
            credential: "sk-or-testkey",
            supportsReasoning: true
        )
        let engine = try HanlinAISDKAgentEngine(configuration: config, fetch: emulator.makeFetchFunction())

        let loadSkill = HanlinAISDKToolDefinition(
            name: "load_skill",
            description: "Load a skill",
            inputSchemaData: try JSONSerialization.data(withJSONObject: ["type": "object"]),
            execute: { _, _ in HanlinAISDKToolExecutionOutput(modelText: "code skill loaded") }
        )

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Run python code")],
            baseSystemPrompt: "Assistant",
            tools: [loadSkill],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: ["load_skill"]) }
        )

        var didFailPreservation = false
        do {
            for try await _ in stream {}
        } catch let err as ConformanceProtocolError {
            if err.category == .REASONING_STATE {
                didFailPreservation = true
            }
        } catch {
            // Other error
        }

        #expect(!didFailPreservation, "OpenRouter reasoning_details must be preserved during stream decode and round-trip in continuation request.")
        #expect(emulator.requestCount == 2)
    }

    // MARK: - P12B: Structured SDK History (Section 7)

    @Test("P12B: Structured assistant tool-call and tool-result history survives into next provider model request")
    func testP12BStructuredSDKHistory() async throws {
        let calcTool = HanlinAISDKToolDefinition(
            name: "calculate",
            description: "Calculator",
            inputSchemaData: try JSONSerialization.data(withJSONObject: [
                "type": "object",
                "properties": ["expr": ["type": "string"]]
            ]),
            execute: { args, callID in
                HanlinAISDKToolExecutionOutput(modelText: "100")
            }
        )

        let emulator = StatefulProviderEmulator(
            profile: .openAINativeChat,
            scenarioName: "P12B_StructuredSDKHistory",
            roundExpectations: [
                0: RoundExpectation(),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-calc-1", name: "calculate")],
                    expectedToolResults: [ExpectedToolResult(callID: "call-calc-1", name: "calculate", expectedContent: .exact("100"))]
                )
            ],
            roundResponses: [
                0: .sseChunks(ProviderResponseFixtures.openAIChatToolCallChunks(
                    calls: [(id: "call-calc-1", name: "calculate", arguments: "{\"expr\":\"50+50\"}")],
                    id: "c-p12b-1"
                )),
                1: .sseChunks(ProviderResponseFixtures.openAIChatTextChunks(text: "Result is 100.", id: "c-p12b-2"))
            ]
        )

        let config = HanlinChatModelConfiguration(
            modelID: "gpt-4o",
            company: "OpenAI",
            apiType: "openai",
            endpoint: "https://api.openai.com/v1/chat/completions",
            credential: "test-openai-key"
        )
        let engine = try HanlinAISDKAgentEngine(configuration: config, fetch: emulator.makeFetchFunction())

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Calculate 50 + 50")],
            baseSystemPrompt: "Assistant",
            tools: [calcTool],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: ["calculate"]) }
        )

        var finalAns = ""
        for try await event in stream {
            if case .textDelta(let delta) = event { finalAns += delta }
        }

        #expect(finalAns.contains("Result is 100"))
        #expect(emulator.requestCount == 2)
    }
}
