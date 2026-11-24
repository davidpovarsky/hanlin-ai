#if canImport(TranslationUIProvider)
import HanlinLocalization
// TranslationProviderSession.swift
// ChavrusaChatTranslationProvider

import Foundation
import HanlinPlatformContracts
import HanlinScriptExtensions
import Observation
import SwiftUI
@preconcurrency import TranslationUIProvider

@MainActor
@Observable
public final class TranslationProviderSession {
    public let context: any TranslationUIProviderContext
    private var explicitSourceText: String?
    public var path: [TranslationRoute] = []
    public var translatedText: String = ""
    public var isTranslating: Bool = false
    public var quickQuery: String = ""

    // Mini Chat State
    public private(set) var chatMessages: [HanlinCompactChatMessage] = []
    public private(set) var isChatStreaming: Bool = false
    public private(set) var chatError: String? = nil

    public let services: HanlinTranslationHostServices
    private var agentClient: HanlinCompactAgentClient { services.agentClient }

    public var sourceText: String {
        get {
            if let explicit = explicitSourceText, !explicit.isEmpty {
                return explicit
            }
            let live = context.inputText.map { String($0.characters) } ?? ""
            if !live.isEmpty {
                return live
            }
            return ""
        }
        set {
            explicitSourceText = newValue
        }
    }

    public func updateSourceTextIfNeeded(_ text: String) {
        guard !text.isEmpty else { return }
        if explicitSourceText != text {
            explicitSourceText = text
        }
    }

    public init(context: any TranslationUIProviderContext, services: HanlinTranslationHostServices) {
        self.context = context
        self.services = services
        let initial = context.inputText.map { String($0.characters) } ?? ""
        if !initial.isEmpty {
            self.explicitSourceText = initial
        }
    }

    public var sessionContext: HanlinTranslationSessionContext {
        .init(
            sourceText: sourceText,
            origin: .translationUI,
            presentation: "modal"
        )
    }

    public func finish(with text: String? = nil) {
        let textToUse = text ?? translatedText
        let finalAttributed = textToUse.isEmpty ? nil : AttributedString(textToUse)
        context.finish(translation: finalAttributed)
    }

    public func sendChatMessage(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isChatStreaming else { return }

        let userMsg = HanlinCompactChatMessage(role: "user", content: trimmed)
        chatMessages.append(userMsg)

        let assistantIndex = chatMessages.count
        chatMessages.append(HanlinCompactChatMessage(role: "assistant", content: ""))
        isChatStreaming = true
        chatError = nil

        let messagesToSend = Array(chatMessages[..<assistantIndex])
        let contextText = sourceText

        Task {
            do {
                let stream = try await agentClient.stream(messages: messagesToSend, systemContext: contextText)
                for try await delta in stream {
                    chatMessages[assistantIndex].content += delta
                }
            } catch {
                chatError = error.localizedDescription
                if chatMessages[assistantIndex].content.isEmpty {
                    chatMessages[assistantIndex].content = "Unable to complete request: \(error.localizedDescription)"
                }
            }
            isChatStreaming = false
        }
    }
}

#endif
