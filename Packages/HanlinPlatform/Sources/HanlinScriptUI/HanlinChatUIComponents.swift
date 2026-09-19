// HanlinChatUIComponents.swift
// HanlinScriptUI
//
// Shared, extension-safe SwiftUI chat presentation components.
// Reused across main app and Translation Provider compact chat.

import HanlinChatCore
import SwiftUI

public enum HanlinChatPresentationMode: Sendable {
    case full
    case compact
}

// MARK: - Message Bubble

public struct HanlinChatMessageBubble: View {
    public let message: HanlinChatMessage
    public let isStreaming: Bool
    public let presentationMode: HanlinChatPresentationMode

    public init(
        message: HanlinChatMessage,
        isStreaming: Bool = false,
        presentationMode: HanlinChatPresentationMode = .compact
    ) {
        self.message = message
        self.isStreaming = isStreaming
        self.presentationMode = presentationMode
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: presentationMode == .compact ? 8 : 12) {
            if message.role == "assistant" {
                assistantAvatar
                assistantContent
                Spacer(minLength: presentationMode == .compact ? 32 : 48)
            } else {
                Spacer(minLength: presentationMode == .compact ? 32 : 48)
                userContent
            }
        }
    }

    private var assistantAvatar: some View {
        Image(systemName: "sparkles")
            .font(.caption)
            .foregroundStyle(.white)
            .padding(6)
            .background(Color.accentColor, in: Circle())
    }

    private var assistantContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if message.content.isEmpty && isStreaming {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Thinking...")
                        .font(presentationMode == .compact ? .subheadline : .body)
                        .foregroundStyle(.secondary)
                }
                .padding(presentationMode == .compact ? 12 : 14)
            } else {
                Text(message.content)
                    .font(presentationMode == .compact ? .subheadline : .body)
                    .foregroundStyle(Color.primary)
                    .textSelection(.enabled)
                    .padding(presentationMode == .compact ? 12 : 14)
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var userContent: some View {
        Text(message.content)
            .font(presentationMode == .compact ? .subheadline : .body)
            .foregroundStyle(.white)
            .textSelection(.enabled)
            .padding(presentationMode == .compact ? 12 : 14)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Chat Composer

public struct HanlinChatComposer: View {
    @Binding public var text: String
    public let canSend: Bool
    public let isStreaming: Bool
    public let presentationMode: HanlinChatPresentationMode
    public let placeholder: String
    public let onSend: () -> Void

    @FocusState private var isInputFocused: Bool

    public init(
        text: Binding<String>,
        canSend: Bool,
        isStreaming: Bool = false,
        presentationMode: HanlinChatPresentationMode = .compact,
        placeholder: String = "Ask Hanlin...",
        onSend: @escaping () -> Void
    ) {
        self._text = text
        self.canSend = canSend
        self.isStreaming = isStreaming
        self.presentationMode = presentationMode
        self.placeholder = placeholder
        self.onSend = onSend
    }

    public var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .font(presentationMode == .compact ? .subheadline : .body)
                .padding(10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                .focused($isInputFocused)
                .onSubmit {
                    if canSend && !isStreaming {
                        onSend()
                    }
                }

            Button {
                if canSend && !isStreaming {
                    onSend()
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(canSend && !isStreaming ? Color.accentColor : Color(.systemGray4))
            }
            .disabled(!canSend || isStreaming)
        }
        .padding(.horizontal, presentationMode == .compact ? 12 : 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

// MARK: - Error Banner

public struct HanlinChatErrorBanner: View {
    public let errorMessage: String

    public init(errorMessage: String) {
        self.errorMessage = errorMessage
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
        }
        .padding(8)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
    }
}
