// HanlinChatStreamEvent.swift
// HanlinChatCore
//
// Structured streaming events yielded by the shared Hanlin chat engine.

import Foundation

public struct HanlinChatResponseMetadata: Hashable, Sendable {
    public let statusCode: Int
    public let providerRequestID: String?

    public init(statusCode: Int, providerRequestID: String? = nil) {
        self.statusCode = statusCode
        self.providerRequestID = providerRequestID
    }
}

public struct HanlinChatStreamEvent: @unchecked Sendable {
    public var content: String?
    public var reasoning: String?
    public var toolCalls: [[String: Any]]?
    public var audioDelta: [String: Any]?
    public var tokenUsage: HanlinChatTokenUsage?
    public var finishReason: String?
    public var isDone: Bool
    public var responseMetadata: HanlinChatResponseMetadata?

    public init(
        content: String? = nil,
        reasoning: String? = nil,
        toolCalls: [[String: Any]]? = nil,
        audioDelta: [String: Any]? = nil,
        tokenUsage: HanlinChatTokenUsage? = nil,
        finishReason: String? = nil,
        isDone: Bool = false,
        responseMetadata: HanlinChatResponseMetadata? = nil
    ) {
        self.content = content
        self.reasoning = reasoning
        self.toolCalls = toolCalls
        self.audioDelta = audioDelta
        self.tokenUsage = tokenUsage
        self.finishReason = finishReason
        self.isDone = isDone
        self.responseMetadata = responseMetadata
    }
}
