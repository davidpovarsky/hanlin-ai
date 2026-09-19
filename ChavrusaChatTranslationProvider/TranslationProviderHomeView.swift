// TranslationProviderHomeView.swift
// ChavrusaChatTranslationProvider

import HanlinPlatformContracts
import HanlinScriptExtensions
import SwiftUI
@preconcurrency import Translation
@preconcurrency import TranslationUIProvider

struct TranslationProviderHomeView: View {
    @Bindable var session: TranslationProviderSession

    var body: some View {
        Form {
            Section("Selected text") {
                Text(session.sourceText.isEmpty ? "No text selected" : session.sourceText)
            }

            Section("Translation") {
                if session.translatedText.isEmpty {
                    ContentUnavailableView("Ready to translate", systemImage: "translate")
                } else {
                    Text(session.translatedText)
                        .textSelection(.enabled)
                }
            }

            Section("Ask Hanlin") {
                HStack(spacing: 8) {
                    TextField("Ask about this text...", text: $session.quickQuery)
                        .onSubmit {
                            submitQuickQuery()
                        }

                    Button {
                        submitQuickQuery()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(session.quickQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationTitle("ChavrusaChat")
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
                .disabled(session.translatedText.isEmpty)
            }
        }
        .translationTask(source: nil, target: nil) { translationSession in
            guard !session.sourceText.isEmpty else { return }
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
}
