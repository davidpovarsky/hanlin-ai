import Foundation
import HanlinChatCore
import SwiftData
@testable import AI_Hanlin

public enum ProductionProviderProfile: String, CaseIterable, Sendable {
    case openAINative
    case openAICompatible
    case openRouter
    case anthropic
    case google

    public var company: String {
        switch self {
        case .openAINative: return "OPENAI"
        case .openAICompatible: return "CONFORMANCE"
        case .openRouter: return "OPENROUTER"
        case .anthropic: return "ANTHROPIC"
        case .google: return "GOOGLE"
        }
    }

    public var apiType: APIType {
        switch self {
        case .openAINative, .openAICompatible, .openRouter:
            return .openAI
        case .anthropic:
            return .anthropic
        case .google:
            return .gemini
        }
    }

    public var endpoint: String {
        switch self {
        case .openAINative:
            return "https://api.openai.com/v1/chat/completions"
        case .openAICompatible:
            return "https://conformance.provider/v1/chat/completions"
        case .openRouter:
            return "https://openrouter.ai/api/v1/chat/completions"
        case .anthropic:
            return "https://api.anthropic.com/v1/messages"
        case .google:
            return "https://generativelanguage.googleapis.com/v1beta/chat/completions"
        }
    }

    public var modelName: String {
        switch self {
        case .openAINative: return "gpt-4o"
        case .openAICompatible: return "conformance-model"
        case .openRouter: return "nvidia/llama-3.1-nemotron-70b-instruct"
        case .anthropic: return "claude-3-5-sonnet-20241022"
        case .google: return "gemini-2.0-flash-exp"
        }
    }

    public var supportsReasoning: Bool {
        switch self {
        case .openAINative, .openAICompatible: return false
        case .openRouter, .anthropic, .google: return true
        }
    }
}

public enum ProductionConformanceFixtures {
    public static let secretAPIKey = "CONFORMANCE_SECRET_DO_NOT_LEAK"
    public static let testHost = "conformance.provider"
    public static let endpointURL = "https://\(testHost)/v1/chat/completions"

    public static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: ChatMessages.self,
            APIKeys.self,
            SearchKeys.self,
            AllModels.self,
            ChatRecords.self,
            UserInfo.self,
            PromptRepo.self,
            KnowledgeRecords.self,
            KnowledgeChunk.self,
            MemoryArchive.self,
            TranslationDic.self,
            ToolKeys.self,
            configurations: configuration
        )
    }

    // MARK: - OpenAI-Compatible Fixtures

    public static func sseToolCall(
        id: String,
        name: String,
        arguments: [String: Any],
        finishReason: String = "tool_calls"
    ) -> Data {
        let argumentsData = try! JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
        let argumentsJSON = String(decoding: argumentsData, as: UTF8.self)
        let payload: [String: Any] = [
            "choices": [[
                "delta": [
                    "role": "assistant",
                    "tool_calls": [[
                        "index": 0,
                        "id": id,
                        "type": "function",
                        "function": ["name": name, "arguments": argumentsJSON]
                    ]]
                ],
                "finish_reason": finishReason
            ]]
        ]
        return sseData(payload)
    }

    public static func sseParallelToolCalls(
        calls: [(id: String, name: String, arguments: [String: Any])]
    ) -> Data {
        var toolDeltas: [[String: Any]] = []
        for (idx, call) in calls.enumerated() {
            let argumentsData = try! JSONSerialization.data(withJSONObject: call.arguments, options: [.sortedKeys])
            toolDeltas.append([
                "index": idx,
                "id": call.id,
                "type": "function",
                "function": ["name": call.name, "arguments": String(decoding: argumentsData, as: UTF8.self)]
            ])
        }
        let payload: [String: Any] = [
            "choices": [[
                "delta": [
                    "role": "assistant",
                    "tool_calls": toolDeltas
                ],
                "finish_reason": "tool_calls"
            ]]
        ]
        return sseData(payload)
    }

    public static func sseFinalAnswer(_ text: String) -> Data {
        sseData([
            "choices": [[
                "delta": ["role": "assistant", "content": text],
                "finish_reason": "stop"
            ]]
        ])
    }

    public static func sseFinishOnly(finishReason: String = "other") -> Data {
        sseData([
            "choices": [[
                "delta": [:],
                "finish_reason": finishReason
            ]]
        ])
    }

    public static func sseOpenRouterReasoningAndTool(
        reasoningContent: String,
        reasoningDetails: [[String: Any]],
        callID: String,
        toolName: String,
        arguments: [String: Any]
    ) -> Data {
        let argsData = try! JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
        let argsJSON = String(decoding: argsData, as: UTF8.self)
        let chunks = ProviderResponseFixtures.openAIReasoningAndToolCallChunks(
            reasoningContent: reasoningContent,
            reasoningDetails: reasoningDetails,
            calls: [(id: callID, name: toolName, arguments: argsJSON)],
            id: "or-reason-tool-1"
        )
        return Data(chunks.joined().utf8)
    }

    // MARK: - Anthropic Native Fixtures

    public static func sseAnthropicToolCall(
        id: String,
        name: String,
        arguments: [String: Any],
        thinking: String? = nil,
        signature: String? = nil
    ) -> Data {
        let argsData = try! JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
        let argsJSON = String(decoding: argsData, as: UTF8.self)
        if let thinking, let signature {
            let chunks = ProviderResponseFixtures.anthropicThinkingAndToolUseChunks(
                thinking: thinking,
                signature: signature,
                calls: [(id: id, name: name, arguments: argsJSON)]
            )
            return Data(chunks.joined().utf8)
        } else {
            let chunks = ProviderResponseFixtures.anthropicToolUseChunks(
                calls: [(id: id, name: name, arguments: argsJSON)]
            )
            return Data(chunks.joined().utf8)
        }
    }

    public static func sseAnthropicFinalAnswer(_ text: String) -> Data {
        let chunks = ProviderResponseFixtures.anthropicTextChunks(text: text)
        return Data(chunks.joined().utf8)
    }

    // MARK: - Google Native Fixtures

    public static func sseGoogleFunctionCall(
        name: String,
        arguments: [String: Any],
        thoughtSignature: String? = nil
    ) -> Data {
        let chunks = ProviderResponseFixtures.googleFunctionCallChunks(
            calls: [(name: name, args: arguments, thoughtSignature: thoughtSignature)]
        )
        return Data(chunks.joined().utf8)
    }

    public static func sseGoogleFinalAnswer(_ text: String) -> Data {
        let chunks = ProviderResponseFixtures.googleTextChunks(text: text)
        return Data(chunks.joined().utf8)
    }

    // MARK: - Helpers

    public static func sseData(_ payload: [String: Any]) -> Data {
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let sse = "data: \(String(decoding: data, as: UTF8.self))\n\ndata: [DONE]\n\n"
        return Data(sse.utf8)
    }
}
