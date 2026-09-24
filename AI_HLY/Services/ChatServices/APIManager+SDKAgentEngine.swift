import Foundation
import SwiftData
import HanlinChatCore
import HanlinPlatformContracts

extension APIManager {
    func processSDKAgentEngine(
        formattedMessages: [[String: Any]],
        modelInfo: AllModels,
        chatConfig: HanlinChatModelConfiguration,
        preparedAssistantTools: AssistantToolBridge.PreparedTools,
        session: AssistantCapabilitySession,
        currentLanguage: String,
        currentLanguagePrefix: Bool,
        continuation: AsyncThrowingStream<StreamData, Error>.Continuation
    ) async throws {
        var systemParts: [String] = []
        var sdkMessages: [HanlinAISDKMessage] = []

        for msg in formattedMessages {
            let role = msg["role"] as? String ?? ""
            let content = msg["content"] as? String ?? ""
            if role == "system" || role == "developer" {
                if !content.isEmpty && !systemParts.contains(content) {
                    systemParts.append(content)
                }
            } else if role == "assistant" {
                sdkMessages.append(HanlinAISDKMessage(role: .assistant, text: content))
            } else {
                sdkMessages.append(HanlinAISDKMessage(role: .user, text: content))
            }
        }
        let baseSystemPrompt = systemParts.isEmpty ? nil : systemParts.joined(separator: "\n\n")

        let toolAdapter = HanlinAISDKToolAdapter(
            session: session,
            preparedTools: preparedAssistantTools,
            modelContext: self.context,
            currentLanguage: currentLanguage,
            progressSummaryRequired: modelInfo.agentCapabilities.supportsProgressSummaryField,
            supportsReportProgress: modelInfo.agentCapabilities.supportsReportProgressTool,
            callbacks: HanlinAISDKToolAdapter.Callbacks(
                onStreamData: { continuation.yield($0) },
                onAgentEvent: { continuation.yield(StreamData(agentEvents: [$0])) },
                onProgressMessage: { continuation.yield(StreamData(agentEvents: [.progressMessage($0)])) },
                currentReasoningSummary: { [weak self] in self?.toolMessageReasoning }
            ),
            reportProgressController: self.reportProgressController,
            diagnosticsRecorder: self.agentDiagnosticsRecorder
        )

        let toolDefinitions = try toolAdapter.allToolDefinitions()
        let chatEngine = self.chatEngineFactory()
        let fetch = HanlinAISDKProviderFactory.makeFetch(sessionConfiguration: chatEngine.sessionConfiguration)
        let agentEngine = try HanlinAISDKAgentEngine(configuration: chatConfig, fetch: fetch)

        let sdkStream = try await agentEngine.stream(
            messages: sdkMessages,
            baseSystemPrompt: baseSystemPrompt,
            tools: toolDefinitions,
            prepareStep: {
                toolAdapter.prepareStep()
            }
        )

        var currentStepID: UUID?

        for try await event in sdkStream {
            if self.isCancelled {
                continuation.finish()
                self.isCancelled = false
                await self.agentDiagnosticsRecorder?.complete(status: "cancelled")
                return
            }

            switch event {
            case .runStarted:
                continuation.yield(StreamData(operationalState: currentLanguagePrefix ? "正在处理" : "Processing"))

            case .stepStarted(let index, let prep):
                let stepID = await self.agentDiagnosticsRecorder?.beginRound(
                    index: index,
                    trigger: index <= 1 ? "initialUserRequest" : "continueAfterToolResult",
                    requestData: Data(),
                    loadedSkillIDs: prep.loadedSkillIDs,
                    modelVisibleToolAliases: prep.activeToolAliases,
                    modelVisibleToolCount: prep.activeToolAliases.count,
                    modelVisibleSchemaBytes: prep.visibleSchemaBytes,
                    providerID: chatConfig.company ?? "Unknown",
                    modelID: chatConfig.modelID
                )
                currentStepID = stepID
                toolAdapter.currentRoundID = stepID
                continuation.yield(StreamData(operationalState: currentLanguagePrefix ? "等待模型响应" : "Waiting for model response"))

            case .textDelta(let text):
                if self.toolMessage == nil { self.toolMessage = "" }
                self.toolMessage?.append(text)
                if let stepID = currentStepID {
                    self.agentDiagnosticsRecorder?.recordStreamEvent(
                        roundID: stepID,
                        visibleContent: text,
                        visibleReasoningSummary: nil,
                        isMeaningful: true
                    )
                }
                continuation.yield(StreamData(content: text))

            case .reasoningDelta(let text):
                if self.toolMessageReasoning == nil { self.toolMessageReasoning = "" }
                self.toolMessageReasoning?.append(text)
                if let stepID = currentStepID {
                    self.agentDiagnosticsRecorder?.recordStreamEvent(
                        roundID: stepID,
                        visibleContent: nil,
                        visibleReasoningSummary: text,
                        isMeaningful: true
                    )
                }
                continuation.yield(StreamData(reasoning: text))

            case .toolCallArgumentsStarted(let id, let name):
                continuation.yield(StreamData(operationalState: currentLanguagePrefix ? "正在使用工具" : "Using Tools"))

            case .toolCallArgumentsDelta(let id, let delta):
                continuation.yield(StreamData(agentEvents: [.toolCallArgumentsDelta(id: id, delta: delta)]))

            case .toolCall(let call):
                break

            case .toolResult(let callID, let name, let modelText, let resultRef):
                break

            case .stepFinished(let index, let finishReason, let usage, let meaningfulCount):
                if let stepID = currentStepID {
                    let tokenUsage = AgentTokenUsage(
                        inputTokens: usage.inputTokens,
                        outputTokens: usage.outputTokens,
                        reasoningTokens: usage.reasoningTokens,
                        cachedInputTokens: usage.cachedInputTokens,
                        totalTokens: usage.totalTokens,
                        source: .providerReported
                    )
                    await self.agentDiagnosticsRecorder?.finishRound(
                        roundID: stepID,
                        finishReason: finishReason,
                        usage: tokenUsage,
                        meaningfulEventCount: meaningfulCount
                    )
                }

            case .finished(let reason, let usage):
                await self.agentDiagnosticsRecorder?.complete(status: "completed")
                continuation.yield(StreamData(content: "\n\n"))
                continuation.finish()
                return

            case .cancelled:
                await self.agentDiagnosticsRecorder?.complete(status: "cancelled")
                continuation.finish()
                return
            }
        }

        await self.agentDiagnosticsRecorder?.complete(status: "completed")
        continuation.finish()
    }
}
