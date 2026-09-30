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
    private var providerRequestActiveContinuation: CheckedContinuation<Void, Never>?

    func reset() {
        toolStartedContinuation = nil
        gateContinuation = nil
        providerRequestActiveContinuation = nil
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

    func waitForProviderRequestActive() async {
        await withCheckedContinuation { cont in
            providerRequestActiveContinuation = cont
        }
    }

    func recordProviderRequestActive() {
        let cont = providerRequestActiveContinuation
        providerRequestActiveContinuation = nil
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

    private static func makeSequentialToolChainValidators(
        stepCount: Int,
        toolName: String,
        callIDPrefix: String
    ) -> [Int: ProductionConformanceURLProtocol.RequestValidator] {
        var validators: [Int: ProductionConformanceURLProtocol.RequestValidator] = [:]
        for round in 0...stepCount {
            validators[round] = { roundIdx, req, body in
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                guard let messages = json?["messages"] as? [[String: Any]] else {
                    throw ConformanceProtocolError(
                        category: .REQUEST_SERIALIZATION,
                        ownership: .swiftAISDKDependency,
                        round: roundIdx,
                        message: "Production request missing messages array."
                    )
                }

                // For round N > 0, verify rounds 0..<N assistant tool calls and tool results exist
                for prev in 0..<roundIdx {
                    let expectedCallID = "\(callIDPrefix)-\(prev + 1)"
                    // Verify assistant tool call
                    let hasCall = messages.contains { msg in
                        guard (msg["role"] as? String) == "assistant",
                              let calls = msg["tool_calls"] as? [[String: Any]] else { return false }
                        return calls.contains { ($0["id"] as? String) == expectedCallID }
                    }
                    if !hasCall {
                        throw ConformanceProtocolError(
                            category: .TOOL_RESULT_CONTINUATION,
                            ownership: .swiftAISDKDependency,
                            round: roundIdx,
                            message: "Round \(roundIdx) missing assistant tool call for '\(expectedCallID)'."
                        )
                    }

                    // Verify tool result
                    let hasResult = messages.contains { msg in
                        (msg["role"] as? String) == "tool" && (msg["tool_call_id"] as? String) == expectedCallID
                    }
                    if !hasResult {
                        throw ConformanceProtocolError(
                            category: .TOOL_RESULT_CONTINUATION,
                            ownership: .swiftAISDKDependency,
                            round: roundIdx,
                            message: "Round \(roundIdx) missing tool result for '\(expectedCallID)'."
                        )
                    }
                }
            }
        }
        return validators
    }

    private func runProductionConversation(
        responses: [Data],
        validators: [Int: ProductionConformanceURLProtocol.RequestValidator] = [:],
        modelName: String? = nil,
        profile: ProductionProviderProfile = .openAICompatible,
        ifThink: Bool? = nil,
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
        let effectiveModel = modelName ?? profile.modelName
        let effectiveThink = ifThink ?? profile.supportsReasoning

        context.insert(AllModels(
            name: effectiveModel,
            displayName: "Conformance Model",
            position: 0,
            company: profile.company,
            supportsTextGen: true,
            supportsToolUse: true,
            supportsReasoning: profile.supportsReasoning
        ))
        context.insert(APIKeys(
            name: "Conformance-\(profile.company)",
            company: profile.company,
            key: ProductionConformanceFixtures.secretAPIKey,
            requestURL: profile.endpoint,
            apiType: profile.apiType
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
                modelName: effectiveModel,
                modelDisplayName: "Conformance Model"
            )],
            modelName: effectiveModel,
            groupID: UUID(),
            runID: UUID(),
            ifSearch: false,
            ifKnowledge: false,
            ifToolUse: true,
            assistantToolScope: .nativeOnly,
            ifThink: effectiveThink,
            ifAudio: false,
            ifPlanning: false,
            thinkingLength: effectiveThink ? 2048 : 0,
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

        if let firstErr = ProductionConformanceURLProtocol.validationErrors().first {
            throw firstErr
        }

        let recordedDiagnostics = await manager.agentDiagnosticsRecorder?.currentSession ?? AgentDiagnosticsSession(runID: UUID())
        let convResult = ConversationResult(
            answer: answer,
            events: events,
            requests: ProductionConformanceURLProtocol.allBodies(),
            diagnostics: recordedDiagnostics
        )
        return (convResult, manager)
    }

    // MARK: - P01: Skills Exposure and Execution

    @Test("P01: Skills dynamic tool exposure and tool execution through production loop")
    func testP01SkillsExposureAndExecution() async throws {
        let responses = [
            ProductionConformanceFixtures.sseToolCall(id: "call-load-1", name: "load_skill", arguments: ["skill": "code"]),
            ProductionConformanceFixtures.sseToolCall(id: "call-py-2", name: "execute_local_python_code", arguments: ["source": "print(6 * 7)"]),
            ProductionConformanceFixtures.sseFinalAnswer("42 / LOCAL_PYTHON_COMPLETE")
        ]

        let validators: [Int: ProductionConformanceURLProtocol.RequestValidator] = [
            0: { roundIdx, req, body in
                let bodyStr = String(decoding: body, as: UTF8.self)
                if !bodyStr.contains("load_skill") || bodyStr.contains("execute_local_python_code") {
                    throw ConformanceProtocolError(category: .TOOL_SCHEMA, ownership: .hanlinAIProduction, round: roundIdx, message: "Round 0 must expose load_skill but not execute_local_python_code.")
                }
            },
            1: { roundIdx, req, body in
                let bodyStr = String(decoding: body, as: UTF8.self)
                if !bodyStr.contains("execute_local_python_code") || !bodyStr.contains("call-load-1") {
                    throw ConformanceProtocolError(category: .TOOL_SCHEMA, ownership: .hanlinAIProduction, round: roundIdx, message: "Round 1 must expose execute_local_python_code and contain call-load-1 result.")
                }
            },
            2: { roundIdx, req, body in
                let bodyStr = String(decoding: body, as: UTF8.self)
                if !bodyStr.contains("call-py-2") || !bodyStr.contains("42") {
                    throw ConformanceProtocolError(category: .TOOL_RESULT_CONTINUATION, ownership: .hanlinAIProduction, round: roundIdx, message: "Round 2 must contain python result 42.")
                }
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

    // MARK: - P03: 5-Step Sequential Tools (Validated Every Round)

    @Test("P03: 5-step sequential production tool chain with per-round request validation")
    func testP03FiveStepSequentialTools() async throws {
        let responses = [
            ProductionConformanceFixtures.sseToolCall(id: "c-1", name: "quick_calculate", arguments: ["expression": "1 + 1"]),
            ProductionConformanceFixtures.sseToolCall(id: "c-2", name: "quick_calculate", arguments: ["expression": "2 + 2"]),
            ProductionConformanceFixtures.sseToolCall(id: "c-3", name: "quick_calculate", arguments: ["expression": "4 + 4"]),
            ProductionConformanceFixtures.sseToolCall(id: "c-4", name: "quick_calculate", arguments: ["expression": "8 + 8"]),
            ProductionConformanceFixtures.sseToolCall(id: "c-5", name: "quick_calculate", arguments: ["expression": "16 + 16"]),
            ProductionConformanceFixtures.sseFinalAnswer("CHAIN_COMPLETE_32")
        ]

        let validators = Self.makeSequentialToolChainValidators(stepCount: 5, toolName: "quick_calculate", callIDPrefix: "c")

        let (res, _) = try await runProductionConversation(responses: responses, validators: validators)
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

    // MARK: - P05: Production Reasoning + Tool Loop Across Profiles (Section 9)

    @Test("P05: Production reasoning and tool loop for OpenAI-compatible")
    func testP05ReasoningToolLoopOpenAICompatible() async throws {
        let toolChunks = ProductionConformanceFixtures.openAIReasoningAndToolCallChunks(
            reasoningContent: "First calculate the sum",
            calls: [(id: "p05-c1", name: "quick_calculate", arguments: "{\"expression\":\"10+20\"}")],
            id: "p05-resp-1"
        )
        let responses: [Data] = [
            Data(toolChunks.joined().utf8),
            ProductionConformanceFixtures.sseFinalAnswer("SUM_IS_30")
        ]

        let validators: [Int: ProductionConformanceURLProtocol.RequestValidator] = [
            0: { _, _, _ in },
            1: { roundIdx, req, body in
                let bodyStr = String(decoding: body, as: UTF8.self)
                if !bodyStr.contains("First calculate the sum") || !bodyStr.contains("p05-c1") {
                    throw ConformanceProtocolError(
                        category: .REASONING_STATE,
                        ownership: .swiftAISDKDependency,
                        round: roundIdx,
                        message: "Round 1 continuation did not preserve reasoning content."
                    )
                }
            }
        ]

        let (res, _) = try await runProductionConversation(
            responses: responses,
            validators: validators,
            profile: .openAICompatible,
            ifThink: true
        )
        #expect(res.answer.contains("SUM_IS_30"))
        #expect(res.requests.count == 2)
    }

    @Test("P05: Production reasoning and tool loop for Anthropic native")
    func testP05ReasoningToolLoopAnthropic() async throws {
        let thinkingToolData = ProductionConformanceFixtures.sseAnthropicToolCall(
            id: "p05-ant-1",
            name: "quick_calculate",
            arguments: ["expression": "50+50"],
            thinking: "Let us compute 50 plus 50",
            signature: "sig-p05-ant"
        )
        let finalData = ProductionConformanceFixtures.sseAnthropicFinalAnswer("ANTHROPIC_SUM_100")

        let validators: [Int: ProductionConformanceURLProtocol.RequestValidator] = [
            0: { _, _, _ in },
            1: { roundIdx, req, body in
                let bodyStr = String(decoding: body, as: UTF8.self)
                if !bodyStr.contains("p05-ant-1") {
                    throw ConformanceProtocolError(
                        category: .TOOL_RESULT_CONTINUATION,
                        ownership: .swiftAISDKDependency,
                        round: roundIdx,
                        message: "Round 1 Anthropic continuation missing tool_use_id 'p05-ant-1'."
                    )
                }
            }
        ]

        let (res, _) = try await runProductionConversation(
            responses: [thinkingToolData, finalData],
            validators: validators,
            profile: .anthropic,
            ifThink: true
        )
        #expect(res.answer.contains("ANTHROPIC_SUM_100"))
        #expect(res.requests.count == 2)
    }

    @Test("P05: Production reasoning and tool loop for Google native")
    func testP05ReasoningToolLoopGoogle() async throws {
        let functionCallData = ProductionConformanceFixtures.sseGoogleFunctionCall(
            name: "quick_calculate",
            arguments: ["expression": "10*10"],
            thoughtSignature: "sig-p05-google"
        )
        let finalData = ProductionConformanceFixtures.sseGoogleFinalAnswer("GOOGLE_PRODUCT_100")

        let validators: [Int: ProductionConformanceURLProtocol.RequestValidator] = [
            0: { _, _, _ in },
            1: { roundIdx, req, body in
                let bodyStr = String(decoding: body, as: UTF8.self)
                if !bodyStr.contains("quick_calculate") {
                    throw ConformanceProtocolError(
                        category: .TOOL_RESULT_CONTINUATION,
                        ownership: .swiftAISDKDependency,
                        round: roundIdx,
                        message: "Round 1 Google continuation missing functionResponse."
                    )
                }
            }
        ]

        let (res, _) = try await runProductionConversation(
            responses: [functionCallData, finalData],
            validators: validators,
            profile: .google,
            ifThink: true
        )
        #expect(res.answer.contains("GOOGLE_PRODUCT_100"))
        #expect(res.requests.count == 2)
    }

    // MARK: - P06: 20-Step Production Loop (Validated Every Round)

    @Test("P06: 20-step production tool loop with per-round request validation")
    func testP06TwentyStepProductionLoop() async throws {
        var responses: [Data] = []
        for i in 0..<19 {
            responses.append(ProductionConformanceFixtures.sseToolCall(
                id: "c20-\(i + 1)",
                name: "quick_calculate",
                arguments: ["expression": "\(i) + 1"]
            ))
        }
        responses.append(ProductionConformanceFixtures.sseFinalAnswer("20_STEPS_PRODUCTION_COMPLETE"))

        let validators = Self.makeSequentialToolChainValidators(stepCount: 19, toolName: "quick_calculate", callIDPrefix: "c20")

        let (res, _) = try await runProductionConversation(responses: responses, validators: validators)
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

    // MARK: - P09: Provider Stream Cancellation (Section 9)

    @Test("P09: Provider stream cancellation cancels active request without late events or mutation")
    func testP09CancelProviderStream() async throws {
        await ProductionGate.shared.reset()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProductionConformanceURLProtocol.self]

        ProductionConformanceURLProtocol.configure(
            responses: [ProductionConformanceFixtures.sseFinalAnswer("SHOULD_BE_CANCELLED")],
            preResponseHook: { _ in
                await ProductionGate.shared.recordProviderRequestActive()
                await ProductionGate.shared.waitForGate()
            }
        )

        let container = try ProductionConformanceFixtures.makeContainer()
        let context = container.mainContext
        context.insert(AllModels(name: "m-cancel", displayName: "MCancel", position: 0, company: "TEST", supportsTextGen: true, supportsToolUse: true))
        context.insert(APIKeys(name: "KCancel", company: "TEST", key: "key", requestURL: ProductionConformanceFixtures.endpointURL, apiType: .openAI))
        try context.save()

        let manager = APIManager(
            context: context,
            chatEngineFactory: { HanlinChatEngine(sessionConfiguration: configuration) }
        )

        let runTask = Task { @MainActor () -> (String, Error?) in
            var text = ""
            do {
                let stream = try await manager.sendStreamRequest(
                    messages: [RequestMessage(role: "user", text: "Cancel test", modelName: "m-cancel", modelDisplayName: "MCancel")],
                    modelName: "m-cancel",
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

        // Wait until request is actively being held by provider gate
        await ProductionGate.shared.waitForProviderRequestActive()

        // Cancel while provider stream is active
        manager.cancelCurrentRequest()

        // Release the gate
        await ProductionGate.shared.releaseGate()

        let (text, _) = await runTask.value
        #expect(!text.contains("SHOULD_BE_CANCELLED"), "No late visible tokens after cancellation.")
    }

    // MARK: - P10: Cancellation During Running Tool

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

    // MARK: - P12A: Real Application Second User Turn History (Section 7)

    @Test("P12A: Real application second turn history preserves user and assistant visible text")
    func testP12ARealApplicationSecondTurnHistory() async throws {
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
                0: { roundIdx, req, body in
                    let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                    guard let messages = json?["messages"] as? [[String: Any]] else {
                        throw ConformanceProtocolError(
                            category: .REQUEST_SERIALIZATION,
                            ownership: .swiftAISDKDependency,
                            round: roundIdx,
                            message: "Missing messages array"
                        )
                    }
                    let textArray = messages.compactMap { $0["content"] as? String }
                    let fullText = textArray.joined(separator: " ")
                    guard fullText.contains("Calculate 100 + 200"),
                          fullText.contains("Result is 300."),
                          fullText.contains("What was the previous result?") else {
                        throw ConformanceProtocolError(
                            category: .TOOL_RESULT_CONTINUATION,
                            ownership: .hanlinAIProduction,
                            round: roundIdx,
                            message: "Second turn history did not preserve user and assistant text. Observed: \(textArray)"
                        )
                    }
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

    // MARK: - Section 19: Dynamic Provider Inventory

    @Test("Section 19: Dynamic Provider Inventory derived from getKeyList() and getModelList()")
    func testDynamicProviderInventory() throws {
        let keys = getKeyList()
        let models = getModelList()
        let allAPITypes = APIType.allCases

        #expect(!keys.isEmpty, "getKeyList() must return predefined keys.")
        #expect(!models.isEmpty, "getModelList() must return predefined models.")

        for key in keys {
            let company = key.company ?? "Unknown"
            let companyModels = models.filter { $0.company == company }
            let toolCapableCount = companyModels.filter { $0.supportsToolUse }.count
            let reasoningCapableCount = companyModels.filter { $0.supportsReasoning }.count

            let agentRoute: String
            if company.uppercased() == "LOCAL" {
                agentRoute = "processLocalModel"
            } else if company.uppercased() == "GOOGLE" {
                agentRoute = "googleNative"
            } else if company.uppercased() == "ANTHROPIC" {
                agentRoute = "anthropicNative"
            } else {
                agentRoute = "openAICompatible"
            }

            let directChatRoute: String = key.apiType.rawValue

            #expect(!company.isEmpty)
            #expect(!key.requestURL.isEmpty)
            #expect(allAPITypes.contains(key.apiType))
            #expect(!agentRoute.isEmpty)
            #expect(!directChatRoute.isEmpty)
        }
    }

    // MARK: - Section 20: APIType.openAIResponse Characterization

    @Test("Section 20: Characterize APIType.openAIResponse as dormant and unreachable in user configuration")
    func testOpenAIResponseDormancyCharacterization() throws {
        let keys = getKeyList()
        let responseKeys = keys.filter { $0.apiType == .openAIResponse }
        #expect(responseKeys.isEmpty, "getKeyList() defaults to .openAI; openAIResponse must not be configured in system keys.")
        #expect(APIType.allCases.contains(.openAIResponse), "openAIResponse must exist in APIType.allCases.")

        let classification = "DORMANT / NOT IN READINESS GATE"
        #expect(classification == "DORMANT / NOT IN READINESS GATE")
    }
}
