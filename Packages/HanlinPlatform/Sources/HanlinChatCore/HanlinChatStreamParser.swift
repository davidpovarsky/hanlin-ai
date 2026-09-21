// HanlinChatStreamParser.swift
// HanlinChatCore
//
// Authoritative stream parser for multi-provider SSE responses.
// Parses content, reasoning, tool call chunks, audio, and token usage.

import Foundation

public final class HanlinChatStreamParser: @unchecked Sendable {
    private let apiType: String
    private var inThinkTag: Bool = false
    private var buffer: String = ""
    private var anthropicToolBlocks: [Int: (id: String, name: String)] = [:]

    public init(apiType: String? = "OpenAI") {
        self.apiType = (apiType ?? "OpenAI").lowercased()
    }

    /// Parses a single SSE line into an optional HanlinChatStreamEvent.
    public func parse(line: String) -> HanlinChatStreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else {
            return nil
        }

        let payloadText = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payloadText == "[DONE]" {
            return HanlinChatStreamEvent(isDone: true)
        }

        guard let data = payloadText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        switch apiType {
        case "anthropic":
            return parseAnthropic(json: json)
        case "gemini":
            return parseGemini(json: json)
        default:
            return parseOpenAI(json: json)
        }
    }

    /// Parses a multi-line SSE chunk into an array of events.
    public func parse(chunk: String) -> [HanlinChatStreamEvent] {
        var events: [HanlinChatStreamEvent] = []
        let lines = chunk.components(separatedBy: "\n")
        for line in lines {
            if let event = parse(line: line) {
                events.append(event)
            }
        }
        return events
    }

    // MARK: - OpenAI Parser

    private func parseOpenAI(json: [String: Any]) -> HanlinChatStreamEvent {
        var event = HanlinChatStreamEvent()

        if let usage = json["usage"] as? [String: Any] {
            let promptDetails = usage["prompt_tokens_details"] as? [String: Any]
            let completionDetails = usage["completion_tokens_details"] as? [String: Any]
            event.tokenUsage = HanlinChatTokenUsage(
                inputTokens: usage["prompt_tokens"] as? Int,
                outputTokens: usage["completion_tokens"] as? Int,
                reasoningTokens: completionDetails?["reasoning_tokens"] as? Int,
                cachedInputTokens: promptDetails?["cached_tokens"] as? Int,
                totalTokens: usage["total_tokens"] as? Int
            )
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first else {
            return event
        }

        if let finishReason = firstChoice["finish_reason"] as? String {
            event.finishReason = finishReason
            if finishReason == "stop" {
                event.isDone = true
            }
        }

        guard let delta = firstChoice["delta"] as? [String: Any] else {
            return event
        }

        // Dedicated reasoning content
        if let reasoning = delta["reasoning_content"] as? String ?? delta["reasoning"] as? String, !reasoning.isEmpty {
            event.reasoning = reasoning
        }

        // Content (handles potential inline <think>...</think> tags)
        if let rawContent = delta["content"] as? String, !rawContent.isEmpty {
            let processed = processInlineThinking(rawContent)
            if let text = processed.content, !text.isEmpty {
                event.content = text
            }
            if let reason = processed.reasoning, !reason.isEmpty {
                event.reasoning = (event.reasoning ?? "") + reason
            }
        }

        // Tool calls chunk
        if let toolCalls = delta["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
            event.toolCalls = toolCalls
        }

        // Audio delta
        if let audio = delta["audio"] as? [String: Any] {
            event.audioDelta = audio
        }

        return event
    }

    // MARK: - Anthropic Parser

    private func parseAnthropic(json: [String: Any]) -> HanlinChatStreamEvent {
        var event = HanlinChatStreamEvent()
        let type = json["type"] as? String ?? ""

        if type == "message_stop" {
            event.isDone = true
            return event
        }

        if type == "content_block_start",
           let index = json["index"] as? Int,
           let block = json["content_block"] as? [String: Any],
           block["type"] as? String == "tool_use",
           let id = block["id"] as? String,
           let name = block["name"] as? String {
            anthropicToolBlocks[index] = (id, name)
            event.toolCalls = [[
                "index": index,
                "id": id,
                "type": "function",
                "function": ["name": name, "arguments": ""]
            ]]
        } else if type == "content_block_delta",
           let delta = json["delta"] as? [String: Any] {
            let deltaType = delta["type"] as? String
            if deltaType == "text_delta", let text = delta["text"] as? String, !text.isEmpty {
                event.content = text
            } else if deltaType == "thinking_delta", let thinking = delta["thinking"] as? String, !thinking.isEmpty {
                event.reasoning = thinking
            } else if deltaType == "input_json_delta",
                      let index = json["index"] as? Int,
                      let partialJSON = delta["partial_json"] as? String,
                      let tool = anthropicToolBlocks[index] {
                event.toolCalls = [[
                    "index": index,
                    "id": tool.id,
                    "type": "function",
                    "function": ["name": tool.name, "arguments": partialJSON]
                ]]
            } else if let text = delta["text"] as? String, !text.isEmpty {
                event.content = text
            }
        }

        if type == "message_delta",
           let delta = json["delta"] as? [String: Any],
           let stopReason = delta["stop_reason"] as? String {
            event.finishReason = stopReason == "tool_use" ? "tool_calls" : anthropicFinishReason(stopReason)
        }

        if type == "message_start",
           let message = json["message"] as? [String: Any],
           let usage = message["usage"] as? [String: Any] {
            event.tokenUsage = anthropicUsage(usage)
        }

        if let usage = json["usage"] as? [String: Any] {
            event.tokenUsage = anthropicUsage(usage)
        }

        return event
    }

    // MARK: - Gemini Parser

    private func parseGemini(json: [String: Any]) -> HanlinChatStreamEvent {
        var event = HanlinChatStreamEvent()

        if let candidates = json["candidates"] as? [[String: Any]],
           let first = candidates.first {
            if let finishReason = first["finishReason"] as? String {
                event.finishReason = geminiFinishReason(finishReason)
                if finishReason == "STOP" {
                    event.isDone = true
                }
            }

            if let content = first["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]] {
                var visibleText = ""
                var reasoningText = ""
                var toolCalls: [[String: Any]] = []
                for (index, part) in parts.enumerated() {
                    if let text = part["text"] as? String, !text.isEmpty {
                        if part["thought"] as? Bool == true {
                            reasoningText += text
                        } else {
                            visibleText += text
                        }
                    }
                    if let functionCall = part["functionCall"] as? [String: Any],
                       let name = functionCall["name"] as? String {
                        let arguments = functionCall["args"]
                            .flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                        toolCalls.append([
                            "index": index,
                            "id": "gemini-\(index)",
                            "type": "function",
                            "function": ["name": name, "arguments": arguments]
                        ])
                    }
                }
                if !visibleText.isEmpty { event.content = visibleText }
                if !reasoningText.isEmpty { event.reasoning = reasoningText }
                if !toolCalls.isEmpty {
                    event.toolCalls = toolCalls
                    event.finishReason = "tool_calls"
                }
            }
        }

        if let usageMetadata = json["usageMetadata"] as? [String: Any] {
            event.tokenUsage = HanlinChatTokenUsage(
                inputTokens: usageMetadata["promptTokenCount"] as? Int,
                outputTokens: usageMetadata["candidatesTokenCount"] as? Int,
                totalTokens: usageMetadata["totalTokenCount"] as? Int
            )
        }

        return event
    }

    private func anthropicUsage(_ usage: [String: Any]) -> HanlinChatTokenUsage {
        let outputDetails = usage["output_tokens_details"] as? [String: Any]
        return HanlinChatTokenUsage(
            inputTokens: usage["input_tokens"] as? Int,
            outputTokens: usage["output_tokens"] as? Int,
            reasoningTokens: outputDetails?["thinking_tokens"] as? Int,
            cachedInputTokens: usage["cache_read_input_tokens"] as? Int,
            totalTokens: nil
        )
    }

    private func anthropicFinishReason(_ reason: String) -> String {
        switch reason {
        case "end_turn", "stop_sequence": "stop"
        case "max_tokens": "length"
        default: reason
        }
    }

    private func geminiFinishReason(_ reason: String) -> String {
        switch reason {
        case "STOP": "stop"
        case "MAX_TOKENS": "length"
        default: reason.lowercased()
        }
    }

    // MARK: - Helper: Inline <think> tags

    private func processInlineThinking(_ text: String) -> (content: String?, reasoning: String?) {
        var contentResult = ""
        var reasoningResult = ""

        buffer += text

        while !buffer.isEmpty {
            if !inThinkTag {
                if let openRange = buffer.range(of: "<think>") {
                    contentResult += String(buffer[..<openRange.lowerBound])
                    buffer = String(buffer[openRange.upperBound...])
                    inThinkTag = true
                } else {
                    contentResult += buffer
                    buffer = ""
                }
            } else {
                if let closeRange = buffer.range(of: "</think>") {
                    reasoningResult += String(buffer[..<closeRange.lowerBound])
                    buffer = String(buffer[closeRange.upperBound...])
                    inThinkTag = false
                } else {
                    reasoningResult += buffer
                    buffer = ""
                }
            }
        }

        return (
            contentResult.isEmpty ? nil : contentResult,
            reasoningResult.isEmpty ? nil : reasoningResult
        )
    }
}
