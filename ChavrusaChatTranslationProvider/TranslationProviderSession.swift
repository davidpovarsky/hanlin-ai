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
final class TranslationProviderSession {
    let context: any TranslationUIProviderContext
    let sourceText: String
    var path: [TranslationRoute] = []
    var translatedText: String = ""
    var isTranslating: Bool = false
    var quickQuery: String = ""

    // Mini Chat State
    var chatMessages: [HanlinCompactChatMessage] = []
    var isChatStreaming: Bool = false
    var chatError: String? = nil

    private let agentClient = HanlinCompactAgentClient()

    init(context: any TranslationUIProviderContext) {
        self.context = context
        self.sourceText = context.inputText.map { String($0.characters) } ?? ""
    }

    var sessionContext: HanlinTranslationSessionContext {
        .init(
            sourceText: sourceText,
            origin: "system.translation",
            presentation: "modal"
        )
    }

    func finish(with text: String? = nil) {
        let textToUse = text ?? translatedText
        let finalAttributed = textToUse.isEmpty ? nil : AttributedString(textToUse)
        context.finish(translation: finalAttributed)
    }

    func sendChatMessage(_ prompt: String) {
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
