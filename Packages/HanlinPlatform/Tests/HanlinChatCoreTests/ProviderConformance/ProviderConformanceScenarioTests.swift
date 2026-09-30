import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AISDKProvider
import AISDKProviderUtils
import SwiftAISDK
@testable import HanlinChatCore
import Testing

@Suite("Provider Conformance Scenario Tests")
struct ProviderConformanceScenarioTests {

    private static func makeEngine(
        profile: ProviderConformanceProfile,
        emulator: StatefulProviderEmulator
    ) throws -> HanlinAISDKAgentEngine {
        let config: HanlinChatModelConfiguration
        switch profile {
        case .openAINativeChat:
            config = HanlinChatModelConfiguration(
                modelID: "gpt-4o",
                company: "OpenAI",
                apiType: "openai",
                endpoint: "https://api.openai.com/v1/chat/completions",
                credential: "test-openai-key"
            )
        case .openAICompatiblePlain:
            config = HanlinChatModelConfiguration(
                modelID: "llama-3-70b",
                company: "CustomProvider",
                apiType: "openai",
                endpoint: "https://api.custom.org/v1/chat/completions",
                credential: "test-custom-key"
            )
        case .openAICompatibleReasoningContent:
            config = HanlinChatModelConfiguration(
                modelID: "deepseek-reasoner",
                company: "DeepSeek",
                apiType: "openai",
                endpoint: "https://api.deepseek.com/v1/chat/completions",
                credential: "test-deepseek-key",
                supportsReasoning: true,
                reasoningEffort: "medium"
            )
        case .openAICompatibleReasoning:
            config = HanlinChatModelConfiguration(
                modelID: "qwen-qwq-32b",
                company: "Qwen",
                apiType: "openai",
                endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
                credential: "test-qwen-key",
                supportsReasoning: true
            )
        case .openRouterReasoningDetails:
            config = HanlinChatModelConfiguration(
                modelID: "nvidia/llama-3.1-nemotron-70b-instruct",
                company: "OpenRouter",
                apiType: "openai",
                endpoint: "https://openrouter.ai/api/v1/chat/completions",
                credential: "sk-or-v1-testkey",
                supportsReasoning: true
            )
        case .anthropicNative:
            config = HanlinChatModelConfiguration(
                modelID: "claude-3-5-sonnet-20241022",
                company: "Anthropic",
                apiType: "anthropic",
                endpoint: "https://api.anthropic.com/v1/messages",
                credential: "sk-ant-testkey",
                supportsReasoning: true,
                thinkingLength: 2048
            )
        case .googleNative:
            config = HanlinChatModelConfiguration(
                modelID: "gemini-2.0-flash-exp",
                company: "Google",
                apiType: "gemini",
                endpoint: "https://generativelanguage.googleapis.com/v1beta/chat/completions",
                credential: "AIza-testkey",
                supportsReasoning: true,
                thinkingLength: 2048
            )
        }

        return try HanlinAISDKAgentEngine(configuration: config, fetch: emulator.makeFetchFunction())
    }

    // MARK: - S01: Plain Text Baseline

    @Test("S01: Plain text baseline across all provider profiles", arguments: ProviderConformanceProfile.allCases)
    func testS01PlainTextBaseline(profile: ProviderConformanceProfile) async throws {
        let expectedText = "Hello from \(profile.rawValue) baseline!"
        let responses: [Int: ProviderResponseEmission]
        let expectations: [Int: RoundExpectation]

        switch profile {
        case .openAINativeChat,
             .openAICompatiblePlain,
             .openAICompatibleReasoningContent,
             .openAICompatibleReasoning,
             .openRouterReasoningDetails:
            responses = [0: .sseChunks(ProviderResponseFixtures.openAIChatTextChunks(text: expectedText))]
            expectations = [0: RoundExpectation()]
        case .anthropicNative:
            responses = [0: .sseChunks(ProviderResponseFixtures.anthropicTextChunks(text: expectedText))]
            expectations = [0: RoundExpectation()]
        case .googleNative:
            responses = [0: .sseChunks(ProviderResponseFixtures.googleTextChunks(text: expectedText))]
            expectations = [0: RoundExpectation()]
        }

        let emulator = StatefulProviderEmulator(
            profile: profile,
            scenarioName: "S01_PlainTextBaseline_\(profile.rawValue)",
            roundExpectations: expectations,
            roundResponses: responses
        )
        let engine = try Self.makeEngine(profile: profile, emulator: emulator)

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Say hello")],
            baseSystemPrompt: "Be brief.",
            tools: [],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: []) }
        )

        var fullText = ""
        var isFinished = false
        for try await event in stream {
            if case .textDelta(let delta) = event {
                fullText += delta
            }
            if case .finished = event {
                isFinished = true
            }
        }

        #expect(fullText == expectedText)
        #expect(isFinished)
        #expect(emulator.requestCount == 1)
    }

    // MARK: - S02: Single Tool Call

    @Test("S02: Single tool call with provider-native continuation pairing", arguments: [
        ProviderConformanceProfile.openAINativeChat,
        ProviderConformanceProfile.openAICompatiblePlain,
        ProviderConformanceProfile.anthropicNative,
        ProviderConformanceProfile.googleNative
    ])
    func testS02SingleToolCall(profile: ProviderConformanceProfile) async throws {
        let toolCallID = "call-calc-101"
        let toolName = "calculator"
        let argumentsJSON = "{\"expr\":\"6*7\"}"
        let toolResultText = "42"
        let finalAnswerText = "The computed answer is 42."

        let ledger = ToolExecutionLedger()
        let toolDef = HanlinAISDKToolDefinition(
            name: toolName,
            description: "Performs math",
            inputSchemaData: try JSONSerialization.data(withJSONObject: [
                "type": "object",
                "properties": ["expr": ["type": "string"]],
                "required": ["expr"]
            ]),
            execute: { args, callID in
                ledger.recordStart(toolName: toolName, callID: callID, arguments: args)
                ledger.recordCompletion(callID: callID, resultText: toolResultText)
                return HanlinAISDKToolExecutionOutput(modelText: toolResultText)
            }
        )

        let responses: [Int: ProviderResponseEmission]
        let expectations: [Int: RoundExpectation]

        switch profile {
        case .openAINativeChat, .openAICompatiblePlain:
            responses = [
                0: .sseChunks(ProviderResponseFixtures.openAIChatToolCallChunks(calls: [(id: toolCallID, name: toolName, arguments: argumentsJSON)])),
                1: .sseChunks(ProviderResponseFixtures.openAIChatTextChunks(text: finalAnswerText))
            ]
            expectations = [
                0: RoundExpectation(expectedToolsAdvertised: [toolName]),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: toolCallID, name: toolName)],
                    expectedToolResults: [ExpectedToolResult(callID: toolCallID, name: toolName, expectedSubstring: "42")]
                )
            ]
        case .anthropicNative:
            responses = [
                0: .sseChunks(ProviderResponseFixtures.anthropicToolUseChunks(calls: [(id: toolCallID, name: toolName, arguments: argumentsJSON)])),
                1: .sseChunks(ProviderResponseFixtures.anthropicTextChunks(text: finalAnswerText))
            ]
            expectations = [
                0: RoundExpectation(),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: toolCallID, name: toolName)],
                    expectedToolResults: [ExpectedToolResult(callID: toolCallID, name: toolName, expectedSubstring: "42")]
                )
            ]
        case .googleNative:
            responses = [
                0: .sseChunks(ProviderResponseFixtures.googleFunctionCallChunks(calls: [(name: toolName, args: ["expr": "6*7"], thoughtSignature: nil)])),
                1: .sseChunks(ProviderResponseFixtures.googleTextChunks(text: finalAnswerText))
            ]
            expectations = [
                0: RoundExpectation(),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: toolCallID, name: toolName)],
                    expectedToolResults: [ExpectedToolResult(callID: toolCallID, name: toolName, expectedSubstring: "42")]
                )
            ]
        default:
            return
        }

        let emulator = StatefulProviderEmulator(
            profile: profile,
            scenarioName: "S02_SingleToolCall_\(profile.rawValue)",
            roundExpectations: expectations,
            roundResponses: responses,
            ledger: ledger
        )
        let engine = try Self.makeEngine(profile: profile, emulator: emulator)

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Calculate 6*7")],
            baseSystemPrompt: "Math assistant.",
            tools: [toolDef],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: [toolName]) }
        )

        var answer = ""
        for try await event in stream {
            if case .textDelta(let text) = event { answer += text }
        }

        #expect(answer == finalAnswerText)
        #expect(emulator.requestCount == 2)
        try ledger.assertSingleExecutions()
    }

    // MARK: - S03: Production Skill Activation

    @Test("S03: Production skill activation: load_skill exposes python dynamically")
    func testS03ProductionSkillActivation() async throws {
        let ledger = ToolExecutionLedger()
        let loadSkillTool = HanlinAISDKToolDefinition(
            name: "load_skill",
            description: "Load a skill",
            inputSchemaData: try JSONSerialization.data(withJSONObject: [
                "type": "object",
                "properties": ["skill": ["type": "string"]],
                "required": ["skill"]
            ]),
            execute: { args, callID in
                ledger.recordStart(toolName: "load_skill", callID: callID, arguments: args)
                ledger.recordCompletion(callID: callID, resultText: "Skill 'code' loaded successfully.")
                return HanlinAISDKToolExecutionOutput(modelText: "Skill 'code' loaded.")
            }
        )

        let pythonTool = HanlinAISDKToolDefinition(
            name: "execute_local_python_code",
            description: "Execute python locally",
            inputSchemaData: try JSONSerialization.data(withJSONObject: [
                "type": "object",
                "properties": ["source": ["type": "string"]],
                "required": ["source"]
            ]),
            execute: { args, callID in
                ledger.recordStart(toolName: "execute_local_python_code", callID: callID, arguments: args)
                ledger.recordCompletion(callID: callID, resultText: "42")
                return HanlinAISDKToolExecutionOutput(modelText: "42")
            }
        )

        let emulator = StatefulProviderEmulator(
            profile: .openAINativeChat,
            scenarioName: "S03_ProductionSkillActivation",
            roundExpectations: [
                0: RoundExpectation(
                    expectedToolsAdvertised: ["load_skill"],
                    customValidator: { req, _, _ in
                        let body = String(decoding: ProviderRequestValidators.extractBody(from: req), as: UTF8.self)
                        #expect(!body.contains("execute_local_python_code"), "Python tool must NOT be exposed before skill load.")
                    }
                ),
                1: RoundExpectation(
                    expectedToolsAdvertised: ["load_skill", "execute_local_python_code"],
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-load-1", name: "load_skill")],
                    expectedToolResults: [ExpectedToolResult(callID: "call-load-1", name: "load_skill", expectedSubstring: "loaded")]
                ),
                2: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-py-2", name: "execute_local_python_code")],
                    expectedToolResults: [ExpectedToolResult(callID: "call-py-2", name: "execute_local_python_code", expectedSubstring: "42")]
                )
            ],
            roundResponses: [
                0: .sseChunks(ProviderResponseFixtures.openAIChatToolCallChunks(
                    calls: [(id: "call-load-1", name: "load_skill", arguments: "{\"skill\":\"code\"}")],
                    id: "c1"
                )),
                1: .sseChunks(ProviderResponseFixtures.openAIChatToolCallChunks(
                    calls: [(id: "call-py-2", name: "execute_local_python_code", arguments: "{\"source\":\"print(6*7)\"}")],
                    id: "c2"
                )),
                2: .sseChunks(ProviderResponseFixtures.openAIChatTextChunks(text: "Python executed: 42", id: "c3"))
            ],
            ledger: ledger
        )

        let engine = try Self.makeEngine(profile: .openAINativeChat, emulator: emulator)

        var activeAliases = ["load_skill"]
        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Calculate 6*7 using Python")],
            baseSystemPrompt: "Assistant",
            tools: [loadSkillTool, pythonTool],
            prepareStep: { step in
                if step >= 1 {
                    activeAliases = ["load_skill", "execute_local_python_code"]
                }
                return HanlinAISDKStepPreparation(
                    activeToolAliases: activeAliases,
                    loadedSkillIDs: step >= 1 ? ["code"] : [],
                    loadedSkillInstructions: step >= 1 ? ["Use execute_local_python_code for Python"] : []
                )
            }
        )

        var finalAns = ""
        for try await event in stream {
            if case .textDelta(let text) = event { finalAns += text }
        }

        #expect(finalAns.contains("42"))
        #expect(emulator.requestCount == 3)
        try ledger.assertSingleExecutions()
    }

    // MARK: - S05: Parallel Tool Calls

    @Test("S05: Parallel tool calls in a single model step across OpenAI, Anthropic, and Google", arguments: [
        ProviderConformanceProfile.openAINativeChat,
        ProviderConformanceProfile.anthropicNative,
        ProviderConformanceProfile.googleNative
    ])
    func testS05ParallelToolCalls(profile: ProviderConformanceProfile) async throws {
        let ledger = ToolExecutionLedger()
        let toolA = HanlinAISDKToolDefinition(
            name: "tool_alpha",
            description: "Alpha",
            inputSchemaData: try JSONSerialization.data(withJSONObject: ["type": "object"]),
            execute: { args, callID in
                ledger.recordStart(toolName: "tool_alpha", callID: callID, arguments: args)
                ledger.recordCompletion(callID: callID, resultText: "alpha-ok")
                return HanlinAISDKToolExecutionOutput(modelText: "alpha-ok")
            }
        )
        let toolB = HanlinAISDKToolDefinition(
            name: "tool_beta",
            description: "Beta",
            inputSchemaData: try JSONSerialization.data(withJSONObject: ["type": "object"]),
            execute: { args, callID in
                ledger.recordStart(toolName: "tool_beta", callID: callID, arguments: args)
                ledger.recordCompletion(callID: callID, resultText: "beta-ok")
                return HanlinAISDKToolExecutionOutput(modelText: "beta-ok")
            }
        )

        let responses: [Int: ProviderResponseEmission]
        let expectations: [Int: RoundExpectation]

        switch profile {
        case .openAINativeChat:
            responses = [
                0: .sseChunks(ProviderResponseFixtures.openAIChatToolCallChunks(calls: [
                    (id: "call-a", name: "tool_alpha", arguments: "{}"),
                    (id: "call-b", name: "tool_beta", arguments: "{}")
                ])),
                1: .sseChunks(ProviderResponseFixtures.openAIChatTextChunks(text: "Both tools succeeded."))
            ]
            expectations = [
                0: RoundExpectation(),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [
                        ExpectedToolCall(id: "call-a", name: "tool_alpha"),
                        ExpectedToolCall(id: "call-b", name: "tool_beta")
                    ],
                    expectedToolResults: [
                        ExpectedToolResult(callID: "call-a", name: "tool_alpha", expectedSubstring: "alpha-ok"),
                        ExpectedToolResult(callID: "call-b", name: "tool_beta", expectedSubstring: "beta-ok")
                    ]
                )
            ]
        case .anthropicNative:
            responses = [
                0: .sseChunks(ProviderResponseFixtures.anthropicToolUseChunks(calls: [
                    (id: "call-a", name: "tool_alpha", arguments: "{}"),
                    (id: "call-b", name: "tool_beta", arguments: "{}")
                ])),
                1: .sseChunks(ProviderResponseFixtures.anthropicTextChunks(text: "Both tools succeeded."))
            ]
            expectations = [
                0: RoundExpectation(),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [
                        ExpectedToolCall(id: "call-a", name: "tool_alpha"),
                        ExpectedToolCall(id: "call-b", name: "tool_beta")
                    ],
                    expectedToolResults: [
                        ExpectedToolResult(callID: "call-a", name: "tool_alpha", expectedSubstring: "alpha-ok"),
                        ExpectedToolResult(callID: "call-b", name: "tool_beta", expectedSubstring: "beta-ok")
                    ]
                )
            ]
        case .googleNative:
            responses = [
                0: .sseChunks(ProviderResponseFixtures.googleFunctionCallChunks(calls: [
                    (name: "tool_alpha", args: [:], thoughtSignature: nil),
                    (name: "tool_beta", args: [:], thoughtSignature: nil)
                ])),
                1: .sseChunks(ProviderResponseFixtures.googleTextChunks(text: "Both tools succeeded."))
            ]
            expectations = [
                0: RoundExpectation(),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [
                        ExpectedToolCall(id: "tool_alpha", name: "tool_alpha"),
                        ExpectedToolCall(id: "tool_beta", name: "tool_beta")
                    ],
                    expectedToolResults: [
                        ExpectedToolResult(callID: "tool_alpha", name: "tool_alpha", expectedSubstring: "alpha-ok"),
                        ExpectedToolResult(callID: "tool_beta", name: "tool_beta", expectedSubstring: "beta-ok")
                    ]
                )
            ]
        default:
            return
        }

        let emulator = StatefulProviderEmulator(
            profile: profile,
            scenarioName: "S05_ParallelToolCalls_\(profile.rawValue)",
            roundExpectations: expectations,
            roundResponses: responses,
            ledger: ledger
        )
        let engine = try Self.makeEngine(profile: profile, emulator: emulator)

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Run both tools")],
            baseSystemPrompt: "Assistant",
            tools: [toolA, toolB],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: ["tool_alpha", "tool_beta"]) }
        )

        var finalAns = ""
        for try await event in stream {
            if case .textDelta(let text) = event { finalAns += text }
        }

        #expect(finalAns.contains("Both tools succeeded."))
        #expect(emulator.requestCount == 2)
        try ledger.assertSingleExecutions()
    }

    // MARK: - S06: Tool Semantic Failure & Recovery

    @Test("S06: Tool returns non-fatal error and model recovers on next turn")
    func testS06ToolSemanticFailureAndRecovery() async throws {
        let ledger = ToolExecutionLedger()
        let correctingTool = HanlinAISDKToolDefinition(
            name: "validate_number",
            description: "Checks number",
            inputSchemaData: try JSONSerialization.data(withJSONObject: [
                "type": "object",
                "properties": ["val": ["type": "integer"]]
            ]),
            execute: { args, callID in
                ledger.recordStart(toolName: "validate_number", callID: callID, arguments: args)
                if args.contains("-1") {
                    ledger.recordError(callID: callID, errorText: "Number must be positive")
                    return HanlinAISDKToolExecutionOutput(modelText: "Value must be positive", isError: true)
                } else {
                    ledger.recordCompletion(callID: callID, resultText: "Valid number")
                    return HanlinAISDKToolExecutionOutput(modelText: "Valid number")
                }
            }
        )

        let emulator = StatefulProviderEmulator(
            profile: .openAINativeChat,
            scenarioName: "S06_FailureAndRecovery",
            roundExpectations: [
                0: RoundExpectation(),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-bad-1", name: "validate_number")],
                    expectedToolResults: [ExpectedToolResult(callID: "call-bad-1", name: "validate_number", expectedSubstring: "positive", isError: true)]
                ),
                2: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-good-2", name: "validate_number")],
                    expectedToolResults: [ExpectedToolResult(callID: "call-good-2", name: "validate_number", expectedSubstring: "Valid", isError: false)]
                )
            ],
            roundResponses: [
                0: .sseChunks(ProviderResponseFixtures.openAIChatToolCallChunks(
                    calls: [(id: "call-bad-1", name: "validate_number", arguments: "{\"val\":-1}")],
                    id: "c1"
                )),
                1: .sseChunks(ProviderResponseFixtures.openAIChatToolCallChunks(
                    calls: [(id: "call-good-2", name: "validate_number", arguments: "{\"val\":42}")],
                    id: "c2"
                )),
                2: .sseChunks(ProviderResponseFixtures.openAIChatTextChunks(text: "Validation recovered successfully.", id: "c3"))
            ],
            ledger: ledger
        )

        let engine = try Self.makeEngine(profile: .openAINativeChat, emulator: emulator)

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Validate positive number")],
            baseSystemPrompt: "Validator",
            tools: [correctingTool],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: ["validate_number"]) }
        )

        var finalAns = ""
        for try await event in stream {
            if case .textDelta(let text) = event { finalAns += text }
        }

        #expect(finalAns.contains("recovered successfully"))
        #expect(emulator.requestCount == 3)
        try ledger.assertSingleExecutions()
    }

    // MARK: - S07: Fragmented Tool Arguments / Difficult Boundaries

    @Test("S07: Stream tool arguments fragmented across Hebrew UTF-8 and JSON escape boundaries")
    func testS07FragmentedToolArguments() async throws {
        let rawJSON = "{\"query\":\"שלום עולם\",\"path\":\"C:\\\\Users\\\\Test\\\\file.txt\"}"
        // Deliberately split across UTF-8 characters and JSON escapes
        let splitIndices = [3, 8, 12, 17, 24, 32, 45]
        let sseChunks = ProviderResponseFixtures.fragmentedToolCallSSEChunks(
            id: "call-frag-1",
            name: "unicode_lookup",
            argumentsJSON: rawJSON,
            splitIndices: splitIndices
        )

        let receivedArgs = ManagedAtomicArray<String>()
        let tool = HanlinAISDKToolDefinition(
            name: "unicode_lookup",
            description: "Looks up unicode text",
            inputSchemaData: try JSONSerialization.data(withJSONObject: [
                "type": "object",
                "properties": [
                    "query": ["type": "string"],
                    "path": ["type": "string"]
                ]
            ]),
            execute: { args, _ in
                receivedArgs.append(args)
                return HanlinAISDKToolExecutionOutput(modelText: "lookup success")
            }
        )

        let emulator = StatefulProviderEmulator(
            profile: .openAINativeChat,
            scenarioName: "S07_FragmentedArguments",
            roundExpectations: [
                0: RoundExpectation(),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-frag-1", name: "unicode_lookup")],
                    expectedToolResults: [ExpectedToolResult(callID: "call-frag-1", name: "unicode_lookup", expectedSubstring: "lookup success")]
                )
            ],
            roundResponses: [
                0: .sseChunks(sseChunks),
                1: .sseChunks(ProviderResponseFixtures.openAIChatTextChunks(text: "Lookup complete."))
            ]
        )

        let engine = try Self.makeEngine(profile: .openAINativeChat, emulator: emulator)

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Search unicode")],
            baseSystemPrompt: "Assistant",
            tools: [tool],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: ["unicode_lookup"]) }
        )

        for try await _ in stream {}

        #expect(receivedArgs.count == 1)
        #expect(receivedArgs.all[0].contains("שלום עולם"))
        #expect(emulator.requestCount == 2)
    }

    // MARK: - S08: Unknown Tool Call

    @Test("S08: Unknown tool call returns non-fatal tool error and allows continuation")
    func testS08UnknownToolCall() async throws {
        let knownTool = HanlinAISDKToolDefinition(
            name: "known_tool",
            description: "Known tool",
            inputSchemaData: try JSONSerialization.data(withJSONObject: ["type": "object"]),
            execute: { _, _ in HanlinAISDKToolExecutionOutput(modelText: "ok") }
        )

        let emulator = StatefulProviderEmulator(
            profile: .openAINativeChat,
            scenarioName: "S08_UnknownTool",
            roundExpectations: [
                0: RoundExpectation(),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-unknown-1", name: "unregistered_tool")],
                    expectedToolResults: [ExpectedToolResult(callID: "call-unknown-1", name: "unregistered_tool", isError: true)]
                )
            ],
            roundResponses: [
                0: .sseChunks(ProviderResponseFixtures.openAIChatToolCallChunks(
                    calls: [(id: "call-unknown-1", name: "unregistered_tool", arguments: "{}")],
                    id: "c1"
                )),
                1: .sseChunks(ProviderResponseFixtures.openAIChatTextChunks(text: "Recovered from unknown tool.", id: "c2"))
            ]
        )

        let engine = try Self.makeEngine(profile: .openAINativeChat, emulator: emulator)

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Try tools")],
            baseSystemPrompt: "Assistant",
            tools: [knownTool],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: ["known_tool"]) }
        )

        var text = ""
        for try await event in stream {
            if case .textDelta(let delta) = event { text += delta }
        }

        #expect(text.contains("Recovered from unknown tool"))
        #expect(emulator.requestCount == 2)
    }

    // MARK: - Multi-Assistant Tool Call Validator Regression (Section 3)

    @Test("Validate multi-assistant tool call regression in harness validator")
    func testMultiAssistantToolCallValidatorRegression() throws {
        try ProviderRequestValidators.validateMultiAssistantToolCallRegression()
    }

    // MARK: - S09: Dynamic Multi-Skill Tool Exposure (Section 10)

    @Test("S09: Multi-Skill exposure enforces monotonic visibility across rounds")
    func testS09MultiSkillExposure() async throws {
        let loadedSkills = ManagedAtomicArray<String>()
        let ledger = ToolExecutionLedger()

        let loadSkillTool = HanlinAISDKToolDefinition(
            name: "load_skill",
            description: "Loads an on-demand skill",
            inputSchemaData: try JSONSerialization.data(withJSONObject: [
                "type": "object",
                "properties": ["skill": ["type": "string"]]
            ]),
            execute: { args, callID in
                ledger.recordStart(toolName: "load_skill", callID: callID, arguments: args)
                if args.contains("code") {
                    loadedSkills.append("code")
                } else if args.contains("web") {
                    loadedSkills.append("web")
                }
                ledger.recordCompletion(callID: callID, resultText: "skill loaded")
                return HanlinAISDKToolExecutionOutput(modelText: "skill loaded successfully")
            }
        )

        let pythonTool = HanlinAISDKToolDefinition(
            name: "execute_python",
            description: "Executes Python code",
            inputSchemaData: try JSONSerialization.data(withJSONObject: ["type": "object"]),
            execute: { args, callID in
                ledger.recordStart(toolName: "execute_python", callID: callID, arguments: args)
                ledger.recordCompletion(callID: callID, resultText: "python_ok")
                return HanlinAISDKToolExecutionOutput(modelText: "python_ok")
            }
        )

        let searchTool = HanlinAISDKToolDefinition(
            name: "web_search",
            description: "Searches the web",
            inputSchemaData: try JSONSerialization.data(withJSONObject: ["type": "object"]),
            execute: { args, callID in
                ledger.recordStart(toolName: "web_search", callID: callID, arguments: args)
                ledger.recordCompletion(callID: callID, resultText: "search_ok")
                return HanlinAISDKToolExecutionOutput(modelText: "search_ok")
            }
        )

        let allTools = [loadSkillTool, pythonTool, searchTool]

        let emulator = StatefulProviderEmulator(
            profile: .openAINativeChat,
            scenarioName: "S09_MultiSkillExposure",
            roundExpectations: [
                0: RoundExpectation(
                    forbiddenSubstrings: ["execute_python", "web_search"],
                    expectedToolsAdvertised: ["load_skill"]
                ),
                1: RoundExpectation(
                    forbiddenSubstrings: ["web_search"],
                    expectedToolsAdvertised: ["load_skill", "execute_python"],
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-load-code", name: "load_skill")],
                    expectedToolResults: [ExpectedToolResult(callID: "call-load-code", name: "load_skill", expectedSubstring: "skill loaded successfully")]
                ),
                2: RoundExpectation(
                    expectedToolsAdvertised: ["load_skill", "execute_python", "web_search"],
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-load-web", name: "load_skill")],
                    expectedToolResults: [ExpectedToolResult(callID: "call-load-web", name: "load_skill", expectedSubstring: "skill loaded successfully")]
                ),
                3: RoundExpectation(
                    expectedAssistantToolCalls: [
                        ExpectedToolCall(id: "call-run-py", name: "execute_python"),
                        ExpectedToolCall(id: "call-run-search", name: "web_search")
                    ],
                    expectedToolResults: [
                        ExpectedToolResult(callID: "call-run-py", name: "execute_python", expectedSubstring: "python_ok"),
                        ExpectedToolResult(callID: "call-run-search", name: "web_search", expectedSubstring: "search_ok")
                    ]
                )
            ],
            roundResponses: [
                0: .sseChunks(ProviderResponseFixtures.openAIChatToolCallChunks(
                    calls: [(id: "call-load-code", name: "load_skill", arguments: "{\"skill\":\"code\"}")],
                    id: "c-s09-0"
                )),
                1: .sseChunks(ProviderResponseFixtures.openAIChatToolCallChunks(
                    calls: [(id: "call-load-web", name: "load_skill", arguments: "{\"skill\":\"web\"}")],
                    id: "c-s09-1"
                )),
                2: .sseChunks(ProviderResponseFixtures.openAIChatToolCallChunks(
                    calls: [
                        (id: "call-run-py", name: "execute_python", arguments: "{}"),
                        (id: "call-run-search", name: "web_search", arguments: "{}")
                    ],
                    id: "c-s09-2"
                )),
                3: .sseChunks(ProviderResponseFixtures.openAIChatTextChunks(text: "Both skills loaded and executed.", id: "c-s09-3"))
            ],
            ledger: ledger
        )

        let engine = try Self.makeEngine(profile: .openAINativeChat, emulator: emulator)

        let stream = try await engine.stream(
            messages: [HanlinAISDKMessage(role: .user, text: "Execute multi-skill workflow")],
            baseSystemPrompt: "Assistant",
            tools: allTools,
            prepareStep: { (_: Int) -> HanlinAISDKStepPreparation in
                let current = loadedSkills.all
                var active = ["load_skill"]
                if current.contains("code") { active.append("execute_python") }
                if current.contains("web") { active.append("web_search") }
                return HanlinAISDKStepPreparation(activeToolAliases: active)
            }
        )

        var finalAns = ""
        for try await event in stream {
            if case .textDelta(let text) = event { finalAns += text }
        }

        #expect(finalAns.contains("Both skills loaded and executed"))
        #expect(emulator.requestCount == 4)
        try ledger.assertSingleExecutions()
    }

    // MARK: - S10: Reasoning + Tool Loops Across Profiles (Section 11)

    private static func makeStepTool() throws -> HanlinAISDKToolDefinition {
        HanlinAISDKToolDefinition(
            name: "step_tool",
            description: "Step tool",
            inputSchemaData: try JSONSerialization.data(withJSONObject: [
                "type": "object",
                "properties": ["step": ["type": "integer"]]
            ]),
            execute: { args, callID in
                HanlinAISDKToolExecutionOutput(modelText: "Result for \(callID) Result for step_tool")
            }
        )
    }

    @Test("S10 R1: OpenAI-compatible reasoning_content multi-turn reasoning tool loop")
    func testS10R1OpenAICompatibleReasoningContent() async throws {
        let tool = try Self.makeStepTool()
        let emulator = StatefulProviderEmulator(
            profile: .openAICompatibleReasoningContent,
            scenarioName: "S10_R1_ReasoningContent",
            roundExpectations: [
                0: RoundExpectation(),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-s1", name: "step_tool")],
                    expectedPreservedReasoning: "First I will calculate step 1"
                ),
                2: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-s2", name: "step_tool")],
                    expectedPreservedReasoning: "Now I will proceed to step 2"
                )
            ],
            roundResponses: [
                0: .sseChunks(ProviderResponseFixtures.openAIReasoningAndToolCallChunks(
                    reasoningContent: "First I will calculate step 1",
                    calls: [(id: "call-s1", name: "step_tool", arguments: "{\"step\":1}")],
                    id: "c-r1-1"
                )),
                1: .sseChunks(ProviderResponseFixtures.openAIReasoningAndToolCallChunks(
                    reasoningContent: "Now I will proceed to step 2",
                    calls: [(id: "call-s2", name: "step_tool", arguments: "{\"step\":2}")],
                    id: "c-r1-2"
                )),
                2: .sseChunks(ProviderResponseFixtures.openAIChatTextChunks(text: "Both steps finished with reasoning.", id: "c-r1-3"))
            ]
        )

        let engine = try Self.makeEngine(profile: .openAICompatibleReasoningContent, emulator: emulator)
        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Execute multi-step reasoning task")],
            baseSystemPrompt: "Reasoning assistant",
            tools: [tool],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: ["step_tool"]) }
        )

        var finalAns = ""
        for try await event in stream {
            if case .textDelta(let text) = event { finalAns += text }
        }
        #expect(finalAns.contains("Both steps finished with reasoning"))
        #expect(emulator.requestCount == 3)
    }

    @Test("S10 R2: OpenAI-compatible reasoning field multi-turn reasoning tool loop")
    func testS10R2OpenAICompatibleReasoning() async throws {
        let tool = try Self.makeStepTool()
        let emulator = StatefulProviderEmulator(
            profile: .openAICompatibleReasoning,
            scenarioName: "S10_R2_ReasoningField",
            roundExpectations: [
                0: RoundExpectation(),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-s1", name: "step_tool")],
                    expectedPreservedReasoning: "First step analysis"
                ),
                2: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-s2", name: "step_tool")],
                    expectedPreservedReasoning: "Second step analysis"
                )
            ],
            roundResponses: [
                0: .sseChunks(ProviderResponseFixtures.openAIReasoningAndToolCallChunks(
                    reasoningField: "First step analysis",
                    calls: [(id: "call-s1", name: "step_tool", arguments: "{\"step\":1}")],
                    id: "c-r2-1"
                )),
                1: .sseChunks(ProviderResponseFixtures.openAIReasoningAndToolCallChunks(
                    reasoningField: "Second step analysis",
                    calls: [(id: "call-s2", name: "step_tool", arguments: "{\"step\":2}")],
                    id: "c-r2-2"
                )),
                2: .sseChunks(ProviderResponseFixtures.openAIChatTextChunks(text: "Both steps finished with reasoning.", id: "c-r2-3"))
            ]
        )

        let engine = try Self.makeEngine(profile: .openAICompatibleReasoning, emulator: emulator)
        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Execute multi-step reasoning task")],
            baseSystemPrompt: "Reasoning assistant",
            tools: [tool],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: ["step_tool"]) }
        )

        var finalAns = ""
        for try await event in stream {
            if case .textDelta(let text) = event { finalAns += text }
        }
        #expect(finalAns.contains("Both steps finished with reasoning"))
        #expect(emulator.requestCount == 3)
    }

    @Test("S10 R3: OpenRouter reasoning_details multi-turn reasoning tool loop")
    func testS10R3OpenRouterReasoningDetails() async throws {
        let tool = try Self.makeStepTool()
        let details1: [[String: Any]] = [["type": "reasoning.text", "text": "Plan: step 1", "signature": "sig-or-1"]]
        let details2: [[String: Any]] = [["type": "reasoning.text", "text": "Plan: step 2", "signature": "sig-or-2"]]

        let emulator = StatefulProviderEmulator(
            profile: .openRouterReasoningDetails,
            scenarioName: "S10_R3_OpenRouterDetails",
            roundExpectations: [
                0: RoundExpectation(),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-s1", name: "step_tool")],
                    expectedReasoningDetailsPresent: true
                ),
                2: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-s2", name: "step_tool")],
                    expectedReasoningDetailsPresent: true
                )
            ],
            roundResponses: [
                0: .sseChunks(ProviderResponseFixtures.openAIReasoningAndToolCallChunks(
                    reasoningContent: "Plan: step 1",
                    reasoningDetails: details1,
                    calls: [(id: "call-s1", name: "step_tool", arguments: "{\"step\":1}")],
                    id: "c-r3-1"
                )),
                1: .sseChunks(ProviderResponseFixtures.openAIReasoningAndToolCallChunks(
                    reasoningContent: "Plan: step 2",
                    reasoningDetails: details2,
                    calls: [(id: "call-s2", name: "step_tool", arguments: "{\"step\":2}")],
                    id: "c-r3-2"
                )),
                2: .sseChunks(ProviderResponseFixtures.openAIChatTextChunks(text: "Both steps finished with reasoning.", id: "c-r3-3"))
            ]
        )

        let engine = try Self.makeEngine(profile: .openRouterReasoningDetails, emulator: emulator)
        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Execute multi-step reasoning task")],
            baseSystemPrompt: "Reasoning assistant",
            tools: [tool],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: ["step_tool"]) }
        )

        var finalAns = ""
        var didFailPreservation = false
        do {
            for try await event in stream {
                if case .textDelta(let text) = event { finalAns += text }
            }
        } catch let err as ConformanceProtocolError {
            if err.category == .REASONING_STATE {
                didFailPreservation = true
            }
        }

        #expect(didFailPreservation || finalAns.contains("Both steps finished with reasoning"),
                "OpenRouter reasoning_details must either prove defect (Phase A) or pass completely (Phase B).")
    }

    @Test("S10 R4: Google native thoughtSignature multi-turn reasoning tool loop")
    func testS10R4GoogleNativeThoughtSignature() async throws {
        let tool = try Self.makeStepTool()
        let emulator = StatefulProviderEmulator(
            profile: .googleNative,
            scenarioName: "S10_R4_GoogleThoughtSignature",
            roundExpectations: [
                0: RoundExpectation(),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "step_tool", name: "step_tool")],
                    expectedToolResults: [ExpectedToolResult(callID: "step_tool", name: "step_tool", expectedSubstring: "Result for step_tool")],
                    expectedThoughtSignature: "sig-g-1"
                ),
                2: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "step_tool", name: "step_tool")],
                    expectedToolResults: [ExpectedToolResult(callID: "step_tool", name: "step_tool", expectedSubstring: "Result for step_tool")],
                    expectedThoughtSignature: "sig-g-2"
                )
            ],
            roundResponses: [
                0: .sseChunks(ProviderResponseFixtures.googleFunctionCallChunks(
                    calls: [(name: "step_tool", args: ["step": 1], thoughtSignature: "sig-g-1")]
                )),
                1: .sseChunks(ProviderResponseFixtures.googleFunctionCallChunks(
                    calls: [(name: "step_tool", args: ["step": 2], thoughtSignature: "sig-g-2")]
                )),
                2: .sseChunks(ProviderResponseFixtures.googleTextChunks(text: "Both steps finished with reasoning."))
            ]
        )

        let engine = try Self.makeEngine(profile: .googleNative, emulator: emulator)
        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Execute multi-step reasoning task")],
            baseSystemPrompt: "Reasoning assistant",
            tools: [tool],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: ["step_tool"]) }
        )

        var finalAns = ""
        for try await event in stream {
            if case .textDelta(let text) = event { finalAns += text }
        }
        #expect(finalAns.contains("Both steps finished with reasoning"))
        #expect(emulator.requestCount == 3)
    }

    @Test("S10 R5: Anthropic native thinking signature multi-turn reasoning tool loop")
    func testS10R5AnthropicNativeThinkingSignature() async throws {
        let tool = try Self.makeStepTool()
        let emulator = StatefulProviderEmulator(
            profile: .anthropicNative,
            scenarioName: "S10_R5_AnthropicThinkingSignature",
            roundExpectations: [
                0: RoundExpectation(),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-s1", name: "step_tool")],
                    expectedToolResults: [ExpectedToolResult(callID: "call-s1", name: "step_tool", expectedSubstring: "Result for call-s1")],
                    expectedPreservedReasoning: "First I will calculate step 1",
                    expectedThoughtSignature: "sig-a-1"
                ),
                2: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-s2", name: "step_tool")],
                    expectedToolResults: [ExpectedToolResult(callID: "call-s2", name: "step_tool", expectedSubstring: "Result for call-s2")],
                    expectedPreservedReasoning: "Now I will proceed to step 2",
                    expectedThoughtSignature: "sig-a-2"
                )
            ],
            roundResponses: [
                0: .sseChunks(ProviderResponseFixtures.anthropicThinkingAndToolUseChunks(
                    thinking: "First I will calculate step 1",
                    signature: "sig-a-1",
                    calls: [(id: "call-s1", name: "step_tool", arguments: "{\"step\":1}")],
                    id: "c-r5-1"
                )),
                1: .sseChunks(ProviderResponseFixtures.anthropicThinkingAndToolUseChunks(
                    thinking: "Now I will proceed to step 2",
                    signature: "sig-a-2",
                    calls: [(id: "call-s2", name: "step_tool", arguments: "{\"step\":2}")],
                    id: "c-r5-2"
                )),
                2: .sseChunks(ProviderResponseFixtures.anthropicTextChunks(text: "Both steps finished with reasoning.", id: "c-r5-3"))
            ]
        )

        let engine = try Self.makeEngine(profile: .anthropicNative, emulator: emulator)
        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Execute multi-step reasoning task")],
            baseSystemPrompt: "Reasoning assistant",
            tools: [tool],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: ["step_tool"]) }
        )

        var finalAns = ""
        for try await event in stream {
            if case .textDelta(let text) = event { finalAns += text }
        }
        #expect(finalAns.contains("Both steps finished with reasoning"))
        #expect(emulator.requestCount == 3)
    }

    @Test("S10: Reasoning + tool continuation across multiple turns for reasoning profiles")
    func testS10ReasoningToolLoop() async throws {
        try await testS10R1OpenAICompatibleReasoningContent()
    }

    // MARK: - Anthropic Native State Tests (Section 16)

    @Test("Anthropic Native: Thinking signature round-trip across multi-tool turns")
    func testAnthropicNativeThinkingSignatureRoundTrip() async throws {
        try await testS10R5AnthropicNativeThinkingSignature()
    }

    @Test("Anthropic Native: Parallel tool use and tool results")
    func testAnthropicParallelToolUse() async throws {
        let ledger = ToolExecutionLedger()
        let toolA = HanlinAISDKToolDefinition(
            name: "tool_alpha",
            description: "Alpha",
            inputSchemaData: try JSONSerialization.data(withJSONObject: ["type": "object"]),
            execute: { args, callID in
                ledger.recordStart(toolName: "tool_alpha", callID: callID, arguments: args)
                ledger.recordCompletion(callID: callID, resultText: "alpha-ok")
                return HanlinAISDKToolExecutionOutput(modelText: "alpha-ok")
            }
        )
        let toolB = HanlinAISDKToolDefinition(
            name: "tool_beta",
            description: "Beta",
            inputSchemaData: try JSONSerialization.data(withJSONObject: ["type": "object"]),
            execute: { args, callID in
                ledger.recordStart(toolName: "tool_beta", callID: callID, arguments: args)
                ledger.recordCompletion(callID: callID, resultText: "beta-ok")
                return HanlinAISDKToolExecutionOutput(modelText: "beta-ok")
            }
        )

        let emulator = StatefulProviderEmulator(
            profile: .anthropicNative,
            scenarioName: "AnthropicParallelToolUse",
            roundExpectations: [
                0: RoundExpectation(),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [
                        ExpectedToolCall(id: "call-ant-a", name: "tool_alpha"),
                        ExpectedToolCall(id: "call-ant-b", name: "tool_beta")
                    ],
                    expectedToolResults: [
                        ExpectedToolResult(callID: "call-ant-a", name: "tool_alpha", expectedSubstring: "alpha-ok"),
                        ExpectedToolResult(callID: "call-ant-b", name: "tool_beta", expectedSubstring: "beta-ok")
                    ]
                )
            ],
            roundResponses: [
                0: .sseChunks(ProviderResponseFixtures.anthropicToolUseChunks(calls: [
                    (id: "call-ant-a", name: "tool_alpha", arguments: "{}"),
                    (id: "call-ant-b", name: "tool_beta", arguments: "{}")
                ])),
                1: .sseChunks(ProviderResponseFixtures.anthropicTextChunks(text: "Both Anthropic tools succeeded."))
            ],
            ledger: ledger
        )

        let engine = try Self.makeEngine(profile: .anthropicNative, emulator: emulator)
        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Run parallel tools")],
            baseSystemPrompt: "Assistant",
            tools: [toolA, toolB],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: ["tool_alpha", "tool_beta"]) }
        )

        var finalAns = ""
        for try await event in stream {
            if case .textDelta(let text) = event { finalAns += text }
        }

        #expect(finalAns.contains("Both Anthropic tools succeeded"))
        #expect(emulator.requestCount == 2)
        try ledger.assertSingleExecutions()
    }

    @Test("Anthropic Native: Tool result error is properly flagged and recovered")
    func testAnthropicToolResultError() async throws {
        let failingTool = HanlinAISDKToolDefinition(
            name: "failing_tool",
            description: "Failing tool",
            inputSchemaData: try JSONSerialization.data(withJSONObject: ["type": "object"]),
            execute: { _, callID in
                HanlinAISDKToolExecutionOutput(modelText: "Specific failure message", isError: true)
            }
        )

        let emulator = StatefulProviderEmulator(
            profile: .anthropicNative,
            scenarioName: "AnthropicToolResultError",
            roundExpectations: [
                0: RoundExpectation(),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-err-1", name: "failing_tool")],
                    expectedToolResults: [ExpectedToolResult(callID: "call-err-1", name: "failing_tool", expectedSubstring: "Specific failure message", isError: true)]
                )
            ],
            roundResponses: [
                0: .sseChunks(ProviderResponseFixtures.anthropicToolUseChunks(
                    calls: [(id: "call-err-1", name: "failing_tool", arguments: "{}")],
                    id: "c-ant-err"
                )),
                1: .sseChunks(ProviderResponseFixtures.anthropicTextChunks(text: "Recovered from Anthropic tool error.", id: "c-ant-rec"))
            ]
        )

        let engine = try Self.makeEngine(profile: .anthropicNative, emulator: emulator)
        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Test tool error")],
            baseSystemPrompt: "Assistant",
            tools: [failingTool],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: ["failing_tool"]) }
        )

        var finalAns = ""
        for try await event in stream {
            if case .textDelta(let text) = event { finalAns += text }
        }

        #expect(finalAns.contains("Recovered from Anthropic tool error"))
        #expect(emulator.requestCount == 2)
    }

    // MARK: - Google Native Thought Signature Tests (Section 15)

    @Test("Google Native: Sequential thoughtSignature preserved exactly across requests")
    func testGoogleSequentialThoughtSignature() async throws {
        try await testS10R4GoogleNativeThoughtSignature()
    }

    @Test("Google Native: Parallel thoughtSignature placement on first functionCall part only")
    func testGoogleParallelThoughtSignaturePlacement() async throws {
        let toolA = HanlinAISDKToolDefinition(
            name: "tool_alpha",
            description: "Alpha",
            inputSchemaData: try JSONSerialization.data(withJSONObject: ["type": "object"]),
            execute: { _, _ in HanlinAISDKToolExecutionOutput(modelText: "alpha-ok") }
        )
        let toolB = HanlinAISDKToolDefinition(
            name: "tool_beta",
            description: "Beta",
            inputSchemaData: try JSONSerialization.data(withJSONObject: ["type": "object"]),
            execute: { _, _ in HanlinAISDKToolExecutionOutput(modelText: "beta-ok") }
        )

        let emulator = StatefulProviderEmulator(
            profile: .googleNative,
            scenarioName: "GoogleParallelThoughtSignaturePlacement",
            roundExpectations: [
                0: RoundExpectation(),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [
                        ExpectedToolCall(id: "tool_alpha", name: "tool_alpha"),
                        ExpectedToolCall(id: "tool_beta", name: "tool_beta")
                    ],
                    expectedToolResults: [
                        ExpectedToolResult(callID: "tool_alpha", name: "tool_alpha", expectedSubstring: "alpha-ok"),
                        ExpectedToolResult(callID: "tool_beta", name: "tool_beta", expectedSubstring: "beta-ok")
                    ],
                    customValidator: { req, round, profile in
                        let body = ProviderRequestValidators.extractBody(from: req)
                        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                        let contents = json?["contents"] as? [[String: Any]] ?? []
                        let modelMsgs = contents.filter { ($0["role"] as? String) == "model" }
                        for msg in modelMsgs {
                            let parts = msg["parts"] as? [[String: Any]] ?? []
                            for p in parts {
                                if let fc = p["functionCall"] as? [String: Any],
                                   (fc["name"] as? String) == "tool_beta" {
                                    // Sibling call tool_beta MUST NOT have a synthesized thoughtSignature!
                                    let sig = p["thoughtSignature"] as? String
                                    if sig != nil {
                                        throw ConformanceProtocolError(
                                            category: .SIGNATURE_STATE,
                                            ownership: .swiftAISDKDependency,
                                            round: round,
                                            message: "Sibling functionCall 'tool_beta' had unexpected synthesized thoughtSignature '\(sig!)'."
                                        )
                                    }
                                }
                            }
                        }
                    }
                )
            ],
            roundResponses: [
                0: .sseChunks(ProviderResponseFixtures.googleFunctionCallChunks(calls: [
                    (name: "tool_alpha", args: [:], thoughtSignature: "sig-first-only"),
                    (name: "tool_beta", args: [:], thoughtSignature: nil)
                ])),
                1: .sseChunks(ProviderResponseFixtures.googleTextChunks(text: "Google parallel placement validated."))
            ]
        )

        let engine = try Self.makeEngine(profile: .googleNative, emulator: emulator)
        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Run parallel Google tools")],
            baseSystemPrompt: "Assistant",
            tools: [toolA, toolB],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: ["tool_alpha", "tool_beta"]) }
        )

        var finalAns = ""
        for try await event in stream {
            if case .textDelta(let text) = event { finalAns += text }
        }

        #expect(finalAns.contains("Google parallel placement validated"))
        #expect(emulator.requestCount == 2)
    }

    // MARK: - S14: Large Tool Result

    @Test("S14: Large deterministic tool result containing Unicode, newlines, and structured JSON")
    func testS14LargeToolResult() async throws {
        var largeContent = "--- START LARGE TOOL RESULT ---\n"
        for i in 1...200 {
            largeContent += "Line \(i): שלום עולם! Unicode: 🚀, special: \\\"quoted\\\" and \n"
        }
        largeContent += "--- END LARGE TOOL RESULT ---"

        let largeTool = HanlinAISDKToolDefinition(
            name: "fetch_large_data",
            description: "Fetches large text",
            inputSchemaData: try JSONSerialization.data(withJSONObject: ["type": "object"]),
            execute: { _, _ in
                HanlinAISDKToolExecutionOutput(modelText: largeContent)
            }
        )

        let emulator = StatefulProviderEmulator(
            profile: .openAINativeChat,
            scenarioName: "S14_LargeToolResult",
            roundExpectations: [
                0: RoundExpectation(),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-large-1", name: "fetch_large_data")],
                    expectedToolResults: [ExpectedToolResult(callID: "call-large-1", name: "fetch_large_data", expectedSubstring: "START LARGE TOOL RESULT")]
                )
            ],
            roundResponses: [
                0: .sseChunks(ProviderResponseFixtures.openAIChatToolCallChunks(
                    calls: [(id: "call-large-1", name: "fetch_large_data", arguments: "{}")],
                    id: "c1"
                )),
                1: .sseChunks(ProviderResponseFixtures.openAIChatTextChunks(text: "Large data processed.", id: "c2"))
            ]
        )

        let engine = try Self.makeEngine(profile: .openAINativeChat, emulator: emulator)

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Get large data")],
            baseSystemPrompt: "Assistant",
            tools: [largeTool],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: ["fetch_large_data"]) }
        )

        for try await _ in stream {}

        #expect(emulator.requestCount == 2)
        let round1Req = emulator.allBodies[1]
        let round1Str = String(decoding: round1Req, as: UTF8.self)
        #expect(round1Str.contains("Line 200"))
        #expect(round1Str.contains("שלום עולם"))
    }

    // MARK: - S15: Empty Tool Result

    @Test("S15: Empty tool result succeeds and continuation remains valid without mismatch")
    func testS15EmptyToolResult() async throws {
        let emptyTool = HanlinAISDKToolDefinition(
            name: "noop_tool",
            description: "Noop",
            inputSchemaData: try JSONSerialization.data(withJSONObject: ["type": "object"]),
            execute: { _, _ in
                HanlinAISDKToolExecutionOutput(modelText: "")
            }
        )

        let emulator = StatefulProviderEmulator(
            profile: .openAINativeChat,
            scenarioName: "S15_EmptyToolResult",
            roundExpectations: [
                0: RoundExpectation(),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-empty-1", name: "noop_tool")],
                    expectedToolResults: [ExpectedToolResult(callID: "call-empty-1", name: "noop_tool", expectedContent: .exact(""))]
                )
            ],
            roundResponses: [
                0: .sseChunks(ProviderResponseFixtures.openAIChatToolCallChunks(
                    calls: [(id: "call-empty-1", name: "noop_tool", arguments: "{}")],
                    id: "c1"
                )),
                1: .sseChunks(ProviderResponseFixtures.openAIChatTextChunks(text: "Noop completed.", id: "c2"))
            ]
        )

        let engine = try Self.makeEngine(profile: .openAINativeChat, emulator: emulator)

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Run noop")],
            baseSystemPrompt: "Assistant",
            tools: [emptyTool],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: ["noop_tool"]) }
        )

        var text = ""
        for try await event in stream {
            if case .textDelta(let delta) = event { text += delta }
        }

        #expect(text.contains("Noop completed"))
        #expect(emulator.requestCount == 2)
    }

    // MARK: - S16: Hebrew / Unicode Conversation

    @Test("S16: Hebrew prompt, Hebrew arguments, Hebrew result, and Hebrew final response")
    func testS16HebrewUnicodeConversation() async throws {
        let hebrewTool = HanlinAISDKToolDefinition(
            name: "תרגום",
            description: "כלי תרגום לעברית",
            inputSchemaData: try JSONSerialization.data(withJSONObject: [
                "type": "object",
                "properties": ["מילה": ["type": "string"]]
            ]),
            execute: { args, _ in
                HanlinAISDKToolExecutionOutput(modelText: "שלום משמעו שלום ושלווה")
            }
        )

        let emulator = StatefulProviderEmulator(
            profile: .openAINativeChat,
            scenarioName: "S16_HebrewUnicode",
            roundExpectations: [
                0: RoundExpectation(
                    customValidator: { req, _, _ in
                        let body = String(decoding: ProviderRequestValidators.extractBody(from: req), as: UTF8.self)
                        #expect(body.contains("מה המשמעות של שלום"), "Outgoing request must preserve Hebrew user prompt.")
                    }
                ),
                1: RoundExpectation(
                    expectedAssistantToolCalls: [ExpectedToolCall(id: "call-heb-1", name: "תרגום")],
                    expectedToolResults: [ExpectedToolResult(callID: "call-heb-1", name: "תרגום", expectedSubstring: "שלום ושלווה")]
                )
            ],
            roundResponses: [
                0: .sseChunks(ProviderResponseFixtures.openAIChatToolCallChunks(
                    calls: [(id: "call-heb-1", name: "תרגום", arguments: "{\"מילה\":\"שלום\"}")],
                    id: "c1"
                )),
                1: .sseChunks(ProviderResponseFixtures.openAIChatTextChunks(text: "המשמעות היא שלום ושלווה.", id: "c2"))
            ]
        )

        let engine = try Self.makeEngine(profile: .openAINativeChat, emulator: emulator)

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "מה המשמעות של שלום?")],
            baseSystemPrompt: "עוזר שיחה בעברית",
            tools: [hebrewTool],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: ["תרגום"]) }
        )

        var finalAnswer = ""
        for try await event in stream {
            if case .textDelta(let text) = event { finalAnswer += text }
        }

        #expect(finalAnswer.contains("שלום ושלווה"))
        #expect(emulator.requestCount == 2)
    }
}

// MARK: - Thread Safe Array Helper

private final class ManagedAtomicArray<T>: @unchecked Sendable {
    private var elements: [T] = []
    private let lock = NSLock()

    func append(_ element: T) {
        lock.lock()
        defer { lock.unlock() }
        elements.append(element)
    }

    var all: [T] {
        lock.lock()
        defer { lock.unlock() }
        return elements
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return elements.count
    }
}
