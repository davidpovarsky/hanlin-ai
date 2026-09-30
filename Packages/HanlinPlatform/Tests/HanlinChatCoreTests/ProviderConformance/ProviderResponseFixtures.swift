import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AISDKProvider
import AISDKProviderUtils

public enum ProviderResponseFixtures {

    // MARK: - OpenAI / OpenAI-Compatible Fixtures

    public static func openAIChatTextChunks(
        text: String,
        id: String = "chatcmpl-text-1",
        model: String = "gpt-4o",
        finishReason: String? = "stop"
    ) -> [String] {
        let first = sseOpenAI([
            "id": id,
            "model": model,
            "choices": [[
                "index": 0,
                "delta": ["role": "assistant", "content": text],
                "finish_reason": NSNull()
            ]]
        ])
        let terminal = sseOpenAI([
            "id": id,
            "model": model,
            "choices": [[
                "index": 0,
                "delta": [:],
                "finish_reason": finishReason as Any
            ]]
        ])
        return [first, terminal, "data: [DONE]\n\n"]
    }

    public static func openAIChatToolCallChunks(
        calls: [(id: String, name: String, arguments: String)],
        id: String = "chatcmpl-tool-1",
        model: String = "gpt-4o",
        finishReason: String = "tool_calls"
    ) -> [String] {
        var toolDeltas: [[String: Any]] = []
        for (idx, call) in calls.enumerated() {
            toolDeltas.append([
                "index": idx,
                "id": call.id,
                "type": "function",
                "function": [
                    "name": call.name,
                    "arguments": call.arguments
                ]
            ])
        }

        let first = sseOpenAI([
            "id": id,
            "model": model,
            "choices": [[
                "index": 0,
                "delta": [
                    "role": "assistant",
                    "tool_calls": toolDeltas
                ],
                "finish_reason": NSNull()
            ]]
        ])
        let terminal = sseOpenAI([
            "id": id,
            "model": model,
            "choices": [[
                "index": 0,
                "delta": [:],
                "finish_reason": finishReason
            ]]
        ])
        return [first, terminal, "data: [DONE]\n\n"]
    }

    public static let richOpaqueReasoningDetailsJSONValue: JSONValue = .array([
        .object([
            "type": .string("reasoning.text"),
            "text": .string("opaque-a"),
            "signature": .string("sig-A"),
            "provider_blob": .object([
                "encrypted": .string("ENC-AAA"),
                "index": .number(7),
                "valid": .bool(true),
                "nullable": .null
            ])
        ]),
        .object([
            "type": .string("provider.custom"),
            "signature": .string("sig-B"),
            "payload": .array([
                .string("x"),
                .number(3),
                .bool(false),
                .object(["nested": .string("value")])
            ])
        ])
    ])

    public static var richOpaqueReasoningDetailsObject: [Any] {
        let data = try! JSONEncoder().encode(richOpaqueReasoningDetailsJSONValue)
        return try! JSONSerialization.jsonObject(with: data) as! [Any]
    }

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

        let chunk = sseOpenAI([
            "id": id,
            "choices": [[
                "index": 0,
                "delta": delta,
                "finish_reason": NSNull()
            ]]
        ])
        let term = sseOpenAI([
            "id": id,
            "choices": [[
                "index": 0,
                "delta": [:],
                "finish_reason": "tool_calls"
            ]]
        ])
        return [chunk, term, "data: [DONE]\n\n"]
    }

    public static func openAIFinishOnlyChunks(
        finishReason: String? = "other",
        id: String = "chatcmpl-finish-only"
    ) -> [String] {
        let chunk = sseOpenAI([
            "id": id,
            "choices": [[
                "index": 0,
                "delta": [:],
                "finish_reason": finishReason as Any
            ]]
        ])
        return [chunk, "data: [DONE]\n\n"]
    }

    public static func openAIUsageOnlyChunk(
        promptTokens: Int = 10,
        completionTokens: Int = 20,
        id: String = "chatcmpl-usage-only"
    ) -> String {
        sseOpenAI([
            "id": id,
            "choices": [],
            "usage": [
                "prompt_tokens": promptTokens,
                "completion_tokens": completionTokens,
                "total_tokens": promptTokens + completionTokens
            ]
        ])
    }

    // MARK: - Anthropic Native Fixtures

    public static func anthropicTextChunks(
        text: String,
        id: String = "msg-anthropic-text-1",
        stopReason: String = "end_turn"
    ) -> [String] {
        let start = sseAnthropic([
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
        let blockStart = sseAnthropic([
            "type": "content_block_start",
            "index": 0,
            "content_block": ["type": "text", "text": ""]
        ])
        let delta = sseAnthropic([
            "type": "content_block_delta",
            "index": 0,
            "delta": ["type": "text_delta", "text": text]
        ])
        let blockStop = sseAnthropic([
            "type": "content_block_stop",
            "index": 0
        ])
        let msgDelta = sseAnthropic([
            "type": "message_delta",
            "delta": ["stop_reason": stopReason, "stop_sequence": NSNull()],
            "usage": ["output_tokens": 15]
        ])
        let msgStop = sseAnthropic(["type": "message_stop"])
        return [start, blockStart, delta, blockStop, msgDelta, msgStop]
    }

    public static func anthropicToolUseChunks(
        calls: [(id: String, name: String, arguments: String)],
        id: String = "msg-anthropic-tool-1",
        stopReason: String = "tool_use"
    ) -> [String] {
        var chunks: [String] = []
        chunks.append(sseAnthropic([
            "type": "message_start",
            "message": [
                "id": id,
                "type": "message",
                "role": "assistant",
                "model": "claude-3-5-sonnet-20241022",
                "content": [],
                "stop_reason": NSNull()
            ]
        ]))

        for (idx, call) in calls.enumerated() {
            chunks.append(sseAnthropic([
                "type": "content_block_start",
                "index": idx,
                "content_block": [
                    "type": "tool_use",
                    "id": call.id,
                    "name": call.name,
                    "input": [:]
                ]
            ]))
            chunks.append(sseAnthropic([
                "type": "content_block_delta",
                "index": idx,
                "delta": [
                    "type": "input_json_delta",
                    "partial_json": call.arguments
                ]
            ]))
            chunks.append(sseAnthropic([
                "type": "content_block_stop",
                "index": idx
            ]))
        }

        chunks.append(sseAnthropic([
            "type": "message_delta",
            "delta": ["stop_reason": stopReason, "stop_sequence": NSNull()],
            "usage": ["output_tokens": 25]
        ]))
        chunks.append(sseAnthropic(["type": "message_stop"]))
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
        chunks.append(sseAnthropic([
            "type": "message_start",
            "message": [
                "id": id,
                "type": "message",
                "role": "assistant",
                "model": "claude-3-5-sonnet-20241022",
                "content": [],
                "stop_reason": NSNull()
            ]
        ]))

        // Block 0: thinking block
        chunks.append(sseAnthropic([
            "type": "content_block_start",
            "index": 0,
            "content_block": [
                "type": "thinking",
                "thinking": ""
            ]
        ]))
        chunks.append(sseAnthropic([
            "type": "content_block_delta",
            "index": 0,
            "delta": [
                "type": "thinking_delta",
                "thinking": thinking
            ]
        ]))
        chunks.append(sseAnthropic([
            "type": "content_block_delta",
            "index": 0,
            "delta": [
                "type": "signature_delta",
                "signature": signature
            ]
        ]))
        chunks.append(sseAnthropic([
            "type": "content_block_stop",
            "index": 0
        ]))

        // Subsequent blocks: tool_use
        for (idx, call) in calls.enumerated() {
            let blockIndex = idx + 1
            chunks.append(sseAnthropic([
                "type": "content_block_start",
                "index": blockIndex,
                "content_block": [
                    "type": "tool_use",
                    "id": call.id,
                    "name": call.name,
                    "input": [:]
                ]
            ]))
            chunks.append(sseAnthropic([
                "type": "content_block_delta",
                "index": blockIndex,
                "delta": [
                    "type": "input_json_delta",
                    "partial_json": call.arguments
                ]
            ]))
            chunks.append(sseAnthropic([
                "type": "content_block_stop",
                "index": blockIndex
            ]))
        }

        chunks.append(sseAnthropic([
            "type": "message_delta",
            "delta": ["stop_reason": stopReason, "stop_sequence": NSNull()],
            "usage": ["output_tokens": 30]
        ]))
        chunks.append(sseAnthropic(["type": "message_stop"]))
        return chunks
    }

    // MARK: - Google Native Fixtures

    public static func googleTextChunks(
        text: String,
        finishReason: String = "STOP"
    ) -> [String] {
        let chunk1 = sseGoogle([
            "candidates": [[
                "content": [
                    "role": "model",
                    "parts": [["text": text]]
                ],
                "finishReason": finishReason
            ]],
            "usageMetadata": [
                "promptTokenCount": 5,
                "candidatesTokenCount": 10
            ]
        ])
        return [chunk1]
    }

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

        let chunk = sseGoogle([
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
        return [chunk]
    }

    // MARK: - Stream Chunk Boundary Transformers

    public static func oneByteDataChunks(from sseChunks: [String]) -> [Data] {
        let fullData = Data(sseChunks.joined().utf8)
        var result: [Data] = []
        for byte in fullData {
            result.append(Data([byte]))
        }
        return result
    }

    public static func fragmentedToolCallSSEChunks(
        id: String,
        name: String,
        argumentsJSON: String,
        splitIndices: [Int]
    ) -> [String] {
        var chunks: [String] = []
        chunks.append("data: {\"id\":\"\(id)\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"tool_calls\":[{\"index\":0,\"id\":\"\(id)\",\"type\":\"function\",\"function\":{\"name\":\"\(name)\",\"arguments\":\"\"}}]},\"finish_reason\":null}]}\n\n")

        var last = argumentsJSON.startIndex
        for splitIndex in splitIndices {
            let offset = min(splitIndex, argumentsJSON.count)
            let curr = argumentsJSON.index(argumentsJSON.startIndex, offsetBy: offset)
            if curr > last {
                let piece = String(argumentsJSON[last..<curr])
                let escaped = piece.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                chunks.append("data: {\"id\":\"\(id)\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\(escaped)\"}}]},\"finish_reason\":null}]}\n\n")
                last = curr
            }
        }
        if last < argumentsJSON.endIndex {
            let piece = String(argumentsJSON[last..<argumentsJSON.endIndex])
            let escaped = piece.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            chunks.append("data: {\"id\":\"\(id)\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\(escaped)\"}}]},\"finish_reason\":null}]}\n\n")
        }

        chunks.append("data: {\"id\":\"\(id)\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n")
        chunks.append("data: [DONE]\n\n")
        return chunks
    }

    // MARK: - SSE Serialization Helpers

    private static func sseOpenAI(_ payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return "data: \(String(decoding: data, as: UTF8.self))\n\n"
    }

    private static func sseAnthropic(_ payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let eventType = payload["type"] as? String ?? "message"
        return "event: \(eventType)\ndata: \(String(decoding: data, as: UTF8.self))\n\n"
    }

    private static func sseGoogle(_ payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return "data: \(String(decoding: data, as: UTF8.self))\n\n"
    }
}
