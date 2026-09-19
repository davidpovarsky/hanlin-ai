// TranslationProviderMiniChatView.swift
// ChavrusaChatTranslationProvider

import HanlinPlatformContracts
import HanlinScriptExtensions
import SwiftUI

struct TranslationProviderMiniChatView: View {
    @Bindable var session: TranslationProviderSession
    @State private var inputPrompt: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Chat Messages Scroll
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(session.chatMessages.enumerated()), id: \.offset) { index, msg in
                            chatBubble(msg: msg, index: index)
                        }

                        if let error = session.chatError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(8)
                                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                                .padding(.horizontal, 16)
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
            HStack(spacing: 8) {
                TextField("Ask Hanlin...", text: $inputPrompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                    .focused($isInputFocused)
                    .onSubmit {
                        send()
                    }

                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(canSend ? Color.accentColor : Color(.systemGray4))
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
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

    @ViewBuilder
    private func chatBubble(msg: HanlinCompactChatMessage, index: Int) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if msg.role == "assistant" {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Color.accentColor, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(msg.content.isEmpty && session.isChatStreaming ? "Thinking..." : msg.content)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

                Spacer(minLength: 32)
            } else {
                Spacer(minLength: 32)

                Text(msg.content)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .id(index)
    }
}
