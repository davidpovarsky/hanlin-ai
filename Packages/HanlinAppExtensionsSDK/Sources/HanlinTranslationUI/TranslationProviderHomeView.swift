#if canImport(TranslationUIProvider)
import HanlinLocalization
// TranslationProviderHomeView.swift
// ChavrusaChatTranslationProvider

import HanlinPlatformContracts
import HanlinScriptExtensions
import SwiftUI
@preconcurrency import Translation
@preconcurrency import TranslationUIProvider

public struct TranslationProviderHomeView: View {
    @Bindable public var session: TranslationProviderSession

    public init(session: TranslationProviderSession) {
        self.session = session
    }

    public var body: some View {
        Form {
            Section(hanlin: "Selected text") {
                Text(session.sourceText.isEmpty ? String(localized: "No text selected", bundle: HanlinLocalization.bundle) : session.sourceText)
            }

            Section(hanlin: "Translation") {
                if session.translatedText.isEmpty {
                    ContentUnavailableView(hanlin: "Ready to translate", systemImage: "translate")
                } else {
                    Text(session.translatedText)
                        .textSelection(.enabled)
                }
            }

            Section(hanlin: "Ask Hanlin") {
                HStack(spacing: 8) {
                    TextField(hanlin: "Ask about this text...", text: $session.quickQuery)
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
        .navigationTitle(Text("ChavrusaChat", bundle: HanlinLocalization.bundle))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    session.path.append(.apps)
                } label: {
                    Label(hanlin: "Apps", systemImage: "square.grid.2x2")
                }
                .accessibilityLabel(Text("Mini Apps", bundle: HanlinLocalization.bundle))
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(session.context.allowsReplacement ? String(localized: "Replace", bundle: HanlinLocalization.bundle) : String(localized: "Done", bundle: HanlinLocalization.bundle)) {
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

#endif
