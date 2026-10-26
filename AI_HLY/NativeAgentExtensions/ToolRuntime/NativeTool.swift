//
//  NativeTool.swift
//  AI_HLY
//
//  Swift-only native tool protocol. No JS/TS runtime is used.
//

import Foundation
import SwiftData

@MainActor
protocol NativeTool {
    var name: String { get }
    var catalogEntry: NativeToolCatalogEntry { get }

    /// OpenAI-compatible schema object:
    /// ["type": "function", "function": ["name": ..., "description": ..., "parameters": ...]]
    func openAIToolSchema() -> [String: Any]

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult
}

struct NativeToolExecutionContext {
    var localeIdentifier: String
    var modelContext: ModelContext?
    var toolCallID: String?
    var chatID: String?
    var isTemporaryChat: Bool
    var requestID: String?
    var capabilitySession: AssistantCapabilitySession?
    var attachmentResolver: (@Sendable (String) async throws -> Data)?

    init(
        localeIdentifier: String,
        modelContext: ModelContext? = nil,
        toolCallID: String? = nil,
        chatID: String? = nil,
        isTemporaryChat: Bool = false,
        requestID: String? = nil,
        capabilitySession: AssistantCapabilitySession? = nil,
        attachmentResolver: (@Sendable (String) async throws -> Data)? = nil
    ) {
        self.localeIdentifier = localeIdentifier
        self.modelContext = modelContext
        self.toolCallID = toolCallID
        self.chatID = chatID
        self.isTemporaryChat = isTemporaryChat
        self.requestID = requestID
        self.capabilitySession = capabilitySession
        self.attachmentResolver = attachmentResolver
    }

    var effectiveChatID: String? {
        guard let chatID, !chatID.isEmpty, chatID != "default_chat" else { return nil }
        return chatID
    }

    var effectiveRequestID: String? {
        guard let req = requestID ?? toolCallID, !req.isEmpty, req != "default_request" else { return nil }
        return req
    }

    func resolveAttachment(handle: String) async throws -> Data {
        guard let validChatID = effectiveChatID else {
            throw HanlinHostServiceError.capabilityNotGranted("Access denied: Attachment resolution requires an authentic, non-default chat scope.")
        }
        if let resolver = attachmentResolver {
            return try await resolver(handle)
        }
        return try await AuthorizedAttachmentRegistry.shared.resolve(
            handle: handle,
            chatID: validChatID,
            requestID: effectiveRequestID
        )
    }

    var isHebrew: Bool { localeIdentifier.hasPrefix("he") }
    var isChinese: Bool { localeIdentifier.hasPrefix("zh") }
}

enum NativeToolSchema {
    static func function(name: String, description: String, parameters: [String: Any]) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parameters
            ]
        ]
    }

    static func object(properties: [String: Any], required: [String] = []) -> [String: Any] {
        var schema: [String: Any] = [
            "type": "object",
            "properties": properties,
            "additionalProperties": false
        ]
        if !required.isEmpty {
            schema["required"] = required
        }
        return schema
    }

    static func string(description: String, enumValues: [String]? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "string", "description": description]
        if let enumValues { schema["enum"] = enumValues }
        return schema
    }

    static func boolean(description: String) -> [String: Any] {
        ["type": "boolean", "description": description]
    }

    static func number(description: String, minimum: Int? = nil, maximum: Int? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "number", "description": description]
        if let minimum { schema["minimum"] = minimum }
        if let maximum { schema["maximum"] = maximum }
        return schema
    }

    static func integer(description: String, minimum: Int? = nil, maximum: Int? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "integer", "description": description]
        if let minimum { schema["minimum"] = minimum }
        if let maximum { schema["maximum"] = maximum }
        return schema
    }

    static func stringArray(description: String, maximumItems: Int? = nil) -> [String: Any] {
        var schema: [String: Any] = [
            "type": "array",
            "items": ["type": "string"],
            "description": description
        ]
        if let maximumItems { schema["maxItems"] = maximumItems }
        return schema
    }
}
