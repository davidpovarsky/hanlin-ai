//
//  NativeTool.swift
//  AI_HLY
//
//  Swift host boundary for native tools and selected MiniApp assistant adapters.
//  Modern MiniApp adapters invoke their original runtime only during execution.
//

import Foundation
import SwiftData
import HanlinPlatformContracts

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
    /// Immutable user settings selected before sending; distinct from model arguments.
    var composerConfiguration: HanlinJSONValue?
    var attachmentResolver: (@Sendable (String) async throws -> Data)?

    init(
        localeIdentifier: String,
        modelContext: ModelContext? = nil,
        toolCallID: String? = nil,
        chatID: String? = nil,
        isTemporaryChat: Bool = false,
        requestID: String? = nil,
        capabilitySession: AssistantCapabilitySession? = nil,
        composerConfiguration: HanlinJSONValue? = nil,
        attachmentResolver: (@Sendable (String) async throws -> Data)? = nil
    ) {
        self.localeIdentifier = localeIdentifier
        self.modelContext = modelContext
        self.toolCallID = toolCallID
        self.chatID = chatID
        self.isTemporaryChat = isTemporaryChat
        self.requestID = requestID
        self.capabilitySession = capabilitySession
        self.composerConfiguration = composerConfiguration
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
