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
            event.tokenUsage = HanlinChatTokenUsage(
                inputTokens: usage["prompt_tokens"] as? Int,
                outputTokens: usage["completion_tokens"] as? Int,
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

        if type == "content_block_delta",
           let delta = json["delta"] as? [String: Any] {
            let deltaType = delta["type"] as? String
            if deltaType == "text_delta", let text = delta["text"] as? String, !text.isEmpty {
                event.content = text
            } else if deltaType == "thinking_delta", let thinking = delta["thinking"] as? String, !thinking.isEmpty {
                event.reasoning = thinking
            } else if let text = delta["text"] as? String, !text.isEmpty {
                event.content = text
            }
        }

        if let usage = json["usage"] as? [String: Any] {
            event.tokenUsage = HanlinChatTokenUsage(
                inputTokens: usage["input_tokens"] as? Int,
                outputTokens: usage["output_tokens"] as? Int,
                totalTokens: nil
            )
        }

        return event
    }

    // MARK: - Gemini Parser

    private func parseGemini(json: [String: Any]) -> HanlinChatStreamEvent {
        var event = HanlinChatStreamEvent()

        if let candidates = json["candidates"] as? [[String: Any]],
           let first = candidates.first {
            if let finishReason = first["finishReason"] as? String {
                event.finishReason = finishReason
                if finishReason == "STOP" {
                    event.isDone = true
                }
            }

            if let content = first["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let firstPart = parts.first,
               let text = firstPart["text"] as? String,
               !text.isEmpty {
                event.content = text
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
