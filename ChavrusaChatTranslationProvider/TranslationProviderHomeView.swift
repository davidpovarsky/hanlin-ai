// TranslationProviderHomeView.swift
// ChavrusaChatTranslationProvider

import HanlinPlatformContracts
import HanlinScriptExtensions
import SwiftUI
@preconcurrency import Translation
@preconcurrency import TranslationUIProvider

struct TranslationProviderHomeView: View {
    @Bindable var session: TranslationProviderSession
    @State private var isShowingOriginal: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Original Selected Text Section
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Selected Text", systemImage: "text.quote")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(session.sourceText.count) chars")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Text(session.sourceText)
                        .font(.subheadline)
                        .lineLimit(isShowingOriginal ? nil : 3)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isShowingOriginal.toggle()
                            }
                        }
                }

                // Translation Editor Section
                VStack(alignment: .leading, spacing: 6) {
                    Label("Translation", systemImage: "character.book.closed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if session.translatedText.isEmpty && session.isTranslating {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 6)
                            Text("Translating...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(24)
                    } else {
                        TextEditor(text: $session.translatedText)
                            .font(.body)
                            .frame(minHeight: 120)
                            .padding(8)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.separator), lineWidth: 0.5)
                            )
                    }
                }

                // Agent Quick Composer ("Ask Hanlin")
                VStack(alignment: .leading, spacing: 10) {
                    Label("Ask Hanlin", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField("Ask about this text...", text: $session.quickQuery)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                            .onSubmit {
                                submitQuickQuery()
                            }

                        Button {
                            submitQuickQuery()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundStyle(session.quickQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : Color.accentColor)
                        }
                        .disabled(session.quickQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    // Quick prompt chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            quickChip("Explain this text", prompt: "Please explain the meaning and context of this text in detail.")
                            quickChip("Summarize", prompt: "Please provide a concise summary of this text.")
                            quickChip("Key terms", prompt: "Explain the key terms and concepts in this text.")
                            quickChip("Translate in-depth", prompt: "Provide an in-depth translation with commentary.")
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(16)
        }
        .navigationTitle("Hanlin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    session.path.append(.apps)
                } label: {
                    Label("Apps", systemImage: "square.grid.2x2")
                }
                .accessibilityLabel("Mini Apps")
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(session.context.allowsReplacement ? "Replace" : "Done") {
                    session.finish()
                }
            }
        }
        .translationTask(source: nil, target: nil) { translationSession in
            guard !session.sourceText.isEmpty && session.translatedText.isEmpty else { return }
            session.isTranslating = true
            defer { session.isTranslating = false }
            if let response = try? await translationSession.translate(session.sourceText) {
                session.translatedText = response.targetText
            }
        }
    }

    private func submitQuickQuery() {
        let q = session.quickQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        session.quickQuery = ""
        session.path.append(.chat)
        session.sendChatMessage(q)
    }

    private func quickChip(_ label: String, prompt: String) -> some View {
        Button {
            session.path.append(.chat)
            session.sendChatMessage(prompt)
        } label: {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemBackground), in: Capsule())
                .overlay(Capsule().stroke(Color(.separator), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
