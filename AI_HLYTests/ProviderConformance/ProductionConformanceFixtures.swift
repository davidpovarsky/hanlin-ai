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
                "index": 0,
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
                "index": 0,
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
                "index": 0,
                "delta": ["role": "assistant", "content": text],
                "finish_reason": "stop"
            ]]
        ])
    }

    public static func sseFinishOnly(finishReason: String = "other") -> Data {
        sseData([
            "choices": [[
                "index": 0,
                "delta": [:],
                "finish_reason": finishReason
            ]]
        ])
    }

    // MARK: - OpenAI / OpenRouter Fixtures

    public static func openAIReasoningAndToolCallChunks(
        reasoningContent: String? = nil,
        reasoningField: String? = nil,
        reasoningDetails: [Any]? = nil,
        calls: [(id: String, name: String, arguments: String)],
        id: String = "chatcmpl-reason-tool-1"
    ) -> [String] {
        var delta: [String: Any] = ["role": "assistant"]
        if let reasoningContent {
            delta["reasoning_content"] = reasoningContent
        }
        if let reasoningField {
            delta["reasoning"] = reasoningField
        }
        if let reasoningDetails {
            delta["reasoning_details"] = reasoningDetails
        }

        var toolDeltas: [[String: Any]] = []
        for (idx, call) in calls.enumerated() {
            toolDeltas.append([
                "index": idx,
                "id": call.id,
                "type": "function",
                "function": ["name": call.name, "arguments": call.arguments]
            ])
        }
        delta["tool_calls"] = toolDeltas

        let chunkData = try! JSONSerialization.data(withJSONObject: [
            "id": id,
            "choices": [[
                "index": 0,
                "delta": delta,
                "finish_reason": NSNull()
            ]]
        ])
        let chunk = "data: \(String(decoding: chunkData, as: UTF8.self))\n\n"
        let termData = try! JSONSerialization.data(withJSONObject: [
            "id": id,
            "choices": [[
                "index": 0,
                "delta": [:],
                "finish_reason": "tool_calls"
            ]]
        ])
        let term = "data: \(String(decoding: termData, as: UTF8.self))\n\n"
        return [chunk, term, "data: [DONE]\n\n"]
    }

    public static var richOpaqueReasoningDetailsJSON: [[String: Any]] {
        [
            [
                "type": "reasoning.text",
                "text": "opaque-a",
                "signature": "sig-A",
                "provider_blob": [
                    "encrypted": "ENC-AAA",
                    "index": 7,
                    "valid": true,
                    "nullable": NSNull()
                ]
            ],
            [
                "type": "provider.custom",
                "signature": "sig-B",
                "payload": ["x", 3, false, ["nested": "value"]]
            ]
        ]
    }

    public static func areJSONEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        guard let lData = try? JSONSerialization.data(withJSONObject: lhs),
              let rData = try? JSONSerialization.data(withJSONObject: rhs) else {
            return false
        }
        guard let lObj = try? JSONSerialization.jsonObject(with: lData),
              let rObj = try? JSONSerialization.jsonObject(with: rData) else {
            return false
        }
        return areObjectsEqual(lObj, rObj)
    }

    private static func areObjectsEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        if let lDict = lhs as? [String: Any], let rDict = rhs as? [String: Any] {
            guard lDict.count == rDict.count else { return false }
            for (key, lVal) in lDict {
                guard let rVal = rDict[key], areObjectsEqual(lVal, rVal) else { return false }
            }
            return true
        }
        if let lArr = lhs as? [Any], let rArr = rhs as? [Any] {
            guard lArr.count == rArr.count else { return false }
            for i in 0..<lArr.count {
                guard areObjectsEqual(lArr[i], rArr[i]) else { return false }
            }
            return true
        }
        if lhs is NSNull && rhs is NSNull { return true }
        if let lStr = lhs as? String, let rStr = rhs as? String { return lStr == rStr }
        if let lNum = lhs as? NSNumber, let rNum = rhs as? NSNumber {
            if CFGetTypeID(lNum) == CFBooleanGetTypeID() || CFGetTypeID(rNum) == CFBooleanGetTypeID() {
                return (CFGetTypeID(lNum) == CFBooleanGetTypeID()) == (CFGetTypeID(rNum) == CFBooleanGetTypeID()) && lNum.boolValue == rNum.boolValue
            }
            return lNum == rNum
        }
        return false
    }

    public static func sseLateGhostResponse(
        toolCallID: String = "ghost-call-1",
        toolName: String = "p09_ghost_detector_tool"
    ) -> Data {
        let textChunk = sseData([
            "choices": [[
                "index": 0,
                "delta": ["role": "assistant", "content": "LATE_FORBIDDEN_GHOST_TEXT"],
                "finish_reason": NSNull()
            ]]
        ])
        let toolChunk = sseToolCall(id: toolCallID, name: toolName, arguments: [:])
        let finishChunk = sseFinalAnswer("LATE_FORBIDDEN_FINAL_ANSWER")
        var combined = Data()
        combined.append(textChunk)
        combined.append(toolChunk)
        combined.append(finishChunk)
        return combined
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
        let chunks = openAIReasoningAndToolCallChunks(
            reasoningContent: reasoningContent,
            reasoningDetails: reasoningDetails,
            calls: [(id: callID, name: toolName, arguments: argsJSON)],
            id: "or-reason-tool-1"
        )
        return Data(chunks.joined().utf8)
    }

    // MARK: - Anthropic Native Fixtures

    public static func anthropicToolUseChunks(
        calls: [(id: String, name: String, arguments: String)],
        id: String = "msg-anthropic-tool-1",
        stopReason: String = "tool_use"
    ) -> [String] {
        var chunks: [String] = []
        func appendEvent(_ payload: [String: Any]) {
            let json = try! JSONSerialization.data(withJSONObject: payload)
            chunks.append("event: \(payload["type"] as? String ?? "message")\ndata: \(String(decoding: json, as: UTF8.self))\n\n")
        }
        appendEvent([
            "type": "message_start",
            "message": [
                "id": id,
                "type": "message",
                "role": "assistant",
                "model": "claude-3-5-sonnet-20241022",
                "content": [],
                "stop_reason": NSNull()
            ]
        ])
        for (idx, call) in calls.enumerated() {
            appendEvent([
                "type": "content_block_start",
                "index": idx,
                "content_block": [
                    "type": "tool_use",
                    "id": call.id,
                    "name": call.name,
                    "input": [:]
                ]
            ])
            appendEvent([
                "type": "content_block_delta",
                "index": idx,
                "delta": [
                    "type": "input_json_delta",
                    "partial_json": call.arguments
                ]
            ])
            appendEvent([
                "type": "content_block_stop",
                "index": idx
            ])
        }
        appendEvent([
            "type": "message_delta",
            "delta": ["stop_reason": stopReason, "stop_sequence": NSNull()],
            "usage": ["output_tokens": 25]
        ])
        appendEvent(["type": "message_stop"])
        return chunks
    }

    public static func anthropicThinkingAndToolUseChunks(
        thinking: String,
        signature: String,
        calls: [(id: String, name: String, arguments: String)],
        id: String = "msg-anthropic-think-tool-1",
        stopReason: String = "tool_use"
    ) -> [String] {
        var chunks: [String] = []
        func appendEvent(_ payload: [String: Any]) {
            let json = try! JSONSerialization.data(withJSONObject: payload)
            chunks.append("event: \(payload["type"] as? String ?? "message")\ndata: \(String(decoding: json, as: UTF8.self))\n\n")
        }
        appendEvent([
            "type": "message_start",
            "message": [
                "id": id,
                "type": "message",
                "role": "assistant",
                "model": "claude-3-5-sonnet-20241022",
                "content": [],
                "stop_reason": NSNull()
            ]
        ])
        appendEvent([
            "type": "content_block_start",
            "index": 0,
            "content_block": [
                "type": "thinking",
                "thinking": ""
            ]
        ])
        appendEvent([
            "type": "content_block_delta",
            "index": 0,
            "delta": [
                "type": "thinking_delta",
                "thinking": thinking
            ]
        ])
        appendEvent([
            "type": "content_block_delta",
            "index": 0,
            "delta": [
                "type": "signature_delta",
                "signature": signature
            ]
        ])
        appendEvent([
            "type": "content_block_stop",
            "index": 0
        ])
        for (idx, call) in calls.enumerated() {
            let blockIndex = idx + 1
            appendEvent([
                "type": "content_block_start",
                "index": blockIndex,
                "content_block": [
                    "type": "tool_use",
                    "id": call.id,
                    "name": call.name,
                    "input": [:]
                ]
            ])
            appendEvent([
                "type": "content_block_delta",
                "index": blockIndex,
                "delta": [
                    "type": "input_json_delta",
                    "partial_json": call.arguments
                ]
            ])
            appendEvent([
                "type": "content_block_stop",
                "index": blockIndex
            ])
        }
        appendEvent([
            "type": "message_delta",
            "delta": ["stop_reason": stopReason, "stop_sequence": NSNull()],
            "usage": ["output_tokens": 25]
        ])
        appendEvent(["type": "message_stop"])
        return chunks
    }

    public static func anthropicTextChunks(
        text: String,
        id: String = "msg-anthropic-text-1",
        stopReason: String = "end_turn"
    ) -> [String] {
        var chunks: [String] = []
        func appendEvent(_ payload: [String: Any]) {
            let json = try! JSONSerialization.data(withJSONObject: payload)
            chunks.append("event: \(payload["type"] as? String ?? "message")\ndata: \(String(decoding: json, as: UTF8.self))\n\n")
        }
        appendEvent([
            "type": "message_start",
            "message": [
                "id": id,
                "type": "message",
                "role": "assistant",
                "model": "claude-3-5-sonnet-20241022",
                "content": [],
                "stop_reason": NSNull()
            ]
        ])
        appendEvent([
            "type": "content_block_start",
            "index": 0,
            "content_block": ["type": "text", "text": ""]
        ])
        appendEvent([
            "type": "content_block_delta",
            "index": 0,
            "delta": ["type": "text_delta", "text": text]
        ])
        appendEvent([
            "type": "content_block_stop",
            "index": 0
        ])
        appendEvent([
            "type": "message_delta",
            "delta": ["stop_reason": stopReason, "stop_sequence": NSNull()],
            "usage": ["output_tokens": 15]
        ])
        appendEvent(["type": "message_stop"])
        return chunks
    }

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
            let chunks = anthropicThinkingAndToolUseChunks(
                thinking: thinking,
                signature: signature,
                calls: [(id: id, name: name, arguments: argsJSON)]
            )
            return Data(chunks.joined().utf8)
        } else {
            let chunks = anthropicToolUseChunks(
                calls: [(id: id, name: name, arguments: argsJSON)]
            )
            return Data(chunks.joined().utf8)
        }
    }

    public static func sseAnthropicFinalAnswer(_ text: String) -> Data {
        let chunks = anthropicTextChunks(text: text)
        return Data(chunks.joined().utf8)
    }

    // MARK: - Google Native Fixtures

    public static func googleFunctionCallChunks(
        calls: [(name: String, args: [String: Any], thoughtSignature: String?)],
        finishReason: String = "STOP"
    ) -> [String] {
        var parts: [[String: Any]] = []
        for call in calls {
            var part: [String: Any] = [
                "functionCall": [
                    "name": call.name,
                    "args": call.args
                ]
            ]
            if let sig = call.thoughtSignature {
                part["thoughtSignature"] = sig
            }
            parts.append(part)
        }
        let chunkData = try! JSONSerialization.data(withJSONObject: [
            "candidates": [[
                "content": [
                    "role": "model",
                    "parts": parts
                ],
                "finishReason": finishReason
            ]],
            "usageMetadata": [
                "promptTokenCount": 8,
                "candidatesTokenCount": 14
            ]
        ])
        return ["data: \(String(decoding: chunkData, as: UTF8.self))\n\n"]
    }

    public static func googleTextChunks(
        text: String,
        finishReason: String = "STOP"
    ) -> [String] {
        let chunkData = try! JSONSerialization.data(withJSONObject: [
            "candidates": [[
                "content": [
                    "role": "model",
                    "parts": [["text": text]]
                ],
                "finishReason": finishReason
            ]],
            "usageMetadata": [
                "promptTokenCount": 8,
                "candidatesTokenCount": 10
            ]
        ])
        return ["data: \(String(decoding: chunkData, as: UTF8.self))\n\n"]
    }

    public static func sseGoogleFunctionCall(
        name: String,
        arguments: [String: Any],
        thoughtSignature: String? = nil
    ) -> Data {
        let chunks = googleFunctionCallChunks(
            calls: [(name: name, args: arguments, thoughtSignature: thoughtSignature)]
        )
        return Data(chunks.joined().utf8)
    }

    public static func sseGoogleFinalAnswer(_ text: String) -> Data {
        let chunks = googleTextChunks(text: text)
        return Data(chunks.joined().utf8)
    }

    // MARK: - Helpers

    public static func sseData(_ payload: [String: Any]) -> Data {
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let sse = "data: \(String(decoding: data, as: UTF8.self))\n\ndata: [DONE]\n\n"
        return Data(sse.utf8)
    }
}

// MARK: - Conformance Failure Classification & Protocol Error

public enum ConformanceFailureCategory: String, CaseIterable, Sendable, Codable {
    case ROUTING
    case REQUEST_SERIALIZATION
    case TOOL_SCHEMA
    case TOOL_CALL_PARSE
    case TOOL_RESULT_CONTINUATION
    case REASONING_STATE
    case SIGNATURE_STATE
    case STREAM_PARSER
    case FINISH_REASON
    case EMPTY_RESPONSE
    case RETRY
    case TOOL_EXECUTION
    case DYNAMIC_TOOL_EXPOSURE
    case CANCELLATION
    case RUN_OWNERSHIP
    case DIAGNOSTICS
    case DIRECT_CHAT_PATH
    case SDK_DEPENDENCY
    case TEST_HARNESS
    case MODEL_NONCOMPLIANCE
}

public enum FailureOwnership: String, CaseIterable, Sendable, Codable {
    case hanlinAIProduction = "hanlin-ai production"
    case swiftAISDKDependency = "swift-ai-sdk dependency"
    case testHarness = "test harness"
    case providerModelBehavior = "provider/model behavior"
    case unknown = "unknown"
}

public struct ConformanceProtocolError: Error, CustomStringConvertible, Sendable {
    public let category: ConformanceFailureCategory
    public let ownership: FailureOwnership
    public let round: Int
    public let message: String

    public init(
        category: ConformanceFailureCategory = .TEST_HARNESS,
        ownership: FailureOwnership = .testHarness,
        round: Int = 0,
        message: String
    ) {
        self.category = category
        self.ownership = ownership
        self.round = round
        self.message = message
    }

    public var description: String {
        "[\(category.rawValue) / \(ownership.rawValue) / Round \(round)] \(message)"
    }
}

