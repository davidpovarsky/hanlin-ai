#if canImport(TranslationUIProvider)
import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptExtensions
import SwiftUI

/// Editable input and native package results remain inside Apple's translation
/// extension. The original provider context owns expansion and text replacement.
struct TranslationProviderNativePresentationView: View {
    @Bindable var session: TranslationProviderSession
    let app: HanlinScriptTranslationUISnapshot
    @State private var draft: String
    @State private var submitted: String
    @State private var sessionID = UUID()

    init(session: TranslationProviderSession, app: HanlinScriptTranslationUISnapshot) {
        self.session = session
        self.app = app
        _draft = State(initialValue: session.sourceText)
        _submitted = State(initialValue: session.sourceText)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let input = app.nativePresentation?.input {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(input.title).font(.headline)
                        TextField(input.placeholder ?? input.title, text: $draft, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                            .accessibilityIdentifier("hanlin.nativePresentation.query")
                            .onSubmit(submit)
                        Button(input.submitTitle, systemImage: "arrow.clockwise") { submit() }
                            .accessibilityIdentifier("hanlin.nativePresentation.submit")
                    }
                }
                if let store = try? session.services.loadStore() {
                    HanlinNativePresentationContentView(request: request, store: store) { effect in
                        if effect.expandsSheet { session.context.expandSheet() }
                        if effect.finishRequested {
                            session.context.finish(translation: effect.replacementText.map { AttributedString($0) })
                        }
                    }
                    .id(sessionID)
                } else {
                    ContentUnavailableView("MiniApp storage unavailable", systemImage: "externaldrive.badge.exclamationmark")
                }
            }
            .padding()
        }
        .navigationTitle(app.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: session.sourceText) { _, newValue in
            draft = newValue
            submitted = newValue
            sessionID = UUID()
        }
    }

    private var request: HanlinNativePresentationRequest {
        .init(identity: app.identity, kind: .translationUI, sessionID: sessionID,
            inputText: submitted, parameters: .object(["query": .string(submitted)]),
            allowsReplacement: session.context.allowsReplacement)
    }

    private func submit() {
        submitted = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        sessionID = UUID()
        session.context.expandSheet()
    }
}
#endif
