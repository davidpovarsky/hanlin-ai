// TranslationProviderMiniChatView.swift
// ChavrusaChatTranslationProvider

import HanlinChatCore
import HanlinPlatformContracts
import HanlinScriptExtensions
import HanlinScriptUI
import SwiftUI

struct TranslationProviderMiniChatView: View {
    @Bindable var session: TranslationProviderSession
    @State private var inputPrompt: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Chat Messages Scroll
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(session.chatMessages.enumerated()), id: \.offset) { index, msg in
                            HanlinChatMessageBubble(
                                message: msg,
                                isStreaming: session.isChatStreaming && index == session.chatMessages.indices.last,
                                presentationMode: .compact
                            )
                            .id(index)
                        }

                        if let error = session.chatError {
                            HanlinChatErrorBanner(errorMessage: error)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: session.chatMessages.count) {
                    if let lastIndex = session.chatMessages.indices.last {
                        withAnimation {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Composer
            HanlinChatComposer(
                text: $inputPrompt,
                canSend: canSend,
                isStreaming: session.isChatStreaming,
                presentationMode: .compact,
                placeholder: "Ask Hanlin...",
                onSend: send
            )
        }
        .navigationTitle("Ask Hanlin")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var canSend: Bool {
        !inputPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !session.isChatStreaming
    }

    private func send() {
        let q = inputPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !session.isChatStreaming else { return }
        inputPrompt = ""
        session.sendChatMessage(q)
    }
}
