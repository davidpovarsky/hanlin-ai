import Foundation
import Testing
import HanlinPlatformContracts
@testable import AI_Hanlin

@MainActor
@Suite("Classic Source-First Chat Restoration & Agent Capability Verification", .serialized)
struct ClassicChatRestorationTests {

    @Test("Text models with failed or unverified capability probes never route to images/generations")
    func modelExecutionRoutingNeverRoutesTextModelToImageGen() {
        // 1. nvidia/nemotron-3-ultra-550b-a55b:free with failed probe (supportsTextGen: false, supportsImageGen: false)
        // must route to .remoteText, NEVER .remoteImageGeneration
        let nemotronRoute = APIManager.resolveModelExecutionRoute(
            company: "OPENROUTER",
            modelName: "nvidia/nemotron-3-ultra-550b-a55b:free",
            supportsTextGen: false,
            supportsImageGen: false
        )
        #expect(nemotronRoute == .remoteText)
        #expect(!ModelRefreshService.isKnownImageOnlyModelID("nvidia/nemotron-3-ultra-550b-a55b:free"))

        // 2. Explicit image generation model routes to .remoteImageGeneration
        let dalleRoute = APIManager.resolveModelExecutionRoute(
            company: "OPENAI",
            modelName: "dall-e-3",
            supportsTextGen: false,
            supportsImageGen: true
        )
        #expect(dalleRoute == .remoteImageGeneration)
        #expect(ModelRefreshService.isKnownImageOnlyModelID("dall-e-3"))
        #expect(ModelRefreshService.isKnownImageOnlyModelID("cogview-4"))

        // 3. Local models always route to .localText
        let localRoute = APIManager.resolveModelExecutionRoute(
            company: "LOCAL",
            modelName: "qwen-local",
            supportsTextGen: true,
            supportsImageGen: false
        )
        #expect(localRoute == .localText)

        // 4. Text models with supportsTextGen = true route to .remoteText
        let textRoute = APIManager.resolveModelExecutionRoute(
            company: "OPENAI",
            modelName: "gpt-4o",
            supportsTextGen: true,
            supportsImageGen: false
        )
        #expect(textRoute == .remoteText)
    }

    @Test("Image generation diagnostics report HTTP status and redacted error, and decode both URL and b64_json")
    func imageGenerationErrorDiagnosticsAndBase64Decoding() throws {
        let errorJSON = """
        {
          "error": {
            "message": "Model nvidia/nemotron-3-ultra-550b-a55b:free does not support image generation with key sk-secret1234567890abcdef and Bearer secret_token_xyz"
          }
        }
        """.data(using: .utf8)!

        let errorMessage = APIManager.buildImageGenerationFailureMessage(
            statusCode: 404,
            responseData: errorJSON,
            modelName: "nvidia/nemotron-3-ultra-550b-a55b:free",
            company: "OPENROUTER",
            isChinese: false
        )
        #expect(errorMessage.contains("nvidia/nemotron-3-ultra-550b-a55b:free"))
        #expect(errorMessage.contains("HTTP 404"))
        #expect(errorMessage.contains("does not support image generation"))
        #expect(!errorMessage.contains("sk-secret1234567890abcdef"))
        #expect(!errorMessage.contains("secret_token_xyz"))

        // Verify URL payload extraction
        let urlPayload: [String: Any] = [
            "data": [
                [
                    "url": "https://example.com/generated.png",
                    "revised_prompt": "A serene mountain landscape"
                ]
            ]
        ]
        let extractedURL = APIManager.extractGeneratedImagePayload(from: urlPayload, company: "OPENAI")
        #expect(extractedURL.urlString == "https://example.com/generated.png")
        #expect(extractedURL.imageData == nil)

        // Verify base64 payload extraction
        let sampleBytes = Data([0x89, 0x50, 0x4E, 0x47])
        let b64String = sampleBytes.base64EncodedString()
        let b64Payload: [String: Any] = [
            "data": [
                [
                    "b64_json": b64String,
                    "revised_prompt": "Base64 rendered icon"
                ]
            ]
        ]
        let extractedB64 = APIManager.extractGeneratedImagePayload(from: b64Payload, company: "OPENAI")
        #expect(extractedB64.urlString == nil)
        #expect(extractedB64.imageData == sampleBytes)
    }

    @Test("ToolResultPresentationCoordinator distinguishes text-only tools from truly empty results")
    func toolResultPresentationCoordinatorTruthTable() {
        var cardCapableProfile = ToolPresentationProfile.generic(toolName: "search_online")
        cardCapableProfile.result = .init(rendererKind: .modernNative, supportsCard: true)
        cardCapableProfile.resultDisplayPolicy = .modelControlled

        let callWithCardRequest = AgentToolCall.parse(
            id: "call_search_1",
            name: "search_online",
            argumentsJSON: #"{"query":"SwiftUI","result_presentation":"card"}"#,
            presentationProfile: cardCapableProfile
        )

        // 1. Tool succeeded with modelText but no UI card payload -> .noUserFacingCardPayload (NEVER .emptyResult)
        let textSuccessDecision = ToolResultPresentationCoordinator.decide(
            call: callWithCardRequest,
            profile: cardCapableProfile,
            hasPayload: false,
            hasModelText: true,
            isError: false
        )
        #expect(!textSuccessDecision.shouldPresent)
        #expect(textSuccessDecision.suppressionReason == ToolResultSuppressionReason.noUserFacingCardPayload)
        #expect(textSuccessDecision.suppressionReason != ToolResultSuppressionReason.emptyResult)

        // 2. Tool returned neither UI payload nor modelText -> .emptyResult
        let trulyEmptyDecision = ToolResultPresentationCoordinator.decide(
            call: callWithCardRequest,
            profile: cardCapableProfile,
            hasPayload: false,
            hasModelText: false,
            isError: false
        )
        #expect(!trulyEmptyDecision.shouldPresent)
        #expect(trulyEmptyDecision.suppressionReason == ToolResultSuppressionReason.emptyResult)

        // 3. Tool with UI card payload -> presents card
        let cardDecision = ToolResultPresentationCoordinator.decide(
            call: callWithCardRequest,
            profile: cardCapableProfile,
            hasPayload: true,
            hasModelText: true,
            isError: false
        )
        #expect(cardDecision.shouldPresent)
        #expect(cardDecision.suppressionReason == nil)

        // 4. Text-only tool profile without result UI support -> .toolDoesNotSupportResultUI
        var textOnlyProfile = ToolPresentationProfile.generic(toolName: "read_web_page")
        textOnlyProfile.result = .init(rendererKind: .modernNative, supportsCard: false)
        textOnlyProfile.resultDisplayPolicy = .never
        let readCall = AgentToolCall.parse(
            id: "call_read_1",
            name: "read_web_page",
            argumentsJSON: #"{"url":"https://example.com"}"#,
            presentationProfile: textOnlyProfile
        )
        let textOnlyDecision = ToolResultPresentationCoordinator.decide(
            call: readCall,
            profile: textOnlyProfile,
            hasPayload: false,
            hasModelText: true,
            isError: false
        )
        #expect(!textOnlyDecision.shouldPresent)
        #expect(textOnlyDecision.suppressionReason == ToolResultSuppressionReason.toolDoesNotSupportResultUI)
    }

    @Test("ProgressSummarySanitizer rejects raw chain-of-thought and preserves concise summaries")
    func progressSummarySanitizerRejectsRawChainOfThought() {
        let leakedCoT1 = "Thinking Process: 1. Understand the User's Request: The user wants to know what tools are available."
        let leakedCoT2 = "Let's think step by step: First, we should call tool_search."
        let leakedCoT3 = "1. Understand the goal\n2. Analyze the constraints\n3. Formulate response"

        #expect(ProgressSummarySanitizer.looksLikeRawChainOfThought(leakedCoT1))
        #expect(ProgressSummarySanitizer.looksLikeRawChainOfThought(leakedCoT2))
        #expect(ProgressSummarySanitizer.looksLikeRawChainOfThought(leakedCoT3))

        #expect(ProgressSummarySanitizer.sanitizeProviderReasoningSummary(leakedCoT1) == nil)
        #expect(ProgressSummarySanitizer.sanitizeProviderReasoningSummary(leakedCoT2) == nil)

        let conciseSummary = "Checking available runtime capabilities"
        #expect(!ProgressSummarySanitizer.looksLikeRawChainOfThought(conciseSummary))
        #expect(ProgressSummarySanitizer.sanitizeProviderReasoningSummary(conciseSummary) == conciseSummary)
    }

    @Test("Monotonic terminal state in AgentEventAccumulator and idempotent AgentDiagnosticsRecorder completion")
    func monotonicTerminalStateAndIdempotentDiagnosticsCompletion() async throws {
        var accumulator = AgentEventAccumulator(run: AgentRun(groupID: UUID()))
        let initialCall = AgentToolCall.parse(
            id: "initial_call_1",
            name: "get_runtime_capabilities",
            argumentsJSON: "{}"
        )
        accumulator.apply(.toolCallStarted(initialCall))
        accumulator.apply(.runCompleted)

        #expect(accumulator.run.status == .completed)
        let stepCountAtCompletion = accumulator.run.steps.count
        let itemCountAtCompletion = accumulator.run.transcriptItems.count

        // Late events after terminal state must be ignored
        let lateCall = AgentToolCall.parse(
            id: "late_call_1",
            name: "execute_local_python_code",
            argumentsJSON: #"{"source":"print(1)"}"#
        )
        accumulator.apply(.toolCallStarted(lateCall))
        accumulator.apply(.runFailed(AgentSafeError(message: "Late error")))

        #expect(accumulator.run.status == .completed)
        #expect(accumulator.run.steps.count == stepCountAtCompletion)
        #expect(accumulator.run.transcriptItems.count == itemCountAtCompletion)

        // AgentDiagnosticsRecorder idempotent complete() must NOT overwrite completed status or record late error
        let recorder = try #require(
            await AgentDiagnosticsRecorder.start(
                runID: UUID(),
                groupID: UUID(),
                providerID: "openrouter",
                modelID: "nvidia/nemotron-3-ultra-550b-a55b:free"
            )
        )
        await recorder.complete(status: "completed")
        await recorder.complete(status: "completed")
        await recorder.complete(status: "failed", error: "late stream callback")

        let session = await recorder.session
        #expect(session.status == "completed")
        #expect(session.isComplete)
        #expect(session.error == nil)
    }

    @Test("manage_mcp_servers tool and mcp_servers skill are registered, discoverable, and report all 5 state dimensions")
    func manageMCPServersToolRegistrationAndStatusExecution() async throws {
        let catalog = NativeToolCatalog.shared
        catalog.ensureBuiltinsRegistered()

        let mcpTool = try #require(catalog.tool(named: "manage_mcp_servers", enabledOnly: false))
        #expect(mcpTool is ManageMCPServersTool)

        // Check system skills
        let skills = SystemSkillsProvider.systemSkills(codeEnabled: true)
        let mcpSkill = try #require(skills.first(where: { $0.id.rawValue == "mcp_servers" }))
        #expect(mcpSkill.preferredToolIDs.contains("manage_mcp_servers"))
        #expect(mcpSkill.preferredToolIDs.contains("list_tools"))
        #expect(mcpSkill.preferredToolIDs.contains("get_runtime_capabilities"))

        let codeSkill = try #require(skills.first(where: { $0.id.rawValue == "code" }))
        #expect(codeSkill.preferredToolIDs.first == "execute_local_python_code")
        #expect(codeSkill.preferredToolIDs.contains("get_runtime_capabilities"))
        #expect(codeSkill.preferredToolIDs.contains("manage_runtime_packages"))
        #expect(codeSkill.preferredToolIDs.contains("execute_skill_resource"))

        // Execute status action on ManageMCPServersTool
        let context = NativeToolExecutionContext(localeIdentifier: "en_US", chatID: "test-chat-id")
        let statusResult = await mcpTool.execute(argumentsJSON: #"{"action":"status"}"#, context: context)
        #expect(statusResult.outcome == .succeeded)
        #expect(statusResult.modelText.contains("global_mcp_enabled"))
        #expect(statusResult.modelText.contains("server_installed"))
        #expect(statusResult.modelText.contains("server_enabled"))
        #expect(statusResult.modelText.contains("selected_for_current_chat"))
        #expect(statusResult.modelText.contains("worker_running"))

        // Execute list action on ManageMCPServersTool
        let listResult = await mcpTool.execute(argumentsJSON: #"{"action":"list"}"#, context: context)
        #expect(listResult.outcome == .succeeded)
        #expect(listResult.modelText.contains("global_mcp_enabled"))

        // Verify GetRuntimeCapabilitiesTool advertises manage_mcp_servers
        let capabilitiesTool = GetRuntimeCapabilitiesTool()
        let capResult = await capabilitiesTool.execute(argumentsJSON: "{}", context: context)
        #expect(capResult.outcome == .succeeded)
        #expect(capResult.modelText.contains("manage_mcp_servers"))

        // Verify all preferredToolIDs across all system skills (including mcp_servers and code) resolve in canonical authority
        let legacySources = LegacyToolCanonicalAdapter.sources()
        let prepared = try await AssistantToolBridge.prepare(scope: .nativeOnly, legacySources: legacySources)
        for skill in skills {
            for toolID in skill.preferredToolIDs {
                let resolution = prepared.authority.resolution(alias: toolID)
                #expect(resolution != nil, "Skill '\(skill.id.rawValue)' preferredToolID '\(toolID)' must resolve in canonical authority")
            }
        }
    }

    @Test("ChatView dynamic bottom padding adapts to measured composer height and attachments")
    func dynamicBottomPaddingCalculation() {
        let baseCompact = ChatView.calculateDynamicBottomPadding(
            measuredComposerHeight: 56,
            hasURLs: false,
            hasImages: false,
            hasDocuments: false,
            showPhotoSourceOptions: false,
            hasPrompts: false
        )
        let expandedMultiline = ChatView.calculateDynamicBottomPadding(
            measuredComposerHeight: 132,
            hasURLs: false,
            hasImages: false,
            hasDocuments: false,
            showPhotoSourceOptions: false,
            hasPrompts: false
        )
        let fallbackWithAttachments = ChatView.calculateDynamicBottomPadding(
            measuredComposerHeight: 0,
            hasURLs: true,
            hasImages: true,
            hasDocuments: false,
            showPhotoSourceOptions: false,
            hasPrompts: true
        )

        #expect(baseCompact >= 96)
        #expect(expandedMultiline > baseCompact)
        #expect(fallbackWithAttachments > 116)
    }
}
